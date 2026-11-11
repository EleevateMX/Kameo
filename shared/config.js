// Configuración compartida entre servidor y navegador.
// Todo lo que define el "mundo" de ALUX vive aquí para que ambos lados coincidan.

export const TICK_RATE = 30;      // simulaciones por segundo en el servidor
export const SNAPSHOT_RATE = 15;  // estados enviados por segundo a los clientes

export const WORLD = { w: 3600, h: 2400 };

// Plaza Grande: punto de aparición
export const SPAWN = { x: 600, y: 600 };

// Ciudad Blanca está dividida en 6 distritos de 1200x1200
export const DISTRICTS = [
  { id: 'centro',   name: 'Centro Histórico',    x: 0,    y: 0,    w: 1200, h: 1200, ground: '#eadcb8', alt: '#e2d1a6', cap: 3, kinds: ['dron'] },
  { id: 'montejo',  name: 'Paseo de Montejo',    x: 1200, y: 0,    w: 1200, h: 1200, ground: '#d9d4c4', alt: '#cfc8b4', cap: 7, kinds: ['dron', 'dron', 'centinela'] },
  { id: 'torre',    name: 'Torre Obsidiana',     x: 2400, y: 0,    w: 1200, h: 1200, ground: '#2a2138', alt: '#231b30', cap: 8, kinds: ['dron', 'centinela', 'bruto'], boss: true },
  { id: 'cenote',   name: 'Cenote Sagrado',      x: 0,    y: 1200, w: 1200, h: 1200, ground: '#7fae5a', alt: '#76a453', cap: 6, kinds: ['dron', 'centinela'] },
  { id: 'hacienda', name: 'Hacienda Henequenera', x: 1200, y: 1200, w: 1200, h: 1200, ground: '#c9a76b', alt: '#c09d60', cap: 7, kinds: ['dron', 'bruto'] },
  { id: 'progreso', name: 'Malecón de Progreso', x: 2400, y: 1200, w: 1200, h: 1200, ground: '#f1e1b0', alt: '#ead79f', cap: 9, kinds: ['centinela', 'bruto', 'dron'] },
];

// Edificios y obstáculos sólidos { x, y, w, h, name?, style }
export const OBSTACLES = [
  // Centro Histórico
  { x: 420, y: 170, w: 360, h: 170, name: 'Catedral', style: 'catedral' },
  { x: 120, y: 430, w: 170, h: 340, name: 'Palacio Municipal', style: 'rosa' },
  { x: 420, y: 860, w: 360, h: 170, name: 'Casa de los Guardianes', style: 'amarillo' },
  { x: 910, y: 430, w: 170, h: 340, name: 'Palacio de Gobierno', style: 'azul' },
  { x: 60, y: 60, w: 180, h: 160, style: 'verde' },
  { x: 960, y: 60, w: 180, h: 160, style: 'rosa' },
  { x: 60, y: 980, w: 180, h: 160, style: 'azul' },
  { x: 960, y: 980, w: 180, h: 160, style: 'amarillo' },
  // Paseo de Montejo (casonas)
  { x: 1300, y: 90, w: 210, h: 200, style: 'rosa' },
  { x: 1300, y: 470, w: 210, h: 220, style: 'amarillo' },
  { x: 1300, y: 870, w: 210, h: 220, style: 'azul' },
  { x: 2090, y: 90, w: 210, h: 200, style: 'verde' },
  { x: 2090, y: 470, w: 210, h: 220, style: 'rosa' },
  { x: 2090, y: 870, w: 210, h: 220, style: 'amarillo' },
  { x: 1720, y: 640, w: 160, h: 110, name: 'Monumento', style: 'piedra' },
  // Torre Obsidiana (pilares)
  { x: 2560, y: 160, w: 100, h: 100, style: 'obsidiana' },
  { x: 3340, y: 160, w: 100, h: 100, style: 'obsidiana' },
  { x: 2560, y: 940, w: 100, h: 100, style: 'obsidiana' },
  { x: 3340, y: 940, w: 100, h: 100, style: 'obsidiana' },
  // Cenote Sagrado (rocas y selva)
  { x: 110, y: 1310, w: 150, h: 140, style: 'selva' },
  { x: 940, y: 1340, w: 150, h: 140, style: 'selva' },
  { x: 140, y: 2140, w: 170, h: 160, style: 'selva' },
  { x: 920, y: 2120, w: 170, h: 160, style: 'selva' },
  // Hacienda Henequenera
  { x: 1650, y: 1290, w: 300, h: 180, name: 'Casa Principal', style: 'rojo' },
  { x: 2160, y: 1330, w: 80, h: 80, name: 'Chimenea', style: 'piedra' },
  { x: 1320, y: 2060, w: 260, h: 140, name: 'Bodega', style: 'rojo' },
  { x: 1960, y: 2060, w: 260, h: 140, name: 'Desfibradora', style: 'piedra' },
  // Malecón de Progreso
  { x: 3360, y: 1320, w: 100, h: 100, name: 'Faro', style: 'faro' },
  { x: 2540, y: 1380, w: 230, h: 160, style: 'azul' },
  { x: 2820, y: 1660, w: 200, h: 140, style: 'amarillo' },
];

