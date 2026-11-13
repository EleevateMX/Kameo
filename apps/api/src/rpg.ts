// Reglas de la progresión RPG. Todo pasa por store.rpgApply, que es atómico e idempotente:
// aquí sólo se decide qué cambia. Contrato y números: docs/RPG.md y @alux/shared-contracts (rpg.ts).
import { randomInt } from 'node:crypto';
import {
  AMULETS_RPG, AMULET_PRICE, GACHA, GRANTS, GRANT_KINDS, SKILLS, amuletDef, levelFromXp, rpgView,
  type GrantKind, type Rarity, type RpgView, type SkillId,
} from '@alux/shared-contracts';
import type { Store } from './store/types.ts';

const KEY_RE = /^[\w:.\-]{1,120}$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export interface GrantResult {
  playerId: string; kind: string; applied: boolean; reason?: string;
  xp: number; seeds: number; level: number; leveledUp: boolean; totalXp: number; totalSeeds: number;
}

/** Una recompensa por algo que pasó en el juego. Las cantidades las pone la API, no quien avisa. */
export async function grant(store: Store, playerId: string, kind: string, key: string): Promise<GrantResult> {
  const blank = { playerId, kind, xp: 0, seeds: 0, level: 1, leveledUp: false, totalXp: 0, totalSeeds: 0 };
  if (!GRANT_KINDS.includes(kind as GrantKind) || !UUID_RE.test(playerId) || typeof key !== 'string' || !KEY_RE.test(key)) {
    return { ...blank, applied: false, reason: 'invalid' };
  }
  const def = GRANTS[kind as GrantKind];
  let before = 1;
  const out = await store.rpgApply({
    playerId, kind,
    // «once»: la misma clave para siempre, diga lo que diga quien avisa
    key: def.scope === 'once' ? `${kind}:once` : `${kind}:${key}`,
    decide: (state, today) => {
      before = levelFromXp(state.xp).level;
      if (def.scope === 'daily' && today >= def.limit) return { reject: 'daily_limit' };
      return { xp: def.xp, seeds: def.seeds };
    },
  });
  const level = levelFromXp(out.state.xp).level;
  return {
    playerId, kind, applied: out.applied, ...(out.reason ? { reason: out.reason } : {}),
    xp: out.applied ? def.xp : 0, seeds: out.applied ? def.seeds : 0,
    level, leveledUp: out.applied && level > before, totalXp: out.state.xp, totalSeeds: out.state.seeds,
  };
}

export type ShopResult = { ok: true; rpg: RpgView; item?: { id: string; item: string; rarity: Rarity; name: string }; repeated?: boolean }
  | { ok: false; status: number; error: string };

const fail = (reason: string | undefined): ShopResult => {
  const status = reason === 'not_enough_seeds' ? 402 : reason === 'already_owned' || reason === 'max_rank' ? 409 : 400;
  return { ok: false, status, error: reason === 'max_rank' ? 'already_owned' : (reason ?? 'invalid') };
};

/** Compra en el Puesto de Saberes: una mejora de habilidad o un amuleto de los que se venden. */
export async function buy(store: Store, playerId: string, what: unknown, requestId: unknown): Promise<ShopResult> {
  if (typeof what !== 'string' || typeof requestId !== 'string' || !UUID_RE.test(requestId)) return fail('invalid');
  const [type, id] = what.split(':');
  const out = await store.rpgApply({
    playerId, kind: 'buy', key: `buy:${requestId}`,
    decide: (state) => {
      if (type === 'skill' && id in SKILLS) {
        const skill = SKILLS[id as SkillId];
        const rank = state.skills[id as SkillId] ?? 0;
        if (rank >= skill.cost.length) return { reject: 'max_rank' };
        if (state.seeds < skill.cost[rank]) return { reject: 'not_enough_seeds' };
        return { seeds: -skill.cost[rank], skill: { id: id as SkillId, rank: rank + 1 }, result: { what } };
      }
      if (type === 'amulet') {
        const def = amuletDef(id);
        const price = def ? AMULET_PRICE[def.rarity] : undefined;
        if (!def || price === undefined) return { reject: 'invalid' };
        if (state.items.some((i) => i.item === def.id)) return { reject: 'already_owned' };
        if (state.seeds < price) return { reject: 'not_enough_seeds' };
        return { seeds: -price, addItem: { item: def.id, rarity: def.rarity }, result: { what, item: def.id, rarity: def.rarity } };
      }
      return { reject: 'invalid' };
    },
  });
  if (!out.applied && out.reason !== 'duplicate') return fail(out.reason);
  const got = out.result?.item ? amuletDef(String(out.result.item)) : undefined;
  return {
    ok: true, rpg: rpgView(out.state), repeated: !out.applied,
    ...(got && out.itemId ? { item: { id: out.itemId, item: got.id, rarity: got.rarity, name: got.name } } : {}),
  };
}

