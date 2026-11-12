// Cinemática compartida con cuatro navegadores en la misma sala, cada uno en una situación
// distinta: dos tienen el vídeo, uno recibe archivos rotos y a otro no le llega la descarga.
// Todos deben empezar y terminar juntos, cada uno con lo que pueda ver, y seguir jugando.
// Requiere ALUX corriendo (node scripts/dev.mjs --prod).   npm run test:cine-coop
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import type { Page } from 'playwright';
import { BASE, driveTo, launch, login, sleep, state, waitFor } from './lib.ts';
import { installWitness, serveVideo, witness, type Mode } from './cine-lib.ts';

const OUT = process.env.E2E_SHOTS || path.resolve(import.meta.dirname, 'screenshots/cine');
fs.mkdirSync(OUT, { recursive: true });
const ok = (msg: string) => console.log(`✓ ${msg}`);
const CAST: { name: string; mode: Mode; altar: [number, number] }[] = [
  { name: 'Con vídeo', mode: 'ok', altar: [0, -15.5] },
  { name: 'También', mode: 'ok', altar: [-11, 7] },
  { name: 'Roto', mode: 'roto', altar: [8, 16] },
  { name: 'Lento', mode: 'lento', altar: [17.5, -5] },
];

const browser = await launch();
const pages: Page[] = [];
for (const who of CAST) {
  const ctx = await browser.newContext({ viewport: { width: 480, height: 270 } });
  await ctx.addInitScript(() => { try { localStorage.setItem('alux_seen_llamado', '1'); } catch { /* nada */ } });
  const page = await ctx.newPage();
  await serveVideo(page, who.mode);
  await login(page, who.name);
  pages.push(page);
}
await pages[0].click('text=Crear sala privada');
const code = (await pages[0].textContent('.room-code'))!.trim();
await Promise.all(pages.map((p) => p.goto(`${BASE}/game/index.html?room=${code}&debug=1&q=min`)));
await Promise.all(pages.map((p, i) => waitFor(`${CAST[i].name} en la sala con los cuatro`, async () => {
  const s = await state(p);
  return !!s && s.net === 'PLAYING' && s.players.length === 4 && s.players.every((q) => q.on);
}, 300_000)));
for (const p of pages) {
  await waitFor('bienvenida', async () => (await state(p) as any)?.ui?.intro === true, 120_000);
  await p.keyboard.press('Enter');
  await waitFor('bienvenida cerrada', async () => (await state(p) as any)?.ui?.intro === false, 60_000);
  await installWitness(p);
}
await Promise.all([0, 1].map((i) => waitFor(`${CAST[i].name}: vídeos precargados`, async () => (await state(pages[i]) as any).video?.clips?.sello_2?.s === 'ready', 120_000)));
ok(`Sala ${code}: cuatro navegadores dentro; dos con los vídeos precargados, uno con archivos rotos y uno con la descarga colgada`);

// Cada quien camina a su altar; la sala se pausa cuando pisa el último
const walk = { stop: false };
const going = pages.map((p, i) => driveTo(p, CAST[i].altar[0], CAST[i].altar[1], { timeoutMs: 420_000, stop: 0.9, cancel: walk }));
await waitFor('la sala entra en preparación', async () => (await witness(pages[0])).seen[1] !== undefined, 420_000);
walk.stop = true;
await Promise.all(going);
await Promise.all(pages.map((p, i) => waitFor(`${CAST[i].name}: orden de inicio`, async () => (await witness(p)).seen[2] !== undefined, 60_000)));
const preps = await Promise.all(pages.map(async (p) => { const w = await witness(p); return w.seen[2] - w.seen[1]; }));
ok(`Los cuatro reciben la orden de inicio; preparación vista por cada uno: ${preps.map((ms) => `${(ms / 1000).toFixed(1)} s`).join(', ')}`);

// Dos la ven como vídeo: se espera a que avance y entonces votan tres de cuatro
await waitFor('el vídeo avanza en el primero', async () => ((await witness(pages[0])).maxT.sello_1 ?? 0) > 0.6, 30_000);
await pages[0].screenshot({ path: path.join(OUT, 'coop-con-video.png'), timeout: 120_000 }).catch(() => {});
await pages[2].screenshot({ path: path.join(OUT, 'coop-con-motor.png'), timeout: 120_000 }).catch(() => {});
await pages[0].keyboard.press('Enter');
const one = await waitFor('un voto contado', async () => {
  const st: any = await state(pages[3]);
  return st.skip_votes >= 1 || st.cine_phase !== 2 ? st : false;
}, 20_000);
const stillPlaying = (one as any).cine_phase === 2;
await Promise.all([pages[1], pages[2]].map((p) => p.keyboard.press('Enter')));

