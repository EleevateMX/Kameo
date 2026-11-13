import { randomUUID } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { DEFAULT_LOOK, DEFAULT_UNLOCKS, EMPTY_RPG, cleanLook, cleanName, type Character, type FormId, type PlayerProfile, type RpgState } from '@alux/shared-contracts';
import type { MemberRow, RoomRow, RpgApplied, RpgChange, Store, SessionMetrics } from './types.ts';

interface PlayerRec {
  id: string;
  provider: 'discord' | 'dev' | 'beta';
  providerId: string;
  displayName: string;
  avatarUrl: string | null;
  character: Character;
  unlocks: FormId[];
  quests: Record<string, string>;
}
interface RoomRec extends Omit<RoomRow, 'createdAt' | 'lastSeenAt'> {
  createdAt: string;
  lastSeenAt: string;
  members: { id: string; joinedAt: string }[];
}
interface Data {
  players: Record<string, PlayerRec>;
  rooms: Record<string, RoomRec>;
  ledger: { playerId: string; reward: string; source: string; idempotencyKey: string; grantedAt: string }[];
  rpg?: Record<string, RpgState>;
  rpgLedger?: { playerId: string; kind: string; key: string; at: string; result?: Record<string, unknown>; itemId?: string }[];
}

/** Almacén en memoria con guardado opcional a un archivo JSON (sólo desarrollo). */
export class MemoryStore implements Store {
  private data: Data = { players: {}, rooms: {}, ledger: [] };
  private timer: NodeJS.Timeout | null = null;

  constructor(private file: string | null = null) {
    if (file && fs.existsSync(file)) {
      try {
        this.data = { ...this.data, ...JSON.parse(fs.readFileSync(file, 'utf8')) };
      } catch {
        console.warn(`[store] No se pudo leer ${file}; se empieza de cero.`);
      }
    }
  }

  private save() {
    if (!this.file || this.timer) return;
    this.timer = setTimeout(() => {
      this.timer = null;
      this.flush();
    }, 500);
  }

