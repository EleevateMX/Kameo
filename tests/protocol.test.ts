// Prueba de red del servidor dedicado de Godot con bots (sin navegador).
// Arranca el servidor real, conecta jugadores por WebSocket e intenta hacer trampa.
import assert from 'node:assert/strict';
import { spawn, type ChildProcess } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import type { AddressInfo } from 'node:net';
import path from 'node:path';
import { after, before, describe, test } from 'node:test';
import { BOSS_STATES, ENEMY_STATES, GAME_TICKET_AUDIENCE, signJwt, type CombatEvent, type FormId, type RosterEntry, type ServerMessage, type SnapshotPlayer } from '@alux/shared-contracts';

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
  combat: CombatEvent[] = [];
  error: { code: string } | null = null;
  closed = false;
  seq = 0;
  slot = -1;
  /** Respuesta a la preparación de una cinemática: true «tengo el vídeo», false «veré la del motor», null no contesta. */
  autoReady: boolean | null = false;
  /** Vota omitir cualquier cinemática compartida en cuanto empieza (para pruebas que no tratan de ellas). */
  autoSkip = false;

  constructor(public id: string, public name: string) {}

  connect(token: string) {
    this.welcome = null;
    this.error = null;
    this.closed = false;
    this.seq = 0;
    return new Promise<void>((resolve) => {
      this.ws = new WebSocket(`ws://127.0.0.1:${PORT}`);
      this.ws.onopen = () => {
        this.ws.send(JSON.stringify({ t: 'hello', v: 2, ticket: token }));
        // Un cliente real manda su entrada 30 veces por segundo; el bot al menos da señales de vida
        const ws = this.ws;
        const alive = setInterval(() => (ws.readyState === WebSocket.OPEN ? ws.send('{"t":"ping","c":0}') : clearInterval(alive)), 2000);
      };
      this.ws.onmessage = (ev) => {
        const m = JSON.parse(String(ev.data));
        if (m.t === 'welcome') { this.welcome = m; this.slot = m.slot; this.roster = m.players; resolve(); }
        else if (m.t === 'roster') this.roster = m.players;
        else if (m.t === 'snap') { this.snap = m; if (m.ev?.length) this.combat.push(...m.ev); }
        else if (m.t === 'event') {
          this.events.push(m);
          if (m.e === 'cine_prep' && this.autoReady !== null) this.send({ t: 'cine_ready', id: m.id, v: this.autoReady ? 1 : 0 });
          if (m.e === 'cine' && this.autoSkip) this.send({ t: 'skip' });
        }
        else if (m.t === 'error') { this.error = m; resolve(); }
      };
      this.ws.onclose = () => { this.closed = true; resolve(); };
      this.ws.onerror = () => {};
    });
  }

  send(msg: unknown) { if (this.ws.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify(msg)); }
  input(mx: number, mz: number, extra: { j?: 0 | 1; f?: string; a?: number; r?: number } = {}) {
    this.send({ t: 'in', s: ++this.seq, mx, mz, j: extra.j ?? 0, f: extra.f ?? '', a: extra.a ?? 0, r: extra.r ?? 0 });
  }
  me(): SnapshotPlayer | undefined { return this.snap?.p.find((p) => p[0] === this.slot); }
  pos() { const m = this.me()!; return { x: m[4], y: m[5], z: m[6] }; }
  hp() { return this.me()![3]; }
  form() { return this.me()![9]; }
  dead() { return (this.me()![11] & 8) !== 0; }
  energy() { return this.me()![12]; }
  seen(slot: number) { const p = this.snap!.p.find((q) => q[0] === slot)!; return { x: p[4], y: p[5], z: p[6] }; }
  /** Enemigos vivos según el último estado: {id, kind, x, z, hp, maxHp, state, target} */
  foes() {
    return (this.snap?.e ?? []).map((e) => ({ id: e[0], kind: e[1], x: e[2], z: e[4], hp: e[6], maxHp: e[7], state: ENEMY_STATES[e[8]], target: e[9] }))
      .filter((e) => e.state !== 'dead');
  }
  ofType(type: string) { return this.combat.filter((e) => e[0] === type); }

  /** Camina hacia un punto a ritmo de tiempo real (30 inputs por segundo). */
  async walkTo(x: number, z: number, maxSeconds = 12, extra: { f?: string } = {}) {
    const end = Date.now() + maxSeconds * 1000;
    while (Date.now() < end) {
      const m = this.me();
      if (m) {
        const dx = x - m[4], dz = z - m[6];
        const d = Math.hypot(dx, dz);
        if (d < 0.35) return true;
        this.input(dx / d, dz / d, extra);
      }
      await sleep(33);
    }
    return false;
  }

  /** Pelea como lo haría un jugador: se acerca al enemigo elegido y ataca apuntándole. */
  async fight(pick: (b: Bot) => { x: number; z: number } | undefined, until: () => boolean, maxSeconds: number, opts: { form?: string; reach?: number } = {}) {
    const end = Date.now() + maxSeconds * 1000;
    while (Date.now() < end && !until()) {
      const m = this.me();
      const foe = pick(this);
      if (m && foe && !this.dead()) {
        const dx = foe.x - m[4], dz = foe.z - m[6];
        const d = Math.hypot(dx, dz) || 1;
        const near = d < (opts.reach ?? 1.9);
        this.input(near ? 0 : dx / d, near ? 0 : dz / d, { a: near || (opts.reach ?? 0) > 5 ? 1 : 0, r: Math.atan2(dx, dz), f: opts.form ?? '' });
      } else {
        this.input(0, 0);
      }
      await sleep(33);
    }
    return until();
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
  assert.equal(cheat.form(), 0, 'sigue siendo alux');

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

test('acertijo + emboscada: 4 altares abren el santuario, los 4 pelean juntos y el sello se da una sola vez al vencer', async () => {
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
  assert.equal(bots[0].snap!.w[3], 0, 'la emboscada no ha empezado');

  // El cuarto alux pisa su altar: se abre y despiertan los guardianes
  // (al pisarlo, la sala se pausa para la escena del sello: el bot termina de llegar cuando acaba)
  assert.ok(await bots[3].walkTo(plates[3][0], plates[3][1], 26));
  await sleep(600);
  for (const b of bots) {
    assert.equal(b.snap!.w[0], 1, 'todos ven el santuario abierto');
    assert.ok(b.events.some((e) => e.e === 'gate_open'));
    assert.equal(b.snap!.w[3], 1, 'todos ven la emboscada en curso');
  }
  const wave = bots[0].snap!.w[4];
  assert.equal(wave, 8, 'con 4 jugadores aparecen 5 criaturas y 3 guardianes');
  assert.equal(rewardCalls.length, before, 'abrir la puerta ya no da el sello: hay que vencer');

  // Los cuatro pelean como Balam contra el enemigo de la emboscada más cercano a cada uno
  const homes = new Set([[-22, -14], [20, -20], [-3, 28], [24, 14]].map(([x, z]) => `${x},${z}`));
  const targetsSeen = new Set<number>();
  const nearestWave = (b: Bot) => {
    const m = b.me()!;
    const foes = b.foes().filter((f) => Math.hypot(f.x - 15, f.z) < 26);
    for (const f of foes) if (f.target >= 0) targetsSeen.add(f.target);
    return foes.sort((p, q) => Math.hypot(p.x - m[4], p.z - m[6]) - Math.hypot(q.x - m[4], q.z - m[6]))[0];
  };
  void homes;
  const done = () => bots[0].snap!.w[3] === 2;
  const results = await Promise.all(bots.map((b) => b.fight(nearestWave, done, 120, { form: 'balam' })));
  assert.ok(results.every(Boolean), `la emboscada debería superarse (quedan ${bots[0].snap!.w[4]})`);
  await sleep(1000);

  // Todos ven lo mismo: mismas bajas, mismo estado, mismo punto de reaparición nuevo
  for (const b of bots) {
    assert.equal(b.snap!.w[3], 2);
    assert.equal(b.snap!.w[5], 1, 'el punto de reaparición pasa al santuario');
    assert.ok(b.ofType('enc').some((e) => e[1] === 'clear'));
    assert.equal(b.form(), 1, 'sigue transformado en Balam');
  }
  const kills = bots.map((b) => b.ofType('die').filter((e) => e[1] === 'e').map((e) => e[2]).sort().join(','));
  assert.equal(new Set(kills).size, 1, 'los cuatro recibieron exactamente las mismas bajas');
  assert.ok(targetsSeen.size >= 2, `los enemigos persiguieron a ${targetsSeen.size} jugador(es) distintos`);

  const calls = rewardCalls.slice(before);
  assert.equal(calls.length, 1, 'una sola petición de recompensa');
  assert.equal(calls[0].reward, 'sello_del_claro');
  assert.deepEqual([...calls[0].players].sort(), bots.map((b) => b.id).sort());
  assert.ok(bots.every((b) => b.events.some((e) => e.e === 'reward' && e.saved === true)));

  // Con la puerta abierta se puede entrar al santuario
  assert.ok(await bots[3].walkTo(19, 0, 10));
  assert.ok(await bots[3].walkTo(25, 0, 8), 'debería cruzar la puerta abierta');
  bots.forEach((b) => b.close());
});

test('combate: el servidor decide daño, enfriamientos y energía; el cliente no puede inventarlos', async () => {
  const room = 'PELEA1';
  const a = new Bot(randomUUID(), 'Maga');
  await a.connect(ticket({ id: a.id, room }));
  await sleep(300);
  assert.equal(a.foes().length, 4, 'hay 4 enemigos rondando el claro');
  assert.equal(a.hp(), 100);
  const foe0 = a.foes().find((f) => f.kind === 1 && f.z > 20)!; // criatura corrompida del sur
  assert.equal(foe0.hp, 40);

  // Atacar desde lejos no hace nada: garras a 25 m y chispas que no llegan
  for (let i = 0; i < 20; i++) { a.input(0, 0, { a: 1, r: Math.atan2(foe0.x - a.pos().x, foe0.z - a.pos().z) }); await sleep(33); }
  await sleep(600);
  assert.equal(a.foes().find((f) => f.id === foe0.id)!.hp, 40, 'fuera de alcance no hay daño');
  assert.equal(a.ofType('hit').length, 0);

  // Ráfaga de 80 inputs con el botón de ataque (más sería expulsión por inundación):
  // el enfriamiento lo lleva el servidor, no el cliente
  const boltsBefore = a.ofType('bolt').length;
  const t0 = Date.now();
  for (let i = 0; i < 80; i++) a.send({ t: 'in', s: ++a.seq, mx: 0, mz: 0, j: 0, f: '', a: 1, r: 0 });
  await sleep(1200);
  const fired = a.ofType('bolt').length - boltsBefore;
  const maxLegit = Math.ceil(((Date.now() - t0) / 1000 + 0.8) / 0.42) + 1;
  assert.ok(fired >= 1 && fired <= maxLegit, `disparó ${fired} chispas (máximo legítimo ${maxLegit})`);

  // Mensajes inventados de daño/vida/energía: se ignoran
  a.send({ t: 'hit', target: foe0.id, dmg: 9999 });
  a.send({ t: 'in', s: ++a.seq, mx: 0, mz: 0, j: 0, f: '', a: 0, r: 0, hp: 9999, energy: 9999, dmg: 9999, cd1: 0 });
  await sleep(300);
  assert.equal(a.foes().find((f) => f.id === foe0.id)!.hp, 40);
  assert.ok(a.hp() <= 100 && a.energy() <= 100);

  // Acercarse y disparar de verdad: 12 de daño ×1.5 contra corrompidas = 18 por chispa
  const aimAt = (b: Bot) => b.foes().find((f) => f.id === foe0.id);
  await a.fight(aimAt, () => a.ofType('hit').some((e) => e[1] === 'e' && e[2] === foe0.id), 20, { reach: 9 });
  const firstHit = a.ofType('hit').find((e) => e[1] === 'e' && e[2] === foe0.id)!;
  assert.equal(firstHit[3], 18, 'el daño lo calcula el servidor con sus reglas');
  assert.equal(firstHit[5], a.slot);

  // La esquiva gasta energía y tiene enfriamiento: pulsarla 30 veces sólo esquiva una o dos
  const dodgesBefore = a.ofType('act').filter((e) => e[2] === 'dodge').length;
  for (let i = 0; i < 30; i++) { a.input(0, 0, { a: i % 2 ? 2 : 0 }); await sleep(33); }
  await sleep(300);
  const dodges = a.ofType('act').filter((e) => e[2] === 'dodge').length - dodgesBefore;
  assert.ok(dodges >= 1 && dodges <= 2, `esquivó ${dodges} veces en 1 s`);
  assert.ok(a.energy() < 100, 'la esquiva consume energía');

  // Debilitada (≤40 %), un alux puede purificarla tocándola: muere "purificada" y cura
  await a.fight(aimAt, () => { const f = aimAt(a); return !f || f.hp <= 16; }, 20, { reach: 9 });
  const weak = aimAt(a);
  if (weak) {
    const end = Date.now() + 15_000;
    while (Date.now() < end && aimAt(a)) {
      const f = aimAt(a)!;
      const m = a.me()!;
      const d = Math.hypot(f.x - m[4], f.z - m[6]) || 1;
      a.input(d > 1.6 ? (f.x - m[4]) / d : 0, d > 1.6 ? (f.z - m[6]) / d : 0, { a: a.seq % 6 === 0 ? 4 : 0 });
      await sleep(33);
    }
    const death = a.ofType('die').find((e) => e[1] === 'e' && e[2] === foe0.id);
    assert.ok(death, 'la criatura debería caer');
    assert.equal(death![3], 1, 'cae purificada, no a golpes');
  }
  a.close();
});

test('combate: un jugador que no se defiende cae y reaparece en el punto de control con la vida completa', async () => {
  const room = 'CAIDA1';
  const a = new Bot(randomUUID(), 'Quieto');
  await a.connect(ticket({ id: a.id, room }));
  await sleep(300);
  // Se planta junto al guardián de piedra del noroeste y no hace nada
  assert.ok(await a.walkTo(-17, -13, 14));
  const fell = await a.fight(() => undefined, () => a.dead(), 40);
  assert.ok(fell, 'debería caer');
  assert.equal(a.hp(), 0);
  assert.ok(a.ofType('hit').some((e) => e[1] === 'p' && e[2] === a.slot && e[3] === 15), 'cada golpe del guardián quita 15');
  // Caído no puede moverse ni atacar
  const where = a.pos();
  for (let i = 0; i < 20; i++) { a.input(1, 0, { a: 1 }); await sleep(33); }
  assert.ok(Math.hypot(a.pos().x - where.x, a.pos().z - where.z) < 1.5, 'caído no camina');
  await a.fight(() => undefined, () => !a.dead(), 10);
  assert.equal(a.dead(), false, 'reaparece');
  assert.equal(a.hp(), 100);
  assert.ok(Math.hypot(a.pos().x, a.pos().z - 3.2) < 2.5, `reaparece en la plaza (está en ${a.pos().x.toFixed(1)}, ${a.pos().z.toFixed(1)})`);
  assert.ok(a.ofType('respawn').some((e) => e[1] === a.slot));
  a.close();
});

test('partida de un jugador: derrota si cae, el santuario se vuelve a sellar y se puede reintentar hasta vencer', async () => {
  const room = 'SOLO01';
  const a = new Bot(randomUUID(), 'Sola');
  await a.connect(ticket({ id: a.id, room }));
  await sleep(300);
  assert.equal(a.snap!.w[2], 1, 'un jugador solo necesita un altar');
  const before = rewardCalls.length;

  // Abre el santuario pisando un altar y se deja vencer sin defenderse
  assert.ok(await a.walkTo(17.5, -5, 16));
  await sleep(500);
  assert.equal(a.snap!.w[0], 1, 'santuario abierto');
  assert.equal(a.snap!.w[3], 1, 'emboscada en curso');
  assert.equal(a.snap!.w[4], 3, 'con un jugador aparecen 2 criaturas y 1 guardián');
  await a.walkTo(15, 0, 6);
  const lost = await a.fight(() => undefined, () => a.snap!.w[3] === 3, 60);
  assert.ok(lost, 'si cae el único jugador, la emboscada se pierde');
  assert.ok(a.ofType('enc').some((e) => e[1] === 'fail'), 'llega el evento de derrota');
  assert.ok(a.events.some((e) => e.e === 'defeat'));
  assert.equal(a.snap!.w[0], 0, 'el santuario se vuelve a sellar');
  assert.equal(a.snap!.w[4], 0, 'la emboscada se retira');
  assert.ok(a.snap!.w[9] > 0, 'los altares quedan en espera unos segundos');
  assert.equal(rewardCalls.length, before, 'perder no da recompensa');

  // Reaparece junto al brasero y, pasada la espera, la sala vuelve al estado inicial
  await a.fight(() => undefined, () => !a.dead() && a.snap!.w[3] === 0, 15);
  assert.equal(a.dead(), false);
  assert.equal(a.hp(), 100);
  assert.equal(a.snap!.w[3], 0, 'se puede volver a intentar');
  assert.ok(Math.hypot(a.pos().x, a.pos().z - 3.2) < 2.5, 'reaparece en la plaza');

  // Segundo intento: esta vez pelea como Balam y vence
  assert.ok(await a.walkTo(17.5, -5, 16, { f: 'balam' }));
  await sleep(500);
  assert.equal(a.snap!.w[3], 1, 'la emboscada vuelve a empezar');
  const nearest = (b: Bot) => {
    const m = b.me()!;
    return b.foes().filter((f) => Math.hypot(f.x - 15, f.z) < 26).sort((p, q) => Math.hypot(p.x - m[4], p.z - m[6]) - Math.hypot(q.x - m[4], q.z - m[6]))[0];
  };
  let tries = 0;
  while (a.snap!.w[3] !== 2 && tries < 4) {
    // (si vuelve a caer, la sala se reinicia y lo intenta otra vez: es justo lo que haría un jugador)
    await a.fight(nearest, () => a.snap!.w[3] === 2 || a.snap!.w[3] === 3, 90, { form: 'balam' });
    if (a.snap!.w[3] === 3) {
      await a.fight(() => undefined, () => !a.dead() && a.snap!.w[3] === 0, 15);
      await a.walkTo(17.5, -5, 16);
      await sleep(500);
    }
    tries++;
  }
  assert.equal(a.snap!.w[3], 2, 'un jugador solo puede vencer la emboscada');
  await sleep(800);
  assert.equal(rewardCalls.length, before + 1, 'la victoria da el sello');
  a.close();
});

test('otra ronda: tras vencer, la sala se reinicia sólo cuando la piden todos los conectados', async () => {
  const room = 'RONDA2';
  const a = new Bot(randomUUID(), 'Uno');
  const b = new Bot(randomUUID(), 'Dos');
  await a.connect(ticket({ id: a.id, room, name: a.name }));
  await b.connect(ticket({ id: b.id, room, name: b.name }));
  await sleep(300);

  // Pedir otra ronda antes de vencer no hace nada
  a.send({ t: 'again' });
  await sleep(300);
  assert.equal(a.snap!.w[7], 0, 'el voto no cuenta sin victoria');

  assert.deepEqual(await Promise.all([a.walkTo(0, -15.5, 14, { f: 'balam' }), b.walkTo(17.5, -5, 16, { f: 'balam' })]), [true, true]);
  await sleep(500);
  assert.equal(a.snap!.w[3], 1, 'emboscada en curso');
  const nearest = (bot: Bot) => {
    const m = bot.me()!;
    return bot.foes().filter((f) => Math.hypot(f.x - 15, f.z) < 26).sort((p, q) => Math.hypot(p.x - m[4], p.z - m[6]) - Math.hypot(q.x - m[4], q.z - m[6]))[0];
  };
  const done = () => a.snap!.w[3] === 2;
  const won = await Promise.all([a, b].map((bot) => bot.fight(nearest, done, 120, { form: 'balam' })));
  assert.ok(won.every(Boolean), 'los dos vencen la emboscada');
  const kills = a.ofType('die').filter((e) => e[1] === 'e').length;

  // Uno solo no basta
  a.send({ t: 'again' });
  await sleep(500);
  assert.equal(a.snap!.w[7], 1, 'un voto de dos');
  assert.equal(a.snap!.w[8], 2, 'dos conectados');
  assert.equal(a.snap!.w[3], 2, 'la sala sigue igual con un solo voto');
  assert.equal(a.snap!.w[0], 1);

  // Con los dos votos empieza otra ronda: santuario sellado, todos junto al brasero y con la vida completa
  b.send({ t: 'again' });
  await sleep(700);
  for (const bot of [a, b]) {
    assert.ok(bot.events.some((e) => e.e === 'restart'), 'llega el aviso de nueva ronda');
    assert.equal(bot.snap!.w[3], 0, 'emboscada pendiente otra vez');
    assert.equal(bot.snap!.w[0], 0, 'santuario sellado');
    assert.equal(bot.snap!.w[7], 0, 'los votos se limpian');
    assert.equal(bot.hp(), 100);
    assert.ok(Math.hypot(bot.pos().x, bot.pos().z - 3.2) < 3, `vuelve a la plaza (${bot.pos().x.toFixed(1)}, ${bot.pos().z.toFixed(1)})`);
  }
  // Los altares esperan unos segundos y luego vuelven a funcionar
  assert.ok(a.snap!.w[9] > 0);
  await sleep(3200);
  assert.deepEqual(await Promise.all([a.walkTo(0, -15.5, 14), b.walkTo(17.5, -5, 16)]), [true, true]);
  await sleep(500);
  assert.equal(a.snap!.w[3], 1, 'la segunda ronda empieza al pisar de nuevo los altares');
  assert.equal(a.events.filter((e) => e.e === 'cine').length, 1, 'la cinemática del sello no se repite en la misma sala');
  assert.equal(a.snap!.w[11], 0);
  assert.ok(a.ofType('die').filter((e) => e[1] === 'e').length >= kills);
  a.close();
  b.close();
});

test('historia: hablar con Chiich Yaxché sólo cuenta estando a su lado y lo sabe toda la sala', async () => {
  const room = 'HISTO1';
  const a = new Bot(randomUUID(), 'Uno');
  const b = new Bot(randomUUID(), 'Dos');
  await a.connect(ticket({ id: a.id, room, name: a.name }));
  await b.connect(ticket({ id: b.id, room, name: b.name }));
  await sleep(300);
  assert.equal(a.snap!.w[10], 0, 'al empezar nadie ha hablado con ella');

  // Desde lejos no cuenta, y un personaje que no existe se ignora
  assert.ok(await a.walkTo(7, 9, 12));
  a.send({ t: 'talk', n: 'yaxche' });
  a.send({ t: 'talk', n: 'nadie' });
  a.send({ t: 'talk' });
  await sleep(400);
  assert.equal(a.snap!.w[10], 0, 'hablar desde lejos no avanza la historia');
  assert.equal(a.events.filter((e) => e.e === 'story').length, 0);

  // A su lado sí: la bandera cambia para todos y llega el aviso con quién fue
  assert.ok(await a.walkTo(-4.2, 1.8, 14));
  a.send({ t: 'talk', n: 'yaxche' });
  await sleep(400);
  for (const bot of [a, b]) {
    assert.equal(bot.snap!.w[10] & 1, 1, 'toda la sala ve que la historia avanzó');
    const ev = bot.events.filter((e) => e.e === 'story');
    assert.equal(ev.length, 1);
    assert.deepEqual([ev[0].k, ev[0].npc, ev[0].by], ['talked', 'yaxche', 'Uno']);
  }
  // …y queda guardado en el perfil de los dos presentes
  await sleep(500);
  const saved = rewardCalls.filter((c) => c.reward === 'llamado_de_yaxche' && c.room === room);
  assert.equal(saved.length, 1, 'una sola petición para guardar el avance');
  assert.deepEqual([...saved[0].players].sort(), [a.id, b.id].sort());
  // Repetirlo no vuelve a avisar, y los altares siguen funcionando igual
  assert.ok(await b.walkTo(-4.2, 1.8, 14));
  b.send({ t: 'talk', n: 'yaxche' });
  await sleep(400);
  assert.equal(a.events.filter((e) => e.e === 'story').length, 1, 'el aviso llega una sola vez');
  assert.equal(a.snap!.w[3], 0);
  a.close();
  b.close();
});

/** Da los últimos pasos hasta pisar un altar y devuelve en cuanto el servidor pausa la sala. */
async function stepOntoPlate(bot: Bot, x: number, z: number) {
  const end = Date.now() + 6000;
  while (Date.now() < end && !((bot.snap?.w[11] ?? 0) > 0)) {
    const m = bot.me()!;
    const dx = x - m[4], dz = z - m[6], d = Math.hypot(dx, dz) || 1;
    bot.input(dx / d, dz / d);
    await sleep(33);
  }
  return (bot.snap?.w[11] ?? 0) > 0;
}

const phase = (bot: Bot) => bot.snap?.w[13] ?? 0;
const until = async (what: string, cond: () => boolean, ms = 8000) => {
  const end = Date.now() + ms;
  while (Date.now() < end) { if (cond()) return; await sleep(25); }
  assert.fail(`no ocurrió a tiempo: ${what}`);
};
const count = (bot: Bot, e: string) => bot.events.filter((ev) => ev.e === e).length;

test('cinemática compartida: preparación, orden de inicio, pausa, voto de mayoría y reanudación', async () => {
  // Dos jugadores que contestan a mano: hace falta el voto de los dos
  const room = 'CINE02';
  const a = new Bot(randomUUID(), 'Uno');
  const b = new Bot(randomUUID(), 'Dos');
  a.autoReady = b.autoReady = null;
  await a.connect(ticket({ id: a.id, room, name: a.name }));
  await b.connect(ticket({ id: b.id, room, name: b.name }));
  await sleep(300);
  assert.deepEqual([a.snap!.w[11], phase(a)], [0, 0], 'sin cinemática al empezar');
  // Uno ya está en su altar; el otro se queda a dos pasos y entra cuando toca
  assert.deepEqual(await Promise.all([a.walkTo(0, -15.5, 14), b.walkTo(15.4, -4.5, 16)]), [true, true]);
  assert.ok(await stepOntoPlate(b, 17.5, -5), 'al pisar el segundo altar la sala se pausa');
  await sleep(300);

  // PREPARING: aviso a todos, sala en pausa, todavía sin orden de inicio
  for (const bot of [a, b]) {
    const prep = bot.events.filter((e) => e.e === 'cine_prep');
    assert.equal(prep.length, 1, 'el servidor avisa a todos de que se preparen');
    assert.equal(prep[0].id, 'sello');
    assert.ok(prep[0].wait >= 3 && prep[0].wait <= 8, 'con un tiempo máximo de espera');
    assert.equal(phase(bot), 1, 'fase de preparación');
    assert.ok(bot.snap!.w[11] > 0, 'la sala está en pausa');
    assert.equal(count(bot, 'cine'), 0, 'nadie empieza por su cuenta');
  }
  // En pausa nadie se mueve, nadie ataca y nadie recibe daño
  const where = b.pos();
  for (let i = 0; i < 20; i++) { b.input(-1, 0, { a: 1, j: 1 }); await sleep(33); }
  assert.ok(Math.hypot(b.pos().x - where.x, b.pos().z - where.z) < 0.3, 'durante la preparación el personaje no camina');
  // Todavía no se puede votar, ni dar por lista una escena que no es
  a.send({ t: 'skip' });
  a.send({ t: 'cine_ready', id: 'otra', v: 1 });
  await sleep(300);
  assert.equal(a.snap!.w[12], 0, 'en la preparación no se vota');
  assert.equal(phase(a), 1);
  // Con uno listo se sigue esperando al otro; con los dos, orden de inicio para todos a la vez
  a.send({ t: 'cine_ready', id: 'sello', v: 1 });
  await sleep(400);
  assert.equal(phase(a), 1, 'falta el segundo jugador');
  b.send({ t: 'cine_ready', id: 'sello', v: 0 });   // sin vídeo: verá la del motor
  await until('orden de inicio', () => count(a, 'cine') === 1 && count(b, 'cine') === 1 && phase(a) === 2 && phase(b) === 2, 2000);
  for (const bot of [a, b]) {
    const ev = bot.events.filter((e) => e.e === 'cine')[0];
    assert.equal(ev.id, 'sello');
    assert.equal(ev.at, 0, 'empieza desde el principio');
    assert.ok(ev.dur > 5 && ev.dur < 12);
  }

  // PLAYING: sigue la pausa
  const still = b.pos();
  for (let i = 0; i < 30; i++) { b.input(-1, 0, { a: 1, j: 1 }); await sleep(33); }
  assert.ok(Math.hypot(b.pos().x - still.x, b.pos().z - still.z) < 0.3, 'en pausa el personaje no camina');
  assert.equal(b.hp(), 100);
  assert.equal(b.foes().filter((f) => f.state !== 'idle').length, 0, 'los enemigos esperan');
  // Un voto de dos no basta; con el segundo se omite
  a.send({ t: 'skip' });
  await sleep(400);
  assert.equal(a.snap!.w[12], 1, 'un voto contado');
  assert.equal(phase(a), 2, 'con un voto de dos sigue');
  assert.equal(count(a, 'cine_end'), 0);
  b.send({ t: 'skip' });
  await until('fin por mayoría', () => count(a, 'cine_end') === 1 && count(b, 'cine_end') === 1, 2000);
  for (const bot of [a, b]) {
    const end = bot.events.filter((e) => e.e === 'cine_end');
    assert.deepEqual([end[0].id, end[0].skipped], ['sello', true]);
  }

  // RESUMING: un instante más de pausa (sin daño) mientras los clientes vuelven al juego
  await until('fase de reanudación', () => phase(b) === 3, 1000);
  assert.ok(b.snap!.w[11] > 0, 'la sala sigue en pausa al reanudar');
  const back = b.pos();
  for (let i = 0; i < 10; i++) { b.input(-1, 0); await sleep(33); }
  assert.ok(Math.hypot(b.pos().x - back.x, b.pos().z - back.z) < 0.3, 'tampoco se camina mientras se reanuda');
  assert.equal(b.hp(), 100, 'nadie recibe daño en la transición');
  await until('partida reanudada', () => phase(a) === 0 && phase(b) === 0 && a.snap!.w[11] === 0, 3000);
  const from = b.pos();
  for (let i = 0; i < 30; i++) { b.input(-1, 0); await sleep(33); }
  assert.ok(Math.hypot(b.pos().x - from.x, b.pos().z - from.z) > 1,
    `al terminar se recupera el control (de ${from.x.toFixed(1)},${from.z.toFixed(1)} a ${b.pos().x.toFixed(1)},${b.pos().z.toFixed(1)}; vida ${b.hp()}, caído ${b.dead()}, banderas ${b.me()![11]})`);
  // Votar fuera de una cinemática no hace nada, y la escena no se repite
  a.send({ t: 'skip' });
  await sleep(300);
  assert.equal(a.snap!.w[12], 0);
  assert.deepEqual([count(a, 'cine_prep'), count(a, 'cine'), count(a, 'cine_end')], [1, 1, 1], 'cada evento, una sola vez');
  a.close();
  b.close();

  // Un cliente que nunca avisa (versión vieja, vídeo colgado) no bloquea: se agota la espera y empieza
  const c = new Bot(randomUUID(), 'Sola');
  c.autoReady = null;
  await c.connect(ticket({ id: c.id, room: 'CINE01', name: c.name }));
  await sleep(300);
  assert.ok(await c.walkTo(15.4, -4.5, 16));
  assert.ok(await stepOntoPlate(c, 17.5, -5));
  const prepAt = Date.now();
  await c.fight(() => undefined, () => count(c, 'cine') === 1, 10);
  const waited = (Date.now() - prepAt) / 1000;
  assert.ok(waited > 3.5 && waited < 6.5, `espera como mucho el tiempo máximo (${waited.toFixed(1)} s)`);
  // …y sin votos termina sola al cumplirse su duración
  const started = Date.now();
  await c.fight(() => undefined, () => count(c, 'cine_end') === 1, 15);
  const took = (Date.now() - started) / 1000;
  assert.ok(took > 5 && took < 12, `dura lo que dura su guion (${took.toFixed(1)} s)`);
  assert.equal(c.events.filter((e) => e.e === 'cine_end')[0].skipped, false);
  await c.fight(() => undefined, () => phase(c) === 0, 4);
  assert.equal(phase(c), 0, 'y la partida se reanuda');
  c.close();

  // Un jugador solo que avisa y vota: empieza enseguida y se omite al instante
  const d = new Bot(randomUUID(), 'Prisa');
  d.autoReady = true;
  await d.connect(ticket({ id: d.id, room: 'CINE00', name: d.name }));
  await sleep(300);
  assert.ok(await d.walkTo(15.4, -4.5, 16));
  assert.ok(await stepOntoPlate(d, 17.5, -5));
  await until('inicio inmediato', () => count(d, 'cine') === 1, 1500);
  d.send({ t: 'skip' });
  await until('omitida', () => count(d, 'cine_end') === 1, 1500);
  assert.equal(d.events.filter((e) => e.e === 'cine_end')[0].skipped, true, 'solo: su voto es mayoría');
  d.close();
});

test('cinemática compartida: quien se va no bloquea, quien vuelve o llega se engancha y nada se duplica', async () => {
  const room = 'CINE03';
  const a = new Bot(randomUUID(), 'Queda');
  const b = new Bot(randomUUID(), 'Se va');
  a.autoReady = true;
  b.autoReady = null;
  await a.connect(ticket({ id: a.id, room, name: a.name }));
  await b.connect(ticket({ id: b.id, room, name: b.name }));
  await sleep(300);
  assert.deepEqual(await Promise.all([a.walkTo(0, -15.5, 14), b.walkTo(15.4, -4.5, 16)]), [true, true]);
  assert.ok(await stepOntoPlate(b, 17.5, -5));
  await sleep(300);
  assert.equal(phase(a), 1, 'esperando al jugador que no ha avisado');
  // El que faltaba se desconecta en plena preparación: la sala no se queda esperándolo
  b.close();
  await until('empieza sin el ausente', () => count(a, 'cine') === 1 && phase(a) === 2, 2500);

  // Vuelve a mitad de la escena: el servidor le dice cuál es y por dónde va
  await sleep(1500);
  b.events = [];
  await b.connect(ticket({ id: b.id, room, name: b.name }));
  assert.equal(b.welcome!.rejoin, true);
  assert.equal(b.welcome!.w[13], 2, 'la sala sigue reproduciendo');
  await until('enganche del que vuelve', () => count(b, 'cine') === 1, 1500);
  const joinB = b.events.filter((e) => e.e === 'cine')[0];
  assert.equal(joinB.id, 'sello');
  assert.ok(joinB.at >= 1 && joinB.at < joinB.dur, `con el tiempo transcurrido (${joinB.at} de ${joinB.dur} s)`);
  assert.equal(count(b, 'cine_prep'), 0, 'sin volver a prepararse');
  // Llega un jugador nuevo: también se engancha, y la sala sigue en pausa para él
  const c = new Bot(randomUUID(), 'Llega');
  await c.connect(ticket({ id: c.id, room, name: c.name }));
  await until('enganche del que llega', () => count(c, 'cine') === 1, 1500);
  assert.ok(c.events.filter((e) => e.e === 'cine')[0].at > joinB.at - 0.2);
  await sleep(300);
  const where = c.pos();
  for (let i = 0; i < 15; i++) { c.input(1, 0); await sleep(33); }
  assert.ok(Math.hypot(c.pos().x - where.x, c.pos().z - where.z) < 0.3, 'quien llega tampoco se mueve durante la escena');
  // Ahora son tres: un voto ya no basta, dos sí
  c.send({ t: 'skip' });
  await sleep(350);
  assert.deepEqual([a.snap!.w[12], phase(a)], [1, 2], 'un voto de tres no la termina');
  b.send({ t: 'skip' });
  await until('fin para los tres', () => [a, b, c].every((bot) => count(bot, 'cine_end') === 1), 2000);
  await until('reanudada', () => [a, b, c].every((bot) => phase(bot) === 0), 3000);
  // Nada duplicado para quien estuvo todo el rato
  assert.deepEqual([count(a, 'cine_prep'), count(a, 'cine'), count(a, 'cine_end'), count(a, 'gate_open')], [1, 1, 1, 1]);
  assert.equal(a.snap!.w[3], 1, 'y la emboscada empieza una sola vez');
  // Volver después de la escena no la repite
  b.close();
  await sleep(300);
  b.events = [];
  await b.connect(ticket({ id: b.id, room, name: b.name }));
  await sleep(500);
  assert.deepEqual([count(b, 'cine_prep'), count(b, 'cine')], [0, 0], 'al volver después no hay escena');
  [a, b, c].forEach((bot) => bot.close());

  // Reconexión en plena preparación: recibe el aviso con la espera que queda
  const p = new Bot(randomUUID(), 'Corte');
  const q = new Bot(randomUUID(), 'Firme');
  p.autoReady = q.autoReady = null;
  await p.connect(ticket({ id: p.id, room: 'CINE04', name: p.name }));
  await q.connect(ticket({ id: q.id, room: 'CINE04', name: q.name }));
  await sleep(300);
  assert.deepEqual(await Promise.all([q.walkTo(0, -15.5, 14), p.walkTo(15.4, -4.5, 16)]), [true, true]);
  assert.ok(await stepOntoPlate(p, 17.5, -5));
  await sleep(700);
  p.close();
  await sleep(200);
  p.events = [];
  await p.connect(ticket({ id: p.id, room: 'CINE04', name: p.name }));
  assert.equal(p.welcome!.w[13], 1, 'la sala sigue preparándose');
  await until('aviso al que vuelve', () => count(p, 'cine_prep') === 1, 1500);
  const again = p.events.filter((e) => e.e === 'cine_prep')[0];
  assert.ok(again.wait > 1.5 && again.wait < 4.6, `con la espera que queda (${again.wait} s)`);
  p.send({ t: 'cine_ready', id: 'sello', v: 0 });
  q.send({ t: 'cine_ready', id: 'sello', v: 1 });
  await until('inicio', () => count(p, 'cine') === 1 && count(q, 'cine') === 1, 1500);
  assert.equal(count(q, 'cine_prep'), 1, 'quien no se fue no recibe avisos repetidos');
  p.send({ t: 'skip' });
  q.send({ t: 'skip' });
  await until('fin', () => count(p, 'cine_end') === 1 && count(q, 'cine_end') === 1, 2000);
  await until('reanudada', () => phase(p) === 0 && phase(q) === 0, 3000);
  p.close();
  q.close();
});

// ───────────────────────── Jefe: Nojoch Tuunich ─────────────────────────
const B = { phase: 0, x: 1, z: 2, state: 4, silence: 6, glyphs: 7, needed: 8, aimX: 10, aimZ: 11, rubble: 13,
  anchors: 14, anchorsNeed: 15, pillars: 16, heart: 17, releases: 18, lit: 19, litNeed: 20, ritual: 21, channel: 22, touchNeed: 23 } as const;
const BOSS_STATE = [...BOSS_STATES] as string[];
const inCourt = (x: number, z: number) => x > 22.9 && x < 33.1 && Math.abs(z) < 5.1;
const bossEv = (bot: Bot, kind: string) => bot.combat.filter((e) => e[0] === 'boss' && e[1] === kind);

/** Abre el santuario con todos los bots y vence la emboscada (como Balam). Deja a todos fuera del patio. */
async function clearAmbush(bots: Bot[]) {
  const plates = [[17.5, -5], [0, -15.5], [-11, 7], [8, 16]];
  bots.forEach((b) => { b.autoReady = true; b.autoSkip = true; });
  // (el último en llegar pisa su altar ya con la sala en pausa: llega cuando termina la escena)
  await Promise.all(bots.map((b, i) => b.walkTo(plates[i][0], plates[i][1], 30)));
  await until('emboscada en curso', () => bots[0].snap!.w[3] === 1, 20_000);
  const nearest = (b: Bot) => {
    const m = b.me()!;
    return b.foes().filter((f) => Math.hypot(f.x - 15, f.z) < 26 && !inCourt(f.x, f.z))
      .sort((p, q) => Math.hypot(p.x - m[4], p.z - m[6]) - Math.hypot(q.x - m[4], q.z - m[6]))[0];
  };
  for (let tries = 0; tries < 5 && bots[0].snap!.w[3] !== 2; tries++) {
    await Promise.all(bots.map((b) => b.fight(nearest, () => b.snap!.w[3] === 2 || b.snap!.w[3] === 3, 120, { form: 'balam' })));
    if (bots[0].snap!.w[3] === 3) {
      // cayó todo el grupo: se reagrupan y vuelven a abrir
      await Promise.all(bots.map((b) => b.fight(() => undefined, () => !b.dead() && b.snap!.w[3] === 0 && b.snap!.w[9] === 0, 20)));
      await Promise.all(bots.map((b, i) => b.walkTo(plates[i][0], plates[i][1], 30)));
      await until('emboscada de nuevo', () => bots[0].snap!.w[3] === 1, 20_000);
    }
  }
  assert.equal(bots[0].snap!.w[3], 2, 'el grupo supera la emboscada');
}

/**
 * Un bot pelea la fase 1 como lo haría un jugador que la entiende: entra al patio, se aparta del
 * golpe de losa, debilita a una criatura con chispas (sin romperla) y la toca cerca del guardián.
 */
async function bossPhase1(bot: Bot, index: number, done: () => boolean, maxSeconds: number) {
  const end = Date.now() + maxSeconds * 1000;
  while (Date.now() < end && !done()) {
    const m = bot.me(), b = bot.snap?.b;
    if (!m || !b || bot.dead()) { bot.input(0, 0, { f: 'alux' }); await sleep(33); continue; }
    const me = { x: m[4], z: m[6] };
    const go = (x: number, z: number, extra: { a?: number; r?: number } = {}) => {
      const dx = x - me.x, dz = z - me.z, d = Math.hypot(dx, dz) || 1;
      bot.input(d > 0.25 ? dx / d : 0, d > 0.25 ? dz / d : 0, { f: 'alux', ...extra });
    };
    if (!inCourt(me.x, me.z)) {
      // por el portal: primero delante de él, luego dentro
      if (me.x < 21 && Math.abs(me.z) > 1.2) go(19.5, 0); else go(25.5, index % 2 ? 1.5 : -1.5);
    } else if (BOSS_STATE[b[B.state]] === 'slam_w' && Math.hypot(me.x - b[B.aimX], me.z - b[B.aimZ]) < 4.4) {
      // aviso de golpe de losa: fuera del círculo, sin salir del patio
      const ax = me.x - b[B.aimX], az = me.z - b[B.aimZ], d = Math.hypot(ax, az) || 1;
      const tx = Math.min(32, Math.max(23.6, me.x + (ax / d) * 4)), tz = Math.min(4.4, Math.max(-4.4, me.z + (az / d || (index % 2 ? 1 : -1)) * 4));
      go(tx, tz);
    } else {
      const foes = bot.foes().filter((f) => f.kind === 1 && inCourt(f.x, f.z)).sort((p, q) => p.id - q.id);
      const foe = foes.length ? foes[index % foes.length] : undefined;
      if (!foe) {
        go(26.5, index % 2 ? 2.5 : -2.5);   // espera a la siguiente llamada, a distancia media del guardián
      } else {
        const dx = foe.x - me.x, dz = foe.z - me.z, d = Math.hypot(dx, dz), r = Math.atan2(dx, dz);
        const nearBoss = Math.hypot(foe.x - b[B.x], foe.z - b[B.z]) <= 5.4;
        if (foe.hp > foe.maxHp * 0.4) {
          // chispas desde media distancia: la tercera la rompería, así que se para al 40 %
          if (d > 5) go(foe.x, foe.z, { a: 1, r }); else bot.input(0, 0, { f: 'alux', a: 1, r });
        } else if (!nearBoss) {
          go(b[B.x] - 3.2, b[B.z] + (index % 2 ? 1.2 : -1.2));   // la criatura lo sigue hasta el guardián
        } else if (d > 1.9) {
          go(foe.x, foe.z);
        } else {
          bot.input(0, 0, { f: 'alux', a: 4, r });   // tocar: purifica
        }
      }
    }
    await sleep(33);
  }
  return done();
}

const ANCHORS = [[10.8, -5], [10.8, 5], [19.4, 6.2], [8.4, 0]];
const SOCKETS = [[12.6, -2.6], [12.6, 2.6], [18.2, 2.8], [15.5, -6], [14.6, 5.4], [18.4, -2.2]];
const RITUAL_SPOTS = [[0, -3.1], [3.1, 0], [0, 3.1], [-3.1, 0]];

/** Para salir del patio hay que cruzar el portal: devuelve el siguiente punto hacia (x, z). */
function route(me: { x: number; z: number }, x: number, z: number) {
  if (me.x > 22.4 && x < 22) return Math.abs(me.z) > 0.9 && me.x > 23.4 ? [24.4, 0] : [20.4, 0];
  return [x, z];
}

/**
 * Fase 2 como la jugaría un grupo que la entiende: un alux despierta una columna, todos se colocan
 * detrás de ella para que la embestida la rompa, se refugian de la lluvia, y con el guardián
 * aturdido unos pisan las anclas mientras Balam golpea el corazón.
 */
async function bossPhase2(bot: Bot, index: number, n: number, done: () => boolean, maxSeconds: number) {
  const end = Date.now() + maxSeconds * 1000;
  let tick = 0;
  while (Date.now() < end && !done()) {
    tick++;
    const m = bot.me(), b = bot.snap?.b;
    if (!m || !b || bot.dead()) { bot.input(0, 0, { f: 'alux' }); await sleep(33); continue; }
    const me = { x: m[4], z: m[6] };
    const st = BOSS_STATE[b[B.state]];
    const boss = { x: b[B.x], z: b[B.z] };
    const go = (x: number, z: number, extra: { a?: number; r?: number; f?: string } = {}) => {
      const [tx, tz] = route(me, x, z);
      const dx = tx - me.x, dz = tz - me.z, d = Math.hypot(dx, dz) || 1;
      bot.input(d > 0.3 ? dx / d : 0, d > 0.3 ? dz / d : 0, { f: 'alux', ...extra });
    };
    const up = (b[B.pillars] as unknown as number[][]).map((p) => p[0]).sort((p, q) => p - q);
    const need = b[B.anchorsNeed];
    const onAnchor = n > 1 && index >= 1 && index <= need;
    if (st === 'kneel' || st === 'transit' || st === 'rise' || st === 'sleep') {
      // mientras sale del patio (o se despierta tras una derrota), a esperarlo en la explanada
      go(10.5 - (index % 2), index % 2 ? 3.6 : -3.6);
    } else if (st === 'stunned' || st === 'bound') {
      const order = ANCHORS.map((a, i) => ({ i, d: Math.hypot(a[0] - boss.x, a[1] - boss.z) })).sort((p, q) => p.d - q.d);
      const claw = () => {
        const dx = boss.x - me.x, dz = boss.z - me.z, d = Math.hypot(dx, dz) || 1;
        if (d > 3) bot.input(dx / d, dz / d, { f: 'balam' });
        else bot.input(0, 0, { f: 'balam', a: st === 'bound' ? 1 : 0, r: Math.atan2(dx, dz) });
      };
      if (n === 1) {
        // solo: pisa el ancla (se queda activa un rato) y corre a golpear
        if (st === 'stunned') go(ANCHORS[order[0].i][0], ANCHORS[order[0].i][1]); else claw();
      } else if (onAnchor) {
        go(ANCHORS[order[index - 1].i][0], ANCHORS[order[index - 1].i][1]);
      } else {
        claw();
      }
    } else if (!up.length) {
      // sin columnas: todos hacia el zócalo más alejado del guardián; el primero la despierta
      const far = SOCKETS.map((p) => ({ p, d: Math.hypot(p[0] - boss.x, p[1] - boss.z) })).sort((p, q) => q.d - p.d)[0].p;
      const d = Math.hypot(far[0] - me.x, far[1] - me.z);
      if (d > 1.5 + (index ? 1 : 0)) go(far[0] + (index ? 1.2 : 0), far[1]);
      else bot.input(0, 0, { f: 'alux', a: index === 0 && tick % 12 < 2 ? 4 : 0 });
    } else {
      const s = SOCKETS[up[0]];
      const L = Math.hypot(s[0] - boss.x, s[1] - boss.z) || 1;
      const ux = (s[0] - boss.x) / L, uz = (s[1] - boss.z) / L;
      const rain = st === 'rain_w' || st === 'rain';
      const D = rain ? 1.7 : Math.max(2.0, 7.5 - L);
      const lat = (index - (n - 1) / 2) * 0.7;
      let tx = s[0] + ux * D - uz * lat, tz = s[1] + uz * D + ux * lat;
      if (st === 'slam_w' && Math.hypot(me.x - b[B.aimX], me.z - b[B.aimZ]) < 4.4) {
        const ax = me.x - b[B.aimX], az = me.z - b[B.aimZ], d = Math.hypot(ax, az) || 1;
        tx = me.x + (ax / d) * 4; tz = me.z + (az / d) * 4;
      }
      go(tx, tz);
    }
    await sleep(33);
  }
  return done();
}

/**
 * Fase 3: encender los glifos del suelo purificando criaturas junto a él; después, quitarse de
 * encima a las que lleguen y tocarlo todos a la vez. `away`: este bot se va lejos y no participa.
 */
async function bossPhase3(bot: Bot, index: number, done: () => boolean, maxSeconds: number, away = false) {
  const end = Date.now() + maxSeconds * 1000;
  while (Date.now() < end && !done()) {
    const m = bot.me(), b = bot.snap?.b;
    if (!m || !b || bot.dead()) { bot.input(0, 0, { f: 'alux' }); await sleep(33); continue; }
    const me = { x: m[4], z: m[6] };
    const st = BOSS_STATE[b[B.state]];
    const boss = { x: b[B.x], z: b[B.z] };
    const go = (x: number, z: number, extra: { a?: number; r?: number } = {}) => {
      const [tx, tz] = route(me, x, z);
      const dx = tx - me.x, dz = tz - me.z, d = Math.hypot(dx, dz) || 1;
      bot.input(d > 0.3 ? dx / d : 0, d > 0.3 ? dz / d : 0, { f: 'alux', ...extra });
    };
    const foes = bot.foes().filter((f) => f.kind === 1 && Math.hypot(f.x - boss.x, f.z - boss.z) < 16).sort((p, q) => p.id - q.id);
    if (away) {
      go(-17, 3);
    } else if (st !== 'ritual') {
      go(boss.x - 6.5, (index - 1.5) * 1.6);
    } else if (b[B.lit] < b[B.litNeed]) {
      const foe = foes.length ? foes[index % foes.length] : undefined;
      if (!foe) {
        go(boss.x + RITUAL_SPOTS[index][0] * 1.3, boss.z + RITUAL_SPOTS[index][1] * 1.3);
      } else {
        const dx = foe.x - me.x, dz = foe.z - me.z, d = Math.hypot(dx, dz), r = Math.atan2(dx, dz);
        const nearBoss = Math.hypot(foe.x - boss.x, foe.z - boss.z) <= 6.6;
        if (foe.hp > foe.maxHp * 0.4) {
          if (d > 5) go(foe.x, foe.z, { a: 1, r }); else bot.input(0, 0, { f: 'alux', a: 1, r });
        } else if (!nearBoss) {
          go(boss.x + RITUAL_SPOTS[index][0], boss.z + RITUAL_SPOTS[index][1]);
        } else if (d > 1.9) {
          go(foe.x, foe.z);
        } else {
          bot.input(0, 0, { f: 'alux', a: 4, r });
        }
      }
    } else if (foes.length) {
      // contacto abierto: primero fuera las criaturas (a chispazos), que cortan el contacto
      const foe = foes.sort((p, q) => Math.hypot(p.x - me.x, p.z - me.z) - Math.hypot(q.x - me.x, q.z - me.z))[0];
      const dx = foe.x - me.x, dz = foe.z - me.z, d = Math.hypot(dx, dz), r = Math.atan2(dx, dz);
      if (d > 7) go(foe.x, foe.z, { a: 1, r }); else bot.input(0, 0, { f: 'alux', a: 1, r });
    } else {
      const sx = boss.x + RITUAL_SPOTS[index][0], sz = boss.z + RITUAL_SPOTS[index][1];
      if (Math.hypot(sx - me.x, sz - me.z) > 0.6) go(sx, sz); else bot.input(0, 0, { f: 'alux', a: 4 });
    }
    await sleep(33);
  }
  return done();
}

describe('jefe: Nojoch Tuunich, combate completo', { concurrency: 3 }, () => {
  for (const n of [1, 2, 4]) {
    test(`${n} ${n === 1 ? 'jugador' : 'jugadores'}: tres fases decididas por el servidor, sin teletransportes, con puntos de control y una Pluma de Jade por jugador`, async () => {
      const room = `JEFE0${n}`;
      const bots = Array.from({ length: n }, (_, i) => new Bot(randomUUID(), `Memoria${n}${i + 1}`));
      for (const b of bots) await b.connect(ticket({ id: b.id, room, name: b.name }));
      await sleep(300);
      const a = bots[0];
      assert.equal(a.welcome!.b![B.phase], 0, 'al entrar a la sala, el guardián duerme');
      await clearAmbush(bots);
      await sleep(600);
      assert.equal(a.snap!.b![B.phase], 0, 'superar la emboscada no lo despierta: hay que entrar al patio');
      assert.equal(BOSS_STATE[a.snap!.b![B.state]], 'sleep');
      assert.equal(a.foes().some((f) => inCourt(f.x, f.z)), false, 'el patio está vacío');

      // Un cliente no puede despertarlo, encender glifos ni cambiar de fase con mensajes
      const fakes = [{ t: 'boss', phase: 3 }, { t: 'glyph', n: 4 }, { t: 'purify', id: 1 }, { t: 'silence', v: 0 },
        { t: 'anchor', i: 0 }, { t: 'heart', v: 0 }, { t: 'free' }, { t: 'reward', reward: 'pluma_de_jade' }, { t: 'talk', n: 'nojoch' }];
      for (const fake of fakes) a.send(fake);
      await sleep(400);
      assert.deepEqual([a.snap!.b![B.phase], a.snap!.b![B.glyphs], a.snap!.b![B.silence]], [0, 0, 100], 'los mensajes inventados se ignoran');

      // ── Fase 1 ── Entra uno: despierta para todos, con los glifos que tocan a este grupo
      const need = [2, 3, 4, 4][n - 1];
      void bossPhase1(a, 0, () => a.snap!.b![B.phase] !== 0, 30);
      await until('el guardián despierta', () => bots.every((b) => b.snap!.b![B.phase] === 1), 30_000);
      assert.equal(bossEv(a, 'awake').length, 1);
      assert.deepEqual([a.snap!.b![B.needed], a.snap!.b![B.glyphs], a.snap!.b![B.silence]], [need, 0, 100]);
      assert.equal(BOSS_STATE[a.snap!.b![B.state]], 'rise', 'primero se pone en pie');
      const hpAtRise = a.hp();
      await until('termina de levantarse', () => BOSS_STATE[a.snap!.b![B.state]] !== 'rise', 6_000);
      assert.ok(a.hp() >= hpAtRise, 'mientras se levanta nadie recibe daño');

      if (n === 1) {
        // Derrota: si cae el único jugador, vuelve a dormirse y se reintenta desde esta fase
        await a.fight(() => undefined, () => a.snap!.b![B.phase] === 0, 120);
        assert.equal(a.snap!.b![B.phase], 0, 'sin nadie en pie, el guardián vuelve a dormirse');
        assert.equal(bossEv(a, 'fail').length, 1);
        assert.equal(a.foes().some((f) => inCourt(f.x, f.z)), false, 'sus criaturas se van con él');
        assert.deepEqual(a.snap!.b![B.rubble], [], 'y los escombros');
        assert.equal(a.snap!.w[3], 2, 'la emboscada sigue superada: no hay que volver a abrir');
        await a.fight(() => undefined, () => !a.dead(), 15);
        assert.ok(!inCourt(a.pos().x, a.pos().z), 'reaparece fuera del patio');
      }

      // El grupo completa la fase: tantos glifos como le tocan, ni uno más
      const in2 = () => a.snap!.b![B.phase] === 2;
      const r1 = await Promise.all(bots.map((b, i) => bossPhase1(b, i, in2, 300)));
      assert.ok(r1.every(Boolean), `la fase 1 se completa (glifos ${a.snap!.b![B.glyphs]}/${a.snap!.b![B.needed]}, fase ${a.snap!.b![B.phase]})`);
      await sleep(500);
      const glyphEvents = bossEv(a, 'glyph');
      assert.equal(glyphEvents[glyphEvents.length - 1][2], need, 'se encendieron los glifos necesarios');
      assert.ok(bossEv(a, 'summon').length >= 1, 'las criaturas las llamó él');
      assert.ok(bossEv(a, 'tele').length >= 1, 'cada ataque avisó antes');
      let phaseEv = bossEv(a, 'phase');
      assert.deepEqual([phaseEv.length, phaseEv[0][2], phaseEv[0][3]], [1, 2, 66], 'pasa a la fase 2 una sola vez, con un tercio menos de Silencio');
      for (const b of bots) {
        assert.deepEqual([b.snap!.b![B.phase], b.snap!.b![B.silence], BOSS_STATE[b.snap!.b![B.state]]], [2, 66, 'kneel'], 'todos ven lo mismo');
        assert.equal(b.foes().some((f) => inCourt(f.x, f.z)), false, 'las criaturas que quedaban se deshacen');
      }
      assert.equal(a.snap!.w[5], 2, 'punto de control de la fase: se reaparece en la explanada');

      // ── Fase 2 ── El guardián sale andando del patio; a nadie se le mueve de sitio
      const last = new Map<Bot, { x: number; z: number; dead: boolean }>();
      let maxJump = 0;
      const watch = setInterval(() => {
        for (const b of bots) {
          const m = b.me();
          if (!m || b.closed) continue;
          const now = { x: m[4], z: m[6], dead: (m[11] & 8) !== 0 };
          const was = last.get(b);
          if (was && !was.dead && !now.dead) maxJump = Math.max(maxJump, Math.hypot(now.x - was.x, now.z - was.z));
          last.set(b, now);
        }
      }, 50);
      const in3 = () => a.snap!.b![B.phase] === 3;
      const p2 = Promise.all(bots.map((b, i) => bossPhase2(b, i, n, () => in3() || (n === 1 && a.snap!.b![B.releases] >= 1), 420)));
      await until('sale a la explanada', () => bossEv(a, 'arena').length >= 1, 40_000);
      clearInterval(watch);
      assert.ok(a.snap!.b![B.x] < 21, `el guardián está en la explanada (x=${a.snap!.b![B.x]})`);
      assert.ok(maxJump < 2.5, `ningún jugador se teletransporta durante la transición (salto máximo ${maxJump.toFixed(2)} m)`);
      for (const b of bots) {
        assert.ok(Math.abs(b.snap!.b![B.x] - a.snap!.b![B.x]) < 1.5 && Math.abs(b.snap!.b![B.z] - a.snap!.b![B.z]) < 1.5, 'todos lo ven en el mismo sitio');
      }
      assert.equal(a.snap!.b![B.anchorsNeed], [1, 1, 2, 2][n - 1], 'anclas según el grupo');
      // Hablarle antes de liberarlo no adelanta la historia
      a.send({ t: 'talk', n: 'nojoch' });
      for (const fake of [{ t: 'anchor', i: 0, on: 1 }, { t: 'bound' }, { t: 'heart', v: 0 }]) a.send(fake);
      await sleep(300);
      assert.deepEqual([a.snap!.b![B.anchors], a.snap!.b![B.heart], a.snap!.b![B.releases], a.snap!.w[10] & 6], [0, 100, 0, 0], 'nada de eso lo decide el cliente');

      if (n === 1) {
        // Punto de control: tras liberar un corazón cae; el combate se retoma en la fase 2, no en la 1
        await p2;
        assert.equal(a.snap!.b![B.releases], 1, `libera un corazón (fase ${a.snap!.b![B.phase]}, corazón ${a.snap!.b![B.heart]})`);
        await a.fight(() => undefined, () => a.snap!.b![B.phase] === 0, 180);
        assert.deepEqual([a.snap!.b![B.phase], BOSS_STATE[a.snap!.b![B.state]], a.snap!.b![B.silence], a.snap!.b![B.releases]], [0, 'sleep', 66, 0],
          'vuelve a dormirse con el Silencio del inicio de la fase 2');
        assert.ok(a.snap!.b![B.x] < 21, 'y se queda en la explanada');
        await a.fight(() => undefined, () => !a.dead(), 15);
        assert.ok(a.pos().x < 9, `el jugador reaparece lejos de él (x=${a.pos().x.toFixed(1)})`);
        await sleep(6500);   // tarda un momento en poder despertar otra vez
        assert.equal(await bossPhase2(a, 0, 1, in3, 420), true, 'la fase 2 se completa en el reintento');
        const awake = bossEv(a, 'awake');
        assert.equal(awake[awake.length - 1][2], 2, 'el reintento despierta directamente en la fase 2');
      } else {
        assert.ok((await p2).every(Boolean), `la fase 2 se completa (corazones ${a.snap!.b![B.releases]}/3, corazón ${a.snap!.b![B.heart]} %)`);
      }
      await sleep(400);
      const hearts = bossEv(a, 'heart').slice(-3);
      assert.deepEqual(hearts.map((e) => e[4]), [55, 44, 33], 'cada corazón liberado baja el Silencio');
      assert.equal(bossEv(a, 'bound')[0][3], 100, 'hasta que las cadenas lo sujetan, el corazón está intacto');
      assert.ok(bossEv(a, 'crash').length >= 3 && bossEv(a, 'pillar').length >= 1, 'las columnas las despiertan los jugadores y se rompen con la embestida');
      assert.ok(bossEv(a, 'heart_hit').every((e) => bots.some((b) => b.slot === e[2])), 'los golpes al corazón son de jugadores de la sala');
      phaseEv = bossEv(a, 'phase');
      assert.deepEqual(phaseEv[phaseEv.length - 1].slice(2), [3, 33], 'pasa a la fase 3');
      assert.ok(a.combat.filter((e) => e[0] === 'hit' && e[1] === 'e' && e[2] === 0).length === 0, 'el guardián no recibe golpes: no tiene vida que quitar');

      // ── Fase 3 ── Glifos del suelo y contacto de todos los que siguen en pie
      const freed = () => a.snap!.b![B.phase] === 4;
      const stays = bots.filter((_, i) => !(n === 4 && i === 3));   // con cuatro, uno se va a la plaza: no bloquea
      const p3 = Promise.all(bots.map((b, i) => bossPhase3(b, i, () => freed() || b.closed, 300, n === 4 && i === 3)));
      await until('se arrodilla para el ritual', () => BOSS_STATE[a.snap!.b![B.state]] === 'ritual', 40_000);
      assert.equal(a.snap!.b![B.litNeed], [1, 2, 2, 3][n - 1], 'glifos del suelo según el grupo');
      // Tocarlo antes de encender los glifos no sirve
      assert.equal(a.snap!.b![B.ritual], 0);
      await until('se abre el contacto', () => a.snap!.b![B.lit] >= a.snap!.b![B.litNeed] || freed(), 200_000);
      if (n === 2) bots[1].close();   // uno se cae justo ahora: el otro puede terminar solo
      await p3;
      assert.ok(freed(), `el guardián queda liberado (glifos ${a.snap!.b![B.lit]}/${a.snap!.b![B.litNeed]}, contacto ${a.snap!.b![B.ritual]} %)`);
      await sleep(1500);
      for (const b of bots.filter((q) => !q.closed)) {
        assert.deepEqual([b.snap!.b![B.phase], b.snap!.b![B.silence], BOSS_STATE[b.snap!.b![B.state]]], [4, 0, 'freed'], 'todos lo ven liberado');
        assert.equal(b.events.filter((e) => e.e === 'story' && e.k === 'freed').length, 1, 'la liberación se anuncia una vez');
        assert.equal(b.events.filter((e) => e.e === 'reward' && e.reward === 'pluma_de_jade').length, 1, 'cada jugador recibe una Pluma de Jade');
        assert.equal(b.snap!.w[10] & 2, 2, 'queda anotado en la historia de la sala');
        assert.equal(b.foes().some((f) => Math.hypot(f.x - b.snap!.b![B.x], f.z - b.snap!.b![B.z]) < 16 && f.kind === 1), false, 'las criaturas del Silencio se deshacen');
      }
      assert.equal(bossEv(a, 'freed').length, 1);
      if (n === 4) assert.ok(stays.length === 3 && bossEv(a, 'contact').length >= 1, 'quien se fue lejos no bloqueó el ritual');
      const feather = rewardCalls.filter((c) => c.room === room && c.reward === 'pluma_de_jade');
      assert.equal(feather.length, 1, 'el servidor pide la recompensa una sola vez');
      assert.deepEqual([...feather[0].players].sort(), bots.map((b) => b.id).sort(), 'para todos los que libraron el combate, también quien se cayó al final');

      // La pista del Cenote: sólo hablando con él, a su lado, y una vez
      const far = stays[stays.length - 1];
      await far.walkTo(a.snap!.b![B.x] - 9, 6, 12);
      far.send({ t: 'talk', n: 'nojoch' });
      await sleep(300);
      assert.equal(a.snap!.w[10] & 4, 0, 'desde lejos no cuenta');
      await a.walkTo(a.snap!.b![B.x] - 3, 0.5, 12);
      a.send({ t: 'talk', n: 'nojoch' });
      await until('pista del Cenote', () => (a.snap!.w[10] & 4) === 4, 4_000);
      a.send({ t: 'talk', n: 'nojoch' });
      await sleep(300);
      assert.equal(a.events.filter((e) => e.e === 'story' && e.k === 'clue').length, 1, 'la pista se da una vez');

      if (n === 2) {
        // Quien se cayó vuelve y encuentra al guardián liberado
        const back = bots[1];
        await back.connect(ticket({ id: back.id, room, name: back.name }));
        assert.deepEqual([back.welcome!.b![B.phase], back.welcome!.w[10] & 6], [4, 6], 'al volver ve al guardián liberado y la historia al día');
      }
      bots.forEach((b) => b.close());
    });
  }
});

test('una conexión que deja de enviar se libera sola y el jugador puede volver', async () => {
  const room = 'MUDA01';
  const id = randomUUID();
  const witness = new Bot(randomUUID(), 'Testigo');
  await witness.connect(ticket({ id: witness.id, room }));
  // Conexión "muda": se autentica y luego no manda nada (como una red cortada sin cerrar)
  const silent = new WebSocket(`ws://127.0.0.1:${PORT}`);
  await new Promise((r) => (silent.onopen = r));
  silent.send(JSON.stringify({ t: 'hello', v: 2, ticket: ticket({ id, room, name: 'Muda' }) }));
  await sleep(1000);
  assert.equal(witness.roster.find((r) => r.id === id)?.on, true);
  await sleep(16_000);
  assert.equal(witness.roster.find((r) => r.id === id)?.on, false, 'el servidor la marca desconectada');
  const again = new Bot(id, 'Muda');
  await again.connect(ticket({ id, room, name: 'Muda' }));
  assert.equal(again.welcome?.rejoin, true);
  again.close();
  witness.close();
  silent.close();
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
