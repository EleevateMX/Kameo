// El camino completo de la Alpha 0.4 contra un despliegue, con un navegador real y UNA cuenta:
// portal → personalizador 3D → plaza de Mérida → portal → sala del Claro de los Aluxes.
//
//   E2E_BASE_URL=https://alux-beta.onrender.com E2E_INVITES=ALUX-… npx tsx e2e/beta-plaza.ts
//
// Comprueba que cada paso funciona por HTTPS/WSS reales y que el aspecto elegido llega a la plaza
// y a la sala. Al terminar deja el alux como estaba. Con una sola cuenta no puede comprobar que
// dos personas se vean: eso lo hace e2e/plaza.ts (dos navegadores) contra la imagen local.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import type { Frame, Page } from 'playwright';
import { BASE, launch, sleep, waitFor } from './lib.ts';

const code = (process.env.E2E_INVITES || '').split(',')[0]?.trim();
if (!code) { console.error('Falta E2E_INVITES con una invitación.'); process.exit(1); }
const OUT = path.resolve(import.meta.dirname, 'screenshots/beta-plaza');
fs.mkdirSync(OUT, { recursive: true });
const ok = (msg: string) => console.log(`✓ ${msg}`);
const frameOf = (page: Page, what: string): Frame | undefined => page.frames().find((f) => f.url().includes(what));
const st = async (page: Page, what: string): Promise<any> => frameOf(page, what)?.evaluate(() => (window as any).__aluxState).catch(() => undefined);
const set = (page: Page, what: string, key: string, value: string) => frameOf(page, what)!.evaluate(([k, v]) => { (window as any)[k] = v; }, [key, value]);
const api = (page: Page, method: string, url: string, body?: unknown) => page.evaluate(async ([m, u, b]) => {
  const r = await fetch(u as string, { method: m as string, headers: { 'content-type': 'application/json', 'x-alux-csrf': '1' }, body: b ? JSON.stringify(b) : undefined });
  return r.json();
}, [method, url, body] as const);

