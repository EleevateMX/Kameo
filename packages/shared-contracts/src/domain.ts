import type { FormId } from './protocol.ts';

export const HATS = ['Sombrero de palma', 'Penacho', 'Flor de mayo', 'Sin sombrero'] as const;
export const ALUX_COLORS = ['#2ec4a6', '#e4007c', '#ffd23f', '#ff7a1a', '#19b4d6', '#8f5bd6', '#7ccf4e', '#f25f5c'] as const;

export interface Character {
  name: string;
  color: string;
  hat: number;
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
export const REWARDS: Record<string, { title: string; quest?: string; unlock?: FormId }> = {
  llamado_de_yaxche: { title: 'El llamado de la abuela', quest: 'cap1_llamado' },
  sello_del_claro: { title: 'Sello del Claro', quest: 'cap1_santuario' },
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
