// Prueba de audio: ¿sale sonido de verdad del juego en el navegador?
// No se fía de que el juego diga «reproduje X»: engancha lo que llega a la salida de audio del
// navegador, mide su nivel y lo graba. Las grabaciones se guardan para poder escucharlas.
//
//   npx tsx e2e/audio-probe.ts [escenarios…] [--out carpeta]
//   E2E_BASE_URL=https://… E2E_INVITES=ALUX-… npx tsx e2e/audio-probe.ts      contra un despliegue
//   AUDIO_PROBE_REPORT_ONLY=1 …                                              sólo informa, no exige nada
//
// Escenarios (todos si no se indica ninguno):
//   normal      al entrar suena el ambiente y la música; una habilidad se oye por encima; el botón
//               «Probar sonido» mide señal; con el volumen general a cero no sale nada y se avisa;
//               con la pestaña oculta se calla y al volver suena otra vez
//   bloqueado   el navegador exige un gesto en la página (política simulada, ver BLOCK_AUDIO):
//               aviso en pantalla, silencio hasta el primer clic y sonido después
//   cine        la introducción suena con su banda sonora y, al omitirla, se funde enseguida
// Requiere ALUX corriendo (node scripts/dev.mjs --prod) salvo contra un despliegue.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { chromium, type Page } from 'playwright';
import { BASE, login, sleep, state, waitFor } from './lib.ts';

const args = process.argv.slice(2);
const outAt = args.indexOf('--out');
const OUT = path.resolve(outAt >= 0 ? args[outAt + 1] : path.resolve(import.meta.dirname, 'screenshots/audio'));
const wanted = args.filter((a, i) => !a.startsWith('--') && (outAt < 0 || i !== outAt + 1));
const SCENARIOS = wanted.length ? wanted : ['normal', 'bloqueado', 'cine'];
const REPORT_ONLY = process.env.AUDIO_PROBE_REPORT_ONLY === '1';
fs.mkdirSync(OUT, { recursive: true });
const ok = (msg: string) => console.log(`✓ ${msg}`);
const info = (msg: string) => console.log(`  ${msg}`);
const dB = (v: number) => (v > 0 ? `${(20 * Math.log10(v)).toFixed(1)} dBFS` : 'silencio absoluto');
/** −60 dBFS de media: por debajo, en la práctica, no se oye nada. */
const AUDIBLE = 0.001;
/** Lo que queda al silenciar: se admite el ruido de cuantización de los fundidos, nada más. */
const SILENT = 0.0002;
const check = (cond: unknown, msg: string) => {
  if (cond) return;
  if (REPORT_ONLY) console.log(`  ✗ (no exigido) ${msg}`); else assert.fail(msg);
};

