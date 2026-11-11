// Simulación autoritativa del mundo de ALUX.
// El navegador sólo envía "intenciones" (teclas, apuntado); aquí se decide
// todo lo demás: movimiento, daño, enemigos, cubos y el jefe.
import {
  TICK_RATE, SNAPSHOT_RATE, DISTRICTS, FORMS, FORM_ORDER, ENEMIES, CUBES,
  CUBE_HP, CUBE_R, CUBE_RESPAWN, SPAWN, BOSS_SPAWN, BOSS_RESPAWN,
  levelFromXp, xpForLevel, districtAt,
} from '../shared/config.js';
import { resolveCollisions, moveEntity, pointInBuilding, isFree } from '../shared/physics.js';

const rnd = (a, b) => a + Math.random() * (b - a);
const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
const angDiff = (a, b) => {
  let d = a - b;
  while (d > Math.PI) d -= Math.PI * 2;
  while (d < -Math.PI) d += Math.PI * 2;
  return Math.abs(d);
};
const round = (n) => Math.round(n);
const SAFE_RADIUS = 240;

export class Game {
  constructor(io, store) {
    this.io = io;
    this.store = store;
    this.time = 0;
    this.nextId = 1;
    this.players = new Map();
    this.enemies = [];
    this.projectiles = [];
    this.events = [];
    this.boss = null;
    this.bossRespawnAt = 0;
    this.spawnTimer = 0;
    this.cubes = CUBES.map((c) => ({ ...c, hp: CUBE_HP, on: true, respawnAt: 0, contrib: new Set() }));
  }

  start() {
    let last = performance.now();
    setInterval(() => {
      const now = performance.now();
      const dt = Math.min(0.1, (now - last) / 1000);
      last = now;
      this.update(dt);
    }, 1000 / TICK_RATE);
    setInterval(() => this.broadcast(), 1000 / SNAPSHOT_RATE);
    setInterval(() => this.sendPrivate(), 200);
  }

  id() { return this.nextId++; }

  toast(text, kind = 'info') {
    this.events.push({ t: 'msg', text, kind });
  }

  // ───────────────────────── Jugadores ─────────────────────────

  addPlayer(socket, user) {
    for (const other of this.players.values()) {
      if (other.userId === user.id) {
        other.socket.emit('kicked', 'Abriste el juego en otra pestaña.');
        other.socket.disconnect(true);
      }
    }
    const prog = this.store.getPlayer(user);
    const form = FORMS.guardian;
    const p = {
      id: socket.id,
      socket,
      userId: user.id,
      name: String(user.name).slice(0, 24),
      avatar: user.avatar,
      x: SPAWN.x + rnd(-60, 60),
      y: SPAWN.y + rnd(-60, 60),
      form: 'guardian',
      hp: form.hp,
      aim: 0,
      input: { up: false, down: false, left: false, right: false, fire: false, special: false },
      cdP: 0, cdS: 0, cdF: 0,
      inv: 2,
      dead: false, respawn: 0,
      dashT: 0, dashVx: 0, dashVy: 0, dashDmg: 0, dashHit: null,
      lastHit: -99,
      lvl: levelFromXp(prog.xp),
      chatAt: 0,
    };
    this.players.set(socket.id, p);

    socket.on('input', (msg) => {
      if (!msg || typeof msg !== 'object') return;
      const i = p.input;
      i.up = !!msg.up; i.down = !!msg.down; i.left = !!msg.left; i.right = !!msg.right;
      i.fire = !!msg.fire; i.special = !!msg.special;
      if (Number.isFinite(msg.aim)) p.aim = msg.aim;
    });

    socket.on('form', (key) => this.switchForm(p, key));

    socket.on('chat', (text) => {
      if (typeof text !== 'string') return;
      const clean = text.replace(/\s+/g, ' ').trim().slice(0, 140);
      if (!clean || this.time - p.chatAt < 0.7) return;
      p.chatAt = this.time;
      this.io.emit('chat', { n: p.name, c: FORMS[p.form].color, text: clean });
    });

    socket.on('disconnect', () => {
      this.players.delete(socket.id);
      this.toast(`${p.name} salió de Ciudad Blanca`, 'dim');
    });

    socket.emit('welcome', { id: socket.id, seenPrologue: prog.seenPrologue });
    this.toast(`${p.name} llegó a Ciudad Blanca`, 'dim');
  }

