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
// (desde la Alpha 0.4 el botón JUGAR abre el juego dentro de la página de la sala, para
// conservar la pantalla completa; el resto de la prueba lo abre directamente con depuración)
await page.click('button.enter');
await page.waitForURL(`**/play/${code}`, { timeout: 60_000 });
await page.waitForSelector('iframe.play-frame');
assert.ok((await page.getAttribute('iframe.play-frame', 'src'))!.includes(`/game/index.html?room=${code}`), 'JUGAR abre el juego de esa sala');
await page.goto(`${BASE}/game/index.html?room=${code}&debug=1&q=${QUALITY}`);
await waitFor('el juego conecta', async () => (await state(page))?.net === 'PLAYING', 300_000);

// 2b) Introducción del capítulo: cinemática dentro del motor, con franjas y subtítulos
await waitFor('cinemática de introducción', async () => (await state(page) as any)?.cine === 'llamado', 30_000);
let s: any = await state(page);
assert.equal(s.ui.cine, true, 'la interfaz entra en modo cine');
assert.equal(s.ui.intro, false, 'la bienvenida espera a que termine la cinemática');
const before0 = s.players[0];
await page.keyboard.down('KeyW');
await sleep(1500);
await page.keyboard.up('KeyW');
s = await state(page);
assert.ok(Math.hypot(s.players[0].x - before0.x, s.players[0].z - before0.z) < 0.3, 'durante la cinemática el personaje no camina');
assert.equal(s.cine, 'llamado', 'las teclas de juego no la interrumpen');
await shot(page, '01a-cinematica.png');
await page.keyboard.press('Enter');
await waitFor('cinemática omitida', async () => (await state(page) as any)?.cine === '', 30_000);
ok('Introducción «El llamado»: se reproduce, deja quieto al personaje y se omite con Enter');

await waitFor('bienvenida visible', async () => (await ui(page)).intro === true, 30_000);
s = await state(page);
assert.equal(s.encounter, 0);
assert.match(s.ui.objective, /Habla con Chiich Yaxché/, 'el primer objetivo es narrativo');
await shot(page, '01-bienvenida.png');
ok('Bienvenida con objetivo y controles; el personaje no se mueve mientras está abierta');

// 3) Empezar con Enter; el aviso inicial se va solo
await page.keyboard.press('Enter');
await waitFor('bienvenida cerrada', async () => (await ui(page)).intro === false, 30_000);
await shot(page, '02-explorar.png');
ok('Enter cierra la bienvenida');
// Audio: no basta con que el juego diga que reproduce; el mezclador mide lo que sale por la salida
await waitFor('ambiente y música sonando', async () => {
  const m = ((await state(page)) as any).snd;
  return m?.music === 'mus_claro' && (m.loops || []).includes('amb_selva') && m.rms > 0.0005;
}, 30_000);
s = await state(page);
assert.equal(s.music, 'mus_claro');
assert.deepEqual(s.snd.errors, [], 'sin errores de carga de audio');
ok(`Audio: música «${s.snd.music}» y ${s.snd.loops.length} capas de ambiente sonando; nivel medido en la salida ${(20 * Math.log10(s.snd.rms)).toFixed(0)} dBFS`);

// 3b) Primer objetivo narrativo: hablar con la abuela del claro
assert.equal(s.story, 0, 'nadie ha hablado todavía con ella');
assert.ok(await driveTo(page, -3.6, 2.0, { timeoutMs: 120_000, stop: 1.2 }), 'llega junto a Chiich Yaxché');
await waitFor('a distancia de hablar', async () => (await state(page) as any).npc_near === true, 30_000);
await page.keyboard.press('KeyF');
await waitFor('diálogo abierto', async () => (await ui(page)).dialog === true, 30_000);
await shot(page, '02a-dialogo.png');
const where = (await state(page))!.players[0];
await page.keyboard.down('KeyW');
await sleep(1200);
await page.keyboard.up('KeyW');
const still = (await state(page))!.players[0];
assert.ok(Math.hypot(still.x - where.x, still.z - where.z) < 0.3, 'mientras habla, el personaje no camina');
for (let i = 0; i < 40 && (await ui(page)).dialog; i++) {
  await page.keyboard.press('Enter');
  await sleep(350);
}
assert.equal((await ui(page)).dialog, false, 'el diálogo termina');
await waitFor('el servidor anota que ya habló', async () => ((await state(page) as any).story & 1) === 1, 30_000);
s = await state(page);
assert.match(s.ui.objective, /Pisa un altar/, 'tras hablar, el objetivo pasa a los altares');
await shot(page, '02b-mision.png');
ok('Diálogo con Chiich Yaxché: F abre, Enter avanza, el servidor anota el avance y el objetivo cambia a los altares');

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
// La sala se pausa en cuanto se pisa el cuarto altar, así que la cinemática se vigila mientras camina
const drive = driveTo(page, 17.5, -5, { timeoutMs: 240_000, stop: 0.9 });

