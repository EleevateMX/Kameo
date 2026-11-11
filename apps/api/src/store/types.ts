import type { Character, FormId, PlayerProfile, RoomVisibility } from '@alux/shared-contracts';

export interface RoomRow {
  code: string;
  visibility: RoomVisibility;
  ownerId: string;
  serverId: string;
  status: 'open' | 'closed';
  gateOpen: boolean;
  createdAt: Date;
  lastSeenAt: Date;
}

export interface MemberRow {
  id: string;
  name: string;
  color: string;
  joinedAt: Date;
}

export interface RewardEffect {
  quest?: string;
  unlock?: FormId;
}

/**
 * Persistencia. Hay dos implementaciones:
 *  - MemoryStore: archivo JSON local, para desarrollar sin base de datos.
 *  - PgStore: PostgreSQL / Supabase (DATABASE_URL).
 * Sólo la API escribe aquí; ni el navegador ni el cliente del juego tienen acceso.
 */
export interface Store {
  upsertPlayer(p: { provider: 'discord' | 'dev'; providerId: string; displayName: string; avatarUrl: string | null }): Promise<string>;
  getProfile(id: string): Promise<PlayerProfile | null>;
  updateCharacter(id: string, c: Character): Promise<void>;

  createRoom(r: { code: string; visibility: RoomVisibility; ownerId: string; serverId: string }): Promise<boolean>;
  getRoom(code: string): Promise<RoomRow | null>;
  listOpenPublicRooms(): Promise<RoomRow[]>;
  listOpenRooms(): Promise<RoomRow[]>;
  updateRoom(code: string, patch: { gateOpen?: boolean; status?: 'open' | 'closed'; touch?: boolean }): Promise<void>;
  addMember(code: string, playerId: string): Promise<void>;
  removeMember(code: string, playerId: string): Promise<void>;
  listMembers(code: string): Promise<MemberRow[]>;

  recordSession(s: { jti: string; playerId: string; code: string; expiresAt: Date }): Promise<void>;

  /**
   * Otorga una recompensa de forma transaccional e idempotente.
   * Devuelve true sólo la primera vez que se aplica esa clave.
   */
  grantReward(g: { playerId: string; reward: string; source: string; idempotencyKey: string; effect: RewardEffect }): Promise<boolean>;

  close(): Promise<void>;
}