  switchForm(p, key) {
    if (p.dead || !FORMS[key] || key === p.form || p.cdF > 0) return;
    const prog = this.store.get(p.userId);
    if (!prog || !prog.unlocked.includes(key)) return;
    const ratio = p.hp / this.maxHp(p);
    p.form = key;
    p.hp = Math.max(1, ratio * this.maxHp(p));
    p.cdF = 1;
    p.cdP = 0.2;
    p.dashT = 0;
    this.events.push({ t: 'shift', x: round(p.x), y: round(p.y), c: FORMS[key].color });
    resolveCollisions(p, FORMS[key].r, !!FORMS[key].swim);
  }

  maxHp(p) {
    return FORMS[p.form].hp * (1 + 0.03 * (p.lvl - 1));
  }

  dmgMult(p) {
    return 1 + 0.05 * (p.lvl - 1);
  }

  hurtPlayer(p, dmg) {
    if (p.dead || p.inv > 0) return;
    p.hp -= dmg;
    p.lastHit = this.time;
    this.events.push({ t: 'hit', x: round(p.x), y: round(p.y), c: '#ff3b5c' });
    if (p.hp <= 0) {
      p.hp = 0;
      p.dead = true;
      p.respawn = 4;
      p.dashT = 0;
      this.store.update(p.userId, (r) => { r.deaths++; });
      this.events.push({ t: 'boom', x: round(p.x), y: round(p.y), r: 40, c: FORMS[p.form].color });
      p.socket.emit('notice', { text: 'Caíste… reapareces en la Plaza Grande.', kind: 'bad' });
    }
  }

  awardXp(p, amount) {
    const rec = this.store.update(p.userId, (r) => { r.xp += amount; });
    if (!rec) return;
    const lvl = levelFromXp(rec.xp);
    if (lvl > p.lvl) {
      p.lvl = lvl;
      p.hp = this.maxHp(p);
      this.events.push({ t: 'shift', x: round(p.x), y: round(p.y), c: '#ffd23f' });
      p.socket.emit('notice', { text: `¡Subiste a nivel ${lvl}!`, kind: 'good' });
    }
  }

  updatePlayer(p, dt) {
    if (p.dead) {
      p.respawn -= dt;
      if (p.respawn <= 0) {
        p.dead = false;
        p.x = SPAWN.x + rnd(-60, 60);
        p.y = SPAWN.y + rnd(-60, 60);
        p.hp = this.maxHp(p);
        p.inv = 2;
      }
      return;
    }
    const f = FORMS[p.form];
    p.cdP -= dt; p.cdS -= dt; p.cdF -= dt;
    if (p.inv > 0) p.inv -= dt;

    if (p.dashT > 0) {
      p.dashT -= dt;
      p.x += p.dashVx * dt;
      p.y += p.dashVy * dt;
      resolveCollisions(p, f.r, !!f.swim);
      if (p.dashDmg > 0) {
        for (const e of this.enemies) {
          if (!p.dashHit.has(e.id) && dist(p, e) < f.r + e.r + 10) {
            p.dashHit.add(e.id);
            this.damageEnemy(e, p.dashDmg * this.dmgMult(p), p);
          }
        }
        for (const c of this.cubes) {
          if (c.on && !p.dashHit.has(c.id) && dist(p, c) < f.r + CUBE_R + 10) {
            p.dashHit.add(c.id);
            this.damageCube(c, p.dashDmg * this.dmgMult(p), p);
          }
        }
      }
    } else {
      const i = p.input;
      moveEntity(p, (i.right ? 1 : 0) - (i.left ? 1 : 0), (i.down ? 1 : 0) - (i.up ? 1 : 0), f.speed, dt, f.r, !!f.swim);
    }

    if (this.time - p.lastHit > 4) {
      p.hp = Math.min(this.maxHp(p), p.hp + 5 * dt);
    }

    if (p.input.fire && p.cdP <= 0) this.primary(p, f);
    if (p.input.special && p.cdS <= 0) this.special(p, f);
  }

