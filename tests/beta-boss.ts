// Sesión completa de un jugador contra un despliegue, por el protocolo real y sin navegador:
// entra con una invitación, abre el santuario, vence la emboscada y libera a Nojoch Tuunich
// (tres fases). Comprueba que el servidor desplegado lleva el combate de principio a fin por
// HTTPS/WSS, que las cinemáticas se anuncian, que la Pluma de Jade queda guardada en el perfil y
// que la pista del Cenote se anota. Mide latencia y ritmo de estados.
//
//   npx tsx beta-boss.ts https://alux-beta.onrender.com --code ALUX-…      (o BETA_CODE=…)
//
// Juega como un jugador solo que conoce el combate (los mismos bots de las pruebas locales). No
// imprime el código ni ninguna cookie. Termina con código de salida 1 si algo falla.
import assert from 'node:assert/strict';
import { ENEMY_STATES, PROTOCOL_VERSION } from '@alux/shared-contracts';
import { B, BOSS_STATE, bossPhase1, bossPhase2, bossPhase3, inCourt, type BossBot } from './boss-bots.ts';

const args = process.argv.slice(2);
const base = (args.find((a) => /^https?:\/\//.test(a)) || '').replace(/\/$/, '');
const flag = (name: string) => (args.includes(`--${name}`) ? args[args.indexOf(`--${name}`) + 1] : '');
const code = flag('code') || process.env.BETA_CODE || '';
if (!base || !code) {
  console.error('Uso: npx tsx beta-boss.ts https://tu-servicio.onrender.com --code ALUX-…');
  process.exit(1);
}
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const ok = (msg: string) => console.log(`✓ ${msg}`);
let cookie = '';
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

class Solo implements BossBot {
  ws!: WebSocket;
  snap: any = null;
  slot = -1;
  seq = 0;
  events: any[] = [];
  combat: (string | number)[][] = [];
  rtts: number[] = [];
  snaps = 0;
  closed = false;
  connect(url: string, ticket: string) {
    return new Promise<void>((resolve, reject) => {
      const ws = new WebSocket(url);
      this.ws = ws;
      const timer = setTimeout(() => reject(new Error('el servidor de juego no respondió')), 20_000);
      ws.onopen = () => ws.send(JSON.stringify({ t: 'hello', v: PROTOCOL_VERSION, ticket }));
      ws.onmessage = (ev) => {
        const m = JSON.parse(String(ev.data));
        if (m.t === 'welcome') { this.slot = m.slot; clearTimeout(timer); resolve(); }
        else if (m.t === 'snap') { this.snap = m; this.snaps++; if (m.ev?.length) this.combat.push(...m.ev); }
        else if (m.t === 'pong') this.rtts.push(performance.now() - m.c);
        else if (m.t === 'event') {
          this.events.push(m);
          // Las cinemáticas compartidas: un jugador solo las omite al instante (aquí no hay nada que ver)
          if (m.e === 'cine_prep') ws.send(JSON.stringify({ t: 'cine_ready', id: m.id, v: 0 }));
          if (m.e === 'cine') ws.send(JSON.stringify({ t: 'skip' }));
        } else if (m.t === 'error') { clearTimeout(timer); reject(new Error(`el servidor rechazó la entrada: ${m.code}`)); }
      };
      ws.onclose = () => { this.closed = true; };
      ws.onerror = () => { clearTimeout(timer); reject(new Error(`no se pudo abrir ${url}`)); };
    });
  }
  me(): number[] | undefined { return this.snap?.p.find((p: number[]) => p[0] === this.slot); }
  dead() { const m = this.me(); return m ? (m[11] & 8) !== 0 : false; }
  hp() { return this.me()?.[3] ?? 0; }
  foes() {
    return ((this.snap?.e ?? []) as number[][])
      .map((e) => ({ id: e[0], kind: e[1], x: e[2], z: e[4], hp: e[6], maxHp: e[7], state: ENEMY_STATES[e[8]] }))
      .filter((e) => e.state !== 'dead');
  }
  input(mx: number, mz: number, extra: { j?: 0 | 1; f?: string; a?: number; r?: number } = {}) {
    if (this.ws.readyState !== WebSocket.OPEN) return;
    this.ws.send(JSON.stringify({ t: 'in', s: ++this.seq, mx, mz, j: extra.j ?? 0, f: extra.f ?? '', a: extra.a ?? 0, r: extra.r ?? 0 }));
  }
  async walkTo(x: number, z: number, maxSeconds: number, f = '') {
    const end = Date.now() + maxSeconds * 1000;
    while (Date.now() < end) {
      const m = this.me();
      if (m) {
        const dx = x - m[4], dz = z - m[6], d = Math.hypot(dx, dz);
        if (d < 0.4) return true;
        this.input(dx / d, dz / d, { f });
      }
      await sleep(33);
    }
    return false;
  }
  /** Pelea contra el enemigo más cercano que cumpla `pick` hasta que `until` sea cierto. */
  async fight(pick: (f: { x: number; z: number }) => boolean, until: () => boolean, maxSeconds: number) {
    const end = Date.now() + maxSeconds * 1000;
    while (Date.now() < end && !until()) {
      const m = this.me();
      const foe = m && this.foes().filter(pick).sort((p, q) => Math.hypot(p.x - m[4], p.z - m[6]) - Math.hypot(q.x - m[4], q.z - m[6]))[0];
      if (m && foe && !this.dead()) {
        const dx = foe.x - m[4], dz = foe.z - m[6], d = Math.hypot(dx, dz) || 1;
        const near = d < 1.9;
        this.input(near ? 0 : dx / d, near ? 0 : dz / d, { a: near ? 1 : 0, r: Math.atan2(dx, dz), f: 'balam' });
      } else this.input(0, 0);
      await sleep(33);
    }
    return until();
  }
}

const started = Date.now();
const mark = () => ((Date.now() - started) / 1000).toFixed(0);
const until = async (what: string, cond: () => boolean, ms: number) => {
  const end = Date.now() + ms;
  while (Date.now() < end) { if (cond()) return; await sleep(50); }
  throw new Error(`no ocurrió a tiempo: ${what}`);
};

try {
  // 1) Sesión con invitación, sala y ticket
  const login = await call('/auth/beta', { method: 'POST', body: new URLSearchParams({ code }) });
  assert.equal(login.status, 303, 'la invitación no dio sesión');
  assert.ok(cookie, 'sin cookie de sesión');
  const before = await (await call('/api/v1/me')).json();
  const health = await (await call('/healthz')).json().catch(() => ({}));
  const room = await (await call('/api/v1/rooms', { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' })).json();
  assert.match(room.code ?? '', /^[A-Z0-9]{4,12}$/, 'no se pudo crear la sala');
  const t = await (await call(`/api/v1/rooms/${room.code}/ticket`, { method: 'POST' })).json();
  if (base.startsWith('https://')) assert.match(t.wsUrl, /^wss:\/\//, 'el servidor de juego debe anunciarse por wss://');
  const bot = new Solo();
  await bot.connect(t.wsUrl, t.ticket);
  const pings = setInterval(() => { if (bot.ws.readyState === WebSocket.OPEN) bot.ws.send(JSON.stringify({ t: 'ping', c: performance.now() })); }, 1000);
  await until('primer estado', () => bot.snap !== null && bot.me() !== undefined, 15_000);
  const b = () => bot.snap.b as number[];
  assert.ok(Array.isArray(b()) && b().length >= 24, `el servidor desplegado no trae el jefe completo (estado de ${b()?.length ?? 0} campos)`);
  ok(`Sesión por ${t.wsUrl.split('://')[0]}:// en la sala ${room.code} · versión desplegada ${String(health.commit ?? health.version ?? '¿?').slice(0, 12)} · el perfil tenía: ${before.rewards.join(', ') || 'nada'}`);

  // 2) Altar, «El sello cede» y emboscada (solo: si cae, se reintenta como haría un jugador)
  let defeats = 0;
  for (let attempt = 0; attempt < 6 && bot.snap.w[3] !== 2; attempt++) {
    await bot.fight(() => false, () => !bot.dead() && bot.snap.w[9] === 0 && bot.snap.w[3] !== 3, 30);
    await bot.walkTo(17.5, -5, 40);
    await until('emboscada en curso', () => bot.snap.w[3] === 1 && bot.snap.w[13] === 0, 30_000);
    await bot.fight((f) => Math.hypot(f.x - 15, f.z) < 26 && !inCourt(f.x, f.z), () => bot.snap.w[3] === 2 || bot.snap.w[3] === 3, 150);
    if (bot.snap.w[3] === 3) defeats++;
  }
  assert.equal(bot.snap.w[3], 2, 'la emboscada no se superó');
  assert.ok(bot.events.some((e) => e.e === 'cine_prep' && e.id === 'sello'), '«El sello cede» no se anunció');
  await until('Sello del Claro', () => bot.events.some((e) => e.e === 'reward' && e.reward === 'sello_del_claro'), 15_000);
  const tAmbush = mark();
  ok(`Emboscada superada a los ${tAmbush} s (${defeats} derrota(s) antes) · «El sello cede» anunciada · Sello del Claro ${bot.events.find((e) => e.e === 'reward' && e.reward === 'sello_del_claro').saved ? 'guardado' : 'SIN GUARDAR'}`);

  // 3) Las tres fases del guardián
  const phase = () => b()[B.phase];
  assert.equal(phase(), 0, 'el guardián debería dormir hasta que alguien entre al patio');
  assert.equal(await bossPhase1(bot, 0, () => phase() >= 2, 420), true, `la fase 1 no se completó (glifos ${b()[B.glyphs]}/${b()[B.needed]})`);
  assert.ok(bot.events.some((e) => e.e === 'cine_prep' && e.id === 'despertar'), '«El despertar» no se anunció');
  const t1 = mark();
  ok(`Fase 1 «Olvido» completada a los ${t1} s · «El despertar» anunciada · Silencio ${b()[B.silence]}`);
  for (let attempt = 0; attempt < 4 && phase() < 3; attempt++) {
    await bossPhase2(bot, 0, 1, () => phase() >= 3, 300);
  }
  assert.ok(phase() >= 3, `la fase 2 no se completó (corazones ${b()[B.releases]}/3)`);
  const t2 = mark();
  ok(`Fase 2 «Furia» completada a los ${t2} s · el guardián en la explanada (x=${b()[B.x]}) · Silencio ${b()[B.silence]}`);
  for (let attempt = 0; attempt < 4 && phase() !== 4; attempt++) {
    await bossPhase3(bot, 0, () => phase() === 4 || phase() === 0, 240);
    if (phase() === 0) await bossPhase2(bot, 0, 1, () => phase() === 3, 60);   // cayó: se acerca y lo despierta en su fase
  }
  assert.equal(phase(), 4, `el guardián no quedó liberado (glifos ${b()[B.lit]}/${b()[B.litNeed]}, contacto ${b()[B.ritual]} %)`);
  const t3 = mark();
  await until('Pluma de Jade', () => bot.events.some((e) => e.e === 'reward' && e.reward === 'pluma_de_jade'), 20_000);
  await until('fin de «La liberación»', () => bot.snap.w[13] === 0, 30_000);
  const feather = bot.events.find((e) => e.e === 'reward' && e.reward === 'pluma_de_jade');
  assert.equal(feather.saved, true, 'la Pluma de Jade no se guardó');
  assert.ok(bot.events.some((e) => e.e === 'cine_prep' && e.id === 'liberacion'), '«La liberación» no se anunció');
  assert.equal(bot.snap.w[10] & 2, 2, 'la liberación no quedó en la historia de la sala');
  const fails = bot.combat.filter((e) => e[0] === 'boss' && e[1] === 'fail').length;
  const falls = bot.combat.filter((e) => e[0] === 'die' && e[1] === 'p').length;
  ok(`Fase 3 «Recuerdo» y liberación a los ${t3} s · «La liberación» anunciada · Pluma de Jade guardada (${feather.new ? 'nueva' : 'ya la tenía'}) · ${fails} derrota(s) ante el jefe, ${falls} caída(s) en total`);

  // 4) La pista del Cenote y lo que quedó en el perfil
  await bot.walkTo(b()[B.x] - 3, 0.5, 30, 'alux');
  bot.ws.send(JSON.stringify({ t: 'talk', n: 'nojoch' }));
  await until('pista del Cenote', () => (bot.snap.w[10] & 4) === 4, 10_000);
  const after = await (await call('/api/v1/me')).json();
  assert.equal(after.rewards.filter((r: string) => r === 'pluma_de_jade').length, 1, 'la Pluma de Jade debe estar una sola vez en el perfil');
  assert.equal(after.quests.cap1_guardian, 'completed');
  ok(`Pista del Cenote anotada por el servidor · perfil: ${after.rewards.join(', ')}`);

  // 5) Red
  clearInterval(pings);
  const rtt = bot.rtts.length ? bot.rtts.reduce((p, q) => p + q, 0) / bot.rtts.length : NaN;
  const secs = (Date.now() - started) / 1000;
  console.log(`Red: latencia media ${rtt.toFixed(0)} ms (máx. ${Math.max(...bot.rtts).toFixed(0)}) · ${(bot.snaps / secs).toFixed(1)} estados/s durante ${secs.toFixed(0)} s · conexión ${bot.closed ? 'CORTADA' : 'sin cortes'}`);
  assert.equal(bot.closed, false, 'la conexión se cortó durante la sesión');
  bot.ws.close();
  console.log(`Sesión completa verificada contra ${base}.`);
  process.exit(0);
} catch (err) {
  console.error(`✗ ${(err as Error).message}`);
  process.exit(1);
}
