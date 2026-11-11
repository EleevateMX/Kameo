// Dibujo del mundo con Canvas 2D. Todo es vectorial (sin imágenes externas)
// para que el juego cargue rápido y tenga un estilo propio.
import { WORLD, DISTRICTS, OBSTACLES, WATER, FORMS, ENEMIES, CUBE_R, SPAWN } from '/shared/config.js';

const TAU = Math.PI * 2;

const FACADES = {
  rosa: ['#e86a92', '#c94f77'],
  amarillo: ['#f2c14e', '#d3a032'],
  azul: ['#4f8fd6', '#3a71b5'],
  verde: ['#62b37a', '#4a9661'],
  rojo: ['#c4553a', '#a23f29'],
  piedra: ['#bdb4a3', '#9d937f'],
  catedral: ['#d8c9a8', '#b8a784'],
  obsidiana: ['#1a1424', '#0e0a15'],
  faro: ['#f4f1ea', '#d14b3d'],
};

// Pseudoaleatorio estable para decorar el mapa igual en cada cuadro
function seeded(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 4294967296;
  };
}

function buildDecor() {
  const r = seeded(20251122);
  const decor = { henequen: [], trees: [], palms: [], lamps: [] };
  const hac = DISTRICTS.find((d) => d.id === 'hacienda');
  for (let row = 0; row < 7; row++) {
    for (let col = 0; col < 13; col++) {
      const x = hac.x + 120 + col * 75 + (row % 2) * 30;
      const y = hac.y + 560 + row * 62;
      if (Math.hypot(x - 1800, y - 1800) < 150) continue;
      decor.henequen.push({ x, y, s: 0.8 + r() * 0.4 });
    }
  }
  const cen = DISTRICTS.find((d) => d.id === 'cenote');
  for (let i = 0; i < 70; i++) {
    const x = cen.x + 40 + r() * (cen.w - 80);
    const y = cen.y + 40 + r() * (cen.h - 80);
    if (Math.hypot(x - 600, y - 1820) < 300 || Math.hypot(x - 600, y - 1480) < 90) continue;
    decor.trees.push({ x, y, s: 18 + r() * 22, c: r() });
  }
  const pro = DISTRICTS.find((d) => d.id === 'progreso');
  for (let i = 0; i < 16; i++) {
    decor.palms.push({ x: pro.x + 60 + i * 72 + r() * 20, y: 2120 - r() * 30, s: 0.8 + r() * 0.4 });
  }
  // Plaza Grande: laureles
  for (let i = 0; i < 12; i++) {
    const a = (i / 12) * TAU;
    decor.trees.push({ x: SPAWN.x + Math.cos(a) * 170, y: SPAWN.y + Math.sin(a) * 170, s: 20, c: 0.2 });
  }
  return decor;
}

