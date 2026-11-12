// Combate completo contra Nojoch Tuunich en un navegador real, con capturas de cada fase.
// Una jugadora (el navegador) y tres compañeros (bots que hablan el protocolo real) recorren las
// tres fases, las dos cinemáticas del jefe, la entrega de la Pluma de Jade y la pista del Cenote.
// Los bots llevan el peso del combate (en este entorno el navegador pinta a 1–3 FPS); la jugadora
// mira, y en la fase 3 toca al guardián manteniendo F como cualquier otra.
// Requiere ALUX corriendo (node scripts/dev.mjs --prod).
//
//   npx tsx e2e/boss-fight.ts
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { B, BOSS_STATE, bossPhase1, bossPhase2, bossPhase3 } from '../boss-bots.ts';
import { Actor, BASE, driveTo, launch, login, sleep, state, waitFor } from './lib.ts';

const OUT = process.env.E2E_SHOTS || path.resolve(import.meta.dirname, 'screenshots/jefe');
fs.mkdirSync(OUT, { recursive: true });
const QUALITY = process.env.E2E_QUALITY || 'min';
const ok = (msg: string) => console.log(`✓ ${msg}`);
const st = async (page: any) => (await state(page)) as any;
const shot = async (page: any, name: string) => {
  const f0 = (await st(page)).frames;
  await waitFor('cuadros nuevos', async () => (await st(page)).frames >= f0 + 2, 60_000).catch(() => {});
  await page.screenshot({ path: path.join(OUT, name), timeout: 180_000 }).catch((e: unknown) => console.log(`  (sin captura ${name}: ${String(e).slice(0, 80)})`));
};
const look = (page: any, from: { x: number; z: number }, to: { x: number; z: number }) =>
  page.evaluate((yaw: number) => { (window as any).ALUX_CAM_YAW = yaw; }, Math.atan2(to.x - from.x, to.z - from.z));

const browser = await launch();
const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
const page = await ctx.newPage();
const errors: string[] = [];
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text().slice(0, 300)); });
page.on('pageerror', (e) => errors.push(String(e).slice(0, 300)));

// 1) Sala con cuatro: la jugadora y tres compañeros
await login(page, 'Ixchel');
await page.evaluate(() => { try { localStorage.setItem('alux_seen_llamado', '1'); } catch { /* nada */ } });
await page.click('text=Crear sala privada');
const code = (await page.textContent('.room-code'))!.trim();
const t0 = Date.now();
await page.goto(`${BASE}/game/index.html?room=${code}&debug=1&q=${QUALITY}`);
await waitFor('el juego conecta', async () => (await st(page))?.net === 'PLAYING', 300_000);
const loadSecs = (Date.now() - t0) / 1000;
await waitFor('bienvenida', async () => (await st(page))?.ui?.intro === true, 60_000);
await page.keyboard.press('Enter');
await waitFor('bienvenida cerrada', async () => (await st(page))?.ui?.intro === false, 30_000);
const cast = [new Actor(code, 'Nicte', '#e4007c', 1), new Actor(code, 'Balam Kin', '#ffd23f', 2), new Actor(code, 'Chaac', '#ff7a1a', 0)];
cast.forEach((a) => { a.autoSkip = true; });
// Entre fase y fase los bots esperan a la jugadora: dan señales de vida para no perder su sitio
const alive = setInterval(() => cast.forEach((a) => { if (a.ws.readyState === WebSocket.OPEN) a.ws.send('{"t":"ping","c":0}'); }), 2000);
await waitFor('cuatro en la sala', async () => (await st(page)).need === 4, 30_000);
const me = async () => { const s = await st(page); return s.players.find((p: any) => p.id === s.me); };
const mySlot = (await st(page)).slot as number;
ok(`Sala ${code} con cuatro jugadores (carga del juego: ${loadSecs.toFixed(1)} s)`);