// Agua: sólo las formas que nadan (Áak) pueden entrar
export const WATER = [
  { type: 'circle', x: 600, y: 1820, r: 210, name: 'Cenote' },
  { type: 'rect', x: 2400, y: 2170, w: 1200, h: 230, name: 'Golfo de México' },
];

// Las 5 formas jugables. Itzel empieza con la Guardiana y Balam.
export const FORM_ORDER = ['guardian', 'balam', 'aak', 'tzunun', 'ceiba'];
export const STARTING_FORMS = ['guardian', 'balam'];

export const FORMS = {
  guardian: {
    name: 'Itzel', title: 'Guardiana de Jade', color: '#2ec4a6', speed: 230, hp: 100, r: 16,
    primary: { type: 'shot', dmg: 12, cd: 0.32, speed: 640, ttl: 0.9, kind: 'jade', r: 6 },
    special: { type: 'dash', cd: 2.5, dist: 220, dmg: 0 },
    desc: 'Disparo de jade y un salto ágil. Versátil, pero frágil.',
  },
  balam: {
    name: 'Balam', title: 'Jaguar de Fuego', color: '#ff7a1a', speed: 270, hp: 130, r: 18,
    primary: { type: 'melee', dmg: 30, cd: 0.38, range: 74, arc: 1.3 },
    special: { type: 'dash', cd: 3, dist: 300, dmg: 40 },
    desc: 'Zarpazos ardientes y una embestida que quema todo a su paso.',
  },
  aak: {
    name: 'Áak', title: 'Tortuga del Cenote', color: '#19b4d6', speed: 165, hp: 240, r: 24, swim: true,
    primary: { type: 'shot', dmg: 14, cd: 0.26, speed: 520, ttl: 0.8, kind: 'agua', r: 8, knock: 140 },
    special: { type: 'shield', cd: 9, dur: 2.5, heal: 50, radius: 230 },
    desc: 'Chorros que empujan, escudo que cura aliados y puede nadar.',
  },
  tzunun: {
    name: "Tz'unu'un", title: 'Colibrí del Relámpago', color: '#ffd23f', speed: 330, hp: 85, r: 13,
    primary: { type: 'shot', dmg: 8, cd: 0.11, speed: 820, ttl: 0.6, kind: 'rayo', r: 4 },
    special: { type: 'chain', cd: 5, dmg: 38, range: 340, hop: 260, max: 6 },
    desc: 'Rafagas eléctricas veloces y una cadena de relámpagos.',
  },
  ceiba: {
    name: 'Ceiba', title: 'Gólem de Raíces', color: '#5fae3c', speed: 150, hp: 280, r: 26,
    primary: { type: 'melee', dmg: 46, cd: 0.7, range: 88, arc: 1.6 },
    special: { type: 'quake', cd: 6, dmg: 60, radius: 210, stun: 1.5 },
    desc: 'Golpes pesados y un terremoto que aturde a los enemigos.',
  },
};

// Enemigos de Obsidiana Corp.
export const ENEMIES = {
  dron:      { name: 'Dron Obsidiana', hp: 40,   speed: 150, r: 16, dmg: 10, xp: 10 },
  centinela: { name: 'Centinela',      hp: 80,   speed: 90,  r: 20, dmg: 12, xp: 20, range: 380, fireCd: 1.6 },
  bruto:     { name: 'Bruto',          hp: 230,  speed: 85,  r: 30, dmg: 24, xp: 45 },
  okom:      { name: "Ok'om, Titán de Obsidiana", hp: 3200, speed: 70, r: 72, dmg: 30, xp: 600 },
};

// Cubos de contención donde Obsidiana Corp. encerró a los aluxes
export const CUBES = [
  { id: 'cubo-aak',      alux: 'aak',    x: 600,  y: 1480, district: 'cenote' },
  { id: 'cubo-tzunun',   alux: 'tzunun', x: 1800, y: 300,  district: 'montejo' },
  { id: 'cubo-ceiba',    alux: 'ceiba',  x: 1800, y: 1800, district: 'hacienda' },
  { id: 'cubo-errante',  alux: null,     x: 3150, y: 1900, district: 'progreso' },
];
export const CUBE_HP = 600;
export const CUBE_R = 28;
export const CUBE_RESPAWN = 45; // segundos

export const BOSS_SPAWN = { x: 3000, y: 600 };
export const BOSS_RESPAWN = 120;

export function levelFromXp(xp) {
  return Math.min(30, Math.floor(Math.sqrt(xp / 60)) + 1);
}
export function xpForLevel(lvl) {
  return 60 * (lvl - 1) * (lvl - 1);
}

export function districtAt(x, y) {
  for (const d of DISTRICTS) {
    if (x >= d.x && x < d.x + d.w && y >= d.y && y < d.y + d.h) return d;
  }
  return DISTRICTS[0];
}
