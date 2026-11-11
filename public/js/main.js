import { FORMS, FORM_ORDER, districtAt } from '/shared/config.js';
import { moveEntity } from '/shared/physics.js';
import { Renderer } from './render.js';
import { PROLOGUE, STORY_EVENTS, HELP } from './story.js';

const $ = (sel) => document.querySelector(sel);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const ERRORS = {
  cancelado: 'Cancelaste el inicio de sesión con Discord.',
  estado_invalido: 'La sesión expiró. Intenta de nuevo.',
  discord: 'Discord no respondió. Intenta de nuevo en un momento.',
  discord_no_configurado: 'El login con Discord aún no está configurado en este servidor.',
  invitados_desactivados: 'El modo invitado está desactivado.',
  sesion: 'No se pudo crear la sesión.',
};

// ───────────────────────── Pantalla de inicio ─────────────────────────

async function boot() {
  const params = new URLSearchParams(location.search);
  if (params.get('error')) {
    $('#login-error').textContent = ERRORS[params.get('error')] || 'Algo salió mal.';
    history.replaceState(null, '', '/');
  }

  const [config, me] = await Promise.all([
    fetch('/api/config').then((r) => r.json()),
    fetch('/api/me').then((r) => (r.ok ? r.json() : null)),
  ]);

  renderAluxCards();
  loadLeaderboard();

  if (!config.discordEnabled) $('#btn-discord').classList.add('disabled');
  if (config.allowGuest) $('#btn-guest').hidden = false;

  if (me && me.user) {
    $('#login').hidden = true;
    startGame(me);
  } else {
    $('#login').hidden = false;
  }
}

function renderAluxCards() {
  $('#alux-cards').innerHTML = FORM_ORDER.map((k) => {
    const f = FORMS[k];
    return `<div class="alux-card" style="--c:${f.color}">
      <div class="alux-dot"></div>
      <div><b>${esc(f.name)}</b><span>${esc(f.title)}</span><p>${esc(f.desc)}</p></div>
    </div>`;
  }).join('');
}

async function loadLeaderboard() {
  try {
    const rows = await fetch('/api/leaderboard').then((r) => r.json());
    const html = rows.length
      ? rows.map((r, i) => `<li><span class="pos">${i + 1}</span>${r.avatar ? `<img src="${esc(r.avatar)}" alt="">` : '<i></i>'}<b>${esc(r.name)}</b><em>${r.xp} XP</em></li>`).join('')
      : '<li class="empty">Aún no hay guardianes. ¡Sé el primero!</li>';
    document.querySelectorAll('.leaderboard').forEach((el) => { el.innerHTML = html; });
  } catch { /* sin conexión */ }
}

// ───────────────────────── Juego ─────────────────────────