// 2) Altares y emboscada (ya cubiertos por otras pruebas: aquí sólo hay que pasarlos)
const plates = [[0, -15.5], [-11, 7], [8, 16]];
await Promise.all(cast.map((a, i) => a.walkTo(plates[i][0], plates[i][1])));
const hold = cast.map((a) => a.idle(0, 1));
await page.mouse.click(640, 300);
const toPlate = driveTo(page, 17.5, -5, { timeoutMs: 300_000, stop: 0.9 });
await waitFor('«El sello cede»', async () => (await st(page)).cine === 'sello' || (await st(page)).encounter === 1, 300_000);
await page.keyboard.press('Enter');
await waitFor('emboscada en curso', async () => (await st(page)).encounter === 1 && (await st(page)).frozen === false, 60_000);
await toPlate;
hold.forEach(clearInterval);
const cleared = () => cast[0].world()[3] === 2;
await page.keyboard.down('KeyJ');
await Promise.all(cast.map((a) => a.fight(cleared, 240, { form: 'balam', near: { x: 15, z: 0, r: 26 } })));
await page.keyboard.up('KeyJ');
assert.ok(cleared(), 'la emboscada se supera');
await waitFor('panel de victoria', async () => (await st(page)).ui.result === true, 60_000);
await page.keyboard.press('Enter');   // «Entrar al santuario»
await waitFor('panel cerrado', async () => (await st(page)).ui.result === false, 30_000);
let s = await st(page);
assert.equal(s.encounter, 2, 'Enter en el panel sigue la aventura: no pide otra ronda');
assert.match(s.ui.objective, /Entra al santuario/);
ok('Emboscada superada; el panel invita a entrar al santuario');

// La jugadora se queda mirando desde la plaza, fuera del alcance del combate
await page.mouse.click(640, 300);
const WATCH = { x: -1.5, z: 3.0 };
const toWatch = driveTo(page, WATCH.x, WATCH.z, { timeoutMs: 300_000, stop: 1.2 });

// 3) Fase 1: un compañero entra al patio, el guardián despierta con su cinemática
const b = () => cast[0].snap?.b as number[];
const phase = () => b()?.[B.phase] ?? 0;
cast.forEach((a) => { a.autoSkip = false; });   // «El despertar» se deja ver antes de votar
const p1 = Promise.all(cast.map((a, i) => bossPhase1(a, i, () => phase() >= 2, 420)));
await waitFor('el guardián despierta', async () => (await st(page)).boss[0] === 1, 120_000);
await waitFor('«El despertar» en pantalla', async () => (await st(page)).cine === 'despertar', 60_000);
assert.equal((await st(page)).frozen, true, 'la sala está en pausa durante el despertar');
// Con sus vídeos descargados, la escena se ve como vídeo (si faltan, con el motor: también vale)
const clips = (await st(page)).video?.clips ?? {};
const have = (id: string) => ['fetched', 'ready', 'playing', 'ended'].includes(clips[id]?.s);
const despertarVideo = [1, 2, 3, 4].every((i) => have(`despertar_${i}`));
if (despertarVideo) await waitFor('«El despertar» como vídeo', async () => (await st(page)).cine_video === true || (await st(page)).cine !== 'despertar', 30_000);
const sawDespertarVideo = (await st(page)).cine_video === true;
await sleep(2500);
await shot(page, '01-cinematica-despertar.png');
cast.forEach((a) => { a.ws.send(JSON.stringify({ t: 'skip' })); a.autoSkip = true; });
await waitFor('fin de «El despertar»', async () => (await st(page)).frozen === false && (await st(page)).cine === '', 60_000);
await waitFor('barra de Silencio', async () => (await st(page)).boss_bar === true, 30_000);
s = await st(page);
assert.match(s.ui.objective, /glifos del guardián/);
assert.equal(s.music, 'mus_jefe', 'música propia del guardián');
if (despertarVideo) assert.equal(sawDespertarVideo, true, 'con los vídeos descargados, «El despertar» se ve como vídeo');
ok(`Fase 1 «Olvido»: despierta para todos con su cinemática (${sawDespertarVideo ? 'vídeo de Kling' : 'versión del motor'}), barra de Silencio y música propia (glifos ${s.boss[7]}/${s.boss[8]})`);
assert.ok((await p1).every(Boolean), 'los compañeros completan la fase 1');
await toWatch;

