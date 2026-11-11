// Prueba de extremo a extremo del primer hito: cuatro cuentas distintas entran
// desde el portal a la misma sala, cada una en su propio navegador.
// Requiere ALUX corriendo (npm run dev) y usa la "entrada de prueba" del portal.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { chromium, type Browser, type Page } from 'playwright';

const BASE = process.env.E2E_BASE_URL || 'http://localhost:3000';
const SHOTS = process.env.E2E_SHOTS || path.resolve(import.meta.dirname, 'screenshots');
const NAMES = ['Ixchel', 'Balam Kin', 'Nicte', 'Chaac'];
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const logs: string[] = [];
let diagnose: () => Promise<void> = async () => {};

interface GameState {
  net: string; room: string; me: string; slot: number; gate: boolean; plates: number; need: number; form: string; fps: number; rejoins: number;
  players: { id: string; slot: number; name: string; on: boolean; form: string; x: number; y: number; z: number }[];
}
const state = (page: Page) => page.evaluate(() => (window as any).__aluxState as GameState | undefined);

async function waitFor<T>(what: string, fn: () => Promise<T | false | undefined | null>, timeoutMs = 60_000): Promise<T> {
  const end = Date.now() + timeoutMs;
  for (;;) {
    const v = await fn();
    if (v) return v;
    if (Date.now() > end) throw new Error(`Tiempo agotado esperando: ${what}`);
    await sleep(250);
  }
}

