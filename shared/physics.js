// Colisiones compartidas: el servidor las usa como autoridad y el navegador
// para predecir el movimiento del propio jugador.
import { WORLD, OBSTACLES, WATER } from './config.js';

const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);

function pushOutOfRect(ent, r, o) {
  const cx = clamp(ent.x, o.x, o.x + o.w);
  const cy = clamp(ent.y, o.y, o.y + o.h);
  const dx = ent.x - cx;
  const dy = ent.y - cy;
  const d2 = dx * dx + dy * dy;
  if (d2 >= r * r) return;
  if (d2 > 0.0001) {
    const d = Math.sqrt(d2);
    ent.x += (dx / d) * (r - d);
    ent.y += (dy / d) * (r - d);
    return;
  }
  // El centro quedó dentro: sacar por el lado más cercano
  const left = ent.x - o.x, right = o.x + o.w - ent.x;
  const top = ent.y - o.y, bottom = o.y + o.h - ent.y;
  const m = Math.min(left, right, top, bottom);
  if (m === left) ent.x = o.x - r;
  else if (m === right) ent.x = o.x + o.w + r;
  else if (m === top) ent.y = o.y - r;
  else ent.y = o.y + o.h + r;
}

function pushOutOfCircle(ent, r, c) {
  let dx = ent.x - c.x;
  let dy = ent.y - c.y;
  const min = c.r + r;
  const d2 = dx * dx + dy * dy;
  if (d2 >= min * min) return;
  if (d2 < 0.0001) { dx = 0; dy = -1; } // justo en el centro: salir hacia arriba
  const d = Math.hypot(dx, dy);
  ent.x = c.x + (dx / d) * min;
  ent.y = c.y + (dy / d) * min;
}

export function resolveCollisions(ent, r, canSwim = false) {
  for (const o of OBSTACLES) pushOutOfRect(ent, r, o);
  if (!canSwim) {
    for (const w of WATER) {
      if (w.type === 'circle') pushOutOfCircle(ent, r, w);
      else pushOutOfRect(ent, r, w);
    }
  }
  ent.x = clamp(ent.x, r, WORLD.w - r);
  ent.y = clamp(ent.y, r, WORLD.h - r);
}

// ¿Un punto (proyectil) choca contra un edificio?
export function pointInBuilding(x, y) {
  if (x < 0 || y < 0 || x > WORLD.w || y > WORLD.h) return true;
  for (const o of OBSTACLES) {
    if (x >= o.x && x <= o.x + o.w && y >= o.y && y <= o.y + o.h) return true;
  }
  return false;
}

// ¿Hay espacio libre para una entidad de radio r en (x, y)?
export function isFree(x, y, r) {
  const probe = { x, y };
  resolveCollisions(probe, r, false);
  return Math.abs(probe.x - x) < 0.5 && Math.abs(probe.y - y) < 0.5;
}

export function moveEntity(ent, dx, dy, speed, dt, r, canSwim) {
  const len = Math.hypot(dx, dy);
  if (len > 0) {
    ent.x += (dx / len) * speed * dt;
    ent.y += (dy / len) * speed * dt;
  }
  resolveCollisions(ent, r, canSwim);
}
