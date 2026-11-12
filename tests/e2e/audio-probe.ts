// Sonda de audio: ¿sale sonido de verdad del juego en el navegador?
// No se fía de que el juego diga «reproduje X»: engancha todo lo que el motor conecta a la salida
// de audio del navegador, mide su nivel y lo graba. La grabación se guarda para poder escucharla.
//
//   npx tsx e2e/audio-probe.ts [carpeta de salida]
//   E2E_BASE_URL=https://… E2E_INVITES=ALUX-… npx tsx e2e/audio-probe.ts      contra un despliegue
//
// Etapas: (1) al cargar, sin tocar nada (así llega quien entra con el autoplay bloqueado);
// (2) tras el primer clic y Enter: ambiente y música; (3) al usar una habilidad.
// Requiere ALUX corriendo (node scripts/dev.mjs --prod) salvo contra un despliegue.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';
import { BASE, login, sleep, state, waitFor } from './lib.ts';

const OUT = path.resolve(process.argv[2] || path.resolve(import.meta.dirname, 'screenshots/audio'));
fs.mkdirSync(OUT, { recursive: true });
const ok = (msg: string) => console.log(`✓ ${msg}`);
const info = (msg: string) => console.log(`  ${msg}`);
const dB = (v: number) => (v > 0 ? `${(20 * Math.log10(v)).toFixed(1)} dBFS` : 'silencio absoluto');

