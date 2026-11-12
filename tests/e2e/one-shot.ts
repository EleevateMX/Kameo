// Una captura real del juego en el navegador (un jugador, sesión viva contra el servidor).
//   npx tsx e2e/one-shot.ts salida.png [calidad: high|low|min] [ancho] [alto]
import { BASE, launch, login, state, waitFor } from './lib.ts';
const out = process.argv[2] || 'captura.png';
const q = process.argv[3] || 'high';
const w = Number(process.argv[4] || 1280), h = Number(process.argv[5] || 720);
const browser = await launch();
const page = await (await browser.newContext({ viewport: { width: w, height: h } })).newPage();
page.on('console', (m) => { if (m.type() === 'error') console.log('[consola]', m.text().slice(0, 300)); });
page.on('pageerror', (e) => console.log('[error]', e.message));
await login(page, 'Ixchel');
await page.click('text=Crear sala privada');
const code = (await page.textContent('.room-code'))!.trim();
await page.goto(`${BASE}/game/index.html?room=${code}&debug=1&cine=0&q=${q}`);
await waitFor('jugando', async () => (await state(page))?.net === 'PLAYING', 300_000);
const f0 = (await state(page))!.frames;
await waitFor('unos cuadros más', async () => (await state(page))!.frames >= f0 + 8, 300_000);
await page.screenshot({ path: out, timeout: 180_000 });
const s = (await state(page))!;
console.log(`captura ${out} · calidad ${s.quality} · glb=${s.glb} · ${JSON.stringify(s.perf)}`);
await browser.close();
process.exit(0);
