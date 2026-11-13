import type { FormId } from './protocol.ts';

// ── Apariencia del alux (personalizador 3D) ──
// Cada lista es un catálogo: el índice es lo que se guarda y lo que viaja al juego, y el nombre del
// nodo o del material del modelo (game/assets/characters/alux.glb) está en
// game/scripts/shared/look_def.gd, que debe llevar las mismas listas en el mismo orden.
export const HATS = ['Sombrero de palma', 'Penacho', 'Flor de mayo', 'Sin tocado', 'Diadema de plumas', 'Pañuelo', 'Corona de hojas'] as const;
export const OUTFITS = ['Túnica', 'Capa corta', 'Faja con flecos', 'Bordado'] as const;
export const ACCESSORIES = ['Ninguno', 'Morral', 'Sonaja', 'Caracol', 'Farol de luciérnagas'] as const;
export const AMULETS = ['Ninguno', 'Colgante de jade', 'Concha', 'Espejo de obsidiana', 'Collar de semillas'] as const;
/** Color principal (túnica). */
export const ALUX_COLORS = ['#2ec4a6', '#e4007c', '#ffd23f', '#ff7a1a', '#19b4d6', '#8f5bd6', '#7ccf4e', '#f25f5c',
  '#fff7ec', '#3f7d5c', '#b3372e', '#31466b'] as const;
/** Color secundario (ribetes, capa, faja, pañuelo). */
export const ACCENT_COLORS = ['#fff7ec', '#ffd23f', '#e4007c', '#ff7a1a', '#2ec4a6', '#19b4d6', '#8f5bd6', '#7ccf4e', '#b3372e', '#3d2a20'] as const;
/** Tonos de piel. El primero es el de siempre. */
export const SKIN_TONES = ['#a9714b', '#aa8062', '#8c563a', '#6f4530', '#a98b72'] as const;

/** Lo que el jugador elige además del color principal y el tocado. Todo son índices de los catálogos. */
export interface Look {
  outfit: number;
  accessory: number;
  amulet: number;
  accent: number;
  skin: number;
}
/** El alux de siempre lleva su morral y su colgante de jade: ése es el aspecto inicial. */
export const DEFAULT_LOOK: Look = { outfit: 0, accessory: 1, amulet: 1, accent: 0, skin: 0 };
const LOOK_LIMITS: Record<keyof Look, number> = {
  outfit: OUTFITS.length, accessory: ACCESSORIES.length, amulet: AMULETS.length, accent: ACCENT_COLORS.length, skin: SKIN_TONES.length,
};
/** Orden de los campos cuando la apariencia viaja como lista (ticket del juego y protocolo). */
export const LOOK_ORDER: (keyof Look)[] = ['outfit', 'accessory', 'amulet', 'accent', 'skin'];

/** Deja una apariencia válida: lo que falte o no exista en el catálogo vuelve a su valor inicial. */
export function cleanLook(raw: unknown): Look {
  const src = (raw && typeof raw === 'object' ? raw : {}) as Record<string, unknown>;
  const out = { ...DEFAULT_LOOK };
  for (const key of LOOK_ORDER) {
    const v = src[key];
    if (typeof v === 'number' && Number.isInteger(v) && v >= 0 && v < LOOK_LIMITS[key]) out[key] = v;
  }
  return out;
}
/** ¿Es exactamente una apariencia del catálogo? (para rechazar lo que mande un cliente manipulado) */
export function isValidLook(raw: unknown): raw is Look {
  if (!raw || typeof raw !== 'object') return false;
  const src = raw as Record<string, unknown>;
  return LOOK_ORDER.every((key) => {
    const v = src[key];
    return typeof v === 'number' && Number.isInteger(v) && v >= 0 && v < LOOK_LIMITS[key];
  }) && Object.keys(src).every((k) => (LOOK_ORDER as string[]).includes(k));
}
export const lookToList = (look: Look): number[] => LOOK_ORDER.map((key) => look[key]);

export interface Character {
  name: string;
  color: string;
  hat: number;
  look: Look;
}

export interface PlayerProfile {
  id: string;
  displayName: string;
  avatarUrl: string | null;
  provider: 'discord' | 'dev' | 'beta';
  character: Character;
  unlocks: FormId[];
  rewards: string[];
  quests: Record<string, string>;
  /** Progresión RPG (nivel, experiencia, semillas, inventario). Sólo la trae `GET /v1/me`. */
  rpg?: import('./rpg.ts').RpgView;
}

export type RoomVisibility = 'private' | 'public';

export interface RoomInfo {
  code: string;
  visibility: RoomVisibility;
  ownerId: string;
  createdAt: string;
  members: { id: string; name: string; color: string; online: boolean }[];
  online: number;
  gateOpen: boolean;
}

/** Catálogo de recompensas que el servidor de juego puede otorgar. */
export const REWARDS: Record<string, { title: string; quest?: string; unlock?: FormId; kind?: 'object'; note?: string }> = {
  llamado_de_yaxche: { title: 'El llamado de la abuela', quest: 'cap1_llamado' },
  sello_del_claro: { title: 'Sello del Claro', quest: 'cap1_santuario' },
  /** Objeto ancestral: la entrega Nojoch Tuunich al recordar quién es. Señala el Cenote (capítulo II). */
  pluma_de_jade: { title: 'Pluma de Jade', quest: 'cap1_guardian', kind: 'object', note: 'Tira hacia el agua del cenote' },
};

export const DEFAULT_UNLOCKS: FormId[] = ['alux', 'balam'];

export function isValidColor(c: unknown): c is string {
  return typeof c === 'string' && /^#[0-9a-fA-F]{6}$/.test(c);
}

export function cleanName(raw: unknown, fallback = 'Alux'): string {
  if (typeof raw !== 'string') return fallback;
  const s = raw.replace(/[\u0000-\u001f\u007f<>]/g, '').replace(/\s+/g, ' ').trim().slice(0, 20);
  return s.length >= 2 ? s : fallback;
}
