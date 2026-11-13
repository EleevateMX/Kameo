// Los muros del patio del santuario en un navegador real, con capturas: cerrados mientras el
// guardián duerme, hundiéndose cuando despierta (al volver de «El despertar» se ve el último
// tramo), abiertos después, y tal cual al recargar la página (quien llega tarde no ve animación).
// Dos compañeros (bots que hablan el protocolo real) abren el santuario y superan la emboscada;
// la jugadora del navegador llega después y sólo mira. Requiere ALUX corriendo.
//
//   npx tsx e2e/court-walls.ts
//
// Variables: E2E_BASE_URL, E2E_WS_URL, E2E_SHOTS (carpeta de capturas), E2E_QUALITY (min|low|high),
// E2E_VIDEO=1 deja ver «El despertar» como vídeo (por defecto se ve con el motor, que es donde
// los muros empiezan a moverse a la vista).
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { Actor, BASE, launch, login, sleep, state, waitFor } from './lib.ts';

const OUT = process.env.E2E_SHOTS || path.resolve(import.meta.dirname, 'screenshots/santuario');
fs.mkdirSync(OUT, { recursive: true });
const QUALITY = process.env.E2E_QUALITY || 'low';
const ok = (msg: string) => console.log(`✓ ${msg}`);
const st = async (page: any) => (await state(page)) as any;
const shot = async (page: any, name: string) => {
  const f0 = (await st(page)).frames;
  await waitFor('cuadros nuevos', async () => (await st(page)).frames >= f0 + 2, 60_000).catch(() => {});
  await page.screenshot({ path: path.join(OUT, name), timeout: 180_000 }).catch((e: unknown) => console.log(`  (sin captura ${name}: ${String(e).slice(0, 80)})`));
};
/** Cámara fija (sólo con ?debug=1): desde dónde y hacia dónde. '' la devuelve al personaje. */
const cam = (page: any, spec: string) => page.evaluate((v: string) => { (window as any).ALUX_CAM = v; }, spec);
/** Deja los muros a medio hundir sólo a la vista (0 cerrados … 1 abiertos); '' vuelve al estado real. */
const wallsAt = (page: any, k: string) => page.evaluate((v: string) => { (window as any).ALUX_WALLS = v; }, k);
const VIEWS = {
  portal: '22.7,1.9,0,31.6,2.3,0',        // como el último plano de «El despertar»
  alto: '12.5,13.5,-5,29,0.5,0.3',        // desde arriba, por encima de la portada: el patio entero
  dentro: '23.6,2.6,3.2,32.5,1.2,-4.5',   // dentro del patio, hacia la esquina del fondo
  esquina: '25.5,5.2,-2.4,22.6,3.0,-6.1', // donde el muro norte (que se hunde) se une a la portada (que no)
};

const browser = await launch();
const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
const page = await ctx.newPage();
const errors: string[] = [];
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text().slice(0, 300)); });
page.on('pageerror', (e) => errors.push(String(e).slice(0, 300)));
if (process.env.E2E_VIDEO !== '1') await page.route('**/video/**', (r) => r.abort());

