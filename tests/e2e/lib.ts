// Utilidades compartidas por las pruebas de navegador: bots por WebSocket,
// lectura del estado del juego y conducción del jugador con el teclado.
import { randomUUID } from 'node:crypto';
import { chromium, type Browser, type Page } from 'playwright';
import { DEV_SECRETS, ENEMY_STATES, GAME_TICKET_AUDIENCE, PROTOCOL_VERSION, signJwt } from '@alux/shared-contracts';

export const BASE = process.env.E2E_BASE_URL || 'http://localhost:3000';
export const WS = process.env.E2E_WS_URL || 'ws://localhost:9080';
export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export interface GameState {
  net: string; room: string; me: string; slot: number; gate: boolean; plates: number; need: number; form: string;
  hp: number; energy: number; encounter: number; wave: number; frames: number; rejoins: number; glb: boolean;
  players: { id: string; slot: number; name: string; on: boolean; form: string; dead: boolean; hp: number; x: number; y: number; z: number }[];
  enemies: { id: number; kind: string; hp: number; state: string; x: number; z: number }[];
  dmg_enemies: Record<string, number>; dmg_players: Record<string, number>; quality: string;
  perf: { fps: number; ping: number; snaps: number; mem: number; heap: number; draws: number; enemies: number };
}

export const state = (page: Page) => page.evaluate(() => (window as any).__aluxState as GameState | undefined);

export async function waitFor<T>(what: string, fn: () => Promise<T | false | undefined | null>, timeoutMs = 60_000): Promise<T> {
  const end = Date.now() + timeoutMs;
  for (;;) {
    const v = await fn();
    if (v) return v;
    if (Date.now() > end) throw new Error(`Tiempo agotado esperando: ${what}`);
    await sleep(250);
  }
}

