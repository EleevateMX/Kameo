// Mundo abierto en el servidor de zonas: el paso Mérida → Camino a Motul → cartel de Motul y
// vuelta, las zonas seguras, el combate mínimo, purificar, caer y reaparecer, los puntos de
// descubrimiento, la misión y las recompensas pedidas a la API. Con bots y una API simulada
// (el contrato de docs/RPG.md: POST /internal/rpg/grant), sin navegador.
import assert from 'node:assert/strict';
import { spawn, type ChildProcess } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import http from 'node:http';
import type { AddressInfo } from 'node:net';
import path from 'node:path';
import { after, afterEach, before, describe, test } from 'node:test';
import { ZONE_TICKET_AUDIENCE, signJwt } from '@alux/shared-contracts';
import { ZBot, sleep, until } from './zone-bots.ts';

const ROOT = path.resolve(import.meta.dirname, '..');
const GODOT = process.env.GODOT_BIN || path.join(ROOT, '.tools/godot');
const PORT = 19300 + Math.floor(Math.random() * 250);
const SECRET = 'zone-wild-secret-123456';
const SERVICE_KEY = 'zone-wild-service-key';
const URL = `ws://127.0.0.1:${PORT}`;
const RESPAWN = 8;   // segundos (en producción son 45)

// Lo que estas pruebas necesitan saber del camino (game/scripts/shared/camino_def.gd y wild_def.gd)
const ROAD: [number, number][] = [[0, 0], [26, -4], [52, -16], [78, -20], [104, -34], [128, -52], [154, -58], [180, -72], [204, -80]];
const SAFE: [number, number, number][] = [[4, 0, 26], [204, -80, 26]];
const HOMES: Record<number, [number, number]> = { 0: [44.1, -11.8], 1: [59.4, -14.1], 2: [72.4, -22.2], 3: [88.4, -23.3], 7: [152.6, -57.7], 9: [47.5, 3.5] };
const NPC: [number, number] = [12.5, 5.5];
const MILPA: [number, number] = [44, 8];
const SIGN: [number, number] = [199, -78.3];
const CART: [number, number] = [210.6, -84.6];
const GATE_MOTUL: [number, number] = [31.6, -12.75];      // en la plaza de Mérida
const MISSION = 'camino_motul:recado';
const PAY: Record<string, [number, number]> = { purify: [20, 8], enemy: [15, 5], discovery: [40, 15], mission: [100, 40] };

const dist = (a: { x: number; z: number }, b: [number, number] | { x: number; z: number }) =>
  Array.isArray(b) ? Math.hypot(a.x - b[0], a.z - b[1]) : Math.hypot(a.x - b.x, a.z - b.z);
const inSafe = (p: { x: number; z: number }, margin = 0) => SAFE.some(([x, z, r]) => Math.hypot(p.x - x, p.z - z) < r + margin);

let godot: ChildProcess;
let fakeApi: http.Server;
let serverLog = '';
// ── API simulada: aplica cada clave una vez por jugador, como la de verdad ──
const ledger = new Set<string>();
const totals = new Map<string, { xp: number; seeds: number }>();
/** Cada recompensa pedida (aplicada o no), en orden de llegada. */
const asked: { playerId: string; kind: string; key: string; applied: boolean }[] = [];
const requests: { path: string; key: string; status: number }[] = [];
let failNext = 0;

const applied = (playerId: string, kind: string) => asked.filter((g) => g.playerId === playerId && g.kind === kind && g.applied);

function ticket(o: { id: string; name?: string; zone?: string; rpg?: unknown }) {
  return signJwt({
    aud: ZONE_TICKET_AUDIENCE, sub: o.id, jti: randomUUID(), zone: o.zone ?? 'camino_motul',
    name: o.name ?? 'Bot', color: '#e4007c', hat: 1, look: [1, 2, 3, 4, 2], ...(o.rpg ? { rpg: o.rpg } : {}),
  }, SECRET, 60);
}
const live: ZBot[] = [];
const join = async (name: string, extra: Partial<Parameters<typeof ticket>[0]> = {}) => {
  const bot = new ZBot(extra.id ?? randomUUID(), name, URL);
  live.push(bot);
  await bot.connect(ticket({ id: bot.id, name, ...extra }));
  assert.ok(bot.welcome, `${name} debe entrar (error: ${bot.error?.code})`);
  return bot;
};

