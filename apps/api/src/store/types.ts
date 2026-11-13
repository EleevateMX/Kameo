import type { Character, FormId, PlayerProfile, Rarity, RoomVisibility, RpgState, SkillId } from '@alux/shared-contracts';

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

/** Lo que decide una regla de la progresión RPG sobre el estado (ya bloqueado) de un jugador. */
export interface RpgChange {
  xp?: number;                                   // experiencia que se suma
  seeds?: number;                                // semillas que se suman (negativo: gasto)
  skill?: { id: SkillId; rank: number };         // deja una habilidad en ese rango
  equipped?: string | null;                      // objeto equipado (null: ninguno); undefined: no cambia
  pity?: number;                                 // contador de garantía del gachapón
  addItem?: { item: string; rarity: Rarity };    // objeto nuevo en el inventario
  /** Lo que se devuelve a quien repita la misma clave (p. ej. qué salió en el gachapón). */
  result?: Record<string, unknown>;
}
export interface RpgApplied {
  applied: boolean;
  reason?: string;                               // 'duplicate', o el motivo del rechazo
  state: RpgState;
  result?: Record<string, unknown>;
  /** Objeto creado por este apunte (o por el original, si es una repetición). */
  itemId?: string;
}

/**
 * Persistencia. Hay dos implementaciones:
 *  - MemoryStore: archivo JSON local, para desarrollar sin base de datos.
 *  - PgStore: PostgreSQL / Supabase (DATABASE_URL).
 * Sólo la API escribe aquí; ni el navegador ni el cliente del juego tienen acceso.
 */
export interface Store {
  upsertPlayer(p: { provider: 'discord' | 'dev' | 'beta'; providerId: string; displayName: string; avatarUrl: string | null }): Promise<string>;
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

  /** Progresión RPG de un jugador (si aún no tiene, la de un alux recién llegado). */
  getRpg(playerId: string): Promise<RpgState>;
  /**
   * Aplica un movimiento de la progresión de forma atómica e idempotente: bloquea el estado del
   * jugador, comprueba que la clave no se haya usado ya y llama a `decide` con el estado y con
   * cuántos apuntes de ese `kind` lleva hoy (día UTC). `decide` devuelve el cambio o un rechazo.
   * Repetir una clave no cambia nada y devuelve el resultado del apunte original.
   */
  rpgApply(a: {
    playerId: string; kind: string; key: string;
    decide: (state: RpgState, today: number) => RpgChange | { reject: string };
  }): Promise<RpgApplied>;

  /** Guarda (o actualiza) las métricas de una sesión de juego. */
  saveMetrics(m: SessionMetrics): Promise<void>;
  /** Últimas sesiones registradas, de la más reciente a la más antigua. */
  listMetrics(limit: number): Promise<(SessionMetrics & { createdAt: Date; updatedAt: Date })[]>;

  /** ¿Responde el almacén? (para la comprobación de disponibilidad) */
  ping(): Promise<boolean>;
  close(): Promise<void>;
}

/** Rendimiento de una sesión de juego, tal como lo mide el navegador del jugador. */
export interface SessionMetrics {
  sessionId: string;
  playerId: string;
  room: string;
  quality: string;
  fpsAvg: number | null;
  fpsMin: number | null;
  pingAvg: number | null;
  pingMax: number | null;
  loadMs: number | null;
  seconds: number;
  /** Resto de datos (memoria, navegador, resolución, volumen, resultados…). */
  data: Record<string, unknown>;
}
