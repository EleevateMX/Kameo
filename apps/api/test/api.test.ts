import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import type { AddressInfo } from 'node:net';
import { after, before, describe, test } from 'node:test';
import pg from 'pg';
import {
  GAME_TICKET_AUDIENCE, SESSION_AUDIENCE, betaAccessEnabled, findInvite, generateInviteCode, hashInviteCode, parseBetaInvites,
  ZONE_TICKET_AUDIENCE, signJwt, verifyJwt, type GameTicketClaims,
} from '@alux/shared-contracts';
import { createApp } from '../src/app.ts';
import { migrate } from '../src/migrate.ts';
import type { Config } from '../src/config.ts';
import { MemoryStore } from '../src/store/memory.ts';
import { PgStore } from '../src/store/pg.ts';
import type { Store } from '../src/store/types.ts';

const config: Config = {
  port: 0, sessionSecret: 'test-session-secret-123456', ticketSecret: 'test-ticket-secret-123456',
  serviceKey: 'test-service-key-123456', databaseUrl: null, dataFile: null,
  gameServers: [{ id: 'gs-1', wsUrl: 'ws://localhost:9080' }], zoneWsUrl: 'ws://localhost:9081', production: false,
  host: '127.0.0.1', commit: 'abc1234',
  // Acceso de testers: una invitación vigente y otra vencida
  betaEnabled: true,
  betaInvites: [
    { id: 'ana', hash: hashInviteCode('ALUX-AAAAA-BBBBB-CCCCC-DDDDD'), expiresAt: Date.now() + 86_400_000, name: 'Ana' },
    { id: 'viejo', hash: hashInviteCode('ALUX-ZZZZZ-ZZZZZ-ZZZZZ-ZZZZZ'), expiresAt: Date.now() - 1000, name: 'Viejo' },
  ],
};

