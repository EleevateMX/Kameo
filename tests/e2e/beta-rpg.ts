// Progresión RPG contra un despliegue, con un navegador real y una cuenta (la de verificación):
// Puesto de Saberes de la plaza → comprar un amuleto común → equiparlo → entrar al Claro con él.
//
//   E2E_BASE_URL=https://alux-beta.onrender.com E2E_INVITES=ALUX-… npx tsx e2e/beta-rpg.ts
//
// Requiere semillas suficientes (80) o el amuleto ya comprado. No compra dos veces.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { BASE, launch, login, sleep, state, waitFor } from './lib.ts';

const OUT = process.env.E2E_SHOTS || path.resolve(import.meta.dirname, 'screenshots/beta-rpg');
fs.mkdirSync(OUT, { recursive: true });
const ok = (msg: string) => console.log(`✓ ${msg}`);
const browser = await launch();
const page = await (await browser.newContext({ viewport: { width: 1280, height: 720 } })).newPage();
await login(page, 'Cine');
const me0 = await page.evaluate(async () => (await (await fetch('/api/v1/me')).json()).rpg);
ok(`Perfil: nivel ${me0.level}, ${me0.xp} de experiencia, ${me0.seeds} semillas, ${me0.items.length} amuleto(s), vida ${me0.stats.hp}`);

await page.goto(`${BASE}/plaza?debug=1&q=min&fs=0`);
const plaza = () => page.frames().find((f) => f.url().includes('mode=plaza'));
const zs = async (): Promise<any> => plaza()?.evaluate(() => (window as any).__aluxState).catch(() => undefined);
const act = (v: string) => plaza()!.evaluate((x) => { (window as any).ALUX_ACTION = x; }, v);
await waitFor('dentro de la plaza', async () => (await zs())?.net === 'PLAYING', 300_000);
await act('shop');
await waitFor('el puesto abre con el perfil', async () => (await zs())?.shop?.rpg?.level >= 1 && (await zs()).shop.catalog === true && !(await zs()).shop.busy, 60_000);
let shop = (await zs()).shop;
let idx = shop.rpg.items.findIndex((i: any) => i.item === 'semilla_ceiba');
if (idx < 0) {
  assert.ok(shop.rpg.seeds >= 80, `hacen falta 80 semillas (hay ${shop.rpg.seeds})`);
  await act('shop:buy:amulet:semilla_ceiba');
  await waitFor('amuleto comprado', async () => (await zs()).shop.rpg.items.some((i: any) => i.item === 'semilla_ceiba') && !(await zs()).shop.busy, 60_000);
  shop = (await zs()).shop;
  assert.equal(shop.rpg.seeds, me0.seeds - 80, 'cuesta 80 semillas, una sola vez');
  idx = shop.rpg.items.findIndex((i: any) => i.item === 'semilla_ceiba');
  ok(`Compra en el Puesto de Saberes: «${shop.last?.name}» por 80 semillas (quedan ${shop.rpg.seeds})`);
} else {
  ok('El amuleto ya estaba en el inventario: no se vuelve a comprar');
}
await act(`shop:equip:${idx}`);
await waitFor('amuleto equipado', async () => (await zs()).shop.rpg.equipped === (await zs()).shop.rpg.items[idx].id && !(await zs()).shop.busy, 60_000);
shop = (await zs()).shop;
const base = Math.round(100 * (1 + 0.01 * (shop.rpg.level - 1)));
assert.equal(shop.rpg.stats.hp, Math.round(base * 1.02), 'común de vida: +2 % sobre la vida de su nivel');
await sleep(1500);
await page.screenshot({ path: path.join(OUT, '01-puesto-de-saberes.png'), timeout: 180_000 });
ok(`Equipado: vida máxima ${shop.rpg.stats.hp} (nivel ${shop.rpg.level} sin amuleto: ${base})`);

const room = await page.evaluate(async () => (await (await fetch('/api/v1/rooms', { method: 'POST', headers: { 'content-type': 'application/json', 'x-alux-csrf': '1' }, body: '{}' })).json()).code);
await page.goto(`${BASE}/game/index.html?room=${room}&debug=1&q=min`);
await waitFor('el Claro', async () => (await state(page))?.net === 'PLAYING', 300_000);
await waitFor('vida máxima con el amuleto', async () => (await state(page) as any).rpg?.hp_max === shop.rpg.stats.hp, 30_000);
await waitFor('el HUD muestra la progresión', async () => (await state(page) as any).rpg?.hud?.open === true, 30_000);
const s: any = await state(page);
assert.equal(s.hp, shop.rpg.stats.hp, 'entra con la vida llena, ya con el amuleto');
await sleep(1500);
await page.screenshot({ path: path.join(OUT, '02-claro.png'), timeout: 180_000 });
ok(`Claro de los Aluxes (sala ${room}): vida ${s.hp}/${s.rpg.hp_max} con el amuleto · HUD «${s.rpg.hud.level}», ${s.rpg.hud.seeds}`);
await browser.close();
process.exit(0);
