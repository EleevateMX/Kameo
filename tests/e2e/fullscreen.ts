// Pantalla completa (Alpha 0.4): el botón JUGAR del portal la pide dentro del propio clic con la
// Fullscreen API (nunca se simula F11) y el juego se abre dentro de la misma página para no perderla.
//
//   npx tsx e2e/fullscreen.ts
//
// Comprueba, en un navegador real:
//   1. JUGAR entra en pantalla completa, el juego carga dentro del portal y suena.
//   2. El botón discreto del juego sale y vuelve a entrar, y la preferencia se recuerda.
//   3. Salir como con Esc (lo hace el navegador) deja la partida en marcha, en ventana.
//   4. Con la preferencia desactivada, JUGAR entra en ventana.
//   5. Si el navegador niega la pantalla completa, se entra igual, en ventana.
//   6. Abriendo el juego directamente, el primer clic la pide (una sola vez).
// Requiere ALUX corriendo (node scripts/dev.mjs --prod).
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import type { Browser, Frame, Page } from 'playwright';
import { BASE, launch, login, sleep, state, waitFor } from './lib.ts';

const OUT = path.resolve(import.meta.dirname, 'screenshots/pantalla-completa');
fs.mkdirSync(OUT, { recursive: true });
const ok = (msg: string) => console.log(`✓ ${msg}`);

const isFullscreen = (page: Page) => page.evaluate(() => !!document.fullscreenElement);
const pref = (page: Page) => page.evaluate(() => localStorage.getItem('alux_fullscreen'));
const gameFrame = (page: Page): Frame | undefined => page.frames().find((f) => f.url().includes('/game/index.html'));
/** El juego ya arrancó dentro del marco (el motor terminó de cargar). */
async function waitGame(page: Page): Promise<Frame> {
  await waitFor('el juego aparece dentro del portal', async () => !!gameFrame(page), 60_000);
  const frame = gameFrame(page)!;
  await waitFor('el motor arranca', async () => frame.evaluate(() => Number((window as any).ALUX?.engineMs) > 0).catch(() => false), 300_000);
  return frame;
}
/** Pulsa el botón de pantalla completa del juego con el ratón de verdad (mover, pulsar, soltar).
 *  La orden de clic de alto nivel se queda esperando cuando el propio clic cambia el modo de pantalla. */
async function pressFs(page: Page, frame: Frame) {
  const box = (await frame.locator('#fs').boundingBox())!;
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
  await page.mouse.up();
}
const snd = (frame: Frame) => frame.evaluate(() => JSON.parse((window as any).ALUX_SND.state()));

async function newPlayer(browser: Browser, name: string, init?: string) {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
  const page = await ctx.newPage();
  if (init) await page.addInitScript(init);
  await login(page, name);
  await page.evaluate(() => { try { localStorage.setItem('alux_seen_llamado', '1'); localStorage.removeItem('alux_fullscreen'); } catch { /* nada */ } });
  await page.reload();
  await page.click('text=Crear sala privada');
  const code = (await page.textContent('.room-code'))!.trim();
  return { page, code };
}

const browser = await launch();