function suite(label: string, makeStore: () => Promise<Store>) {
  describe(`API (${label})`, () => {
    let store: Store;
    let base = '';
    let close: () => Promise<void>;

    before(async () => {
      store = await makeStore();
      const server = createApp(store, config).listen(0);
      base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
      close = () => new Promise((r) => server.close(() => r()));
    });
    after(async () => {
      await close();
      await store.close();
    });

    const svc = (p: string, body: unknown, key = config.serviceKey) =>
      fetch(base + p, { method: 'POST', headers: { 'content-type': 'application/json', 'x-service-key': key }, body: JSON.stringify(body) });

    async function login(n: number) {
      const r = await svc('/internal/players/upsert', { provider: 'dev', providerId: `${label}-${n}-${Date.now()}`, displayName: `Tester ${n}` });
      const { id } = await r.json();
      const cookie = `alux_session=${signJwt({ aud: SESSION_AUDIENCE, sub: id }, config.sessionSecret, 3600)}`;
      const call = (method: string, p: string, body?: unknown, csrf = true) =>
        fetch(base + p, {
          method,
          headers: { cookie, 'content-type': 'application/json', ...(csrf ? { 'x-alux-csrf': '1' } : {}) },
          body: body === undefined ? undefined : JSON.stringify(body),
        });
      return { id, call };
    }

    test('rechaza peticiones sin sesión, con sesión falsa o sin cabecera anti-CSRF', async () => {
      assert.equal((await fetch(`${base}/v1/me`)).status, 401);
      const forged = signJwt({ aud: SESSION_AUDIENCE, sub: 'x' }, 'otro-secreto', 3600);
      assert.equal((await fetch(`${base}/v1/me`, { headers: { cookie: `alux_session=${forged}` } })).status, 401);
      // Un ticket de juego no sirve como sesión
      const a = await login(0);
      const wrongAud = signJwt({ aud: GAME_TICKET_AUDIENCE, sub: a.id }, config.sessionSecret, 3600);
      assert.equal((await fetch(`${base}/v1/me`, { headers: { cookie: `alux_session=${wrongAud}` } })).status, 401);
      assert.equal((await a.call('POST', '/v1/rooms', {}, false)).status, 403);
    });

    test('acceso de testers: la sesión vale mientras la invitación esté vigente y el acceso activo', async () => {
      const r = await svc('/internal/players/upsert', { provider: 'beta', providerId: `ana-${label}`, displayName: 'Ana' });
      assert.equal(r.status, 200);
      const { id } = await r.json();
      const session = (inv: string) => `alux_session=${signJwt({ aud: SESSION_AUDIENCE, sub: id, inv }, config.sessionSecret, 3600)}`;
      const me = await fetch(`${base}/v1/me`, { headers: { cookie: session('ana') } });
      assert.equal(me.status, 200);
      assert.equal((await me.json()).provider, 'beta');
      assert.equal((await fetch(`${base}/v1/me`, { headers: { cookie: session('viejo') } })).status, 401, 'invitación vencida');
      assert.equal((await fetch(`${base}/v1/me`, { headers: { cookie: session('nadie') } })).status, 401, 'invitación retirada');
      // Con el acceso por invitación apagado (p. ej. al activar Discord), esas sesiones dejan de valer
      const off = createApp(store, { ...config, betaEnabled: false }).listen(0);
      try {
        const offBase = `http://127.0.0.1:${(off.address() as AddressInfo).port}`;
        assert.equal((await fetch(`${offBase}/v1/me`, { headers: { cookie: session('ana') } })).status, 401);
      } finally {
        await new Promise((done) => off.close(() => done(null)));
      }
    });

    test('invitaciones: formato, vencimiento, comparación y activación', () => {
      const code = generateInviteCode();
      assert.match(code, /^ALUX(-[A-HJ-NP-Z2-9]{5}){4}$/);
      const { invites, rejected } = parseBetaInvites(
        `ana:${hashInviteCode(code)}:2999-12-31:Ana María, mal:xyz:2999-01-01, viejo:${hashInviteCode('ALUX-ZZZZZ-ZZZZZ-ZZZZZ-ZZZZZ')}:2001-01-01`);
      assert.equal(invites.length, 2);
      assert.equal(rejected, 1);
      assert.equal(findInvite(invites, code.toLowerCase().replace(/-/g, ' '))?.id, 'ana', 'se acepta en minúsculas y con espacios');
      assert.equal(findInvite(invites, 'ALUX-ZZZZZ-ZZZZZ-ZZZZZ-ZZZZZ'), null, 'una invitación vencida no entra');
      assert.equal(findInvite(invites, 'ALUX-AAAAA-AAAAA-AAAAA-AAAAA'), null);
      assert.equal(findInvite(invites, ''), null);
      const env = { BETA_ACCESS: 'invite', BETA_INVITES: `ana:${hashInviteCode(code)}:2999-12-31` };
      assert.equal(betaAccessEnabled(env), true);
      assert.equal(betaAccessEnabled({ ...env, BETA_ACCESS: 'off' }), false);
      assert.equal(betaAccessEnabled({ ...env, BETA_INVITES: '' }), false, 'sin invitaciones no hay acceso');
      assert.equal(betaAccessEnabled({ ...env, DISCORD_CLIENT_ID: 'x', DISCORD_CLIENT_SECRET: 'y' }), false, 'con Discord se apaga solo');
    });

    test('métricas de sesión: se guardan una vez por sesión, se acotan y exigen sesión', async () => {
      const a = await login(40);
      const b = await login(41);
      const sid = randomUUID();
      assert.equal((await fetch(`${base}/v1/telemetry`, { method: 'POST', body: '{}' })).status, 401);
      assert.equal((await a.call('POST', '/v1/telemetry', { sid: 'no-es-uuid' })).status, 400);
      const report = { sid, room: 'abc123', quality: 'low', qualityAuto: true, fpsAvg: 48.2, fpsMin: 31, pingAvg: 62, pingMax: 140,
        loadMs: 8421.7, seconds: 60, heapMb: 210, viewport: '1920x1080', renderer: 'ANGLE (x)', audio: { master: 0.8, context: 'running' },
        cine: { video: 1, engine: 2, fallbacks: 1, bytes: 1_800_000, preloadMs: 950, fails: ['sello_2:atascado', 7, 'x'.repeat(200)] } };
      assert.equal((await a.call('POST', '/v1/telemetry', report)).status, 200);
      assert.equal((await a.call('POST', '/v1/telemetry', { ...report, seconds: 9e9, fpsAvg: 'mucho', quality: 'ultra', final: true })).status, 200);
      // Otro jugador no puede pisar la sesión de alguien más
      assert.equal((await b.call('POST', '/v1/telemetry', { ...report, seconds: 5 })).status, 200);
      const mine = (await store.listMetrics(50)).filter((m) => m.sessionId === sid);
      assert.equal(mine.length, 1, 'una fila por sesión');
      assert.equal(mine[0].playerId, a.id);
      assert.equal(mine[0].seconds, 86_400, 'los valores se acotan');
      assert.equal(mine[0].fpsAvg, null, 'lo que no es número no se guarda');
      assert.equal(mine[0].quality, '');
      assert.equal(mine[0].room, 'ABC123');
      assert.equal(mine[0].loadMs, 8422);
      assert.equal((mine[0].data as any).final, true);
      // Cinemáticas: cuántas se vieron como vídeo o con el motor y qué falló, con los textos acotados
      const cine = (mine[0].data as any).cine;
      assert.deepEqual([cine.video, cine.engine, cine.fallbacks, cine.bytes, cine.preloadMs], [1, 2, 1, 1_800_000, 950]);
      assert.deepEqual([cine.fails[0], cine.fails[1], cine.fails[2].length], ['sello_2:atascado', '', 48]);
      const health = await (await fetch(`${base}/health`)).json();
      assert.deepEqual(health, { ok: true, db: true, commit: 'abc1234' });
    });

    test('perfil inicial y personalización del alux con validación', async () => {
      const a = await login(1);
      const me = await (await a.call('GET', '/v1/me')).json();
      assert.deepEqual(me.unlocks, ['alux', 'balam']);
      assert.equal(me.character.name, 'Tester 1');
      assert.equal((await a.call('PUT', '/v1/me/character', { name: 'X', color: '#ff0000', hat: 1 })).status, 400);
      assert.equal((await a.call('PUT', '/v1/me/character', { name: 'Ixchel', color: 'rojo', hat: 1 })).status, 400);
      assert.equal((await a.call('PUT', '/v1/me/character', { name: 'Ixchel', color: '#ff0000', hat: 9 })).status, 400);
      const ok = await (await a.call('PUT', '/v1/me/character', { name: '  Ixchel <b> ', color: '#E4007C', hat: 2 })).json();
      assert.deepEqual(ok.character, { name: 'Ixchel b', color: '#e4007c', hat: 2, look: { outfit: 0, accessory: 1, amulet: 1, accent: 0, skin: 0 } });

      // Apariencia del personalizador 3D: sólo valores del catálogo, y se conserva si no se manda
      const look = { outfit: 1, accessory: 2, amulet: 3, accent: 4, skin: 2 };
      for (const bad of [{ ...look, outfit: 99 }, { ...look, amulet: -1 }, { ...look, skin: 1.5 }, { ...look, scale: 3 }, { outfit: 1 }, 'capa', [1, 2, 3, 4, 2]]) {
        assert.equal((await a.call('PUT', '/v1/me/character', { name: 'Ixchel', color: '#e4007c', hat: 2, look: bad })).status, 400, `apariencia inválida: ${JSON.stringify(bad)}`);
      }
      const dressed = await (await a.call('PUT', '/v1/me/character', { name: 'Ixchel', color: '#19b4d6', hat: 5, look })).json();
      assert.deepEqual(dressed.character, { name: 'Ixchel', color: '#19b4d6', hat: 5, look });
      // el editor sencillo del portal sólo manda nombre, color y tocado: lo demás no se pierde
      const renamed = await (await a.call('PUT', '/v1/me/character', { name: 'Ixchel Dos', color: '#19b4d6', hat: 5 })).json();
      assert.deepEqual(renamed.character.look, look);
      assert.deepEqual((await (await a.call('GET', '/v1/me')).json()).character, { name: 'Ixchel Dos', color: '#19b4d6', hat: 5, look });
    });

    test('sala privada: ticket firmado, de un solo jugador, con el perfil del servidor', async () => {
      const a = await login(2);
      const room = await (await a.call('POST', '/v1/rooms', { visibility: 'private' })).json();
      assert.match(room.code, /^[A-Z0-9]{6}$/);
      const t = await (await a.call('POST', `/v1/rooms/${room.code}/ticket`)).json();
      assert.equal(t.wsUrl, 'ws://localhost:9080');
      const claims = verifyJwt<GameTicketClaims>(t.ticket, config.ticketSecret, GAME_TICKET_AUDIENCE);
      assert.ok(claims);
      assert.equal(claims.sub, a.id);
      assert.equal(claims.room, room.code);
      assert.deepEqual(claims.forms, ['alux', 'balam']);
      assert.ok(claims.exp - claims.iat <= 120);
      assert.equal(verifyJwt(t.ticket, 'secreto-equivocado', GAME_TICKET_AUDIENCE), null);
      assert.equal((await a.call('POST', '/v1/rooms/ZZZZZZ/ticket')).status, 404);
    });

    test('plaza: ticket de zona propio, con el aspecto del perfil, que no vale para una sala', async () => {
      const a = await login(3);
      const look = { outfit: 2, accessory: 3, amulet: 0, accent: 5, skin: 1 };
      await a.call('PUT', '/v1/me/character', { name: 'Plazera', color: '#ffd23f', hat: 4, look });
      const t = await (await a.call('POST', '/v1/zones/merida/ticket')).json();
      assert.equal(t.wsUrl, 'ws://localhost:9081');
      assert.equal(t.zone, 'merida');
      const claims = verifyJwt<any>(t.ticket, config.ticketSecret, ZONE_TICKET_AUDIENCE);
      assert.ok(claims);
      assert.equal(claims.sub, a.id);
      assert.deepEqual([claims.zone, claims.name, claims.color, claims.hat, claims.look], ['merida', 'Plazera', '#ffd23f', 4, [2, 3, 0, 5, 1]]);
      assert.ok(claims.exp - claims.iat <= 120);
      assert.equal(verifyJwt(t.ticket, config.ticketSecret, GAME_TICKET_AUDIENCE), null, 'un ticket de zona no abre una sala');
      assert.equal((await a.call('POST', '/v1/zones/atlantida/ticket')).status, 404);
      // sin sesión no hay ticket
      assert.equal((await fetch(base + '/v1/zones/merida/ticket', { method: 'POST', headers: { 'x-alux-csrf': '1' } })).status, 401);
      // el servidor de zonas relee el aspecto con su clave de servicio; sin ella, nada
      const fresh = await (await svc('/internal/zone/character', { player: a.id })).json();
      assert.deepEqual(fresh, { name: 'Plazera', color: '#ffd23f', hat: 4, look: [2, 3, 0, 5, 1] });
      assert.equal((await svc('/internal/zone/character', { player: a.id }, 'clave-falsa')).status, 401);
    });

    test('máximo 4 aluxes por sala; el quinto recibe room_full', async () => {
      const owner = await login(10);
      const room = await (await owner.call('POST', '/v1/rooms', {})).json();
      assert.equal((await owner.call('POST', `/v1/rooms/${room.code}/ticket`)).status, 200);
      for (let i = 11; i <= 13; i++) {
        assert.equal((await (await login(i)).call('POST', `/v1/rooms/${room.code}/ticket`)).status, 200);
      }
      const fifth = await login(14);
      const r = await fifth.call('POST', `/v1/rooms/${room.code}/ticket`);
      assert.equal(r.status, 409);
      assert.equal((await r.json()).error, 'room_full');
      // Un miembro puede pedir otro ticket (reconexión)
      assert.equal((await owner.call('POST', `/v1/rooms/${room.code}/ticket`)).status, 200);
      const info = await (await owner.call('GET', `/v1/rooms/${room.code}`)).json();
      assert.equal(info.members.length, 4);
    });

    test('emparejamiento público junta jugadores en la misma sala', async () => {
      const a = await login(20);
      const b = await login(21);
      const ra = await (await a.call('POST', '/v1/rooms/quick')).json();
      await a.call('POST', `/v1/rooms/${ra.code}/ticket`);
      const rb = await (await b.call('POST', '/v1/rooms/quick')).json();
      assert.equal(rb.code, ra.code);
      assert.equal(rb.visibility, 'public');
    });

    test('recompensas: sólo el servidor de juego, sólo miembros, y sin duplicados', async () => {
      const a = await login(30);
      const b = await login(31);
      const outsider = await login(32);
      const room = await (await a.call('POST', '/v1/rooms', {})).json();
      await a.call('POST', `/v1/rooms/${room.code}/ticket`);
      await b.call('POST', `/v1/rooms/${room.code}/ticket`);
      const body = { server_id: 'gs-1', room: room.code, reward: 'sello_del_claro', players: [a.id, b.id, outsider.id], idempotency_key: `${room.code}:1:sello_del_claro` };

      // Un jugador no puede llamar al endpoint interno
      assert.equal((await a.call('POST', '/internal/game/rewards', body)).status, 401);
      assert.equal((await svc('/internal/game/rewards', body, 'clave-falsa')).status, 401);
      assert.equal((await svc('/internal/game/rewards', { ...body, reward: 'oro_infinito' })).status, 400);

      const first = await (await svc('/internal/game/rewards', body)).json();
      assert.deepEqual(first.granted.sort(), [a.id, b.id].sort());
      const retry = await (await svc('/internal/game/rewards', body)).json();
      assert.deepEqual(retry.granted, []);

      const me = await (await a.call('GET', '/v1/me')).json();
      assert.deepEqual(me.rewards, ['sello_del_claro']);
      assert.equal(me.quests.cap1_santuario, 'completed');
      assert.deepEqual((await (await outsider.call('GET', '/v1/me')).json()).rewards, []);
      assert.equal((await (await a.call('GET', `/v1/rooms/${room.code}`)).json()).gateOpen, true);
    });

    test('Pluma de Jade: una por jugador aunque la gane en varias salas, y queda en su perfil', async () => {
      const a = await login(33);
      const b = await login(34);
      const first = await (await a.call('POST', '/v1/rooms', {})).json();
      await a.call('POST', `/v1/rooms/${first.code}/ticket`);
      await b.call('POST', `/v1/rooms/${first.code}/ticket`);
      const grant = (code: string, players: string[]) => svc('/internal/game/rewards',
        { server_id: 'gs-1', room: code, reward: 'pluma_de_jade', players, idempotency_key: `${code}:1:pluma_de_jade` });
      assert.deepEqual((await (await grant(first.code, [a.id, b.id])).json()).granted.sort(), [a.id, b.id].sort());
      // Otra sala, otra liberación: el servidor vuelve a pedirla y la API no la repite
      const second = await (await a.call('POST', '/v1/rooms', {})).json();
      await a.call('POST', `/v1/rooms/${second.code}/ticket`);
      assert.deepEqual((await (await grant(second.code, [a.id])).json()).granted, []);
      const me = await (await a.call('GET', '/v1/me')).json();
      assert.deepEqual(me.rewards.filter((r: string) => r === 'pluma_de_jade'), ['pluma_de_jade']);
      assert.equal(me.quests.cap1_guardian, 'completed');
      // No abre el santuario de la sala ni desbloquea formas: es un objeto, no una transformación
      assert.equal((await (await a.call('GET', `/v1/rooms/${second.code}`)).json()).gateOpen, false);
      assert.deepEqual(me.unlocks.sort(), ['alux', 'balam']);
    });

    test('el latido del servidor de juego marca quién está en línea', async () => {
      const a = await login(40);
      const room = await (await a.call('POST', '/v1/rooms', {})).json();
      await a.call('POST', `/v1/rooms/${room.code}/ticket`);
      await svc('/internal/game/heartbeat', { server_id: 'gs-1', rooms: [{ code: room.code, players: [{ id: a.id, on: true }], gate_open: false }] });
      const info = await (await a.call('GET', `/v1/rooms/${room.code}`)).json();
      assert.equal(info.online, 1);
      assert.equal(info.members[0].online, true);
    });
  });
}

suite('memoria', async () => new MemoryStore(null));

// Con TEST_DATABASE_URL se repiten las mismas pruebas contra PostgreSQL real
if (process.env.TEST_DATABASE_URL) {
  suite('postgres', async () => {
    const url = process.env.TEST_DATABASE_URL!;
    const client = new pg.Client({ connectionString: url });
    await client.connect();
    await client.query('drop schema public cascade; create schema public;');
    await client.end();
    // Las migraciones entran con el mismo programa que se usa al desplegar, y repetirlo no cambia nada
    const first = await migrate(url, { log: () => {} });
    assert.ok(first.length >= 2 && first.every((m) => m.applied));
    const again: string[] = [];
    await migrate(url, { log: (l) => again.push(l) });
    assert.deepEqual(again, [], 'la segunda pasada no aplica nada');
    assert.ok((await migrate(url, { statusOnly: true })).every((m) => m.applied && !m.changed));
    return PgStore.connect(url);
  });
}
