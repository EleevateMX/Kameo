import pg from 'pg';
import { DEFAULT_UNLOCKS, cleanLook, cleanName, type Character, type FormId, type PlayerProfile, type Rarity, type RpgState } from '@alux/shared-contracts';
import type { MemberRow, RoomRow, RpgApplied, RpgChange, SessionMetrics, Store } from './types.ts';

/** PostgreSQL / Supabase. El esquema está en supabase/migrations. */
export class PgStore implements Store {
  private pool: pg.Pool;

  constructor(databaseUrl: string, pool?: pg.Pool) {
    this.pool = pool ?? makePool(databaseUrl, wantsSsl(databaseUrl));
  }

  /** Conecta y comprueba la conexión. Si el servidor no admite TLS, reintenta sin él. */
  static async connect(databaseUrl: string): Promise<PgStore> {
    return new PgStore(databaseUrl, await connectPool(databaseUrl));
  }

  async upsertPlayer(p: { provider: 'discord' | 'dev' | 'beta'; providerId: string; displayName: string; avatarUrl: string | null }) {
    const client = await this.pool.connect();
    try {
      await client.query('begin');
      const { rows } = await client.query(
        `insert into players (provider, provider_id, display_name, avatar_url)
         values ($1, $2, $3, $4)
         on conflict (provider, provider_id)
         do update set display_name = excluded.display_name, avatar_url = excluded.avatar_url, last_login_at = now()
         returning id, (xmax = 0) as created`,
        [p.provider, p.providerId, p.displayName, p.avatarUrl],
      );
      const id: string = rows[0].id;
      if (rows[0].created) {
        await client.query('insert into characters (player_id, name) values ($1, $2) on conflict do nothing', [id, cleanName(p.displayName)]);
        for (const form of DEFAULT_UNLOCKS) {
          await client.query('insert into unlocks (player_id, form) values ($1, $2) on conflict do nothing', [id, form]);
        }
      }
      await client.query('commit');
      return id;
    } catch (err) {
      await client.query('rollback');
      throw err;
    } finally {
      client.release();
    }
  }

  async getProfile(id: string): Promise<PlayerProfile | null> {
    const { rows } = await this.pool.query(
      `select p.id, p.display_name, p.avatar_url, p.provider, c.name, c.color, c.hat, c.look,
              coalesce((select array_agg(form order by unlocked_at) from unlocks u where u.player_id = p.id), '{}') as unlocks,
              coalesce((select array_agg(reward order by granted_at) from rewards_ledger r where r.player_id = p.id), '{}') as rewards,
              coalesce((select jsonb_object_agg(quest, status) from quest_progress q where q.player_id = p.id), '{}'::jsonb) as quests
         from players p left join characters c on c.player_id = p.id
        where p.id = $1`,
      [id],
    );
    const r = rows[0];
    if (!r) return null;
    return {
      id: r.id, displayName: r.display_name, avatarUrl: r.avatar_url, provider: r.provider,
      character: { name: r.name ?? cleanName(r.display_name), color: r.color ?? '#2ec4a6', hat: r.hat ?? 0, look: cleanLook(r.look) },
      unlocks: r.unlocks, rewards: r.rewards, quests: r.quests,
    };
  }

  async updateCharacter(id: string, c: Character) {
    await this.pool.query(
      `insert into characters (player_id, name, color, hat, look) values ($1, $2, $3, $4, $5)
       on conflict (player_id) do update set name = excluded.name, color = excluded.color, hat = excluded.hat, look = excluded.look, updated_at = now()`,
      [id, c.name, c.color, c.hat, JSON.stringify(cleanLook(c.look))],
    );
  }

  async createRoom(r: { code: string; visibility: 'private' | 'public'; ownerId: string; serverId: string }) {
    const res = await this.pool.query(
      'insert into parties (code, visibility, owner_id, server_id) values ($1, $2, $3, $4) on conflict (code) do nothing',
      [r.code, r.visibility, r.ownerId, r.serverId],
    );
    return res.rowCount === 1;
  }

  private row(r: any): RoomRow {
    return {
      code: r.code, visibility: r.visibility, ownerId: r.owner_id, serverId: r.server_id, status: r.status,
      gateOpen: r.gate_open, createdAt: r.created_at, lastSeenAt: r.last_seen_at,
    };
  }

  async getRoom(code: string) {
    const { rows } = await this.pool.query('select * from parties where code = $1', [code]);
    return rows[0] ? this.row(rows[0]) : null;
  }

  async listOpenRooms() {
    const { rows } = await this.pool.query("select * from parties where status = 'open' order by created_at");
    return rows.map((r) => this.row(r));
  }

  async listOpenPublicRooms() {
    const { rows } = await this.pool.query("select * from parties where status = 'open' and visibility = 'public' order by created_at");
    return rows.map((r) => this.row(r));
  }

  async updateRoom(code: string, patch: { gateOpen?: boolean; status?: 'open' | 'closed'; touch?: boolean }) {
    await this.pool.query(
      `update parties set
         gate_open = coalesce($2, gate_open),
         status = coalesce($3, status),
         last_seen_at = case when $4 then now() else last_seen_at end
       where code = $1`,
      [code, patch.gateOpen ?? null, patch.status ?? null, !!patch.touch],
    );
  }

