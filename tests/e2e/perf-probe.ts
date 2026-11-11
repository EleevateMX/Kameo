// Mide los cuadros por segundo reales de un cliente (contando cuadros, no el contador del motor).
//   npx tsx e2e/perf-probe.ts [ancho] [alto] [parámetros extra, p. ej. "&q=low"]
import { BASE, launch, login, sleep, state, waitFor } from './lib.ts';
const w = Number(process.argv[2] || 640), h = Number(process.argv[3] || 360), extra = process.argv[4] || '';
const browser = await launch();
const page = await (await browser.newContext({ viewport: { width: w, height: h } })).newPage();
await login(page, 'Medidor');
await page.click('text=Crear sala privada');
const code = (await page.textContent('.room-code'))!.trim();
await page.goto(`${BASE}/game/index.html?room=${code}&debug=1${extra}`);
await waitFor('jugando', async () => (await state(page))?.net === 'PLAYING', 240_000);
await sleep(8000);
const a = (await state(page))!; const t0 = Date.now();
await sleep(15000);
const b = (await state(page))!; const secs = (Date.now() - t0) / 1000;
console.log(`${w}x${h}${extra} · ${((b.frames - a.frames) / secs).toFixed(2)} FPS reales · glb=${b.glb} · dibujados=${b.perf.draws} · triángulos=${(b.perf as any).tris} · objetos=${(b.perf as any).objects} · ping=${b.perf.ping} ms · JS ${b.perf.heap} MB`);
await browser.close();
process.exit(0);
