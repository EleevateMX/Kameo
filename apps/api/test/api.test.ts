import assert from 'node:assert/strict';
import type { AddressInfo } from 'node:net';
import fs from 'node:fs';
import path from 'node:path';
import { after, before, describe, test } from 'node:test';
import pg from 'pg';
import { GAME_TICKET_AUDIENCE, SESSION_AUDIENCE, signJwt, verifyJwt, type GameTicketClaims } from '@alux/shared-contracts';
import { createApp } from '../src/app.ts';
import type { Config } from '../src/config.ts';
import { MemoryStore } from '../src/store/memory.ts';
import { PgStore } from '../src/store/pg.ts';
import type { Store } from '../src/store/types.ts';

const config: Config = {
  port: 0, sessionSecret: 'test-session-secret-123456', ticketSecret: 'test-ticket-secret-123456',
  serviceKey: 'test-service-key-123456', databaseUrl: null, dataFile: null,
  gameServers: [{ id: 'gs-1', wsUrl: 'ws://localhost:9080' }], production: false,
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

    test('perfil inicial y personalización del alux con validación', async () => {
      const a = await login(1);
      const me = await (await a.call('GET', '/v1/me')).json();
      assert.deepEqual(me.unlocks, ['alux', 'balam']);
      assert.equal(me.character.name, 'Tester 1');
      assert.equal((await a.call('PUT', '/v1/me/character', { name: 'X', color: '#ff0000', hat: 1 })).status, 400);
      assert.equal((await a.call('PUT', '/v1/me/character', { name: 'Ixchel', color: 'rojo', hat: 1 })).status, 400);
      assert.equal((await a.call('PUT', '/v1/me/character', { name: 'Ixchel', color: '#ff0000', hat: 9 })).status, 400);
      const ok = await (await a.call('PUT', '/v1/me/character', { name: '  Ixchel <b> ', color: '#E4007C', hat: 2 })).json();
      assert.deepEqual(ok.character, { name: 'Ixchel b', color: '#e4007c', hat: 2 });
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
    const dir = path.resolve(import.meta.dirname, '../../../supabase/migrations');
    const client = new pg.Client({ connectionString: url });
    await client.connect();
    await client.query('drop schema public cascade; create schema public;');
    for (const f of fs.readdirSync(dir).sort()) await client.query(fs.readFileSync(path.join(dir, f), 'utf8'));
    await client.end();
    return new PgStore(url);
  });
}