  async addMember(code: string, playerId: string) {
    await this.pool.query('insert into party_members (party_code, player_id) values ($1, $2) on conflict do nothing', [code, playerId]);
  }

  async removeMember(code: string, playerId: string) {
    await this.pool.query('delete from party_members where party_code = $1 and player_id = $2', [code, playerId]);
  }

  async listMembers(code: string): Promise<MemberRow[]> {
    const { rows } = await this.pool.query(
      `select m.player_id as id, coalesce(c.name, p.display_name) as name, coalesce(c.color, '#2ec4a6') as color, m.joined_at
         from party_members m join players p on p.id = m.player_id left join characters c on c.player_id = m.player_id
        where m.party_code = $1 order by m.joined_at`,
      [code],
    );
    return rows.map((r) => ({ id: r.id, name: r.name, color: r.color, joinedAt: r.joined_at }));
  }

  async recordSession(s: { jti: string; playerId: string; code: string; expiresAt: Date }) {
    await this.pool.query(
      'insert into sessions (jti, player_id, party_code, expires_at) values ($1, $2, $3, $4) on conflict do nothing',
      [s.jti, s.playerId, s.code, s.expiresAt],
    );
  }

  async grantReward(g: { playerId: string; reward: string; source: string; idempotencyKey: string; effect: { quest?: string; unlock?: FormId } }) {
    const client = await this.pool.connect();
    try {
      await client.query('begin');
      const ins = await client.query(
        `insert into rewards_ledger (player_id, reward, source, idempotency_key)
         values ($1, $2, $3, $4) on conflict (idempotency_key) do nothing`,
        [g.playerId, g.reward, g.source, g.idempotencyKey],
      );
      const fresh = ins.rowCount === 1;
      if (fresh) {
        if (g.effect.quest) {
          await client.query(
            `insert into quest_progress (player_id, quest, status) values ($1, $2, 'completed')
             on conflict (player_id, quest) do update set status = 'completed', updated_at = now()`,
            [g.playerId, g.effect.quest],
          );
        }
        if (g.effect.unlock) {
          await client.query(
            "insert into unlocks (player_id, form, source) values ($1, $2, $3) on conflict do nothing",
            [g.playerId, g.effect.unlock, g.reward],
          );
        }
      }
      await client.query('commit');
      return fresh;
    } catch (err) {
      await client.query('rollback');
      throw err;
    } finally {
      client.release();
    }
  }

  /** Lee el estado RPG con la conexión dada (para usarlo dentro de una transacción). */
  private async readRpg(q: { query: pg.Pool['query'] }, playerId: string, lock = false): Promise<RpgState> {
    const st = await q.query(`select xp, seeds, skills, equipped, pity from rpg_state where player_id = $1${lock ? ' for update' : ''}`, [playerId]);
    const items = await q.query('select id, item, rarity from rpg_items where player_id = $1 order by created_at, id', [playerId]);
    const r = st.rows[0];
    return {
      xp: r?.xp ?? 0, seeds: r?.seeds ?? 0, skills: r?.skills ?? {}, equipped: r?.equipped ?? null, pity: r?.pity ?? 0,
      items: items.rows.map((i: { id: string; item: string; rarity: Rarity }) => ({ id: i.id, item: i.item, rarity: i.rarity })),
    };
  }

  async getRpg(playerId: string): Promise<RpgState> {
    return this.readRpg(this.pool, playerId);
  }

