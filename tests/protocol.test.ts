// Prueba de red del servidor dedicado de Godot con bots (sin navegador).
// Arranca el servidor real, conecta jugadores por WebSocket e intenta hacer trampa.
import assert from 'node:assert/strict';
import { spawn, type ChildProcess } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import type { AddressInfo } from 'node:net';
import path from 'node:path';
import { after, before, test } from 'node:test';
import { GAME_TICKET_AUDIENCE, signJwt, type FormId, type RosterEntry, type ServerMessage, type SnapshotPlayer } from '@alux/shared-contracts';

const ROOT = path.resolve(import.meta.dirname, '..');
const GODOT = process.env.GODOT_BIN || path.join(ROOT, '.tools/godot');
const PORT = 19080 + Math.floor(Math.random() * 500);
const SECRET = 'protocol-test-secret-123456';
const SERVICE_KEY = 'protocol-test-service-key';
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

let godot: ChildProcess;
let fakeApi: http.Server;
const rewardCalls: any[] = [];
const heartbeats: any[] = [];
let serverLog = '';

function ticket(opts: { id: string; room: string; name?: string; forms?: FormId[]; secret?: string; ttl?: number; jti?: string }) {
  return signJwt({
    aud: GAME_TICKET_AUDIENCE, sub: opts.id, jti: opts.jti ?? randomUUID(), room: opts.room,
    name: opts.name ?? 'Bot', color: '#e4007c', hat: 1, forms: opts.forms ?? ['alux', 'balam'],
  }, opts.secret ?? SECRET, opts.ttl ?? 60);
}

class Bot {
  ws!: WebSocket;
  welcome: Extract<ServerMessage, { t: 'welcome' }> | null = null;
  roster: RosterEntry[] = [];
  snap: Extract<ServerMessage, { t: 'snap' }> | null = null;
  events: any[] = [];
  error: { code: string } | null = null;
  closed = false;
  seq = 0;
  slot = -1;

  constructor(public id: string, public name: string) {}

  connect(token: string) {
    this.welcome = null;
    this.error = null;
    this.closed = false;
    this.seq = 0;
    return new Promise<void>((resolve) => {
      this.ws = new WebSocket(`ws://127.0.0.1:${PORT}`);
      this.ws.onopen = () => this.ws.send(JSON.stringify({ t: 'hello', v: 1, ticket: token }));
      this.ws.onmessage = (ev) => {
        const m = JSON.parse(String(ev.data));
        if (m.t === 'welcome') { this.welcome = m; this.slot = m.slot; this.roster = m.players; resolve(); }
        else if (m.t === 'roster') this.roster = m.players;
        else if (m.t === 'snap') this.snap = m;
        else if (m.t === 'event') this.events.push(m);
        else if (m.t === 'error') { this.error = m; resolve(); }
      };
      this.ws.onclose = () => { this.closed = true; resolve(); };
      this.ws.onerror = () => {};
    });
  }

  send(msg: unknown) { if (this.ws.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify(msg)); }
  input(mx: number, mz: number, extra: { j?: 0 | 1; f?: string } = {}) {
    this.send({ t: 'in', s: ++this.seq, mx, mz, j: extra.j ?? 0, f: extra.f ?? '' });
  }
  me(): SnapshotPlayer | undefined { return this.snap?.p.find((p) => p[0] === this.slot); }
  pos() { const m = this.me()!; return { x: m[3], y: m[4], z: m[5] }; }
  seen(slot: number) { const p = this.snap!.p.find((q) => q[0] === slot)!; return { x: p[3], y: p[4], z: p[5] }; }

  /** Camina hacia un punto a ritmo de tiempo real (30 inputs por segundo). */
  async walkTo(x: number, z: number, maxSeconds = 12) {
    const end = Date.now() + maxSeconds * 1000;
    while (Date.now() < end) {
      const m = this.me();
      if (m) {
        const dx = x - m[3], dz = z - m[5];
        const d = Math.hypot(dx, dz);
        if (d < 0.35) return true;
        this.input(dx / d, dz / d);
      }
      await sleep(33);
    }
    return false;
  }
  close() { this.ws.close(); }
}