// 5b) Cinemática compartida «El sello cede»: todos la ven, la sala está en pausa y se omite por mayoría
await waitFor('cinemática compartida', async () => (await state(page) as any).cine === 'sello', 240_000);
s = await state(page);
assert.equal(s.frozen, true, 'la sala está en pausa');
assert.equal(s.gate, true);
assert.equal(s.wave, 8);
// Se vota enseguida: la escena dura 7 s y en este entorno una captura puede tardar más que eso
await page.keyboard.press('Enter');
await waitFor('voto contado o escena terminada', async () => {
  const st: any = await state(page);
  return st.skip_votes === 1 || st.frozen === false;
}, 30_000);
s = await state(page);
if (s.frozen) {
  assert.equal(s.cine, 'sello', 'un voto de cuatro no la omite');
  await page.screenshot({ path: path.join(OUT, '05a-cinematica-sello.png'), timeout: 180_000 });
  cast.slice(0, 2).forEach((a) => a.ws.send(JSON.stringify({ t: 'skip' })));
} else {
  console.log('  (la escena terminó por su duración antes de poder completar la votación)');
}
await waitFor('fin de la cinemática', async () => (await state(page) as any).frozen === false && (await state(page) as any).cine === '', 30_000);
assert.ok(await drive, 'la jugadora termina de llegar a su altar');
await waitFor('emboscada en curso', async () => (await state(page))?.encounter === 1, 60_000);
timers.forEach(clearInterval);   // (los compañeros siguen dando señales de vida hasta que empiezan a pelear)
ok('Cinemática compartida: pausa la sala, un voto de cuatro no basta y con tres se omite');

s = await state(page);
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
// Los compañeros siguen dando señales de vida mientras se miran el panel y las recompensas
const keepAlive = cast.map((a) => a.idle(0, 1));
await waitFor('panel de victoria', async () => (await ui(page)).result === true, 60_000);
s = await state(page);
assert.equal(s.encounter, 2);
assert.match(s.ui.objective, /Entra al santuario/, 'el objetivo invita a seguir: el guardián espera dentro');
assert.equal(s.ui.captured, false, 'el ratón queda libre para pulsar los botones');
assert.ok(s.stats.kills + s.stats.purified >= 8, `el resumen cuenta las 8 bajas (${s.stats.kills} + ${s.stats.purified})`);
// Progresión RPG: jugar el Claro da experiencia y semillas (las pone la API), y se ve en pantalla
await waitFor('recompensa del Claro en pantalla', async () => ((await state(page) as any).rpg?.xp ?? 0) >= 150 + 8 * 15, 30_000);
s = await state(page);
assert.ok(s.rpg.seeds >= 75 + 8 * 5, `semillas por el Claro y las ocho criaturas (${s.rpg.seeds})`);
assert.match(s.rpg.hud.level, /NIVEL [3-9]/, `con ${s.rpg.xp} de experiencia ya subió de nivel (${s.rpg.hud.level})`);
assert.equal(s.rpg.hud.open, true);
const earned = { xp: s.rpg.xp, seeds: s.rpg.seeds, level: s.rpg.hud.level };
await shot(page, '06-victoria.png');
ok(`Progresión: ${earned.xp} de experiencia y ${earned.seeds} semillas por jugar el Claro; el HUD marca «${earned.level}»`);
ok(`Victoria: panel con resumen (${Math.round(s.stats.secs)} s, ${s.stats.kills} vencidos, ${s.stats.purified} purificadas, ${s.stats.falls} caídas)`);