// 4) Fase 2: sale a la explanada; columnas, embestida, anclas y corazón
const p2 = Promise.all(cast.map((a, i) => bossPhase2(a, i, 4, () => phase() >= 3, 600)));
await waitFor('fase 2 en el navegador', async () => (await st(page)).boss[0] === 2, 60_000);
await look(page, WATCH, { x: 15.5, z: 0 });
await waitFor('el guardián llega a la explanada', async () => (await st(page)).boss[1] < 21 && BOSS_STATE[(await st(page)).boss[4]] !== 'transit', 90_000);
s = await st(page);
assert.equal(s.music, 'mus_jefe_furia', 'la música cambia con la fase');
assert.equal(s.boss[15], 2, 'con cuatro hacen falta dos anclas');
const posBefore = await me();
await shot(page, '02-fase2-explanada.png');
const seen2 = { pillar: false, bound: false, objective: new Set<string>() };
const watch2 = setInterval(async () => {
  const q = await st(page).catch(() => null);
  if (!q?.boss) return;
  seen2.objective.add(String(q.ui.objective).replace(/\(\d\/\d\)/, '').trim());
  if ((q.boss[16] as number[][]).length && !seen2.pillar) { seen2.pillar = true; void shot(page, '03-fase2-columnas.png'); }
  if (BOSS_STATE[q.boss[4]] === 'bound' && !seen2.bound) { seen2.bound = true; void shot(page, '04-fase2-corazon.png'); }
}, 700);
assert.ok((await p2).every(Boolean), `los compañeros completan la fase 2 (corazones ${b()[B.releases]}/3)`);
clearInterval(watch2);
const posAfter = await me();
assert.ok(Math.hypot(posAfter.x - posBefore.x, posAfter.z - posBefore.z) < 1.5, 'a la jugadora nadie la movió de sitio durante la fase');
assert.ok(seen2.pillar && seen2.bound, 'el navegador vio columnas despiertas y el corazón expuesto');
ok(`Fase 2 «Furia»: explanada, columnas, anclas y corazón (objetivos vistos: ${[...seen2.objective].join(' | ')})`);

// 5) Fase 3: los compañeros encienden los glifos; la jugadora se acerca y lo toca con F
const freed = () => phase() === 4;
cast.forEach((a) => { a.autoSkip = false; });   // «La liberación» también se deja ver
const p3 = Promise.all(cast.map((a, i) => bossPhase3(a, i, freed, 600)));
await waitFor('fase 3 en el navegador', async () => (await st(page)).boss[0] === 3, 60_000);
s = await st(page);
assert.equal(s.music, 'mus_recuerdo');
const spot = { x: 15.5 - 4.1, z: 0 };   // el glifo del oeste: fuera del pulso, dentro del contacto
let arrived = false;
for (let attempt = 1; attempt <= 5 && !arrived && !freed(); attempt++) {
  // (en este entorno el navegador a veces pierde el foco del teclado: un clic en el juego lo devuelve)
  await page.mouse.click(640, 300);
  arrived = await driveTo(page, spot.x, spot.z, { timeoutMs: 90_000, stop: 0.7 });
  if (!arrived) {
    const q = await st(page);
    const p = q.players.find((r: any) => r.id === q.me);
    console.log(`  (intento ${attempt}: en ${p.x.toFixed(1)}, ${p.z.toFixed(1)} · vida ${q.hp} · caída ${p.dead} · menú ${q.ui.menu} · ratón ${q.ui.captured} · pausa ${q.frozen} · fps ${q.perf.fps})`);
    if (q.ui.menu) await page.keyboard.press('Escape');
  }
}
assert.ok(arrived, 'la jugadora llega junto al guardián');
await look(page, spot, { x: 15.5, z: 0 });
await shot(page, '05-fase3-ritual.png');
await waitFor('contacto abierto', async () => (await st(page)).boss[19] >= (await st(page)).boss[20] || (await st(page)).boss[0] === 4, 400_000);
await page.keyboard.down('KeyF');
let touched = false;
const watch3 = setInterval(async () => {
  const q = await st(page).catch(() => null);
  if (q?.boss && (q.boss[22] & (1 << mySlot)) !== 0 && !touched) { touched = true; void shot(page, '06-fase3-contacto.png'); }
}, 500);
// Si un golpe la aparta, vuelve a su sitio sin soltar F
const back = setInterval(async () => {
  const p = await me().catch(() => null);
  if (p && !p.dead && Math.hypot(p.x - spot.x, p.z - spot.z) > 1.2 && phase() === 3) await driveTo(page, spot.x, spot.z, { timeoutMs: 20_000, stop: 0.7 });
}, 4000);
await p3;
clearInterval(watch3);
clearInterval(back);
await page.keyboard.up('KeyF');
assert.ok(freed(), `el guardián queda liberado (glifos ${b()[B.lit]}/${b()[B.litNeed]}, contacto ${b()[B.ritual]} %)`);
assert.ok(touched, 'el servidor contó el contacto de la jugadora (mantener F en el navegador)');
ok('Fase 3 «Recuerdo»: glifos del suelo encendidos y contacto de los cuatro, la jugadora incluida');