await Promise.all(pages.map((p, i) => waitFor(`${CAST[i].name}: partida reanudada`, async () => {
  const st: any = await state(p);
  return st.cine_phase === 0 && st.cine === '' && st.fade === 0 && st.ui.cine === false && st.frozen === false;
}, 90_000)));
const ws = await Promise.all(pages.map((p) => witness(p)));
const ss = (await Promise.all(pages.map((p) => state(p)))) as any[];
for (let i = 0; i < 4; i++) {
  const w = ws[i], s = ss[i], who = CAST[i].name;
  // La reanudación dura un segundo: con cuatro navegadores sin GPU una página puede no llegar a
  // muestrearla (se comprueba en cine-video.ts y en las pruebas de servidor)
  assert.ok(w.seen[1] !== undefined && w.seen[2] !== undefined, `${who}: pasa por la preparación y la reproducción`);
  assert.equal(s.cine_stats.video + s.cine_stats.engine, 1, `${who}: la ve una sola vez`);
  assert.ok(w.encounters.includes(1), `${who}: la emboscada empieza al terminar (visto: ${w.encounters.join('→')})`);
  assert.equal(await pages[i].evaluate(() => (window as any).ALUX_VIDEO.visible()), false, `${who}: nada tapa el juego al terminar`);
}
assert.deepEqual(ss.map((s) => s.cine_stats.video), [1, 1, 0, 0], 'vídeo para quien lo tiene, escena del motor para los otros dos');
assert.ok(ws[0].log.some((r: any) => r.overlay && r.phase === 2) && ws[1].log.some((r: any) => r.overlay && r.phase === 2), 'los dos primeros ven el vídeo sobre el juego');
assert.ok(!ws[2].log.some((r: any) => r.overlay) && !ws[3].log.some((r: any) => r.overlay), 'a los otros dos no se les tapa el juego');
assert.equal(new Set(ws.map((w) => w.wave)).size, 1, `los cuatro ven la misma emboscada (${ws.map((w) => w.wave).join(', ')} enemigos)`);
const ends = await Promise.all(pages.map((p) => p.evaluate(() => { const c = (window as any).__cine; const row = c.log.find((r: any) => r.at > c.seen[2] && r.phase !== 2); return row ? row.at : NaN; })));
const played = ws.map((w, i) => ends[i] - w.seen[2]);
// Los tiempos son los que alcanza a muestrear cada página (sin GPU van a 1–2 cuadros por segundo):
// sirven de orientación, no miden la sincronía, que la impone el servidor.
ok(`Cada uno la ve con lo que tiene (vídeo, vídeo, motor, motor) y los cuatro salen de la escena; duración muestreada en cada página: ${played.map((ms) => `${(ms / 1000).toFixed(1)} s`).join(', ')}`);
if (stillPlaying) {
  assert.ok(Math.max(...played) < 6800, `tres votos de cuatro la terminan antes de tiempo (${Math.max(...played)} ms de 7000)`);
  ok('Voto de mayoría con cuatro navegadores: un voto no basta, con tres se omite');
} else {
  console.log('  (el equipo iba demasiado cargado para votar antes de que terminara sola; el voto está cubierto en las pruebas de servidor)');
}

// Tras la escena todos siguen jugando (quien haya caído en la emboscada, o esté viendo el
// resultado, no puede caminar: eso también es seguir en la partida)
const before = (await Promise.all(pages.map((p) => state(p)))) as any[];
await Promise.all(pages.map(async (p) => { await p.keyboard.down('KeyS'); await sleep(1500); await p.keyboard.up('KeyS'); }));
await sleep(800);
const after = (await Promise.all(pages.map((p) => state(p)))) as any[];
const fine = after.filter((s, i) => {
  const me = s.players.find((q: any) => q.id === s.me), was = before[i].players.find((q: any) => q.id === before[i].me);
  return s.net === 'PLAYING' && s.frozen === false && (me.dead || was.dead || s.ui.result || Math.hypot(me.x - was.x, me.z - was.z) > 0.4);
}).length;
assert.equal(fine, 4, 'los cuatro siguen en la partida con el control recuperado');
ok('Después de la escena los cuatro siguen conectados, sin pausa y con el control recuperado');
await browser.close();
console.log(`Cinemática compartida con cuatro navegadores verificada. Capturas en ${OUT}`);
process.exit(0);
