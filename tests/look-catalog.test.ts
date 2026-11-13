// Los catálogos del personalizador viven en dos sitios: el contrato compartido (lo que valida la
// API y muestra el portal) y game/scripts/shared/look_def.gd (lo que usan el servidor de juego y
// el cliente). El índice de cada lista es lo que se guarda y lo que viaja: si no coinciden, un
// jugador elegiría una cosa y los demás verían otra.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { ACCENT_COLORS, ACCESSORIES, ALUX_COLORS, AMULETS, HATS, LOOK_ORDER, OUTFITS, SKIN_TONES, cleanLook, isValidLook, lookToList } from '@alux/shared-contracts';

const gd = fs.readFileSync(path.resolve(import.meta.dirname, '../game/scripts/shared/look_def.gd'), 'utf8');
/** Lista de GDScript `const NOMBRE := [...]` como texto. */
const block = (name: string) => {
  const m = gd.match(new RegExp(`const ${name}(?:: Array)? :?= (\\[[\\s\\S]*?\\])\\n(?:\\n|const |##)`));
  assert.ok(m, `look_def.gd debe declarar ${name}`);
  return m![1];
};
/** Nombres de un catálogo: cada entrada es ["Nombre", …]; en los tocados lo que sigue es otra lista. */
const names = (name: string) => [...block(name).matchAll(name === 'HATS' ? /\["([^"]+)", \[/g : /\["([^"]+)", "/g)].map((m) => m[1]);
const strings = (name: string) => [...block(name).matchAll(/"([^"]+)"/g)].map((m) => m[1]);

test('los catálogos del juego y del contrato coinciden, en el mismo orden', () => {
  assert.deepEqual(names('HATS'), [...HATS]);
  assert.deepEqual(names('OUTFITS'), [...OUTFITS]);
  assert.deepEqual(names('ACCESSORIES'), [...ACCESSORIES]);
  assert.deepEqual(names('AMULETS'), [...AMULETS]);
  assert.deepEqual(strings('COLORS'), [...ALUX_COLORS]);
  assert.deepEqual(strings('ACCENTS'), [...ACCENT_COLORS]);
  assert.deepEqual(strings('SKINS'), [...SKIN_TONES]);
});

test('la apariencia viaja como lista en el mismo orden y con los mismos límites', () => {
  assert.deepEqual(LOOK_ORDER, ['outfit', 'accessory', 'amulet', 'accent', 'skin']);
  for (const [i, key] of ['OUTFIT', 'ACCESSORY', 'AMULET', 'ACCENT', 'SKIN'].entries()) {
    assert.match(gd, new RegExp(`const ${key} := ${i}\\b`), `${key} debe ser el campo ${i}`);
  }
  const limits = JSON.parse(block('LIMITS'));
  assert.deepEqual(limits, [OUTFITS.length, ACCESSORIES.length, AMULETS.length, ACCENT_COLORS.length, SKIN_TONES.length]);
  assert.deepEqual(lookToList({ outfit: 1, accessory: 2, amulet: 3, accent: 4, skin: 2 }), [1, 2, 3, 4, 2]);
});

test('lo que no es del catálogo no pasa', () => {
  assert.equal(isValidLook({ outfit: 0, accessory: 0, amulet: 0, accent: 0, skin: 0 }), true);
  assert.equal(isValidLook({ outfit: OUTFITS.length, accessory: 0, amulet: 0, accent: 0, skin: 0 }), false, 'índice fuera del catálogo');
  assert.equal(isValidLook({ outfit: 1.5, accessory: 0, amulet: 0, accent: 0, skin: 0 }), false, 'índice no entero');
  assert.equal(isValidLook({ outfit: 0, accessory: 0, amulet: 0, accent: 0 }), false, 'falta un campo');
  assert.equal(isValidLook({ outfit: 0, accessory: 0, amulet: 0, accent: 0, skin: 0, scale: 9 }), false, 'campo desconocido');
  // lo que falta o no vale vuelve al aspecto inicial (el alux de siempre lleva morral y colgante de jade)
  assert.deepEqual(cleanLook({ outfit: 99, accessory: 'x', amulet: 2 }), { outfit: 0, accessory: 1, amulet: 2, accent: 0, skin: 0 });
  assert.deepEqual(cleanLook(null), { outfit: 0, accessory: 1, amulet: 1, accent: 0, skin: 0 });
  assert.deepEqual(JSON.parse(block('DEFAULT')), lookToList(cleanLook(null)), 'el aspecto inicial es el mismo en el juego y en el contrato');
});
