// Capturas a calidad alta: un navegador real + tres bots colocados en escena.
// Requiere ALUX corriendo en modo desarrollo (usa el secreto de tickets de desarrollo).
import fs from 'node:fs';
import path from 'node:path';
import { Actor, BASE, driveTo, launch, login, lookAt, sleep, state, waitFor } from './lib.ts';

const OUT = process.env.E2E_SHOTS || path.resolve(import.meta.dirname, 'screenshots');
fs.mkdirSync(OUT, { recursive: true });
const shot = (page: any, name: string) => page.screenshot({ path: path.join(OUT, name), timeout: 180_000 });
// El juego corre en calidad baja para ir fluido sin GPU; sólo durante la captura se sube a alta.
const beauty = async (page: any, name: string) => {
  await page.evaluate(() => { (window as any).ALUX_SET_QUALITY = 'high'; });
  const f0 = (await state(page))!.frames;
  await waitFor('cuadros en calidad alta', async () => (await state(page))!.frames >= f0 + 3, 60_000);
  await shot(page, name);
  await page.evaluate(() => { (window as any).ALUX_SET_QUALITY = 'min'; });
};

const browser = await launch();
const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 }, deviceScaleFactor: 2 });
const page = await ctx.newPage();
await page.goto(BASE);
await shot(page, 'portada.png');
await login(page, 'Ixchel');
await page.click('.swatch[aria-label="#19b4d6"]');
await page.click('text=Guardar alux');
await page.waitForSelector('.saved:has-text("Guardado")');
await page.click('text=Crear sala privada');
const code = (await page.textContent('.room-code'))!.trim();
await page.waitForTimeout(500);
await shot(page, 'centro-de-jugadores.png');

// El juego se renderiza a tamaño normal (sin duplicar píxeles) para que el render por software alcance
const game = await (await browser.newContext({ viewport: { width: 1280, height: 720 }, storageState: await ctx.storageState() })).newPage();
game.on('console', (m) => { if (m.type() === 'error') console.log('[consola]', m.text().slice(0, 300)); });
await game.goto(`${BASE}/game/index.html?room=${code}&debug=1&cine=0&q=min`);
await waitFor('el juego arranca', async () => (await state(game))?.net === 'PLAYING', 240_000);
console.log('modelos .glb:', (await state(game))!.glb);

const cast = [
  new Actor(code, 'Nicte', '#e4007c', 1),
  new Actor(code, 'Balam Kin', '#ffd23f', 2),
  new Actor(code, 'Chaac', '#ff7a1a', 0),
];
await sleep(1500);

// 1) Los cuatro en la plaza, uno transformado en Balam
await Promise.all([cast[0].walkTo(0.4, -3.4), cast[1].walkTo(-3.4, -1.6, 'balam'), cast[2].walkTo(5.2, -2.2)]);
let timers = [cast[0].idle(0.2, 1), cast[1].idle(0.8, 0.6), cast[2].idle(-0.5, 1)];
await sleep(6000);
await beauty(game, 'juego-cuatro-aluxes.png');

// 1b) Primeros planos: se acerca la cámara y el personaje camina un paso hacia ella para verle la cara
await game.click('#canvas', { timeout: 180_000, noWaitAfter: true });
for (let i = 0; i < 8; i++) await game.mouse.wheel(0, -200);
await game.keyboard.down('KeyS');
await sleep(700);
await game.keyboard.up('KeyS');
await sleep(1500);
await beauty(game, 'juego-alux-de-cerca.png');
await game.keyboard.press('Digit2');
await waitFor('transformación', async () => (await state(game))!.form === 'balam', 30_000);
await game.keyboard.down('KeyS');
await sleep(500);
await game.keyboard.up('KeyS');
await sleep(2500);
await beauty(game, 'juego-balam-de-cerca.png');
await game.keyboard.press('Digit1');
for (let i = 0; i < 8; i++) await game.mouse.wheel(0, 200);
await sleep(1500);
timers.forEach(clearInterval);

// 2) Acertijo: tres bots a sus altares y la jugadora del navegador al cuarto → se abre y hay emboscada
const plates = [[0, -15.5], [-11, 7], [8, 16]];
await Promise.all(cast.map((a, i) => a.walkTo(plates[i][0], plates[i][1])));
timers = cast.map((a) => a.idle(0, 1));
await game.click('#canvas', { timeout: 180_000, noWaitAfter: true });
const arrived = await driveTo(game, 17.5, -5, { timeoutMs: 120_000, stop: 0.9 });
console.log('jugadora en el altar:', arrived);
await waitFor('emboscada en curso', async () => (await state(game))?.encounter === 1, 30_000);
timers.forEach(clearInterval);

// 3) Combate cooperativo: dos Balam cuerpo a cuerpo, un alux a distancia, y la jugadora dispara
const center = { x: 15, z: 0, r: 26 };
const cleared = () => cast[0].world()[3] === 2;
// (los bots atacan a ratos mientras se toman las capturas; después pelean en serio)
let lazy = true;
const fights = [
  cast[0].fight(() => cleared() || !lazy, 240, { reach: 8, near: center, lazy: true }),
  cast[1].fight(() => cleared() || !lazy, 240, { form: 'balam', near: center, lazy: true }),
  cast[2].fight(() => cleared() || !lazy, 240, { form: 'balam', near: center, lazy: true }),
];
const me = () => state(game).then((s) => s!.players.find((p) => p.id === s!.me)!);
await lookAt(game, await me(), { x: 15, z: 0 });
await game.keyboard.down('KeyJ');
for (let i = 1; i <= 4; i++) {
  await sleep(1500);
  await lookAt(game, await me(), { x: 15, z: 0 });
  await beauty(game, `juego-combate-${i}.png`);
  const st = await state(game);
  console.log(`combate ${i}: cuadros=${st!.frames} fps=${st!.perf.fps} quedan=${st!.wave} vida=${st!.hp}`);
}
lazy = false;
await Promise.all(fights);
await Promise.all([
  cast[0].fight(cleared, 150, { reach: 8, near: center }),
  cast[1].fight(cleared, 150, { form: 'balam', near: center }),
  cast[2].fight(cleared, 150, { form: 'balam', near: center }),
]);
await game.keyboard.up('KeyJ');
const end = await state(game);
console.log('emboscada superada:', end!.encounter === 2, '· vida de la jugadora:', end!.hp);
await sleep(1500);
await beauty(game, 'juego-santuario-liberado.png');
console.log('rendimiento (render por software):', JSON.stringify(end!.perf));
await browser.close();
console.log(`Capturas guardadas en ${OUT}`);
process.exit(0);