  private flush() {
    if (!this.file) return;
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    const tmp = `${this.file}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(this.data));
    fs.renameSync(tmp, this.file);
  }

  async upsertPlayer(p: { provider: 'discord' | 'dev' | 'beta'; providerId: string; displayName: string; avatarUrl: string | null }) {
    let rec = Object.values(this.data.players).find((x) => x.provider === p.provider && x.providerId === p.providerId);
    if (!rec) {
      rec = {
        id: randomUUID(), provider: p.provider, providerId: p.providerId,
        displayName: p.displayName, avatarUrl: p.avatarUrl,
        character: { name: cleanName(p.displayName), color: '#2ec4a6', hat: 0, look: { ...DEFAULT_LOOK } },
        unlocks: [...DEFAULT_UNLOCKS], quests: {},
      };
      this.data.players[rec.id] = rec;
    } else {
      rec.displayName = p.displayName;
      rec.avatarUrl = p.avatarUrl;
    }
    this.save();
    return rec.id;
  }

  async getProfile(id: string): Promise<PlayerProfile | null> {
    const r = this.data.players[id];
    if (!r) return null;
    return {
      id: r.id, displayName: r.displayName, avatarUrl: r.avatarUrl, provider: r.provider,
      character: { ...r.character, look: cleanLook(r.character.look) }, unlocks: [...r.unlocks],
      rewards: this.data.ledger.filter((l) => l.playerId === id).map((l) => l.reward),
      quests: { ...r.quests },
    };
  }

  async updateCharacter(id: string, c: Character) {
    const r = this.data.players[id];
    if (r) r.character = { ...c, look: cleanLook(c.look) };
    this.save();
  }

  async createRoom(r: { code: string; visibility: 'private' | 'public'; ownerId: string; serverId: string }) {
    if (this.data.rooms[r.code]) return false;
    const now = new Date().toISOString();
    this.data.rooms[r.code] = { ...r, status: 'open', gateOpen: false, createdAt: now, lastSeenAt: now, members: [] };
    this.save();
    return true;
  }

  private row(r: RoomRec): RoomRow {
    return {
      code: r.code, visibility: r.visibility, ownerId: r.ownerId, serverId: r.serverId, status: r.status,
      gateOpen: r.gateOpen, createdAt: new Date(r.createdAt), lastSeenAt: new Date(r.lastSeenAt),
    };
  }

  async getRoom(code: string) {
    const r = this.data.rooms[code];
    return r ? this.row(r) : null;
  }

  async listOpenRooms() {
    return Object.values(this.data.rooms).filter((r) => r.status === 'open').map((r) => this.row(r));
  }

  async listOpenPublicRooms() {
    return (await this.listOpenRooms()).filter((r) => r.visibility === 'public');
  }

  async updateRoom(code: string, patch: { gateOpen?: boolean; status?: 'open' | 'closed'; touch?: boolean }) {
    const r = this.data.rooms[code];
    if (!r) return;
    if (patch.gateOpen !== undefined) r.gateOpen = patch.gateOpen;
    if (patch.status) r.status = patch.status;
    if (patch.touch) r.lastSeenAt = new Date().toISOString();
    this.save();
  }

  async addMember(code: string, playerId: string) {
    const r = this.data.rooms[code];
    if (!r || r.members.some((m) => m.id === playerId)) return;
    r.members.push({ id: playerId, joinedAt: new Date().toISOString() });
    this.save();
  }

  async removeMember(code: string, playerId: string) {
    const r = this.data.rooms[code];
    if (!r) return;
    r.members = r.members.filter((m) => m.id !== playerId);
    this.save();
  }

  async listMembers(code: string): Promise<MemberRow[]> {
    const r = this.data.rooms[code];
    if (!r) return [];
    return r.members.flatMap((m) => {
      const p = this.data.players[m.id];
      return p ? [{ id: m.id, name: p.character.name, color: p.character.color, joinedAt: new Date(m.joinedAt) }] : [];
    });
  }

  async recordSession() {
    // En memoria no hace falta auditar los tickets emitidos.
  }

  async grantReward(g: { playerId: string; reward: string; source: string; idempotencyKey: string; effect: { quest?: string; unlock?: FormId } }) {
    const p = this.data.players[g.playerId];
    if (!p) return false;
    if (this.data.ledger.some((l) => l.idempotencyKey === g.idempotencyKey)) return false;
    this.data.ledger.push({
      playerId: g.playerId, reward: g.reward, source: g.source,
      idempotencyKey: g.idempotencyKey, grantedAt: new Date().toISOString(),
    });
    if (g.effect.quest) p.quests[g.effect.quest] = 'completed';
    if (g.effect.unlock && !p.unlocks.includes(g.effect.unlock)) p.unlocks.push(g.effect.unlock);
    this.save();
    return true;
  }

  async getRpg(playerId: string): Promise<RpgState> {
    const s = this.data.rpg?.[playerId];
    return s ? { ...s, skills: { ...s.skills }, items: s.items.map((i) => ({ ...i })) } : { ...EMPTY_RPG, skills: {}, items: [] };
  }

  async rpgApply(a: { playerId: string; kind: string; key: string; decide: (state: RpgState, today: number) => RpgChange | { reject: string } }): Promise<RpgApplied> {
    this.data.rpg ??= {};
    this.data.rpgLedger ??= [];
    const state = await this.getRpg(a.playerId);
    if (!this.data.players[a.playerId]) return { applied: false, reason: 'no_player', state };
    const prev = this.data.rpgLedger.find((l) => l.playerId === a.playerId && l.key === a.key);
    if (prev) return { applied: false, reason: 'duplicate', state, result: prev.result, itemId: prev.itemId };
    const day = new Date().toISOString().slice(0, 10);
    const today = this.data.rpgLedger.filter((l) => l.playerId === a.playerId && l.kind === a.kind && l.at.slice(0, 10) === day).length;
    const change = a.decide(state, today);
    if ('reject' in change) return { applied: false, reason: change.reject, state };
    state.xp += change.xp ?? 0;
    state.seeds += change.seeds ?? 0;
    if (state.seeds < 0) return { applied: false, reason: 'not_enough_seeds', state: await this.getRpg(a.playerId) };
    if (change.skill) state.skills[change.skill.id] = change.skill.rank;
    if (change.pity !== undefined) state.pity = change.pity;
    let itemId: string | undefined;
    if (change.addItem) {
      itemId = randomUUID();
      state.items.push({ id: itemId, ...change.addItem });
    }
    if (change.equipped !== undefined) state.equipped = change.equipped;
    this.data.rpg[a.playerId] = state;
    this.data.rpgLedger.push({ playerId: a.playerId, kind: a.kind, key: a.key, at: new Date().toISOString(), result: change.result, itemId });
    this.save();
    return { applied: true, state: await this.getRpg(a.playerId), result: change.result, itemId };
  }

  private metrics = new Map<string, SessionMetrics & { createdAt: Date; updatedAt: Date }>();

  async saveMetrics(m: SessionMetrics) {
    const prev = this.metrics.get(m.sessionId);
    if (prev && prev.playerId !== m.playerId) return;
    this.metrics.set(m.sessionId, { ...m, createdAt: prev?.createdAt ?? new Date(), updatedAt: new Date() });
    if (this.metrics.size > 500) this.metrics.delete(this.metrics.keys().next().value!);
  }

  async listMetrics(limit: number) {
    return [...this.metrics.values()].sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime()).slice(0, limit);
  }

  async ping() {
    return true;
  }

  async close() {
    if (this.timer) clearTimeout(this.timer);
    this.timer = null;
    this.flush();
  }
}
