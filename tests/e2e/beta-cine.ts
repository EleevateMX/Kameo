// Cinemáticas en un navegador real contra un despliegue de beta, entrando con una invitación.
// Tres pasadas, cada una en una sala nueva y con un jugador solo:
//   ver        la introducción «El llamado» y la compartida «El sello cede» entera; si el despliegue
//              trae vídeos, tienen que descargarse y verse como vídeo
//   omitir     Enter a mitad de «El sello cede»: termina antes de tiempo y la partida sigue
//   sin_video  se cortan las descargas de vídeo: la escena se ve con el motor y la partida sigue
// Sirve para cualquier versión desde la 0.2 (en la 0.2 no hay vídeos: se ve siempre con el motor).
//
//   E2E_BASE_URL=https://alux-beta.onrender.com E2E_INVITES=ALUX-… npx tsx e2e/beta-cine.ts [ver omitir sin_video]
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import type { Browser } from 'playwright';
import { BASE, driveTo, launch, login, sleep, state, waitFor } from './lib.ts';

const OUT = process.env.E2E_SHOTS || path.resolve(import.meta.dirname, 'screenshots/beta');
fs.mkdirSync(OUT, { recursive: true });
const ok = (msg: string) => console.log(`✓ ${msg}`);
assert.ok(process.env.E2E_INVITES, 'Define E2E_INVITES con un código de invitación');
type Mode = 'ver' | 'omitir' | 'sin_video';
const wanted = (process.argv.slice(2).filter((a) => ['ver', 'omitir', 'sin_video'].includes(a)) as Mode[]);
const modes: Mode[] = wanted.length ? wanted : ['ver', 'omitir', 'sin_video'];

