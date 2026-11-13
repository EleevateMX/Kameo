// Capturas y medidas de dibujo de la plaza de Mérida, con un navegador y un alux.
//
//   E2E_BASE_URL=http://localhost:3000 npx tsx e2e/plaza-capturas.ts [carpeta] [vistas…]
//
// Recorre unos cuantos puntos de vista (llegada, vista general, cada fachada, el mercado, el
// camino al portal…) en calidad alta, y cuatro de ellos en mínima. De cada uno
// guarda la captura y las llamadas de dibujo, primitivas y objetos que da el motor
// (`__aluxState.perf`). No comprueba nada: es la herramienta para comparar antes y después de
// tocar el escenario. Sin tarjeta gráfica los FPS no valen; las llamadas y las primitivas sí.
// Requiere ALUX corriendo con el servidor de zonas (node scripts/dev.mjs).
import fs from 'node:fs';
import path from 'node:path';
import type { Frame, Page } from 'playwright';
import { BASE, launch, login, sleep, waitFor } from './lib.ts';

const OUT = path.resolve(process.argv[2] || path.join(import.meta.dirname, 'screenshots/plaza-nueva'));
const ONLY = process.argv.slice(3);
fs.mkdirSync(OUT, { recursive: true });

/** Vistas: por dónde andar ("x,z;x,z…"; '' = quedarse en la llegada) y cámara "giro,inclinación,distancia". */
const VIEWS: { id: string; goto: string; cam: string }[] = [
  { id: 'llegada', goto: '', cam: '' },
  { id: 'vista-general', goto: '0,24', cam: '3.1416,0.62,13' },
  { id: 'casonas-sur', goto: '0,22', cam: '0.0,0.1,12' },
  { id: 'fuente-suroeste', goto: '-8,18', cam: '-0.785,0.2,11' },
  { id: 'portales-oeste', goto: '-9,8;-18,3', cam: '-1.5708,0.08,13' },
  { id: 'mercado', goto: '-14,-6', cam: '-2.356,0.2,10' },
  { id: 'mercado-antojitos', goto: '-9,-12', cam: '3.3,0.12,7' },
  { id: 'palacio-norte', goto: '-3,-13', cam: '3.1416,0.06,12' },
  { id: 'noreste-reservado', goto: '14,-8', cam: '2.3,0.12,12' },
  { id: 'puesto-y-tablon', goto: '9,-6;8,1', cam: '1.75,0.2,8' },
  { id: 'camino-portal', goto: '15,0', cam: '1.5708,0.14,9' },
  { id: 'templo', goto: '19,2;19,12;15,16', cam: '1.2,0.02,13' },
  { id: 'desde-el-portal', goto: '27,0', cam: '-1.5708,0.22,12' },
];

const frameOf = (page: Page): Frame | undefined => page.frames().find((f) => f.url().includes('mode=plaza'));
const st = async (page: Page): Promise<any> => frameOf(page)?.evaluate(() => (window as any).__aluxState).catch(() => undefined);
const set = (page: Page, key: string, value: string) => frameOf(page)!.evaluate(([k, v]) => { (window as any)[k] = v; }, [key, value]);

/** Lo que cuesta el cuadro, ya quieto: el máximo de unas cuantas lecturas. */
async function measure(page: Page) {
  let best = { draws: 0, prims: 0, objects: 0 };
  for (let i = 0; i < 6; i++) {
    await sleep(700);
    const p = (await st(page))?.perf;
    if (p && p.draws >= best.draws) best = { draws: p.draws, prims: p.prims, objects: p.objects };
  }
  return best;
}

const browser = await launch();
const results: Record<string, unknown>[] = [];
for (const q of ['high', 'min']) {
  const page = await (await browser.newContext({ viewport: { width: 1280, height: 720 } })).newPage();
  await login(page, q === 'high' ? 'Captura' : 'Mínima');
  await page.goto(`${BASE}/plaza?debug=1&q=${q}&fs=0`);
  await waitFor('dentro de la plaza', async () => (await st(page))?.net === 'PLAYING', 300_000);
  await set(page, 'ALUX_ACTION', 'gov:off');
  await sleep(4000);
  const label = q === 'high' ? 'alta' : 'minima';
  for (const v of VIEWS) {
    if (q === 'min' && !['llegada', 'vista-general', 'casonas-sur', 'mercado'].includes(v.id)) continue;
    if (ONLY.length && !ONLY.includes(v.id)) continue;
    for (const leg of v.goto ? v.goto.split(';') : []) {
      const [x, z] = leg.split(',').map(Number);
      await set(page, 'ALUX_ZONE_GOTO', leg);
      await waitFor(`llegar a ${v.id}`, async () => { const m = (await st(page)).me; return Math.hypot(m.x - x, m.z - z) < 1.2; }, 120_000).catch(() => console.log(`  (no llegó a ${leg})`));
      await sleep(600);
    }
    if (v.cam) await set(page, 'ALUX_CAM', v.cam);
    await sleep(2500);
    const perf = await measure(page);
    const s = await st(page);
    await page.screenshot({ path: path.join(OUT, `${label}-${v.id}.png`) });
    results.push({ q: label, view: v.id, ...perf, me: [s.me.x, s.me.z], npcs: s.npcs?.length });
    console.log(`${label.padEnd(7)} ${v.id.padEnd(20)} ${String(perf.draws).padStart(4)} llamadas · ${String(perf.prims).padStart(7)} primitivas · ${String(perf.objects).padStart(4)} objetos`);
    if (v.id === 'llegada') console.log(`        escena: ${JSON.stringify(s.scene)}`);
  }
  await page.context().close();
}
fs.writeFileSync(path.join(OUT, 'medidas.json'), JSON.stringify(results, null, 1));
await browser.close();
console.log(`Capturas y medidas en ${OUT}`);
process.exit(0);