export function launch(): Promise<Browser> {
  return chromium.launch({
    args: [
      // Render por software para máquinas sin tarjeta gráfica (CI). Con GPU real, quítalos.
      ...(process.env.E2E_GPU === '1' ? [] : ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader']),
      '--ignore-gpu-blocklist',
      // Sólo para probar contra un proxy local con certificado propio (scripts/test-beta-image.sh)
      ...(process.env.E2E_INSECURE_TLS === '1' ? ['--ignore-certificate-errors'] : []),
      // Sin esto Chromium pausa las pestañas que considera en segundo plano y el juego deja de avanzar
      '--disable-renderer-backgrounding', '--disable-backgrounding-occluded-windows', '--disable-background-timer-throttling',
    ],
    headless: process.env.E2E_HEADED !== '1',
  });
}

// Contra un despliegue de beta (sin entrada de prueba) se entra con invitaciones de tester:
// E2E_INVITES="CODIGO1,CODIGO2,…" (una por cuenta que abra la prueba).
const invites = (process.env.E2E_INVITES || '').split(',').map((c) => c.trim()).filter(Boolean);

export async function login(page: Page, name: string) {
  await page.goto(BASE);
  if (invites.length) {
    await page.fill('#beta-code', invites.shift()!);
    await Promise.all([page.waitForURL('**/hub'), page.click('.beta-login button')]);
    // La invitación trae su propio nombre: se pone el que pide la prueba, como haría el tester
    await page.evaluate(async (wanted) => {
      const me = await (await fetch('/api/v1/me')).json();
      await fetch('/api/v1/me/character', {
        method: 'PUT', headers: { 'content-type': 'application/json', 'x-alux-csrf': '1' },
        body: JSON.stringify({ ...me.character, name: wanted }),
      });
    }, name);
    await page.reload();
    return;
  }
  await page.fill('#dev-name', name);
  await Promise.all([page.waitForURL('**/hub'), page.click('.dev-login button')]);
}

/** Orienta la cámara (sólo disponible con ?debug=1) y camina con W hasta llegar a (x, z). */
export async function driveTo(page: Page, x: number, z: number, opts: { timeoutMs?: number; stop?: number; cancel?: { stop: boolean } } = {}) {
  const end = Date.now() + (opts.timeoutMs ?? 60_000);
  let walking = false;
  // Para detectar que se quedó atascado de frente contra un obstáculo y rodearlo
  let mark = { x: NaN, z: NaN, at: Date.now() };
  let side = 'KeyD';
  let last: any = null;
  try {
    while (Date.now() < end) {
      if (opts.cancel?.stop) return false;   // quien llama ya no necesita que llegue
      const s = await state(page);
      const me = s?.players.find((p) => p.id === s.me);
      if (me) {
        last = { x: me.x, z: me.z, dead: me.dead, ui: (s as any).ui, net: s!.net };
        const dx = x - me.x, dz = z - me.z;
        if (Math.hypot(dx, dz) < (opts.stop ?? 0.8)) return true;
        await page.evaluate((yaw) => { (window as any).ALUX_CAM_YAW = yaw; }, Math.atan2(dx, dz));
        if (!walking) { await page.keyboard.down('KeyW'); walking = true; }
        if (!(Math.hypot(me.x - mark.x, me.z - mark.z) < 0.4)) {
          mark = { x: me.x, z: me.z, at: Date.now() };
        } else if (Date.now() - mark.at > 4000 && !me.dead) {
          // lleva 4 s sin avanzar: un paso lateral, como haría una persona, y sigue
          await page.keyboard.down(side);
          await sleep(900);
          await page.keyboard.up(side);
          side = side === 'KeyD' ? 'KeyA' : 'KeyD';
          mark = { x: NaN, z: NaN, at: Date.now() };
        }
      }
      await sleep(120);
    }
    console.log(`driveTo(${x}, ${z}) no llegó. Último estado: ${JSON.stringify(last)}`);
    return false;
  } finally {
    if (walking) await page.keyboard.up('KeyW');
  }
}

export const lookAt = (page: Page, from: { x: number; z: number }, to: { x: number; z: number }) =>
  page.evaluate((yaw) => { (window as any).ALUX_CAM_YAW = yaw; }, Math.atan2(to.x - from.x, to.z - from.z));

/** Bot que habla el protocolo real. Firma su propio ticket con el secreto de desarrollo. */
export class Actor {
  ws: WebSocket;
  id = randomUUID();
  seq = 0;
  slot = -1;
  snap: any = null;
  events: (string | number)[][] = [];
  constructor(room: string, public name: string, color: string, hat: number) {
    const ticket = signJwt({ aud: GAME_TICKET_AUDIENCE, sub: this.id, jti: randomUUID(), room, name, color, hat, forms: ['alux', 'balam'] },
      process.env.GAME_TICKET_SECRET || DEV_SECRETS.GAME_TICKET_SECRET, 60);
    this.ws = new WebSocket(WS);
    this.ws.onopen = () => this.ws.send(JSON.stringify({ t: 'hello', v: PROTOCOL_VERSION, ticket }));
    this.ws.onmessage = (ev) => {
      const m = JSON.parse(String(ev.data));
      if (m.t === 'welcome') this.slot = m.slot;
      if (m.t === 'snap') { this.snap = m; if (m.ev?.length) this.events.push(...m.ev); }
    };
  }
  me(): number[] | undefined { return this.snap?.p.find((p: number[]) => p[0] === this.slot); }
  pos() { const m = this.me(); return m ? { x: m[4], z: m[6] } : { x: 0, z: 0 }; }
  dead() { const m = this.me(); return m ? (m[11] & 8) !== 0 : false; }
  world(): number[] { return this.snap?.w ?? [0, 0, 1, 0, 0, 0, 1]; }
  foes() {
    return ((this.snap?.e ?? []) as number[][])
      .map((e) => ({ id: e[0], kind: e[1], x: e[2], z: e[4], hp: e[6], state: ENEMY_STATES[e[8]] }))
      .filter((e) => e.state !== 'dead');
  }
  send(mx: number, mz: number, extra: { f?: string; a?: number; r?: number; j?: number } = {}) {
    if (this.ws.readyState !== WebSocket.OPEN) return;
    this.ws.send(JSON.stringify({ t: 'in', s: ++this.seq, mx, mz, j: extra.j ?? 0, f: extra.f ?? '', a: extra.a ?? 0, r: extra.r ?? 0 }));
  }
  async walkTo(x: number, z: number, f = '', maxSeconds = 20) {
    const end = Date.now() + maxSeconds * 1000;
    while (Date.now() < end) {
      const p = this.pos();
      const dx = x - p.x, dz = z - p.z, d = Math.hypot(dx, dz);
      if (d < 0.3) return true;
      this.send(dx / d, dz / d, { f });
      await sleep(33);
    }
    return false;
  }
  /** Se queda quieto mirando hacia (dx, dz) y mantiene viva la conexión. */
  idle(dx: number, dz: number) {
    this.send(dx * 0.06, dz * 0.06);
    return setInterval(() => this.send(0, 0), 500);
  }
  /** Pelea contra el enemigo más cercano hasta que `until` sea cierto. `reach` grande = ataca a distancia. */
  async fight(until: () => boolean, maxSeconds: number, opts: { form?: string; reach?: number; near?: { x: number; z: number; r: number }; lazy?: boolean } = {}) {
    const end = Date.now() + maxSeconds * 1000;
    const reach = opts.reach ?? 1.9;
    while (Date.now() < end && !until()) {
      const p = this.pos();
      const foe = this.foes()
        .filter((f) => !opts.near || Math.hypot(f.x - opts.near.x, f.z - opts.near.z) < opts.near.r)
        .sort((a, b) => Math.hypot(a.x - p.x, a.z - p.z) - Math.hypot(b.x - p.x, b.z - p.z))[0];
      if (foe && !this.dead()) {
        const dx = foe.x - p.x, dz = foe.z - p.z, d = Math.hypot(dx, dz) || 1;
        const close = d < reach;
        // `lazy`: ataca sólo a ratos, para que el combate dure (útil para capturas)
        const swing = close && (!opts.lazy || this.seq % 90 < 12);
        this.send(close ? 0 : dx / d, close ? 0 : dz / d, { a: swing ? 1 : 0, r: Math.atan2(dx, dz), f: opts.form ?? '' });
      } else {
        this.send(0, 0, { f: opts.form ?? '' });
      }
      await sleep(33);
    }
    return until();
  }
}
