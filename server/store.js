// Guardado simple del progreso de cada jugador en un archivo JSON.
// Suficiente para empezar; para producción con muchos jugadores conviene
// cambiarlo por una base de datos (Postgres, Supabase, SQLite...).
import fs from 'node:fs';
import path from 'node:path';
import { STARTING_FORMS, FORM_ORDER } from '../shared/config.js';

export class Store {
  constructor(file) {
    this.file = file;
    this.players = {};
    this.timer = null;
    try {
      this.players = JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch {
      this.players = {};
    }
  }

  getPlayer(user) {
    let p = this.players[user.id];
    if (!p) {
      p = this.players[user.id] = {
        id: user.id,
        name: user.name,
        avatar: user.avatar,
        guest: !!user.guest,
        xp: 0,
        kills: 0,
        deaths: 0,
        freed: 0,
        bossKills: 0,
        unlocked: [...STARTING_FORMS],
        createdAt: Date.now(),
        seenPrologue: false,
      };
    }
    p.name = user.name;
    p.avatar = user.avatar;
    this.save();
    return p;
  }

  get(id) {
    return this.players[id];
  }

  update(id, fn) {
    const p = this.players[id];
    if (!p) return null;
    fn(p);
    this.save();
    return p;
  }

  unlock(id, form) {
    let added = false;
    this.update(id, (p) => {
      if (!p.unlocked.includes(form)) {
        p.unlocked.push(form);
        p.unlocked.sort((a, b) => FORM_ORDER.indexOf(a) - FORM_ORDER.indexOf(b));
        added = true;
      }
    });
    return added;
  }

  leaderboard(limit = 10) {
    return Object.values(this.players)
      .filter((p) => !p.guest)
      .sort((a, b) => b.xp - a.xp)
      .slice(0, limit)
      .map(({ name, avatar, xp, kills, freed, bossKills }) => ({ name, avatar, xp, kills, freed, bossKills }));
  }

  save() {
    if (this.timer) return;
    this.timer = setTimeout(() => {
      this.timer = null;
      fs.mkdirSync(path.dirname(this.file), { recursive: true });
      const tmp = this.file + '.tmp';
      fs.writeFileSync(tmp, JSON.stringify(this.players));
      fs.renameSync(tmp, this.file);
    }, 2000);
  }
}
