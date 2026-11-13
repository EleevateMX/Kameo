// Personalizador 3D (Alpha 0.4): el alux real, con cámara orbital, se viste en el juego, se guarda
// en el perfil y los demás jugadores lo ven igual.
//
//   npx tsx e2e/customizer.ts
//
// Comprueba, en navegadores reales:
//   1. Desde el portal se abre el juego en modo «vestir» con el alux del perfil.
//   2. Elegir color, tocado, vestimenta, accesorio y amuleto cambia el modelo (se miran las piezas
//      que quedan a la vista, no sólo la opción marcada); arrastrar gira la cámara y la rueda acerca.
//   3. Guardar lo deja en el perfil (API) y persiste al volver a abrir.
//   4. En una sala, otro jugador ve ese aspecto.
//   5. Cambiarse dentro de la sala se replica al otro jugador sin recargar.
// Requiere ALUX corriendo (node scripts/dev.mjs --prod).
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import type { Frame, Page } from 'playwright';
import { BASE, launch, login, sleep, state, waitFor } from './lib.ts';

const OUT = path.resolve(import.meta.dirname, 'screenshots/personalizador');
fs.mkdirSync(OUT, { recursive: true });
const ok = (msg: string) => console.log(`✓ ${msg}`);

const browser = await launch();
const newPage = async () => (await browser.newContext({ viewport: { width: 1280, height: 720 } })).newPage();
const me = (page: Page) => page.evaluate(async () => (await (await fetch('/api/v1/me')).json()).character);

// ── 1) Del portal al personalizador ──
const a = await newPage();
await login(a, 'Vestida');
await a.goto(`${BASE}/hub`);
assert.equal(await a.getAttribute('a.look-3d', 'href'), '/alux', 'el portal enlaza al personalizador 3D');
await a.goto(`${BASE}/alux?debug=1&q=min`);
const custom = async (): Promise<{ frame: Frame; st: () => Promise<any>; cmd: (c: string) => Promise<void> }> => {
  await waitFor('el juego en modo vestir', async () => a.frames().some((f) => f.url().includes('mode=alux')), 60_000);
  const frame = a.frames().find((f) => f.url().includes('mode=alux'))!;
  const st = async () => (await frame.evaluate(() => (window as any).__aluxState).catch(() => undefined))?.custom;
  const cmd = async (c: string) => { await frame.evaluate((v) => { (window as any).ALUX_CUSTOM = v; }, c); await sleep(900); };
  await waitFor('el personalizador se abre', async () => (await st())?.active === true, 300_000);
  return { frame, st, cmd };
};
let c = await custom();
let s = await c.st();
assert.equal(s.name, 'Vestida');
assert.equal(s.color, '#2ec4a6');
assert.equal(s.hat, 0);
assert.ok(s.parts.includes('Hat_Palma'), `el alux empieza con su sombrero de palma (piezas: ${s.parts})`);
assert.equal(s.anim, 'Idle', 'el alux está en reposo');
assert.equal(s.dirty, false);
await sleep(1500);
await a.screenshot({ path: path.join(OUT, '01-inicio.png') });
ok(`El portal abre el juego en modo vestir con el alux del perfil (ofrece: ${Object.entries(s.options).map(([k, v]) => `${k} ${(v as unknown[]).length}`).join(', ')})`);

// ── 2) Elegir cambia el modelo ──
await c.cmd('color:#e4007c');
await c.cmd('hat:1');
await c.cmd('accent:3');
const want: Record<string, number> = { outfit: s.look[0], accessory: s.look[1], amulet: s.look[2], accent: 3, skin: s.look[4] };
const expectParts = ['Hat_Penacho'];
// De cada familia se elige una pieza distinta de la que lleva, si el modelo la trae
for (const [family, prefix] of [['outfit', 'Outfit_'], ['accessory', 'Acc_'], ['amulet', 'Amu_']] as const) {
  const offered: number[] = s.options[family] ?? [];
  const pick = offered.find((v) => v > 0 && v !== want[family]);
  if (pick === undefined) continue;
  await c.cmd(`${family}:${pick}`);
  want[family] = pick;
  expectParts.push(prefix);
}
if ((s.options.skin ?? []).length > 1) { await c.cmd('skin:2'); want.skin = 2; }
await waitFor('el modelo refleja lo elegido', async () => {
  const now = await c.st();
  return now.color === '#e4007c' && now.hat === 1 && JSON.stringify(now.look) === JSON.stringify([want.outfit, want.accessory, want.amulet, want.accent, want.skin]);
}, 30_000);
s = await c.st();
assert.ok(!s.parts.includes('Hat_Palma'), `el sombrero anterior ya no se ve (piezas: ${s.parts})`);
for (const p of expectParts) assert.ok(s.parts.some((x: string) => x.startsWith(p)), `debe verse una pieza ${p}* (piezas: ${s.parts})`);
assert.equal(s.parts.filter((x: string) => x.startsWith('Hat_')).length, 1, 'un solo tocado a la vez');
assert.ok(s.parts.filter((x: string) => x.startsWith('Outfit_')).length <= 1 && s.parts.filter((x: string) => x.startsWith('Acc_')).length <= 1
  && s.parts.filter((x: string) => x.startsWith('Amu_')).length <= 1, 'una sola pieza de cada familia');
assert.equal(s.dirty, true);
ok(`Elegir cambia el modelo real: piezas a la vista ${s.parts.join(', ')}`);