async function run(browser: Browser, mode: Mode) {
  const ctx = await browser.newContext({ viewport: { width: 960, height: 540 } });
  // La introducción sólo se comprueba en la primera pasada
  if (mode !== 'ver') await ctx.addInitScript(() => { try { localStorage.setItem('alux_seen_llamado', '1'); } catch { /* nada */ } });
  const page = await ctx.newPage();
  const errors: string[] = [];
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text().slice(0, 200)); });
  page.on('pageerror', (e) => errors.push(String(e).slice(0, 200)));
  const videoRequests: { url: string; status: number; bytes: number; cache: string }[] = [];
  page.on('response', async (r) => {
    if (!/\/game\/video\/.+\.(mp4|webm)/.test(r.url())) return;
    const len = Number(r.headers()['content-length'] || 0);
    videoRequests.push({ url: path.basename(new URL(r.url()).pathname), status: r.status(), bytes: len, cache: r.headers()['cache-control'] || '' });
  });
  if (mode === 'sin_video') await page.route(/\/game\/video\/.+\.(mp4|webm)/, (route) => route.abort());

  await login(page, 'Cine');
  await page.click('text=Crear sala privada');
  const code = (await page.textContent('.room-code'))!.trim();
  await page.goto(`${BASE}/game/index.html?room=${code}&debug=1&q=min`);
  await waitFor('el juego conecta', async () => (await state(page))?.net === 'PLAYING', 300_000);
  let s: any = await state(page);

  if (mode === 'ver') {
    // Introducción del capítulo, local: se reproduce sola la primera vez y se omite con Enter
    await waitFor('introducción «El llamado»', async () => (await state(page) as any)?.cine === 'llamado', 60_000);
    s = await state(page);
    assert.equal(s.ui.cine, true, 'la interfaz entra en modo cine');
    await sleep(2500);
    await page.screenshot({ path: path.join(OUT, 'cine-llamado.jpg'), type: 'jpeg', quality: 80, timeout: 120_000 }).catch(() => {});
    assert.equal((await state(page) as any).cine, 'llamado', 'sigue reproduciéndose');
    await page.keyboard.press('Enter');
    await waitFor('introducción omitida', async () => (await state(page) as any)?.cine === '', 30_000);
    ok('Introducción «El llamado»: se reproduce al entrar y se omite con Enter');
  }
  await waitFor('bienvenida', async () => (await state(page) as any)?.ui?.intro === true, 60_000);
  await page.keyboard.press('Enter');
  await waitFor('bienvenida cerrada', async () => (await state(page) as any)?.ui?.intro === false, 30_000);

  // ¿Trae vídeos este despliegue? (la 0.2 no tiene el puente de vídeo; la 0.2.1 sí)
  s = await state(page);
  const hasBridge = s.video !== undefined;
  let clips: Record<string, any> = {};
  if (hasBridge) {
    await waitFor('descargas de vídeo resueltas', async () => {
      const v = (await state(page) as any).video;
      if (!v || v.manifest === 'idle' || v.manifest === 'loading') return false;
      const all = Object.values(v.clips ?? {}) as any[];
      return all.every((c) => ['fetched', 'absent', 'error', 'ready'].includes(c.s));
    }, 120_000);
    clips = ((await state(page)) as any).video.clips ?? {};
  }
  const names = Object.keys(clips);
  const fetched = names.filter((n) => clips[n].s === 'fetched');
  if (mode === 'sin_video') {
    if (hasBridge) assert.equal(fetched.length, 0, 'con las descargas cortadas no hay ningún vídeo disponible');
  } else if (hasBridge && names.length) {
    assert.equal(fetched.length, names.length, `todos los vídeos se descargan (${names.map((n) => `${n}:${clips[n].s}`).join(', ')})`);
    const total = names.reduce((sum, n) => sum + clips[n].bytes, 0);
    const okReq = videoRequests.filter((r) => r.status === 200);
    assert.ok(okReq.length >= names.length, 'un archivo por vídeo, servido con 200');
    assert.ok(okReq.every((r) => /immutable/.test(r.cache)), `los vídeos llegan con caché larga (${okReq[0]?.cache})`);
    ok(`Carga de vídeo: ${names.length} archivos, ${(total / 1e6).toFixed(2)} MB (${okReq.map((r) => r.url).join(', ')}), caché «${okReq[0].cache}»`);
  }

  // Sola, pisa el altar: la sala se pausa, se ve la escena y vuelve la partida
  await page.evaluate(() => {
    const w = window as any;
    w.__seen = { cine: false, frozen: false, video: false, clipsSeen: [] as string[], enc: [] as number[], t0: 0, t1: 0 };
    setInterval(() => {
      const st = w.__aluxState;
      if (!st) return;
      const c = w.__seen;
      if (st.cine === 'sello') { c.cine = true; c.t0 = c.t0 || performance.now(); c.t1 = performance.now(); }
      if (st.frozen) c.frozen = true;
      if (st.cine_video) c.video = true;
      const cur = st.video && st.video.current;
      if (cur && st.video.visible && !c.clipsSeen.includes(cur)) c.clipsSeen.push(cur);
      if (c.enc[c.enc.length - 1] !== st.encounter) c.enc.push(st.encounter);
    }, 40);
  });
  const seen = () => page.evaluate(() => (window as any).__seen);
  await page.mouse.click(480, 200);
  const walk = { stop: false };
  const going = driveTo(page, 17.5, -5, { timeoutMs: 240_000, stop: 0.9, cancel: walk });
  await waitFor('la sala se pausa para la escena', async () => (await seen()).frozen === true, 240_000);
  walk.stop = true;
  await going;
  await waitFor('escena «El sello cede» en pantalla', async () => (await seen()).cine === true, 30_000);
  if (mode === 'omitir') {
    await sleep(1800);
    await page.keyboard.press('Enter');
  } else {
    await sleep(mode === 'ver' ? 4200 : 1500);
    await page.screenshot({ path: path.join(OUT, `cine-sello-${mode}.jpg`), type: 'jpeg', quality: 80, timeout: 120_000 }).catch(() => {});
  }
  await waitFor('partida reanudada', async () => {
    const st: any = await state(page);
    return st.cine === '' && st.frozen === false && st.ui.cine === false;
  }, 60_000);
  const w = await seen();
  s = await state(page);
  const secs = (w.t1 - w.t0) / 1000;
  assert.ok(w.enc.includes(1), `la emboscada empieza al terminar (visto: ${w.enc.join('→')})`);
  assert.equal(s.gate, true, 'el santuario queda abierto');
  if (hasBridge) assert.equal(await page.evaluate(() => (window as any).ALUX_VIDEO.visible()), false, 'ningún vídeo tapa el juego al terminar');
  if (mode === 'ver') {
    if (fetched.length) {
      assert.equal(w.video, true, 'con los vídeos descargados, la escena se ve como vídeo');
      assert.ok(w.clipsSeen.length >= 2, `se ven varios planos como vídeo (${w.clipsSeen.join(', ')})`);
      assert.equal(s.cine_stats.fallbacks, 0, 'sin recurrir al motor');
    }
    ok(`Reproducción: «El sello cede» pausa la sala, se ve ${w.video ? `como vídeo (${w.clipsSeen.join(', ')})` : 'con el motor'} durante ${secs.toFixed(1)} s y la partida sigue con la emboscada`);
  } else if (mode === 'omitir') {
    assert.ok(secs < 8, `con Enter termina antes de su duración (${secs.toFixed(1)} s)`);
    ok(`Omisión: Enter a mitad de la escena la termina a los ${secs.toFixed(1)} s (${w.video ? 'vídeo' : 'motor'}) y la partida sigue`);
  } else {
    assert.equal(w.video, false, 'sin vídeos, la escena se ve con el motor');
    if (hasBridge) assert.ok(s.cine_stats.engine >= 1, 'contada como vista con el motor');
    ok(`Respaldo: con las descargas de vídeo cortadas, la escena se ve con el motor durante ${secs.toFixed(1)} s y la partida sigue${hasBridge ? ` (fallos registrados: ${s.video.log.map((l: any) => `${l.id}:${l.what}`).join(', ') || 'ninguno'})` : ''}`);
  }
  if (mode === 'ver') ok(`Este navegador (render por software, no representativo): ${s.perf.fps} FPS · ping ${Math.round(s.perf.ping)} ms`);
  const bad = errors.filter((e) => !/favicon|WebGL|GPU stall|swiftshader|deprecated|net::ERR_FAILED|Failed to load resource/i.test(e));
  if (bad.length) console.log('Errores de consola:\n  ' + bad.slice(0, 6).join('\n  '));
  assert.equal(bad.length, 0, 'sin errores en la consola del navegador');
  await ctx.close();
}

const browser = await launch();
for (const mode of modes) await run(browser, mode);
await browser.close();
console.log(`Cinemáticas verificadas contra ${BASE} (${modes.join(', ')}). Capturas en ${OUT}`);
process.exit(0);
