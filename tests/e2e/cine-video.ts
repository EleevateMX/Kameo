// Cinemáticas con vídeo en un navegador real: precarga, reproducción sobre el juego, subtítulos,
// vuelta al juego y todos los caminos de fallo (archivo ausente o roto, descarga lenta, vídeo que
// se atasca, omitir a mitad). Los vídeos son patrones de prueba generados en local
// (tests/fixtures/video): se sirven interceptando las peticiones, sin tocar el juego.
// Requiere ALUX corriendo (node scripts/dev.mjs --prod).
//   npm run test:cine            todos los casos
//   npm run test:cine -- ok roto sólo los indicados
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import type { Browser, Page } from 'playwright';
import { BASE, driveTo, launch, login, sleep, state, waitFor } from './lib.ts';
import { installWitness, serveVideo, witness, type Mode } from './cine-lib.ts';

const OUT = process.env.E2E_SHOTS || path.resolve(import.meta.dirname, 'screenshots/cine');
fs.mkdirSync(OUT, { recursive: true });
const ok = (msg: string) => console.log(`✓ ${msg}`);
const only = process.argv.slice(2);

async function enter(browser: Browser, name: string, mode: Mode | null, size = { width: 960, height: 540 }) {
  const ctx = await browser.newContext({ viewport: size });
  // La introducción del capítulo no es lo que se prueba aquí
  await ctx.addInitScript(() => { try { localStorage.setItem('alux_seen_llamado', '1'); } catch { /* nada */ } });
  const page = await ctx.newPage();
  const errors: string[] = [];
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text().slice(0, 200)); });
  page.on('pageerror', (e) => errors.push(String(e).slice(0, 200)));
  const counter = { bytes: 0, files: 0 };
  if (mode) await serveVideo(page, mode, counter);
  await login(page, name);
  await page.click('text=Crear sala privada');
  const code = (await page.textContent('.room-code'))!.trim();
  await page.goto(`${BASE}/game/index.html?room=${code}&debug=1&q=min`);
  await waitFor('el juego conecta', async () => (await state(page))?.net === 'PLAYING', 300_000);
  await waitFor('bienvenida', async () => (await state(page) as any)?.ui?.intro === true, 60_000);
  await page.keyboard.press('Enter');
  await waitFor('bienvenida cerrada', async () => (await state(page) as any)?.ui?.intro === false, 30_000);
  return { ctx, page, code, errors, counter };
}

/** Lleva a la jugadora (sola) al altar del santuario y espera a que la cinemática termine. */
async function openAndWatch(page: Page, during?: (page: Page) => Promise<void>) {
  await installWitness(page);
  await page.mouse.click(480, 200);
  const walk = { stop: false };
  const going = driveTo(page, 17.5, -5, { timeoutMs: 180_000, stop: 0.9, cancel: walk });
  await waitFor('la sala entra en preparación', async () => (await witness(page)).seen[1] !== undefined, 180_000);
  walk.stop = true;
  await going;
  await waitFor('orden de inicio', async () => (await witness(page)).seen[2] !== undefined, 30_000);
  if (during) await during(page);
  await waitFor('partida reanudada', async () => {
    const st: any = await state(page);
    return st.cine_phase === 0 && st.cine === '' && st.fade === 0 && st.ui.cine === false;
  }, 60_000);
  return { w: await witness(page), s: (await state(page)) as any };
}

/** Después de la cinemática el juego tiene que estar como antes: interfaz, control y emboscada. */
async function assertResumed(page: Page, s: any) {
  assert.equal(s.frozen, false, 'la sala ya no está en pausa');
  assert.equal(s.encounter, 1, 'la emboscada empieza al terminar la escena');
  assert.equal(s.ui.cine, false, 'la interfaz de juego vuelve');
  assert.match(s.ui.objective, /enemig|Quedan|Resist/i, 'con el objetivo de la emboscada');
  assert.equal(await page.evaluate(() => (window as any).ALUX_VIDEO.visible()), false, 'el vídeo ya no tapa el juego');
  const me0 = s.players.find((p: any) => p.id === s.me);
  await page.keyboard.down('KeyS');
  await sleep(1500);
  await page.keyboard.up('KeyS');
  const s2: any = await state(page);
  const me1 = s2.players.find((p: any) => p.id === s2.me);
  assert.ok(me1.dead || Math.hypot(me1.x - me0.x, me1.z - me0.z) > 0.5, 'se recupera el control del personaje');
}