before(async () => {
  assert.ok(fs.existsSync(GODOT), `No encuentro Godot en ${GODOT}. Ejecuta: npm run setup:godot`);
  fakeApi = http.createServer((req, res) => {
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      const ok = req.headers['x-service-key'] === SERVICE_KEY;
      const data = body ? JSON.parse(body) : {};
      if (ok && req.url === '/internal/game/rewards') rewardCalls.push(data);
      if (ok && req.url === '/internal/game/heartbeat') heartbeats.push(data);
      res.writeHead(ok ? 200 : 401, { 'content-type': 'application/json' });
      res.end(JSON.stringify(req.url === '/internal/game/rewards' ? { granted: data.players ?? [] } : { ok: true }));
    });
  }).listen(0);
  const apiPort = (fakeApi.address() as AddressInfo).port;
  godot = spawn(GODOT, ['--headless', '--path', path.join(ROOT, 'game'), '--', '--server'], {
    env: { ...process.env, ALUX_PORT: String(PORT), ALUX_TICKET_SECRET: SECRET, ALUX_SERVICE_KEY: SERVICE_KEY, ALUX_API_URL: `http://127.0.0.1:${apiPort}`, ALUX_SERVER_ID: 'test-1' },
  });
  godot.stdout!.on('data', (d) => (serverLog += d));
  godot.stderr!.on('data', (d) => (serverLog += d));
  for (let i = 0; i < 100 && !serverLog.includes('escuchando'); i++) await sleep(100);
  assert.ok(serverLog.includes('escuchando'), `El servidor no arrancó:\n${serverLog}`);
});

after(() => {
  godot?.kill();
  fakeApi?.close();
  if (/SCRIPT ERROR|ERROR:/.test(serverLog)) console.log('--- registro del servidor ---\n' + serverLog);
});

test('rechaza tickets falsos, vencidos, repetidos y clientes sin ticket', async () => {
  const forged = new Bot(randomUUID(), 'Falso');
  await forged.connect(ticket({ id: forged.id, room: 'AUTH01', secret: 'no-es-el-secreto' }));
  assert.equal(forged.error?.code, 'bad_ticket');

  const expired = new Bot(randomUUID(), 'Vencido');
  await expired.connect(ticket({ id: expired.id, room: 'AUTH01', ttl: -10 }));
  assert.equal(expired.error?.code, 'bad_ticket');

  const tk = ticket({ id: randomUUID(), room: 'AUTH01' });
  const first = new Bot('x', 'Uno');
  await first.connect(tk);
  assert.ok(first.welcome);
  const replay = new Bot('x', 'Dos');
  await replay.connect(tk);
  assert.equal(replay.error?.code, 'ticket_used');

  // Sin autenticarse no se puede mandar nada más
  const anon = new WebSocket(`ws://127.0.0.1:${PORT}`);
  await new Promise((r) => (anon.onopen = r));
  anon.send(JSON.stringify({ t: 'in', s: 1, mx: 1, mz: 0, j: 0, f: '' }));
  anon.send('esto no es json');
  await new Promise((r) => (anon.onclose = r));
  first.close();
});