// Chromium tal cual, con su política de autoplay normal (un gesto para sonar), y con el audio
// encendido: Playwright lo silencia por defecto y entonces no habría nada que medir.
const browser = await chromium.launch({
  args: [
    ...(process.env.E2E_GPU === '1' ? [] : ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader']),
    '--ignore-gpu-blocklist', '--disable-renderer-backgrounding', '--disable-backgrounding-occluded-windows', '--disable-background-timer-throttling',
  ],
  ignoreDefaultArgs: ['--mute-audio'],
  headless: process.env.E2E_HEADED !== '1',
});
const ctx = await browser.newContext({ viewport: { width: 960, height: 540 } });
const page = await ctx.newPage();
const errors: string[] = [];
page.on('console', (m) => { if (m.type() === 'error' || /audio|sample|AudioContext/i.test(m.text())) errors.push(`[${m.type()}] ${m.text().slice(0, 240)}`); });
page.on('pageerror', (e) => errors.push(`[pageerror] ${String(e).slice(0, 240)}`));

// Antes de que cargue nada: todo lo que se conecte a la salida de audio pasa también por un
// analizador y una grabadora propios.
await page.addInitScript(() => {
  const w = window as any;
  w.__probe = { ctx: null, analyser: null, chunks: [] as Blob[], recorder: null, connects: 0, contexts: 0, marks: [] as any[] };
  const connect = AudioNode.prototype.connect;
  // Grafo completo: cada nodo que se conecta queda numerado para poder seguir el camino de un
  // sonido hasta la salida y ver en qué ganancia se queda.
  const ids = new Map<any, number>();
  const nodes: any[] = [];
  const edges: [number, number][] = [];
  // (como propiedad y no como constante: el transpilador envuelve las funciones con nombre en un
  // auxiliar que no existe dentro de la página)
  w.__idOf = function (n: any) {
    if (!ids.has(n)) { ids.set(n, nodes.length); nodes.push(n); }
    return ids.get(n)!;
  };
  const starts: any[] = [];
  const start = AudioBufferSourceNode.prototype.start;
  AudioBufferSourceNode.prototype.start = function (this: AudioBufferSourceNode, ...rest: any[]) {
    try {
      let peak = 0;
      const b = this.buffer;
      if (b) { const d = b.getChannelData(0); for (let i = 0; i < d.length; i += 7) { const v = Math.abs(d[i]); if (v > peak) peak = v; } }
      starts.push({ id: w.__idOf(this), t: Math.round(performance.now()), dur: b ? +b.duration.toFixed(2) : 0, peak: +peak.toFixed(3), loop: this.loop, rate: this.playbackRate.value });
    } catch (e) { starts.push({ error: String(e) }); }
    return (start as any).apply(this, rest);
  } as any;
  const disconnect = AudioNode.prototype.disconnect;
  const cuts: any[] = [];
  AudioNode.prototype.disconnect = function (this: AudioNode, ...rest: any[]) {
    try { cuts.push([w.__idOf(this), rest[0] && typeof rest[0] === 'object' ? w.__idOf(rest[0]) : -1]); } catch { /* nada */ }
    return (disconnect as any).apply(this, rest);
  } as any;
  w.__probeGraph = () => ({
    nodes: nodes.map((n, i) => ({ id: i, type: n.constructor.name, gain: n.gain ? +n.gain.value.toFixed(4) : undefined, pan: n.pan ? n.pan.value : undefined, ch: n.channelCount, inputs: n.numberOfInputs, outputs: n.numberOfOutputs })),
    edges, cuts, starts,
  });
  AudioNode.prototype.connect = function (this: AudioNode, dest: any, ...rest: any[]) {
    const out = (connect as any).call(this, dest, ...rest);
    try { if (dest instanceof AudioNode && dest !== w.__probe.analyser && dest !== w.__probe.tapOut) edges.push([w.__idOf(this), w.__idOf(dest), rest[0] ?? 0, rest[1] ?? 0] as any); } catch { /* nada */ }
    try {
      if (dest instanceof AudioDestinationNode) {
        const p = w.__probe;
        p.connects++;
        if (p.ctx !== dest.context) {
          p.ctx = dest.context;
          p.contexts++;
          p.analyser = dest.context.createAnalyser();
          p.analyser.fftSize = 2048;
          const stream = (dest.context as AudioContext).createMediaStreamDestination();
          p.tapOut = stream;
          try {
            p.recorder = new MediaRecorder(stream.stream, { mimeType: 'audio/webm;codecs=opus', audioBitsPerSecond: 128000 });
            p.recorder.ondataavailable = (ev: BlobEvent) => { if (ev.data.size) p.chunks.push(ev.data); };
            p.recorder.start(500);
          } catch (e) { p.recorderError = String(e); }
        }
        (connect as any).call(this, p.analyser);
        (connect as any).call(this, p.tapOut);
      }
    } catch (e) { w.__probe.error = String(e); }
    return out;
  } as any;
  // Nivel de lo que está saliendo ahora mismo (RMS y pico de la ventana del analizador)
  w.__probeLevel = () => {
    const p = w.__probe;
    if (!p.analyser) return { rms: 0, peak: 0, state: p.ctx ? p.ctx.state : 'sin contexto', connects: p.connects };
    const buf = new Float32Array(p.analyser.fftSize);
    p.analyser.getFloatTimeDomainData(buf);
    let sum = 0, peak = 0;
    for (const v of buf) { sum += v * v; if (Math.abs(v) > peak) peak = Math.abs(v); }
    return { rms: Math.sqrt(sum / buf.length), peak, state: p.ctx.state, connects: p.connects, rate: p.ctx.sampleRate };
  };
  w.__probeStop = () => new Promise<string>((resolve) => {
    const p = w.__probe;
    if (!p.recorder || p.recorder.state === 'inactive') return resolve('');
    p.recorder.onstop = async () => {
      const blob = new Blob(p.chunks, { type: 'audio/webm' });
      const bytes = new Uint8Array(await blob.arrayBuffer());
      let bin = '';
      for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
      resolve(btoa(bin));
    };
    p.recorder.stop();
  });
});

/** Mide durante `ms` y devuelve el RMS medio, el máximo y el pico. */
async function listen(ms: number) {
  let n = 0, sum = 0, max = 0, peak = 0, st = '';
  const end = Date.now() + ms;
  while (Date.now() < end) {
    const l: any = await page.evaluate(() => (window as any).__probeLevel());
    n++; sum += l.rms; max = Math.max(max, l.rms); peak = Math.max(peak, l.peak); st = l.state;
    await sleep(100);
  }
  return { rms: sum / Math.max(n, 1), max, peak, state: st };
}
const audioState = () => page.evaluate(() => {
  const w = window as any;
  return {
    ctx: w.ALUX_AUDIO ? w.ALUX_AUDIO.state : 'sin contexto',
    rate: w.ALUX_AUDIO ? w.ALUX_AUDIO.sampleRate : 0,
    probe: w.__probeLevel(),
    activation: (navigator as any).userActivation ? { active: (navigator as any).userActivation.isActive, been: (navigator as any).userActivation.hasBeenActive } : null,
  };
});

await login(page, 'Oido');
await page.evaluate(() => { try { localStorage.setItem('alux_seen_llamado', '1'); localStorage.removeItem('alux_settings'); } catch { /* nada */ } });
await page.click('text=Crear sala privada');
const code = (await page.textContent('.room-code'))!.trim();
// Se llega como llega un jugador: navegando, sin gesto en la página del juego
await page.goto(`${BASE}/game/index.html?room=${code}&debug=1&q=min&fs=0`);
await waitFor('el juego conecta', async () => (await state(page))?.net === 'PLAYING', 300_000);
await sleep(1500);

// 1) Sin tocar nada
let a: any = await audioState();
const quiet = await listen(4000);
let s: any = await state(page);
info(`al cargar, sin gesto: AudioContext «${a.ctx}» a ${a.rate} Hz · conexiones a la salida: ${a.probe.connects} · nivel ${dB(quiet.rms)} (pico ${dB(quiet.peak)})`);
info(`  el juego dice: música «${s.music}», sonidos cargados ${s.audio.length} (${s.audio.slice(0, 6).join(', ')}…), ajustes ${JSON.stringify(s.settings)}`);

// 2) Primer gesto: clic en el juego y Enter (cierra la bienvenida)
await page.mouse.click(480, 300);
await sleep(300);
await page.keyboard.press('Enter');
await waitFor('bienvenida cerrada', async () => (await state(page) as any)?.ui?.intro === false, 30_000).catch(() => {});
await sleep(2500);
a = await audioState();
const ambient = await listen(6000);
s = await state(page);
info(`tras el primer clic: AudioContext «${a.ctx}» · conexiones: ${a.probe.connects} · nivel medio ${dB(ambient.rms)} (máx. ${dB(ambient.max)}, pico ${dB(ambient.peak)})`);
info(`  el juego dice: música «${s.music}», sonidos cargados ${s.audio.length}`);

// 3) Una habilidad: chispas de jade (J) durante tres segundos
await page.keyboard.down('KeyJ');
const skill = await listen(3000);
await page.keyboard.up('KeyJ');
info(`usando la chispa de jade: nivel medio ${dB(skill.rms)} (máx. ${dB(skill.max)}, pico ${dB(skill.peak)})`);
s = await state(page);
info(`  sonidos cargados ahora: ${s.audio.join(', ')}`);

// Grafo de Web Audio tal como quedó: por dónde va cada sonido y con qué ganancia
const graph: any = await page.evaluate(() => (window as any).__probeGraph());
fs.writeFileSync(path.join(OUT, 'grafo.json'), JSON.stringify(graph, null, 1));
info(`grafo: ${graph.nodes.length} nodos, ${graph.edges.length} conexiones, ${graph.cuts.length} desconexiones, ${graph.starts.length} sonidos arrancados`);

// Grabación de lo que salió
const b64: string = await page.evaluate(() => (window as any).__probeStop());
const file = path.join(OUT, 'salida.webm');
if (b64) fs.writeFileSync(file, Buffer.from(b64, 'base64'));
info(b64 ? `grabación de la salida: ${file} (${(Buffer.from(b64, 'base64').length / 1024).toFixed(0)} KB)` : 'sin grabación (no hubo nada conectado a la salida)');
if (errors.length) console.log('Consola del navegador:\n  ' + errors.slice(0, 14).join('\n  '));

// Veredicto: −60 dBFS de media es el umbral por debajo del cual, en la práctica, no se oye nada
const AUDIBLE = 0.001;
const report = {
  alCargar: { contexto: a.ctx, nivel: quiet.rms },
  trasElGesto: { contexto: a.ctx, nivel: ambient.rms, maximo: ambient.max },
  habilidad: { nivel: skill.rms, maximo: skill.max },
};
fs.writeFileSync(path.join(OUT, 'informe.json'), JSON.stringify(report, null, 2));
await browser.close();
if (process.env.AUDIO_PROBE_REPORT_ONLY === '1') process.exit(0);
assert.equal(a.ctx, 'running', 'tras el primer gesto el AudioContext debe estar en marcha');
assert.ok(ambient.rms > AUDIBLE, `tras el primer gesto tiene que sonar el ambiente (nivel ${dB(ambient.rms)})`);
assert.ok(skill.max > ambient.rms * 1.2 || skill.max > 0.02, `la habilidad tiene que oírse por encima del ambiente (máx. ${dB(skill.max)} frente a ${dB(ambient.rms)})`);
ok(`Sale sonido real del juego: ambiente ${dB(ambient.rms)}, habilidad hasta ${dB(skill.max)}`);
process.exit(0);