// Cámara orbital: arrastrar gira, la rueda acerca
const before = await c.st();
await a.mouse.move(300, 380);
await a.mouse.down();
await a.mouse.move(520, 380, { steps: 8 });
await a.mouse.up();
await a.mouse.move(300, 380);
await a.mouse.wheel(0, -400);
await waitFor('la cámara gira y se acerca', async () => {
  const now = await c.st();
  return Math.abs(now.yaw - before.yaw) > 0.3 && now.dist < before.dist - 0.2;
}, 20_000);
s = await c.st();
await c.cmd('yaw:0.35');
await sleep(1500);
await a.screenshot({ path: path.join(OUT, '02-vestida.png') });
ok(`Cámara orbital: giró ${Math.abs(s.yaw - before.yaw).toFixed(2)} rad arrastrando y se acercó de ${before.dist} a ${s.dist} m con la rueda`);

// ── 3) Guardar y persistir ──
await c.cmd('save');
await waitFor('guardado', async () => /^Guardado/.test((await c.st()).status), 30_000);
const saved = await me(a);
assert.deepEqual(saved, { name: 'Vestida', color: '#e4007c', hat: 1, look: want });
await a.goto(`${BASE}/alux?debug=1&q=min`);
c = await custom();
s = await c.st();
assert.equal(s.color, '#e4007c');
assert.equal(s.hat, 1);
assert.deepEqual(s.look, [want.outfit, want.accessory, want.amulet, want.accent, want.skin]);
assert.equal(s.dirty, false);
await c.cmd('close');
await waitFor('vuelta al portal', async () => a.url().endsWith('/hub'), 30_000);
assert.match((await a.textContent('.look-line'))!, /Penacho/, 'el portal resume lo que lleva el alux');
ok(`Guardado en el perfil y conservado al volver: ${JSON.stringify(saved)}`);

// ── 4) En una sala, otro jugador lo ve igual ──
await a.click('text=Crear sala privada');
const code = (await a.textContent('.room-code'))!.trim();
const b = await newPage();
await login(b, 'Vecina');
const url = `${BASE}/game/index.html?room=${code}&debug=1&q=min&cine=0&fs=0`;
await Promise.all([a.goto(url), b.goto(url)]);
await waitFor('los dos en la sala', async () => (await state(a))?.net === 'PLAYING' && (await state(b))?.net === 'PLAYING'
  && ((await state(b)) as any).players.length === 2, 300_000);
const seenBy = async (page: Page, name: string) => ((await state(page)) as any).players.find((p: any) => p.name === name);
let other = await seenBy(b, 'Vestida');
assert.equal(other.color, '#e4007c');
assert.equal(other.hat, 1);
assert.deepEqual(other.look, [want.outfit, want.accessory, want.amulet, want.accent, want.skin]);
const neighbour = await seenBy(a, 'Vecina');
assert.deepEqual([neighbour.color, neighbour.hat, neighbour.look], ['#2ec4a6', 0, [0, 1, 1, 0, 0]], 'quien no se ha vestido se ve con el aspecto inicial (morral y colgante de jade)');
ok('Réplica: el otro jugador dibuja a Vestida con el color, el tocado y las piezas guardadas');

// ── 5) Cambiarse dentro de la sala ──
await a.mouse.click(640, 360);
await sleep(300);
await a.keyboard.press('Enter');
await waitFor('bienvenida cerrada', async () => ((await state(a)) as any).ui.intro === false, 30_000);
await a.evaluate(() => { (window as any).ALUX_ACTION = 'customize'; });
const inRoom = async () => ((await state(a)) as any).custom;
await waitFor('personalizador abierto en la sala', async () => (await inRoom()).active === true, 30_000).catch(async (e) => {
  const st: any = await state(a);
  console.log(`  no se abrió: ${JSON.stringify({ ui: st.ui, encounter: st.encounter, frozen: st.frozen, cine: st.cine, hint: st.hint, me: st.players.find((p: any) => p.name === 'Vestida') })}`);
  throw e;
});
const send = async (v: string) => { await a.evaluate((x) => { (window as any).ALUX_CUSTOM = x; }, v); await sleep(900); };
await send('hat:2');
await send('color:#19b4d6');
await sleep(1200);
await a.screenshot({ path: path.join(OUT, '03-en-la-sala.png') });
await send('save');
await waitFor('guardado en la sala', async () => /^Guardado/.test((await inRoom()).status), 30_000);
await waitFor('el otro jugador ve el cambio sin recargar', async () => {
  const p = await seenBy(b, 'Vestida');
  return p.hat === 2 && p.color === '#19b4d6';
}, 30_000);
await send('close');
await waitFor('personalizador cerrado', async () => (await inRoom()).active === false, 15_000);
other = await seenBy(a, 'Vestida');
assert.deepEqual([other.color, other.hat], ['#19b4d6', 2], 'la propia jugadora se ve con el aspecto nuevo');
assert.equal((await state(a))?.net, 'PLAYING', 'la partida sigue');
assert.deepEqual([(await me(a)).color, (await me(a)).hat], ['#19b4d6', 2]);
ok('Cambio dentro de la sala: guardado en la API, releído por el servidor y visto por el otro jugador sin recargar');

await browser.close();
console.log(`Personalizador 3D verificado. Capturas en ${OUT}`);
process.exit(0);