  primary(p, f) {
    const a = f.primary;
    p.cdP = a.cd;
    const dx = Math.cos(p.aim), dy = Math.sin(p.aim);
    if (a.type === 'shot') {
      this.projectiles.push({
        id: this.id(), team: 'p', owner: p.id, kind: a.kind,
        x: p.x + dx * (f.r + 6), y: p.y + dy * (f.r + 6),
        vx: dx * a.speed, vy: dy * a.speed, ttl: a.ttl,
        dmg: a.dmg * this.dmgMult(p), r: a.r, knock: a.knock || 0,
      });
    } else if (a.type === 'melee') {
      this.events.push({ t: 'slash', x: round(p.x), y: round(p.y), a: +p.aim.toFixed(2), r: a.range + f.r, c: f.color });
      const dmg = a.dmg * this.dmgMult(p);
      const reach = a.range + f.r;
      for (const e of this.enemies) {
        const d = dist(p, e);
        if (d < reach + e.r && (d < e.r + f.r || angDiff(Math.atan2(e.y - p.y, e.x - p.x), p.aim) < a.arc / 2 + 0.25)) {
          this.damageEnemy(e, dmg, p, 90);
        }
      }
      for (const c of this.cubes) {
        if (!c.on) continue;
        const d = dist(p, c);
        if (d < reach + CUBE_R && angDiff(Math.atan2(c.y - p.y, c.x - p.x), p.aim) < a.arc / 2 + 0.35) {
          this.damageCube(c, dmg, p);
        }
      }
    }
  }

  special(p, f) {
    const s = f.special;
    p.cdS = s.cd;
    if (s.type === 'dash') {
      const i = p.input;
      let dx = (i.right ? 1 : 0) - (i.left ? 1 : 0);
      let dy = (i.down ? 1 : 0) - (i.up ? 1 : 0);
      if (!dx && !dy) { dx = Math.cos(p.aim); dy = Math.sin(p.aim); }
      const len = Math.hypot(dx, dy);
      const dur = 0.18;
      p.dashT = dur;
      p.dashVx = (dx / len) * (s.dist / dur);
      p.dashVy = (dy / len) * (s.dist / dur);
      p.dashDmg = s.dmg;
      p.dashHit = new Set();
      p.inv = Math.max(p.inv, 0.25);
      this.events.push({ t: 'dash', x: round(p.x), y: round(p.y), c: f.color });
    } else if (s.type === 'shield') {
      p.inv = Math.max(p.inv, s.dur);
      for (const o of this.players.values()) {
        if (!o.dead && dist(o, p) < s.radius) {
          o.hp = Math.min(this.maxHp(o), o.hp + s.heal);
        }
      }
      this.events.push({ t: 'shield', x: round(p.x), y: round(p.y), r: s.radius, c: f.color });
    } else if (s.type === 'chain') {
      const pts = [[round(p.x), round(p.y)]];
      const hit = new Set();
      let from = p;
      let range = s.range;
      for (let n = 0; n < s.max; n++) {
        let best = null, bd = range;
        for (const e of this.enemies) {
          if (hit.has(e.id)) continue;
          const d = dist(from, e);
          if (d < bd) { bd = d; best = e; }
        }
        if (!best) break;
        hit.add(best.id);
        pts.push([round(best.x), round(best.y)]);
        this.damageEnemy(best, s.dmg * this.dmgMult(p), p);
        from = best;
        range = s.hop;
      }
      if (pts.length === 1) {
        // Sin enemigos: el rayo cae donde apuntas
        pts.push([round(p.x + Math.cos(p.aim) * 160), round(p.y + Math.sin(p.aim) * 160)]);
      }
      this.events.push({ t: 'chain', pts, c: f.color });
    } else if (s.type === 'quake') {
      const dmg = s.dmg * this.dmgMult(p);
      for (const e of this.enemies) {
        if (dist(p, e) < s.radius + e.r) {
          this.damageEnemy(e, dmg, p, 120);
          e.stun = Math.max(e.stun, e.boss ? s.stun * 0.3 : s.stun);
        }
      }
      for (const c of this.cubes) {
        if (c.on && dist(p, c) < s.radius + CUBE_R) this.damageCube(c, dmg, p);
      }
      this.events.push({ t: 'quake', x: round(p.x), y: round(p.y), r: s.radius, c: f.color });
    }
  }