// 6) Liberación: cinemática, Pluma de Jade guardada y panel de capítulo
await waitFor('«La liberación» en pantalla', async () => (await st(page)).cine === 'liberacion', 60_000);
const liberacionVideo = [1, 2, 3].every((i) => have(`liberacion_${i}`));
if (liberacionVideo) await waitFor('«La liberación» como vídeo', async () => (await st(page)).cine_video === true || (await st(page)).cine !== 'liberacion', 30_000);
const sawLiberacionVideo = (await st(page)).cine_video === true;
await sleep(2500);
await shot(page, '07-cinematica-liberacion.png');
cast.forEach((a) => a.ws.send(JSON.stringify({ t: 'skip' })));
await waitFor('panel de capítulo', async () => (await st(page)).ui.result === true, 120_000);
s = await st(page);
assert.equal(s.boss[0], 4);
assert.equal(s.frozen, false, 'la sala ya no está en pausa');
assert.equal(s.story & 2, 2, 'la liberación queda en la historia de la sala');
await shot(page, '08-capitulo-completado.png');
const profile = await page.evaluate(async () => (await fetch('/api/v1/me')).json());
assert.deepEqual(profile.rewards.filter((r: string) => r === 'pluma_de_jade'), ['pluma_de_jade'], 'la Pluma de Jade queda en el perfil, una sola');
assert.equal(profile.quests.cap1_guardian, 'completed');
if (liberacionVideo) assert.equal(sawLiberacionVideo, true, 'con los vídeos descargados, «La liberación» se ve como vídeo');
assert.equal(s.cine_stats.fallbacks, 0, 'ningún vídeo falló a mitad');
assert.equal(await page.evaluate(() => (window as any).ALUX_VIDEO?.visible?.() ?? false), false, 'ningún vídeo tapa el juego al terminar');
ok(`Liberación: cinemática compartida (${sawLiberacionVideo ? 'vídeo de Kling' : 'versión del motor'}), panel «Capítulo I completado» y Pluma de Jade guardada en el perfil`);

// 7) La pista del Cenote: hablar con el guardián liberado
await page.keyboard.press('Enter');
await waitFor('panel cerrado', async () => (await st(page)).ui.result === false, 30_000);
s = await st(page);
assert.match(s.ui.objective, /Habla con Nojoch Tuunich/);
await page.mouse.click(640, 300);
if (!(await st(page)).npc_near) await driveTo(page, 15.5 - 3.4, 0.4, { timeoutMs: 120_000, stop: 0.8 });
await waitFor('junto al guardián', async () => (await st(page)).npc_near === true, 60_000);
await shot(page, '09-guardian-liberado.png');
await page.keyboard.press('KeyF');
await waitFor('diálogo abierto', async () => (await st(page)).ui.dialog === true, 30_000);
for (let i = 0; i < 8 && (await st(page)).ui.dialog; i++) { await page.keyboard.press('Enter'); await sleep(900); }
await waitFor('pista del Cenote', async () => ((await st(page)).story & 4) === 4, 30_000);
s = await st(page);
assert.match(s.ui.objective, /Capítulo I completado/);
await shot(page, '10-pista-cenote.png');
ok('Pista del Cenote: el guardián liberado habla, el servidor la anota y la brújula marca el camino');

// 8) Rendimiento de este navegador (render por software: sirve para comparar, no como referencia)
s = await st(page);
console.log(`Rendimiento (SwiftShader, calidad ${s.quality}): ${s.perf.fps} FPS · ${s.perf.draws} llamadas de dibujo · ${Math.round(s.perf.mem)} MB estáticos · ping ${Math.round(s.perf.ping)} ms`);
const bad = errors.filter((e) => !/favicon|WebGL|GPU stall|swiftshader|deprecated|Failed to load resource/i.test(e));
if (bad.length) console.log('Errores de consola:\n  ' + bad.slice(0, 8).join('\n  '));
assert.equal(bad.length, 0, 'sin errores en la consola del navegador');
clearInterval(alive);
cast.forEach((a) => a.ws.close());
await browser.close();
console.log(`Combate completo verificado. Capturas en ${OUT}`);
process.exit(0);
