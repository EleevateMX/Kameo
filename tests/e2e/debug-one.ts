// Herramienta de depuración: abre un cliente, lo recarga y muestra consola y estado.
import { chromium } from 'playwright';
const BASE = process.env.E2E_BASE_URL || 'http://localhost:3000';
const out = process.argv[2] || 'debug.png';
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const page = await (await browser.newContext({ viewport: { width: 640, height: 360 } })).newPage();
page.on('console', (m) => { if (!/Godot Engine|OpenGL|Build conf/.test(m.text())) console.log('[console]', m.type(), m.text().slice(0, 300)); });
page.on('pageerror', (e) => console.log('[pageerror]', e.message));
page.on('requestfailed', (r) => console.log('[requestfailed]', r.url().slice(0, 120), r.failure()?.errorText));
page.on('response', (r) => { if (r.url().includes('/api/')) console.log('[api]', r.status(), r.url().slice(-40)); });
await page.goto(BASE);
await page.fill('#dev-name', 'Depurador');
await Promise.all([page.waitForURL('**/hub'), page.click('.dev-login button')]);
await page.click('text=Crear sala privada');
const code = (await page.textContent('.room-code'))!.trim();
const url = `${BASE}/game/index.html?room=${code}&debug=1&cine=0&q=low`;
const watch = async (label: string) => {
  for (let i = 0; i < 10; i++) {
    await new Promise((r) => setTimeout(r, 3000));
    const s = await page.evaluate(() => JSON.stringify({ st: (window as any).__aluxState, alux: (window as any).ALUX }));
    console.log(label, i, s.slice(0, 260));
    if (s.includes('PLAYING')) return;
  }
};
await page.goto(url);
await watch('carga 1');
await page.goto('about:blank');
await new Promise((r) => setTimeout(r, 1500));
await page.goto(url);
await watch('carga 2');
await page.screenshot({ path: out });
await browser.close();
