// Protocolo WebSocket entre el cliente Godot y el servidor de juego (JSON).
// Documentación completa: docs/protocolo.md

export const PROTOCOL_VERSION = 1;
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
export type ClientMessage =
  | { t: 'hello'; v: number; ticket: string }
  | { t: 'in'; s: number; mx: number; mz: number; j: 0 | 1; f: FormId | '' }
  | { t: 'ping'; c: number };

/** [x, y, z, vy, yaw, forma, cooldown, banderas(1=suelo, 2=nadando)] */
export type PlayerStateArray = [number, number, number, number, number, number, number, number];
/** [slot, últimoInputProcesado, conectado, ...estado] */
export type SnapshotPlayer = [number, number, 0 | 1, ...PlayerStateArray];
/** [santuarioAbierto, máscaraDeAltares, altaresNecesarios] */
export type WorldStateArray = [0 | 1, number, number];

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
  | { t: 'welcome'; v: number; id: string; slot: number; room: string; rejoin: boolean; unlocked: FormId[]; me: PlayerStateArray; players: RosterEntry[]; w: WorldStateArray; tick_rate: number }
  | { t: 'roster'; players: RosterEntry[] }
  | { t: 'snap'; k: number; w: WorldStateArray; p: SnapshotPlayer[] }
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
