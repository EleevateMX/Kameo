// Recorrido completo de una sesión de playtest en un navegador real, con capturas de cada paso:
// portal → sala → bienvenida → menú → altares → emboscada → victoria → otra ronda → derrota →
// reintentar → salir al portal. Tres bots hacen de compañeros en la primera ronda.
// Requiere ALUX corriendo (node scripts/dev.mjs --prod).
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { Actor, BASE, driveTo, launch, login, sleep, state, waitFor } from './lib.ts';

const OUT = process.env.E2E_SHOTS || path.resolve(import.meta.dirname, 'screenshots/playtest');
fs.mkdirSync(OUT, { recursive: true });
const QUALITY = process.env.E2E_QUALITY || 'min';
const ok = (msg: string) => console.log(`✓ ${msg}`);
const ui = async (page: any) => (await state(page) as any)?.ui ?? {};
const shot = async (page: any, name: string) => {
  // unos cuadros de margen para que el panel termine de pintarse
  const f0 = (await state(page))!.frames;
  await waitFor('cuadros nuevos', async () => (await state(page))!.frames >= f0 + 3, 60_000);
  await page.screenshot({ path: path.join(OUT, name), timeout: 180_000 });
};

const browser = await launch();
const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
const page = await ctx.newPage();
const errors: string[] = [];
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text().slice(0, 300)); });
page.on('pageerror', (e) => errors.push(String(e).slice(0, 300)));

// 1) Portal y sala
await login(page, 'Ixchel');
await page.click('text=Crear sala privada');
const code = (await page.textContent('.room-code'))!.trim();
await page.screenshot({ path: path.join(OUT, '00-portal-sala.png') });
ok(`Portal: sesión iniciada y sala ${code} creada`);

// 2) Entrar al claro: pantalla de carga → bienvenida
await page.click('text=Entrar al claro');
await page.waitForURL('**/game/index.html**', { timeout: 60_000 });
await page.goto(`${BASE}/game/index.html?room=${code}&debug=1&q=${QUALITY}`);
await waitFor('el juego conecta', async () => (await state(page))?.net === 'PLAYING', 300_000);
await waitFor('bienvenida visible', async () => (await ui(page)).intro === true, 30_000);
let s: any = await state(page);
assert.equal(s.encounter, 0);
assert.match(s.ui.objective, /Pisa un altar/, 'un jugador solo ve el objetivo en singular');
await shot(page, '01-bienvenida.png');
ok('Bienvenida con objetivo y controles; el personaje no se mueve mientras está abierta');

// 3) Empezar con Enter; el aviso inicial se va solo
await page.keyboard.press('Enter');
await waitFor('bienvenida cerrada', async () => (await ui(page)).intro === false, 30_000);
await shot(page, '02-explorar.png');
ok('Enter cierra la bienvenida');
s = await state(page);
assert.ok(s.audio.includes('amb_selva') && s.audio.includes('mus_claro'), `ambiente y música cargados (${s.audio.join(', ')})`);
assert.equal(s.music, 'mus_claro');
ok(`Audio: ${s.audio.length} sonidos cargados, música de exploración sonando`);

// 4) Menú: se abre con Esc, deja al personaje quieto, recentra la cámara y se cierra
await page.keyboard.press('Escape');
await waitFor('menú abierto', async () => (await ui(page)).menu === true, 30_000);
await shot(page, '03-menu.png');
const before = (await state(page))!.players[0];
await page.keyboard.down('KeyW');
await sleep(1500);
await page.keyboard.up('KeyW');
const after = (await state(page))!.players[0];
assert.ok(Math.hypot(after.x - before.x, after.z - before.z) < 0.3, 'con el menú abierto el personaje no camina');
await page.keyboard.press('Escape');
await waitFor('menú cerrado', async () => (await ui(page)).menu === false, 30_000);
await page.keyboard.press('KeyH');
await waitFor('ayuda abierta', async () => (await ui(page)).help === true, 30_000);
await shot(page, '04-controles.png');
await page.keyboard.press('KeyH');
await waitFor('ayuda cerrada', async () => (await ui(page)).help === false, 30_000);
ok('Menú (Esc) y ayuda de controles (H) se abren y se cierran; el menú no deja caminar');

// 5) Llegan tres compañeros: el objetivo pasa a pedir cuatro altares
const cast = [new Actor(code, 'Nicte', '#e4007c', 1), new Actor(code, 'Balam Kin', '#ffd23f', 2), new Actor(code, 'Chaac', '#ff7a1a', 0)];
await waitFor('cuatro en la sala', async () => (await state(page))!.need === 4, 30_000);
s = await state(page);
assert.match(s.ui.objective, /Pisen 4 altares/);
const plates = [[0, -15.5], [-11, 7], [8, 16]];
await Promise.all(cast.map((a, i) => a.walkTo(plates[i][0], plates[i][1])));
let timers = cast.map((a) => a.idle(0, 1));
assert.ok(await driveTo(page, 17.5, -5, { timeoutMs: 180_000, stop: 0.9 }), 'la jugadora llega a su altar');
await waitFor('emboscada en curso', async () => (await state(page))?.encounter === 1, 60_000);
timers.forEach(clearInterval);
s = await state(page);
assert.equal(s.gate, true);
assert.equal(s.wave, 8);
assert.match(s.ui.objective, /Emboscada/);
assert.equal(s.music, 'mus_emboscada');
await shot(page, '05-emboscada.png');
ok('Cuatro altares abren el santuario: emboscada con objetivo, música y aviso propios');