  // ───────────────────────── Enemigos ─────────────────────────

  spawnEnemy(kind, x, y, district) {
    const def = ENEMIES[kind];
    const e = {
      id: this.id(), kind, x, y, district,
      hp: def.hp, mhp: def.hp, r: def.r,
      atkCd: rnd(0.5, 1.5), stun: 0, idle: 0,
      wanderA: rnd(0, Math.PI * 2), wanderT: 0,
      boss: kind === 'okom',
    };
    this.enemies.push(e);
    return e;
  }

  damageEnemy(e, dmg, p, knock = 0) {
    if (e.hp <= 0) return;
    e.hp -= dmg;
    e.idle = 0;
    this.events.push({ t: 'hit', x: round(e.x), y: round(e.y), c: '#ffffff' });
    if (knock && !e.boss && p) {
      const a = Math.atan2(e.y - p.y, e.x - p.x);
      e.x += Math.cos(a) * knock * (e.kind === 'bruto' ? 0.25 : 0.5);
      e.y += Math.sin(a) * knock * (e.kind === 'bruto' ? 0.25 : 0.5);
      resolveCollisions(e, e.r, false);
    }
    if (e.hp <= 0) this.killEnemy(e, p);
  }

  killEnemy(e, p) {
    const def = ENEMIES[e.kind];
    this.events.push({ t: 'boom', x: round(e.x), y: round(e.y), r: e.r * 1.8, c: e.boss ? '#b04cff' : '#7b5cff' });
    if (e.boss) {
      this.boss = null;
      this.bossRespawnAt = this.time + BOSS_RESPAWN;
      for (const o of this.players.values()) {
        if (dist(o, e) < 1500) {
          this.awardXp(o, def.xp);
          this.store.update(o.userId, (r) => { r.bossKills++; });
        }
      }
      this.toast(`¡Ok'om cayó! La Torre Obsidiana queda en silencio… por ahora.`, 'good');
      this.io.emit('story', 'boss_defeated');
      return;
    }
    if (p) {
      this.awardXp(p, def.xp);
      this.store.update(p.userId, (r) => { r.kills++; });
    }
  }

  nearestPlayer(e, maxD) {
    let best = null, bd = maxD;
    for (const p of this.players.values()) {
      if (p.dead) continue;
      const d = dist(p, e);
      if (d < bd) { bd = d; best = p; }
    }
    return best;
  }

  enemyShoot(e, angle, speed, dmg, kind = 'obs') {
    this.projectiles.push({
      id: this.id(), team: 'e', kind,
      x: e.x + Math.cos(angle) * (e.r + 4), y: e.y + Math.sin(angle) * (e.r + 4),
      vx: Math.cos(angle) * speed, vy: Math.sin(angle) * speed,
      ttl: 2.2, dmg, r: 7,
    });
  }