function startGame(me) {
  $('#game').hidden = false;
  const renderer = new Renderer($('#canvas'), $('#minimap'));
  const socket = io({ transports: ['websocket', 'polling'] });

  const user = me.user;
  $('#hud-name').textContent = user.name;
  if (user.avatar) $('#hud-avatar').src = user.avatar;
  else $('#hud-avatar').classList.add('no-avatar');

  let myId = null;
  let priv = null;
  const snaps = [];
  let offset = null;
  const local = { x: 0, y: 0, ready: false };
  let lastFrame = performance.now();
  let chatting = false;
  let currentDistrict = null;

  // ── Red ──
  socket.on('welcome', (w) => {
    myId = w.id;
    if (!w.seenPrologue) showPrologue();
  });
  socket.on('auth_required', () => location.reload());
  socket.on('kicked', (msg) => {
    alert(msg);
  });
  socket.on('disconnect', () => {
    $('#conn').hidden = false;
  });
  socket.on('connect', () => {
    $('#conn').hidden = true;
  });

  socket.on('snap', (s) => {
    const now = performance.now();
    const off = s.t - now;
    offset = offset === null ? off : offset * 0.9 + off * 0.1;
    s.pm = new Map(s.p.map((p) => [p.id, p]));
    s.em = new Map(s.e.map((e) => [e.id, e]));
    s.bm = new Map(s.b.map((b) => [b.id, b]));
    snaps.push(s);
    while (snaps.length > 30) snaps.shift();
    for (const ev of s.ev) {
      if (ev.t === 'msg') toast(ev.text, ev.kind);
      else renderer.addEvent(ev);
    }
    const mine = s.pm.get(myId);
    if (mine && !local.ready) {
      local.x = mine.x; local.y = mine.y; local.ready = true;
    }
  });

  socket.on('me', (m) => {
    priv = m;
    updateHud();
  });
  socket.on('notice', (n) => toast(n.text, n.kind, n.big));
  socket.on('story', (key) => {
    if (STORY_EVENTS[key]) storyLine(STORY_EVENTS[key]);
  });
  socket.on('chat', (m) => addChat(m));

  // ── Entrada ──
  const keys = new Set();
  const mouse = { x: 0, y: 0, left: false, right: false };
  let lastSent = '';
  let lastSentAt = 0;

  const canvas = $('#canvas');
  canvas.addEventListener('contextmenu', (e) => e.preventDefault());
  canvas.addEventListener('mousemove', (e) => { mouse.x = e.clientX; mouse.y = e.clientY; });
  canvas.addEventListener('mousedown', (e) => {
    if (e.button === 0) mouse.left = true;
    if (e.button === 2) mouse.right = true;
  });
  window.addEventListener('mouseup', (e) => {
    if (e.button === 0) mouse.left = false;
    if (e.button === 2) mouse.right = false;
  });
  window.addEventListener('blur', () => { keys.clear(); mouse.left = mouse.right = false; });

  window.addEventListener('keydown', (e) => {
    if (chatting) {
      if (e.key === 'Escape') closeChat();
      return;
    }
    if (!$('#prologue').hidden) {
      if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); nextPrologue(); }
      return;
    }
    if (e.key === 'Enter') { e.preventDefault(); openChat(); return; }
    const k = e.key.toLowerCase();
    if (k >= '1' && k <= '5') {
      const form = FORM_ORDER[Number(k) - 1];
      if (priv && !priv.unlocked.includes(form)) {
        toast(`${FORMS[form].name} sigue atrapado en un cubo de contención.`, 'dim');
      } else socket.emit('form', form);
    }
    if (k === 'h') $('#help').hidden = !$('#help').hidden;
    if (k === 'm') $('#minimap-wrap').classList.toggle('hidden');
    if (k === ' ' || k.startsWith('arrow')) e.preventDefault();
    keys.add(k);
  });
  window.addEventListener('keyup', (e) => keys.delete(e.key.toLowerCase()));

  function inputState(aim) {
    return {
      up: keys.has('w') || keys.has('arrowup'),
      down: keys.has('s') || keys.has('arrowdown'),
      left: keys.has('a') || keys.has('arrowleft'),
      right: keys.has('d') || keys.has('arrowright'),
      fire: mouse.left,
      special: mouse.right || keys.has(' ') || keys.has('shift'),
      aim: +aim.toFixed(2),
    };
  }

  // ── Chat ──
  const chatInput = $('#chat-input');
  function openChat() {
    chatting = true;
    keys.clear();
    $('#chat').classList.add('open');
    chatInput.focus();
  }
  function closeChat() {
    chatting = false;
    $('#chat').classList.remove('open');
    chatInput.blur();
  }
  chatInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      const text = chatInput.value.trim();
      if (text) socket.emit('chat', text);
      chatInput.value = '';
      closeChat();
    }
  });
  function addChat(m) {
    const li = document.createElement('li');
    const name = document.createElement('b');
    name.textContent = m.n + ': ';
    name.style.color = m.c;
    li.append(name, document.createTextNode(m.text));
    const list = $('#chat-log');
    list.append(li);
    while (list.children.length > 40) list.firstChild.remove();
    list.scrollTop = list.scrollHeight;
  }

  // ── Prólogo ──
  let prologueIdx = 0;
  function showPrologue() {
    prologueIdx = 0;
    $('#prologue').hidden = false;
    renderPrologue();
  }
  function renderPrologue() {
    const page = PROLOGUE[prologueIdx];
    $('#prologue-title').textContent = page.title;
    $('#prologue-text').textContent = page.text;
    $('#prologue-step').textContent = `${prologueIdx + 1} / ${PROLOGUE.length}`;
    $('#prologue-next').textContent = prologueIdx === PROLOGUE.length - 1 ? '¡A jugar!' : 'Siguiente';
  }
  function nextPrologue() {
    prologueIdx++;
    if (prologueIdx >= PROLOGUE.length) {
      $('#prologue').hidden = true;
      fetch('/api/prologue-seen', { method: 'POST' });
      toast('Libera a los aluxes de los cubos rosas. Pulsa H para ver los controles.', 'good', true);
      return;
    }
    renderPrologue();
  }
  $('#prologue-next').addEventListener('click', nextPrologue);
  $('#prologue-skip').addEventListener('click', () => { prologueIdx = PROLOGUE.length; nextPrologue(); });
  $('#btn-story').addEventListener('click', showPrologue);

  // ── Ayuda / salir ──
  $('#help-list').innerHTML = HELP.map(([k, v]) => `<li><kbd>${esc(k)}</kbd><span>${esc(v)}</span></li>`).join('');
  $('#btn-help').addEventListener('click', () => { $('#help').hidden = !$('#help').hidden; });
  $('#help-close').addEventListener('click', () => { $('#help').hidden = true; });
  $('#btn-logout').addEventListener('click', async () => {
    await fetch('/auth/logout', { method: 'POST' });
    location.href = '/';
  });

  // ── Barra de formas ──
  const bar = $('#forms');
  bar.innerHTML = FORM_ORDER.map((k, i) => {
    const f = FORMS[k];
    return `<button class="form-slot locked" data-form="${k}" style="--c:${f.color}" title="${esc(f.title)}">
      <span class="key">${i + 1}</span><span class="orb"></span><span class="fname">${esc(f.name)}</span><span class="cd"></span>
    </button>`;
  }).join('');
  bar.addEventListener('click', (e) => {
    const btn = e.target.closest('.form-slot');
    if (btn && !btn.classList.contains('locked')) socket.emit('form', btn.dataset.form);
  });

  function updateHud() {
    if (!priv) return;
    $('#hud-level').textContent = `Nv. ${priv.lvl}`;
    const span = Math.max(1, priv.nextXp - priv.lvlXp);
    $('#xp-fill').style.width = `${Math.min(100, ((priv.xp - priv.lvlXp) / span) * 100)}%`;
    $('#xp-text').textContent = `${priv.xp} XP`;
    $('#online').textContent = `${priv.online} en línea`;
    $('#stats').textContent = `${priv.kills} drones · ${priv.freed} aluxes liberados · ${priv.bossKills} titanes`;
    for (const btn of bar.children) {
      btn.classList.toggle('locked', !priv.unlocked.includes(btn.dataset.form));
    }
    $('#respawn').hidden = !priv.respawn;
    $('#respawn-t').textContent = Math.ceil(priv.respawn);
  }

  // ── Interpolación ──
  const lerp = (a, b, t) => a + (b - a) * t;
  function lerpAngle(a, b, t) {
    let d = b - a;
    while (d > Math.PI) d -= Math.PI * 2;
    while (d < -Math.PI) d += Math.PI * 2;
    return a + d * t;
  }

  function interpolated(now) {
    if (!snaps.length) return null;
    const renderT = now + offset - 1000 / 15 * 1.6;
    let a = snaps[0], b = snaps[snaps.length - 1];
    for (let i = snaps.length - 1; i > 0; i--) {
      if (snaps[i - 1].t <= renderT) { a = snaps[i - 1]; b = snaps[i]; break; }
    }
    const t = b.t === a.t ? 1 : Math.max(0, Math.min(1, (renderT - a.t) / (b.t - a.t)));
    const players = b.p.map((p) => {
      const pa = a.pm.get(p.id);
      if (!pa) return { ...p, moving: false };
      return { ...p, x: lerp(pa.x, p.x, t), y: lerp(pa.y, p.y, t), ang: lerpAngle(pa.ang, p.ang, t), moving: Math.hypot(p.x - pa.x, p.y - pa.y) > 1 };
    });
    const enemies = b.e.map((e) => {
      const ea = a.em.get(e.id);
      return ea ? { ...e, x: lerp(ea.x, e.x, t), y: lerp(ea.y, e.y, t) } : e;
    });
    const bullets = b.b.map((x) => {
      const xa = a.bm.get(x.id);
      return xa ? { ...x, x: lerp(xa.x, x.x, t), y: lerp(xa.y, x.y, t) } : x;
    });
    return { players, enemies, bullets, cubes: b.c, latest: snaps[snaps.length - 1] };
  }

  // ── Bucle de render ──
  function loop() {
    const now = performance.now();
    const dt = Math.min(0.05, (now - lastFrame) / 1000);
    lastFrame = now;
    const state = interpolated(now);
    if (state && myId) {
      const serverMe = state.latest.pm.get(myId);
      const view = state.players.find((p) => p.id === myId);
      let aim = 0;
      if (serverMe && view) {
        const f = FORMS[serverMe.f];
        const inp = inputState(0);
        const dx = (inp.right ? 1 : 0) - (inp.left ? 1 : 0);
        const dy = (inp.down ? 1 : 0) - (inp.up ? 1 : 0);
        const moving = dx || dy;
        // Predicción local de movimiento + corrección suave hacia el servidor
        if (serverMe.d || serverMe.dash) {
          local.x = lerp(local.x, serverMe.x, Math.min(1, dt * 18));
          local.y = lerp(local.y, serverMe.y, Math.min(1, dt * 18));
        } else {
          if (!chatting && $('#prologue').hidden) moveEntity(local, dx, dy, f.speed, dt, f.r, !!f.swim);
          const ex = serverMe.x - local.x, ey = serverMe.y - local.y;
          const err = Math.hypot(ex, ey);
          if (err > 140) { local.x = serverMe.x; local.y = serverMe.y; }
          else {
            const k = Math.min(1, dt * (moving ? 2.5 : 10));
            local.x += ex * k; local.y += ey * k;
          }
        }
        view.x = local.x; view.y = local.y;
        aim = Math.atan2(mouse.y - renderer.h / 2, mouse.x - renderer.w / 2);
        view.ang = aim;
        view.moving = !!moving;
        // Enviar entrada
        const inp2 = (chatting || !$('#prologue').hidden)
          ? { up: false, down: false, left: false, right: false, fire: false, special: false, aim: +aim.toFixed(2) }
          : inputState(aim);
        const key = JSON.stringify(inp2);
        if ((key !== lastSent && now - lastSentAt > 33) || now - lastSentAt > 250) {
          socket.emit('input', inp2);
          lastSent = key;
          lastSentAt = now;
        }
        // HUD de vida y forma
        $('#hp-fill').style.width = `${Math.max(0, (serverMe.hp / serverMe.mhp) * 100)}%`;
        $('#hp-text').textContent = `${serverMe.hp} / ${serverMe.mhp}`;
        $('#form-title').textContent = `${f.name} · ${f.title}`;
        $('#form-title').style.color = f.color;
        for (const btn of bar.children) {
          const active = btn.dataset.form === serverMe.f;
          btn.classList.toggle('active', active);
          const cd = btn.querySelector('.cd');
          if (active && priv) {
            const pct = Math.max(0, priv.cdS / f.special.cd);
            cd.style.height = `${pct * 100}%`;
          } else cd.style.height = '0%';
        }
        // distrito actual
        const d = districtAt(local.x, local.y);
        if (d.id !== currentDistrict) {
          currentDistrict = d.id;
          showDistrict(d.name);
        }
      }
      renderer.frame(state, local.x, local.y, myId, now / 1000);
      renderer.minimap(state, myId);
      // barra del jefe
      const boss = state.enemies.find((e) => e.k === 'okom');
      $('#boss').hidden = !boss;
      if (boss) $('#boss-fill').style.width = `${(boss.hp / boss.mhp) * 100}%`;
    }
    requestAnimationFrame(loop);
  }
  requestAnimationFrame(loop);

  function showDistrict(name) {
    const el = $('#district');
    el.textContent = name;
    el.classList.remove('show');
    void el.offsetWidth;
    el.classList.add('show');
  }
}

// ───────────────────────── Avisos ─────────────────────────

function toast(text, kind = 'info', big = false) {
  const el = document.createElement('div');
  el.className = `toast ${kind}${big ? ' big' : ''}`;
  el.textContent = text;
  $('#toasts').append(el);
  setTimeout(() => el.classList.add('out'), big ? 5000 : 3500);
  setTimeout(() => el.remove(), big ? 5600 : 4100);
}

function storyLine(text) {
  const el = $('#story-line');
  el.textContent = text;
  el.hidden = false;
  clearTimeout(storyLine.t);
  storyLine.t = setTimeout(() => { el.hidden = true; }, 9000);
}

boot();
