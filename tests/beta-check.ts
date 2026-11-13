// Comprobación de disponibilidad de un despliegue de ALUX (beta privada), desde fuera.
//
//   npm run beta:check -- https://alux-beta.onrender.com
//   npm run beta:check -- https://alux-beta.onrender.com --code ALUX-XXXXX-XXXXX-XXXXX-XXXXX
//
// Sin código comprueba todo lo público: portal por HTTPS, salud de la API y de la base de datos,
// que no haya entradas abiertas ni rutas internas, la descarga del juego y el WebSocket seguro.
// Con el código de un tester, además entra como él y recorre el camino completo: sesión,
// guardado, sala, ticket, partida por wss:// (estados y latencia) y registro de métricas.
// No imprime el código ni ninguna cookie. Termina con código de salida 1 si algo falla.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import http from 'node:http';
import https from 'node:https';
import { PROTOCOL_VERSION } from '@alux/shared-contracts';

const args = process.argv.slice(2);
const base = (args.find((a) => /^https?:\/\//.test(a)) || '').replace(/\/$/, '');
const flag = (name: string) => (args.includes(`--${name}`) ? args[args.indexOf(`--${name}`) + 1] : '');
const code = flag('code') || process.env.BETA_CODE || '';
// Para comprobar la persistencia tras un reinicio: --mark deja un nombre de alux y --expect lo exige
const mark = flag('mark');
const expect = flag('expect');
// --commit <hash> exige que la versión desplegada sea exactamente ese commit
const wantCommit = flag('commit').toLowerCase();
if (!base) {
  console.error('Uso: npm run beta:check -- https://tu-servicio.onrender.com [--code ALUX-…]');
  process.exit(1);
}
const secure = base.startsWith('https://');
const wsBase = base.replace(/^http/, 'ws');
let cookie = '';
let failed = 0;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function call(path: string, init: RequestInit = {}) {
  const res = await fetch(base + path, {
    redirect: 'manual', ...init,
    headers: { ...(cookie ? { cookie } : {}), 'x-alux-csrf': '1', ...(init.headers ?? {}) },
  });
  for (const c of res.headers.getSetCookie?.() ?? []) {
    const [pair] = c.split(';');
    if (pair.startsWith('alux_session=')) cookie = pair;
  }
  return res;
}

async function step(name: string, fn: () => Promise<string | void>) {
  const t0 = performance.now();
  try {
    const note = await fn();
    console.log(`✓ ${name}${note ? `  ·  ${note}` : ''}  (${Math.round(performance.now() - t0)} ms)`);
  } catch (err) {
    failed++;
    console.log(`✗ ${name}\n    ${(err as Error).message.split('\n')[0]}`);
  }
}

/** Abre el WebSocket del juego, manda `hello` y devuelve el primer mensaje del servidor. */
function hello(url: string, ticket: string, onOpen?: (ws: WebSocket) => void): Promise<{ msg: any; ws: WebSocket }> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    const timer = setTimeout(() => { ws.close(); reject(new Error('el servidor de juego no respondió en 20 s')); }, 20_000);
    ws.onopen = () => { ws.send(JSON.stringify({ t: 'hello', v: PROTOCOL_VERSION, ticket })); onOpen?.(ws); };
    ws.onmessage = (ev) => {
      const m = JSON.parse(String(ev.data));
      if (m.t === 'welcome' || m.t === 'error') { clearTimeout(timer); resolve({ msg: m, ws }); }
    };
    ws.onerror = () => { clearTimeout(timer); reject(new Error(`no se pudo abrir ${url} (¿el proxy deja pasar WebSocket?)`)); };
  });
}

console.log(`Comprobando ${base}${code ? ' con una invitación de tester' : ''}\n`);

await step('Portal accesible', async () => {
  const res = await call('/');
  assert.equal(res.status, 200, `la portada respondió ${res.status}`);
  const html = await res.text();
  assert.match(html, /ALUX/);
  if (secure) assert.ok(res.headers.get('strict-transport-security'), 'falta la cabecera HSTS');
  assert.ok(!/action="\/auth\/dev"/.test(html), 'la entrada de prueba sin restricciones está visible: debe estar desactivada');
  const how = /action="\/auth\/beta"/.test(html) ? 'invitación de tester' : /\/auth\/discord/.test(html) ? 'Discord' : 'ninguna';
  assert.notEqual(how, 'ninguna', 'no hay ninguna forma de iniciar sesión (faltan BETA_INVITES o Discord)');
  return `${secure ? 'HTTPS' : 'HTTP (¡sin cifrar!)'} · entrada: ${how} · buscadores: ${res.headers.get('x-robots-tag') || 'sin restricción'}`;
});

