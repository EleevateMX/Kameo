// Equilibrio de la progresión RPG en los niveles 1, 5 y 10 (docs/RPG.md): cuánto separa a un
// alux recién llegado de uno con todo lo que esta versión permite. Sin servidores: son las
// mismas fórmulas que usa la API (packages/shared-contracts/src/rpg.ts).
//
//   npx tsx --test rpg-balance.test.ts
import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  AMULETS_RPG, AMULET_PRICE, GACHA, GRANTS, RARITY_BONUS, RPG_MAX_LEVEL, SKILLS, levelFromXp, rpgStats, xpForLevel, xpToNext,
  type RpgState,
} from '@alux/shared-contracts';

// Del combate del Claro (game/scripts/shared/combat_def.gd): daño base y criatura de referencia
const CHISPA = 12, GARRAS = 16, WEAK = 1.5;          // las corrompidas reciben ×1.5
const FOE_HP = 40, FOE_DMG = 15;

const build = (level: number, opts: { amulet?: string; chispa?: number; garras?: number } = {}): RpgState => ({
  xp: xpForLevel(level), seeds: 0, pity: 0,
  skills: { chispa: opts.chispa ?? 0, garras: opts.garras ?? 0 },
  items: opts.amulet ? [{ id: 'x', item: opts.amulet, rarity: AMULETS_RPG.find((a) => a.id === opts.amulet)!.rarity }] : [],
  equipped: opts.amulet ? 'x' : null,
});
const row = (label: string, s: RpgState) => {
  const st = rpgStats(s);
  const chispa = CHISPA * st.dmg.all * st.dmg.chispa * WEAK;
  const garras = GARRAS * st.dmg.all * st.dmg.garras * WEAK;
  return {
    label, level: st.lv, hp: st.hp, chispa: Math.round(chispa * 10) / 10, garras: Math.round(garras * 10) / 10,
    hitsToKill: Math.ceil(FOE_HP / Math.round(chispa)), hitsToDie: Math.ceil(st.hp / FOE_DMG),
  };
};

test('curva: 100 + 20·(n−1)², máximo provisional 10', () => {
  assert.deepEqual([1, 2, 3, 5, 9].map(xpToNext), [100, 120, 180, 420, 1380]);
  assert.deepEqual([1, 5, 10].map(xpForLevel), [0, 680, 4980]);
  assert.equal(levelFromXp(4979).level, 9);
  assert.equal(levelFromXp(4980).level, 10);
  assert.equal(levelFromXp(999_999).level, RPG_MAX_LEVEL, 'no pasa del máximo');
});

test('equilibrio en niveles 1, 5 y 10: el equipo y el nivel ayudan, pero nadie sobra', () => {
  const table = [
    row('nivel 1, sin nada', build(1)),
    row('nivel 5, sin nada', build(5)),
    row('nivel 5, amuleto común de vida + Chispa I', build(5, { amulet: 'semilla_ceiba', chispa: 1 })),
    row('nivel 10, sin nada', build(10)),
    row('nivel 10, raro de daño + Chispa I + Garras I', build(10, { amulet: 'espejo_obsidiana', chispa: 1, garras: 1 })),
    row('nivel 10, legendario de vida + mejoras', build(10, { amulet: 'disco_sol', chispa: 1, garras: 1 })),
    row('nivel 10, legendario de daño + mejoras', build(10, { amulet: 'escama_serpiente', chispa: 1, garras: 1 })),
  ];
  console.log('\n  Perfil                                         Nv  Vida  Chispa  Garras  Chispas p/ vencer  Golpes que aguanta');
  for (const r of table) {
    console.log(`  ${r.label.padEnd(46)} ${String(r.level).padStart(2)}  ${String(r.hp).padStart(4)}  ${String(r.chispa).padStart(6)}  ${String(r.garras).padStart(6)}  ${String(r.hitsToKill).padStart(17)}  ${String(r.hitsToDie).padStart(18)}`);
  }
  const [l1, l5, , l10, , hpMax, dmgMax] = table;
  // El nivel solo: +1 % de vida por nivel y nada de daño
  assert.deepEqual([l1.hp, l5.hp, l10.hp], [100, 104, 109]);
  assert.deepEqual([l5.chispa, l10.chispa], [l1.chispa, l1.chispa], 'subir de nivel no da daño');
  // Lo máximo que esta versión permite frente a un recién llegado
  assert.ok(hpMax.hp / l1.hp <= 1.18, `vida: como mucho +18 % (${hpMax.hp} frente a ${l1.hp})`);
  assert.ok(dmgMax.chispa / l1.chispa <= 1.19, `daño: como mucho +19 % (${dmgMax.chispa} frente a ${l1.chispa})`);
  // En la práctica: una chispa menos por criatura y un golpe más de aguante, no otra liga
  assert.ok(l1.hitsToKill - dmgMax.hitsToKill <= 1, 'la diferencia es, como mucho, una chispa menos por criatura');
  assert.ok(hpMax.hitsToDie - l1.hitsToDie <= 1, 'y un golpe más de aguante');
  // Un nivel 5 al lado de un nivel 10 sin equipo: misma pegada, 5 % menos de vida
  assert.ok(l10.hp / l5.hp <= 1.05);
});

test('economía: lo que se gana jugando alcanza para comprar, sin regalar', () => {
  // Una sesión completa del Claro por primera vez: 4 criaturas del claro + 8 de la emboscada,
  // el Claro y la primera liberación de Nojoch (las invocaciones del guardián entran en el tope diario)
  const first = 12 * GRANTS.enemy.seeds + GRANTS.claro.seeds + GRANTS.nojoch.seeds;
  const xp = 12 * GRANTS.enemy.xp + GRANTS.claro.xp + GRANTS.nojoch.xp;
  assert.equal(first, 285);
  assert.equal(levelFromXp(xp).level, 4, `la primera partida completa deja en el nivel 4 (${xp} de experiencia)`);
  assert.ok(first >= SKILLS.chispa.cost[0] + AMULET_PRICE.common!, 'da para la primera mejora y un amuleto común');
  assert.ok(first < SKILLS.chispa.cost[0] + SKILLS.garras.cost[0] + AMULET_PRICE.rare!, 'pero no para todo: hay que elegir');
  // Lo más que da un día de repetir (topes diarios): no hay semillas infinitas
  const daily = GRANTS.purify.limit * GRANTS.purify.seeds + GRANTS.enemy.limit * GRANTS.enemy.seeds + GRANTS.claro.seeds;
  assert.equal(daily, 595);
  assert.ok(daily / GACHA.cost < 6, 'menos de seis tiradas al día a base de repetir');
  // Gachapón: las probabilidades suman 1 y lo esperado por tirada no supera lo que cuesta comprar
  assert.equal(Object.values(GACHA.odds).reduce((a, b) => a + b, 0), 1000);
  assert.ok(RARITY_BONUS.legendary <= 0.08 && RARITY_BONUS.common === 0.02 && RARITY_BONUS.rare === 0.04);
});