/** Se acerca a una criatura viva, la golpea hasta dejarla débil y la purifica (o la remata). */
async function hunt(bot: ZBot, id: number, how: 'purify' | 'kill' = 'purify') {
  const home = HOMES[id];
  const deaths = bot.got('ev', 'die').filter((e) => e.c === id).length;
  const end = Date.now() + 60_000;
  let lastAtk = 0;
  while (Date.now() < end) {
    if (bot.got('ev', 'die').filter((e) => e.c === id).length > deaths) return;
    assert.ok(bot.hp > 0, 'el bot no debería caer cazando una sola criatura');
    const c = bot.creature(id);
    const me = bot.pos();
    if (!c) {
      // todavía no se ve (lejos, o esperando a reaparecer): hacia su sitio, sin pisarlo
      if (dist(me, home) > 13.5) await bot.walkTo(home[0] + (me.x < home[0] ? -12 : 12), home[1], 4000, false);
      else await sleep(100);
      continue;
    }
    const d = dist(me, c);
    if (c.st === 'weak' && how === 'purify') {
      if (d > 2.2) await bot.walkTo(c.x, c.z, 600, false);
      bot.purify();
      await sleep(120);
    } else if (d > 5.5 || inSafe(me, 0.5)) {
      // a tiro y fuera de la zona segura (desde dentro no se ataca)
      const step = inSafe(me, 0.5) ? home : [c.x, c.z] as [number, number];
      await bot.walkTo(step[0], step[1], 250, false);
    } else if (Date.now() - lastAtk >= 500) {
      bot.attackAt(c.x, c.z);
      lastAtk = Date.now();
      await sleep(60);
    } else {
      await sleep(40);
    }
  }
  assert.fail(`no se pudo ${how === 'purify' ? 'purificar' : 'vencer'} a la criatura ${id}`);
}