export class Renderer {
  constructor(canvas, minimap) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.mini = minimap;
    this.mctx = minimap.getContext('2d');
    this.decor = buildDecor();
    this.avatars = new Map();
    this.particles = [];
    this.cam = { x: 0, y: 0 };
    this.shake = 0;
    this.resize();
    window.addEventListener('resize', () => this.resize());
  }

  resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    this.dpr = dpr;
    this.w = window.innerWidth;
    this.h = window.innerHeight;
    this.canvas.width = this.w * dpr;
    this.canvas.height = this.h * dpr;
    this.canvas.style.width = this.w + 'px';
    this.canvas.style.height = this.h + 'px';
  }

  avatar(url) {
    if (!url) return null;
    let img = this.avatars.get(url);
    if (!img) {
      img = new Image();
      img.src = url;
      this.avatars.set(url, img);
    }
    return img.complete && img.naturalWidth ? img : null;
  }

  worldToScreen(x, y) {
    return { x: x - this.cam.x + this.w / 2, y: y - this.cam.y + this.h / 2 };
  }

  // ───────────── Efectos ─────────────
  addEvent(ev) {
    const P = this.particles;
    const now = performance.now() / 1000;
    switch (ev.t) {
      case 'hit':
        for (let i = 0; i < 5; i++) {
          const a = Math.random() * TAU, s = 60 + Math.random() * 120;
          P.push({ k: 'dot', x: ev.x, y: ev.y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, life: 0.35, t0: now, c: ev.c, r: 2.5 });
        }
        break;
      case 'spark':
        P.push({ k: 'ring', x: ev.x, y: ev.y, r0: 2, r1: 14, life: 0.2, t0: now, c: '#ffffff' });
        break;
      case 'boom':
        P.push({ k: 'ring', x: ev.x, y: ev.y, r0: 5, r1: ev.r * 1.6, life: 0.45, t0: now, c: ev.c, w: 6 });
        for (let i = 0; i < 16; i++) {
          const a = Math.random() * TAU, s = 80 + Math.random() * 220;
          P.push({ k: 'dot', x: ev.x, y: ev.y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, life: 0.6, t0: now, c: i % 2 ? ev.c : '#ff3bd4', r: 3.5 });
        }
        break;
      case 'slash':
        P.push({ k: 'slash', x: ev.x, y: ev.y, a: ev.a, r: ev.r, life: 0.18, t0: now, c: ev.c });
        break;
      case 'dash':
        P.push({ k: 'ring', x: ev.x, y: ev.y, r0: 10, r1: 40, life: 0.3, t0: now, c: ev.c });
        break;
      case 'shield':
        P.push({ k: 'ring', x: ev.x, y: ev.y, r0: 20, r1: ev.r, life: 0.6, t0: now, c: ev.c, w: 8 });
        break;
      case 'quake':
        P.push({ k: 'ring', x: ev.x, y: ev.y, r0: 20, r1: ev.r, life: 0.5, t0: now, c: ev.c, w: 10 });
        P.push({ k: 'cracks', x: ev.x, y: ev.y, r: ev.r * 0.8, life: 0.7, t0: now, c: ev.c, seed: Math.random() * 1000 });
        this.shake = Math.max(this.shake, 8);
        break;
      case 'chain':
        P.push({ k: 'bolt', pts: ev.pts, life: 0.3, t0: now, c: ev.c });
        break;
      case 'shift':
        for (let i = 0; i < 20; i++) {
          const a = (i / 20) * TAU;
          P.push({ k: 'dot', x: ev.x, y: ev.y, vx: Math.cos(a) * 160, vy: Math.sin(a) * 160, life: 0.5, t0: now, c: ev.c, r: 3 });
        }
        break;
      case 'free':
        P.push({ k: 'ring', x: ev.x, y: ev.y, r0: 10, r1: 260, life: 1, t0: now, c: ev.c, w: 10 });
        for (let i = 0; i < 40; i++) {
          const a = Math.random() * TAU, s = 100 + Math.random() * 300;
          P.push({ k: 'dot', x: ev.x, y: ev.y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, life: 1.1, t0: now, c: i % 3 ? ev.c : '#ffd23f', r: 4 });
        }
        P.push({ k: 'text', x: ev.x, y: ev.y - 40, text: ev.alux ? `¡${FORMS[ev.alux].name} es libre!` : '¡Alux libre!', life: 2, t0: now, c: ev.c });
        this.shake = Math.max(this.shake, 6);
        break;
    }
  }

  drawParticles(now) {
    const ctx = this.ctx;
    this.particles = this.particles.filter((p) => now - p.t0 < p.life);
    for (const p of this.particles) {
      const t = (now - p.t0) / p.life;
      ctx.globalAlpha = 1 - t;
      ctx.strokeStyle = ctx.fillStyle = p.c;
      if (p.k === 'dot') {
        const el = now - p.t0;
        ctx.beginPath();
        ctx.arc(p.x + p.vx * el * (1 - t * 0.5), p.y + p.vy * el * (1 - t * 0.5), p.r * (1 - t * 0.5), 0, TAU);
        ctx.fill();
      } else if (p.k === 'ring') {
        ctx.lineWidth = (p.w || 3) * (1 - t);
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.r0 + (p.r1 - p.r0) * t, 0, TAU);
        ctx.stroke();
      } else if (p.k === 'slash') {
        ctx.lineWidth = 10 * (1 - t);
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.r * (0.7 + t * 0.3), p.a - 0.8, p.a + 0.8);
        ctx.stroke();
      } else if (p.k === 'bolt') {
        ctx.lineWidth = 4 * (1 - t) + 1;
        ctx.shadowColor = p.c;
        ctx.shadowBlur = 12;
        ctx.beginPath();
        for (let i = 0; i < p.pts.length - 1; i++) {
          const [x1, y1] = p.pts[i], [x2, y2] = p.pts[i + 1];
          ctx.moveTo(x1, y1);
          for (let s = 1; s <= 6; s++) {
            const f = s / 6;
            const j = s === 6 ? 0 : (Math.random() - 0.5) * 22;
            ctx.lineTo(x1 + (x2 - x1) * f + j, y1 + (y2 - y1) * f + j);
          }
        }
        ctx.stroke();
        ctx.shadowBlur = 0;
      } else if (p.k === 'cracks') {
        const r = seeded(p.seed | 0);
        ctx.lineWidth = 3;
        ctx.beginPath();
        for (let i = 0; i < 8; i++) {
          let a = r() * TAU, x = p.x, y = p.y;
          ctx.moveTo(x, y);
          for (let s = 0; s < 4; s++) {
            a += (r() - 0.5) * 0.8;
            x += Math.cos(a) * p.r / 4;
            y += Math.sin(a) * p.r / 4;
            ctx.lineTo(x, y);
          }
        }
        ctx.stroke();
      } else if (p.k === 'text') {
        ctx.font = '700 22px Bungee, sans-serif';
        ctx.textAlign = 'center';
        ctx.lineWidth = 5;
        ctx.strokeStyle = '#1b1029';
        ctx.strokeText(p.text, p.x, p.y - t * 50);
        ctx.fillText(p.text, p.x, p.y - t * 50);
      }
    }
    ctx.globalAlpha = 1;
  }

  // ───────────── Mapa ─────────────
  inView(x, y, w, h, pad = 80) {
    const l = this.cam.x - this.w / 2 - pad, t = this.cam.y - this.h / 2 - pad;
    return x + w > l && x < l + this.w + pad * 2 && y + h > t && y < t + this.h + pad * 2;
  }

  drawGround(now) {
    const ctx = this.ctx;
    const tile = 100;
    for (const d of DISTRICTS) {
      if (!this.inView(d.x, d.y, d.w, d.h)) continue;
      ctx.fillStyle = d.ground;
      ctx.fillRect(d.x, d.y, d.w, d.h);
      ctx.fillStyle = d.alt;
      const x0 = Math.max(d.x, Math.floor((this.cam.x - this.w / 2) / tile) * tile);
      const y0 = Math.max(d.y, Math.floor((this.cam.y - this.h / 2) / tile) * tile);
      for (let x = x0; x < Math.min(d.x + d.w, this.cam.x + this.w / 2 + tile); x += tile) {
        for (let y = y0; y < Math.min(d.y + d.h, this.cam.y + this.h / 2 + tile); y += tile) {
          if (((x / tile) + (y / tile)) % 2 === 0) ctx.fillRect(x, y, tile, tile);
        }
      }
      if (d.id === 'torre') {
        // rejilla de neón de Obsidiana Corp.
        ctx.strokeStyle = 'rgba(176, 76, 255, 0.25)';
        ctx.lineWidth = 2;
        ctx.beginPath();
        for (let x = d.x; x <= d.x + d.w; x += 100) { ctx.moveTo(x, d.y); ctx.lineTo(x, d.y + d.h); }
        for (let y = d.y; y <= d.y + d.h; y += 100) { ctx.moveTo(d.x, y); ctx.lineTo(d.x + d.w, y); }
        ctx.stroke();
        const pulse = 0.5 + 0.5 * Math.sin(now * 2);
        ctx.strokeStyle = `rgba(255, 59, 212, ${0.25 + pulse * 0.3})`;
        ctx.lineWidth = 6;
        ctx.beginPath();
        ctx.arc(3000, 600, 300, 0, TAU);
        ctx.stroke();
      }
    }

    // Calles principales
    ctx.fillStyle = 'rgba(80, 70, 60, 0.18)';
    ctx.fillRect(0, 380, WORLD.w, 40);
    ctx.fillRect(0, 1180, WORLD.w, 40);
    ctx.fillRect(1180, 0, 40, WORLD.h);
    ctx.fillRect(2380, 0, 40, WORLD.h);
    // Paseo de Montejo: camellón
    ctx.fillStyle = '#9fbf7a';
    ctx.fillRect(1760, 20, 80, 600);
    ctx.fillRect(1760, 780, 80, 400);

    // Plaza Grande
    ctx.fillStyle = '#a9c98a';
    ctx.beginPath();
    ctx.arc(SPAWN.x, SPAWN.y, 220, 0, TAU);
    ctx.fill();
    ctx.fillStyle = '#eadcb8';
    ctx.beginPath();
    ctx.arc(SPAWN.x, SPAWN.y, 90, 0, TAU);
    ctx.fill();
    ctx.strokeStyle = '#2ec4a6';
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.arc(SPAWN.x, SPAWN.y, 60, 0, TAU);
    ctx.stroke();
    this.drawGlyph(SPAWN.x, SPAWN.y, 40, '#2ec4a6', now);

    // Agua
    for (const w of WATER) {
      const shade = 0.5 + 0.5 * Math.sin(now * 1.5);
      if (w.type === 'circle') {
        if (!this.inView(w.x - w.r, w.y - w.r, w.r * 2, w.r * 2)) continue;
        ctx.fillStyle = '#d8cfae';
        ctx.beginPath(); ctx.arc(w.x, w.y, w.r + 22, 0, TAU); ctx.fill();
        const g = ctx.createRadialGradient(w.x, w.y, 10, w.x, w.y, w.r);
        g.addColorStop(0, '#0b4f6c');
        g.addColorStop(0.7, '#139fb8');
        g.addColorStop(1, '#3fd6d0');
        ctx.fillStyle = g;
        ctx.beginPath(); ctx.arc(w.x, w.y, w.r, 0, TAU); ctx.fill();
        ctx.strokeStyle = `rgba(255,255,255,${0.15 + shade * 0.2})`;
        ctx.lineWidth = 2;
        for (let i = 1; i <= 3; i++) {
          ctx.beginPath(); ctx.arc(w.x, w.y, (w.r * i) / 3.5 + shade * 8, 0, TAU); ctx.stroke();
        }
      } else {
        if (!this.inView(w.x, w.y, w.w, w.h)) continue;
        const g = ctx.createLinearGradient(0, w.y, 0, w.y + w.h);
        g.addColorStop(0, '#3fd6d0');
        g.addColorStop(1, '#0f6d93');
        ctx.fillStyle = g;
        ctx.fillRect(w.x, w.y, w.w, w.h);
        ctx.strokeStyle = 'rgba(255,255,255,0.45)';
        ctx.lineWidth = 3;
        ctx.beginPath();
        for (let x = w.x; x < w.x + w.w; x += 20) {
          const y = w.y + 6 + Math.sin(x / 40 + now * 2) * 5;
          if (x === w.x) ctx.moveTo(x, y); else ctx.lineTo(x, y);
        }
        ctx.stroke();
        // muelle
        ctx.fillStyle = '#8b5e3c';
        ctx.fillRect(3000, w.y - 10, 50, w.h + 10);
      }
    }

    // Decoración
    for (const h of this.decor.henequen) {
      if (!this.inView(h.x, h.y, 1, 1)) continue;
      ctx.strokeStyle = '#5d8a6a';
      ctx.lineWidth = 3;
      ctx.beginPath();
      for (let i = 0; i < 8; i++) {
        const a = (i / 8) * TAU;
        ctx.moveTo(h.x, h.y);
        ctx.lineTo(h.x + Math.cos(a) * 16 * h.s, h.y + Math.sin(a) * 16 * h.s);
      }
      ctx.stroke();
    }
    for (const p of this.decor.palms) {
      if (!this.inView(p.x, p.y, 1, 1)) continue;
      ctx.fillStyle = '#7a5530';
      ctx.fillRect(p.x - 3, p.y - 4, 6, 14);
      ctx.fillStyle = '#3f9b4a';
      for (let i = 0; i < 6; i++) {
        const a = (i / 6) * TAU + Math.sin(now + p.x) * 0.1;
        ctx.beginPath();
        ctx.ellipse(p.x + Math.cos(a) * 16 * p.s, p.y - 6 + Math.sin(a) * 16 * p.s, 16 * p.s, 5 * p.s, a, 0, TAU);
        ctx.fill();
      }
    }
  }

  drawTrees() {
    const ctx = this.ctx;
    for (const t of this.decor.trees) {
      if (!this.inView(t.x, t.y, 1, 1)) continue;
      ctx.fillStyle = 'rgba(0,0,0,0.15)';
      ctx.beginPath(); ctx.arc(t.x + 6, t.y + 8, t.s, 0, TAU); ctx.fill();
      ctx.fillStyle = t.c > 0.5 ? '#2f7a3a' : '#3b8f45';
      ctx.beginPath(); ctx.arc(t.x, t.y, t.s, 0, TAU); ctx.fill();
      ctx.fillStyle = 'rgba(255,255,255,0.12)';
      ctx.beginPath(); ctx.arc(t.x - t.s * 0.3, t.y - t.s * 0.3, t.s * 0.5, 0, TAU); ctx.fill();
    }
  }

  drawGlyph(x, y, s, c, now) {
    // Glifo de jade inspirado en grecas mayas (diseño original)
    const ctx = this.ctx;
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(now * 0.2);
    ctx.strokeStyle = c;
    ctx.lineWidth = 3;
    for (let i = 0; i < 4; i++) {
      ctx.rotate(TAU / 4);
      ctx.beginPath();
      ctx.moveTo(s * 0.2, 0);
      ctx.lineTo(s * 0.6, 0);
      ctx.lineTo(s * 0.6, s * 0.4);
      ctx.lineTo(s * 0.35, s * 0.4);
      ctx.lineTo(s * 0.35, s * 0.2);
      ctx.stroke();
    }
    ctx.restore();
  }

  drawBuildings(now) {
    const ctx = this.ctx;
    for (const o of OBSTACLES) {
      if (!this.inView(o.x, o.y, o.w, o.h)) continue;
      const [main, dark] = FACADES[o.style] || FACADES.piedra;
      // sombra
      ctx.fillStyle = 'rgba(0,0,0,0.22)';
      ctx.fillRect(o.x + 10, o.y + 14, o.w, o.h);

      if (o.style === 'selva') {
        ctx.fillStyle = '#245e2d';
        ctx.fillRect(o.x, o.y, o.w, o.h);
        ctx.fillStyle = '#2f7a3a';
        for (let i = 0; i < 6; i++) {
          ctx.beginPath();
          ctx.arc(o.x + ((i * 53) % o.w), o.y + ((i * 37) % o.h), 34, 0, TAU);
          ctx.fill();
        }
        continue;
      }
      if (o.style === 'obsidiana') {
        const pulse = 0.5 + 0.5 * Math.sin(now * 3 + o.x);
        ctx.shadowColor = '#b04cff';
        ctx.shadowBlur = 20 * pulse;
        ctx.fillStyle = main;
        ctx.fillRect(o.x, o.y, o.w, o.h);
        ctx.shadowBlur = 0;
        ctx.strokeStyle = `rgba(255,59,212,${0.5 + pulse * 0.5})`;
        ctx.lineWidth = 3;
        ctx.strokeRect(o.x + 8, o.y + 8, o.w - 16, o.h - 16);
        continue;
      }
      if (o.style === 'faro') {
        for (let i = 0; i < 5; i++) {
          ctx.fillStyle = i % 2 ? dark : main;
          ctx.fillRect(o.x, o.y + (o.h / 5) * i, o.w, o.h / 5);
        }
        const a = now * 1.5;
        ctx.fillStyle = 'rgba(255, 236, 150, 0.15)';
        ctx.beginPath();
        ctx.moveTo(o.x + o.w / 2, o.y + o.h / 2);
        ctx.arc(o.x + o.w / 2, o.y + o.h / 2, 500, a - 0.2, a + 0.2);
        ctx.fill();
        continue;
      }

      // fachada colonial: techo plano + frente
      const front = Math.min(34, o.h * 0.28);
      ctx.fillStyle = dark;
      ctx.fillRect(o.x, o.y, o.w, o.h);
      ctx.fillStyle = main;
      ctx.fillRect(o.x, o.y, o.w, o.h - front);
      // pretil
      ctx.fillStyle = 'rgba(255,255,255,0.35)';
      ctx.fillRect(o.x, o.y, o.w, 6);
      // ventanas con arco en el frente
      ctx.fillStyle = 'rgba(30, 20, 40, 0.55)';
      const n = Math.max(2, Math.floor(o.w / 46));
      for (let i = 0; i < n; i++) {
        const wx = o.x + ((i + 0.5) * o.w) / n - 8;
        const wy = o.y + o.h - front + 8;
        ctx.beginPath();
        ctx.moveTo(wx, wy + front - 12);
        ctx.lineTo(wx, wy + 6);
        ctx.arc(wx + 8, wy + 6, 8, Math.PI, 0);
        ctx.lineTo(wx + 16, wy + front - 12);
        ctx.fill();
      }
      if (o.style === 'catedral') {
        ctx.fillStyle = dark;
        ctx.fillRect(o.x - 10, o.y - 20, 60, 60);
        ctx.fillRect(o.x + o.w - 50, o.y - 20, 60, 60);
        ctx.fillStyle = main;
        ctx.fillRect(o.x - 4, o.y - 14, 48, 48);
        ctx.fillRect(o.x + o.w - 44, o.y - 14, 48, 48);
      }
      if (o.name) {
        ctx.font = '600 13px Rubik, sans-serif';
        ctx.textAlign = 'center';
        ctx.fillStyle = 'rgba(30,20,40,0.75)';
        ctx.fillText(o.name.toUpperCase(), o.x + o.w / 2, o.y + (o.h - front) / 2 + 5);
      }
    }

    // La torre de Obsidiana Corp.
    if (this.inView(2900, 20, 200, 160)) {
      const pulse = 0.5 + 0.5 * Math.sin(now * 2);
      ctx.fillStyle = '#0e0a15';
      ctx.beginPath();
      ctx.moveTo(2920, 150); ctx.lineTo(3000, 10); ctx.lineTo(3080, 150);
      ctx.fill();
      ctx.strokeStyle = `rgba(255,59,212,${0.5 + pulse * 0.5})`;
      ctx.lineWidth = 3;
      ctx.stroke();
      ctx.font = '700 14px Bungee, sans-serif';
      ctx.fillStyle = '#ff3bd4';
      ctx.textAlign = 'center';
      ctx.fillText('OBSIDIANA CORP.', 3000, 175);
    }
  }

  // ───────────── Entidades ─────────────
  drawCube(c, now) {
    const ctx = this.ctx;
    if (!c.on) {
      ctx.strokeStyle = 'rgba(255,255,255,0.25)';
      ctx.setLineDash([6, 6]);
      ctx.lineWidth = 2;
      ctx.beginPath(); ctx.arc(c.x, c.y, CUBE_R + 6, 0, TAU); ctx.stroke();
      ctx.setLineDash([]);
      return;
    }
    const col = c.al ? FORMS[c.al].color : '#ffffff';
    ctx.save();
    ctx.translate(c.x, c.y);
    // pilar de energía
    ctx.fillStyle = 'rgba(255,59,212,0.12)';
    ctx.beginPath(); ctx.arc(0, 0, CUBE_R + 26 + Math.sin(now * 4) * 4, 0, TAU); ctx.fill();
    ctx.rotate(now * 0.8);
    ctx.shadowColor = '#ff3bd4';
    ctx.shadowBlur = 18;
    ctx.fillStyle = '#2b1640';
    ctx.strokeStyle = '#ff3bd4';
    ctx.lineWidth = 3;
    ctx.beginPath(); ctx.rect(-CUBE_R, -CUBE_R, CUBE_R * 2, CUBE_R * 2); ctx.fill(); ctx.stroke();
    ctx.shadowBlur = 0;
    ctx.rotate(-now * 1.6);
    ctx.fillStyle = col;
    ctx.globalAlpha = 0.6 + 0.4 * Math.sin(now * 5);
    ctx.beginPath(); ctx.arc(0, 0, 11, 0, TAU); ctx.fill();
    ctx.globalAlpha = 1;
    ctx.restore();
    // barra de vida del cubo
    const pct = Math.max(0, c.hp / 600);
    ctx.strokeStyle = 'rgba(0,0,0,0.4)';
    ctx.lineWidth = 5;
    ctx.beginPath(); ctx.arc(c.x, c.y, CUBE_R + 14, 0, TAU); ctx.stroke();
    ctx.strokeStyle = '#ff3bd4';
    ctx.beginPath(); ctx.arc(c.x, c.y, CUBE_R + 14, -Math.PI / 2, -Math.PI / 2 + TAU * pct); ctx.stroke();
    if (c.al) {
      ctx.font = '600 12px Rubik, sans-serif';
      ctx.textAlign = 'center';
      ctx.fillStyle = '#1b1029';
      ctx.fillText(`${FORMS[c.al].name} atrapado`, c.x, c.y + CUBE_R + 34);
    }
  }

  drawEnemy(e, now) {
    const ctx = this.ctx;
    const def = ENEMIES[e.k];
    const r = def.r;
    ctx.save();
    ctx.translate(e.x, e.y);
    ctx.fillStyle = 'rgba(0,0,0,0.25)';
    ctx.beginPath(); ctx.ellipse(4, r * 0.7, r, r * 0.45, 0, 0, TAU); ctx.fill();
    if (e.st) ctx.globalAlpha = 0.7;

    if (e.k === 'dron') {
      ctx.translate(0, Math.sin(now * 6 + e.id) * 3 - 6);
      ctx.strokeStyle = 'rgba(255,59,212,0.6)';
      ctx.lineWidth = 2;
      ctx.beginPath(); ctx.ellipse(0, 0, r + 8, (r + 8) * 0.4, now * 10, 0, TAU); ctx.stroke();
      ctx.fillStyle = '#1e1530';
      ctx.beginPath(); ctx.moveTo(0, -r); ctx.lineTo(r, 0); ctx.lineTo(0, r); ctx.lineTo(-r, 0); ctx.closePath(); ctx.fill();
      ctx.fillStyle = '#ff3bd4';
      ctx.beginPath(); ctx.arc(0, 0, 5, 0, TAU); ctx.fill();
    } else if (e.k === 'centinela') {
      ctx.fillStyle = '#251a38';
      ctx.beginPath();
      for (let i = 0; i < 6; i++) {
        const a = (i / 6) * TAU;
        ctx.lineTo(Math.cos(a) * r, Math.sin(a) * r);
      }
      ctx.closePath(); ctx.fill();
      ctx.strokeStyle = '#3fd6d0';
      ctx.lineWidth = 2;
      ctx.stroke();
      ctx.fillStyle = '#3fd6d0';
      ctx.beginPath(); ctx.arc(0, 0, 6 + Math.sin(now * 8) * 1.5, 0, TAU); ctx.fill();
    } else if (e.k === 'bruto') {
      ctx.fillStyle = '#140f1d';
      ctx.beginPath();
      for (let i = 0; i < 10; i++) {
        const a = (i / 10) * TAU;
        const rr = i % 2 ? r : r * 1.2;
        ctx.lineTo(Math.cos(a) * rr, Math.sin(a) * rr);
      }
      ctx.closePath(); ctx.fill();
      ctx.strokeStyle = '#b04cff';
      ctx.lineWidth = 3;
      ctx.stroke();
      ctx.fillStyle = '#ff3b5c';
      ctx.fillRect(-10, -6, 6, 6);
      ctx.fillRect(4, -6, 6, 6);
    } else if (e.k === 'okom') {
      const pulse = 0.5 + 0.5 * Math.sin(now * 3);
      ctx.shadowColor = '#b04cff';
      ctx.shadowBlur = 30;
      ctx.fillStyle = '#0e0a15';
      ctx.beginPath();
      for (let i = 0; i < 14; i++) {
        const a = (i / 14) * TAU + now * 0.1;
        const rr = i % 2 ? r : r * 1.3;
        ctx.lineTo(Math.cos(a) * rr, Math.sin(a) * rr);
      }
      ctx.closePath(); ctx.fill();
      ctx.shadowBlur = 0;
      ctx.strokeStyle = '#ff3bd4';
      ctx.lineWidth = 4;
      ctx.stroke();
      // fragmentos orbitando
      for (let i = 0; i < 6; i++) {
        const a = (i / 6) * TAU - now * 0.8;
        ctx.save();
        ctx.translate(Math.cos(a) * (r + 30), Math.sin(a) * (r + 30));
        ctx.rotate(a);
        ctx.fillStyle = '#2b1640';
        ctx.beginPath(); ctx.moveTo(0, -12); ctx.lineTo(7, 0); ctx.lineTo(0, 12); ctx.lineTo(-7, 0); ctx.fill();
        ctx.restore();
      }
      const g = ctx.createRadialGradient(0, 0, 4, 0, 0, 30);
      g.addColorStop(0, '#ffffff');
      g.addColorStop(0.4, '#ff3bd4');
      g.addColorStop(1, 'rgba(176,76,255,0)');
      ctx.fillStyle = g;
      ctx.beginPath(); ctx.arc(0, 0, 26 + pulse * 6, 0, TAU); ctx.fill();
    }
    ctx.restore();
    if (e.st) {
      ctx.fillStyle = '#ffd23f';
      for (let i = 0; i < 3; i++) {
        const a = now * 4 + (i / 3) * TAU;
        ctx.beginPath(); ctx.arc(e.x + Math.cos(a) * 14, e.y - r - 12 + Math.sin(a) * 4, 3, 0, TAU); ctx.fill();
      }
    }
    if (e.k !== 'okom' && e.hp < e.mhp) {
      const w = r * 2;
      ctx.fillStyle = 'rgba(0,0,0,0.5)';
      ctx.fillRect(e.x - w / 2, e.y - r - 10, w, 4);
      ctx.fillStyle = '#ff3bd4';
      ctx.fillRect(e.x - w / 2, e.y - r - 10, w * (e.hp / e.mhp), 4);
    }
  }

  drawForm(form, x, y, ang, now, moving) {
    const ctx = this.ctx;
    const f = FORMS[form];
    const r = f.r;
    ctx.save();
    ctx.translate(x, y);
    ctx.fillStyle = 'rgba(0,0,0,0.22)';
    ctx.beginPath(); ctx.ellipse(3, r * 0.75, r, r * 0.45, 0, 0, TAU); ctx.fill();

    if (form === 'guardian') {
      ctx.rotate(ang);
      ctx.fillStyle = '#16806c';
      ctx.beginPath(); ctx.moveTo(-r - 6, -8); ctx.lineTo(-r - 14 - Math.sin(now * 10) * 3, 0); ctx.lineTo(-r - 6, 8); ctx.fill();
      ctx.fillStyle = f.color;
      ctx.beginPath(); ctx.arc(0, 0, r, 0, TAU); ctx.fill();
      ctx.strokeStyle = '#0d4f43'; ctx.lineWidth = 3; ctx.stroke();
      ctx.fillStyle = '#1b1029';
      ctx.beginPath(); ctx.arc(-3, 0, r * 0.62, 0, TAU); ctx.fill();
      ctx.fillStyle = '#ffd23f';
      ctx.beginPath(); ctx.arc(r * 0.45, 0, 4, 0, TAU); ctx.fill();
      ctx.fillStyle = '#e4007c';
      ctx.fillRect(-r * 0.55, -r * 0.65, 5, r * 1.3);
    } else if (form === 'balam') {
      ctx.rotate(ang);
      // llamas
      for (let i = 0; i < 4; i++) {
        const fl = Math.sin(now * 14 + i) * 4;
        ctx.fillStyle = i % 2 ? '#ffd23f' : '#ff3b1a';
        ctx.beginPath(); ctx.arc(-r - 4 - i * 5 - (moving ? 4 : 0), fl * 0.5, 7 - i, 0, TAU); ctx.fill();
      }
      ctx.fillStyle = f.color;
      ctx.beginPath(); ctx.ellipse(0, 0, r * 1.15, r * 0.9, 0, 0, TAU); ctx.fill();
      ctx.fillStyle = '#5a2a0a';
      for (const [sx, sy] of [[-6, -7], [-8, 6], [2, -9], [3, 8], [-14, 0]]) {
        ctx.beginPath(); ctx.arc(sx, sy, 3, 0, TAU); ctx.fill();
      }
      ctx.fillStyle = '#ff9a3d';
      ctx.beginPath(); ctx.arc(r * 0.8, 0, r * 0.55, 0, TAU); ctx.fill();
      ctx.fillStyle = f.color;
      ctx.beginPath(); ctx.moveTo(r * 0.6, -r * 0.5); ctx.lineTo(r * 0.75, -r * 0.95); ctx.lineTo(r * 1.0, -r * 0.45); ctx.fill();
      ctx.beginPath(); ctx.moveTo(r * 0.6, r * 0.5); ctx.lineTo(r * 0.75, r * 0.95); ctx.lineTo(r * 1.0, r * 0.45); ctx.fill();
      ctx.fillStyle = '#ffd23f';
      ctx.fillRect(r * 1.0, -5, 4, 3); ctx.fillRect(r * 1.0, 2, 4, 3);
    } else if (form === 'aak') {
      ctx.rotate(ang);
      ctx.fillStyle = '#0f7c96';
      const fl = Math.sin(now * (moving ? 10 : 2)) * 4;
      for (const [fx, fy, s] of [[r * 0.5, -r, 1], [r * 0.5, r, -1], [-r * 0.6, -r * 0.9, 1], [-r * 0.6, r * 0.9, -1]]) {
        ctx.beginPath(); ctx.ellipse(fx, fy + fl * s * 0.3, 9, 5, s * 0.6, 0, TAU); ctx.fill();
      }
      ctx.fillStyle = '#7ee0c9';
      ctx.beginPath(); ctx.arc(r + 4, 0, 8, 0, TAU); ctx.fill();
      ctx.fillStyle = f.color;
      ctx.beginPath(); ctx.arc(0, 0, r, 0, TAU); ctx.fill();
      ctx.strokeStyle = '#0b5368'; ctx.lineWidth = 3; ctx.stroke();
      ctx.strokeStyle = '#ccf6ff'; ctx.lineWidth = 2;
      ctx.beginPath();
      for (let i = 0; i < 6; i++) {
        const a = (i / 6) * TAU;
        ctx.lineTo(Math.cos(a) * r * 0.5, Math.sin(a) * r * 0.5);
      }
      ctx.closePath(); ctx.stroke();
      for (let i = 0; i < 6; i++) {
        const a = (i / 6) * TAU;
        ctx.beginPath(); ctx.moveTo(Math.cos(a) * r * 0.5, Math.sin(a) * r * 0.5); ctx.lineTo(Math.cos(a) * r, Math.sin(a) * r); ctx.stroke();
      }
    } else if (form === 'tzunun') {
      ctx.rotate(ang);
      const flap = Math.sin(now * 40) * 0.5 + 0.5;
      ctx.fillStyle = 'rgba(255, 240, 160, 0.55)';
      ctx.beginPath(); ctx.ellipse(-2, -r - 2, 7, r * (0.6 + flap * 0.7), -0.3, 0, TAU); ctx.fill();
      ctx.beginPath(); ctx.ellipse(-2, r + 2, 7, r * (0.6 + flap * 0.7), 0.3, 0, TAU); ctx.fill();
      ctx.fillStyle = '#2ec4a6';
      ctx.beginPath(); ctx.moveTo(-r - 10, 0); ctx.lineTo(-r, -6); ctx.lineTo(-r, 6); ctx.fill();
      ctx.fillStyle = f.color;
      ctx.beginPath(); ctx.ellipse(0, 0, r, r * 0.75, 0, 0, TAU); ctx.fill();
      ctx.fillStyle = '#e4007c';
      ctx.beginPath(); ctx.arc(r * 0.35, 0, r * 0.45, 0, TAU); ctx.fill();
      ctx.strokeStyle = '#1b1029'; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.moveTo(r * 0.7, 0); ctx.lineTo(r + 14, 0); ctx.stroke();
      ctx.strokeStyle = 'rgba(255,255,255,0.8)'; ctx.lineWidth = 1.5;
      ctx.beginPath(); ctx.moveTo(-4, -4); ctx.lineTo(0, 0); ctx.lineTo(-4, 4); ctx.stroke();
    } else if (form === 'ceiba') {
      ctx.strokeStyle = '#6b4423';
      ctx.lineWidth = 4;
      for (let i = 0; i < 6; i++) {
        const a = (i / 6) * TAU + 0.3;
        ctx.beginPath(); ctx.moveTo(Math.cos(a) * r * 0.8, Math.sin(a) * r * 0.8);
        ctx.quadraticCurveTo(Math.cos(a + 0.3) * r * 1.3, Math.sin(a + 0.3) * r * 1.3, Math.cos(a) * r * 1.45, Math.sin(a) * r * 1.45);
        ctx.stroke();
      }
      ctx.fillStyle = '#8a5a32';
      ctx.beginPath(); ctx.arc(0, 0, r, 0, TAU); ctx.fill();
      ctx.strokeStyle = '#5a3a1c'; ctx.lineWidth = 3; ctx.stroke();
      ctx.fillStyle = f.color;
      for (let i = 0; i < 7; i++) {
        const a = (i / 7) * TAU + Math.sin(now * 2) * 0.05;
        ctx.beginPath(); ctx.arc(Math.cos(a) * r * 0.55, Math.sin(a) * r * 0.55, r * 0.38, 0, TAU); ctx.fill();
      }
      ctx.fillStyle = '#ffd23f';
      ctx.beginPath(); ctx.arc(Math.cos(ang) * r * 0.5 - 5, Math.sin(ang) * r * 0.5, 3, 0, TAU); ctx.fill();
      ctx.beginPath(); ctx.arc(Math.cos(ang) * r * 0.5 + 5, Math.sin(ang) * r * 0.5, 3, 0, TAU); ctx.fill();
    }
    ctx.restore();
  }

  drawPlayer(p, now, isMe) {
    const ctx = this.ctx;
    const f = FORMS[p.f];
    if (p.d) {
      ctx.globalAlpha = 0.35;
      ctx.strokeStyle = '#ffffff';
      ctx.lineWidth = 2;
      ctx.setLineDash([4, 4]);
      ctx.beginPath(); ctx.arc(p.x, p.y, f.r, 0, TAU); ctx.stroke();
      ctx.setLineDash([]);
      ctx.globalAlpha = 1;
      return;
    }
    if (isMe) {
      ctx.strokeStyle = 'rgba(255,255,255,0.5)';
      ctx.lineWidth = 2;
      ctx.beginPath(); ctx.arc(p.x, p.y, f.r + 10, 0, TAU); ctx.stroke();
    }
    this.drawForm(p.f, p.x, p.y, p.ang, now, p.moving);
    if (p.inv) {
      ctx.strokeStyle = `rgba(126, 224, 201, ${0.5 + 0.5 * Math.sin(now * 20)})`;
      ctx.lineWidth = 3;
      ctx.beginPath(); ctx.arc(p.x, p.y, f.r + 7, 0, TAU); ctx.stroke();
    }
    // etiqueta
    const top = p.y - f.r - 30;
    const img = this.avatar(p.a);
    ctx.font = '600 13px Rubik, sans-serif';
    const label = `${p.n} · ${p.l}`;
    const tw = ctx.measureText(label).width;
    const total = tw + 24;
    const lx = p.x - total / 2;
    ctx.fillStyle = 'rgba(27, 16, 41, 0.75)';
    roundRect(ctx, lx - 4, top - 13, total + 8, 20, 10);
    ctx.fill();
    if (img) {
      ctx.save();
      ctx.beginPath(); ctx.arc(lx + 8, top - 3, 8, 0, TAU); ctx.clip();
      ctx.drawImage(img, lx, top - 11, 16, 16);
      ctx.restore();
    } else {
      ctx.fillStyle = f.color;
      ctx.beginPath(); ctx.arc(lx + 8, top - 3, 7, 0, TAU); ctx.fill();
    }
    ctx.fillStyle = isMe ? '#ffd23f' : '#ffffff';
    ctx.textAlign = 'left';
    ctx.fillText(label, lx + 22, top + 1);
    // vida
    const w = 46;
    ctx.fillStyle = 'rgba(0,0,0,0.45)';
    ctx.fillRect(p.x - w / 2, top + 10, w, 5);
    ctx.fillStyle = p.hp / p.mhp > 0.35 ? '#2ec4a6' : '#ff3b5c';
    ctx.fillRect(p.x - w / 2, top + 10, w * Math.max(0, p.hp / p.mhp), 5);
  }

  drawProjectile(b, now) {
    const ctx = this.ctx;
    const styles = {
      jade: ['#7ef0d0', 6],
      agua: ['#5fd8ff', 8],
      rayo: ['#fff27a', 4],
      obs: ['#ff3bd4', 7],
      obsBig: ['#b04cff', 9],
    };
    const [c, r] = styles[b.k] || ['#ffffff', 5];
    ctx.shadowColor = c;
    ctx.shadowBlur = 12;
    ctx.fillStyle = c;
    ctx.beginPath(); ctx.arc(b.x, b.y, r, 0, TAU); ctx.fill();
    ctx.fillStyle = '#ffffff';
    ctx.beginPath(); ctx.arc(b.x, b.y, r * 0.45, 0, TAU); ctx.fill();
    ctx.shadowBlur = 0;
  }

  // ───────────── Cuadro completo ─────────────
  frame(state, camX, camY, myId, now) {
    const ctx = this.ctx;
    this.shake *= 0.88;
    this.cam.x = camX + (Math.random() - 0.5) * this.shake;
    this.cam.y = camY + (Math.random() - 0.5) * this.shake;
    ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    ctx.fillStyle = '#1b1029';
    ctx.fillRect(0, 0, this.w, this.h);
    ctx.translate(Math.round(this.w / 2 - this.cam.x), Math.round(this.h / 2 - this.cam.y));

    this.drawGround(now);
    for (const c of state.cubes) this.drawCube(c, now);
    this.drawBuildings(now);
    for (const e of state.enemies) if (this.inView(e.x, e.y, 1, 1, 120)) this.drawEnemy(e, now);
    const players = [...state.players].sort((a, b) => (a.id === myId) - (b.id === myId));
    for (const p of players) if (this.inView(p.x, p.y, 1, 1)) this.drawPlayer(p, now, p.id === myId);
    for (const b of state.bullets) if (this.inView(b.x, b.y, 1, 1)) this.drawProjectile(b, now);
    this.drawTrees();
    this.drawParticles(now);
  }

  minimap(state, myId) {
    const ctx = this.mctx;
    const W = this.mini.width, H = this.mini.height;
    const sx = W / WORLD.w, sy = H / WORLD.h;
    ctx.clearRect(0, 0, W, H);
    for (const d of DISTRICTS) {
      ctx.fillStyle = d.ground;
      ctx.fillRect(d.x * sx, d.y * sy, d.w * sx, d.h * sy);
    }
    ctx.fillStyle = '#139fb8';
    for (const w of WATER) {
      if (w.type === 'circle') { ctx.beginPath(); ctx.arc(w.x * sx, w.y * sy, w.r * sx, 0, TAU); ctx.fill(); }
      else ctx.fillRect(w.x * sx, w.y * sy, w.w * sx, w.h * sy);
    }
    ctx.fillStyle = 'rgba(27,16,41,0.55)';
    for (const o of OBSTACLES) ctx.fillRect(o.x * sx, o.y * sy, o.w * sx, o.h * sy);
    for (const c of state.cubes) {
      if (!c.on) continue;
      ctx.fillStyle = '#ff3bd4';
      ctx.fillRect(c.x * sx - 3, c.y * sy - 3, 6, 6);
    }
    for (const e of state.enemies) {
      if (e.k === 'okom') {
        ctx.fillStyle = '#ff3b5c';
        ctx.beginPath(); ctx.arc(e.x * sx, e.y * sy, 6, 0, TAU); ctx.fill();
      }
    }
    for (const p of state.players) {
      ctx.fillStyle = p.id === myId ? '#ffffff' : FORMS[p.f].color;
      ctx.beginPath(); ctx.arc(p.x * sx, p.y * sy, p.id === myId ? 4 : 3, 0, TAU); ctx.fill();
      if (p.id === myId) {
        ctx.strokeStyle = '#1b1029'; ctx.lineWidth = 1.5; ctx.stroke();
      }
    }
    ctx.strokeStyle = 'rgba(255,255,255,0.5)';
    ctx.lineWidth = 1;
    ctx.strokeRect(
      (this.cam.x - this.w / 2) * sx, (this.cam.y - this.h / 2) * sy, this.w * sx, this.h * sy,
    );
  }
}

function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}
