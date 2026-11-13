// La plaza social (prototipo de la Alpha 0.4), con dos navegadores reales.
//
//   npx tsx e2e/plaza.ts
//
// Comprueba:
//   1. Desde el portal se entra a la plaza; los dos aluxes se ven, cada uno con el aspecto del otro.
//   2. Uno anda y el otro lo ve moverse, en el mismo sitio que dice el servidor.
//   3. Suena la música de la plaza.
//   4. Cambiarse de aspecto en la plaza se replica al otro.
//   5. El portal lleva a una sala del Claro de los Aluxes, que funciona como siempre; el otro
//      jugador ve que se fue.
// Requiere ALUX corriendo con el servidor de zonas (node scripts/dev.mjs --prod).
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import type { Frame, Page } from 'playwright';
import { BASE, launch, login, sleep, waitFor } from './lib.ts';

const OUT = path.resolve(import.meta.dirname, 'screenshots/plaza');
fs.mkdirSync(OUT, { recursive: true });
const ok = (msg: string) => console.log(`✓ ${msg}`);

const browser = await launch();
const newPage = async () => (await browser.newContext({ viewport: { width: 1280, height: 720 } })).newPage();
const frameOf = (page: Page, what: string): Frame | undefined => page.frames().find((f) => f.url().includes(what));
const st = async (page: Page, what = 'mode=plaza'): Promise<any> => frameOf(page, what)?.evaluate(() => (window as any).__aluxState).catch(() => undefined);
const set = (page: Page, key: string, value: string) => frameOf(page, 'mode=plaza')!.evaluate(([k, v]) => { (window as any)[k] = v; }, [key, value]);
const dist = (p: { x: number; z: number }, q: { x: number; z: number }) => Math.hypot(p.x - q.x, p.z - q.z);

// ── 1) Entrar ──
const a = await newPage();
const b = await newPage();
await login(a, 'Ana');
await login(b, 'Beto');
// Ana llega vestida: su aspecto tiene que verse en la plaza
const look = { outfit: 3, accessory: 4, amulet: 2, accent: 6, skin: 1 };
const saved = await a.evaluate(async (l) => (await (await fetch('/api/v1/me/character', {
  method: 'PUT', headers: { 'content-type': 'application/json', 'x-alux-csrf': '1' }, body: JSON.stringify({ name: 'Ana', color: '#ffd23f', hat: 4, look: l }),
})).json()).character, look);
assert.deepEqual(saved.look, look);
await a.goto(`${BASE}/hub`);
assert.equal(await a.getAttribute('a.plaza', 'href'), '/plaza', 'el portal enlaza a la plaza');
await Promise.all([a.goto(`${BASE}/plaza?debug=1&q=min&fs=0`), b.goto(`${BASE}/plaza?debug=1&q=min&fs=0`)]);
await waitFor('los dos dentro de la plaza', async () => (await st(a))?.net === 'PLAYING' && (await st(b))?.net === 'PLAYING', 300_000);
await waitFor('se ven', async () => (await st(a)).players.length === 1 && (await st(b)).players.length === 1 && (await st(a)).total === 2, 30_000);
let sa = await st(a), sb = await st(b);
assert.equal(sa.zone, 'merida');
assert.equal(sa.players[0].name, 'Beto');
assert.deepEqual([sb.players[0].name, sb.players[0].color, sb.players[0].hat, sb.players[0].look], ['Ana', '#ffd23f', 4, [3, 4, 2, 6, 1]], 'Beto dibuja a Ana con su aspecto');
assert.deepEqual([sa.players[0].color, sa.players[0].hat, sa.players[0].look], ['#2ec4a6', 0, [0, 1, 1, 0, 0]], 'Ana dibuja a Beto con el aspecto inicial');
await sleep(2000);
await a.screenshot({ path: path.join(OUT, '01-plaza.png') });
ok(`Dos aluxes en la plaza «${sa.zone}» (capacidad ${sa.cap}); cada uno ve al otro con su aspecto · ${sa.perf.draws} llamadas de dibujo, ${sa.perf.fps} FPS (render por software)`);

