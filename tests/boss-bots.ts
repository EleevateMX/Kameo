// Bots que pelean contra Nojoch Tuunich como lo haría un grupo que entiende el combate.
// Los usan la prueba de protocolo (sin navegador) y la de navegador con el combate completo.
import { BOSS_STATES } from '@alux/shared-contracts';

export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** Lo mínimo que necesita un bot: su último estado, su jugador y cómo mandar una entrada. */
export interface BossBot {
  snap: any;
  me(): number[] | undefined;
  dead(): boolean;
  input(mx: number, mz: number, extra?: { j?: 0 | 1; f?: string; a?: number; r?: number }): void;
  foes(): { id: number; kind: number; x: number; z: number; hp: number; maxHp: number; state: string }[];
}
type Bot = BossBot;

/** Índices del estado del jefe (campo «b» de cada instantánea). */
export const B = { phase: 0, x: 1, z: 2, state: 4, silence: 6, glyphs: 7, needed: 8, aimX: 10, aimZ: 11, rubble: 13,
  anchors: 14, anchorsNeed: 15, pillars: 16, heart: 17, releases: 18, lit: 19, litNeed: 20, ritual: 21, channel: 22, touchNeed: 23, walls: 24, wallsLeft: 25 } as const;
/** Muros del patio (campo `walls`): cerrados, abriéndose (siguen siendo sólidos) o abiertos. */
export const WALLS = { shut: 0, opening: 1, open: 2 } as const;
export const BOSS_STATE = [...BOSS_STATES] as string[];
export const inCourt = (x: number, z: number) => x > 22.9 && x < 33.1 && Math.abs(z) < 5.1;

/**
 * Un bot pelea la fase 1 como lo haría un jugador que la entiende: entra al patio, se aparta del
 * golpe de losa, debilita a una criatura con chispas (sin romperla) y la toca cerca del guardián.
 */
export async function bossPhase1(bot: Bot, index: number, done: () => boolean, maxSeconds: number) {
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

export const ANCHORS = [[10.8, -5], [10.8, 5], [19.4, 6.2], [8.4, 0]];
export const SOCKETS = [[12.6, -2.6], [12.6, 2.6], [18.2, 2.8], [15.5, -6], [14.6, 5.4], [18.4, -2.2]];
/** Dónde se coloca cada uno para tocarlo: fuera del pulso de Silencio, dentro del alcance del contacto. */
export const RITUAL_SPOTS = [[0, -4.1], [4.1, 0], [0, 4.1], [-4.1, 0]];

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
export async function bossPhase2(bot: Bot, index: number, n: number, done: () => boolean, maxSeconds: number) {
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
    if (st === 'kneel' || st === 'transit' || st === 'leap_w' || st === 'leap' || st === 'rise' || st === 'sleep') {
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
export async function bossPhase3(bot: Bot, index: number, done: () => boolean, maxSeconds: number, away = false) {
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
        go(boss.x + RITUAL_SPOTS[index][0], boss.z + RITUAL_SPOTS[index][1]);
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