// 6b) El guardián duerme en el patio; en cuanto un compañero entra, despierta para todos
keepAlive.forEach(clearInterval);
s = await state(page);
if (s.boss !== undefined) {
  assert.equal(s.boss[0], 0, 'con la emboscada recién superada, el guardián sigue dormido');
  assert.equal(s.boss_glb, true, 'el guardián se ve con su modelo');
  assert.equal(s.boss_bar, false, 'dormido no muestra barra');
  const alive = cast.slice(1).map((a) => a.idle(0, 1));
  await cast[0].walkTo(19.5, 0, 'alux', 25);
  // (al pisar el patio la sala se pausa para la cinemática: el compañero termina de entrar cuando acaba)
  const entering = cast[0].walkTo(25.5, 0, 'alux', 60);
  await waitFor('el guardián despierta', async () => (await state(page) as any).boss[0] === 1, 30_000);
  // Su despertar es una cinemática compartida: se ve (con el motor si no hay vídeo) y se omite por mayoría
  await waitFor('cinemática «El despertar»', async () => (await state(page) as any).cine === 'despertar', 60_000);
  assert.equal(((await state(page)) as any).frozen, true, 'la sala está en pausa durante el despertar');
  await shot(page, '06a-cinematica-despertar.png');
  cast.forEach((a) => a.ws.send(JSON.stringify({ t: 'skip' })));
  await waitFor('fin de «El despertar»', async () => (await state(page) as any).frozen === false && (await state(page) as any).cine === '', 60_000);
  await entering;
  const stay = cast[0].idle(1, 0);
  await waitFor('barra de Silencio', async () => (await state(page) as any).boss_bar === true, 15_000);
  s = await state(page);
  assert.match(s.ui.objective, /glifos del guardián/, 'el objetivo explica qué hacer con él');
  assert.equal(s.boss[6], 100, 'su Silencio está entero');
  await shot(page, '06b-jefe-despierta.png');
  [...alive, stay].forEach(clearInterval);
  ok(`Jefe: Nojoch Tuunich duerme en el patio y despierta para todos cuando entra un compañero (glifos ${s.boss[7]}/${s.boss[8]}, barra de Silencio en pantalla)`);
}

// 7) Otra ronda: hace falta el voto de todos (se pide con su botón; Enter sólo cierra el panel)
await page.evaluate(() => { (window as any).ALUX_ACTION = 'again'; });
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
// Sola, la emboscada puede acabar con ella en segundos y la fase de derrota dura poco: un testigo
// dentro de la página anota lo que pasa aunque esta prueba consulte despacio.
await page.evaluate(() => {
  const w = window as any;
  w.__seen = { wave: 0, defeat: false, gate: null, objective: '' };
  setInterval(() => {
    const st = w.__aluxState;
    if (!st) return;
    if (st.encounter === 1) w.__seen.wave = Math.max(w.__seen.wave, st.wave);
    if (st.encounter === 3 && !w.__seen.defeat) w.__seen = { ...w.__seen, defeat: true, gate: st.gate, objective: st.ui.objective };
  }, 50);
});
const seen = () => page.evaluate(() => (window as any).__seen);
const walk = { stop: false };
const toAltar = driveTo(page, 17.5, -5, { timeoutMs: 180_000, stop: 0.9, cancel: walk });
await waitFor('segunda emboscada', async () => (await seen()).wave > 0, 180_000);
walk.stop = true;
await toAltar;
assert.equal((await seen()).wave, 3, 'sola aparecen tres enemigos');
const fight = { stop: false };
const toFight = driveTo(page, 15, 0, { timeoutMs: 60_000, stop: 1.5, cancel: fight });
await waitFor('derrota', async () => (await seen()).defeat === true, 180_000);
fight.stop = true;
await toFight;
await waitFor('panel de derrota', async () => (await ui(page)).result === true, 60_000);
const lost = await seen();
assert.equal(lost.gate, false, 'el santuario se vuelve a sellar');
assert.match(lost.objective, /Derrota/);
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
await page.evaluate(() => { (window as any).ALUX_ACTION = 'exit'; });   // botón «Salir al portal»
await page.waitForURL('**/hub', { timeout: 60_000 });
await page.screenshot({ path: path.join(OUT, '10-portal-de-vuelta.png') });
ok('Salir al portal desde el menú');