test('cuatro aluxes en la misma sala se ven moverse; el quinto no entra', async () => {
  const room = 'SALA4A';
  const bots = [0, 1, 2, 3].map((i) => new Bot(randomUUID(), `Alux${i + 1}`));
  for (const b of bots) {
    await b.connect(ticket({ id: b.id, room, name: b.name }));
    assert.ok(b.welcome, `${b.name} debería entrar`);
  }
  await sleep(300);
  assert.deepEqual(new Set(bots.map((b) => b.slot)), new Set([0, 1, 2, 3]));
  for (const b of bots) {
    assert.equal(b.roster.length, 4);
    assert.ok(b.roster.every((r) => r.on));
    assert.deepEqual(b.roster.map((r) => r.name).sort(), ['Alux1', 'Alux2', 'Alux3', 'Alux4']);
  }

  const fifth = new Bot(randomUUID(), 'Quinto');
  await fifth.connect(ticket({ id: fifth.id, room }));
  assert.equal(fifth.error?.code, 'room_full');

  // Alux1 camina 1 segundo hacia +x: todos ven lo mismo
  const a = bots[0];
  const start = a.pos();
  for (let i = 0; i < 30; i++) { a.input(1, 0); await sleep(33); }
  await sleep(400);
  const end = a.pos();
  const moved = end.x - start.x;
  assert.ok(moved > 4.2 && moved < 5.6, `debería avanzar ~5.2 m, avanzó ${moved.toFixed(2)}`);
  for (const b of bots.slice(1)) {
    const seen = b.seen(a.slot);
    assert.ok(Math.abs(seen.x - end.x) < 0.01 && Math.abs(seen.z - end.z) < 0.01, `${b.name} ve otra posición`);
  }

  // Estado compartido: el servidor informa de las salas a la API
  await sleep(3500);
  const hb = heartbeats.at(-1);
  const reported = hb.rooms.find((r: any) => r.code === room);
  assert.equal(reported.players.length, 4);
  bots.forEach((b) => b.close());
});

test('trampas: velocidad, teletransporte, formas bloqueadas y recompensas inventadas', async () => {
  const room = 'TRAMPA';
  const cheat = new Bot(randomUUID(), 'Tramposo');
  await cheat.connect(ticket({ id: cheat.id, room, forms: ['alux'] }));
  await sleep(200);
  const start = cheat.pos();
  const rewardsBefore = rewardCalls.length;

  // 1) 400 inputs de golpe con vector enorme: como mucho avanza lo de la ráfaga permitida
  const t0 = Date.now();
  for (let i = 0; i < 400; i++) cheat.send({ t: 'in', s: ++cheat.seq, mx: 9999, mz: 0, j: 0, f: '' });
  await sleep(1000);
  const elapsed = (Date.now() - t0) / 1000;
  const dist = cheat.pos().x - start.x;
  const maxLegit = 5.2 * (elapsed + 0.8);
  assert.ok(dist <= maxLegit, `avanzó ${dist.toFixed(2)} m en ${elapsed.toFixed(2)} s (máximo ${maxLegit.toFixed(2)})`);

  // 2) Mensajes inventados: no existen en el protocolo y se ignoran
  const before = cheat.pos();
  cheat.send({ t: 'pos', x: 28, y: 0, z: 0 });
  cheat.send({ t: 'teleport', to: [28, 0, 0] });
  cheat.send({ t: 'reward', reward: 'sello_del_claro' });
  cheat.send({ t: 'event', e: 'gate_open' });
  cheat.send({ t: 'in', s: ++cheat.seq, mx: 0, mz: 0, j: 0, f: '', x: 28, z: 0, pos: [28, 0, 0] });
  await sleep(400);
  const afterPos = cheat.pos();
  assert.ok(Math.hypot(afterPos.x - before.x, afterPos.z - before.z) < 0.01, 'no debe teletransportarse');
  assert.equal(rewardCalls.length, rewardsBefore, 'no debe generarse ninguna recompensa');
  assert.equal(cheat.snap!.w[0], 0, 'el santuario sigue cerrado');

  // 3) Forma no desbloqueada
  cheat.input(0, 0, { f: 'balam' });
  cheat.input(0, 0, { f: 'kukulkan' });
  await sleep(300);
  assert.equal(cheat.me()![8], 0, 'sigue siendo alux');

  // 4) Inundar de mensajes provoca expulsión
  for (let i = 0; i < 400; i++) cheat.send({ t: 'ping', c: i });
  await sleep(500);
  assert.equal(cheat.error?.code, 'rate_limit');
});

