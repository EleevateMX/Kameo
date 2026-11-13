#!/usr/bin/env node
// Arranca todo ALUX en tu computadora: API, servidor de juego y portal.
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// Este lanzador es para tu computadora: lee .env y permite los secretos de desarrollo
try {
  const { default: dotenv } = await import('dotenv');
  dotenv.config({ path: path.join(root, '.env') });
} catch { /* sin dotenv: se usan las variables del entorno */ }
process.env.ALUX_ALLOW_DEV_SECRETS ??= '1';
const discordReady = process.env.DISCORD_CLIENT_ID && process.env.DISCORD_CLIENT_SECRET;
if (!discordReady) process.env.ALLOW_DEV_LOGIN ??= 'true';
const godot = process.env.GODOT_BIN || path.join(root, '.tools/godot');
const production = process.argv.includes('--prod');

if (!fs.existsSync(godot)) {
  console.error('Falta Godot. Ejecuta primero:  npm run setup:godot');
  process.exit(1);
}
if (!fs.existsSync(path.join(root, 'apps/portal/public/game/index.wasm'))) {
  console.log('Exportando el juego a Web por primera vez…');
  const r = spawnSync(path.join(root, 'scripts/build-game.sh'), { stdio: 'inherit' });
  if (r.status !== 0) process.exit(1);
}
if (production) {
  console.log('Compilando el portal…');
  const r = spawnSync('npm', ['run', 'build', '-w', '@alux/portal'], { cwd: root, stdio: 'inherit' });
  if (r.status !== 0) process.exit(1);
}

const colors = { api: '\x1b[36m', juego: '\x1b[33m', zona: '\x1b[32m', portal: '\x1b[35m' };
const children = [];

function run(name, cmd, args, env = {}) {
  const child = spawn(cmd, args, { cwd: root, env: { ...process.env, ...env }, detached: true });
  const tag = `${colors[name]}[${name}]\x1b[0m `;
  const pipe = (stream) => {
    let buf = '';
    stream.on('data', (d) => {
      buf += d;
      const lines = buf.split('\n');
      buf = lines.pop();
      for (const l of lines) if (l.trim()) console.log(tag + l);
    });
  };
  pipe(child.stdout);
  pipe(child.stderr);
  child.on('exit', (code) => {
    console.log(`${tag}terminó (código ${code})`);
    shutdown(code ?? 1);
  });
  children.push(child);
}

let closing = false;
function shutdown(code = 0) {
  if (closing) return;
  closing = true;
  // Cada servicio corre en su propio grupo de procesos: se cierra el grupo entero
  for (const c of children) {
    try { process.kill(-c.pid, 'SIGTERM'); } catch { /* ya terminó */ }
  }
  setTimeout(() => process.exit(code), 800);
}
process.on('SIGINT', () => shutdown(0));
process.on('SIGTERM', () => shutdown(0));

run('api', 'npm', ['run', production ? 'start' : 'dev', '-w', '@alux/api']);
run('juego', path.join(root, 'scripts/run-game-server.sh'), [], { ALUX_DEV: '1' });
// Servidor de zonas sociales (la plaza): otro proceso; las salas no dependen de él
run('zona', path.join(root, 'scripts/run-zone-server.sh'), [], { ALUX_DEV: '1' });
run('portal', 'npm', ['run', production ? 'start' : 'dev', '-w', '@alux/portal']);

console.log('\nALUX arrancando… abre http://localhost:3000 cuando el portal esté listo.\n');
