// Capturas a calidad alta: un navegador real + tres bots colocados en escena.
// Requiere ALUX corriendo en modo desarrollo (usa el secreto de tickets de desarrollo).
import { randomUUID } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';
import { DEV_SECRETS, GAME_TICKET_AUDIENCE, signJwt } from '@alux/shared-contracts';

const BASE = process.env.E2E_BASE_URL || 'http://localhost:3000';
const WS = process.env.E2E_WS_URL || 'ws://localhost:9080';
const OUT = process.env.E2E_SHOTS || path.resolve(import.meta.dirname, 'screenshots');
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
fs.mkdirSync(OUT, { recursive: true });

class Actor {
  ws: WebSocket;
  seq = 0;
  slot = -1;
  pos = { x: 0, z: 0 };
  constructor(room: string, name: string, color: string, hat: number) {
    const ticket = signJwt({ aud: GAME_TICKET_AUDIENCE, sub: randomUUID(), jti: randomUUID(), room, name, color, hat, forms: ['alux', 'balam'] }, DEV_SECRETS.GAME_TICKET_SECRET, 60);
    this.ws = new WebSocket(WS);
    this.ws.onopen = () => this.ws.send(JSON.stringify({ t: 'hello', v: 1, ticket }));
    this.ws.onmessage = (ev) => {
      const m = JSON.parse(String(ev.data));
      if (m.t === 'welcome') this.slot = m.slot;
      if (m.t === 'snap') {
        const me = m.p.find((p: number[]) => p[0] === this.slot);
        if (me) this.pos = { x: me[3], z: me[5] };
      }
    };
  }
  send(mx: number, mz: number, f = '', j = 0) { this.ws.send(JSON.stringify({ t: 'in', s: ++this.seq, mx, mz, j, f })); }
  async walkTo(x: number, z: number, f = '') {
    for (let i = 0; i < 400; i++) {
      const dx = x - this.pos.x, dz = z - this.pos.z, d = Math.hypot(dx, dz);
      if (d < 0.3) break;
      this.send(dx / d, dz / d, i === 0 ? f : '');
      await sleep(33);
    }
  }
  /** Se queda quieto mirando hacia (dx, dz) y mantiene viva la conexión. */
  idle(dx: number, dz: number) {
    this.send(dx * 0.06, dz * 0.06);
    return setInterval(() => this.send(0, 0), 500);
  }
}

const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 }, deviceScaleFactor: 2 });
const page = await ctx.newPage();
await page.goto(BASE);
await page.screenshot({ path: path.join(OUT, 'portada.png') });
await page.fill('#dev-name', 'Ixchel');
await Promise.all([page.waitForURL('**/hub'), page.click('.dev-login button')]);
await page.click('.swatch[aria-label="#19b4d6"]');
await page.click('text=Guardar alux');
await page.waitForSelector('.saved:has-text("Guardado")');
await page.click('text=Crear sala privada');
const code = (await page.textContent('.room-code'))!.trim();
await page.waitForTimeout(500);
await page.screenshot({ path: path.join(OUT, 'centro-de-jugadores.png') });

// El juego se renderiza a tamaño normal (sin duplicar píxeles) para que el render por software alcance
const game = await (await browser.newContext({ viewport: { width: 1280, height: 720 }, storageState: await ctx.storageState() })).newPage();
await game.goto(`${BASE}/game/index.html?room=${code}&debug=1`);
await game.waitForFunction(() => (window as any).__aluxState?.net === 'PLAYING', null, { timeout: 180_000 });

const cast = [
  new Actor(code, 'Nicte', '#e4007c', 1),
  new Actor(code, 'Balam Kin', '#ffd23f', 2),
  new Actor(code, 'Chaac', '#ff7a1a', 0),
];
await sleep(1500);
await Promise.all([cast[0].walkTo(0.4, -3.4), cast[1].walkTo(-3.4, -1.6, 'balam'), cast[2].walkTo(5.2, -2.2)]);
const timers = [cast[0].idle(0.2, 1), cast[1].idle(0.8, 0.6), cast[2].idle(-0.5, 1)];
await sleep(6000);
await game.screenshot({ path: path.join(OUT, 'juego-cuatro-aluxes.png') });

// Segunda toma: los cuatro altares activos y el santuario abriéndose
const plates = [[0, -15.5], [-11, 7], [8, 16]];
await Promise.all(cast.map((a, i) => a.walkTo(plates[i][0], plates[i][1])));
timers.forEach(clearInterval);
const keep = cast.map((a) => a.idle(0, 1));
await game.click('#canvas');
await game.keyboard.down('KeyE');
await sleep(2300);
await game.keyboard.up('KeyE');
await sleep(6000);
await game.screenshot({ path: path.join(OUT, 'juego-altares.png') });
keep.forEach(clearInterval);
await browser.close();
console.log(`Capturas guardadas en ${OUT}`);
process.exit(0);