  updateEnemy(e, dt) {
    const def = ENEMIES[e.kind];
    e.atkCd -= dt;
    if (e.stun > 0) { e.stun -= dt; return; }

    const target = this.nearestPlayer(e, e.boss ? 1100 : 650);
    let mx = 0, my = 0;

    if (e.boss) {
      this.updateBoss(e, target, dt);
      return;
    }

    if (target) {
      e.idle = 0;
      const d = dist(e, target);
      const ax = (target.x - e.x) / (d || 1), ay = (target.y - e.y) / (d || 1);
      if (e.kind === 'centinela') {
        if (d > 320) { mx = ax; my = ay; } else if (d < 220) { mx = -ax; my = -ay; }
        else { mx = -ay * 0.6; my = ax * 0.6; } // rodea
        if (e.atkCd <= 0 && d < def.range) {
          e.atkCd = def.fireCd;
          this.enemyShoot(e, Math.atan2(ay, ax), 340, def.dmg);
        }
      } else {
        mx = ax; my = ay;
      }
    } else {
      e.idle += dt;
      e.wanderT -= dt;
      if (e.wanderT <= 0) { e.wanderA = rnd(0, Math.PI * 2); e.wanderT = rnd(1.5, 3); }
      mx = Math.cos(e.wanderA) * 0.4; my = Math.sin(e.wanderA) * 0.4;
    }

    const speed = def.speed * Math.hypot(mx, my);
    if (speed > 0) moveEntity(e, mx, my, speed, dt, e.r, false);

    // La Plaza Grande es zona segura: el jade de la fuente repele a Obsidiana
    const sd = dist(e, SPAWN);
    if (sd < SAFE_RADIUS + e.r) {
      const k = (SAFE_RADIUS + e.r) / (sd || 1);
      e.x = SPAWN.x + (e.x - SPAWN.x) * k;
      e.y = SPAWN.y + (e.y - SPAWN.y) * k;
    }

    // Mantener a los enemigos en su distrito
    const D = DISTRICTS.find((d) => d.id === e.district);
    if (D) {
      e.x = Math.max(D.x + e.r, Math.min(D.x + D.w - e.r, e.x));
      e.y = Math.max(D.y + e.r, Math.min(D.y + D.h - e.r, e.y));
    }

    // Daño por contacto
    if (e.kind !== 'centinela' && e.atkCd <= 0) {
      for (const p of this.players.values()) {
        if (!p.dead && dist(p, e) < e.r + FORMS[p.form].r + 4) {
          this.hurtPlayer(p, def.dmg);
          e.atkCd = e.kind === 'bruto' ? 1.2 : 0.8;
          break;
        }
      }
    }
  }

  updateBoss(e, target, dt) {
    const def = ENEMIES.okom;
    const phase2 = e.hp < e.mhp * 0.5;
    e.t1 -= dt; e.t2 -= dt; e.t3 -= dt;

    if (target) {
      const d = dist(e, target);
      if (d > 180) moveEntity(e, target.x - e.x, target.y - e.y, def.speed * (phase2 ? 1.4 : 1), dt, e.r, false);
    }
    const D = DISTRICTS.find((d) => d.id === 'torre');
    e.x = Math.max(D.x + e.r, Math.min(D.x + D.w - e.r, e.x));
    e.y = Math.max(D.y + e.r, Math.min(D.y + D.h - e.r, e.y));

    if (!target) return;

    if (e.t1 <= 0) {
      e.t1 = phase2 ? 1.6 : 2.6;
      const n = phase2 ? 20 : 14;
      e.spin = (e.spin || 0) + 0.27;
      for (let i = 0; i < n; i++) this.enemyShoot(e, e.spin + (i / n) * Math.PI * 2, 250, 14, 'obsBig');
      this.events.push({ t: 'quake', x: round(e.x), y: round(e.y), r: 120, c: '#b04cff' });
    }
    if (e.t2 <= 0) {
      e.t2 = phase2 ? 7 : 9;
      const count = this.enemies.filter((x) => x.district === 'torre').length;
      if (count < 22) {
        for (let i = 0; i < 3; i++) {
          const a = rnd(0, Math.PI * 2);
          const x = e.x + Math.cos(a) * 130, y = e.y + Math.sin(a) * 130;
          if (isFree(x, y, 16)) this.spawnEnemy('dron', x, y, 'torre');
        }
      }
    }
    if (phase2 && e.t3 <= 0) {
      e.t3 = 1.1;
      const base = Math.atan2(target.y - e.y, target.x - e.x);
      for (let i = -2; i <= 2; i++) this.enemyShoot(e, base + i * 0.14, 380, 12);
    }
    if (e.atkCd <= 0) {
      for (const p of this.players.values()) {
        if (!p.dead && dist(p, e) < e.r + FORMS[p.form].r + 4) {
          this.hurtPlayer(p, def.dmg);
          e.atkCd = 1;
          break;
        }
      }
    }
  }

  spawnBoss(n) {
    const e = this.spawnEnemy('okom', BOSS_SPAWN.x, BOSS_SPAWN.y, 'torre');
    e.mhp = e.hp = ENEMIES.okom.hp + 1600 * (n - 1);
    e.t1 = 2; e.t2 = 5; e.t3 = 3;
    this.boss = e;
    this.toast("¡Ok'om, el Titán de Obsidiana, despertó en la Torre!", 'bad');
  }