await step('API y base de datos', async () => {
  const res = await call('/healthz');
  assert.equal(res.status, 200, `/healthz respondió ${res.status}`);
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.equal(body.db, true, 'la API no alcanza la base de datos');
  const deployed = String(body.commit || '');
  if (wantCommit) {
    assert.ok(deployed, 'el servicio no informa de qué commit tiene desplegado');
    assert.ok(deployed.startsWith(wantCommit) || wantCommit.startsWith(deployed), `está desplegado ${deployed.slice(0, 12)}, no ${wantCommit.slice(0, 12)}`);
  }
  return `la base de datos responde · versión desplegada: ${deployed ? deployed.slice(0, 12) : 'no informada'}`;
});

await step('Nada abierto sin sesión', async () => {
  for (const p of ['/internal/game/rewards', '/api/internal/game/rewards', '/api/v1/../internal/players/upsert', '/internal/players/upsert']) {
    const r = await call(p, { method: 'POST', body: '{}', headers: { 'content-type': 'application/json' } });
    assert.ok([400, 404, 405].includes(r.status), `${p} no debe ser accesible (respondió ${r.status})`);
  }
  assert.equal((await call('/api/v1/me')).status, 401, 'el perfil no debe servirse sin sesión');
  assert.equal((await call('/api/v1/rooms', { method: 'POST', body: '{}', headers: { 'content-type': 'application/json' } })).status, 401);
  assert.equal((await call('/api/v1/telemetry', { method: 'POST', body: '{}', headers: { 'content-type': 'application/json' } })).status, 401);
  const dev = await call('/auth/dev', { method: 'POST', body: new URLSearchParams({ name: 'Intruso' }) });
  assert.ok(!cookie, 'la entrada de prueba sin restricciones dio una sesión');
  assert.match(dev.headers.get('location') ?? '', /error=/, 'la entrada de prueba debe rechazarse');
  const bad = await call('/auth/beta', { method: 'POST', body: new URLSearchParams({ code: 'ALUX-AAAAA-AAAAA-AAAAA-AAAAA' }) });
  assert.ok(!cookie, 'un código inventado dio una sesión');
  assert.match(bad.headers.get('location') ?? '', /error=beta_/, 'un código inventado debe rechazarse');
  return 'rutas internas cerradas, sin entrada anónima, códigos inventados rechazados';
});

await step('Descarga del juego', async () => {
  const page = await call('/game/index.html');
  assert.equal(page.status, 200, `/game/index.html respondió ${page.status}`);
  let total = 0;
  const parts: string[] = [];
  for (const f of ['index.js', 'index.pck', 'index.wasm']) {
    // Se cuentan los bytes tal como viajan (comprimidos), pidiéndolos como lo hace un navegador
    const got = await new Promise<{ status: number; bytes: number; encoding: string }>((resolve, reject) => {
      const req = (secure ? https : http).get(`${base}/game/${f}`, { headers: { 'accept-encoding': 'br, gzip' } }, (res) => {
        let bytes = 0;
        res.on('data', (chunk: Buffer) => { bytes += chunk.length; });
        res.on('end', () => resolve({ status: res.statusCode ?? 0, bytes, encoding: String(res.headers['content-encoding'] ?? '') }));
        res.on('error', reject);
      });
      req.on('error', reject);
      req.setTimeout(120_000, () => req.destroy(new Error(`la descarga de ${f} tardó demasiado`)));
    });
    assert.equal(got.status, 200, `/game/${f} respondió ${got.status}`);
    total += got.bytes;
    parts.push(`${f} ${(got.bytes / 1048576).toFixed(1)} MB${got.encoding ? ` (${got.encoding})` : ''}`);
  }
  return `${parts.join(', ')} · total transferido ${(total / 1048576).toFixed(1)} MB`;
});