/** Rareza de una tirada. `roll` es un entero de 0 a 999; con la garantía sólo cuentan épico y legendario. */
export function gachaRarity(roll: number, guaranteed: boolean): Rarity {
  const o = GACHA.odds;
  if (guaranteed) {
    // Misma proporción entre épico y legendario que en una tirada normal
    return roll < Math.round(1000 * o.legendary / (o.epic + o.legendary)) ? 'legendary' : 'epic';
  }
  if (roll < o.legendary) return 'legendary';
  if (roll < o.legendary + o.epic) return 'epic';
  if (roll < o.legendary + o.epic + o.rare) return 'rare';
  return 'common';
}

/** Una tirada del gachapón. `rng` sólo se cambia en las pruebas. */
export async function gacha(store: Store, playerId: string, requestId: unknown, rng: (n: number) => number = randomInt): Promise<ShopResult> {
  if (typeof requestId !== 'string' || !UUID_RE.test(requestId)) return fail('invalid');
  const out = await store.rpgApply({
    playerId, kind: 'gacha', key: `gacha:${requestId}`,
    decide: (state) => {
      if (state.seeds < GACHA.cost) return { reject: 'not_enough_seeds' };
      const guaranteed = state.pity >= GACHA.pity - 1;
      const rarity = gachaRarity(rng(1000), guaranteed);
      const pool = AMULETS_RPG.filter((a) => a.rarity === rarity);
      const item = pool[rng(pool.length)];
      const high = rarity === 'epic' || rarity === 'legendary';
      return {
        seeds: -GACHA.cost, pity: high ? 0 : state.pity + 1,
        addItem: { item: item.id, rarity }, result: { item: item.id, rarity, guaranteed },
      };
    },
  });
  if (!out.applied && out.reason !== 'duplicate') return fail(out.reason);
  const def = amuletDef(String(out.result?.item ?? ''));
  if (!def || !out.itemId) return fail('invalid');
  return { ok: true, rpg: rpgView(out.state), repeated: !out.applied, item: { id: out.itemId, item: def.id, rarity: def.rarity, name: def.name } };
}

/** Equipa un objeto del inventario propio (o ninguno). No cuesta nada y se puede repetir. */
export async function equip(store: Store, playerId: string, itemId: unknown): Promise<ShopResult> {
  if (itemId !== null && (typeof itemId !== 'string' || !UUID_RE.test(itemId))) return fail('invalid');
  const state = await store.getRpg(playerId);
  if (itemId !== null && !state.items.some((i) => i.id === itemId)) return fail('invalid');
  if (state.equipped === itemId) return { ok: true, rpg: rpgView(state) };
  const out = await store.rpgApply({
    // Cada cambio es un apunte propio: la clave lleva el momento para que no choque con el anterior
    playerId, kind: 'equip', key: `equip:${Date.now()}:${itemId ?? 'none'}`,
    decide: (now) => (itemId === null || now.items.some((i) => i.id === itemId) ? { equipped: itemId as string | null } : { reject: 'invalid' }),
  });
  if (!out.applied) return fail(out.reason);
  return { ok: true, rpg: rpgView(out.state) };
}