const cases: Record<string, (browser: Browser) => Promise<void>> = {
  // 1) Todo va bien: los dos planos se ven como vídeo, con subtítulos, y se vuelve al juego
  async ok(browser) {
    const { ctx, page, errors, counter } = await enter(browser, 'Video', 'ok');
    await waitFor('vídeos precargados', async () => {
      const v = (await state(page) as any).video;
      return v?.clips?.sello_1?.s === 'fetched' && v?.clips?.sello_2?.s === 'fetched' && v?.clips?.sello_3?.s === 'fetched';
    }, 60_000);
    const pre: any = (await state(page) as any).video;
    assert.equal(counter.files, 3, 'un archivo por vídeo: sólo el formato que este navegador reproduce');
    ok(`Precarga: 3 vídeos descargados antes de necesitarlos (${(pre.stats.bytes / 1024).toFixed(0)} KB, ${pre.stats.preloadMs} ms el más lento)`);
    let shotDone = false;
    const { w, s } = await openAndWatch(page, async (p) => {
      await waitFor('vídeo en pantalla', async () => (await witness(p)).log.some((r: any) => r.overlay && r.clip === 'sello_1'), 10_000);
      await p.screenshot({ path: path.join(OUT, 'video-sobre-el-juego.png'), timeout: 60_000 }).then(() => { shotDone = true; }).catch(() => {});
    });
    const prepMs = w.seen[2] - w.seen[1];
    assert.ok(prepMs < 2500, `con el vídeo ya descargado la preparación es breve (${prepMs} ms)`);
    assert.ok(w.seen[3] !== undefined, 'pasa por la fase de reanudación');
    const playing = w.log.filter((r: any) => r.phase === 2);
    assert.ok(playing.some((r: any) => r.clip === 'sello_1' && r.overlay && r.engineVideo), 'el primer plano se ve como vídeo');
    assert.ok(playing.some((r: any) => r.clip === 'sello_2' && r.overlay), 'el segundo plano también');
    assert.ok(playing.some((r: any) => r.clip === 'sello_3' && r.overlay), 'y el tercero');
    assert.ok(w.maxT.sello_1 > 1.5 && w.maxT.sello_2 > 0.8, `los dos vídeos avanzan (${w.maxT.sello_1?.toFixed(1)} s y ${w.maxT.sello_2?.toFixed(1)} s)`);
    assert.ok(w.captions.some((c: string) => /sello cede/.test(c)) && w.captions.some((c: string) => /Olvidados/.test(c)), 'los subtítulos de cada plano salen sobre el vídeo');
    assert.ok(w.notes.some((n: string) => /omitir/.test(n)), 'y el aviso para omitir');
    assert.deepEqual([s.cine_stats.video, s.cine_stats.engine, s.cine_stats.fallbacks], [1, 0, 0], 'contada como vista en vídeo, sin recurrir al motor');
    assert.equal(s.video.log.length, 0, 'sin fallos registrados');
    await assertResumed(page, s);
    // (los vídeos de otras escenas no están en el manifiesto de esta prueba: constan como ausentes)
    await waitFor('decodificadores liberados', async () => Object.entries(((await state(page)) as any).video.clips)
      .every(([id, c]: [string, any]) => c.s === (id.startsWith('sello_') ? 'fetched' : 'absent')), 15_000);
    assert.equal(await page.evaluate(() => document.querySelectorAll('#cine video').length), 0, 'al terminar no queda ningún <video> abierto');
    ok(`Vídeo sobre el juego: preparación ${prepMs} ms, tres planos con subtítulos, ${w.videoFrames} cuadros de vídeo, vuelta al juego con la emboscada${shotDone ? '' : ' (sin captura)'}`);
    console.log(`  rendimiento durante la escena: el juego dibuja ${((w.f1 - w.f0) / ((w.t1 - w.t0) / 1000)).toFixed(1)} cuadros/s por debajo (mundo sin dibujar mientras el vídeo lo tapa)`);
    assert.equal(errors.filter((e) => !/favicon|WebGL|GPU stall|swiftshader|deprecated/i.test(e)).length, 0, 'sin errores en la consola');
    await ctx.close();
  },

  // 1b) Los vídeos reales del juego (los de Kling), sin sustituir nada: tienen que descargarse,
  // decodificarse y verse en este navegador, y la escena tiene que durar lo que dice su guion
  async real(browser) {
    const { ctx, page, errors } = await enter(browser, 'Kling', null, { width: 1280, height: 720 });
    await waitFor('vídeos reales precargados', async () => {
      const v = (await state(page) as any).video;
      return ['sello_1', 'sello_2', 'sello_3'].every((id) => v?.clips?.[id]?.s === 'fetched');
    }, 120_000);
    const pre: any = (await state(page) as any).video;
    assert.ok(pre.stats.bytes > 1_000_000, `son los vídeos de verdad, no los de prueba (${pre.stats.bytes} bytes)`);
    const shots: string[] = [];
    const { w, s } = await openAndWatch(page, async (p) => {
      for (const clip of ['sello_1', 'sello_2', 'sello_3']) {
        await waitFor(`${clip} en pantalla`, async () => {
          const cur = await witness(p);
          return cur.log.some((r: any) => r.overlay && r.clip === clip) || cur.seen[3] !== undefined;
        }, 20_000);
        await sleep(clip === 'sello_2' ? 1500 : 900);
        await p.screenshot({ path: path.join(OUT, `kling-${clip}.jpg`), type: 'jpeg', quality: 85, timeout: 30_000 }).then(() => shots.push(clip)).catch(() => {});
      }
    });
    const playing = w.log.filter((r: any) => r.phase === 2);
    for (const clip of ['sello_1', 'sello_2', 'sello_3']) {
      assert.ok(playing.some((r: any) => r.clip === clip && r.overlay), `${clip} se ve como vídeo`);
      assert.ok(w.maxT[clip] > 0.8, `${clip} avanza (${w.maxT[clip]?.toFixed(1)} s)`);
    }
    assert.ok(w.captions.length >= 3, `cada plano con su subtítulo (${w.captions.length})`);
    assert.deepEqual([s.cine_stats.video, s.cine_stats.engine, s.cine_stats.fallbacks], [1, 0, 0], 'vista entera como vídeo, sin recurrir al motor');
    assert.equal(s.video.log.length, 0, 'sin fallos registrados');
    const total = w.seen[3] - w.seen[2];
    assert.ok(total > 8500 && total < 12500, `dura lo que su guion (${total} ms de 10000)`);
    await assertResumed(page, s);
    assert.equal(s.gate, true, 'al volver, el santuario está abierto como mostró el vídeo');
    ok(`Vídeos de Kling en el juego: ${(pre.stats.bytes / 1e6).toFixed(2)} MB precargados en ${pre.stats.preloadMs} ms el más lento; tres planos, ${w.videoFrames} cuadros, ${total} ms; capturas: ${shots.join(', ') || 'ninguna'}`);
    assert.equal(errors.filter((e) => !/favicon|WebGL|GPU stall|swiftshader|deprecated/i.test(e)).length, 0, 'sin errores en la consola');
    await ctx.close();
  },

  // 2) Un archivo no existe y el otro está corrupto: se ve la escena del motor y queda registrado
  async roto(browser) {
    const { ctx, page } = await enter(browser, 'Roto', 'roto');
    await waitFor('descargas resueltas', async () => {
      const v = (await state(page) as any).video;
      // el que no existe falla al descargarse; los corruptos se descubren al prepararlos para la escena
      return v?.clips?.sello_1?.s === 'error' && v?.clips?.sello_2?.s === 'fetched' && v?.clips?.sello_3?.s === 'fetched';
    }, 60_000);
    const { w, s } = await openAndWatch(page);
    assert.ok(!w.log.some((r: any) => r.overlay), 'ningún vídeo tapa el juego');
    assert.ok(w.log.some((r: any) => r.phase === 2 && r.cineUi), 'la escena se ve con el motor');
    assert.deepEqual([s.cine_stats.video, s.cine_stats.engine], [0, 1]);
    const whats = s.video.log.map((l: any) => `${l.id}:${l.what}`);
    assert.ok(whats.includes('sello_1:descarga') && whats.includes('sello_2:decodificar'), `los fallos quedan registrados (${whats.join(', ')})`);
    await assertResumed(page, s);
    ok(`Archivo ausente y archivo corrupto: escena del motor, partida intacta, fallos registrados (${whats.join(', ')})`);
    console.log(`  rendimiento durante la escena: el juego dibuja ${((w.f1 - w.f0) / ((w.t1 - w.t0) / 1000)).toFixed(1)} cuadros/s (escena del motor)`);
    await ctx.close();
  },

  // 3) La descarga no llega a tiempo: el cliente avisa antes del límite y nadie espera de más
  async lento(browser) {
    const { ctx, page } = await enter(browser, 'Lento', 'lento');
    const { w, s } = await openAndWatch(page);
    const prepMs = w.seen[2] - w.seen[1];
    assert.ok(prepMs < 5800, `la preparación no pasa del tiempo máximo (${prepMs} ms)`);
    assert.ok(!w.log.some((r: any) => r.overlay), 'sin vídeo: escena del motor');
    assert.deepEqual([s.cine_stats.video, s.cine_stats.engine], [0, 1]);
    await assertResumed(page, s);
    ok(`Descarga lenta: la escena empieza a los ${prepMs} ms con la versión del motor y la partida sigue`);
    await ctx.close();
  },

  // 4) El vídeo se atasca a mitad: se quita y se sigue viendo el mismo plano con el motor
  async atasco(browser) {
    const { ctx, page } = await enter(browser, 'Atasco', 'ok');
    await waitFor('vídeos precargados', async () => (await state(page) as any).video?.clips?.sello_3?.s === 'fetched', 60_000);
    const { w, s } = await openAndWatch(page, async (p) => {
      // Se atasca el plano más largo (el segundo): así queda tiempo para ver el cambio al motor
      await waitFor('segundo vídeo en pantalla', async () => (await witness(p)).log.some((r: any) => r.overlay && r.clip === 'sello_2'), 15_000);
      await p.evaluate(() => (document.querySelector('#cine video.on') as HTMLVideoElement)?.pause());
    });
    const playing = w.log.filter((r: any) => r.phase === 2);
    assert.ok(playing.some((r: any) => r.overlay) && playing.some((r: any) => !r.overlay && r.cineUi), 'empieza como vídeo y sigue con el motor sin salir de la escena');
    assert.ok(s.cine_stats.fallbacks >= 1, 'el cambio al motor queda contado');
    assert.ok(s.video.log.some((l: any) => l.what === 'atascado'), 'y registrado como atasco');
    await assertResumed(page, s);
    ok('Vídeo atascado: se detecta, se quita y la escena sigue con el motor hasta que el servidor la termina');
    await ctx.close();
  },

  // 5) Omitir a mitad del vídeo (sola: su voto es mayoría)
  async omitir(browser) {
    const { ctx, page } = await enter(browser, 'Omite', 'ok');
    await waitFor('vídeos precargados', async () => (await state(page) as any).video?.clips?.sello_3?.s === 'fetched', 60_000);
    let pressedAt = 0;
    const { w, s } = await openAndWatch(page, async (p) => {
      await waitFor('vídeo en pantalla', async () => (await witness(p)).log.some((r: any) => r.overlay), 10_000);
      pressedAt = await p.evaluate(() => Math.round(performance.now()));
      await p.keyboard.press('Enter');
    });
    const total = w.seen[3] - w.seen[2];
    assert.ok(total < 8000, `la escena termina antes de su duración completa (${total} ms de 10000)`);
    assert.ok(!w.log.some((r: any) => r.clip === 'sello_2' && r.overlay), 'el segundo plano ya no llega a verse');
    await assertResumed(page, s);
    ok(`Omitir durante el vídeo: termina ${w.seen[3] - pressedAt} ms después de pulsar Enter y se vuelve al juego`);
    await ctx.close();
  },
};

const browser = await launch();
for (const [name, run] of Object.entries(cases)) {
  if (only.length && !only.includes(name)) continue;
  await run(browser);
}
await browser.close();
console.log(`Cinemáticas con vídeo verificadas. Capturas en ${OUT}`);
process.exit(0);
