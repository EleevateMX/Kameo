// Protocolo WebSocket entre el cliente Godot y el servidor de juego (JSON).
// Documentación completa: docs/protocolo.md

export const PROTOCOL_VERSION = 2;
export const MAX_PLAYERS_PER_ROOM = 4;
export const GAME_TICKET_AUDIENCE = 'alux-game';
export const SESSION_AUDIENCE = 'alux-session';
export const GAME_TICKET_TTL_SECONDS = 90;

export type FormId = 'alux' | 'balam';
export const FORM_IDS: FormId[] = ['alux', 'balam'];

/** Contenido del ticket que la API firma y el servidor de juego verifica. */
export interface GameTicketClaims {
  aud: typeof GAME_TICKET_AUDIENCE;
  sub: string;      // id del jugador
  jti: string;      // un solo uso
  room: string;     // código de sala
  name: string;
  color: string;    // #rrggbb
  hat: number;      // 0..3
  forms: FormId[];  // transformaciones desbloqueadas
  iat: number;
  exp: number;
}

// Cliente → servidor
/** Botones del campo `a` de cada input. */
export const ACTION_PRIMARY = 1;
export const ACTION_SECONDARY = 2;
export const ACTION_SPECIAL = 4;

export type ClientMessage =
  | { t: 'hello'; v: number; ticket: string }
  /** s secuencia · mx,mz dirección · j salto · f forma deseada · a botones · r giro de puntería (rad) */
  | { t: 'in'; s: number; mx: number; mz: number; j: 0 | 1; f: FormId | ''; a?: number; r?: number }
  | { t: 'ping'; c: number };

/**
 * Estado simulado del jugador (19 valores):
 * [x, y, z, vy, giro, forma, cdForma, banderas(1 suelo, 2 nada, 4 salto ofensivo, 8 caído),
 *  energía, cd1, cd2, cd3, esquiva, esquivaX, esquivaZ, carga, empujeX, empujeZ, botonesPrevios]
 */
export type PlayerStateArray = number[];
/** [slot, últimoInputProcesado, conectado, vida, ...estado] */
export type SnapshotPlayer = number[];
export const SNAP_SLOT = 0, SNAP_ACK = 1, SNAP_ON = 2, SNAP_HP = 3, SNAP_X = 4, SNAP_Y = 5, SNAP_Z = 6,
  SNAP_FORM = 9, SNAP_FLAGS = 11, SNAP_ENERGY = 12;
/** [santuarioAbierto, altares, altaresNecesarios, emboscada(0 pendiente/1 en curso/2 superada), enemigosRestantes, puntoDeReaparición, braseroListo] */
export type WorldStateArray = number[];
/** [id, tipo(0 piedra, 1 corrupta), x, y, z, giro, vida, vidaMáx, estado, slotObjetivo] */
export type SnapshotEnemy = number[];
export const ENEMY_KINDS = ['piedra', 'corrupta'] as const;
export const ENEMY_STATES = ['idle', 'chase', 'windup', 'strike', 'recover', 'stun', 'dead', 'return'] as const;

/**
 * Eventos de combate (campo `ev` de cada snapshot). El primer elemento es el tipo:
 *  ["act", slot, acción, giro, potencia]      animación de un jugador (bolt, claw, charged, pounce, pounce_land, dodge, interact, charge_start, charge_cancel, form)
 *  ["bolt", id, slot, x, y, z, giro]          nace un proyectil
 *  ["bolt_end", id, x, y, z, impactó]
 *  ["hit", "e"|"p", idOSlot, daño, vidaRestante, slotAtacante]
 *  ["die", "e"|"p", idOSlot, purificado, slotAutor]
 *  ["respawn", slot] · ["heal", slot, cantidad, vida] · ["evade", slot] · ["eatk", idEnemigo]
 *  ["brazier", slot] · ["enc", "start"|"clear", enemigos]
 */
export type CombatEvent = (string | number)[];

export interface RosterEntry {
  id: string;
  slot: number;
  name: string;
  color: string;
  hat: number;
  on: boolean;
}

// Servidor → cliente
export type ServerMessage =
  | { t: 'welcome'; v: number; id: string; slot: number; room: string; rejoin: boolean; unlocked: FormId[]; me: PlayerStateArray; hp: number; players: RosterEntry[]; w: WorldStateArray; e: SnapshotEnemy[]; tick_rate: number }
  | { t: 'roster'; players: RosterEntry[] }
  | { t: 'snap'; k: number; w: WorldStateArray; p: SnapshotPlayer[]; e: SnapshotEnemy[]; ev: CombatEvent[] }
  | { t: 'event'; e: 'gate_open'; by: string[] }
  | { t: 'event'; e: 'reward'; reward: string; saved: boolean; new: boolean }
  | { t: 'pong'; c: number }
  | { t: 'error'; code: string; msg: string };

// Servidor de juego → API (interno, con x-service-key)
export interface HeartbeatBody {
  server_id: string;
  rooms: { code: string; players: { id: string; on: boolean }[]; gate_open: boolean }[];
}
export interface RewardBody {
  server_id: string;
  room: string;
  reward: string;
  players: string[];
  idempotency_key: string;
}
export interface RewardResult {
  granted: string[]; // jugadores que la recibieron por primera vez
}
