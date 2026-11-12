// Mezclador de ALUX sobre Web Audio. Se carga ANTES que el motor.
//
// El motor, en web, reproduce los efectos como «muestras» de Web Audio: va bien para sonidos
// cortos, pero no puede hacer tres cosas que el juego necesita:
//   · bucles sin corte (los reinicia al terminar, con un hueco audible),
//   · efectos de bus (limitador, atenuación de la música),
//   · saber si de verdad está saliendo sonido.
// Este archivo se ocupa de eso con el MISMO AudioContext del motor:
//   · música, ambientes y bandas sonoras de las cinemáticas (archivos de game/web/static/audio),
//     con bucles exactos, fundidos cruzados y atenuación automática;
//   · todo lo que el motor manda a la salida pasa por aquí: suma, limitador y medidor;
//   · reanuda el audio con el primer gesto y avisa en pantalla mientras el navegador lo bloquea.
// El juego lo maneja desde game/scripts/client/audio.gd. Diseño y pruebas: docs/AUDIO.md.
(() => {
  'use strict';
  const Native = window.AudioContext || window.webkitAudioContext;
  const t0 = performance.now();
  const S = window.ALUX_SND = {
    ok: !!Native, ctx: null,
    vol: { Master: 0.9, Music: 0.7, Ambience: 0.8, Cinematics: 0.9 },
    manifest: { tracks: {}, cutscenes: {} }, manifestReady: false,
    loaded: {}, loops: {}, log: [], errors: [],
    musicId: '', musicWant: '', musicCur: null, cineCur: null, cineWant: '',
    rmsNow: 0, peakHold: 0, peakMax: 0, unlockMs: -1, muted: false, started: false,
  };
  if (!Native) return;

  const now = () => S.ctx.currentTime;
  const lin = (db) => Math.pow(10, db / 20);
  const note = (ev, detail) => {
    S.log.push([Math.round(performance.now() - t0), ev, detail === undefined ? '' : String(detail).slice(0, 90)]);
    if (S.log.length > 80) S.log.shift();
  };
  const fail = (where, err) => {
    const msg = where + ': ' + String(err && err.message ? err.message : err).slice(0, 90);
    S.errors.push(msg);
    if (S.errors.length > 12) S.errors.shift();
    note('error', msg);
  };
  /** Lleva un parámetro a `value` en `secs` segundos, partiendo de donde esté ahora. */
  const ramp = (param, value, secs) => {
    const t = now();
    param.cancelScheduledValues(t);
    param.setValueAtTime(param.value, t);
    param.linearRampToValueAtTime(value, t + Math.max(secs, 0.01));
  };

  // ---------------------------------------------------------------------------------------
  // 1. El contexto del motor: se captura al crearse y se le monta la cadena de salida
  // ---------------------------------------------------------------------------------------
  let ctxReady;
  const whenCtx = new Promise((resolve) => { ctxReady = resolve; });
  const Wrapped = function (...args) {
    const ctx = new Native(...args);
    if (!S.ctx) attach(ctx);
    return ctx;
  };
  Wrapped.prototype = Native.prototype;
  window.AudioContext = Wrapped;
  if (window.webkitAudioContext) window.webkitAudioContext = Wrapped;

  // Lo que el motor (o cualquiera) conecte a la salida del navegador entra por `godotIn`: así
  // pasa por el mismo limitador y el mismo medidor que la música.
  const nativeConnect = AudioNode.prototype.connect;
  AudioNode.prototype.connect = function (dest, ...rest) {
    if (S.ctx && dest === S.ctx.destination && this !== S.post) {
      nativeConnect.call(this, S.godotIn, rest.length ? rest[0] : 0);
      return dest;
    }
    return nativeConnect.call(this, dest, ...rest);
  };

  const LIMITER = { threshold: -8, knee: 6, ratio: 16, attack: 0.002, release: 0.12 };

  function attach(ctx) {
    S.ctx = ctx;
    window.ALUX_AUDIO = ctx;
    const gain = (v) => { const n = ctx.createGain(); n.gain.value = v; return n; };
    S.godotIn = gain(1);          // efectos del motor (ya traen el volumen de sus buses)
    S.master = gain(S.vol.Master); // maestro de lo que suena por aquí
    S.sum = gain(1);
    S.vis = gain(1);              // se cierra con la pestaña oculta
    S.limiter = ctx.createDynamicsCompressor();
    for (const k in LIMITER) S.limiter[k].value = LIMITER[k];
    S.makeup = gain(1);           // deshace la ganancia de compensación del compresor (se calibra abajo)
    S.post = gain(1);
    S.meter = ctx.createAnalyser();
    S.meter.fftSize = 2048;
    nativeConnect.call(S.godotIn, S.sum);
    nativeConnect.call(S.master, S.sum);
    nativeConnect.call(S.sum, S.vis);
    nativeConnect.call(S.vis, S.limiter);
    nativeConnect.call(S.limiter, S.makeup);
    nativeConnect.call(S.makeup, S.post);
    S.post.connect(ctx.destination);
    nativeConnect.call(S.post, S.meter);
    S.bus = { Music: gain(S.vol.Music), Ambience: gain(S.vol.Ambience), Cinematics: gain(S.vol.Cinematics) };
    for (const k in S.bus) nativeConnect.call(S.bus[k], S.master);
    S.musicDuck = gain(1);        // baja la música bajo los golpes grandes y durante las cinemáticas
    S.ambDuck = gain(1);
    nativeConnect.call(S.musicDuck, S.bus.Music);
    nativeConnect.call(S.ambDuck, S.bus.Ambience);
    ctx.addEventListener('statechange', () => {
      note('ctx', ctx.state);
      if (ctx.state === 'running' && S.unlockMs < 0) S.unlockMs = Math.round(performance.now() - t0);
      paint();
    });
    note('ctx', ctx.state + ' ' + ctx.sampleRate + ' Hz');
    if (ctx.state === 'running') S.unlockMs = Math.round(performance.now() - t0);
    calibrate();
    ctxReady(ctx);
  }

  // El compresor de Web Audio añade por su cuenta una ganancia de compensación que depende de sus
  // parámetros (y de cada navegador). Se mide con un tono muy por debajo del umbral y se deshace,
  // para que el limitador sólo actúe cuando hay picos.
  function calibrate() {
    try {
      const Off = window.OfflineAudioContext || window.webkitOfflineAudioContext;
      const off = new Off(1, 22050, 44100);
      const osc = off.createOscillator();
      const g = off.createGain();
      const comp = off.createDynamicsCompressor();
      for (const k in LIMITER) comp[k].value = LIMITER[k];
      osc.frequency.value = 440;
      g.gain.value = 0.02;
      nativeConnect.call(osc, g);
      nativeConnect.call(g, comp);
      nativeConnect.call(comp, off.destination);
      osc.start();
      Promise.resolve(off.startRendering()).then((buf) => {
        const d = buf.getChannelData(0);
        let sum = 0;
        for (let i = 11025; i < d.length; i++) sum += d[i] * d[i];
        const out = Math.sqrt(sum / (d.length - 11025));
        const ratio = out / (0.02 / Math.SQRT2);
        if (ratio > 0.5 && ratio < 4) { S.makeup.gain.value = 1 / ratio; note('limitador', 'compensa ' + (20 * Math.log10(ratio)).toFixed(1) + ' dB'); }
      }).catch((e) => fail('calibrar', e));
    } catch (e) { fail('calibrar', e); }
  }

  // ---------------------------------------------------------------------------------------
  // 2. Archivos: manifiestos y carga bajo demanda
  // ---------------------------------------------------------------------------------------
  const base = new URL('audio/', (document.currentScript && document.currentScript.src) || location.href).href;
  S.ready = Promise.all(['musica', 'ambiente', 'cine'].map((name) =>
    fetch(base + name + '.json').then((r) => (r.ok ? r.json() : null)).catch(() => null))).then((parts) => {
    for (const part of parts) {
      if (!part) continue;
      Object.assign(S.manifest.tracks, part.tracks || {});
      Object.assign(S.manifest.cutscenes, part.cutscenes || {});
    }
    S.manifestReady = true;
    note('manifiesto', Object.keys(S.manifest.tracks).length + ' pistas');
  });

  const buffers = new Map();   // id -> Promise<AudioBuffer>
  function load(id) {
    if (buffers.has(id)) return buffers.get(id);
    const started = performance.now();
    const p = Promise.all([S.ready, whenCtx]).then(() => {
      const tr = S.manifest.tracks[id];
      if (!tr) throw new Error('no está en el manifiesto');
      return fetch(base + tr.file);
    }).then((r) => {
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.arrayBuffer();
    }).then((data) => new Promise((resolve, reject) => S.ctx.decodeAudioData(data, resolve, reject)))
      .then((buf) => {
        S.loaded[id] = { s: +buf.duration.toFixed(2), ms: Math.round(performance.now() - started) };
        return buf;
      });
    p.catch((e) => { buffers.delete(id); fail('cargar ' + id, e); });
    buffers.set(id, p);
    return p;
  }
  S.preload = (ids) => { for (const id of ids || []) load(id).catch(() => {}); };
  /** ¿Existe la pista? Mientras el manifiesto no ha llegado se responde que sí (se sabrá al cargar). */
  S.has = (id) => !S.manifestReady || !!S.manifest.tracks[id];
  S.hasCine = (id) => !S.manifestReady || !!S.manifest.cutscenes[id];

  /** Arranca una pista. Los bucles llevan medio segundo de material repetido a cada lado
   *  (ver art/audio): el bucle cae siempre dentro de material periódico aunque el decodificador
   *  desplace el contenido unos milisegundos. */
  function start(id, buf, dest, offset) {
    const tr = S.manifest.tracks[id] || {};
    const src = S.ctx.createBufferSource();
    src.buffer = buf;
    let at = Math.max(offset || 0, 0);
    if (tr.loop) {
      const a = tr.loop[0];
      const b = Math.min(tr.loop[1], buf.duration);
      src.loop = true;
      src.loopStart = a;
      src.loopEnd = b;
      at = a + (at % Math.max(b - a, 0.1));
    }
    nativeConnect.call(src, dest);
    if (at < buf.duration - 0.02) src.start(0, at);
    return src;
  }
  function stopLater(part, secs) {
    ramp(part.gain.gain, 0, secs);
    try { part.src.stop(now() + secs + 0.05); } catch (e) { /* no llegó a arrancar */ }
    setTimeout(() => { try { part.gain.disconnect(); } catch (e) { /* nada */ } }, (secs + 0.3) * 1000);
  }

  // ---------------------------------------------------------------------------------------
  // 3. Música: una pista a la vez, con fundido cruzado
  // ---------------------------------------------------------------------------------------
  const recent = [];   // últimas músicas: las demás se sueltan de memoria
  S.music = (id, fade) => {
    id = id || '';
    fade = fade === undefined ? 1.6 : fade;
    if (S.musicWant === id) return;
    S.musicWant = id;
    note('musica', id || '(ninguna)');
    whenCtx.then(() => S.ready).then(() => {
      if (S.musicWant !== id) return;
      if (!id || !S.manifest.tracks[id]) {
        if (id) fail('musica', 'sin pista ' + id);
        swap(null, null, fade);
        return;
      }
      load(id).then((buf) => { if (S.musicWant === id) swap(id, buf, fade); }).catch(() => {});
    });
  };
  function swap(id, buf, fade) {
    if (S.musicCur) { stopLater(S.musicCur, fade); S.musicCur = null; }
    S.musicId = id || '';
    if (!id) return;
    const tr = S.manifest.tracks[id];
    const g = S.ctx.createGain();
    g.gain.value = 0;
    nativeConnect.call(g, S.musicDuck);
    const src = start(id, buf, g, 0);
    ramp(g.gain, lin(tr.gain_db || 0), fade * 0.75);
    const cur = S.musicCur = { id, src, gain: g };
    if (!tr.loop) src.onended = () => { if (S.musicCur === cur) { S.musicCur = null; S.musicId = ''; S.musicWant = ''; } };
    recent.unshift(id);
    for (const old of recent.splice(3)) if (!recent.includes(old)) buffers.delete(old);
  }
  /** Baja la música un momento para dejar sitio a un golpe grande. */
  S.duck = (db, attack, hold, release) => {
    if (!S.ctx || S.cineCur) return;
    const p = S.musicDuck.gain;
    const t = now();
    const v = lin(db === undefined ? -8 : db);
    attack = attack || 0.05; hold = hold === undefined ? 0.5 : hold; release = release || 0.7;
    p.cancelScheduledValues(t);
    p.setValueAtTime(p.value, t);
    p.linearRampToValueAtTime(v, t + attack);
    p.setValueAtTime(v, t + attack + hold);
    p.linearRampToValueAtTime(1, t + attack + hold + release);
  };
  /** Una pista suelta (fanfarria, etc.) en el bus indicado, sin tocar la música de fondo. */
  S.shot = (id, bus, gainDb) => {
    whenCtx.then(() => load(id)).then((buf) => {
      const g = S.ctx.createGain();
      g.gain.value = lin(gainDb || 0);
      nativeConnect.call(g, S.bus[bus] || S.bus.Music);
      const src = start(id, buf, g, 0);
      src.onended = () => { try { g.disconnect(); } catch (e) { /* nada */ } };
    }).catch(() => {});
  };

  // ---------------------------------------------------------------------------------------
  // 4. Ambientes: varias capas en bucle, cada una con su volumen
  // ---------------------------------------------------------------------------------------
  /** `mix`: { id: volumen 0–1 }. Arranca las capas que falten y apaga las que sobren. */
  S.ambience = (mix, secs) => {
    mix = mix || {};
    secs = secs === undefined ? 1.2 : secs;
    whenCtx.then(() => S.ready).then(() => {
      for (const id in mix) {
        if (!S.manifest.tracks[id]) continue;
        let L = S.loops[id];
        if (!L) {
          L = S.loops[id] = { gain: S.ctx.createGain(), src: null, want: 0 };
          L.gain.gain.value = 0;
          nativeConnect.call(L.gain, S.ambDuck);
          const mine = L;
          load(id).then((buf) => {
            // cada capa empieza en un punto distinto: dos partidas no suenan igual
            if (S.loops[id] === mine && !mine.src) mine.src = start(id, buf, mine.gain, Math.random() * buf.duration);
          }).catch(() => { if (S.loops[id] === mine) delete S.loops[id]; });
        }
        L.want = mix[id];
        ramp(L.gain.gain, mix[id], secs);
      }
      for (const id in S.loops) {
        if (id in mix) continue;
        const L = S.loops[id];
        delete S.loops[id];
        if (L.src) stopLater(L, secs); else L.gain.disconnect();
      }
    });
  };
  /** Volumen de una capa ya sonando (p. ej. el brasero según la distancia). */
  S.loopGain = (id, v) => {
    const L = S.loops[id];
    if (!L || Math.abs(L.want - v) < 0.01) return;
    L.want = v;
    L.gain.gain.setTargetAtTime(v, now(), 0.08);
  };

  // ---------------------------------------------------------------------------------------
  // 5. Cinemáticas: una banda sonora por escena (efectos + música), la misma con vídeo o con motor
  // ---------------------------------------------------------------------------------------
  /** Empieza la banda sonora de la cinemática `id` en el segundo `offset` de la escena. */
  S.cine = (id, offset) => {
    const called = performance.now();
    endCine(0.15, false);
    S.cineWant = id;
    note('cine', id + ' @' + (offset || 0).toFixed(2));
    whenCtx.then(() => S.ready).then(() => {
      const c = S.manifest.cutscenes[id];
      if (S.cineWant !== id) return;
      if (!c) { S.cineWant = ''; return; }
      ramp(S.musicDuck.gain, 0, 0.5);
      ramp(S.ambDuck.gain, 0.15, 0.5);
      const cur = S.cineCur = { id, parts: [] };
      for (const [key, bus] of [['fx', 'Cinematics'], ['mus', 'Music']]) {
        if (!c[key]) continue;
        load(c[key]).then((buf) => {
          if (S.cineCur !== cur) return;
          // si la descarga llegó tarde, entra donde va la escena, no desde el principio
          const at = (offset || 0) + (performance.now() - called) / 1000;
          if (at >= buf.duration - 0.05) return;
          const g = S.ctx.createGain();
          g.gain.value = 1;
          nativeConnect.call(g, S.bus[bus]);
          cur.parts.push({ src: start(c[key], buf, g, at), gain: g });
          if (at - (offset || 0) > 0.25) note('cine tarde', c[key] + ' +' + (at - (offset || 0)).toFixed(2) + ' s');
        }).catch(() => {});
      }
    });
  };
  function endCine(fade, restore) {
    S.cineWant = '';
    const cur = S.cineCur;
    S.cineCur = null;
    if (cur) for (const part of cur.parts) stopLater(part, fade);
    if (S.ctx && restore) { ramp(S.musicDuck.gain, 1, 1.4); ramp(S.ambDuck.gain, 1, 1.0); }
  }
  /** Termina la banda sonora (al acabar la escena deja la cola; si se omite, se funde rápido). */
  S.cineStop = (fade) => { if (S.cineCur || S.cineWant) note('cine fin', fade); endCine(fade === undefined ? 0.3 : fade, true); };

  // ---------------------------------------------------------------------------------------
  // 6. Volúmenes, medidor y estado
  // ---------------------------------------------------------------------------------------
  S.volume = (bus, v) => {
    v = Math.min(Math.max(+v || 0, 0), 1);
    S.vol[bus] = v;
    if (!S.ctx) return;
    const node = bus === 'Master' ? S.master : S.bus[bus];
    if (node) node.gain.setTargetAtTime(v, now(), 0.03);
  };
  S.setMuted = (m) => { S.muted = !!m; paint(); };

  const scratch = new Float32Array(2048);
  /** Nivel de lo que está saliendo AHORA por la salida del navegador (después del limitador). */
  S.level = () => {
    if (!S.meter) return { rms: 0, peak: 0 };
    S.meter.getFloatTimeDomainData(scratch);
    let sum = 0, peak = 0;
    for (let i = 0; i < scratch.length; i++) { const v = scratch[i]; sum += v * v; if (v > peak) peak = v; else if (-v > peak) peak = -v; }
    return { rms: Math.sqrt(sum / scratch.length), peak };
  };
  setInterval(() => {
    const l = S.level();
    S.rmsNow = l.rms;
    S.peakHold = Math.max(l.peak, S.peakHold * 0.7);
    if (l.peak > S.peakMax) S.peakMax = l.peak;
    paint();
  }, 200);
  /** Borra la retención de pico (antes de una prueba de sonido). */
  S.resetPeak = () => { S.peakHold = 0; };

  S.state = () => JSON.stringify({
    ok: S.ok, ctx: S.ctx ? S.ctx.state : 'none', rate: S.ctx ? S.ctx.sampleRate : 0,
    rms: +S.rmsNow.toFixed(4), peak: +S.peakHold.toFixed(4), peakMax: +S.peakMax.toFixed(4),
    music: S.musicId, want: S.musicWant, loops: Object.keys(S.loops), cine: S.cineCur ? S.cineCur.id : '',
    loaded: Object.keys(S.loaded), tracks: Object.keys(S.manifest.tracks).length,
    errors: S.errors.slice(-6), unlockMs: S.unlockMs, hidden: document.hidden, muted: S.muted,
    reduction: S.limiter ? +(+S.limiter.reduction).toFixed(1) : 0, vol: S.vol,
  });

  /** Tres notas sintetizadas aquí mismo: prueba la salida aunque no haya cargado ningún archivo. */
  S.beep = () => {
    if (!S.ctx) return;
    const t = now() + 0.02;
    [587.33, 739.99, 880].forEach((f, i) => {
      const o = S.ctx.createOscillator();
      const g = S.ctx.createGain();
      o.type = 'triangle';
      o.frequency.value = f;
      g.gain.setValueAtTime(0, t + i * 0.16);
      g.gain.linearRampToValueAtTime(0.35, t + i * 0.16 + 0.01);
      g.gain.exponentialRampToValueAtTime(0.001, t + i * 0.16 + 0.5);
      nativeConnect.call(o, g);
      nativeConnect.call(g, S.sum);
      o.start(t + i * 0.16);
      o.stop(t + i * 0.16 + 0.55);
    });
  };

  // ---------------------------------------------------------------------------------------
  // 7. Permiso del navegador: reanudar con el primer gesto y avisar mientras esté bloqueado
  // ---------------------------------------------------------------------------------------
  S.resume = (why) => {
    const c = S.ctx;
    if (!c || c.state === 'running' || c.state === 'closed') return;
    c.resume().then(() => note('reanudado', why || '')).catch((e) => fail('reanudar', e));
  };
  for (const ev of ['pointerdown', 'keydown', 'touchend', 'click']) {
    window.addEventListener(ev, () => S.resume(ev), { capture: true, passive: true });
  }
  document.addEventListener('visibilitychange', () => {
    if (!S.ctx) return;
    S.vis.gain.setTargetAtTime(document.hidden ? 0 : 1, now(), document.hidden ? 0.12 : 0.06);
    note('pestaña', document.hidden ? 'oculta' : 'visible');
    if (!document.hidden) S.resume('visible');
  });

  // Aviso en pantalla: «toca para activar el sonido» mientras el navegador no deja sonar, y una
  // marca discreta cuando el jugador tiene el volumen general a cero.
  let badge = null;
  function paint() {
    if (!document.body) return;
    if (!badge) {
      badge = document.createElement('button');
      badge.id = 'snd';
      badge.type = 'button';
      badge.style.cssText = 'position:fixed;z-index:6;left:50%;top:14px;transform:translateX(-50%);padding:10px 18px;border-radius:999px;' +
        'border:1px solid rgba(255,210,63,.7);background:rgba(10,20,17,.88);color:#fff8ea;font:600 14px system-ui,"Segoe UI",sans-serif;' +
        'cursor:pointer;display:none;box-shadow:0 6px 18px rgba(0,0,0,.4)';
      badge.addEventListener('click', () => { S.resume('aviso'); const c = document.getElementById('canvas'); if (c) c.focus(); });
      document.body.appendChild(badge);
    }
    const blocked = S.started && S.ctx && S.ctx.state !== 'running';
    const text = blocked ? '🔇 Toca aquí o pulsa una tecla para activar el sonido' : (S.started && S.muted ? '🔇 Sonido silenciado en Ajustes' : '');
    if (badge.dataset.text === text) return;
    badge.dataset.text = text;
    badge.textContent = text;
    badge.style.display = text ? 'block' : 'none';
    badge.style.opacity = blocked ? '1' : '.75';
    badge.style.top = blocked ? '14px' : 'auto';
    badge.style.bottom = blocked ? 'auto' : '14px';
    badge.dataset.state = blocked ? 'blocked' : (text ? 'muted' : '');
  }
  /** El juego avisa de que ya está en marcha (antes de eso no se molesta con avisos). */
  S.gameStarted = () => { S.started = true; paint(); };
})();