// Desde la Alpha 0.3.1 la música, los ambientes y las bandas sonoras de las cinemáticas se sirven
// aparte: tienen que estar todos los archivos que declaran los manifiestos, con su tamaño.
await step('Audio del juego', async () => {
  const mixer = await fetch(`${base}/game/alux-audio.js`);
  if (mixer.status === 404) return 'esta versión no trae mezclador de audio (anterior a la 0.3.1)';
  assert.equal(mixer.status, 200, `/game/alux-audio.js respondió ${mixer.status}`);
  let files = 0, bytes = 0;
  const groups: string[] = [];
  for (const name of ['musica', 'ambiente', 'cine']) {
    const res = await fetch(`${base}/game/audio/${name}.json`);
    assert.equal(res.status, 200, `/game/audio/${name}.json respondió ${res.status}`);
    const tracks = Object.values(((await res.json()) as { tracks: Record<string, { file: string; bytes: number }> }).tracks);
    assert.ok(tracks.length > 0, `${name}.json no declara ninguna pista`);
    for (const tr of tracks) {
      const head = await fetch(`${base}/game/audio/${tr.file}`, { method: 'HEAD' });
      assert.equal(head.status, 200, `/game/audio/${tr.file} respondió ${head.status}`);
      const size = Number(head.headers.get('content-length') ?? tr.bytes);
      assert.equal(size, tr.bytes, `${tr.file}: ${size} bytes servidos, ${tr.bytes} declarados`);
      assert.match(head.headers.get('content-type') ?? '', /audio\/mpeg/, `${tr.file} se sirve como ${head.headers.get('content-type')}`);
      files++;
      bytes += tr.bytes;
    }
    groups.push(`${tracks.length} de ${name}`);
  }
  return `mezclador y ${files} pistas (${groups.join(', ')}) · ${(bytes / 1048576).toFixed(1)} MB bajo demanda`;
});

await step('WebSocket seguro al servidor de juego', async () => {
  const { msg, ws } = await hello(`${wsBase}/ws`, 'ticket-inventado');
  ws.close();
  assert.equal(msg.t, 'error', 'un ticket inventado debe rechazarse');
  assert.equal(msg.code, 'bad_ticket');
  return `${secure ? 'wss' : 'ws'}:// abre y el servidor rechaza tickets falsos`;
});

