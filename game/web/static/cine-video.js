// Puente de vídeo para las cinemáticas de ALUX (lo usa game/scripts/client/cinematics/video_bridge.gd).
//
// El motor del juego en el navegador no reproduce MP4 ni WebM (sólo Ogg Theora, decodificado por
// software en el hilo principal). Por eso los vídeos de las cinemáticas los reproduce el propio
// navegador, en un elemento <video> colocado encima del lienzo del juego.
//
// Reglas de este puente:
//  - Nada de lo que pasa aquí decide el juego: si un vídeo falta, falla o se atasca, el juego
//    sigue con la misma escena hecha dentro del motor (que corre debajo).
//  - Los vídeos se descargan enteros por adelantado (precarga) y se guardan en la caché del navegador.
//    Descargar no es decodificar: el elemento <video> de cada plano se crea justo antes de su
//    escena (prepare) y se suelta al terminar (release). Tener decodificadores abiertos sin usar
//    le cuesta al equipo durante toda la partida, y en uno modesto se nota.
//  - Suenan sólo si el manifiesto lo indica y el usuario ya interactuó con la página; si el
//    navegador bloquea el sonido, se reproducen en silencio.
//  - Sólo se cargan archivos del mismo sitio declarados en video/manifest.json.
//  - El juego sólo pasa identificadores ([a-z0-9_]) y textos, que se escriben como texto plano.
(() => {
  'use strict';
  const ID_RE = /^[a-z0-9_]{1,40}$/;
  const FILE_RE = /^[a-z0-9_.-]{1,80}\.(mp4|webm)$/;
  const TYPES = { mp4: 'video/mp4; codecs="avc1.42E01E"', webm: 'video/webm; codecs="vp9"' };
  const FETCH_TIMEOUT_MS = 25000;
  const STALL_MS = 1800;            // sin avanzar este tiempo mientras debería sonar = atascado
  const FADE_MS = 280;

  const base = new URL('video/', document.currentScript ? document.currentScript.src : location.href).href;
  const clips = new Map();          // id -> { s, el, bytes, ms, url, audio, dur, err }
  const log = [];                   // fallos pendientes de informar al juego (métricas)
  const stats = { shown: 0, failed: 0, bytes: 0, preloadMs: 0, prepareMs: 0 };
  let manifest = null;              // null: sin pedir · {}: pedido (vacío si no hay o falló)
  let manifestState = 'idle';       // idle · loading · ok · none
  let root = null, stage = null, capWho = null, capText = null, noteEl = null, titleEl = null;
  let current = '';                 // id del vídeo en pantalla
  let lastT = 0, lastMove = 0;
  let hideTimer = 0;

  const fail = (id, what, detail) => {
    stats.failed += 1;
    const entry = { id, what, detail: String(detail || '').slice(0, 120), at: Math.round(performance.now()) };
    log.push(entry);
    if (log.length > 20) log.shift();
    console.warn('[cine] ' + id + ': ' + what + (entry.detail ? ' (' + entry.detail + ')' : ''));
  };

  const pickFormat = (src) => {
    const probe = document.createElement('video');
    for (const kind of ['mp4', 'webm']) {
      if (typeof src[kind] === 'string' && FILE_RE.test(src[kind]) && probe.canPlayType(TYPES[kind]) !== '') return kind;
    }
    return '';
  };

  const build = () => {
    if (root) return;
    const style = document.createElement('style');
    style.textContent = `
      #cine { position: fixed; inset: 0; z-index: 3; background: #000; display: none; pointer-events: none; overflow: hidden; }
      #cine .stage { position: absolute; left: 0; right: 0; top: 10.5vh; bottom: 10.5vh; background: #000; }
      #cine video { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; opacity: 0; transition: opacity ${FADE_MS}ms linear; background: #000; }
      #cine video.on { opacity: 1; }
      #cine .cap { position: absolute; left: 50%; bottom: 13.5vh; transform: translateX(-50%); width: min(860px, 86vw); text-align: center;
        font: 700 clamp(15px, 2.9vh, 30px)/1.3 system-ui, "Segoe UI", sans-serif; color: #fffaeb;
        text-shadow: 0 0 6px rgba(3, 8, 8, .95), 0 2px 2px rgba(3, 8, 8, .95), 0 0 2px #000; }
      #cine .cap .who { display: block; font-size: .72em; color: #ffd23f; margin-bottom: .2em; }
      #cine .title { position: absolute; left: 0; right: 0; top: 14.5vh; text-align: center; font: 800 clamp(20px, 4.2vh, 44px)/1.2 system-ui, "Segoe UI", sans-serif;
        color: #ffd23f; letter-spacing: .04em; text-shadow: 0 0 10px rgba(3, 8, 8, .9), 0 3px 2px rgba(3, 8, 8, .9); opacity: 0; transition: opacity .8s; }
      #cine .title.on { opacity: 1; }
      #cine .note { position: absolute; right: 18px; bottom: 16px; font: 700 clamp(10px, 1.7vh, 16px) system-ui, "Segoe UI", sans-serif; color: rgba(255, 255, 255, .6); }
    `;
    document.head.appendChild(style);
    root = document.createElement('div');
    root.id = 'cine';
    root.setAttribute('aria-hidden', 'true');
    stage = document.createElement('div');
    stage.className = 'stage';
    const cap = document.createElement('div');
    cap.className = 'cap';
    capWho = document.createElement('span');
    capWho.className = 'who';
    capText = document.createElement('span');
    cap.append(capWho, capText);
    titleEl = document.createElement('div');
    titleEl.className = 'title';
    noteEl = document.createElement('div');
    noteEl.className = 'note';
    root.append(stage, titleEl, cap, noteEl);
    document.body.appendChild(root);
  };

  const loadManifest = async () => {
    if (manifestState !== 'idle') return;
    manifestState = 'loading';
    try {
      const res = await fetch(base + 'manifest.json', { cache: 'no-cache', credentials: 'same-origin' });
      if (!res.ok) throw new Error('HTTP ' + res.status);
      const data = await res.json();
      manifest = (data && typeof data.clips === 'object' && data.clips) || {};
      manifestState = Object.keys(manifest).length ? 'ok' : 'none';
    } catch (e) {
      manifest = {};
      manifestState = 'none';
      // Sin manifiesto no hay vídeos: no es un fallo del jugador, el juego usa la versión del motor.
      console.info('[cine] sin manifiesto de vídeo (' + (e && e.message) + '): se usarán las escenas del motor');
    }
  };

  const loadClip = async (id) => {
    const meta = manifest[id];
    const clip = { s: 'loading', el: null, bytes: 0, ms: 0, url: '', audio: !!(meta && meta.audio), dur: Number(meta && meta.dur) || 0, err: '' };
    clips.set(id, clip);
    const kind = meta && typeof meta.src === 'object' && meta.src ? pickFormat(meta.src) : '';
    if (!kind) {
      clip.s = 'error';
      clip.err = 'formato';
      fail(id, 'formato', 'el navegador no reproduce ninguno de los formatos ofrecidos');
      return;
    }
    const t0 = performance.now();
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), FETCH_TIMEOUT_MS);
    try {
      const v = typeof meta.v === 'string' && /^[a-z0-9]{1,32}$/i.test(meta.v) ? '?v=' + meta.v : '';
      const res = await fetch(base + meta.src[kind] + v, { credentials: 'same-origin', signal: ctl.signal, priority: 'low' });
      if (!res.ok) throw new Error('HTTP ' + res.status);
      const blob = await res.blob();
      clip.bytes = blob.size;
      clip.url = URL.createObjectURL(new Blob([blob], { type: kind === 'mp4' ? 'video/mp4' : 'video/webm' }));
    } catch (e) {
      clearTimeout(timer);
      clip.s = 'error';
      clip.err = 'descarga';
      fail(id, 'descarga', e && e.name === 'AbortError' ? 'tiempo agotado' : e && e.message);
      return;
    }
    clearTimeout(timer);
    clip.s = 'fetched';
    clip.ms = Math.round(performance.now() - t0);
    stats.bytes += clip.bytes;
    stats.preloadMs = Math.max(stats.preloadMs, clip.ms);
  };

  // Crea el <video> de un clip ya descargado y espera a que tenga su primer cuadro decodificado.
  const prepareClip = (id) => {
    const clip = clips.get(id);
    if (!clip || clip.s !== 'fetched') return;
    clip.s = 'preparing';
    const t0 = performance.now();
    build();
    const el = document.createElement('video');
    el.muted = true;
    el.playsInline = true;
    el.setAttribute('playsinline', '');
    el.preload = 'auto';
    el.disablePictureInPicture = true;
    el.tabIndex = -1;
    const done = (ok, why) => {
      el.removeEventListener('canplaythrough', onOk);
      el.removeEventListener('loadeddata', onOk);
      el.removeEventListener('error', onErr);
      clearTimeout(guard);
      if (clip.s !== 'preparing') return;   // se soltó mientras se preparaba
      clip.pending = null;
      if (ok) {
        clip.s = 'ready';
        clip.el = el;
        if (!clip.dur && isFinite(el.duration)) clip.dur = el.duration;
        stats.prepareMs = Math.max(stats.prepareMs, Math.round(performance.now() - t0));
      } else {
        clip.s = 'error';
        clip.err = 'decodificar';
        fail(id, 'decodificar', why);
        el.remove();
      }
    };
    const onOk = () => done(true);
    const onErr = () => done(false, el.error ? 'código ' + el.error.code : 'error');
    const guard = setTimeout(() => done(false, 'tiempo agotado'), 12000);
    el.addEventListener('canplaythrough', onOk);
    el.addEventListener('loadeddata', onOk);
    el.addEventListener('error', onErr);
    clip.pending = el;
    el.src = clip.url;
    stage.appendChild(el);
    el.load();
  };

  const stopCurrent = () => {
    const clip = clips.get(current);
    if (clip && clip.el) {
      clip.el.classList.remove('on');
      try { clip.el.pause(); } catch (e) { /* nada */ }
    }
    current = '';
  };

  const api = {
    /** Pide el manifiesto y descarga los vídeos indicados que existan en él (sin decodificarlos). */
    preload(ids) {
      const list = (Array.isArray(ids) ? ids : []).filter((id) => ID_RE.test(id));
      (async () => {
        await loadManifest();
        while (manifestState === 'loading') await new Promise((r) => setTimeout(r, 50));
        for (const id of list) {
          if (clips.has(id)) continue;
          if (!manifest[id]) { clips.set(id, { s: 'absent' }); continue; }
          await loadClip(id);   // de uno en uno: no compite con la partida por la red
        }
      })();
      return true;
    },
    /** Deja listos para reproducir (decodificador creado) los vídeos indicados que ya estén descargados. */
    prepare(ids) {
      (Array.isArray(ids) ? ids : []).filter((id) => ID_RE.test(id)).forEach(prepareClip);
      return true;
    },
    /** Suelta los decodificadores; los archivos descargados se conservan para la próxima vez. */
    release() {
      if (current) stopCurrent();
      clips.forEach((clip) => {
        const el = clip.el || clip.pending;
        if (el) {
          try { el.pause(); el.removeAttribute('src'); el.load(); } catch (e) { /* nada */ }
          el.remove();
        }
        clip.el = null;
        clip.pending = null;
        if (clip.s === 'ready' || clip.s === 'preparing') clip.s = 'fetched';
      });
      if (root) root.style.display = 'none';
      return true;
    },
    /** Estado de un vídeo: unknown · absent · loading · fetched · preparing · ready · playing · ended · error */
    status(id) {
      const clip = clips.get(id);
      if (!clip) return manifestState === 'none' ? 'absent' : 'unknown';
      if (clip.s === 'ready' && id === current && clip.el) return clip.el.ended ? 'ended' : 'playing';
      return clip.s;
    },
    /** Muestra el vídeo sobre el juego y lo reproduce desde `at` segundos. Devuelve false si no puede. */
    show(id, volume, at) {
      const clip = clips.get(id);
      if (!clip || clip.s !== 'ready' || !clip.el) return false;
      build();
      clearTimeout(hideTimer);
      if (current && current !== id) stopCurrent();
      const el = clip.el;
      current = id;
      root.style.display = 'block';
      try { el.currentTime = Math.max(0, Math.min(Number(at) || 0, (clip.dur || 0) - 0.05)); } catch (e) { /* nada */ }
      const vol = Math.max(0, Math.min(1, Number(volume)));
      const active = navigator.userActivation ? navigator.userActivation.hasBeenActive : true;
      el.muted = !(clip.audio && vol > 0 && active);
      el.volume = isFinite(vol) ? vol : 1;
      lastT = el.currentTime;
      lastMove = performance.now();
      const started = el.play();
      if (started && started.catch) {
        started.catch(() => {
          // El navegador bloqueó el sonido: se intenta en silencio antes de darlo por perdido
          el.muted = true;
          const again = el.play();
          if (again && again.catch) again.catch((e) => { if (current === id) { clip.s = 'error'; clip.err = 'reproducir'; fail(id, 'reproducir', e && e.name); } });
        });
      }
      el.classList.add('on');
      stats.shown += 1;
      return true;
    },
    /**
     * Comprueba que el vídeo en pantalla avanza. Devuelve su tiempo en segundos, o -1 si no hay
     * vídeo, falló o lleva demasiado sin avanzar (el juego pasa entonces a la escena del motor).
     */
    tick() {
      const clip = clips.get(current);
      if (!clip || !clip.el || clip.s !== 'ready') return -1;
      const el = clip.el;
      if (el.error) { clip.s = 'error'; clip.err = 'decodificar'; fail(current, 'decodificar', 'código ' + el.error.code); return -1; }
      const now = performance.now();
      if (el.ended || el.currentTime !== lastT) { lastT = el.currentTime; lastMove = now; }
      else if (now - lastMove > STALL_MS) { clip.s = 'error'; clip.err = 'atascado'; fail(current, 'atascado', 't=' + el.currentTime.toFixed(1)); return -1; }
      return el.currentTime;
    },
    /** Quita el vídeo con un fundido a negro y después descubre el juego. */
    hide(instant) {
      if (!root) return true;
      clearTimeout(hideTimer);
      stopCurrent();
      const off = () => { root.style.display = 'none'; api.caption('', ''); api.title(''); };
      if (instant) off(); else hideTimer = setTimeout(off, FADE_MS + 40);
      return true;
    },
    visible() { return !!root && root.style.display === 'block'; },
    caption(who, text) { if (!root) return true; capWho.textContent = String(who || ''); capWho.style.display = who ? 'block' : 'none'; capText.textContent = String(text || ''); return true; },
    title(text) { if (!root) return true; titleEl.textContent = String(text || ''); titleEl.classList.toggle('on', !!text); return true; },
    note(text) { if (!root) return true; noteEl.textContent = String(text || ''); return true; },
    /** Resumen para depurar y para las métricas de la sesión. */
    info() {
      const items = {};
      clips.forEach((c, id) => { items[id] = { s: api.status(id), bytes: c.bytes || 0, ms: c.ms || 0, dur: c.dur || 0, err: c.err || '' }; });
      return JSON.stringify({ manifest: manifestState, current, visible: api.visible(), stats, clips: items, log: log.slice(-8) });
    },
  };
  window.ALUX_VIDEO = api;
})();
