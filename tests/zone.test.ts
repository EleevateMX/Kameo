// Servidor de zonas sociales (la plaza de Mérida), probado con bots y sin navegador.
// Arranca el servidor real (otro proceso que el de mazmorras), conecta aluxes por WebSocket e
// intenta hacer trampa.
import assert from 'node:assert/strict';
import { spawn, type ChildProcess } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import http from 'node:http';
import type { AddressInfo } from 'node:net';
import path from 'node:path';
import { after, afterEach, before, describe, test } from 'node:test';
import { GAME_TICKET_AUDIENCE, ZONE_TICKET_AUDIENCE, signJwt } from '@alux/shared-contracts';
import { ZBot, sleep, until } from './zone-bots.ts';

const ROOT = path.resolve(import.meta.dirname, '..');
const GODOT = process.env.GODOT_BIN || path.join(ROOT, '.tools/godot');
const PORT = 19600 + Math.floor(Math.random() * 300);
const SECRET = 'zone-test-secret-123456';
const SERVICE_KEY = 'zone-test-service-key';
const CAPACITY = 30;
const URL = `ws://127.0.0.1:${PORT}`;

let godot: ChildProcess;
let fakeApi: http.Server;
let serverLog = '';
/** Lo que la API falsa devuelve al servidor cuando relee el aspecto de un jugador. */
const profiles = new Map<string, { name: string; color: string; hat: number; look: number[] }>();
const apiCalls: { path: string; key: string; body: any }[] = [];

function ticket(o: { id: string; name?: string; color?: string; hat?: number; look?: unknown; zone?: string; aud?: string; secret?: string; ttl?: number; jti?: string }) {
  return signJwt({
    aud: o.aud ?? ZONE_TICKET_AUDIENCE, sub: o.id, jti: o.jti ?? randomUUID(), zone: o.zone ?? 'merida',
    name: o.name ?? 'Bot', color: o.color ?? '#e4007c', hat: o.hat ?? 1, look: o.look ?? [1, 2, 3, 4, 2],
  }, o.secret ?? SECRET, o.ttl ?? 60);
}
/** Todos los bots de la prueba en curso: se cierran al terminar, pase o falle, para que una prueba no deje gente en la plaza de la siguiente. */
const live: ZBot[] = [];
const join = async (name: string, extra: Partial<Parameters<typeof ticket>[0]> = {}) => {
  const bot = new ZBot(randomUUID(), name, URL);
  live.push(bot);
  await bot.connect(ticket({ id: bot.id, name, ...extra }));
  assert.ok(bot.welcome, `${name} debe entrar (error: ${bot.error?.code})`);
  return bot;
};

before(async () => {
  fakeApi = http.createServer((req, res) => {
    let raw = '';
    req.on('data', (d) => { raw += d; });
    req.on('end', () => {
      const body = raw ? JSON.parse(raw) : {};
      apiCalls.push({ path: req.url ?? '', key: String(req.headers['x-service-key'] ?? ''), body });
      const p = profiles.get(body.player);
      res.writeHead(p ? 200 : 404, { 'content-type': 'application/json' });
      res.end(JSON.stringify(p ?? { error: 'not_found' }));
    });
  });
  await new Promise<void>((r) => fakeApi.listen(0, '127.0.0.1', r));
  godot = spawn(GODOT, ['--headless', '--path', path.join(ROOT, 'game'), '--', '--zone', `--port=${PORT}`], {
    env: {
      ...process.env, ALUX_TICKET_SECRET: SECRET, ALUX_SERVICE_KEY: SERVICE_KEY, ALUX_ZONE_CAPACITY: String(CAPACITY), ALUX_DEV: '',
      ALUX_API_URL: `http://127.0.0.1:${(fakeApi.address() as AddressInfo).port}`,
    },
  });
  godot.stdout!.on('data', (d) => { serverLog += d; });
  godot.stderr!.on('data', (d) => { serverLog += d; });
  await until('el servidor de zonas arranca', () => serverLog.includes('escuchando'), 30_000);
});

after(async () => {
  godot?.kill();
  fakeApi?.close();
  await sleep(200);
});