// 1) JUGAR con la preferencia por defecto
{
  const { page, code } = await newPlayer(browser, 'Pantalla');
  await page.waitForSelector('.fs-pref input');
  assert.equal(await page.isChecked('.fs-pref input'), true, 'la pantalla completa viene marcada por defecto');
  assert.equal(await isFullscreen(page), false);
  await page.click('button.enter');
  await waitFor('la página del juego', async () => page.url().includes(`/play/${code}`), 30_000);
  assert.equal(await isFullscreen(page), true, 'JUGAR debe dejar la página en pantalla completa');
  const frame = await waitGame(page);
  assert.equal(await isFullscreen(page), true, 'la pantalla completa se conserva mientras carga el juego');
  assert.equal(await frame.evaluate(() => (window as any).ALUX_FS.active()), true, 'el juego sabe que está en pantalla completa');
  await page.screenshot({ path: path.join(OUT, '01-jugar.png') });
  ok(`JUGAR: pantalla completa pedida en el clic, el juego carga dentro del portal (/play/${code}) y la conserva`);

  // Suena también dentro del marco
  await page.mouse.click(640, 360);
  await sleep(300);
  await page.keyboard.press('Enter');
  await waitFor('audio en marcha dentro del marco', async () => { const m = await snd(frame); return m.ctx === 'running' && m.rms > 0.0005; }, 60_000);
  ok('El audio suena con el juego dentro del portal');

  // 2) El botón del juego: salir y volver a entrar. La partida tiene el ratón capturado: como
  //    haría un jugador, Esc lo suelta (abre el menú) y entonces se puede pulsar el botón.
  await page.keyboard.press('Escape');
  await waitFor('el ratón queda libre', async () => frame.evaluate(() => !document.pointerLockElement), 10_000);
  assert.equal(await isFullscreen(page), true, 'Esc abre el menú del juego sin sacar de pantalla completa');
  await pressFs(page, frame);
  await waitFor('sale de pantalla completa', async () => !(await isFullscreen(page)), 10_000);
  assert.equal(await pref(page), '0', 'salir con el botón se recuerda');
  await sleep(1000);
  assert.ok((await snd(frame)).ctx === 'running', 'la partida sigue en ventana');
  await pressFs(page, frame);
  await waitFor('vuelve a pantalla completa', async () => isFullscreen(page), 10_000);
  assert.equal(await pref(page), '1', 'volver a entrar se recuerda');
  ok('Botón del juego: sale a ventana y vuelve a pantalla completa; la preferencia se guarda');

  // 3) Salir como con Esc: lo hace el navegador, sin pasar por el juego
  await page.evaluate(() => document.exitFullscreen());
  await waitFor('fuera de pantalla completa', async () => !(await isFullscreen(page)), 10_000);
  await sleep(1500);
  const after = await snd(frame);
  assert.equal(after.ctx, 'running', 'la partida sigue tras salir con Esc');
  assert.equal(await pref(page), '1', 'salir con Esc no cambia la preferencia');
  assert.equal(await frame.evaluate(() => (window as any).ALUX_FS.active()), false);
  await sleep(1500);
  assert.equal(await isFullscreen(page), false, 'no se le vuelve a meter en pantalla completa sin pedirlo');
  ok('Salir con Esc: la partida continúa en ventana y no se vuelve a entrar sola');
  await page.context().close();
}

// 4) Preferencia desactivada
{
  const { page, code } = await newPlayer(browser, 'Ventana');
  await page.waitForSelector('.fs-pref input');
  await page.uncheck('.fs-pref input');
  assert.equal(await pref(page), '0');
  await page.click('button.enter');
  await waitFor('la página del juego', async () => page.url().includes(`/play/${code}`), 30_000);
  await waitGame(page);
  assert.equal(await isFullscreen(page), false, 'con la preferencia desactivada se entra en ventana');
  ok('Preferencia desactivada: JUGAR entra en ventana');
  await page.context().close();
}

// 5) El navegador la niega
{
  const deny = `Element.prototype.requestFullscreen = function () { return Promise.reject(new TypeError('Permissions check failed')); };`;
  const { page, code } = await newPlayer(browser, 'Negada', deny);
  await page.click('button.enter');
  await waitFor('la página del juego', async () => page.url().includes(`/play/${code}`), 30_000);
  const frame = await waitGame(page);
  assert.equal(await isFullscreen(page), false);
  await page.mouse.click(640, 360);
  await waitFor('la partida funciona en ventana', async () => (await snd(frame)).ctx === 'running', 30_000);
  ok('Pantalla completa negada por el navegador: se entra igual, en ventana');
  await page.context().close();
}

// 6) Abriendo el juego directamente
{
  const { page, code } = await newPlayer(browser, 'Directo');
  await page.goto(`${BASE}/game/index.html?room=${code}&debug=1&q=min&fs=1`);
  await waitFor('el juego conecta', async () => (await state(page))?.net === 'PLAYING', 300_000);
  assert.equal(await isFullscreen(page), false, 'sin gesto no hay pantalla completa');
  await page.mouse.click(640, 360);
  await waitFor('pantalla completa con el primer clic', async () => isFullscreen(page), 10_000);
  await page.evaluate(() => document.exitFullscreen());
  await waitFor('fuera', async () => !(await isFullscreen(page)), 10_000);
  await page.mouse.click(640, 360);
  await sleep(1200);
  assert.equal(await isFullscreen(page), false, 'sólo se pide una vez');
  assert.equal((await state(page))?.net, 'PLAYING');
  ok('Juego abierto directamente: el primer clic pide pantalla completa, una sola vez');
  await page.context().close();
}

await browser.close();
console.log(`Pantalla completa verificada. Capturas en ${OUT}`);
process.exit(0);