before(async () => {
  fakeApi = http.createServer((req, res) => {
    let raw = '';
    req.on('data', (d) => { raw += d; });
    req.on('end', () => {
      const body = raw ? JSON.parse(raw) : {};
      const key = String(req.headers['x-service-key'] ?? '');
      const reply = (status: number, data: unknown) => {
        requests.push({ path: req.url ?? '', key, status });
        res.writeHead(status, { 'content-type': 'application/json' });
        res.end(JSON.stringify(data));
      };
      if (req.url !== '/internal/rpg/grant') return reply(404, { error: 'not_found' });
      if (key !== SERVICE_KEY) return reply(401, { error: 'unauthorized' });
      if (failNext > 0) { failNext--; return reply(503, { error: 'unavailable' }); }
      const results = (body.grants as { playerId: string; kind: string; key: string }[]).map((g) => {
        const id = `${g.playerId}|${g.kind}|${g.key}`;
        const fresh = !ledger.has(id);
        ledger.add(id);
        const t = totals.get(g.playerId) ?? { xp: 0, seeds: 0 };
        const [xp, seeds] = fresh ? PAY[g.kind] : [0, 0];
        t.xp += xp;
        t.seeds += seeds;
        totals.set(g.playerId, t);
        asked.push({ ...g, applied: fresh });
        return { playerId: g.playerId, kind: g.kind, applied: fresh, ...(fresh ? {} : { reason: 'duplicate' }), xp, seeds, level: 1 + Math.floor(t.xp / 100), leveledUp: fresh && Math.floor(t.xp / 100) > Math.floor((t.xp - xp) / 100), totalXp: t.xp, totalSeeds: t.seeds };
      });
      reply(200, { results });
    });
  });
  await new Promise<void>((r) => fakeApi.listen(0, '127.0.0.1', r));
  godot = spawn(GODOT, ['--headless', '--path', path.join(ROOT, 'game'), '--', '--zone', `--port=${PORT}`], {
    env: {
      ...process.env, ALUX_TICKET_SECRET: SECRET, ALUX_SERVICE_KEY: SERVICE_KEY, ALUX_ZONE_CAPACITY: '16', ALUX_DEV: '', ALUX_WILD_RESPAWN: String(RESPAWN),
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

describe('servidor de zonas: el Camino a Motul', { concurrency: false }, () => {
  afterEach(async () => {
    for (const b of live.splice(0)) b.close();
    await sleep(400);
  });

  test('paso entre zonas: de la plaza al camino sólo por el arco, cada zona con su gente, y vuelta', async () => {
    const a = await join('Viajera', { zone: 'merida' });
    const stay = await join('Se queda', { zone: 'merida' });
    assert.equal(a.zone, 'merida');
    await until('se ven en la plaza', () => a.sees('Se queda') && stay.sees('Viajera'), 5000);
    await stay.walkTo(14, 1);   // a la vista del arco del este
    // Lejos del arco no se viaja, se diga lo que se diga
    assert.equal(await a.travel('camino_motul'), null, 'desde el corro de llegada no se puede tomar el camino');
    a.send({ t: 'travel', to: 'camino_motul', x: GATE_MOTUL[0], z: GATE_MOTUL[1], pos: [GATE_MOTUL[0], 0, GATE_MOTUL[1]] });
    await sleep(300);
    assert.equal(a.zone, 'merida', 'decir que se está junto al arco no sirve');
    assert.equal(await a.travel('atlantida'), null, 'ni a una zona que no existe');
    assert.equal(a.got('travel_no').at(-1).why, 'far');
    // Andando hasta el arco del este-noreste, sí
    await a.walkTo(GATE_MOTUL[0] - 1.5, GATE_MOTUL[1]);
    const went = await a.travel('camino_motul');
    assert.ok(went, 'junto al arco se toma el camino');
    assert.equal(a.zone, 'camino_motul');
    assert.ok(dist(a.pos(), [3, 0]) < 1.6, `llega a la salida de Mérida, donde decide el servidor (${JSON.stringify(a.pos())})`);
    assert.equal(a.maxHp, 100, 'sin estadísticas en el ticket, 100 de vida');
    assert.equal(a.hp, 100);
    assert.deepEqual(a.quest, { st: 'none', n: 0, need: 3 });
    // Cada zona con sus vecinos: la de la plaza deja de verla y no hay estados cruzados
    await until('la plaza deja de verla', () => !stay.sees('Viajera') && stay.total === 1, 5000);
    await a.settle();
    assert.equal(a.total, 1, 'cuenta sólo a los del camino');
    assert.equal(a.visible(), 0);
    // Otro alux entra directamente al camino con su ticket: se ven entre ellos, no con la plaza
    const b = await join('En el camino');
    assert.equal(b.welcome.zone, 'camino_motul');
    assert.ok(dist(b.pos(), [3, 0]) < 3.5 && inSafe(b.pos()), 'quien entra con ticket aparece en la zona segura de la salida');
    await until('se ven en el camino', () => a.sees('En el camino') && b.sees('Viajera'), 5000);
    assert.ok(!stay.sees('En el camino') && !b.sees('Se queda'));
    assert.equal(a.total, 2);
    // El movimiento sigue siendo del servidor: ni más deprisa ni fuera del camino
    let from = a.pos();
    const t0 = Date.now();
    await a.hold(1, -0.15, 2000, 3);
    await a.settle();
    const secs = (Date.now() - t0) / 1000;
    let moved = dist(a.pos(), from);
    assert.ok(moved > 9 && moved <= 5.2 * secs + 0.8 && moved < 5.2 * 2.6, `mandar el triple de entradas no hace correr más (${moved.toFixed(2)} m en ${secs.toFixed(2)} s)`);
    from = a.pos();
    a.send({ t: 'in', s: a.seq + 1, x: 0, z: 0, j: 0, r: 0, e: a.epoch, px: 150, pz: -50, pos: [150, 0, -50] });
    a.seq++;
    a.send({ t: 'teleport', x: 150, z: -50 });
    await sleep(400);
    assert.ok(dist(a.pos(), from) < 0.05, 'nadie se teletransporta camino adelante');
    await a.hold(0, -1, 4000);   // contra la albarrada del norte
    await a.settle();
    const p = a.pos();
    const off = Math.min(...ROAD.slice(0, -1).map(([x0, z0], i) => {
      const [x1, z1] = ROAD[i + 1];
      const t = Math.max(0, Math.min(1, ((p.x - x0) * (x1 - x0) + (p.z - z0) * (z1 - z0)) / ((x1 - x0) ** 2 + (z1 - z0) ** 2)));
      return Math.hypot(p.x - (x0 + (x1 - x0) * t), p.z - (z0 + (z1 - z0) * t));
    }));
    assert.ok(off <= 9 - 0.45 + 0.02 || dist(p, [4, 0]) <= 12 - 0.45 + 0.02, `la albarrada detiene (a ${off.toFixed(2)} m del eje del camino)`);
    // Vuelta a Mérida por el arco: sólo desde el arco, y se llega junto a la salida hacia Motul
    assert.equal(await a.travel('merida'), null, 'lejos del arco no se vuelve');
    await a.walkTo(-2.5, 0);
    assert.ok(await a.travel('merida'));
    assert.equal(a.zone, 'merida');
    assert.ok(dist(a.pos(), [28.4, -12.75]) < 1.6, 'llega junto al arco de la plaza');
    await until('la plaza la ve otra vez y el camino no', () => stay.sees('Viajera') && !b.sees('Viajera') && b.total === 1 && stay.total === 2, 6000);
    assert.equal(a.epoch, 2, 'dos viajes');
  });

  test('zona segura y combate: la criatura no entra ni ataca dentro; el ataque sólo cuenta con alcance, arco y enfriamiento; purificar paga a quien participó', async () => {
    const a = await join('Ana');
    const b = await join('Beto', { rpg: { lv: 4, hp: 103, dmg: { chispa: 1.1, garras: 1, all: 1.1 } } });
    assert.equal(b.maxHp, 103, 'la vida máxima sale del ticket');
    assert.equal(b.hp, 103);
    // Ana sale de la zona segura hasta que la zarza 0 la persigue, y vuelve a entrar
    await a.walkTo(37, -8.5, 20_000, false);
    await until('la zarza la ve y la persigue', () => a.creature(0)?.st === 'chase' && a.creature(0)?.target === a.welcome.i, 8000);
    await a.walkTo(22, -3.4);
    assert.ok(inSafe(a.pos()));
    const hitsBefore = a.got('ev', 'hit').filter((e) => e.i === a.welcome.i).length;
    let nearest = Infinity;
    const watchUntil = Date.now() + 5000;
    while (Date.now() < watchUntil) {
      const c = a.creature(0);
      if (c) nearest = Math.min(nearest, dist(c, [SAFE[0][0], SAFE[0][1]]));
      await sleep(50);
    }
    assert.ok(nearest >= 26 + 0.6 - 0.05, `la criatura no pisa la zona segura (lo más cerca: ${nearest.toFixed(2)} m del centro; el borde está a 26)`);
    assert.equal(a.got('ev', 'hit').filter((e) => e.i === a.welcome.i).length, hitsBefore, 'dentro de la zona segura no recibe golpes');
    assert.equal(a.hp, 100);
    // Desde dentro tampoco se ataca
    a.attackAt(HOMES[0][0], HOMES[0][1]);
    await until('ataque rechazado', () => a.got('atk_no').some((m) => m.why === 'safe'), 2000);
    await until('la zarza vuelve a su sitio', () => a.creature(0)?.st === 'idle' && a.creature(0)?.hp === 40, 15_000);
    // Fuera de la zona segura pero lejos: el ataque sale y no da (alcance)
    await a.walkTo(32.5, -6.8);
    assert.ok(!inSafe(a.pos()) && dist(a.pos(), a.creature(0)!) > 8);
    a.attackAt(a.creature(0)!.x, a.creature(0)!.z, { dmg: 999, range: 99, c: 0, x: 44, z: -11 });
    await until('ataque al aire', () => a.got('ev', 'atk').some((e) => e.i === a.welcome.i), 2000);
    assert.deepEqual([a.got('ev', 'atk').at(-1).c, a.got('ev', 'atk').at(-1).d], [-1, 0], 'fuera de alcance no da, diga lo que diga el cliente');
    assert.equal(a.creature(0)!.hp, 40);
    // Beto se coloca a media distancia; Ana se acerca
    await b.walkTo(32.8, -7.0);
    await a.walkTo(38.5, -9.6, 20_000, false);
    await sleep(500);
    let c = a.creature(0)!;
    // De espaldas no da (arco)
    let n = a.got('ev', 'atk').length;
    a.attackAt(a.pos().x * 2 - c.x, a.pos().z * 2 - c.z);
    await until('ataque de espaldas', () => a.got('ev', 'atk').length > n, 2000);
    assert.equal(a.got('ev', 'atk').at(-1).c, dist(a.pos(), a.creature(0)!) > 1.2 ? -1 : 0, 'apuntando al otro lado no da (salvo que la tenga encima)');
    await sleep(500);
    // De frente y a tiro: 12 de daño
    c = a.creature(0)!;
    const hp0 = c.hp;
    n = a.got('ev', 'atk').length;
    a.attackAt(c.x, c.z);
    await until('golpe', () => a.got('ev', 'atk').length > n, 2000);
    assert.deepEqual([a.got('ev', 'atk').at(-1).c, a.got('ev', 'atk').at(-1).d], [0, 12]);
    await until('baja la vida de la criatura', () => a.creature(0)?.hp === hp0 - 12, 2000);
    // Enfriamiento: cuatro ataques seguidos son uno
    await sleep(500);
    c = a.creature(0)!;
    n = a.got('ev', 'atk').length;
    const refused = a.got('atk_no').filter((m) => m.why === 'cd').length;
    for (let i = 0; i < 4; i++) a.attackAt(c.x, c.z);
    await sleep(600);
    assert.equal(a.got('ev', 'atk').length, n + 1, 'de cuatro ataques a la vez sólo sale uno');
    assert.equal(a.got('atk_no').filter((m) => m.why === 'cd').length, refused + 3);
    await until('la criatura queda débil', () => a.creature(0)?.st === 'weak', 3000);
    assert.equal(a.creature(0)!.hp, hp0 - 24);
    // Beto también le da (con su mejora: 12 × 1.1 × 1.1) y así participa
    c = a.creature(0)!;
    const gap = dist(b.pos(), c);
    if (gap < 4.4 || gap > 6.0) await b.walkTo(c.x + (b.pos().x - c.x) / gap * 5.2, c.z + (b.pos().z - c.z) / gap * 5.2, 1500, false);
    await sleep(250);
    assert.ok(!inSafe(b.pos()) && dist(b.pos(), c) < 6.9, 'Beto está a tiro y fuera de la zona segura');
    n = b.got('ev', 'atk').filter((e) => e.i === b.welcome.i).length;
    b.attackAt(c.x, c.z, { dmg: 500 });
    await until('golpe de Beto', () => b.got('ev', 'atk').filter((e) => e.i === b.welcome.i).length > n, 2000);
    assert.deepEqual([b.got('ev', 'atk').at(-1).c, b.got('ev', 'atk').at(-1).d], [0, 14.5], 'el daño lleva el multiplicador del ticket, no el del cliente');
    // Purificar: desde lejos no; de cerca sí
    assert.ok(dist(b.pos(), c) > 3.7, `Beto está lejos para purificar (${dist(b.pos(), c).toFixed(1)} m)`);
    b.purify();
    await until('purificar desde lejos no hace nada', () => b.got('atk_no').some((m) => m.why === 'nothing'), 2000);
    assert.ok(a.creature(0), 'la criatura sigue ahí');
    await a.walkTo(c.x, c.z, 700, false);
    a.purify();
    await until('purificada', () => a.got('ev', 'die').some((e) => e.c === 0 && e.p === 1) && b.got('ev', 'die').some((e) => e.c === 0), 3000);
    // Recompensa: una petición con los dos, clave única de zona, arranque, reaparición y criatura
    await until('recompensas', () => a.got('reward').length >= 1 && b.got('reward').length >= 1, 5000);
    const paid = asked.filter((g) => g.kind === 'purify');
    assert.equal(paid.length, 2, 'cobran los dos que participaron, una vez cada uno');
    assert.deepEqual(paid.map((g) => g.playerId).sort(), [a.id, b.id].sort());
    assert.match(paid[0].key, /^camino_motul:[0-9a-f]+-0:0$/);
    assert.equal(paid[0].key, paid[1].key);
    assert.deepEqual([a.got('reward')[0].kind, a.got('reward')[0].applied, a.got('reward')[0].xp, a.got('reward')[0].seeds, a.got('reward')[0].tseeds], ['purify', true, 20, 8, 8]);
    assert.ok(requests.every((r) => r.key === SERVICE_KEY), 'el servidor llama a la API con su clave de servicio');
    // Vencer sin purificar paga como «enemy», sólo a quien golpeó
    await hunt(a, 1, 'kill');
    await until('recompensa por vencer', () => applied(a.id, 'enemy').length === 1, 5000);
    assert.ok(a.got('ev', 'die').some((e) => e.c === 1 && e.p === 0));
    assert.match(applied(a.id, 'enemy')[0].key, /^camino_motul:[0-9a-f]+-0:1$/);
    assert.equal(asked.filter((g) => g.kind === 'enemy').length, 1, 'Beto no participó: no cobra');
    // Reaparición: la zarza 0 vuelve al rato, entera, y su clave es otra
    await until('la zarza 0 reaparece', () => b.creature(0)?.hp === 40, (RESPAWN + 32) * 1000);
    await hunt(b, 0);
    await until('segunda purificación pagada', () => applied(b.id, 'purify').length === 2, 5000);
    assert.match(applied(b.id, 'purify')[1].key, /^camino_motul:[0-9a-f]+-1:0$/, 'la clave cambia con cada reaparición');
    assert.equal(new Set(asked.map((g) => `${g.playerId}|${g.kind}|${g.key}`)).size, asked.length, 'ninguna recompensa se pidió dos veces');
  });

  test('caída y reaparición: sin vida se cae, no se actúa y se vuelve en la zona segura sin perder la misión', async () => {
    const a = await join('Valiente');
    await a.walkTo(10.5, 3.6);
    a.send({ t: 'quest', a: 'accept' });
    await until('misión aceptada', () => a.quest?.st === 'active', 3000);
    // Se planta junto al henequén bravo y se deja pegar
    await a.walkPath([[26, -4], [52, -16], [70.5, -21]], 40_000);
    await until('la avisan antes de golpear', () => [...a.creatures.values()].some((c) => c.st === 'windup'), 20_000);
    await until('cae', () => a.hp === 0 && a.got('ev', 'down').some((e) => e.i === a.welcome.i), 90_000);
    assert.ok(a.got('ev', 'hit').filter((e) => e.i === a.welcome.i).length >= 6, 'cayó a golpes');
    const where = a.pos();
    const epoch = a.epoch;
    // Caída no anda, no ataca y no viaja
    await a.hold(-1, 0, 800);
    a.attackAt(where.x + 1, where.z);
    await until('ataque rechazado por estar caída', () => a.got('atk_no').some((m) => m.why === 'down'), 2000);
    assert.ok(dist(a.pos(), where) < 0.05, 'caída no se mueve');
    await until('reaparece', () => a.epoch === epoch + 1, 6000);
    assert.equal(a.zone, 'camino_motul');
    assert.ok(dist(a.pos(), [6, -0.6]) < 1.5 && inSafe(a.pos()), `reaparece en la zona segura más cercana (${JSON.stringify(a.pos())})`);
    assert.equal(a.hp, 100, 'con la vida entera');
    assert.ok(a.got('ev', 'up').some((e) => e.i === a.welcome.i));
    assert.deepEqual(a.quest, { st: 'active', n: 0, need: 3 }, 'la misión sigue como estaba');
    await a.hold(1, 0, 600);
    await a.settle();
    assert.ok(dist(a.pos(), [6, -0.6]) > 1.5, 'y puede seguir andando');
  });

  test('descubrimientos y misión: se conceden estando allí y una sola vez; la misión se completa en el cartel de Motul y se vuelve a Mérida', async () => {
    const id = randomUUID();
    ledger.add(`${id}|discovery|camino_motul:cartel_motul`);   // la API ya le pagó ese lugar en otra sesión
    const a = await join('Mensajera', { id });
    assert.deepEqual(a.known, []);
    // La misión se toma hablando con la cordelera, no desde cualquier sitio
    a.send({ t: 'quest', a: 'accept' });
    await sleep(400);
    assert.equal(a.quest!.st, 'none', 'lejos de quien la da no se acepta');
    await a.walkTo(NPC[0] - 2, NPC[1] - 1.6);
    a.send({ t: 'quest', a: 'accept' });
    await until('misión aceptada', () => a.quest?.st === 'active', 3000);
    // Dos purificaciones por el camino
    await hunt(a, 0);
    await until('cuenta para la misión', () => a.quest?.n === 1, 3000);
    await hunt(a, 9);
    await until('segunda', () => a.quest?.n === 2, 3000);
    // La milpa: nada hasta estar allí; la API falla la primera vez y el servidor reintenta
    assert.equal(a.got('disc').length, 0, 'pasar por el camino no descubre la milpa');
    assert.equal(asked.filter((g) => g.playerId === id && g.kind === 'discovery').length, 0);
    failNext = 1;
    await a.walkTo(MILPA[0], MILPA[1] - 2.5);
    await until('descubre la milpa (tras el reintento)', () => a.got('disc').some((m) => m.id === 'camino_motul:milpa'), 12_000);
    assert.equal(a.got('disc')[0].new, true);
    await until('recompensa del descubrimiento', () => a.got('reward').some((m) => m.kind === 'discovery'), 3000);
    const disc = a.got('reward').find((m) => m.kind === 'discovery');
    assert.deepEqual([disc.applied, disc.xp, disc.seeds, disc.key], [true, 40, 15, 'camino_motul:milpa']);
    assert.ok(requests.some((r) => r.status === 503), 'la API falló una vez');
    // Salir y volver a entrar no lo concede otra vez
    await a.walkTo(44, -6);
    await a.walkTo(MILPA[0], MILPA[1] - 2.5);
    await sleep(600);
    assert.equal(asked.filter((g) => g.playerId === id && g.key === 'camino_motul:milpa').length, 1, 'un descubrimiento, una petición');
    // Al cartel de Motul con dos purificaciones: llega, pero la misión no se cumple
    await a.walkPath([[44, -12], [52, -16], [78, -20], [104, -34], [128, -52], [154, -58], [180, -72], [SIGN[0] - 1, SIGN[1]]], 120_000);
    assert.ok(inSafe(a.pos()), 'el cartel está en la zona segura de la llegada');
    await until('el cartel cuenta como lugar', () => a.got('disc').some((m) => m.id === 'camino_motul:cartel_motul'), 5000);
    assert.equal(a.got('disc').find((m) => m.id === 'camino_motul:cartel_motul').new, false, 'la API ya lo conocía: no se celebra como nuevo');
    assert.equal(a.got('reward').filter((m) => m.kind === 'discovery' && m.applied).length, 1, 'ni se paga dos veces');
    assert.equal(a.quest!.st, 'active', 'faltando una purificación la misión no se cumple');
    assert.equal(applied(id, 'mission').length, 0);
    // La que falta, y de vuelta al cartel
    await hunt(a, 7);
    await until('tercera', () => a.quest?.n === 3, 3000);
    assert.equal(a.quest!.st, 'active', 'purificar no basta: hay que llegar al cartel');
    await a.walkPath([[160, -61], [180, -72], [SIGN[0] - 1, SIGN[1]]], 60_000);
    await until('misión cumplida', () => a.quest?.st === 'done', 5000);
    await until('recompensa de la misión', () => a.got('reward').some((m) => m.kind === 'mission'), 5000);
    const mission = a.got('reward').find((m) => m.kind === 'mission');
    assert.deepEqual([mission.applied, mission.xp, mission.seeds, mission.key], [true, 100, 40, MISSION]);
    assert.equal(mission.up, true, 'la subida de nivel que diga la API llega al cliente');
    assert.equal(asked.filter((g) => g.playerId === id && g.kind === 'mission').length, 1);
    assert.equal(applied(id, 'purify').length, 3);
    // La carreta lleva de vuelta a Mérida
    assert.equal(await a.travel('merida'), null, 'la carreta se toma desde la carreta');
    await a.walkTo(CART[0] - 1.2, CART[1] + 0.8);
    assert.ok(await a.travel('merida'));
    assert.equal(a.zone, 'merida');
    assert.ok(dist(a.pos(), [28.4, -12.75]) < 1.6);
    // Reconectar (sin reiniciar el servidor) conserva lo descubierto y la misión
    a.close();
    await sleep(500);
    const again = await join('Mensajera', { id });
    assert.deepEqual(again.quest, { st: 'done', n: 3, need: 3 });
    assert.deepEqual([...again.known].sort(), ['camino_motul:cartel_motul', 'camino_motul:milpa']);
    again.send({ t: 'quest', a: 'accept' });
    await sleep(300);
    assert.equal(again.quest!.st, 'done', 'una misión cumplida no se vuelve a tomar');
    // Y si el ticket trae lo que la API ya pagó (`rpg.done`), vale desde el principio
    const veteran = await join('Veterana', { rpg: { lv: 3, hp: 102, dmg: { chispa: 1, garras: 1, all: 1 }, done: [MISSION, 'camino_motul:cenote'] } });
    assert.equal(veteran.quest!.st, 'done');
    assert.deepEqual(veteran.known, ['camino_motul:cenote']);
    assert.equal(new Set(asked.map((g) => `${g.playerId}|${g.kind}|${g.key}`)).size, asked.length, 'ninguna recompensa se pidió dos veces');
    assert.ok(!/ERROR|SCRIPT ERROR/.test(serverLog), `el servidor no registró errores:\n${serverLog.split('\n').filter((l) => /ERROR/.test(l)).slice(0, 8).join('\n')}`);
  });
});
