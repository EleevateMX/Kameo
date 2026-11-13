// Carga del servidor de zonas: N aluxes simulados paseando por la plaza, y lo que cuesta.
//
//   npx tsx zone-load.ts [8 16 32 …] [--secs 30] [--out archivo.json] [--zone camino_motul]
//
// Con `--zone camino_motul` los aluxes pasean por el Camino a Motul (222 m, con criaturas que
// el servidor simula) y lanzan su chispa de vez en cuando: «juntos» es todos en el primer tramo
// abierto, junto a las criaturas; «repartidos», a lo largo de todo el camino.
//
// Por cada N se hacen dos pasadas: «juntos» (todos alrededor del árbol: el peor caso, todos se
// ven) y «repartidos» (por toda la plaza). Se mide, ya con todos dentro y moviéndose:
//   · servidor: CPU del proceso (% de un núcleo), memoria residente, coste medio y máximo de un paso
//   · red: bytes por segundo que recibe cada alux y estados por segundo
//   · interés: cuántos vecinos ve cada uno (media y máximo)
// No mide el navegador: eso lo hace la prueba de la plaza en navegador.
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { ZONE_TICKET_AUDIENCE, signJwt } from '@alux/shared-contracts';
import { ZBot, sleep, until } from './zone-bots.ts';

const ROOT = path.resolve(import.meta.dirname, '..');
const GODOT = process.env.GODOT_BIN || path.join(ROOT, '.tools/godot');
const SECRET = 'zone-load-secret-123456';
const args = process.argv.slice(2);
const flag = (name: string, fallback: string) => { const i = args.indexOf(`--${name}`); return i >= 0 ? args[i + 1] : fallback; };
const SECS = Number(flag('secs', '30'));
const OUT = flag('out', '');
const ZONE = flag('zone', 'merida');
const ROAD: [number, number][] = [[0, 0], [26, -4], [52, -16], [78, -20], [104, -34], [128, -52], [154, -58], [180, -72], [204, -80]];
/** Un punto del camino a `t` (0–1) de su largo, desplazado `side` metros a un lado. */
function roadAt(t: number, side: number) {
  const seg = Math.min(ROAD.length - 2, Math.floor(t * (ROAD.length - 1)));
  const k = t * (ROAD.length - 1) - seg;
  const [x0, z0] = ROAD[seg], [x1, z1] = ROAD[seg + 1];
  const len = Math.hypot(x1 - x0, z1 - z0);
  return { x: x0 + (x1 - x0) * k - (z1 - z0) / len * side, z: z0 + (z1 - z0) * k + (x1 - x0) / len * side };
}
const sizes = args.filter((a, i) => /^\d+$/.test(a) && !['--secs', '--out', '--zone'].includes(args[i - 1])).map(Number);
const SIZES = sizes.length ? sizes : [8, 16, 32];
const CLOCK = 100;   // jiffies por segundo en Linux

const cpuTicks = (pid: number) => { const f = fs.readFileSync(`/proc/${pid}/stat`, 'utf8').split(') ')[1].split(' '); return Number(f[11]) + Number(f[12]); };
const rssMb = (pid: number) => Number(/VmRSS:\s+(\d+)/.exec(fs.readFileSync(`/proc/${pid}/status`, 'utf8'))![1]) / 1024;