// Antes de que cargue nada: todo lo que se conecte a la salida de audio pasa también por un
// analizador y una grabadora propios, y se anota el grafo de Web Audio completo.
function probeScript() {
  const w = window as any;
  w.__probe = { ctx: null, analyser: null, chunks: [] as Blob[], recorder: null, connects: 0 };
  const connect = AudioNode.prototype.connect;
  const ids = new Map<any, number>();
  const nodes: any[] = [];
  const edges: any[] = [];
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
      const b = this.buffer;
      if (this.context instanceof OfflineAudioContext) return (start as any).apply(this, rest);   // remuestreos: no suenan
      starts.push({ id: w.__idOf(this), t: Math.round(performance.now()), dur: b ? +b.duration.toFixed(2) : 0, loop: this.loop, loopStart: this.loopStart, loopEnd: +this.loopEnd.toFixed(2), offset: +(rest[1] || 0).toFixed(2) });
    } catch (e) { starts.push({ error: String(e) }); }
    return (start as any).apply(this, rest);
  } as any;
  w.__probeGraph = () => ({
    nodes: nodes.map((n, i) => ({ id: i, type: n.constructor.name, gain: n.gain ? +n.gain.value.toFixed(4) : undefined })),
    edges, starts,
  });
  AudioNode.prototype.connect = function (this: AudioNode, dest: any, ...rest: any[]) {
    const out = (connect as any).call(this, dest, ...rest);
    try { if (dest instanceof AudioNode && dest !== w.__probe.analyser && dest !== w.__probe.tapOut) edges.push([w.__idOf(this), w.__idOf(dest)]); } catch { /* nada */ }
    try {
      // sólo la salida real: los contextos fuera de línea (calibración del limitador) no suenan
      if (dest instanceof AudioDestinationNode && !(dest.context instanceof OfflineAudioContext)) {
        const p = w.__probe;
        p.connects++;
        if (p.ctx !== dest.context) {
          p.ctx = dest.context;
          p.analyser = dest.context.createAnalyser();
          p.analyser.fftSize = 2048;
          p.tapOut = (dest.context as AudioContext).createMediaStreamDestination();
          try {
            p.recorder = new MediaRecorder(p.tapOut.stream, { mimeType: 'audio/webm;codecs=opus', audioBitsPerSecond: 128000 });
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
    return { rms: Math.sqrt(sum / buf.length), peak, state: p.ctx.state, connects: p.connects };
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
}

/** Mide durante `ms` y devuelve el RMS medio, el máximo y el pico. */
async function listen(page: Page, ms: number) {
  let n = 0, sum = 0, max = 0, peak = 0, st = '';
  const end = Date.now() + ms;
  while (Date.now() < end) {
    const l: any = await page.evaluate(() => (window as any).__probeLevel());
    n++; sum += l.rms; max = Math.max(max, l.rms); peak = Math.max(peak, l.peak); st = l.state;
    await sleep(80);
  }
  return { rms: sum / Math.max(n, 1), max, peak, state: st };
}
/** Política de autoplay simulada. Bajo automatización Chromium concede siempre el gesto (cada
 *  consulta de la prueba cuenta como interacción), así que el bloqueo real no se puede provocar:
 *  aquí el AudioContext nace suspendido y `resume()` no hace nada hasta que llega a la página un
 *  clic o una tecla de verdad (evento de confianza), que es lo que hace un navegador que bloquea. */
const BLOCK_AUDIO = `(() => {
  const Native = window.AudioContext;
  let gesture = false;
  const resume = Native.prototype.resume;
  Native.prototype.resume = function () { return gesture ? resume.call(this) : Promise.resolve(); };
  const Blocked = function (...args) { const ctx = new Native(...args); if (!gesture) ctx.suspend(); return ctx; };
  Blocked.prototype = Native.prototype;
  window.AudioContext = Blocked;
  for (const ev of ['pointerdown', 'keydown']) window.addEventListener(ev, function (e) { if (e.isTrusted) gesture = true; }, true);
})();`;
/** Simula ocultar o mostrar la pestaña (como texto: el transpilador rompe las funciones flecha con nombre). */
const HIDE = (hidden: boolean) => `Object.defineProperty(document, 'hidden', { configurable: true, get: function () { return ${hidden}; } }); document.dispatchEvent(new Event('visibilitychange'));`;
const snd = async (page: Page): Promise<any> => ((await state(page)) as any)?.snd ?? {};
const badge = (page: Page) => page.evaluate(() => {
  const b = document.getElementById('snd');
  return b && b.style.display !== 'none' ? b.textContent || '' : '';
});

/** Abre el juego en una sala nueva, tal como llega un jugador: navegando, sin gesto en la página. */
async function open(name: string, opts: { blocked?: boolean; intro?: boolean }) {
  // Chromium con el audio encendido (Playwright lo silencia por defecto y no habría nada que medir)
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
  page.on('console', (m) => { if (m.type() === 'error') errors.push(`[${m.type()}] ${m.text().slice(0, 240)}`); });
  page.on('pageerror', (e) => errors.push(`[pageerror] ${String(e).slice(0, 240)}`));
  if (opts.blocked) await page.addInitScript(BLOCK_AUDIO);
  await page.addInitScript(probeScript);
  await login(page, name);
  await page.evaluate((intro) => {
    try {
      if (intro) localStorage.removeItem('alux_seen_llamado'); else localStorage.setItem('alux_seen_llamado', '1');
      localStorage.removeItem('alux_settings');
    } catch { /* nada */ }
  }, !!opts.intro);
  await page.click('text=Crear sala privada');
  const code = (await page.textContent('.room-code'))!.trim();
  await page.goto(`${BASE}/game/index.html?room=${code}&debug=1&q=min&fs=0`);
  await waitFor('el juego conecta', async () => (await state(page))?.net === 'PLAYING', 300_000);
  const close = async (file: string) => {
    const graph: any = await page.evaluate(() => (window as any).__probeGraph());
    fs.writeFileSync(path.join(OUT, `${file}.grafo.json`), JSON.stringify(graph, null, 1));
    const b64: string = await page.evaluate(() => (window as any).__probeStop());
    if (b64) fs.writeFileSync(path.join(OUT, `${file}.webm`), Buffer.from(b64, 'base64'));
    info(b64 ? `grabación de la salida: ${path.join(OUT, `${file}.webm`)} (${(Buffer.from(b64, 'base64').length / 1024).toFixed(0)} KB)` : 'sin grabación (nada llegó a conectarse a la salida)');
    if (errors.length) console.log('  consola del navegador:\n    ' + errors.slice(0, 10).join('\n    '));
    await browser.close();
    return graph;
  };
  return { page, close };
}

const report: Record<string, unknown> = {};

// ─────────────────────────────── normal ───────────────────────────────
async function normal() {
  console.log('— normal —');
  const { page, close } = await open('Oido', {});
  await sleep(1500);
  const quiet = await listen(page, 3000);
  let m = await snd(page);
  info(`al cargar, sin gesto en la página: AudioContext «${m.ctx}» · nivel ${dB(quiet.rms)} (pico ${dB(quiet.peak)})`);

  // Primer gesto: clic en el juego y Enter (cierra la bienvenida)
  await page.mouse.click(480, 300);
  await sleep(300);
  await page.keyboard.press('Enter');
  await waitFor('bienvenida cerrada', async () => (await state(page) as any)?.ui?.intro === false, 30_000).catch(() => {});
  await sleep(3000);
  const ambient = await listen(page, 6000);
  m = await snd(page);
  const s: any = await state(page);
  info(`tras el primer clic: AudioContext «${m.ctx}» · nivel medio ${dB(ambient.rms)} (máx. ${dB(ambient.max)}, pico ${dB(ambient.peak)})`);
  info(`mezclador: música «${m.music}» · capas ${JSON.stringify(m.loops)} · pistas cargadas ${JSON.stringify(m.loaded)} · errores ${JSON.stringify(m.errors)}`);
  check(m.ctx === 'running', 'tras el primer gesto el AudioContext debe estar en marcha');
  check(ambient.rms > AUDIBLE, `tras el primer gesto tiene que sonar el ambiente (nivel ${dB(ambient.rms)})`);
  check(m.music === 'mus_claro' && s.music === 'mus_claro', `la música del claro debe estar sonando (suena «${m.music}»)`);
  check((m.loops || []).includes('amb_selva'), `el ambiente de selva debe estar sonando (capas: ${JSON.stringify(m.loops)})`);
  check((m.errors || []).length === 0, `sin errores de carga de audio (${JSON.stringify(m.errors)})`);
  check(Math.abs(m.rms - ambient.rms) < Math.max(ambient.rms, 0.01), `el medidor del juego debe coincidir con la salida real (dice ${dB(m.rms)}, sale ${dB(ambient.rms)})`);
  ok(`Al entrar suena: ambiente y música a ${dB(ambient.rms)} de media, pico ${dB(ambient.peak)}`);

  // Una habilidad: chispas de jade (J) durante tres segundos
  await page.keyboard.down('KeyJ');
  const skill = await listen(page, 3000);
  await page.keyboard.up('KeyJ');
  check(skill.peak > ambient.peak * 1.3 || skill.peak > 0.2, `la habilidad tiene que oírse por encima del ambiente (pico ${dB(skill.peak)} frente a ${dB(ambient.peak)})`);
  check(skill.peak < 0.999, `la salida no debe recortar (pico ${dB(skill.peak)})`);
  ok(`La chispa de jade se oye por encima: pico ${dB(skill.peak)} (ambiente ${dB(ambient.peak)})`);

  // Botón «Probar sonido»: el juego mide lo que salió y lo dice
  await page.evaluate(() => { (window as any).ALUX_ACTION = 'sound_test'; });
  await sleep(700);
  const test = await listen(page, 1200);
  await waitFor('resultado de la prueba', async () => /Prueba correcta|No llegó/.test(String((await state(page) as any)?.audio_status)), 8000).catch(() => {});
  let status = String((await state(page) as any)?.audio_status);
  check(/Prueba correcta/.test(status), `«Probar sonido» debe confirmar que sale señal (dice: «${status}»)`);
  ok(`«Probar sonido»: «${status}» (medido fuera: pico ${dB(test.peak)})`);

  // Cliente silenciado: volumen general a cero
  await page.evaluate(() => { (window as any).ALUX_SETTING = 'vol_master:0'; });
  await sleep(1500);
  await page.keyboard.down('KeyJ');
  const muted = await listen(page, 2500);
  await page.keyboard.up('KeyJ');
  status = String((await state(page) as any)?.audio_status);
  const mark = await badge(page);
  check(muted.max < SILENT, `con el volumen general a cero no debe salir nada (sale ${dB(muted.max)})`);
  check(/silenciado/i.test(mark), `debe avisar en pantalla de que el sonido está silenciado (aviso: «${mark}»)`);
  check(/cero/.test(status), `el menú debe decir que el volumen está a cero (dice: «${status}»)`);
  ok(`Silenciado: sale ${dB(muted.max)} aunque se use una habilidad · aviso «${mark}» · menú «${status}»`);
  await page.evaluate(() => { (window as any).ALUX_SETTING = 'vol_master:0.9'; });
  await sleep(1500);
  const back = await listen(page, 2500);
  check(back.rms > AUDIBLE && !(await badge(page)), `al subir el volumen vuelve a sonar y el aviso se quita (nivel ${dB(back.rms)})`);
  ok(`Al subir el volumen vuelve el sonido: ${dB(back.rms)}`);

  // Sólo la música a cero: sigue el ambiente
  await page.evaluate(() => { (window as any).ALUX_SETTING = 'vol_music:0'; });
  await sleep(1200);
  const noMusic = await listen(page, 2500);
  await page.evaluate(() => { (window as any).ALUX_SETTING = 'vol_music:0.7'; });
  check(noMusic.rms > AUDIBLE * 0.5 && noMusic.rms < back.rms, `sin música debe quedar el ambiente, más bajo (queda ${dB(noMusic.rms)} de ${dB(back.rms)})`);
  ok(`Música a cero: queda el ambiente a ${dB(noMusic.rms)}`);

  // Cambio de pestaña: con la página oculta se calla; al volver, suena
  await page.evaluate(HIDE(true));
  await sleep(1200);
  const hidden = await listen(page, 2000);
  await page.evaluate(HIDE(false));
  await sleep(1500);
  const shown = await listen(page, 2500);
  check(hidden.max < SILENT, `con la pestaña oculta el juego debe callar (sale ${dB(hidden.max)})`);
  check(shown.rms > AUDIBLE, `al volver a la pestaña debe sonar otra vez (nivel ${dB(shown.rms)})`);
  ok(`Pestaña oculta: ${dB(hidden.max)} · al volver: ${dB(shown.rms)}`);

  const graph = await close('normal');
  // Bucles de verdad: la música y los ambientes arrancan una sola vez, con bucle del propio Web Audio
  const loops = graph.starts.filter((st: any) => st.dur > 3 && st.loop);
  const restarts = graph.starts.filter((st: any) => st.dur > 3 && !st.loop);
  info(`fuentes largas: ${loops.length} en bucle exacto, ${restarts.length} sin bucle (${graph.starts.length} arranques en total)`);
  check(loops.length >= 2, 'la música y el ambiente deben sonar como bucles de Web Audio');
  check(restarts.length === 0, `ningún bucle largo debe reiniciarse a mano (${restarts.length} reinicios)`);
  ok('Bucles sin corte: música y ambientes suenan con bucle exacto, sin reinicios');
  report.normal = { alCargar: quiet.rms, ambiente: ambient.rms, picoHabilidad: skill.peak, silenciado: muted.max, oculto: hidden.max };
}

// ─────────────────────────────── bloqueado ───────────────────────────────
async function blocked() {
  console.log('— bloqueado (el navegador exige un gesto en la página) —');
  const { page, close } = await open('Sordo', { blocked: true });
  await sleep(2500);
  let m = await snd(page);
  const before = await listen(page, 3000);
  const mark = await badge(page);
  info(`sin gesto: AudioContext «${m.ctx}» · nivel ${dB(before.max)} · aviso «${mark}»`);
  check(m.ctx !== 'running', `sin gesto el navegador debe tener el audio bloqueado (está «${m.ctx}»)`);
  check(before.max === 0, `bloqueado no puede sonar nada (sale ${dB(before.max)})`);
  check(/activar el sonido/i.test(mark), `debe verse el aviso para activar el sonido (aviso: «${mark}»)`);
  await page.screenshot({ path: path.join(OUT, 'bloqueado.png') });
  ok(`Bloqueado: contexto «${m.ctx}», silencio y aviso en pantalla «${mark}»`);

  await page.mouse.click(480, 300);
  await sleep(300);
  await page.keyboard.press('Enter');
  await sleep(3500);
  m = await snd(page);
  const after = await listen(page, 5000);
  const markAfter = await badge(page);
  check(m.ctx === 'running', `tras el primer clic el audio debe arrancar (está «${m.ctx}»)`);
  check(after.rms > AUDIBLE, `tras el primer clic tiene que sonar el ambiente (nivel ${dB(after.rms)})`);
  check(!markAfter, `el aviso debe quitarse al activarse el sonido (sigue: «${markAfter}»)`);
  ok(`Primer clic: contexto «${m.ctx}» a los ${m.unlockMs} ms, ambiente a ${dB(after.rms)}, aviso retirado`);
  await close('bloqueado');
  report.bloqueado = { antes: before.max, despues: after.rms, desbloqueoMs: m.unlockMs };
}

// ─────────────────────────────── cine ───────────────────────────────
async function cine() {
  console.log('— cine (banda sonora de la introducción y omisión) —');
  const { page, close } = await open('Cinefila', { intro: true });
  await waitFor('la introducción empieza', async () => (await state(page) as any)?.ui?.cine === true, 30_000);
  await sleep(2500);
  let m = await snd(page);
  const during = await listen(page, 3000);
  info(`durante «El llamado»: banda sonora «${m.cine}» · nivel ${dB(during.rms)} (pico ${dB(during.peak)}) · capas ${JSON.stringify(m.loops)}`);
  check(m.cine === 'llamado', `la introducción debe sonar con su banda sonora (suena «${m.cine}»)`);
  check(during.rms > AUDIBLE, `la banda sonora tiene que oírse (nivel ${dB(during.rms)})`);
  const starts: any = await page.evaluate(() => (window as any).__probeGraph().starts.length);
  // Omitir: la banda sonora se funde enseguida y no queda sonando debajo del juego
  await page.keyboard.press('Enter');
  await waitFor('la introducción termina', async () => (await state(page) as any)?.ui?.cine === false, 15_000);
  await sleep(900);
  m = await snd(page);
  check(m.cine === '', `al omitir, la banda sonora debe parar (sigue «${m.cine}»)`);
  await page.keyboard.press('Enter');
  await sleep(2500);
  const after = await listen(page, 3000);
  m = await snd(page);
  check(m.music === 'mus_claro', `tras la escena vuelve la música del claro (suena «${m.music}»)`);
  check(after.rms > AUDIBLE, `tras la escena sigue sonando el juego (nivel ${dB(after.rms)})`);
  ok(`«El llamado»: banda sonora a ${dB(during.rms)}; omitida, para en menos de un segundo y vuelve la música del claro (${dB(after.rms)})`);
  const graph = await close('cine');
  // Una sola banda sonora: ningún efecto por plano disparado a la vez desde el motor
  const cineStarts = graph.starts.slice(0, starts).filter((st: any) => st.dur >= 3 && !st.loop);
  info(`pistas de cinemática arrancadas: ${cineStarts.length} (efectos y música)`);
  check(cineStarts.length <= 2, `la cinemática debe sonar una sola vez (${cineStarts.length} pistas largas arrancadas)`);
  report.cine = { nivel: during.rms };
}

const RUN: Record<string, () => Promise<void>> = { normal, bloqueado: blocked, cine };
for (const name of SCENARIOS) {
  assert.ok(RUN[name], `escenario desconocido: ${name}`);
  await RUN[name]();
}
fs.writeFileSync(path.join(OUT, 'informe.json'), JSON.stringify(report, null, 2));
console.log(`Audio comprobado con la salida real del navegador (${SCENARIOS.join(', ')}). Grabaciones en ${OUT}`);
process.exit(0);