// 11) El ciclo completo de la progresión: con las semillas ganadas se compra un amuleto en el
//     Puesto de Saberes de Mérida, se equipa y su efecto se ve al volver a una sala
{
  const me0 = await page.evaluate(async () => (await (await fetch('/api/v1/me')).json()).rpg);
  assert.ok(me0.seeds >= 80, `lo ganado quedó guardado en el perfil (${me0.seeds} semillas, nivel ${me0.level})`);
  await page.goto(`${BASE}/plaza?debug=1&q=min&fs=0`);
  const plaza = () => page.frames().find((f) => f.url().includes('mode=plaza'));
  const zs = async (): Promise<any> => plaza()?.evaluate(() => (window as any).__aluxState).catch(() => undefined);
  const act = (v: string) => plaza()!.evaluate((x) => { (window as any).ALUX_ACTION = x; }, v);
  await waitFor('dentro de la plaza', async () => (await zs())?.net === 'PLAYING', 300_000);
  await act('shop');
  await waitFor('el puesto abre con el perfil', async () => (await zs())?.shop?.rpg?.level >= 1 && (await zs()).shop.catalog === true && !(await zs()).shop.busy, 60_000);
  let shop = (await zs()).shop;
  assert.deepEqual([shop.rpg.seeds, shop.rpg.level, shop.rpg.items.length], [me0.seeds, me0.level, 0]);
  await act('shop:buy:amulet:semilla_ceiba');
  await waitFor('amuleto comprado', async () => (await zs()).shop.rpg.items.length === 1 && !(await zs()).shop.busy, 60_000);
  shop = (await zs()).shop;
  assert.equal(shop.rpg.seeds, me0.seeds - 80, 'el amuleto común cuesta 80 semillas');
  assert.equal(shop.rpg.stats.hp, me0.stats.hp, 'sin equipar todavía no hace nada');
  await act('shop:equip:0');
  await waitFor('amuleto equipado', async () => (await zs()).shop.rpg.equipped !== null && !(await zs()).shop.busy, 60_000);
  shop = (await zs()).shop;
  const hp = Math.round(me0.stats.hp * 1.02);
  assert.equal(shop.rpg.stats.hp, hp, 'común de vida: +2 % sobre la vida de su nivel');
  await sleep(1500);
  await page.screenshot({ path: path.join(OUT, '11-puesto-de-saberes.png'), timeout: 180_000 });
  // No alcanza para algo más caro: el puesto no lo regala
  await act('shop:buy:amulet:espejo_obsidiana');
  await waitFor('compra rechazada', async () => (await zs()).shop.ok === false && !(await zs()).shop.busy, 60_000);
  assert.equal((await zs()).shop.rpg.items.length, 1);
  // Y se nota en una sala: la vida máxima es la del amuleto
  const room2 = await page.evaluate(async () => (await (await fetch('/api/v1/rooms', { method: 'POST', headers: { 'content-type': 'application/json', 'x-alux-csrf': '1' }, body: '{}' })).json()).code);
  await page.goto(`${BASE}/game/index.html?room=${room2}&debug=1&q=${QUALITY}`);
  await waitFor('la sala nueva', async () => (await state(page))?.net === 'PLAYING', 300_000);
  await waitFor('vida máxima con el amuleto', async () => (await state(page) as any).rpg?.hp_max === hp, 30_000);
  s = await state(page);
  assert.equal(s.hp, hp, 'entra con la vida llena, ya con el amuleto');
  ok(`Ciclo completo: ${me0.seeds} semillas ganadas jugando → amuleto «Semilla de ceiba» comprado (quedan ${shop.rpg.seeds}) → equipado → ${hp} de vida máxima en la sala (antes ${me0.stats.hp})`);
}

// (el 402 es la compra que el paso 11 hace rechazar a propósito: «no te alcanzan las semillas»)
const bad = errors.filter((e) => !/favicon|WebGL|GPU stall|swiftshader|deprecated|status of 402/i.test(e));
if (bad.length) console.log('Errores de consola:\n  ' + bad.slice(0, 8).join('\n  '));
assert.equal(bad.length, 0, 'sin errores en la consola del navegador');
await browser.close();
console.log(`Flujo de playtest verificado. Capturas en ${OUT}`);
process.exit(0);
