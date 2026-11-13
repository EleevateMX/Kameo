// Progresión RPG de ALUX: números, catálogo y fórmulas compartidos por la API, el portal y las
// pruebas. Las reglas se aplican SIEMPRE en la API (apps/api/src/rpg.ts); aquí no hay estado.
// Contrato y decisiones: docs/RPG.md.

export const RPG_MAX_LEVEL = 10;          // máximo provisional de esta versión
export const RPG_BASE_HP = 100;
export const RPG_BASE_ENERGY = 100;
export const RPG_HP_PER_LEVEL = 0.01;     // +1 % de la vida base por cada nivel por encima del 1

/** Experiencia que hace falta para pasar del nivel `n` al `n + 1`. */
export const xpToNext = (n: number) => 100 + 20 * (n - 1) ** 2;

/** Experiencia total acumulada con la que se alcanza el nivel `n` (nivel 1: 0). */
export function xpForLevel(n: number): number {
  let total = 0;
  for (let i = 1; i < n; i++) total += xpToNext(i);
  return total;
}

/** Nivel que corresponde a una experiencia total (nunca pasa del máximo). */
export function levelFromXp(xp: number): { level: number; xpInLevel: number; xpToNext: number } {
  let level = 1;
  let rest = Math.max(0, Math.floor(xp));
  while (level < RPG_MAX_LEVEL && rest >= xpToNext(level)) {
    rest -= xpToNext(level);
    level++;
  }
  return { level, xpInLevel: rest, xpToNext: level < RPG_MAX_LEVEL ? xpToNext(level) : 0 };
}

// ───────────── Recompensas ─────────────
export type GrantKind = 'purify' | 'enemy' | 'discovery' | 'mission' | 'claro' | 'nojoch';
export const GRANT_KINDS: readonly GrantKind[] = ['purify', 'enemy', 'discovery', 'mission', 'claro', 'nojoch'];

/**
 * Qué da cada hecho y cuántas veces. `scope`:
 *  - 'daily'  repetible, con tope de `limit` al día (UTC); cada hecho con su propia clave
 *  - 'key'    una vez por jugador y clave (un lugar, una misión)
 *  - 'once'   una sola vez por jugador, pase lo que pase con la clave
 */
export const GRANTS: Record<GrantKind, { xp: number; seeds: number; scope: 'daily' | 'key' | 'once'; limit: number }> = {
  purify: { xp: 20, seeds: 8, scope: 'daily', limit: 40 },
  enemy: { xp: 15, seeds: 5, scope: 'daily', limit: 40 },
  discovery: { xp: 40, seeds: 15, scope: 'key', limit: 1 },
  mission: { xp: 100, seeds: 40, scope: 'key', limit: 1 },
  claro: { xp: 150, seeds: 75, scope: 'daily', limit: 1 },
  nojoch: { xp: 300, seeds: 150, scope: 'once', limit: 1 },
};

// ───────────── Habilidades ─────────────
export type SkillId = 'chispa' | 'garras';
export const SKILLS: Record<SkillId, { name: string; form: string; cost: number[]; bonus: number }> = {
  // cost[i]: semillas para pasar del rango i al i + 1; bonus: daño extra por rango (provisional)
  chispa: { name: 'Chispa de jade', form: 'alux', cost: [100], bonus: 0.10 },
  garras: { name: 'Garras', form: 'balam', cost: [150], bonus: 0.10 },
};

// ───────────── Amuletos ─────────────
export type Rarity = 'common' | 'rare' | 'epic' | 'legendary';
export const RARITIES: readonly Rarity[] = ['common', 'rare', 'epic', 'legendary'];
export const RARITY_NAMES: Record<Rarity, string> = { common: 'Común', rare: 'Raro', epic: 'Épico', legendary: 'Legendario' };
/** Bonificación de un amuleto según su rareza (épico y legendario: provisionales). */
export const RARITY_BONUS: Record<Rarity, number> = { common: 0.02, rare: 0.04, epic: 0.06, legendary: 0.08 };
/** Precio en la tienda (los que no aparecen no se venden: salen del gachapón). */
export const AMULET_PRICE: Partial<Record<Rarity, number>> = { common: 80, rare: 250 };

