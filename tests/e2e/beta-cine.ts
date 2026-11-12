// Cinemáticas en un navegador real contra un despliegue de beta, entrando con una invitación:
// la introducción «El llamado» al entrar por primera vez y la compartida «El sello cede» al abrir
// el santuario (un jugador solo), con la vuelta al juego y la emboscada. Sirve para cualquier
// versión desde la 0.2: si el despliegue tiene vídeos, además informa de si se vieron.
//
//   E2E_BASE_URL=https://alux-beta.onrender.com E2E_INVITES=ALUX-… npx tsx e2e/beta-cine.ts
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { BASE, driveTo, launch, login, sleep, state, waitFor } from './lib.ts';

const OUT = process.env.E2E_SHOTS || path.resolve(import.meta.dirname, 'screenshots/beta');
fs.mkdirSync(OUT, { recursive: true });
const ok = (msg: string) => console.log(`✓ ${msg}`);
assert.ok(process.env.E2E_INVITES, 'Define E2E_INVITES con un código de invitación');

const browser = await launch();
const ctx = await browser.newContext({ viewport: { width: 960, height: 540 } });
const page = await ctx.newPage();
const errors: string[] = [];
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text().slice(0, 200)); });
page.on('pageerror', (e) => errors.push(String(e).slice(0, 200)));

await login(page, 'Cine');
await page.click('text=Crear sala privada');
const code = (await page.textContent('.room-code'))!.trim();
await page.goto(`${BASE}/game/index.html?room=${code}&debug=1&q=min`);
await waitFor('el juego conecta', async () => (await state(page))?.net === 'PLAYING', 300_000);
let s: any = await state(page);
ok(`Dentro de la sala ${code} en ${new URL(BASE).host} (${s.ui?.build ?? 'cliente cargado'})`);

// 1) Introducción del capítulo, local: se reproduce sola la primera vez y se omite con Enter
await waitFor('introducción «El llamado»', async () => (await state(page) as any)?.cine === 'llamado', 60_000);
s = await state(page);
assert.equal(s.ui.cine, true, 'la interfaz entra en modo cine');
await sleep(2500);
await page.screenshot({ path: path.join(OUT, 'cine-llamado.jpg'), type: 'jpeg', quality: 80, timeout: 120_000 }).catch(() => {});
assert.equal((await state(page) as any).cine, 'llamado', 'sigue reproduciéndose');
await page.keyboard.press('Enter');
await waitFor('introducción omitida', async () => (await state(page) as any)?.cine === '', 30_000);
await waitFor('bienvenida', async () => (await state(page) as any)?.ui?.intro === true, 30_000);
await page.keyboard.press('Enter');
await waitFor('bienvenida cerrada', async () => (await state(page) as any)?.ui?.intro === false, 30_000);
ok('Introducción «El llamado»: se reproduce al entrar, se omite con Enter y da paso a la bienvenida');

// 2) Compartida: sola, pisa el altar; la sala se pausa, se ve la escena y vuelve la partida
await page.evaluate(() => {
  const w = window as any;
  w.__seen = { cine: false, frozen: false, video: false, enc: [] as number[], t0: 0, t1: 0 };
  setInterval(() => {
    const st = w.__aluxState;
    if (!st) return;
    const c = w.__seen;
    if (st.cine === 'sello') { c.cine = true; c.t0 = c.t0 || performance.now(); c.t1 = performance.now(); }
    if (st.frozen) c.frozen = true;
    if (st.cine_video) c.video = true;
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
await page.screenshot({ path: path.join(OUT, 'cine-sello.jpg'), type: 'jpeg', quality: 80, timeout: 120_000 }).catch(() => {});
await waitFor('partida reanudada', async () => {
  const st: any = await state(page);
  return st.cine === '' && st.frozen === false && st.ui.cine === false;
}, 60_000);
const w = await seen();
s = await state(page);
assert.ok(w.enc.includes(1), `la emboscada empieza al terminar (visto: ${w.enc.join('→')})`);
assert.equal(s.gate, true, 'el santuario queda abierto');
ok(`«El sello cede»: la sala se pausa, la escena se ve ${w.video ? 'como vídeo' : 'con el motor'} durante ${((w.t1 - w.t0) / 1000).toFixed(1)} s y la partida sigue con la emboscada`);
if (s.video) ok(`Vídeos del despliegue: ${JSON.stringify(Object.fromEntries(Object.entries(s.video.clips ?? {}).map(([k, v]: any) => [k, v.s])))} · fallos: ${s.video.log?.length ?? 0}`);
ok(`Este navegador (render por software, no representativo): ${s.perf.fps} FPS · ping ${Math.round(s.perf.ping)} ms`);

const bad = errors.filter((e) => !/favicon|WebGL|GPU stall|swiftshader|deprecated/i.test(e));
if (bad.length) console.log('Errores de consola:\n  ' + bad.slice(0, 6).join('\n  '));
assert.equal(bad.length, 0, 'sin errores en la consola del navegador');
await browser.close();
console.log(`Cinemáticas verificadas contra ${BASE}. Capturas en ${OUT}`);
process.exit(0);