const browser = await launch();
const page = await (await browser.newContext({ viewport: { width: 1280, height: 720 } })).newPage();
const wsUrls: string[] = [];
page.on('websocket', (ws) => wsUrls.push(ws.url()));
let original: any = null;
let failed = false;
try {
  // ── 1) Portal ──
  await page.goto(BASE);
  await page.fill('#beta-code', code);
  await Promise.all([page.waitForURL('**/hub'), page.click('.beta-login button')]);
  original = (await api(page, 'GET', '/api/v1/me')).character;
  assert.equal(await page.getAttribute('a.look-3d', 'href'), '/alux', 'el portal ofrece el personalizador 3D');
  assert.equal(await page.getAttribute('a.plaza', 'href'), '/plaza', 'el portal ofrece la plaza');
  ok(`Portal: sesión con invitación; ofrece «Personalizar en 3D» e «Ir a la plaza» (alux «${original.name}»)`);

  // ── 2) Personalizador 3D ──
  await page.goto(`${BASE}/alux?debug=1&q=min`);
  await waitFor('el personalizador se abre', async () => (await st(page, 'mode=alux'))?.custom?.active === true, 300_000);
  const start = (await st(page, 'mode=alux')).custom;
  const hat = start.hat === 5 ? 4 : 5, color = start.color === '#8f5bd6' ? '#ffd23f' : '#8f5bd6';
  for (const cmd of [`hat:${hat}`, `color:${color}`, 'accent:6']) { await set(page, 'mode=alux', 'ALUX_CUSTOM', cmd); await sleep(1000); }
  await sleep(1500);
  await page.screenshot({ path: path.join(OUT, '01-personalizador.png') });
  await set(page, 'mode=alux', 'ALUX_CUSTOM', 'save');
  await waitFor('guardado', async () => /^Guardado/.test((await st(page, 'mode=alux')).custom.status), 30_000);
  const saved = (await api(page, 'GET', '/api/v1/me')).character;
  assert.deepEqual([saved.hat, saved.color, saved.look.accent], [hat, color, 6], 'el perfil guarda lo elegido');
  ok(`Personalizador 3D: modelo real con ${start.parts.length} piezas visibles; tocado ${hat}, color ${color} y secundario 6 guardados en el perfil`);

  // ── 3) Plaza de Mérida ──
  await page.goto(`${BASE}/plaza?debug=1&q=min&fs=0`);
  await waitFor('dentro de la plaza', async () => (await st(page, 'mode=plaza'))?.net === 'PLAYING', 300_000);
  let s = await st(page, 'mode=plaza');
  assert.equal(s.zone, 'merida');
  assert.deepEqual([s.me.hat, s.me.color], [hat, color], 'el servidor de zonas trae el aspecto del perfil');
  const zoneWs = wsUrls.find((u) => /\/zone/.test(u));
  assert.ok(zoneWs, `la plaza no abrió su WebSocket (abiertos: ${wsUrls.join(', ')})`);
  if (BASE.startsWith('https://')) assert.match(zoneWs!, /^wss:\/\//);
  const from = { x: s.me.x, z: s.me.z };
  await set(page, 'mode=plaza', 'ALUX_ZONE_GOTO', '9,22');
  await waitFor('anda por la plaza', async () => { const m = (await st(page, 'mode=plaza')).me; return Math.hypot(m.x - 9, m.z - 22) < 1.0; }, 90_000);
  s = await st(page, 'mode=plaza');
  await page.mouse.click(400, 400);
  await waitFor('música de la plaza', async () => { const m = (await st(page, 'mode=plaza')).snd; return m.ctx === 'running' && m.music === 'mus_lobby' && m.rms > 0.0005; }, 60_000);
  await sleep(1500);
  await page.screenshot({ path: path.join(OUT, '02-plaza.png') });
  // Con el menú abierto el alux no anda: si quedó abierto, se cierra
  if ((await st(page, 'mode=plaza')).ui.menu) { await set(page, 'mode=plaza', 'ALUX_ACTION', 'menu'); await sleep(600); }
  ok(`Plaza de Mérida por ${zoneWs}: el alux aparece con su aspecto, anduvo ${Math.hypot(s.me.x - from.x, s.me.z - from.z).toFixed(1)} m (movimiento del servidor) y suena «mus_lobby» · aforo ${s.cap}`);

  // ── 4) Portal al Claro ──
  await set(page, 'mode=plaza', 'ALUX_ZONE_GOTO', '28.6,0');
  await waitFor('junto al portal', async () => (await st(page, 'mode=plaza')).portal === true, 120_000);
  await sleep(800);
  assert.match((await st(page, 'mode=plaza')).prompt, /Claro de los Aluxes/);
  await page.screenshot({ path: path.join(OUT, '03-portal.png') });
  await set(page, 'mode=plaza', 'ALUX_ACTION', 'portal');
  await waitFor('la página pasa a una sala', async () => /\/play\/[A-Z0-9]{6}/.test(page.url()), 60_000);
  const room = /\/play\/([A-Z0-9]{6})/.exec(page.url())![1];
  await waitFor('la sala del Claro está en marcha', async () => (await st(page, `room=${room}`))?.net === 'PLAYING', 300_000);
  const r = await st(page, `room=${room}`);
  assert.deepEqual([r.players[0].hat, r.players[0].color], [hat, color], 'entra al Claro con el aspecto elegido');
  const gameWs = wsUrls.find((u) => /\/ws/.test(u));
  assert.ok(gameWs, 'la sala no abrió el WebSocket del servidor de mazmorras');
  await page.mouse.click(640, 360);
  await page.keyboard.press('Enter');
  await waitFor('suena el Claro', async () => { const m = (await st(page, `room=${room}`)).snd; return m && m.ctx === 'running' && m.rms > 0.0005; }, 60_000);
  await sleep(1500);
  await page.screenshot({ path: path.join(OUT, '04-claro.png') });
  ok(`Portal → sala ${room} del Claro de los Aluxes por ${gameWs}: en marcha, con el aspecto elegido y con sonido (${r.build ?? 'sin etiqueta'})`);
} catch (err) {
  failed = true;
  console.log(`✗ ${(err as Error).message.split('\n')[0]}`);
  await page.screenshot({ path: path.join(OUT, 'fallo.png') }).catch(() => {});
} finally {
  // Se deja el alux como estaba
  if (original) {
    await page.goto(`${BASE}/hub`).catch(() => {});
    const back = await api(page, 'PUT', '/api/v1/me/character', original).catch(() => null);
    console.log(back?.character ? `  (alux restaurado: «${back.character.name}»)` : '  (no se pudo restaurar el alux)');
  }
  await browser.close();
}
console.log(failed ? 'El camino de la Alpha 0.4 falló.' : `Camino completo verificado. Capturas en ${OUT}`);
process.exit(failed ? 1 : 0);