  async rpgApply(a: { playerId: string; kind: string; key: string; decide: (state: RpgState, today: number) => RpgChange | { reject: string } }): Promise<RpgApplied> {
    const client = await this.pool.connect();
    try {
      await client.query('begin');
      // La fila del jugador se crea si falta y se bloquea: dos peticiones a la vez van en fila
      const made = await client.query(
        'insert into rpg_state (player_id) select id from players where id = $1 on conflict (player_id) do nothing', [a.playerId]);
      const state = await this.readRpg(client, a.playerId, true);
      const exists = made.rowCount === 1 || (await client.query('select 1 from rpg_state where player_id = $1', [a.playerId])).rowCount === 1;
      if (!exists) {
        await client.query('rollback');
        return { applied: false, reason: 'no_player', state };
      }
      const prev = await client.query('select result, item_id from rpg_ledger where player_id = $1 and key = $2', [a.playerId, a.key]);
      if (prev.rowCount) {
        await client.query('commit');
        return { applied: false, reason: 'duplicate', state, result: prev.rows[0].result ?? undefined, itemId: prev.rows[0].item_id ?? undefined };
      }
      const today = Number((await client.query(
        "select count(*)::int as n from rpg_ledger where player_id = $1 and kind = $2 and created_at >= date_trunc('day', now() at time zone 'utc') at time zone 'utc'",
        [a.playerId, a.kind])).rows[0].n);
      const change = a.decide(state, today);
      if ('reject' in change || state.seeds + (change.seeds ?? 0) < 0) {
        await client.query('rollback');
        return { applied: false, reason: 'reject' in change ? change.reject : 'not_enough_seeds', state };
      }
      let itemId: string | undefined;
      if (change.addItem) {
        const ins = await client.query(
          'insert into rpg_items (player_id, item, rarity, source) values ($1, $2, $3, $4) returning id',
          [a.playerId, change.addItem.item, change.addItem.rarity, a.kind]);
        itemId = ins.rows[0].id;
      }
      const skills = change.skill ? { ...state.skills, [change.skill.id]: change.skill.rank } : state.skills;
      await client.query(
        `update rpg_state set xp = xp + $2, seeds = seeds + $3, skills = $4, equipped = $5, pity = $6, updated_at = now() where player_id = $1`,
        [a.playerId, change.xp ?? 0, change.seeds ?? 0, JSON.stringify(skills),
          change.equipped !== undefined ? change.equipped : state.equipped, change.pity ?? state.pity]);
      await client.query(
        'insert into rpg_ledger (player_id, kind, key, xp, seeds, result, item_id) values ($1, $2, $3, $4, $5, $6, $7)',
        [a.playerId, a.kind, a.key, change.xp ?? 0, change.seeds ?? 0, change.result ? JSON.stringify(change.result) : null, itemId ?? null]);
      const after = await this.readRpg(client, a.playerId);
      await client.query('commit');
      return { applied: true, state: after, result: change.result, itemId };
    } catch (err) {
      await client.query('rollback').catch(() => {});
      // Dos peticiones con la misma clave a la vez: la segunda choca con la clave única
      if ((err as { code?: string }).code === '23505') {
        return { applied: false, reason: 'duplicate', state: await this.getRpg(a.playerId) };
      }
      throw err;
    } finally {
      client.release();
    }
  }

  async saveMetrics(m: SessionMetrics) {
    // Una fila por sesión; sólo su dueño puede actualizarla.
    await this.pool.query(
      `insert into session_metrics (session_id, player_id, room, quality, fps_avg, fps_min, ping_avg, ping_max, load_ms, seconds, data)
       values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
       on conflict (session_id) do update set
         room = excluded.room, quality = excluded.quality, fps_avg = excluded.fps_avg, fps_min = excluded.fps_min,
         ping_avg = excluded.ping_avg, ping_max = excluded.ping_max, load_ms = excluded.load_ms,
         seconds = excluded.seconds, data = excluded.data, updated_at = now()
       where session_metrics.player_id = excluded.player_id`,
      [m.sessionId, m.playerId, m.room, m.quality, m.fpsAvg, m.fpsMin, m.pingAvg, m.pingMax, m.loadMs, m.seconds, JSON.stringify(m.data)],
    );
  }

  async listMetrics(limit: number) {
    const { rows } = await this.pool.query(
      `select session_id, player_id, room, quality, fps_avg, fps_min, ping_avg, ping_max, load_ms, seconds, data, created_at, updated_at
         from session_metrics order by created_at desc limit $1`,
      [limit],
    );
    return rows.map((r) => ({
      sessionId: r.session_id, playerId: r.player_id, room: r.room, quality: r.quality,
      fpsAvg: r.fps_avg, fpsMin: r.fps_min, pingAvg: r.ping_avg, pingMax: r.ping_max, loadMs: r.load_ms,
      seconds: r.seconds, data: r.data, createdAt: r.created_at, updatedAt: r.updated_at,
    }));
  }

  async ping() {
    try {
      await this.pool.query('select 1');
      return true;
    } catch {
      return false;
    }
  }

  async close() {
    await this.pool.end();
  }
}

/** ¿Conviene TLS? No en local ni con PGSSLMODE=disable; sí en cualquier otro caso. */
export function wantsSsl(databaseUrl: string): boolean {
  if (process.env.PGSSLMODE === 'disable') return false;
  return !(/@(localhost|127\.0\.0\.1)[:/]/.test(databaseUrl) || databaseUrl.includes('host=/'));
}

export function makePool(databaseUrl: string, ssl: boolean, max = 10): pg.Pool {
  const pool = new pg.Pool({ connectionString: databaseUrl, max, ssl: ssl ? { rejectUnauthorized: false } : undefined });
  // Un corte de la base de datos no debe tumbar el proceso: el pool reconecta solo.
  pool.on('error', (err) => console.error('[db] Conexión perdida:', err.message));
  return pool;
}

/**
 * Abre el pool y verifica que responde. Algunas redes privadas (p. ej. la interna de Render)
 * no ofrecen TLS: si el servidor lo rechaza, se reintenta sin TLS dentro de esa red.
 */
export async function connectPool(databaseUrl: string, max = 10): Promise<pg.Pool> {
  let pool = makePool(databaseUrl, wantsSsl(databaseUrl), max);
  try {
    await pool.query('select 1');
  } catch (err) {
    if (!/does not support SSL/i.test(String((err as Error).message))) {
      await pool.end().catch(() => {});
      throw err;
    }
    await pool.end().catch(() => {});
    pool = makePool(databaseUrl, false, max);
    await pool.query('select 1');
  }
  return pool;
}