async function main() {
  fs.mkdirSync(SHOTS, { recursive: true });
  const browser: Browser = await chromium.launch({
    args: [
      '--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist',
      // Sin esto Chromium pausa las pestañas que considera en segundo plano y el juego deja de avanzar
      '--disable-renderer-backgrounding', '--disable-backgrounding-occluded-windows', '--disable-background-timer-throttling',
    ],
  });
  const errors: string[] = [];
  const pages: Page[] = [];
  diagnose = async () => {
    for (let i = 0; i < pages.length; i++) {
      const info = await pages[i].evaluate(() => JSON.stringify({ state: (window as any).__aluxState, alux: (window as any).ALUX })).catch((e) => String(e));
      console.error(`  ${NAMES[i]}: ${info.slice(0, 600)}`);
    }
    if (logs.length) console.error('  Consola reciente:\n   ' + logs.slice(-15).join('\n   '));
  };

  // 1) Cuatro cuentas, cuatro navegadores (contextos aislados: cookies separadas)
  for (let i = 0; i < 4; i++) {
    const ctx = await browser.newContext({ viewport: { width: 480, height: 300 } });
    const page = await ctx.newPage();
    page.on('pageerror', (e) => errors.push(`[${NAMES[i]}] ${e.message}`));
    page.on('console', (m) => {
      if (/Godot Engine|OpenGL API|Build configuration/.test(m.text())) return;
      logs.push(`[${NAMES[i]}] ${m.type()}: ${m.text().slice(0, 300)}`);
      if (logs.length > 60) logs.shift();
    });
    pages.push(page);
    await page.goto(BASE);
    await page.fill('#dev-name', NAMES[i]);
    await Promise.all([page.waitForURL('**/hub'), page.click('.dev-login button')]);
  }
  console.log('✓ 4 cuentas con sesión en el portal');

  // 2) La primera personaliza su alux y crea una sala privada
  const host = pages[0];
  await host.click('.swatch[aria-label="#e4007c"]');
  await host.click('.hats .chip:nth-child(2)');
  await host.click('text=Guardar alux');
  await host.waitForSelector('.saved:has-text("Guardado")');
  await host.click('text=Crear sala privada');
  const code = (await host.textContent('.room-code'))!.trim();
  assert.match(code, /^[A-Z0-9]{6}$/);
  console.log(`✓ Sala privada ${code} creada`);

  // 3) El enlace de invitación lleva al juego (y exige sesión)
  const anon = await (await browser.newContext()).newPage();
  await anon.goto(`${BASE}/play/${code}`);
  assert.ok(new URL(anon.url()).searchParams.get('next') === `/play/${code}`, 'sin sesión debe volver a la portada');
  await anon.context().close();
  await pages[1].goto(`${BASE}/play/${code}`);
  assert.ok(pages[1].url().includes(`/game/index.html?room=${code}`), 'la invitación abre el juego');

  // 4) Los cuatro entran a la misma sala
  await Promise.all(pages.map((p) => p.goto(`${BASE}/game/index.html?room=${code}&debug=1&q=low`)));
  const states = await Promise.all(pages.map((p, i) =>
    waitFor(`${NAMES[i]} jugando con 4 aluxes`, async () => {
      const s = await state(p);
      return s && s.net === 'PLAYING' && s.players.length === 4 && s.players.every((q) => q.on) ? s : false;
    }, 120_000)));
  assert.deepEqual(new Set(states.map((s) => s.slot)), new Set([0, 1, 2, 3]), 'cada quien tiene su lugar');
  assert.equal(new Set(states.map((s) => s.me)).size, 4, 'cuatro identidades distintas');
  for (const s of states) {
    assert.equal(s.room, code);
    assert.deepEqual(s.players.map((p) => p.name).sort(), [...NAMES].sort());
  }
  await waitFor('el acertijo pide 4 altares', async () => (await Promise.all(pages.map(state))).every((s) => s!.need === 4), 15_000);
  console.log(`✓ Los 4 están en la sala ${code} (fps: ${states.map((s) => Math.round(s.fps)).join(', ')})`);

  // 5) Cada uno ve los movimientos de los demás
  const hostSlot = states[0].slot;
  const before = states[1].players.find((p) => p.slot === hostSlot)!;
  await host.click('#canvas');
  await host.keyboard.down('KeyW');
  await sleep(1800);
  await host.keyboard.up('KeyW');
  await sleep(900);
  const own = (await state(host))!.players.find((p) => p.slot === hostSlot)!;
  const movedOwn = Math.hypot(own.x - before.x, own.z - before.z);
  assert.ok(movedOwn > 3, `la anfitriona debería haber caminado (se movió ${movedOwn.toFixed(2)} m)`);
  for (let i = 1; i < 4; i++) {
    const seen = (await state(pages[i]))!.players.find((p) => p.slot === hostSlot)!;
    const diff = Math.hypot(seen.x - own.x, seen.z - own.z);
    assert.ok(diff < 0.3, `${NAMES[i]} ve a la anfitriona a ${diff.toFixed(2)} m de donde ella se ve`);
  }
  console.log(`✓ Todos ven el movimiento (${movedOwn.toFixed(1)} m)`);

  // 6) Transformación sincronizada
  await pages[1].click('#canvas');
  await pages[1].keyboard.press('Digit2');
  const slot1 = states[1].slot;
  await waitFor('los demás ven a Balam', async () => {
    const all = await Promise.all(pages.map(state));
    return all.every((s) => s!.players.find((p) => p.slot === slot1)!.form === 'balam');
  }, 15_000);
  console.log('✓ La transformación en Balam se ve en los 4 navegadores');
  await sleep(600);
  await host.screenshot({ path: path.join(SHOTS, 'cuatro-aluxes-calidad-baja.png') });

  // 7) Se cae la red de una jugadora: el juego se reconecta solo y conserva lugar y posición
  const dropped = pages[3];
  const droppedBefore = (await state(dropped))!;
  const posBefore = droppedBefore.players.find((p) => p.id === droppedBefore.me)!;
  await dropped.context().setOffline(true);
  await waitFor('los demás la ven desconectada (corte de red)', async () =>
    (await state(host))!.players.find((p) => p.id === droppedBefore.me)?.on === false, 30_000);
  await dropped.context().setOffline(false);
  const again = await waitFor('se reconecta sola', async () => {
    const s = await state(dropped);
    return s && s.net === 'PLAYING' && s.rejoins >= 1 && s.players.length === 4 ? s : false;
  }, 60_000);
  const posAfter = again.players.find((p) => p.id === again.me)!;
  assert.equal(again.me, droppedBefore.me, 'misma identidad');
  assert.equal(again.slot, droppedBefore.slot, 'mismo lugar');
  assert.ok(Math.hypot(posAfter.x - posBefore.x, posAfter.z - posBefore.z) < 0.05, 'misma posición');
  await waitFor('los demás la ven de vuelta', async () => (await state(host))!.players.find((p) => p.id === again.me)?.on === true, 15_000);
  console.log('✓ Corte de red: reconexión automática con el mismo lugar y posición');

  // 8) Cerrar la pestaña y volver a entrar: misma identidad
  const leaver = pages[2];
  const leaverBefore = (await state(leaver))!;
  const t0 = Date.now();
  await leaver.goto('about:blank');
  await waitFor('los demás la ven desconectada', async () => {
    const s = await state(host);
    return s!.players.find((p) => p.id === leaverBefore.me)?.on === false;
  }, 15_000);
  await leaver.bringToFront();
  await leaver.goto(`${BASE}/game/index.html?room=${code}&debug=1&q=low`);
  const back = await waitFor('vuelve a la sala', async () => {
    const s = await state(leaver);
    return s && s.net === 'PLAYING' && s.players.length === 4 ? s : false;
  }, 240_000);
  assert.equal(back.me, leaverBefore.me, 'misma identidad');
  await waitFor('los demás la ven de vuelta', async () => (await state(host))!.players.find((p) => p.id === back.me)?.on === true, 15_000);
  console.log(`✓ Cerrar y volver a abrir el juego conserva la identidad (${Math.round((Date.now() - t0) / 1000)} s con recarga completa)`);

  // 9) Un quinto jugador no cabe
  const fifthCtx = await browser.newContext();
  const fifth = await fifthCtx.newPage();
  await fifth.goto(BASE);
  await fifth.fill('#dev-name', 'Quinto');
  await Promise.all([fifth.waitForURL('**/hub'), fifth.click('.dev-login button')]);
  const res = await fifth.evaluate(async (c) => {
    const r = await fetch(`/api/v1/rooms/${c}/ticket`, { method: 'POST', headers: { 'x-alux-csrf': '1' } });
    return { status: r.status, body: await r.json() };
  }, code);
  assert.equal(res.status, 409);
  assert.equal(res.body.error, 'room_full');
  console.log('✓ El quinto jugador es rechazado (sala llena)');

  assert.deepEqual(errors, [], 'errores de JavaScript en las páginas');
  await browser.close();
  console.log(`\nPrimer hito verificado. Capturas en ${SHOTS}`);
}

main().catch(async (err) => {
  console.error('\n✗ ' + (err?.message ?? err));
  await diagnose();
  process.exit(1);
});