describe('servidor de zonas: la plaza', { concurrency: false }, () => {
  afterEach(async () => {
    for (const b of live.splice(0)) b.close();
    await sleep(400);
  });

  test('sólo se entra con un ticket de zona válido, y una sola vez', async () => {
    const reject = async (token: string, why: string) => {
      const bot = new ZBot(randomUUID(), 'Intruso', URL);
      await bot.connect(token);
      assert.equal(bot.welcome, null, why);
      assert.equal(bot.error?.code, 'bad_ticket', why);
    };
    await reject('no-es-un-ticket', 'texto cualquiera');
    await reject(ticket({ id: randomUUID(), secret: 'otro-secreto-000000000' }), 'firmado con otro secreto');
    await reject(ticket({ id: randomUUID(), ttl: -5 }), 'caducado');
    await reject(ticket({ id: randomUUID(), aud: GAME_TICKET_AUDIENCE }), 'un ticket de sala no abre la plaza');
    await reject(ticket({ id: randomUUID(), zone: 'atlantida' }), 'ticket de otra zona');
    const id = randomUUID();
    const once = ticket({ id });
    const first = new ZBot(id, 'Una vez', URL);
    await first.connect(once);
    assert.ok(first.welcome);
    await reject(once, 'el mismo ticket por segunda vez');
    first.close();
    // quien no manda el ticket primero, fuera
    const rude = new ZBot(randomUUID(), 'Sin ticket', URL);
    await rude.connectRaw({ t: 'in', s: 1, x: 1, z: 0, j: 0, r: 0 });
    assert.equal(rude.error?.code, 'hello_first');
  });

  test('bienvenida: perfil del ticket (nunca del cliente) y aparición dentro de la plaza', async () => {
    const bot = await join('Ixchel', { color: '#19b4d6', hat: 5, look: [3, 4, 2, 7, 1] });
    const w = bot.welcome!;
    assert.equal(w.zone, 'merida');
    assert.equal(w.cap, CAPACITY);
    assert.equal(w.tick, 20);
    assert.deepEqual(w.me, { n: 'Ixchel', c: '#19b4d6', h: 5, l: [3, 4, 2, 7, 1] });
    assert.ok(Math.abs(w.pos[0]) < 34 && Math.abs(w.pos[2]) < 34, `aparece dentro (${w.pos})`);
    // un ticket con datos fuera del catálogo se recorta
    const odd = await join('Raro', { hat: 99, look: [9, -1, 'x', 4] });
    assert.deepEqual(odd.welcome!.me, { n: 'Raro', c: '#e4007c', h: 6, l: [0, 1, 1, 4, 0] });
    bot.close();
    odd.close();
  });

  test('el movimiento lo decide el servidor: velocidad fija, sin atajos y sin atravesar nada', async () => {
    const bot = await join('Corredora');
    await bot.settle();
    // 2 s andando al oeste a ritmo normal: 5.2 m/s
    let from = bot.pos();
    await bot.hold(-1, 0, 2000);
    await bot.settle();
    let moved = Math.hypot(bot.pos().x - from.x, bot.pos().z - from.z);
    assert.ok(moved > 9.2 && moved < 11.2, `a 5.2 m/s en 2 s se recorren unos 10.4 m (recorrió ${moved.toFixed(2)})`);
    // «correr más»: dirección enorme y el triple de mensajes por segundo. El servidor aplica una
    // entrada por paso: lo que sobra se descarta o espera su turno, así que la distancia nunca
    // pasa de 5.2 m/s por el tiempo transcurrido (más las tres entradas de margen).
    from = bot.pos();
    const t0 = Date.now();
    await bot.hold(0, 50, 2000, 3);
    await bot.settle();
    const secs = (Date.now() - t0) / 1000;
    moved = Math.hypot(bot.pos().x - from.x, bot.pos().z - from.z);
    assert.ok(moved <= 5.2 * secs + 0.8, `mandar más entradas o más fuertes no hace correr más (${moved.toFixed(2)} m en ${secs.toFixed(2)} s: ${(moved / secs).toFixed(2)} m/s)`);
    assert.ok(moved < 5.2 * 2.6, `ni seguir andando mucho después de dejar de pulsar (${moved.toFixed(2)} m con 2 s de entradas)`);
    // campos inventados (una posición) no hacen nada
    from = bot.pos();
    bot.send({ t: 'in', s: bot.seq + 1, x: 0, z: 0, j: 0, r: 0, px: 30, pz: 30, pos: [30, 0, 30] });
    bot.seq++;
    bot.send({ t: 'teleport', x: 30, z: 30 });
    await sleep(500);
    assert.ok(Math.hypot(bot.pos().x - from.x, bot.pos().z - from.z) < 0.05, 'nadie se teletransporta diciéndole al servidor dónde está');
    // contra el edificio del norte y contra el borde: no se atraviesan
    await bot.walkTo(-20, -20);
    await bot.hold(0, -1, 2500);
    await bot.settle();
    assert.ok(bot.pos().z >= -29.0 + 0.45 - 0.02, `el muro de los arcos detiene (z = ${bot.pos().z.toFixed(2)})`);
    await bot.hold(-1, 0, 4000);
    await bot.settle();
    assert.ok(bot.pos().x >= -34 + 0.45 - 0.02, `el borde de la plaza detiene (x = ${bot.pos().x.toFixed(2)})`);
    // contra el gran árbol del centro
    await bot.walkTo(-8, 0.2);
    await bot.hold(1, 0, 2500);
    await bot.settle();
    assert.ok(Math.hypot(bot.pos().x, bot.pos().z) >= 2.6 + 0.45 - 0.02, `el árbol del centro no se atraviesa (a ${Math.hypot(bot.pos().x, bot.pos().z).toFixed(2)} m del centro)`);
    // saltar: sube y vuelve al suelo
    const top = await bot.jump();
    assert.ok(top > 0.6 && top < 1.4, `el salto sube alrededor de un metro (subió ${top.toFixed(2)})`);
    await bot.settle();
    assert.equal(bot.pos().y, 0);
    bot.close();
  });

  test('proximidad: se ve a quien está cerca, con su aspecto; al alejarse deja de verse y al volver reaparece', async () => {
    const a = await join('Ana', { color: '#ffd23f', hat: 4, look: [2, 0, 4, 1, 3] });
    const b = await join('Beto');
    await until('se ven al aparecer', () => a.sees('Beto') && b.sees('Ana'), 5000);
    assert.deepEqual(b.neighbour('Ana')!.profile, { n: 'Ana', c: '#ffd23f', h: 4, l: [2, 0, 4, 1, 3] }, 'el aspecto llega una vez, al entrar a la vista');
    assert.equal(a.total, 2);
    // Ana se va a una esquina y Beto a la contraria: más de 44 m
    await Promise.all([a.walkTo(-31, 31), b.walkTo(31, -22)]);
    await until('dejan de verse', () => !a.sees('Beto') && !b.sees('Ana'), 8000);
    assert.equal(a.total, 2, 'sigue sabiendo cuántos hay en la plaza');
    const statesWhileFar = a.statesFrom('Beto');
    await sleep(1000);
    assert.equal(a.statesFrom('Beto'), statesWhileFar, 'de quien no se ve no llega ningún estado');
    // Beto vuelve hacia el centro: reaparece para Ana a menos de 36 m
    await b.walkTo(-6, 16);
    await until('vuelven a verse', () => a.sees('Beto') && b.sees('Ana'), 8000);
    assert.ok(a.enters.filter((n) => n === 'Beto').length >= 2 && a.leaves >= 1);
    // Cercanos a 10 estados por segundo; lejanos (más de 18 m) a 4
    const d = Math.hypot(a.pos().x - b.pos().x, a.pos().z - b.pos().z);
    assert.ok(d > 20 && d < 36, `están lejos pero a la vista (${d.toFixed(1)} m)`);
    let n0 = a.statesFrom('Beto');
    await sleep(3000);
    const farRate = (a.statesFrom('Beto') - n0) / 3;
    assert.ok(farRate > 2.5 && farRate < 5.5, `un vecino lejano llega a unos 4 estados/s (llegó a ${farRate.toFixed(1)})`);
    await b.walkTo(a.pos().x + 3, a.pos().z - 3);
    await sleep(600);
    n0 = a.statesFrom('Beto');
    await sleep(3000);
    const nearRate = (a.statesFrom('Beto') - n0) / 3;
    assert.ok(nearRate > 8 && nearRate < 12, `un vecino cercano llega a unos 10 estados/s (llegó a ${nearRate.toFixed(1)})`);
    // Al desconectarse, desaparece para quien lo veía
    b.close();
    await until('Beto se va', () => !a.sees('Beto') && a.total === 1, 5000);
    a.close();
  });

  test('cambio de aspecto: el servidor lo relee de la API con su clave y lo reparte a quien lo ve', async () => {
    const a = await join('Vestida');
    const b = await join('Vecina');
    await until('se ven', () => b.sees('Vestida'), 5000);
    profiles.set(a.id, { name: 'Vestida', color: '#19b4d6', hat: 6, look: [3, 4, 2, 9, 4] });
    // lo que diga el cliente sobre su aspecto se ignora: sólo vale lo que devuelve la API
    a.send({ t: 'look', c: '#000000', h: 0, l: [0, 0, 0, 0, 0] });
    await until('la vecina ve el aspecto nuevo', () => b.neighbour('Vestida')?.profile.h === 6, 5000);
    assert.deepEqual(b.neighbour('Vestida')!.profile, { n: 'Vestida', c: '#19b4d6', h: 6, l: [3, 4, 2, 9, 4] });
    await until('ella recibe su perfil', () => a.me?.h === 6, 3000);
    const call = apiCalls.find((c) => c.path === '/internal/zone/character' && c.body.player === a.id);
    assert.ok(call, 'el servidor pregunta a la API');
    assert.equal(call!.key, SERVICE_KEY);
    a.close();
    b.close();
  });

  test('volver a entrar sustituye a la conexión anterior y conserva el sitio', async () => {
    const a = await join('Dos ventanas');
    await a.walkTo(10, 20);
    await a.settle();
    const where = a.pos();
    const again = new ZBot(a.id, 'Dos ventanas', URL);
    await again.connect(ticket({ id: a.id, name: 'Dos ventanas' }));
    assert.ok(again.welcome);
    await until('la primera ventana se cierra', () => a.error?.code === 'replaced', 3000);
    assert.ok(Math.hypot(again.welcome!.pos[0] - where.x, again.welcome!.pos[2] - where.z) < 0.5, 'sigue donde estaba');
    again.close();
  });

  test(`capacidad y tope de vecinos: entran ${CAPACITY}, el siguiente no; cada uno recibe como mucho 24`, async () => {
    await sleep(600);
    const crowd: ZBot[] = [];
    for (let i = 0; i < CAPACITY; i++) crowd.push(await join(`Alux ${i + 1}`));
    const extra = new ZBot(randomUUID(), 'Sobra', URL);
    await extra.connect(ticket({ id: extra.id }));
    assert.equal(extra.welcome, null);
    assert.equal(extra.error?.code, 'zone_full');
    await until('todos ven a sus vecinos', () => crowd.every((b) => b.visible() >= 24), 8000);
    await sleep(1500);
    for (const b of crowd) {
      assert.equal(b.total, CAPACITY, 'todos saben cuántos hay');
      assert.ok(b.visible() <= 24, `tope de vecinos (ve ${b.visible()})`);
      assert.ok(b.maxPerState <= 24, `ningún estado trae más de 24 vecinos (trajo ${b.maxPerState})`);
    }
    // al irse uno, hay sitio otra vez
    crowd[0].close();
    await until('queda un sitio', () => crowd[1].total === CAPACITY - 1, 5000);
    const late = await join('Llega tarde');
    late.close();
    for (const b of crowd) b.close();
    await sleep(300);
    assert.ok(!/ERROR|SCRIPT ERROR/.test(serverLog), `el servidor no registró errores:\n${serverLog.split('\n').filter((l) => /ERROR/.test(l)).slice(0, 5).join('\n')}`);
  });
});