// 1) La sala: la crea la jugadora; dos compañeros abren el santuario y superan la emboscada
await login(page, 'Ixchel');
await page.evaluate(() => { try { localStorage.setItem('alux_seen_llamado', '1'); } catch { /* nada */ } });
await page.click('text=Crear sala privada');
const code = (await page.textContent('.room-code'))!.trim();
const cast = [new Actor(code, 'Nicte', '#e4007c', 1), new Actor(code, 'Chaac', '#ff7a1a', 0)];
cast.forEach((a) => { a.autoSkip = true; });
await waitFor('los compañeros entran', async () => cast.every((a) => a.snap), 30_000);
const plates = [[17.5, -5], [0, -15.5]];
await Promise.all(cast.map((a, i) => a.walkTo(plates[i][0], plates[i][1])));
await waitFor('emboscada en curso', async () => cast[0].world()[3] === 1, 60_000);
const cleared = () => cast[0].world()[3] === 2;
for (let tries = 0; tries < 4 && !cleared(); tries++) {
  await Promise.all(cast.map((a) => a.fight(() => cleared() || cast[0].world()[3] === 3, 240, { form: 'balam', near: { x: 15, z: 0, r: 26 } })));
  if (cast[0].world()[3] === 3) {
    await waitFor('los altares vuelven a responder', async () => cast[0].world()[3] === 0 && cast[0].world()[9] === 0 && cast.every((a) => !a.dead()), 60_000);
    await Promise.all(cast.map((a, i) => a.walkTo(plates[i][0], plates[i][1])));
    await waitFor('emboscada de nuevo', async () => cast[0].world()[3] === 1, 60_000);
  }
}
assert.ok(cleared(), 'los compañeros superan la emboscada');
// se quedan en la explanada, lejos del patio, dando señales de vida
await Promise.all(cast.map((a, i) => a.walkTo(12, i ? 3 : -3)));
let alive = cast.map((a) => a.idle(1, 0));
const boss = () => cast[0].snap.b as number[];
assert.deepEqual([boss()[0], boss()[24]], [0, 0], 'el guardián duerme y los muros del patio están cerrados');
ok(`Sala ${code}: emboscada superada por los compañeros; el guardián duerme`);

// 2) La jugadora llega tarde: ve el patio cerrado, sin animación
const open = async () => {
  await page.goto(`${BASE}/game/index.html?room=${code}&debug=1&q=${QUALITY}`);
  await waitFor('el juego conecta', async () => (await st(page))?.net === 'PLAYING', 300_000);
};
await open();
await waitFor('bienvenida', async () => (await st(page))?.ui?.intro === true, 60_000);
await page.keyboard.press('Enter');
let s = await st(page);
assert.deepEqual([s.walls.state, s.walls.k], [0, 0], 'en el navegador, muros cerrados');
for (const [name, view] of Object.entries(VIEWS)) {
  await cam(page, view);
  await shot(page, `01-cerrados-${name}.png`);
}
ok('Antes de despertar: muros cerrados (capturas 01-*)');

// 3) Un compañero entra al patio: el guardián despierta y los muros empiezan a abrirse
alive.forEach(clearInterval);
cast.forEach((a) => { a.autoSkip = false; });   // «El despertar» se deja ver entera
await cam(page, VIEWS.portal);
await cast[0].walkTo(19.5, 0);
void cast[0].walkTo(25.5, -1.5);
await waitFor('el guardián despierta', async () => (await st(page)).boss?.[0] === 1, 120_000);
alive = cast.map((a) => a.idle(1, 0));
s = await st(page);
assert.equal(s.walls.state, 1, 'al despertar, los muros pasan a «abriéndose»');
await waitFor('«El despertar» en pantalla', async () => (await st(page)).cine === 'despertar', 60_000);
const video = (await st(page)).cine_video === true;
// Con el motor, los muros empiezan a hundirse en el último plano (los 4 s finales de 16)
const seen: number[] = [];
const t0 = Date.now();
let shotInScene = false;
while ((await st(page)).cine === 'despertar' && Date.now() - t0 < 40_000) {
  const q = await st(page);
  seen.push(q.walls.k);
  if (q.walls.k > 0.2 && !shotInScene) {
    // (una sola captura: a 1–4 cuadros por segundo tarda más que lo que queda de escena)
    shotInScene = true;
    await page.screenshot({ path: path.join(OUT, '02-despertar-ultimo-plano.png'), timeout: 60_000 }).catch(() => {});
  }
  await sleep(100);
}
const inScene = Math.max(0, ...seen);
if (!video) assert.ok(inScene > 0.05 && inScene <= 0.51, `en la versión del motor empiezan a hundirse dentro de la escena (hasta ${inScene})`);
ok(`«El despertar» (${video ? 'vídeo' : 'motor'}): durante la escena los muros llegaron a ${Math.round(inScene * 100)} %`);

