// El Camino a Motul en un navegador real: de la plaza de Mérida por el arco del este-noreste al
// camino, la misión de la cordelera, un descubrimiento, una criatura purificada, el cartel de
// Motul, el mapa y la carreta de vuelta. Captura cada paso y anota las llamadas de dibujo.
//
//   E2E_BASE_URL=http://localhost:3300 npx tsx e2e/camino.ts
//
// Requiere el portal, la API y el servidor de zonas en marcha (scripts/dev.mjs o a mano). El
// navegador de pruebas dibuja a 1–8 cuadros por segundo y su alux anda a paso de tortuga: para
// que las criaturas no lo tumben una y otra vez, arranca el servidor con ALUX_WILD_DAMAGE=0.05.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import type { Frame, Page } from 'playwright';
import { BASE, launch, login, sleep, waitFor } from './lib.ts';

const OUT = process.env.E2E_SHOTS || path.resolve(import.meta.dirname, 'screenshots/camino');
fs.mkdirSync(OUT, { recursive: true });
const ok = (msg: string) => console.log(`✓ ${msg}`);
const draws: Record<string, number> = {};

const browser = await launch();
const page: Page = await (await browser.newContext({ viewport: { width: 1280, height: 720 } })).newPage();
const frame = (): Frame | undefined => page.frames().find((f) => f.url().includes('mode=plaza'));
const st = async (): Promise<any> => frame()?.evaluate(() => (window as any).__aluxState).catch(() => undefined);
const set = (key: string, value: string) => frame()!.evaluate(([k, v]) => { (window as any)[k] = v; }, [key, value]);
const dist = (p: { x: number; z: number }, q: [number, number]) => Math.hypot(p.x - q[0], p.z - q[1]);
async function goto(x: number, z: number, timeout = 120_000) {
  await set('ALUX_ZONE_GOTO', `${x},${z}`);
  await waitFor(`llegar a ${x},${z}`, async () => { const s = await st(); return s && (dist(s.me, [x, z]) < 1.0 || s.world.down); }, timeout);
}
async function shot(name: string, label: string) {
  await sleep(2500);
  const s = await st();
  draws[label] = s.perf.draws;
  await page.screenshot({ path: path.join(OUT, name) });
  return s;
}

await login(page, 'Caminante');
await page.goto(`${BASE}/plaza?debug=1&q=high&fs=0`);
await waitFor('dentro de la plaza', async () => (await st())?.net === 'PLAYING', 300_000);
await set('ALUX_ACTION', 'gov:off');
let s = await st();
assert.equal(s.zone, 'merida');
ok(`En la plaza de Mérida (${s.perf.draws} llamadas de dibujo)`);

// ── 1) El arco hacia Motul, al este-noreste de la plaza ──
await goto(29.4, -12.75);
await set('ALUX_CAM', `${Math.PI / 2},0.12,7.5`);
s = await shot('01-plaza-arco-motul.png', 'plaza, frente al arco');
assert.match(s.prompt, /camino a Motul/i, `aviso del arco (${s.prompt})`);
ok(`Arco hacia Motul con su aviso: «${s.prompt}»`);

// ── 2) Paso al camino ──
await set('ALUX_ACTION', 'travel');
await waitFor('en el camino', async () => (await st())?.zone === 'camino_motul', 30_000);
await sleep(1500);
await set('ALUX_CAM', `${Math.PI / 2 - 0.15},0.22,7`);
s = await shot('02-salida-de-merida.png', 'camino, salida de Mérida');
assert.ok(s.world.safe && s.world.hp === s.world.maxhp);
ok(`Camino a Motul: llegada a la zona segura, vida ${s.world.hp}/${s.world.maxhp}, ${s.perf.draws} llamadas de dibujo`);
await set('ALUX_CAM', `${-Math.PI / 2},0.2,7`);
await shot('03-muralla-de-merida.png', 'camino, mirando a Mérida');

// ── 3) La misión de la cordelera ──
await goto(11.0, 4.0);
await set('ALUX_CAM', `${0.9},0.25,6`);
await sleep(800);
s = await st();
assert.match(s.world.prompt, /Rosario/, `aviso de la cordelera (${s.world.prompt}; ${JSON.stringify(s.me)})`);
await set('ALUX_ACTION', 'quest');
await waitFor('diálogo abierto', async () => (await st()).world.dialog, 10_000);
await shot('04-mision-cordelera.png', 'diálogo de la misión');
await set('ALUX_ACTION', 'accept');
await waitFor('misión aceptada', async () => (await st()).world.quest.st === 'active', 10_000);
ok('Misión aceptada: «El recado de la cordelera»');

// ── 4) Descubrimiento: la milpa ──
await goto(44, 4.5);
await waitFor('milpa descubierta', async () => (await st()).world.known.includes('camino_motul:milpa'), 20_000);
await set('ALUX_CAM', `${0.3},0.3,8`);
await shot('05-milpa-descubierta.png', 'milpa');
ok('Lugar descubierto: la milpa');