if (code) {
  let me: any = null;
  let room: any = null;
  await step('Sesión de tester con invitación', async () => {
    const res = await call('/auth/beta', { method: 'POST', body: new URLSearchParams({ code }) });
    assert.equal(res.status, 303);
    assert.ok(cookie, `no se recibió sesión (${res.headers.get('location')})`);
    if (secure) assert.match(res.headers.getSetCookie().join(';'), /Secure/i, 'la cookie de sesión debe llevar Secure');
    assert.match(res.headers.getSetCookie().join(';'), /HttpOnly/i);
    me = await (await call('/api/v1/me')).json();
    assert.equal(me.provider, 'beta');
    return `jugador ${String(me.id).slice(0, 8)} «${me.character.name}»`;
  });

  if (expect) {
    await step('Persistencia tras el reinicio', async () => {
      assert.ok(me, 'sin sesión');
      assert.equal(me.character.name, expect, `el alux se llama «${me.character.name}»: los datos no sobrevivieron`);
      return `el alux «${expect}» sigue ahí con el mismo jugador`;
    });
  }

  await step('Guardado en la base de datos', async () => {
    assert.ok(me, 'sin sesión');
    const want = { ...me.character, hat: (me.character.hat + 1) % 4 };
    assert.equal((await call('/api/v1/me/character', { method: 'PUT', headers: { 'content-type': 'application/json' }, body: JSON.stringify(want) })).status, 200);
    assert.deepEqual((await (await call('/api/v1/me')).json()).character, want);
    // se deja como estaba (o con el nombre pedido en --mark, para comprobar luego que persiste)
    const keep = mark ? { ...me.character, name: mark } : me.character;
    await call('/api/v1/me/character', { method: 'PUT', headers: { 'content-type': 'application/json' }, body: JSON.stringify(keep) });
    return `sellos: ${me.rewards.length ? me.rewards.join(', ') : 'ninguno todavía'}`;
  });

  await step('Sala, ticket y partida por WebSocket seguro', async () => {
    assert.ok(me, 'sin sesión');
    room = await (await call('/api/v1/rooms', { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' })).json();
    assert.match(room.code ?? '', /^[A-Z0-9]{4,12}$/, 'no se pudo crear la sala');
    const t = await (await call(`/api/v1/rooms/${room.code}/ticket`, { method: 'POST' })).json();
    if (secure) assert.match(t.wsUrl, /^wss:\/\//, `el servidor de juego se anuncia como ${t.wsUrl}: debe ser wss://`);
    assert.equal(new URL(t.wsUrl).host, new URL(base).host, 'el WebSocket debe ir por el mismo dominio que el portal');
    const { msg, ws } = await hello(t.wsUrl, t.ticket);
    assert.equal(msg.t, 'welcome', `el servidor respondió ${JSON.stringify(msg).slice(0, 120)}`);
    assert.equal(msg.id, me.id);
    // Cuatro segundos de partida: el personaje camina, llegan estados y se mide la latencia
    let snaps = 0, seq = 0, moved = 0;
    const rtts: number[] = [];
    const x0 = msg.me[0], z0 = msg.me[2];
    ws.onmessage = (ev) => {
      const m = JSON.parse(String(ev.data));
      if (m.t === 'snap') {
        snaps++;
        const p = m.p.find((q: number[]) => q[0] === msg.slot);
        if (p) moved = Math.hypot(p[4] - x0, p[6] - z0);
      } else if (m.t === 'pong') rtts.push(performance.now() - m.c);
    };
    const input = setInterval(() => ws.send(JSON.stringify({ t: 'in', s: ++seq, mx: 0, mz: 1, j: 0, f: '', a: 0, r: 0 })), 33);
    const ping = setInterval(() => ws.send(JSON.stringify({ t: 'ping', c: performance.now() })), 400);
    await sleep(4000);
    clearInterval(input);
    clearInterval(ping);
    ws.close();
    assert.ok(snaps >= 40, `llegaron ${snaps} estados en 4 s (se esperan unos 60)`);
    assert.ok(moved > 5, `el personaje avanzó ${moved.toFixed(1)} m (se esperaban unos 20)`);
    assert.ok(rtts.length > 3, 'no llegaron respuestas de latencia');
    rtts.sort((a, b) => a - b);
    return `sala ${room.code} · ${(snaps / 4).toFixed(0)} estados/s · avanzó ${moved.toFixed(1)} m · latencia ${rtts[Math.floor(rtts.length / 2)].toFixed(0)} ms (máx. ${rtts[rtts.length - 1].toFixed(0)})`;
  });

  await step('Reconexión tras un corte', async () => {
    assert.ok(room?.code, 'sin sala');
    // La conexión anterior ya se cerró de golpe: se vuelve a entrar con un ticket nuevo, como hace el juego
    const t = await (await call(`/api/v1/rooms/${room.code}/ticket`, { method: 'POST' })).json();
    assert.ok(t.ticket, 'no se pudo pedir un ticket nuevo');
    const { msg, ws } = await hello(t.wsUrl, t.ticket);
    ws.close();
    assert.equal(msg.t, 'welcome', `el servidor respondió ${JSON.stringify(msg).slice(0, 120)}`);
    assert.equal(msg.rejoin, true, 'el servidor debe reconocer que es el mismo jugador que vuelve');
    assert.equal(msg.id, me.id);
    const z = msg.me[2];
    assert.ok(Math.abs(z - 3.2) > 5, `debería conservar la posición a la que caminó (está en z=${z.toFixed(1)})`);
    return `mismo jugador, mismo lugar (${msg.slot}) y la posición donde se quedó (z = ${z.toFixed(1)})`;
  });

  await step('Servidor de juego ↔ API y métricas de sesión', async () => {
    assert.ok(room?.code, 'sin sala');
    const info = await (await call(`/api/v1/rooms/${room.code}`)).json();
    assert.ok(info.members.some((m: any) => m.id === me.id), 'la API no registró al jugador en la sala');
    const res = await call('/api/v1/telemetry', {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ sid: randomUUID(), room: room.code, quality: 'min', fpsAvg: 0, seconds: 4, build: 'beta-check', final: true }),
    });
    assert.equal(res.status, 200, `las métricas respondieron ${res.status}`);
    return 'latido recibido y métricas guardadas';
  });
}

console.log(failed ? `\n${failed} comprobación(es) fallaron.` : `\nTodo en orden${code ? '' : ' (sin --code sólo se comprueba la parte pública)'}.`);
process.exit(failed ? 1 : 0);