// 4) Al volver al juego se ve el último tramo; después quedan abiertos
const tail: { k: number; state: number; fade: number }[] = [];
const t1 = Date.now();
let n = 0;
while (Date.now() - t1 < 30_000) {
  const q = await st(page);
  tail.push({ k: q.walls.k, state: q.walls.state, fade: q.fade });
  if (q.walls.state === 2 && q.walls.k >= 1) break;
  if (q.fade < 0.5 && n < 6) await page.screenshot({ path: path.join(OUT, `03-ultimo-tramo-${++n}.png`), timeout: 60_000 }).catch(() => {});
  await sleep(100);
}
s = await st(page);
assert.deepEqual([s.walls.state, s.walls.k], [2, 1], 'los muros terminan abiertos');
const visible = tail.filter((q) => q.fade < 0.5 && q.k < 1);
assert.ok(tail[0].k >= 0.3, `al volver de la escena ya van camino de la mitad (${tail[0].k})`);
ok(`Último tramo a la vista: ${visible.length} lecturas con el juego visible y los muros aún bajando (de ${Math.round((visible[0]?.k ?? 1) * 100)} % a 100 %)`);
// los compañeros se apartan: el guardián se queda en el patio y nadie cae
alive.forEach(clearInterval);
await cast[0].walkTo(19.5, 0);
await Promise.all(cast.map((a, i) => a.walkTo(2, i ? 3 : -3, '', 40)));
alive = cast.map((a) => a.idle(1, 0));
for (const [name, view] of Object.entries(VIEWS)) {
  await cam(page, view);
  await shot(page, `04-abiertos-${name}.png`);
}
ok('Muros abiertos (capturas 04-*)');

// 5) La animación, cuadro a cuadro: sólo se cambia lo que se ve (la colisión es la del servidor)
await cam(page, VIEWS.alto);
await wallsAt(page, '0');
// (así se ve el cierre: suben de vuelta en segundo y medio)
await waitFor('empiezan a subir', async () => (await st(page)).walls.k < 0.9, 30_000);
await page.screenshot({ path: path.join(OUT, '05-cierre-subiendo.png'), timeout: 60_000 }).catch(() => {});
await waitFor('muros arriba (a la vista)', async () => (await st(page)).walls.k <= 0.001, 60_000);
for (const k of ['0.14', '0.3', '0.5', '0.7', '0.88']) {
  await wallsAt(page, k);
  for (const [name, view] of [['alto', VIEWS.alto], ['dentro', VIEWS.dentro], ['portal', VIEWS.portal]]) {
    await cam(page, view);
    await waitFor(`muros al ${k}`, async () => Math.abs((await st(page)).walls.k - Number(k)) < 0.06, 60_000).catch(() => {});
    await page.screenshot({ path: path.join(OUT, `05-animacion-k${k.replace('0.', '')}-${name}.png`), timeout: 60_000 }).catch(() => {});
  }
}
await wallsAt(page, '');
await waitFor('vuelven al estado del servidor', async () => (await st(page)).walls.k >= 1, 60_000);
ok('Animación capturada en cinco momentos (capturas 05-*)');

// 6) Recargar la página: quien llega tarde los ve ya abiertos, sin animación
await open();
s = await st(page);
assert.deepEqual([s.walls.state, s.walls.k], [2, 1], 'al reconectar, abiertos desde el primer estado');
await cam(page, VIEWS.alto);
await shot(page, '06-reconexion-abiertos.png');
ok('Reconexión: abiertos desde el primer cuadro');

alive.forEach(clearInterval);
cast.forEach((a) => a.ws.close());
await browser.close();
const real = errors.filter((e) => !/favicon|video|ERR_FAILED|net::/i.test(e));
if (real.length) console.log('Errores de consola:\n  ' + real.join('\n  '));
assert.equal(real.length, 0, 'sin errores en la consola del navegador');
console.log(`\nCapturas en ${OUT}`);
process.exit(0);