test('reconexión: el jugador conserva identidad, lugar y posición', async () => {
  const room = 'RECON1';
  const a = new Bot(randomUUID(), 'Viajera');
  const b = new Bot(randomUUID(), 'Testigo');
  await a.connect(ticket({ id: a.id, room, name: a.name }));
  await b.connect(ticket({ id: b.id, room, name: b.name }));
  assert.ok(await a.walkTo(6, 1, 6), 'debería llegar al punto');
  await sleep(200);
  const posBefore = a.pos();
  const slotBefore = a.slot;

  a.close();
  await sleep(400);
  assert.equal(b.roster.find((r) => r.id === a.id)?.on, false, 'los demás la ven desconectada');
  assert.equal(b.roster.length, 2, 'su lugar se conserva');

  await a.connect(ticket({ id: a.id, room, name: a.name }));
  assert.ok(a.welcome);
  assert.equal(a.welcome!.rejoin, true);
  assert.equal(a.slot, slotBefore);
  assert.ok(Math.abs(a.welcome!.me[0] - posBefore.x) < 0.01 && Math.abs(a.welcome!.me[2] - posBefore.z) < 0.01, 'misma posición');
  await sleep(200);
  assert.equal(b.roster.find((r) => r.id === a.id)?.on, true);

  // Abrir el juego en otra ventana expulsa la conexión anterior, no duplica al jugador
  const dup = new Bot(a.id, 'Viajera');
  await dup.connect(ticket({ id: a.id, room, name: a.name }));
  await sleep(300);
  assert.equal(a.error?.code, 'replaced');
  assert.equal(b.roster.length, 2);
  dup.close();
  b.close();
});

test('acertijo cooperativo: hacen falta los 4 altares a la vez y la recompensa se pide una sola vez', async () => {
  const room = 'COOP44';
  const bots = [0, 1, 2, 3].map((i) => new Bot(randomUUID(), `Coop${i + 1}`));
  for (const b of bots) await b.connect(ticket({ id: b.id, room, name: b.name }));
  await sleep(300);
  assert.equal(bots[0].snap!.w[2], 4, 'con 4 aluxes se necesitan 4 altares');
  const plates = [[0, -15.5], [-11, 7], [8, 16], [17.5, -5]];
  const before = rewardCalls.length;

  // Tres altares no bastan
  const arrived = await Promise.all(bots.slice(0, 3).map((b, i) => b.walkTo(plates[i][0], plates[i][1], 14)));
  assert.deepEqual(arrived, [true, true, true]);
  await sleep(400);
  assert.equal(bots[0].snap!.w[1], 0b0111, 'tres altares activos');
  assert.equal(bots[0].snap!.w[0], 0, 'el santuario sigue cerrado con 3 de 4');

  // Antes de abrir, la puerta bloquea el paso
  // (el cuarto alux pisa su altar y se abre)
  assert.ok(await bots[3].walkTo(plates[3][0], plates[3][1], 14));
  await sleep(600);
  for (const b of bots) {
    assert.equal(b.snap!.w[0], 1, 'todos ven el santuario abierto');
    assert.ok(b.events.some((e) => e.e === 'gate_open'));
  }
  await sleep(800);
  const calls = rewardCalls.slice(before);
  assert.equal(calls.length, 1, 'una sola petición de recompensa');
  assert.equal(calls[0].reward, 'sello_del_claro');
  assert.deepEqual([...calls[0].players].sort(), bots.map((b) => b.id).sort());
  assert.ok(bots.every((b) => b.events.some((e) => e.e === 'reward' && e.saved === true)));

  // Con la puerta abierta se puede entrar al santuario
  assert.ok(await bots[3].walkTo(19, 0, 8));
  assert.ok(await bots[3].walkTo(25, 0, 8), 'debería cruzar la puerta abierta');
  bots.forEach((b) => b.close());
});

test('la puerta cerrada no se puede atravesar', async () => {
  const a = new Bot(randomUUID(), 'Curiosa');
  const b = new Bot(randomUUID(), 'Ancla'); // segundo jugador para que un solo altar no abra
  await a.connect(ticket({ id: a.id, room: 'PUERTA' }));
  await b.connect(ticket({ id: b.id, room: 'PUERTA' }));
  assert.ok(await a.walkTo(19, 0, 10));
  assert.equal(await a.walkTo(25, 0, 3), false, 'no debería cruzar');
  assert.ok(a.pos().x < 21.4, `se quedó en x=${a.pos().x}`);
  assert.equal(a.snap!.w[0], 0);
  a.close();
  b.close();
});