  spawner() {
    const counts = new Map();
    for (const p of this.players.values()) {
      if (p.dead) continue;
      const d = districtAt(p.x, p.y);
      counts.set(d.id, (counts.get(d.id) || 0) + 1);
    }
    for (const D of DISTRICTS) {
      const n = counts.get(D.id) || 0;
      if (!n) continue;
      if (D.boss && !this.boss && this.time >= this.bossRespawnAt) this.spawnBoss(n);
      const current = this.enemies.filter((e) => e.district === D.id && !e.boss).length;
      const cap = Math.min(D.cap * 3, D.cap + 2 * (n - 1));
      if (current >= cap) continue;
      const kind = D.kinds[Math.floor(Math.random() * D.kinds.length)];
      const r = ENEMIES[kind].r;
      for (let tries = 0; tries < 12; tries++) {
        const x = rnd(D.x + 60, D.x + D.w - 60);
        const y = rnd(D.y + 60, D.y + D.h - 60);
        if (!isFree(x, y, r) || dist({ x, y }, SPAWN) < SAFE_RADIUS + 120) continue;
        let near = false;
        for (const p of this.players.values()) if (dist(p, { x, y }) < 380) { near = true; break; }
        if (near) continue;
        this.spawnEnemy(kind, x, y, D.id);
        break;
      }
    }
  }

  // ───────────────────────── Cubos de contención ─────────────────────────

  damageCube(c, dmg, p) {
    if (!c.on) return;
    c.hp -= dmg;
    if (p) c.contrib.add(p.userId);
    this.events.push({ t: 'hit', x: round(c.x), y: round(c.y), c: '#ff3bd4' });
    if (c.hp <= 0) this.freeCube(c);
  }

  freeCube(c) {
    c.on = false;
    c.respawnAt = this.time + CUBE_RESPAWN;
    this.events.push({ t: 'free', x: c.x, y: c.y, alux: c.alux, c: c.alux ? FORMS[c.alux].color : '#ffffff' });
    const names = [];
    for (const p of this.players.values()) {
      if (!c.contrib.has(p.userId) && dist(p, c) > 700) continue;
      names.push(p.name);
      this.awardXp(p, c.alux ? 80 : 150);
      this.store.update(p.userId, (r) => { r.freed++; });
      if (c.alux && this.store.unlock(p.userId, c.alux)) {
        const f = FORMS[c.alux];
        const key = FORM_ORDER.indexOf(c.alux) + 1;
        p.socket.emit('notice', { text: `¡Liberaste a ${f.name}, ${f.title}! Pulsa ${key} para transformarte.`, kind: 'good', big: true });
        p.socket.emit('story', `freed_${c.alux}`);
      }
    }
    c.contrib = new Set();
    const who = names.slice(0, 3).join(', ') + (names.length > 3 ? ' y más' : '');
    if (c.alux) this.toast(`${who || 'Alguien'} liberó a ${FORMS[c.alux].name} de su cubo de contención`, 'good');
    else this.toast(`${who || 'Alguien'} liberó a un alux errante en el Malecón`, 'good');
  }

  // ───────────────────────── Proyectiles ─────────────────────────

  updateProjectiles(dt) {
    for (const b of this.projectiles) {
      b.x += b.vx * dt;
      b.y += b.vy * dt;
      b.ttl -= dt;
      if (b.ttl <= 0) { b.dead = true; continue; }
      if (pointInBuilding(b.x, b.y)) {
        b.dead = true;
        this.events.push({ t: 'spark', x: round(b.x), y: round(b.y), k: b.kind });
        continue;
      }
      if (b.team === 'p') {
        const owner = this.players.get(b.owner);
        for (const e of this.enemies) {
          if (e.hp > 0 && dist(b, e) < e.r + b.r) {
            this.damageEnemy(e, b.dmg, owner, b.knock);
            b.dead = true;
            break;
          }
        }
        if (b.dead) continue;
        for (const c of this.cubes) {
          if (c.on && dist(b, c) < CUBE_R + b.r) {
            this.damageCube(c, b.dmg, owner);
            b.dead = true;
            break;
          }
        }
      } else {
        for (const p of this.players.values()) {
          if (!p.dead && dist(b, p) < FORMS[p.form].r + b.r) {
            this.hurtPlayer(p, b.dmg);
            b.dead = true;
            break;
          }
        }
      }
    }
    this.projectiles = this.projectiles.filter((b) => !b.dead);
  }