// ── 5) Combate: una zarza, debilitada con la chispa y purificada ──
await goto(36.5, -8.0);
let purified = false;
const end = Date.now() + 120_000;
let fightShot = false;
while (Date.now() < end && !purified) {
  s = await st();
  const c = s.world.creatures.find((x: any) => x.id === 0) ?? s.world.creatures.sort((a: any, b: any) => dist(a, [s.me.x, s.me.z]) - dist(b, [s.me.x, s.me.z]))[0];
  if (s.world.down) { await sleep(1000); continue; }
  if (!c) { await goto(38.5, -9.5, 30_000); continue; }
  const d = dist(s.me, [c.x, c.z]);
  if (c.st === 'weak') {
    if (d > 2.2) await set('ALUX_ZONE_GOTO', `${c.x},${c.z}`);
    else {
      await set('ALUX_ACTION', 'purify');
      purified = await waitFor('purificada', async () => (await st()).world.quest.n >= 1 || null, 5000).then(() => true, () => false);
    }
  } else if (d > 5.5) {
    await set('ALUX_ZONE_GOTO', `${c.x - (c.x - s.me.x) / d * 4},${c.z - (c.z - s.me.z) / d * 4}`);
  } else {
    await set('ALUX_ACTION', 'attack');
    if (!fightShot && c.hp < 40) {
      fightShot = true;
      await set('ALUX_CAM', `${Math.atan2(c.x - s.me.x, c.z - s.me.z)},0.3,7`);
      await page.screenshot({ path: path.join(OUT, '06-combate.png') });
    }
  }
  await sleep(600);
}
assert.ok(purified, 'se purificó una criatura');
await sleep(1500);
await page.screenshot({ path: path.join(OUT, '07-purificada.png') });
ok(`Criatura purificada; misión ${(await st()).world.quest.n}/${(await st()).world.quest.need}`);

// ── 6) Por el camino hasta el cartel de Motul ──
const route: [number, number][] = [[52, -16], [78, -20], [95, -40], [104, -34], [128, -52], [154, -58], [180, -72], [195, -77.4]];
let falls = 0;
for (let i = 0; i < route.length; i++) {
  const [x, z] = route[i];
  await goto(x, z, 180_000);
  if ((await st()).world.down) {
    // Cayó: vuelve en la zona segura de la salida con todo; se rehace el camino desde allí
    assert.ok(++falls <= 3, 'demasiadas caídas en el camino');
    await waitFor('reaparece', async () => !(await st()).world.down, 15_000);
    ok('Cayó en el camino y reapareció en la zona segura sin perder nada; se sigue');
    i = -1;
    continue;
  }
  if (x === 95) {
    await set('ALUX_CAM', `${Math.PI},0.3,8`);
    await shot('08-cenote.png', 'cenote');
  }
  if (x === 128) {
    await set('ALUX_CAM', `${Math.PI / 2 + 0.6},0.2,8`);
    await shot('09-camino-abierto.png', 'tramo abierto');
  }
}
await set('ALUX_CAM', `${Math.PI / 2 + 0.35},0.12,8`);
s = await shot('10-cartel-motul.png', 'cartel de Motul');
assert.ok(s.world.known.includes('camino_motul:cartel_motul'), 'el cartel cuenta como lugar descubierto');
ok(`Llegada al cartel de bienvenida de Motul (${s.perf.draws} llamadas de dibujo); lugares: ${s.world.known.length}`);

// ── 7) El mapa ──
await set('ALUX_ACTION', 'map');
await waitFor('mapa abierto', async () => (await st()).world.map, 10_000);
await shot('11-mapa.png', 'mapa');
await set('ALUX_ACTION', 'map');
ok('Mapa con Mérida, el camino, Motul, Izamal y Valladolid');

// ── 8) De vuelta en la carreta ──
await goto(209.5, -84.0);
await set('ALUX_ACTION', 'travel');
await waitFor('de vuelta en Mérida', async () => (await st())?.zone === 'merida', 30_000);
await sleep(2000);
await set('ALUX_CAM', `${-Math.PI / 2},0.25,7`);
s = await shot('12-vuelta-a-merida.png', 'plaza, de vuelta');
ok(`De vuelta en la plaza junto al arco (${s.me.x.toFixed(1)}, ${s.me.z.toFixed(1)})`);

console.log('\nLlamadas de dibujo (calidad alta, 1280×720, render por software):');
for (const [k, v] of Object.entries(draws)) console.log(`  ${k}: ${v}`);
fs.writeFileSync(path.join(OUT, 'medidas.json'), JSON.stringify({ draws, scene: s.world.scene }, null, 2));
await browser.close();
process.exit(0);
