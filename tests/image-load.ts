// Consumo de la imagen única con todo funcionando a la vez: aluxes paseando por la plaza y, al
// mismo tiempo, una sesión completa del jefe en el servidor de mazmorras. Se lanza desde
// scripts/test-beta-image.sh (AFTER_UP) con la imagen levantada.
//
//   npx tsx image-load.ts https://localhost:8443 --bots 16 --container alux-beta-app
//
// Mide en el contenedor: memoria (máxima y por proceso) y CPU. No mide navegadores.
import { execFileSync, spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { ZONE_TICKET_AUDIENCE, signJwt } from '@alux/shared-contracts';
import { ZBot, sleep } from './zone-bots.ts';

const args = process.argv.slice(2);
const base = (args.find((a) => /^https?:\/\//.test(a)) || '').replace(/\/$/, '');
const flag = (name: string, fallback: string) => { const i = args.indexOf(`--${name}`); return i >= 0 ? args[i + 1] : fallback; };
const N = Number(flag('bots', '16'));
const CONTAINER = flag('container', 'alux-beta-app');
const SECRET = process.env.GAME_TICKET_SECRET || '';
const CODE = (process.env.E2E_INVITES || '').split(',')[2] || '';
if (!base || !SECRET || !CODE) { console.error('Faltan la URL, GAME_TICKET_SECRET o E2E_INVITES'); process.exit(1); }

const sh = (cmd: string) => execFileSync('docker', ['exec', CONTAINER, 'sh', '-c', cmd], { encoding: 'utf8' });
/** Memoria residente por proceso dentro del contenedor (MB), agrupada por servicio. */
function processes() {
  const out = sh(`for p in /proc/[0-9]*; do [ -r $p/status ] || continue; r=$(grep VmRSS $p/status | tr -dc 0-9); [ -n "$r" ] && echo "$r $(tr '\\0' ' ' < $p/cmdline)"; done`);
  const groups: Record<string, number> = {};
  for (const line of out.trim().split('\n')) {
    const kb = Number(line.split(' ')[0]);
    const cmd = line.slice(line.indexOf(' ') + 1);
    const name = /--zone/.test(cmd) ? 'zonas' : /--server/.test(cmd) ? 'mazmorras' : /next/.test(cmd) ? 'portal' : /tsx|src\/index/.test(cmd) ? 'api' : /caddy/.test(cmd) ? 'proxy' : 'otros';
    groups[name] = (groups[name] ?? 0) + kb / 1024;
  }
  return groups;
}
/** Memoria y CPU del contenedor según el propio cgroup (lo que cuenta para el límite). */
function cgroup() {
  const mem = Number(sh('cat /sys/fs/cgroup/memory.current 2>/dev/null || cat /sys/fs/cgroup/memory/memory.usage_in_bytes').trim()) / 1048576;
  // cgroup v2 da microsegundos en cpu.stat; v1, nanosegundos en cpuacct.usage
  const raw = sh('cat /sys/fs/cgroup/cpu.stat 2>/dev/null || echo "ns $(cat /sys/fs/cgroup/cpuacct/cpuacct.usage)"');
  const cpu = /usage_usec (\d+)/.test(raw) ? Number(/usage_usec (\d+)/.exec(raw)![1]) / 1e6 : Number(/ns (\d+)/.exec(raw)?.[1] ?? 0) / 1e9;
  return { mem, cpu };
}
const fmt = (g: Record<string, number>) => Object.entries(g).sort((a, b) => b[1] - a[1]).map(([k, v]) => `${k} ${v.toFixed(0)}`).join(' · ');

const idle = cgroup();
console.log(`En reposo: ${idle.mem.toFixed(0)} MB · por proceso (MB): ${fmt(processes())}`);

// ── Plaza: N aluxes paseando juntos (el peor caso: todos se ven) ──
const bots: ZBot[] = [];
for (let i = 0; i < N; i++) {
  const bot = new ZBot(randomUUID(), `Alux ${i + 1}`, `${base.replace(/^http/, 'ws')}/zone`);
  await bot.connect(signJwt({ aud: ZONE_TICKET_AUDIENCE, sub: bot.id, jti: randomUUID(), zone: 'merida', name: bot.name, color: '#2ec4a6', hat: i % 7, look: [i % 4, i % 5, i % 5, i % 10, i % 5] }, SECRET, 120));
  if (!bot.welcome) { console.error(`el alux ${i + 1} no pudo entrar: ${bot.error?.code}`); process.exit(1); }
  bots.push(bot);
}
let walking = true;
const strolls = bots.map(async (bot) => {
  while (walking) {
    const a = Math.random() * Math.PI * 2, r = 4 + Math.random() * 6;
    const target = { x: Math.sin(a) * r, z: 13 + Math.cos(a) * r * 0.6 };
    const end = Date.now() + 2500 + Math.random() * 2500;
    let next = Date.now();
    while (walking && Date.now() < end) {
      const p = bot.pos(), dx = target.x - p.x, dz = target.z - p.z, d = Math.hypot(dx, dz);
      bot.seq++;
      bot.send({ t: 'in', s: bot.seq, x: d > 0.6 ? dx / d : 0, z: d > 0.6 ? dz / d : 0, j: 0, r: Math.atan2(dx, dz) });
      next += 50;
      await sleep(Math.max(0, next - Date.now()));
    }
  }
});

// ── A la vez: una sesión completa del jefe en el servidor de mazmorras ──
const boss = spawn('npx', ['tsx', 'beta-boss.ts', base, '--code', CODE], { cwd: import.meta.dirname, env: process.env });
let bossLog = '';
boss.stdout.on('data', (d) => { bossLog += d; });
boss.stderr.on('data', (d) => { bossLog += d; });
const bossDone = new Promise<number>((resolve) => boss.on('exit', (c) => resolve(c ?? 1)));

let peak = idle.mem, peakProc: Record<string, number> = {}, samples = 0;
const c0 = cgroup(), t0 = Date.now();
let finished = false;
bossDone.then(() => { finished = true; });
while (!finished) {
  await sleep(2000);
  const now = cgroup();
  samples++;
  if (now.mem > peak) { peak = now.mem; peakProc = processes(); }
}
const c1 = cgroup(), secs = (Date.now() - t0) / 1000;
const code = await bossDone;
walking = false;
await Promise.all(strolls);
const alive = bots.filter((b) => !b.closed).length;
const kb = bots.reduce((s, b) => s + b.bytesIn, 0) / 1024 / bots.length / (secs + 1);
for (const b of bots) b.close();

console.log(bossLog.split('\n').filter((l) => /^[✓✗]/.test(l)).map((l) => l.slice(0, 150)).join('\n'));
console.log(`Con ${N} aluxes en la plaza y una partida completa del jefe a la vez (${secs.toFixed(0)} s, ${samples} muestras):`);
console.log(`  memoria máxima del contenedor: ${peak.toFixed(0)} MB · por proceso en ese momento (MB): ${fmt(peakProc)}`);
console.log(`  CPU media del contenedor: ${(((c1.cpu - c0.cpu) / secs) * 100).toFixed(0)} % de un núcleo`);
console.log(`  plaza: ${alive} de ${N} siguen conectados · ${kb.toFixed(1)} KB/s recibe cada uno`);
if (code !== 0 || alive !== N) { console.error('La carga combinada falló.'); process.exit(1); }
process.exit(0);
