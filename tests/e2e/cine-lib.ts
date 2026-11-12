// Utilidades de las pruebas de cinemáticas con vídeo: sirven vídeos de prueba en lugar de los del
// juego y dejan un testigo dentro de la página que anota fases y reproducción.
import fs from 'node:fs';
import path from 'node:path';
import type { Page } from 'playwright';
import { sleep } from './lib.ts';

const FIX = path.resolve(import.meta.dirname, '../fixtures/video');

export type Mode = 'ok' | 'roto' | 'lento';
const MANIFEST = {
  v: 1,
  clips: {
    sello_1: { src: { mp4: 'sello_1.mp4', webm: 'sello_1.webm' }, dur: 3.5, audio: false, v: 'p1' },
    sello_2: { src: { mp4: 'sello_2.mp4', webm: 'sello_2.webm' }, dur: 3.5, audio: false, v: 'p1' },
    sello_3: { src: { mp4: 'sello_3.mp4', webm: 'sello_3.webm' }, dur: 3.5, audio: false, v: 'p1' },
  },
};

/** Sirve el manifiesto y los vídeos de prueba en lugar de los del juego. */
export async function serveVideo(page: Page, mode: Mode, counter?: { bytes: number; files: number }) {
  await page.route('**/game/video/**', async (route) => {
    const file = path.basename(new URL(route.request().url()).pathname);
    if (file === 'manifest.json') return route.fulfill({ contentType: 'application/json', body: JSON.stringify(MANIFEST) });
    const m = /^sello_([123])\.(mp4|webm)$/.exec(file);
    if (!m) return route.fulfill({ status: 404, body: 'no' });
    if (mode === 'lento') { await sleep(60_000); return route.abort().catch(() => {}); }
    if (mode === 'roto') {
      if (m[1] === '1') return route.fulfill({ status: 404, body: 'no' });
      return route.fulfill({ contentType: `video/${m[2]}`, body: fs.readFileSync(path.join(FIX, 'roto.webm')) });
    }
    const body = fs.readFileSync(path.join(FIX, `prueba_${m[1] === '3' ? '1' : m[1]}.${m[2]}`));
    if (counter) { counter.bytes += body.length; counter.files += 1; }
    return route.fulfill({ contentType: `video/${m[2]}`, body, headers: { 'cache-control': 'public, max-age=31536000, immutable' } });
  });
}

/** Testigo dentro de la página: anota cada cambio de fase y lo que hace el vídeo, sin depender del ritmo de la prueba. */
export const installWitness = (page: Page) => page.evaluate(() => {
  const w = window as any;
  w.__cine = { log: [], seen: {}, captions: [], notes: [], maxT: {}, videoFrames: 0, last: '', encounters: [], wave: 0 };
  setInterval(() => {
    const st = w.__aluxState;
    if (!st) return;
    const c = w.__cine;
    const el = document.querySelector('#cine video.on') as HTMLVideoElement | null;
    const info = JSON.parse(w.ALUX_VIDEO.info());
    const row = { phase: st.cine_phase, engineVideo: st.cine_video, overlay: w.ALUX_VIDEO.visible(), clip: info.current, frozen: st.frozen, cineUi: st.ui.cine };
    const key = JSON.stringify(row);
    if (key !== c.last) { c.last = key; c.log.push({ at: Math.round(performance.now()), ...row }); }
    c.seen[st.cine_phase] = c.seen[st.cine_phase] ?? Math.round(performance.now());
    // Cuadros que dibuja el juego mientras dura la escena (para comparar vídeo y motor)
    if (st.cine_phase === 2) { c.f0 = c.f0 ?? st.frames; c.t0 = c.t0 ?? performance.now(); c.f1 = st.frames; c.t1 = performance.now(); }
    // Qué pasa con la emboscada alrededor de la escena (puede avanzar deprisa si nadie pelea)
    if (c.encounters[c.encounters.length - 1] !== st.encounter) c.encounters.push(st.encounter);
    if (st.encounter === 1) c.wave = Math.max(c.wave, st.wave);
    if (el && info.current) {
      c.maxT[info.current] = Math.max(c.maxT[info.current] ?? 0, el.currentTime);
      const q = el.getVideoPlaybackQuality ? el.getVideoPlaybackQuality() : null;
      if (q) c.videoFrames = Math.max(c.videoFrames, q.totalVideoFrames);
    }
    const cap = document.querySelector('#cine .cap span:last-child')?.textContent || '';
    if (row.overlay && cap && !c.captions.includes(cap)) c.captions.push(cap);
    const note = document.querySelector('#cine .note')?.textContent || '';
    if (row.overlay && note && !c.notes.includes(note)) c.notes.push(note);
  }, 40);
});
export const witness = (page: Page) => page.evaluate(() => (window as any).__cine);