  // ───────────────────────── Bucle principal ─────────────────────────

  update(dt) {
    this.time += dt;
    for (const p of this.players.values()) this.updatePlayer(p, dt);
    for (const e of this.enemies) if (e.hp > 0) this.updateEnemy(e, dt);
    this.updateProjectiles(dt);

    // Separación ligera entre enemigos para que no se encimen
    const es = this.enemies;
    for (let i = 0; i < es.length; i++) {
      for (let j = i + 1; j < es.length; j++) {
        const a = es[i], b = es[j];
        const dx = b.x - a.x, dy = b.y - a.y;
        const min = a.r + b.r;
        const d2 = dx * dx + dy * dy;
        if (d2 > 0 && d2 < min * min) {
          const d = Math.sqrt(d2), push = (min - d) / 2;
          const wa = a.boss ? 0 : 1, wb = b.boss ? 0 : 1;
          a.x -= (dx / d) * push * wa; a.y -= (dy / d) * push * wa;
          b.x += (dx / d) * push * wb; b.y += (dy / d) * push * wb;
        }
      }
    }

    // Quitar enemigos muertos o abandonados
    this.enemies = this.enemies.filter((e) => e.hp > 0 && (e.boss || e.idle < 40));
    if (this.boss && this.boss.hp > 0) {
      const anyone = [...this.players.values()].some((p) => districtAt(p.x, p.y).id === 'torre');
      this.boss.idle = anyone ? 0 : this.boss.idle + dt;
      if (this.boss.idle > 60) {
        this.enemies = this.enemies.filter((e) => e !== this.boss);
        this.boss = null;
      }
    }

    for (const c of this.cubes) {
      if (!c.on && this.time >= c.respawnAt) {
        c.on = true;
        c.hp = CUBE_HP;
      }
    }

    this.spawnTimer -= dt;
    if (this.spawnTimer <= 0) {
      this.spawnTimer = 1;
      this.spawner();
    }
  }

  broadcast() {
    const snap = {
      t: Math.round(this.time * 1000),
      p: [...this.players.values()].map((p) => ({
        id: p.id, n: p.name, a: p.avatar, x: round(p.x), y: round(p.y), f: p.form,
        ang: +p.aim.toFixed(2), hp: round(p.hp), mhp: round(this.maxHp(p)),
        d: p.dead ? 1 : 0, inv: p.inv > 0 ? 1 : 0, dash: p.dashT > 0 ? 1 : 0, l: p.lvl,
      })),
      e: this.enemies.map((e) => ({ id: e.id, k: e.kind, x: round(e.x), y: round(e.y), hp: round(e.hp), mhp: e.mhp, st: e.stun > 0 ? 1 : 0 })),
      b: this.projectiles.map((b) => ({ id: b.id, k: b.kind, x: round(b.x), y: round(b.y), tm: b.team })),
      c: this.cubes.map((c) => ({ id: c.id, x: c.x, y: c.y, hp: round(c.hp), on: c.on ? 1 : 0, al: c.alux })),
      ev: this.events,
    };
    this.events = [];
    this.io.emit('snap', snap);
  }

  sendPrivate() {
    for (const p of this.players.values()) {
      const rec = this.store.get(p.userId);
      if (!rec) continue;
      p.socket.emit('me', {
        cdP: Math.max(0, p.cdP), cdS: Math.max(0, p.cdS), cdF: Math.max(0, p.cdF),
        unlocked: rec.unlocked, xp: rec.xp, lvl: p.lvl,
        lvlXp: xpForLevel(p.lvl), nextXp: xpForLevel(p.lvl + 1),
        kills: rec.kills, freed: rec.freed, bossKills: rec.bossKills,
        respawn: p.dead ? Math.max(0, p.respawn) : 0,
        online: this.players.size,
      });
    }
  }
}