async function run(n: number, together: boolean) {
  const port = 19900 + Math.floor(Math.random() * 300);
  const godot = spawn(GODOT, ['--headless', '--path', path.join(ROOT, 'game'), '--', '--zone', `--port=${port}`], {
    env: { ...process.env, ALUX_TICKET_SECRET: SECRET, ALUX_ZONE_CAPACITY: String(n), ALUX_DEV: '1', ALUX_API_URL: '' },
  });
  let log = '';
  godot.stdout!.on('data', (d) => { log += d; });
  godot.stderr!.on('data', (d) => { log += d; });
  await until('el servidor arranca', () => log.includes('escuchando'), 30_000);
  const bots: ZBot[] = [];
  for (let i = 0; i < n; i++) {
    const bot = new ZBot(randomUUID(), `Alux ${i + 1}`, `ws://127.0.0.1:${port}`);
    await bot.connect(signJwt({ aud: ZONE_TICKET_AUDIENCE, sub: bot.id, jti: randomUUID(), zone: ZONE, name: bot.name, color: '#2ec4a6', hat: i % 7, look: [i % 4, i % 5, i % 5, i % 10, i % 5] }, SECRET, 60));
    if (!bot.welcome) throw new Error(`el alux ${i + 1} no pudo entrar: ${bot.error?.code}`);
    bots.push(bot);
  }
  // Cada alux pasea: elige un punto, anda hasta él, se para un momento y elige otro
  let walking = true;
  const stroll = async (bot: ZBot) => {
    while (walking) {
      const a = Math.random() * Math.PI * 2;
      const r = together ? 4 + Math.random() * 6 : 6 + Math.random() * 26;
      let target = together ? { x: Math.sin(a) * r, z: 13 + Math.cos(a) * r * 0.6 } : { x: Math.sin(a) * r, z: Math.cos(a) * r };
      if (ZONE === 'camino_motul') target = roadAt(together ? 0.15 + Math.random() * 0.15 : Math.random(), (Math.random() - 0.5) * 12);
      const end = Date.now() + 2500 + Math.random() * 2500;
      let next = Date.now();
      while (walking && Date.now() < end) {
        const p = bot.pos();
        const dx = target.x - p.x, dz = target.z - p.z, d = Math.hypot(dx, dz);
        bot.seq++;
        bot.send({ t: 'in', s: bot.seq, x: d > 0.6 ? dx / d : 0, z: d > 0.6 ? dz / d : 0, j: Math.random() < 0.01 ? 1 : 0, r: Math.atan2(dx, dz), e: bot.epoch });
        if (ZONE === 'camino_motul' && Math.random() < 0.05) bot.send({ t: 'atk', r: Math.random() * 6.28 - 3.14 });
        next += 50;
        await sleep(Math.max(0, next - Date.now()));
      }
    }
  };
  const strolls = bots.map(stroll);
  await sleep(6000);   // que se repartan y el servidor llegue a régimen
  const pid = godot.pid!;
  const cpu0 = cpuTicks(pid), t0 = Date.now();
  const bytes0 = bots.map((b) => b.bytesIn), states0 = bots.map((b) => b.statesIn);
  let visSum = 0, visMax = 0, visN = 0, tickAvg = 0, tickMax = 0, outKb = 0, statsN = 0;
  const end = Date.now() + SECS * 1000;
  while (Date.now() < end) {
    await sleep(1000);
    for (const b of bots) { visSum += b.visible(); visN++; visMax = Math.max(visMax, b.visible()); }
    bots[0].send({ t: 'stats' });
    const st = bots[0].stats;
    if (st && st.players === n && st.tick_avg_ms > 0) { tickAvg += st.tick_avg_ms; tickMax = Math.max(tickMax, st.tick_max_ms); outKb += st.bytes_out_s / 1024; statsN++; bots[0].stats = null; }
  }
  const secs = (Date.now() - t0) / 1000;
  const result = {
    aluxes: n, zona: ZONE, reparto: together ? 'juntos' : 'repartidos', segundos: Math.round(secs),
    cpu_pct: +(100 * (cpuTicks(pid) - cpu0) / CLOCK / secs).toFixed(1),
    memoria_mb: +rssMb(pid).toFixed(0),
    paso_ms: +(tickAvg / Math.max(statsN, 1)).toFixed(3), paso_max_ms: +tickMax.toFixed(2),
    salida_kb_s: +(outKb / Math.max(statsN, 1)).toFixed(1),
    por_alux_kb_s: +(bots.reduce((a, b, i) => a + (b.bytesIn - bytes0[i]), 0) / n / secs / 1024).toFixed(2),
    estados_s: +(bots.reduce((a, b, i) => a + (b.statesIn - states0[i]), 0) / n / secs).toFixed(1),
    vecinos_media: +(visSum / Math.max(visN, 1)).toFixed(1), vecinos_max: visMax,
    desconectados: bots.filter((b) => b.closed).length,
    errores_servidor: (log.match(/ERROR/g) ?? []).length,
  };
  walking = false;
  await Promise.all(strolls);
  for (const b of bots) b.close();
  godot.kill();
  await sleep(500);
  return result;
}

const rows: Awaited<ReturnType<typeof run>>[] = [];
for (const n of SIZES) {
  for (const together of [true, false]) {
    const r = await run(n, together);
    rows.push(r);
    console.log(`${String(r.aluxes).padStart(3)} ${r.reparto.padEnd(10)} · servidor: ${r.cpu_pct} % de un núcleo, ${r.memoria_mb} MB, paso ${r.paso_ms} ms (máx. ${r.paso_max_ms}) · ` +
      `cada alux recibe ${r.por_alux_kb_s} KB/s y ${r.estados_s} estados/s · ve ${r.vecinos_media} vecinos (máx. ${r.vecinos_max}) · desconectados ${r.desconectados} · errores ${r.errores_servidor}`);
  }
}
if (OUT) fs.writeFileSync(OUT, JSON.stringify(rows, null, 2));
console.log('\n| Aluxes | Reparto | CPU del servidor | Memoria | Paso medio / máx. | Salida total | Recibe cada alux | Estados/s | Vecinos (media / máx.) |');
console.log('| --- | --- | --- | --- | --- | --- | --- | --- | --- |');
for (const r of rows) console.log(`| ${r.aluxes} | ${r.reparto} | ${r.cpu_pct} % de un núcleo | ${r.memoria_mb} MB | ${r.paso_ms} / ${r.paso_max_ms} ms | ${r.salida_kb_s} KB/s | ${r.por_alux_kb_s} KB/s | ${r.estados_s} | ${r.vecinos_media} / ${r.vecinos_max} |`);
process.exit(rows.some((r) => r.desconectados > 0 || r.errores_servidor > 0) ? 1 : 0);
