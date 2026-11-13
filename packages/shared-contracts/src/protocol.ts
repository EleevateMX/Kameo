// Protocolo WebSocket entre el cliente Godot y el servidor de juego (JSON).
// Documentación completa: docs/protocolo.md

export const PROTOCOL_VERSION = 2;
export const MAX_PLAYERS_PER_ROOM = 4;
export const GAME_TICKET_AUDIENCE = 'alux-game';
/** Tickets del servidor de zonas sociales (otro proceso): no valen en las salas, ni los de sala aquí. */
export const ZONE_TICKET_AUDIENCE = 'alux-zone';
/** Zonas sociales que existen. */
export const ZONES = ['merida'] as const;
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
  | { t: 'ping'; c: number }
  /** Voto para jugar otra ronda tras la victoria (v: 0 lo retira). Se reinicia cuando votan todos los conectados. */
  | { t: 'again'; v?: 0 | 1 }
  /** El jugador terminó de hablar con un personaje (n = su id). El servidor comprueba que está a su lado. */
  | { t: 'talk'; n: string }
  /** Voto para omitir la cinemática compartida en curso. Se omite cuando vota la mayoría de los conectados. */
  | { t: 'skip' }
  /**
   * Respuesta a `cine_prep`: el cliente terminó su transición de entrada. v = 1 si tiene el vídeo,
   * 0 si verá la escena del motor. Sólo acorta la espera: sin respuesta, la escena empieza igual.
   */
  | { t: 'cine_ready'; id: string; v: 0 | 1 };

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
/**
 * [santuarioAbierto, altares, altaresNecesarios, emboscada(0 pendiente/1 en curso/2 superada/3 fallida),
 *  enemigosRestantes, puntoDeReaparición, braseroListo, votosOtraRonda, conectados, segundosDeEsperaDeLosAltares,
 *  banderasDeHistoria(1 = alguien habló con Chiich Yaxché · 2 = Nojoch Tuunich liberado · 4 = pista del Cenote entregada), segundosDeCinemáticaCompartida(0 = ninguna; >0 = sala en pausa),
 *  votosParaOmitirla, faseDeLaCinemática(0 ninguna, 1 preparación, 2 reproducción, 3 reanudación)]
 */
export type WorldStateArray = number[];
/** [id, tipo(0 piedra, 1 corrupta), x, y, z, giro, vida, vidaMáx, estado, slotObjetivo] */
export type SnapshotEnemy = number[];
export const ENEMY_KINDS = ['piedra', 'corrupta'] as const;
/**
 * Nojoch Tuunich, el jefe del Capítulo I (docs/BOSS.md). Lo decide todo el servidor:
 * [fase(0 dormido, 1 olvido, 2 furia, 3 recuerdo, 4 liberado), x, z, giro, estado, segundosDelEstado,
 *  silencio(0–100), glifosEncendidos, glifosNecesarios, slotObjetivo, golpeX, golpeZ, giroDelBarrido,
 *  escombros[[x, z, radio, segundos]],
 *  anclasActivas(máscara), anclasNecesarias, columnas[[zócalo, segundos]], corazón(0–100), corazonesLiberados,
 *  glifosDelSuelo, glifosDelSueloNecesarios, contacto(0–100), quiénesLoTocan(máscara de slots), cuántosDebenTocarlo]
 * Eventos de combate propios (['boss', tipo, ...]):
 *  fase 1  awake [fase, glifos] · tele [ataque, segundos, ...] · slam · sweep · summon · glyph · far · phase [fase, silencio] · fail
 *  fase 2  transit · arena [fase] · pillar [zócalo, slot] · pillar_max · pillar_down · rain · charge [giro] · charge_end
 *          crash [zócalo, aturdido] · shake · anchor [i, activa] · bound [segundos, corazón] · unbound [liberado]
 *          clang [slot] (golpe sin efecto) · heart_hit [slot, daño, corazón] · heart [liberados, total, silencio, slot]
 *  fase 3  ritual [glifos] · lit [n, necesarios, slot] · contact [cuántos] · pulse · freed
 */
export type BossStateArray = [number, number, number, number, number, number, number, number, number, number, number, number, number, number[][],
  number, number, number[][], number, number, number, number, number, number, number];
export const BOSS_STATES = ['sleep', 'rise', 'idle', 'walk', 'slam_w', 'sweep_w', 'summon_w', 'recover', 'kneel', 'freed',
  'transit', 'pillars_w', 'rain_w', 'rain', 'charge_w', 'charge', 'stunned', 'bound', 'ritual'] as const;
export const ENEMY_STATES = ['idle', 'chase', 'windup', 'strike', 'recover', 'stun', 'dead', 'return'] as const;

/**
 * Eventos de combate (campo `ev` de cada snapshot). El primer elemento es el tipo:
 *  ["act", slot, acción, giro, potencia]      animación de un jugador (bolt, claw, charged, pounce, pounce_land, dodge, interact, charge_start, charge_cancel, form)
 *  ["bolt", id, slot, x, y, z, giro]          nace un proyectil
 *  ["bolt_end", id, x, y, z, impactó]
 *  ["hit", "e"|"p", idOSlot, daño, vidaRestante, slotAtacante]
 *  ["die", "e"|"p", idOSlot, purificado, slotAutor]
 *  ["respawn", slot] · ["heal", slot, cantidad, vida] · ["evade", slot] · ["eatk", idEnemigo]
 *  ["brazier", slot] · ["enc", "start"|"clear"|"fail", enemigos]
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
  | { t: 'welcome'; v: number; id: string; slot: number; room: string; rejoin: boolean; unlocked: FormId[]; me: PlayerStateArray; hp: number; players: RosterEntry[]; w: WorldStateArray; e: SnapshotEnemy[]; b?: BossStateArray; tick_rate: number }
  | { t: 'roster'; players: RosterEntry[] }
  | { t: 'snap'; k: number; w: WorldStateArray; p: SnapshotPlayer[]; e: SnapshotEnemy[]; ev: CombatEvent[]; b?: BossStateArray }
  | { t: 'event'; e: 'gate_open'; by: string[] }
  | { t: 'event'; e: 'reward'; reward: string; saved: boolean; new: boolean }
  /** defeat: todo el grupo cayó y el santuario se vuelve a sellar · restart: nueva ronda pedida por el grupo */
  | { t: 'event'; e: 'defeat' | 'restart' }
  /**
   * Avance de la historia de la sala, siempre decidido por el servidor:
   * k = 'talked' (alguien habló con el personaje npc) · 'freed' (Nojoch Tuunich recordó; by = nombres)
   * · 'clue' (el guardián liberado señaló el camino del Cenote).
   */
  | { t: 'event'; e: 'story'; k: string; npc?: string; by: string | string[] }
  /**
   * Cinemática compartida: la dirige el servidor y la sala está en pausa en sus tres fases.
   * cine_prep: prepárense (wait = segundos máximos de espera) → cine: orden de inicio para todos
   * (at = segundos ya transcurridos, para quien se engancha a mitad) → cine_end: terminó; la sala
   * sigue en pausa un instante más (fase de reanudación) y luego continúa la partida.
   */
  | { t: 'event'; e: 'cine_prep'; id: string; wait: number }
  | { t: 'event'; e: 'cine'; id: string; dur: number; at: number }
  | { t: 'event'; e: 'cine_end'; id: string; skipped: boolean }
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