// ── 2) Moverse ──
const start = { x: sa.me.x, z: sa.me.z };
await set(a, 'ALUX_ZONE_GOTO', '9,22');
await waitFor('Ana llega a su destino', async () => dist((await st(a)).me, { x: 9, z: 22 }) < 1.0, 60_000);
// Cuando Ana se para, lo que ve Beto tiene que acabar coincidiendo con donde está ella (los
// navegadores de prueba dibujan a 1–2 cuadros por segundo: se espera a que converja)
let seen: any;
await waitFor('Beto ve a Ana donde ella está', async () => {
  sa = await st(a);
  sb = await st(b);
  seen = sb.players.find((p: any) => p.name === 'Ana');
  return !!seen && dist(seen, sa.me) < 0.5 && dist(sa.me, { x: 9, z: 22 }) < 0.7;
}, 30_000);
assert.ok(dist(sa.me, start) > 5, `Ana se movió (${dist(sa.me, start).toFixed(1)} m)`);
assert.ok(sa.perf.pending <= 12, `la predicción no se queda atrás (${sa.perf.pending} entradas sin confirmar)`);
ok(`Movimiento: Ana anduvo ${dist(sa.me, start).toFixed(1)} m y Beto la ve en el mismo sitio (diferencia ${dist(seen, sa.me).toFixed(2)} m)`);

// ── 3) Sonido ──
await a.mouse.click(400, 400);
await waitFor('música de la plaza sonando', async () => { const m = (await st(a)).snd; return m.ctx === 'running' && m.music === 'mus_lobby' && m.rms > 0.0005; }, 60_000);
await a.keyboard.press('Escape');
await sleep(600);
ok(`Suena la plaza: música «${(await st(a)).snd.music}» con ${(await st(a)).snd.loops.length} capas de ambiente`);

// ── 4) Cambiarse en la plaza ──
await set(a, 'ALUX_ACTION', 'customize');
await waitFor('personalizador abierto', async () => (await st(a)).custom.active === true, 30_000);
await set(a, 'ALUX_CUSTOM', 'hat:6');
await sleep(900);
await set(a, 'ALUX_CUSTOM', 'color:#8f5bd6');
await sleep(1200);
await a.screenshot({ path: path.join(OUT, '02-personalizador.png') });
await set(a, 'ALUX_CUSTOM', 'save');
await waitFor('guardado', async () => /^Guardado/.test((await st(a)).custom.status), 30_000);
await waitFor('Beto ve el aspecto nuevo sin recargar', async () => {
  const p = (await st(b)).players.find((x: any) => x.name === 'Ana');
  return p && p.hat === 6 && p.color === '#8f5bd6';
}, 30_000);
await set(a, 'ALUX_CUSTOM', 'close');
await waitFor('personalizador cerrado', async () => (await st(a)).custom.active === false, 15_000);
assert.deepEqual([(await st(a)).me.hat, (await st(a)).me.color], [6, '#8f5bd6']);
ok('Cambio de aspecto en la plaza: guardado, releído por el servidor de zonas y visto por el otro jugador');

// ── 5) El portal al Claro ──
await set(a, 'ALUX_ZONE_GOTO', '28.6,0');
await waitFor('Ana junto al portal', async () => (await st(a)).portal === true, 90_000);
await sleep(800);
assert.match((await st(a)).prompt, /Claro de los Aluxes/, 'aparece el aviso del portal');
await a.screenshot({ path: path.join(OUT, '03-portal.png') });
await set(a, 'ALUX_ACTION', 'portal');
await waitFor('la página pasa a una sala', async () => /\/play\/[A-Z0-9]{6}/.test(a.url()), 60_000);
const code = /\/play\/([A-Z0-9]{6})/.exec(a.url())![1];
await waitFor('la sala del Claro está en marcha', async () => (await st(a, `room=${code}`))?.net === 'PLAYING', 300_000);
const room = await st(a, `room=${code}`);
assert.equal(room.room, code);
assert.equal(room.players.length, 1);
assert.deepEqual([room.players[0].name, room.players[0].hat, room.players[0].color], ['Ana', 6, '#8f5bd6'], 'entra al Claro con el aspecto que eligió en la plaza');
await waitFor('Beto ve que Ana se fue', async () => (await st(b)).total === 1 && (await st(b)).players.length === 0, 30_000);
await sleep(1500);
await a.screenshot({ path: path.join(OUT, '04-claro.png') });
ok(`Portal: Ana cruzó a la sala ${code} del Claro de los Aluxes, que funciona como siempre; Beto se queda en la plaza y la ve irse`);

await browser.close();
console.log(`Plaza social verificada. Capturas en ${OUT}`);
process.exit(0);
