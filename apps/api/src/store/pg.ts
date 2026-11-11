import pg from 'pg';
import { DEFAULT_UNLOCKS, cleanName, type Character, type FormId, type PlayerProfile } from '@alux/shared-contracts';
import type { MemberRow, RoomRow, Store } from './types.ts';

/** PostgreSQL / Supabase. El esquema está en supabase/migrations. */
export class PgStore implements Store {
  private pool: pg.Pool;

  constructor(databaseUrl: string) {
    const local = /@(localhost|127\.0\.0\.1)[:/]/.test(databaseUrl) || databaseUrl.includes('host=/');
    this.pool = new pg.Pool({
      connectionString: databaseUrl,
      max: 10,
      ssl: local || process.env.PGSSLMODE === 'disable' ? undefined : { rejectUnauthorized: false },
    });
  }

  async upsertPlayer(p: { provider: 'discord' | 'dev'; providerId: string; displayName: string; avatarUrl: string | null }) {
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
      `select p.id, p.display_name, p.avatar_url, p.provider, c.name, c.color, c.hat,
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
      character: { name: r.name ?? cleanName(r.display_name), color: r.color ?? '#2ec4a6', hat: r.hat ?? 0 },
      unlocks: r.unlocks, rewards: r.rewards, quests: r.quests,
    };
  }

  async updateCharacter(id: string, c: Character) {
    await this.pool.query(
      `insert into characters (player_id, name, color, hat) values ($1, $2, $3, $4)
       on conflict (player_id) do update set name = excluded.name, color = excluded.color, hat = excluded.hat, updated_at = now()`,
      [id, c.name, c.color, c.hat],
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

  async close() {
    await this.pool.end();
  }
}
