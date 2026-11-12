// Sesión de un jugador en un navegador real contra un despliegue de beta, entrando con una
// invitación: portal → sala → carga del cliente Godot → bienvenida → menú → altar → emboscada →
// derrota → reintentar → salir. No necesita secretos del servidor (no usa bots).
//
//   E2E_BASE_URL=https://alux-beta.onrender.com E2E_INVITES=ALUX-… npx tsx e2e/beta-solo.ts
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { BASE, driveTo, launch, login, sleep, state, waitFor } from './lib.ts';

const OUT = process.env.E2E_SHOTS || path.resolve(import.meta.dirname, 'screenshots/beta');
fs.mkdirSync(OUT, { recursive: true });
const QUALITY = process.env.E2E_QUALITY || 'min';
const ok = (msg: string) => console.log(`✓ ${msg}`);
const ui = async (page: any) => (await state(page) as any)?.ui ?? {};
const shot = async (page: any, name: string) => {
  const f0 = (await state(page))!.frames;
  await waitFor('cuadros nuevos', async () => (await state(page))!.frames >= f0 + 3, 90_000);
  await page.screenshot({ path: path.join(OUT, name), timeout: 180_000 });
};

assert.ok(process.env.E2E_INVITES, 'Define E2E_INVITES con un código de invitación');
const browser = await launch();
const page = await (await browser.newContext({ viewport: { width: 1280, height: 720 } })).newPage();
const errors: string[] = [];
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text().slice(0, 300)); });
page.on('pageerror', (e) => errors.push(String(e).slice(0, 300)));

await login(page, 'Comprobacion');
await page.click('text=Crear sala privada');
const code = (await page.textContent('.room-code'))!.trim();
await page.screenshot({ path: path.join(OUT, '00-portal.png') });
ok(`Portal por ${BASE.split(':')[0].toUpperCase()}: sesión con invitación y sala ${code} creada`);

const t0 = Date.now();
await page.goto(`${BASE}/game/index.html?room=${code}&debug=1&q=${QUALITY}`);
await waitFor('el juego conecta', async () => (await state(page))?.net === 'PLAYING', 420_000);
await waitFor('bienvenida visible', async () => (await ui(page)).intro === true, 60_000);
let s: any = await state(page);
const wsUrl = await page.evaluate(() => (window as any).ALUX?.wsUrl ?? '');
if (BASE.startsWith('https://')) assert.match(wsUrl, /^wss:\/\//, `el juego se conectó por ${wsUrl}`);
await shot(page, '01-bienvenida.png');
ok(`Cliente Godot cargado y dentro de la sala en ${((Date.now() - t0) / 1000).toFixed(1)} s (medido por el juego: ${(s.metrics.loadMs / 1000).toFixed(1)} s) · ${wsUrl}`);

await page.keyboard.press('Enter');
await waitFor('bienvenida cerrada', async () => (await ui(page)).intro === false, 60_000);
s = await state(page);
assert.ok(s.audio.includes('amb_selva') && s.audio.includes('mus_claro'), `audio cargado: ${s.audio.join(', ')}`);
const audioState = await page.evaluate(() => (window as any).ALUX_AUDIO?.state ?? 'sin contexto');
ok(`Audio: ${s.audio.length} sonidos cargados, música «${s.music}», contexto de audio del navegador: ${audioState}`);

await page.keyboard.press('Escape');
await waitFor('menú abierto', async () => (await ui(page)).menu === true, 60_000);
await shot(page, '02-menu.png');
await page.keyboard.press('Escape');
await waitFor('menú cerrado', async () => (await ui(page)).menu === false, 60_000);
ok('Menú (Esc) abre y cierra');

assert.ok(await driveTo(page, 17.5, -5, { timeoutMs: 240_000, stop: 0.9 }), 'llega al altar');
await waitFor('emboscada en curso', async () => (await state(page))?.encounter === 1, 90_000);
s = await state(page);
assert.equal(s.gate, true);
assert.equal(s.wave, 3, 'con un jugador aparecen tres enemigos');
await shot(page, '03-emboscada.png');
ok(`Altar → santuario abierto → emboscada (${s.wave} enemigos), música «${s.music}»`);

// Se queda en el altar sin defenderse: los enemigos llegan solos. La derrota dura unos segundos
// como estado, así que lo que se espera es su panel.
await waitFor('panel de derrota', async () => (await ui(page)).result === true, 300_000);
s = await state(page);
assert.equal(s.gate, false, 'el santuario se vuelve a sellar');
assert.ok(s.encounter === 3 || s.encounter === 0, 'la emboscada se retira');
assert.equal(s.stats.falls >= 1, true);
await shot(page, '04-derrota.png');
ok('Derrota: el santuario se vuelve a sellar y aparece el panel');
await page.keyboard.press('Enter');
await waitFor('lista para reintentar', async () => {
  const st: any = await state(page);
  return st.ui.result === false && st.encounter === 0 && st.lock === 0;
}, 120_000);
ok('Reintentar: la sala vuelve al estado inicial');

s = await state(page);
ok(`Rendimiento de este navegador (render por software, no representativo): ${s.perf.fps} FPS · ping ${Math.round(s.perf.ping)} ms · ` +
  `${s.perf.snaps} estados/s · JS ${Math.round(s.perf.heap)} MB · reconexiones ${s.rejoins} · muestras de métricas ${s.metrics.samples}`);

await page.keyboard.press('Escape');
await waitFor('menú abierto', async () => (await ui(page)).menu === true, 60_000);
const box = await page.evaluate(() => ({ w: innerWidth, h: innerHeight }));
await page.mouse.click(box.w / 2, box.h / 2 + 170);   // «Salir al portal»
await page.waitForURL('**/hub', { timeout: 90_000 });
ok('Salir al portal desde el menú');

const bad = errors.filter((e) => !/favicon|WebGL|GPU stall|swiftshader|deprecated/i.test(e));
if (bad.length) console.log('Errores de consola:\n  ' + bad.slice(0, 8).join('\n  '));
assert.equal(bad.length, 0, 'sin errores en la consola del navegador');
await browser.close();
console.log(`Sesión de un jugador verificada contra ${BASE}. Capturas en ${OUT}`);
process.exit(0);