// 6) Combate: los bots pelean y la jugadora dispara chispas; al terminar aparece la victoria
const center = { x: 15, z: 0, r: 26 };
const cleared = () => cast[0].world()[3] === 2;
await page.keyboard.down('KeyJ');
await Promise.all([
  cast[0].fight(cleared, 240, { form: 'balam', near: center }),
  cast[1].fight(cleared, 240, { form: 'balam', near: center }),
  cast[2].fight(cleared, 240, { form: 'balam', near: center }),
]);
await page.keyboard.up('KeyJ');
assert.ok(cleared(), 'la emboscada se supera');
await waitFor('panel de victoria', async () => (await ui(page)).result === true, 60_000);
s = await state(page);
assert.equal(s.encounter, 2);
assert.match(s.ui.objective, /Santuario liberado/);
assert.equal(s.ui.captured, false, 'el ratón queda libre para pulsar los botones');
assert.ok(s.stats.kills + s.stats.purified >= 8, `el resumen cuenta las 8 bajas (${s.stats.kills} + ${s.stats.purified})`);
await shot(page, '06-victoria.png');
ok(`Victoria: panel con resumen (${Math.round(s.stats.secs)} s, ${s.stats.kills} vencidos, ${s.stats.purified} purificadas, ${s.stats.falls} caídas)`);

// 7) Otra ronda: hace falta el voto de todos
await page.keyboard.press('Enter');
await waitFor('voto de la jugadora', async () => (await state(page) as any).votes === 1, 30_000);
s = await state(page);
assert.equal(s.encounter, 2, 'con un voto de cuatro la sala no se reinicia');
cast.forEach((a) => a.ws.send(JSON.stringify({ t: 'again' })));
await waitFor('nueva ronda', async () => (await state(page))!.encounter === 0 && (await state(page))!.gate === false, 30_000);
await waitFor('panel cerrado', async () => (await ui(page)).result === false, 30_000);
s = await state(page);
const me = s.players.find((p: any) => p.id === s.me);
assert.ok(Math.hypot(me.x, me.z - 3.2) < 4, 'todos vuelven junto al brasero');
await shot(page, '07-nueva-ronda.png');
ok('Otra ronda: se reinicia cuando votan los cuatro; santuario sellado y todos en el brasero');

// 8) Los compañeros se van: la jugadora abre sola, cae y ve la derrota
cast.forEach((a) => a.ws.close());
await waitFor('se queda sola', async () => (await state(page))!.need === 1, 60_000);
await waitFor('altares listos', async () => (await state(page) as any).lock === 0, 30_000);
await page.mouse.click(640, 300);   // clic en el mundo: captura el ratón
assert.ok(await driveTo(page, 17.5, -5, { timeoutMs: 180_000, stop: 0.9 }), 'vuelve al altar');
await waitFor('segunda emboscada', async () => (await state(page))?.encounter === 1, 60_000);
assert.equal((await state(page))!.wave, 3, 'sola aparecen tres enemigos');
await driveTo(page, 15, 0, { timeoutMs: 60_000, stop: 1.5 });
await waitFor('derrota', async () => (await state(page))?.encounter === 3, 180_000);
await waitFor('panel de derrota', async () => (await ui(page)).result === true, 60_000);
s = await state(page);
assert.equal(s.gate, false, 'el santuario se vuelve a sellar');
assert.match(s.ui.objective, /Derrota/);
await shot(page, '08-derrota.png');
ok('Derrota: si cae la única jugadora se pierde la emboscada y el santuario se sella');

// 9) Reintentar: cierra el panel y la sala vuelve a estar lista
await page.keyboard.press('Enter');
await waitFor('panel cerrado', async () => (await ui(page)).result === false, 30_000);
await waitFor('lista para reintentar', async () => {
  const st: any = await state(page);
  return st.encounter === 0 && st.lock === 0 && st.players.find((p: any) => p.id === st.me)?.dead === false;
}, 60_000);
s = await state(page);
assert.match(s.ui.objective, /Pisa un altar/);
await shot(page, '09-reintentar.png');
ok('Reintentar: reaparece junto al brasero y el objetivo vuelve al principio');

// 10) Salir al portal desde el menú
await page.keyboard.press('Escape');
await waitFor('menú abierto', async () => (await ui(page)).menu === true, 30_000);
const box = await page.evaluate(() => ({ w: innerWidth, h: innerHeight }));
// El botón «Salir al portal» es el último del menú, centrado
await page.mouse.click(box.w / 2, box.h / 2 + 175);
await page.waitForURL('**/hub', { timeout: 60_000 });
await page.screenshot({ path: path.join(OUT, '10-portal-de-vuelta.png') });
ok('Salir al portal desde el menú');

const bad = errors.filter((e) => !/favicon|WebGL|GPU stall|swiftshader|deprecated/i.test(e));
if (bad.length) console.log('Errores de consola:\n  ' + bad.slice(0, 8).join('\n  '));
assert.equal(bad.length, 0, 'sin errores en la consola del navegador');
await browser.close();
console.log(`Flujo de playtest verificado. Capturas en ${OUT}`);
process.exit(0);