export interface AmuletDef { id: string; name: string; rarity: Rarity; stat: 'hp' | 'dmg'; }
/** Amuletos de poder (no confundir con el colgante cosmético del personalizador). */
export const AMULETS_RPG: readonly AmuletDef[] = [
  { id: 'semilla_ceiba', name: 'Semilla de ceiba', rarity: 'common', stat: 'hp' },
  { id: 'lasca_pedernal', name: 'Lasca de pedernal', rarity: 'common', stat: 'dmg' },
  { id: 'cuenta_jade', name: 'Cuenta de jade', rarity: 'rare', stat: 'hp' },
  { id: 'espejo_obsidiana', name: 'Espejo de obsidiana', rarity: 'rare', stat: 'dmg' },
  { id: 'brasa_copal', name: 'Brasa de copal', rarity: 'epic', stat: 'hp' },
  { id: 'caracol_viento', name: 'Caracol del viento', rarity: 'epic', stat: 'dmg' },
  { id: 'disco_sol', name: 'Disco del sol', rarity: 'legendary', stat: 'hp' },
  { id: 'escama_serpiente', name: 'Escama de la serpiente emplumada', rarity: 'legendary', stat: 'dmg' },
];
export const amuletDef = (id: string) => AMULETS_RPG.find((a) => a.id === id);

// ───────────── Gachapón ─────────────
export const GACHA = {
  cost: 100,
  /** Probabilidad de cada rareza, en tantos por mil (suman 1000). Públicas. */
  odds: { common: 700, rare: 250, epic: 40, legendary: 10 } as Record<Rarity, number>,
  /** Cada `pity` tiradas sale épico o mejor: tras `pity - 1` seguidas sin él, la siguiente lo garantiza. */
  pity: 20,
} as const;

// ───────────── Estado y estadísticas ─────────────
export interface RpgItem { id: string; item: string; rarity: Rarity; }
export interface RpgState {
  xp: number;
  seeds: number;
  skills: Partial<Record<SkillId, number>>;
  equipped: string | null;     // id de un objeto del inventario
  pity: number;                // tiradas seguidas sin épico o mejor
  items: RpgItem[];
}
export const EMPTY_RPG: RpgState = { xp: 0, seeds: 0, skills: {}, equipped: null, pity: 0, items: [] };

/** Lo que el combate necesita saber de un jugador (viaja en el ticket, calculado por la API). */
export interface RpgStats { lv: number; hp: number; dmg: { all: number; chispa: number; garras: number }; }
export const BASE_STATS: RpgStats = { lv: 1, hp: RPG_BASE_HP, dmg: { all: 1, chispa: 1, garras: 1 } };

const round3 = (v: number) => Math.round(v * 1000) / 1000;

export function rpgStats(s: RpgState): RpgStats {
  const { level } = levelFromXp(s.xp);
  const worn = s.equipped ? s.items.find((i) => i.id === s.equipped) : undefined;
  const def = worn ? amuletDef(worn.item) : undefined;
  const bonus = def ? RARITY_BONUS[def.rarity] : 0;
  return {
    lv: level,
    hp: Math.round(RPG_BASE_HP * (1 + RPG_HP_PER_LEVEL * (level - 1)) * (1 + (def?.stat === 'hp' ? bonus : 0))),
    dmg: {
      all: round3(1 + (def?.stat === 'dmg' ? bonus : 0)),
      chispa: round3(1 + SKILLS.chispa.bonus * (s.skills.chispa ?? 0)),
      garras: round3(1 + SKILLS.garras.bonus * (s.skills.garras ?? 0)),
    },
  };
}

/** Lo que ve el jugador en su perfil. */
export interface RpgView extends RpgState { level: number; xpInLevel: number; xpToNext: number; stats: RpgStats; }
export function rpgView(s: RpgState): RpgView {
  return { ...s, ...levelFromXp(s.xp), stats: rpgStats(s) };
}
