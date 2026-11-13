// Prueba de extremo a extremo del primer hito: cuatro cuentas distintas entran
// desde el portal a la misma sala, cada una en su propio navegador.
// Requiere ALUX corriendo (npm run dev) y usa la "entrada de prueba" del portal.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import type { Browser, Page } from 'playwright';
import { BASE, driveTo, launch, login, lookAt, sleep, state, waitFor } from './lib.ts';

const SHOTS = process.env.E2E_SHOTS || path.resolve(import.meta.dirname, 'screenshots');
const NAMES = ['Ixchel', 'Balam Kin', 'Nicte', 'Chaac'];
const QUALITY = process.env.E2E_GPU === '1' ? '' : '&q=min';
const logs: string[] = [];
let diagnose: () => Promise<void> = async () => {};

async function main() {
  fs.mkdirSync(SHOTS, { recursive: true });
  const browser: Browser = await launch();
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
    const ctx = await browser.newContext({ viewport: { width: 400, height: 240 } });
    const page = await ctx.newPage();
    page.on('pageerror', (e) => errors.push(`[${NAMES[i]}] ${e.message}`));
    page.on('console', (m) => {
      if (/Godot Engine|OpenGL API|Build configuration/.test(m.text())) return;
      logs.push(`[${NAMES[i]}] ${m.type()}: ${m.text().slice(0, 300)}`);
      if (logs.length > 60) logs.shift();
    });
    pages.push(page);
    await login(page, NAMES[i]);
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
  // (desde la Alpha 0.4 el juego se abre dentro de la propia página de la invitación)
  await pages[1].waitForSelector('iframe.play-frame');
  assert.ok((await pages[1].getAttribute('iframe.play-frame', 'src'))!.includes(`/game/index.html?room=${code}`), 'la invitación abre el juego');

  // 4) Los cuatro entran a la misma sala
  await Promise.all(pages.map((p) => p.goto(`${BASE}/game/index.html?room=${code}&debug=1&cine=0${QUALITY}`)));
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
  console.log(`✓ Los 4 están en la sala ${code} (fps: ${states.map((s) => Math.round(s.perf.fps)).join(', ')})`);

  // 5) Cada uno ve los movimientos de los demás
  const hostSlot = states[0].slot;
  const before = states[1].players.find((p) => p.slot === hostSlot)!;
  await host.click('#canvas', { timeout: 180_000, noWaitAfter: true });
  await host.keyboard.down('KeyW');
  const own = await waitFor('la anfitriona camina 3 m', async () => {
    const me = (await state(host))!.players.find((p) => p.slot === hostSlot)!;
    return Math.hypot(me.x - before.x, me.z - before.z) > 3 ? me : false;
  }, 120_000);
  await host.keyboard.up('KeyW');
  const movedOwn = Math.hypot(own.x - before.x, own.z - before.z);
  await waitFor('los demás la ven donde ella se ve', async () => {
    const mine = (await state(host))!.players.find((p) => p.slot === hostSlot)!;
    const others = await Promise.all(pages.slice(1).map(state));
    return others.every((s) => {
      const seen = s!.players.find((p) => p.slot === hostSlot)!;
      return Math.hypot(seen.x - mine.x, seen.z - mine.z) < 0.3;
    });
  }, 60_000);
  console.log(`✓ Todos ven el movimiento (${movedOwn.toFixed(1)} m)`);

  // 6) Transformación sincronizada
  await pages[1].click('#canvas', { timeout: 180_000, noWaitAfter: true });
  await pages[1].keyboard.press('Digit2');
  const slot1 = states[1].slot;
  await waitFor('los demás ven a Balam', async () => {
    const all = await Promise.all(pages.map(state));
    return all.every((s) => s!.players.find((p) => p.slot === slot1)!.form === 'balam');
  }, 15_000);
  console.log('✓ La transformación en Balam se ve en los 4 navegadores');
  await sleep(600);
  await host.screenshot({ path: path.join(SHOTS, 'cuatro-aluxes-calidad-baja.png') });

  // 6b) Combate sincronizado: la anfitriona busca al guardián de piedra del noreste y pelea con él.
  //     Cada navegador acumula el daño que le comunica el servidor; los cuatro totales deben coincidir.
  await host.click('#canvas', { timeout: 180_000, noWaitAfter: true });
  // Camina como alux y se transforma al llegar: sin tarjeta gráfica el navegador va a 1–2 cuadros
  // por segundo y, con la velocidad de Balam, frenar a metro y medio de un punto era cuestión de suerte.
  assert.ok(await driveTo(host, 14.5, -14.5, { timeoutMs: 150_000, stop: 1.8 }), 'la anfitriona llega cerca del guardián');
  await host.keyboard.press('Digit2');  // como Balam: garras en arco y salto con daño en área
  await waitFor('la anfitriona se transforma', async () => (await state(host))!.form === 'balam', 30_000);
  const hostState = async () => (await state(host))!;
  const hostPos = async () => { const s = await hostState(); return s.players.find((p) => p.id === s.me)!; };
  const foe = (await hostState()).enemies.filter((e) => e.kind === 'piedra').sort((a, b) => Math.hypot(a.x - 14.5, a.z + 14.5) - Math.hypot(b.x - 14.5, b.z + 14.5))[0];
  const hostKey = String((await hostState()).slot);
  await host.keyboard.down('KeyJ');
  await waitFor('la anfitriona daña al guardián y recibe un golpe', async () => {
    const s = await hostState();
    const now = s.enemies.find((e) => e.id === foe.id);
    if (now) await lookAt(host, await hostPos(), now);
    await host.keyboard.press('KeyF');  // salto del jaguar cuando esté disponible
    return (s.dmg_enemies[String(foe.id)] ?? 0) > 0 && (s.dmg_players[hostKey] ?? 0) > 0;
  }, 180_000);
  await host.keyboard.up('KeyJ');
  // Se retira hacia la plaza para que el combate se calme y los totales dejen de cambiar
  await driveTo(host, 2, -2, { timeoutMs: 120_000, stop: 2.5 });
  // Los eventos de combate llegan una sola vez: quien se reconecta a mitad (en este entorno sin GPU
  // una página puede congelarse más de 15 s) se pierde los de ese hueco, pero no el estado.
  // Por eso los totales por eventos se comparan entre quienes no se reconectaron…
  const sig = (s: Awaited<ReturnType<typeof state>>) => JSON.stringify([Object.entries(s!.dmg_enemies).sort(), Object.entries(s!.dmg_players).sort()]);
  const steady = await waitFor('quienes no se reconectaron acumulan exactamente el mismo daño', async () => {
    const all = await Promise.all(pages.map(state));
    const same = all.filter((s, i) => s!.rejoins === states[i].rejoins);
    if (same.length < 3) throw new Error('demasiadas reconexiones durante el combate para comparar');
    const again = await Promise.all(pages.map(state));
    const ok = same.every((s) => sig(s) === sig(same[0])) && again.filter((s, i) => s!.rejoins === states[i].rejoins).every((s) => sig(s) === sig(same[0]));
    return ok && (same[0]!.dmg_enemies[String(foe.id)] ?? 0) > 0 && (same[0]!.dmg_players[hostKey] ?? 0) > 0 ? same : false;
  }, 120_000);
  console.log(`✓ Combate sincronizado: ${steady.length} navegadores ven ${steady[0]!.dmg_enemies[String(foe.id)]} de daño al guardián y ${steady[0]!.dmg_players[hostKey]} a la anfitriona`);
  // …y la vida (estado autoritativo) debe coincidir en los cuatro, se hayan reconectado o no
  await waitFor('los 4 ven la misma vida de la anfitriona y del guardián', async () => {
    const all = await Promise.all(pages.map(state));
    const hp = all.map((s) => Math.ceil(s!.players.find((p) => String(p.slot) === hostKey)!.hp));
    const foeHp = all.map((s) => s!.enemies.find((e) => e.id === foe.id)?.hp ?? -1);
    return Math.max(...hp) - Math.min(...hp) <= 2 && Math.max(...foeHp) - Math.min(...foeHp) <= 2;
  }, 120_000);
  console.log('✓ Los 4 navegadores coinciden en la vida de la anfitriona y del guardián');
  await host.screenshot({ path: path.join(SHOTS, 'combate-calidad-baja.png') });

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

  // 8) Un quinto jugador no cabe
  const fifthCtx = await browser.newContext();
  const fifth = await fifthCtx.newPage();
  await login(fifth, 'Quinto');
  const res = await fifth.evaluate(async (c) => {
    const r = await fetch(`/api/v1/rooms/${c}/ticket`, { method: 'POST', headers: { 'x-alux-csrf': '1' } });
    return { status: r.status, body: await r.json() };
  }, code);
  assert.equal(res.status, 409);
  assert.equal(res.body.error, 'room_full');
  console.log('✓ El quinto jugador es rechazado (sala llena)');

  // 9) Cerrar la pestaña y volver a entrar: misma identidad.
  //    (Dos de las otras ventanas se cierran antes: ya cumplieron su papel y, sin GPU, cuatro juegos a la
  //    vez hacen que la recarga tarde varios minutos en compilar shaders.)
  await pages[1].context().close();
  await pages[3].context().close();
  const leaver = pages[2];
  const leaverBefore = (await state(leaver))!;
  const t0 = Date.now();
  await leaver.goto('about:blank');
  await waitFor('los demás la ven desconectada', async () => {
    const s = await state(host);
    return s!.players.find((p) => p.id === leaverBefore.me)?.on === false;
  }, 15_000);
  await leaver.bringToFront();
  await leaver.goto(`${BASE}/game/index.html?room=${code}&debug=1&cine=0${QUALITY}`);
  const back = await waitFor('vuelve a la sala', async () => {
    const s = await state(leaver);
    return s && s.net === 'PLAYING' && s.players.some((p) => p.id === leaverBefore.me && p.on) ? s : false;
  }, 300_000);
  assert.equal(back.me, leaverBefore.me, 'misma identidad');
  await waitFor('los demás la ven de vuelta', async () => (await state(host))!.players.find((p) => p.id === back.me)?.on === true, 15_000);
  console.log(`✓ Cerrar y volver a abrir el juego conserva la identidad (${Math.round((Date.now() - t0) / 1000)} s con recarga completa)`);

  assert.deepEqual(errors, [], 'errores de JavaScript en las páginas');
  await browser.close();
  console.log(`\nPartida cooperativa de 4 jugadores verificada. Capturas en ${SHOTS}`);
}

main().catch(async (err) => {
  console.error('\n✗ ' + (err?.message ?? err));
  await diagnose();
  process.exit(1);
});
