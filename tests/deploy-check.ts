// Comprueba un despliegue real por HTTPS/WSS: sesión, perfil guardado en la base de datos,
// sala, ticket y entrada al servidor de juego a través del proxy.
//   npx tsx tests/deploy-check.ts https://localhost
import assert from 'node:assert/strict';
import { PROTOCOL_VERSION } from '@alux/shared-contracts';

const base = (process.argv[2] || 'https://localhost').replace(/\/$/, '');
let cookie = '';

async function call(path: string, init: RequestInit = {}) {
  const res = await fetch(base + path, {
    redirect: 'manual',
    ...init,
    headers: { ...(cookie ? { cookie } : {}), 'x-alux-csrf': '1', ...(init.headers ?? {}) },
  });
  const set = res.headers.getSetCookie?.() ?? [];
  for (const c of set) {
    const [pair] = c.split(';');
    if (pair.startsWith('alux_session=')) cookie = pair;
  }
  return res;
}

// 1) Portal por HTTPS y cabeceras
const home = await call('/');
assert.equal(home.status, 200, 'la portada responde');
assert.match(await home.text(), /ALUX/);
console.log('✓ Portal servido por HTTPS');

// 2) Las rutas internas de la API no están expuestas
for (const p of ['/internal/game/rewards', '/api/internal/game/rewards', '/api/v1/../internal/players/upsert']) {
  const r = await call(p, { method: 'POST', body: '{}', headers: { 'content-type': 'application/json' } });
  assert.ok(r.status === 404 || r.status === 405 || r.status === 400, `${p} no debe ser accesible (respondió ${r.status})`);
}
console.log('✓ Rutas internas inaccesibles desde fuera');

// 3) Sesión (entrada de prueba), perfil y persistencia en PostgreSQL
const login = await call('/auth/dev', { method: 'POST', body: new URLSearchParams({ name: 'Despliegue' }) });
assert.equal(login.status, 303);
assert.ok(cookie, 'se recibió la cookie de sesión');
assert.match(login.headers.getSetCookie().join(';'), /Secure/i, 'la cookie de sesión lleva Secure bajo HTTPS');
const saved = await call('/api/v1/me/character', {
  method: 'PUT', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ name: 'Ixchel', color: '#e4007c', hat: 2 }),
});
assert.equal(saved.status, 200);
const me = await (await call('/api/v1/me')).json();
assert.deepEqual(me.character, { name: 'Ixchel', color: '#e4007c', hat: 2 });
console.log('✓ Sesión, perfil y guardado en la base de datos');

// 4) Sala y ticket
const room = await (await call('/api/v1/rooms', { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' })).json();
const t = await (await call(`/api/v1/rooms/${room.code}/ticket`, { method: 'POST' })).json();
assert.match(t.wsUrl, /^wss:\/\//, 'el servidor de juego se anuncia por wss://');
console.log(`✓ Sala ${room.code} y ticket (${t.wsUrl})`);

// 5) Entrar al servidor de juego por WebSocket seguro a través del proxy
const welcome: any = await new Promise((resolve, reject) => {
  const ws = new WebSocket(t.wsUrl);
  const timer = setTimeout(() => reject(new Error('sin respuesta del servidor de juego')), 15000);
  ws.onopen = () => ws.send(JSON.stringify({ t: 'hello', v: PROTOCOL_VERSION, ticket: t.ticket }));
  ws.onmessage = (ev) => {
    const m = JSON.parse(String(ev.data));
    if (m.t === 'welcome' || m.t === 'error') { clearTimeout(timer); ws.close(); resolve(m); }
  };
  ws.onerror = () => { clearTimeout(timer); reject(new Error('fallo de conexión WSS')); };
});
assert.equal(welcome.t, 'welcome', `el servidor respondió ${JSON.stringify(welcome)}`);
assert.equal(welcome.id, me.id);
assert.equal(welcome.room, room.code);
console.log('✓ Conexión wss:// al servidor de juego a través del proxy');

// 6) El servidor de juego habla con la API (latido): la sala muestra al jugador
await new Promise((r) => setTimeout(r, 4500));
const info = await (await call(`/api/v1/rooms/${room.code}`)).json();
assert.ok(info.members.some((m: any) => m.id === me.id), 'la API registra al jugador en la sala');
console.log('✓ Servidor de juego ↔ API\n\nDespliegue verificado.');
