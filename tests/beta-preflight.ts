// Revisión previa a publicar en la rama `beta` (lo que Render despliega). No toca nada:
// sólo lee el repositorio y dice si es seguro publicar el commit actual.
//
//   npm run beta:preflight
//
// Comprueba que render.yaml crea exactamente los dos recursos acordados, que no hay
// secretos en Git (archivos ni historial), que la imagen no trae accesos de prueba
// abiertos, que las invitaciones se validan bien y que ninguna migración borra datos.
// Termina con código de salida 1 si algo no cuadra.
import assert from 'node:assert/strict';
import { execSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { betaAccessEnabled, findInvite, generateInviteCode, hashInviteCode, inviteActive, parseBetaInvites } from '@alux/shared-contracts';

const ROOT = path.resolve(import.meta.dirname, '..');
const read = (p: string) => fs.readFileSync(path.join(ROOT, p), 'utf8');
const git = (cmd: string) => execSync(`git ${cmd}`, { cwd: ROOT, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
let failed = 0;

function step(name: string, fn: () => string | void) {
  try {
    const note = fn();
    console.log(`✓ ${name}${note ? `  ·  ${note}` : ''}`);
  } catch (err) {
    failed++;
    console.log(`✗ ${name}\n    ${(err as Error).message.split('\n').slice(0, 4).join('\n    ')}`);
  }
}

// ── 1) render.yaml: exactamente los dos recursos acordados ──
/** Lectura mínima del Blueprint: bloques de primer nivel y, dentro, cada elemento de lista con sus claves simples. */
function parseBlueprint(text: string) {
  const top: Record<string, Record<string, string>[]> = {};
  let section = '';
  let item: Record<string, string> | null = null;
  let itemIndent = -1;
  for (const raw of text.split('\n')) {
    const line = raw.replace(/\s+#.*$/, '').replace(/^#.*$/, '');
    if (!line.trim()) continue;
    const indent = line.length - line.trimStart().length;
    const mTop = /^([A-Za-z]+):\s*$/.exec(line);
    if (indent === 0 && mTop) { section = mTop[1]; top[section] = []; item = null; continue; }
    if (indent === 0) throw new Error(`render.yaml: línea de primer nivel inesperada: ${line}`);
    const mItem = /^(\s*)-\s+([A-Za-z]+):\s*(.*)$/.exec(line);
    if (mItem && (item === null || mItem[1].length <= itemIndent)) {
      item = { [mItem[2]]: mItem[3].trim() };
      itemIndent = mItem[1].length;
      top[section].push(item);
      continue;
    }
    const mKey = /^\s*([A-Za-z]+):\s*(.*)$/.exec(line);
    if (item && mKey && indent === itemIndent + 2) item[mKey[1]] = mKey[2].trim().replace(/^"(.*)"$/, '$1');
  }
  return top;
}

step('render.yaml crea sólo los dos recursos acordados', () => {
  const text = read('render.yaml');
  const bp = parseBlueprint(text);
  assert.deepEqual(Object.keys(bp).sort(), ['databases', 'services'], 'el Blueprint sólo debe tener services y databases');
  assert.equal(bp.services.length, 1, `hay ${bp.services.length} servicios`);
  assert.equal(bp.databases.length, 1, `hay ${bp.databases.length} bases de datos`);
  const s = bp.services[0];
  const want = { type: 'web', name: 'alux-beta', runtime: 'docker', plan: '0.5c-512mb', region: 'ohio', branch: 'beta',
    autoDeployTrigger: 'commit', healthCheckPath: '/healthz', dockerfilePath: './infra/render/Dockerfile' };
  for (const [k, v] of Object.entries(want)) assert.equal(s[k], v, `servicio: ${k} es «${s[k]}», se esperaba «${v}»`);
  const d = bp.databases[0];
  const wantDb = { name: 'alux-beta-db', plan: '0.1c-256mb', diskSizeGB: '1', region: 'ohio', postgresMajorVersion: '16', ipAllowList: '[]' };
  for (const [k, v] of Object.entries(wantDb)) assert.equal(d[k], v, `base de datos: ${k} es «${d[k]}», se esperaba «${v}»`);
  // Variables: los secretos los genera Render o se escriben en su panel; ninguno lleva valor aquí
  const envBlock = text.slice(text.indexOf('envVars:'), text.indexOf('databases:'))
    .split('\n').map((l) => l.replace(/\s+#.*$/, '')).filter((l) => l.trim() && !l.trim().startsWith('#')).join('\n') + '\n';
  const keys = [...envBlock.matchAll(/^\s*- key: (\w+)\n((?:\s{8}.*\n)*)/gm)].map((m) => ({ key: m[1], body: m[2] }));
  const byKey = Object.fromEntries(keys.map((k) => [k.key, k.body]));
  assert.deepEqual(keys.map((k) => k.key).sort(), ['BETA_ACCESS', 'BETA_INVITES', 'DATABASE_URL', 'GAME_TICKET_SECRET', 'SERVICE_KEY', 'SESSION_SECRET']);
  for (const k of ['SESSION_SECRET', 'GAME_TICKET_SECRET', 'SERVICE_KEY']) assert.match(byKey[k], /generateValue: true/, `${k} debe generarlo Render`);
  assert.match(byKey.BETA_INVITES, /sync: false/, 'BETA_INVITES se escribe en el panel');
  assert.match(byKey.DATABASE_URL, /fromDatabase:[\s\S]*name: alux-beta-db/, 'DATABASE_URL viene de alux-beta-db');
  assert.match(byKey.BETA_ACCESS, /value: invite/);
  assert.equal(keys.filter((k) => /\bvalue:/.test(k.body)).length, 1, 'sólo BETA_ACCESS lleva un valor escrito');
  return 'alux-beta (Docker, 0.5c-512mb, Ohio) + alux-beta-db (PostgreSQL 16, 0.1c-256mb, 1 GB, Ohio, sin acceso externo)';
});

// ── 2) Sin secretos en Git ──
const SECRET_PATTERNS: [string, RegExp][] = [
  ['clave privada', /-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----/],
  ['cadena de conexión con contraseña', /postgres(?:ql)?:\/\/[^\s:@/"'`$<{]+:(?!alux(?:-prueba-local)?@|pass(?:word)?@|pw@|\$|<|\{|\.\.\.|…)[^\s@/"'`$<{]{6,}@(?!localhost|127\.0\.0\.1|db[:/]|alux-beta-db)/],
  ['secreto de Discord', /DISCORD_CLIENT_SECRET\s*[=:]\s*["']?[A-Za-z0-9_-]{24,}/],
  // (formato de archivo .env o de consola; las constantes de las pruebas no son secretos reales)
  ['secreto con valor', /^(?:export\s+)?(?:SESSION_SECRET|GAME_TICKET_SECRET|SERVICE_KEY|DISCORD_CLIENT_SECRET)=["']?[A-Za-z0-9+/=_:@.-]{24,}/m],
  ['token de servicio', /\b(?:rnd_[A-Za-z0-9]{20,}|sbp_[a-f0-9]{30,}|ghp_[A-Za-z0-9]{30,}|sk-[A-Za-z0-9]{30,})\b/],
  ['huellas de invitaciones reales', /BETA_INVITES\s*[=:]\s*["']?[a-z0-9-]+:[0-9a-f]{64}:/],
];
// Códigos de ejemplo que aparecen en pruebas y documentación (no abren nada)
const FAKE_CODES = /ALUX-(?:AAAAA-(?:AAAAA|BBBBB)|ZZZZZ-ZZZZZ|XXXXX-XXXXX)/;
const INVITE_CODE = /ALUX(?:-[A-HJ-NP-Z2-9]{5}){4}/g;

function scan(label: string, text: string, where: (index: number) => string): string[] {
  const hits: string[] = [];
  for (const [name, re] of SECRET_PATTERNS) {
    const m = re.exec(text);
    if (m) hits.push(`${name} en ${where(m.index)}`);
  }
  for (const m of text.matchAll(INVITE_CODE)) {
    if (!FAKE_CODES.test(m[0])) hits.push(`código de invitación en ${where(m.index!)}`);
  }
  return hits.map((h) => `${label}: ${h}`);
}

step('El detector de secretos reconoce lo que debe', () => {
  // Muestras armadas en el momento (así este archivo no contiene ninguna de verdad)
  const samples = [
    ['SESSION', '_SECRET=', 'q'.repeat(40)].join(''),
    ['postgres', 'ql://alux:', 'Xy7'.repeat(6), '@dpg-abc123.ohio-postgres.render.com/alux'].join(''),
    ['-----BEGIN ', 'PRIVATE KEY-----'].join(''),
    generateInviteCode(),
    ['BETA_INVITES=ana:', 'a'.repeat(64), ':2026-12-31'].join(''),
  ];
  for (const sample of samples) assert.equal(scan('muestra', sample, () => 'x').length > 0, true, `no detectó: ${sample.slice(0, 24)}…`);
  for (const harmless of ['SESSION_SECRET=', 'postgres://alux:alux@localhost:5432/alux_test', 'ALUX-XXXXX-XXXXX-XXXXX-XXXXX', 'DATABASE_URL=postgres://…']) {
    assert.deepEqual(scan('muestra', harmless, () => 'x'), [], `falso positivo con: ${harmless}`);
  }
  return `${samples.length} muestras detectadas, sin falsos positivos en los ejemplos de la documentación`;
});

step('Sin secretos en los archivos versionados', () => {
  const files = git('ls-files').split('\n').filter(Boolean);
  const forbidden = files.filter((f) => /(^|\/)\.env(\.|$)(?!example)|\.pem$|\.key$|(^|\/)backups\/|\.dump$|infra\/docker\/certs\/.*\.crt$/.test(f) && !f.endsWith('.env.example'));
  assert.deepEqual(forbidden, [], `archivos que no deberían estar en Git: ${forbidden.join(', ')}`);
  const hits: string[] = [];
  let scanned = 0;
  for (const f of files) {
    if (/\.(png|jpg|jpeg|glb|wav|ttf|ico|woff2?|pck|wasm)$/i.test(f) || f === 'package-lock.json') continue;
    const text = read(f);
    scanned++;
    hits.push(...scan(f, text, (i) => `línea ${text.slice(0, i).split('\n').length}`));
  }
  assert.deepEqual(hits, [], hits.slice(0, 6).join('\n    '));
  for (const line of ['.env', 'backups/', 'infra/docker/certs/*.crt', '.env.deploy-test']) {
    assert.ok(read('.gitignore').split('\n').includes(line), `.gitignore debe excluir ${line}`);
  }
  return `${scanned} archivos de texto revisados; .env, certificados y respaldos están excluidos`;
});

step('Sin secretos en el historial de Git', () => {
  // Todo lo que alguna vez se añadió en los commits que se van a publicar
  const added = git('log -p --no-color --format=%H HEAD').split('\n').filter((l) => l.startsWith('+') && !l.startsWith('+++'))
    .map((l) => l.slice(1)).join('\n');
  const hits = scan('historial', added, () => 'una línea añadida en algún commit');
  assert.deepEqual(hits, [], hits.slice(0, 6).join('\n    '));
  const everTracked = new Set(git('log --name-only --format= HEAD').split('\n').filter(Boolean));
  const bad = [...everTracked].filter((f) => /(^|\/)\.env$|(^|\/)\.env\.(?!example)|\.pem$|\.dump$|infra\/docker\/certs\/.*\.crt$/.test(f));
  assert.deepEqual(bad, [], `archivos sensibles que estuvieron en Git: ${bad.join(', ')}`);
  return `${git('rev-list --count HEAD').trim()} commits revisados`;
});

// ── 3) La imagen no trae accesos de prueba abiertos ──
step('La imagen desplegada no deja accesos de prueba abiertos', () => {
  const start = read('infra/render/start.sh');
  assert.match(start, /export ALLOW_DEV_LOGIN=false/, 'el arranque debe forzar ALLOW_DEV_LOGIN=false');
  assert.match(start, /unset ALUX_ALLOW_DEV_SECRETS/, 'el arranque debe impedir los secretos de desarrollo');
  assert.match(start, /export NODE_ENV=production/);
  for (const name of ['SESSION_SECRET', 'GAME_TICKET_SECRET', 'SERVICE_KEY']) assert.ok(start.includes(name), `el arranque debe exigir ${name}`);
  assert.match(start, /API_HOST=127\.0\.0\.1/, 'la API debe escuchar sólo dentro del contenedor');
  assert.match(start, /ALUX_BIND=127\.0\.0\.1/, 'el servidor de juego debe escuchar sólo dentro del contenedor');
  assert.match(start, /next start apps\/portal -H 127\.0\.0\.1/, 'el portal debe escuchar sólo dentro del contenedor');
  const yaml = read('render.yaml');
  assert.ok(!/ALLOW_DEV_LOGIN|ALUX_ALLOW_DEV_SECRETS|ALUX_ALLOW_FILE_STORE/.test(yaml), 'render.yaml no debe activar modos de prueba');
  const env = read('apps/portal/lib/env.ts');
  assert.match(env, /!discordEnabled && process\.env\.NODE_ENV !== 'production'/, 'la entrada de prueba debe estar apagada en producción');
  const caddy = read('infra/render/Caddyfile');
  assert.ok(!/internal/.test(caddy.replace(/#.*$/gm, '')), 'el proxy no debe enrutar /internal');
  assert.match(caddy, /handle_path \/api\/v1\/\*/, 'el proxy sólo debe exponer /api/v1');
  assert.match(caddy, /admin off/);
  const secrets = read('packages/shared-contracts/src/secrets.ts');
  assert.match(secrets, /NODE_ENV === 'production'[\s\S]*throw new Error/, 'en producción no deben valer los secretos de desarrollo');
  return 'entrada de prueba apagada, secretos de desarrollo rechazados, servicios internos sólo en 127.0.0.1, /internal sin exponer';
});

// ── 4) Invitaciones individuales ──
step('Invitaciones individuales: sólo entra el código vigente de cada tester', () => {
  const day = (offset: number) => new Date(Date.now() + offset * 86_400_000).toISOString().slice(0, 10);
  const codes = [generateInviteCode(), generateInviteCode(), generateInviteCode()];
  assert.equal(new Set(codes).size, 3, 'cada código debe ser distinto');
  const raw = `ana:${hashInviteCode(codes[0])}:${day(14)}:Ana,luis:${hashInviteCode(codes[1])}:${day(14)}:Luis,vencida:${hashInviteCode(codes[2])}:${day(-2)}:Vencida`;
  assert.ok(!raw.includes(codes[0].replace(/-/g, '')) && !raw.includes(codes[0]), 'el valor del servidor no debe contener los códigos');
  const { invites, rejected } = parseBetaInvites(raw);
  assert.equal(invites.length, 3);
  assert.equal(rejected, 0);
  assert.equal(findInvite(invites, codes[0])?.id, 'ana');
  assert.equal(findInvite(invites, codes[1])?.id, 'luis');
  assert.equal(findInvite(invites, codes[2]), null, 'una invitación vencida no entra');
  assert.equal(findInvite(invites, generateInviteCode()), null, 'un código que no es de nadie no entra');
  assert.equal(findInvite(invites, codes[0].slice(0, -1)), null, 'un código incompleto no entra');
  assert.equal(inviteActive(invites, 'ana'), true);
  assert.equal(inviteActive(invites, 'vencida'), false);
  assert.equal(inviteActive(parseBetaInvites(raw.split(',').slice(1).join(',')).invites, 'ana'), false, 'al retirar una invitación, su sesión deja de valer');
  const env = { BETA_ACCESS: 'invite', BETA_INVITES: raw };
  assert.equal(betaAccessEnabled(env), true);
  assert.equal(betaAccessEnabled({ ...env, DISCORD_CLIENT_ID: 'x', DISCORD_CLIENT_SECRET: 'y' }), false, 'con Discord el acceso por invitación se apaga');
  assert.equal(betaAccessEnabled({ BETA_ACCESS: 'invite', BETA_INVITES: '' }), false, 'sin invitaciones no entra nadie');
  assert.equal(betaAccessEnabled({ BETA_INVITES: raw }), false, 'sin BETA_ACCESS=invite no entra nadie');
  const route = read('apps/portal/app/auth/beta/route.ts');
  assert.match(route, /if \(!betaLoginEnabled\) return back\('beta_desactivada'\)/);
  assert.match(route, /blocked\(`ip:\$\{ip\}`, MAX_PER_IP\)/, 'la ruta debe limitar los intentos fallidos por IP');
  assert.match(read('apps/api/src/app.ts'), /claims\.inv !== undefined && !\(config\.betaEnabled && inviteActive/, 'la API debe rechazar sesiones de invitaciones retiradas');
  return 'códigos únicos de 100 bits, el servidor sólo guarda huellas, vencen, se pueden retirar y se apagan con Discord';
});

// ── 5) Migraciones sin modificaciones destructivas ──
step('Las migraciones no borran ni alteran datos existentes', () => {
  const dir = path.join(ROOT, 'supabase/migrations');
  const files = fs.readdirSync(dir).filter((f) => f.endsWith('.sql')).sort();
  assert.ok(files.length >= 2);
  const notes: string[] = [];
  for (const f of files) {
    const sql = fs.readFileSync(path.join(dir, f), 'utf8').replace(/--.*$/gm, '').replace(/\/\*[\s\S]*?\*\//g, '');
    const bad = sql.match(/\b(drop\s+(table|column|schema|database|index|type|function)|truncate|delete\s+from|update\s+\w+\s+set|alter\s+table\s+\w+\s+(alter|rename)|alter\s+column|rename\s+(to|column))\b[^;]*/gi);
    assert.equal(bad, null, `${f} contiene: ${bad?.join(' | ')}`);
    const statements = sql.split(';').map((s) => s.trim().replace(/\s+/g, ' ')).filter(Boolean);
    const kinds = new Map<string, number>();
    for (const st of statements) {
      const kind = /^create table if not exists/i.test(st) ? 'crea tabla' : /^create index if not exists/i.test(st) ? 'crea índice'
        : /^alter table \w+ enable row level security/i.test(st) ? 'activa RLS' : /^alter table \w+ drop constraint if exists \w+_check$/i.test(st) ? 'quita una restricción CHECK'
        : /^alter table \w+ add constraint \w+_check check/i.test(st) ? 'añade una restricción CHECK' : /^create extension if not exists/i.test(st) ? 'activa extensión'
        // una columna nueva con valor por defecto no toca lo que ya había en las filas
        : /^alter table \w+ add column if not exists \w+ [\w ]+ default [^;]+$/i.test(st) ? 'añade una columna con valor por defecto' : '';
      assert.ok(kind, `${f}: sentencia fuera de lo permitido: ${st.slice(0, 90)}`);
      kinds.set(kind, (kinds.get(kind) ?? 0) + 1);
    }
    notes.push(`${f.replace(/\.sql$/, '')}: ${[...kinds].map(([k, n]) => `${n}× ${k}`).join(', ')}`);
  }
  // La única restricción que se cambia se sustituye por otra más amplia: no invalida filas existentes
  const beta = fs.readFileSync(path.join(dir, files[1]), 'utf8');
  assert.match(beta, /check \(provider in \('discord', 'dev', 'beta'\)\)/, "la restricción nueva debe seguir admitiendo 'discord' y 'dev'");
  const look = files.find((f) => f.endsWith('_look.sql'));
  if (look) assert.match(fs.readFileSync(path.join(dir, look), 'utf8'), /check \(hat between 0 and \d\d\)/, 'el límite nuevo del tocado debe seguir admitiendo los cuatro de antes');
  assert.match(read('apps/api/src/migrate.ts'), /ALLOW_DESTRUCTIVE_MIGRATIONS !== '1'/, 'el migrador debe negarse a borrar datos sin permiso');
  return `\n    ${notes.join('\n    ')}`;
});

// ── 6) Vídeos de las cinemáticas: los definitivos, completos y declarados ──
step('Vídeos de las cinemáticas: definitivos, completos y sin material de prueba', () => {
  const dir = 'game/web/static/video';
  const sha = (file: string) => createHash('sha256').update(fs.readFileSync(file)).digest('hex');
  const manifest = JSON.parse(read(`${dir}/manifest.json`)) as { clips: Record<string, { src: Record<string, string>; dur: number; v?: string }> };
  const tracked = new Set(git(`ls-files ${dir}`).split('\n').filter(Boolean).map((f) => path.basename(f)));
  // Los vídeos de prueba (patrones de franjas) viven en tests/fixtures: ninguno puede colarse en el juego
  const fixtures = path.join(ROOT, 'tests/fixtures/video');
  const testHashes = new Set(fs.existsSync(fixtures) ? fs.readdirSync(fixtures).map((f) => sha(path.join(fixtures, f))) : []);
  // Duración de cada plano con vídeo, según el guion
  const scripted = new Map<string, number>();
  for (const m of read('game/scripts/shared/story_def.gd').matchAll(/\{"dur": ([0-9.]+),[^\n]*\n?[^\n]*"video": "([a-z0-9_]+)"/g)) scripted.set(m[2], Number(m[1]));
  const declared = new Set(['manifest.json']);
  const bytes: Record<string, number> = { mp4: 0, webm: 0 };
  for (const [id, clip] of Object.entries(manifest.clips)) {
    assert.match(id, /^[a-z0-9_]+$/, `identificador de vídeo no válido: ${id}`);
    assert.ok(scripted.has(id), `el manifiesto declara «${id}», que ningún plano del guion usa`);
    assert.ok(Math.abs(clip.dur - scripted.get(id)!) < 0.26, `«${id}» dura ${clip.dur} s y su plano ${scripted.get(id)} s`);
    assert.ok(clip.v && /^[a-z0-9]+$/i.test(clip.v), `«${id}» no lleva versión: el navegador no sabría cuándo cambió`);
    for (const kind of ['mp4', 'webm']) {
      const name = clip.src[kind];
      assert.ok(name && tracked.has(name), `«${id}»: falta ${kind} en Git (${name})`);
      declared.add(name);
      const file = path.join(ROOT, dir, name);
      const data = fs.readFileSync(file);
      assert.ok(data.length > 150_000, `${name} pesa ${data.length} bytes: parece incompleto o de prueba`);
      const magic = kind === 'mp4' ? data.subarray(4, 8).toString('latin1') === 'ftyp' : data.readUInt32BE(0) === 0x1a45dfa3;
      assert.ok(magic, `${name} no es un archivo ${kind} válido`);
      assert.ok(!testHashes.has(sha(file)), `${name} es un vídeo de prueba (franjas de colores)`);
      bytes[kind] += data.length;
    }
  }
  const stray = [...tracked].filter((f) => !declared.has(f));
  assert.deepEqual(stray, [], 'hay archivos de vídeo en el juego que el manifiesto no declara');
  const missing = [...scripted.keys()].filter((id) => !manifest.clips[id]);
  const n = Object.keys(manifest.clips).length;
  return `${n} vídeos declarados y presentes · ${(bytes.mp4 / 1e6).toFixed(2)} MB en MP4 o ${(bytes.webm / 1e6).toFixed(2)} MB en WebM por jugador · ninguno es de prueba`
    + (missing.length ? ` · planos que usarán el motor por no tener vídeo: ${missing.join(', ')}` : '');
});

// ── 7) Qué se va a publicar ──
step('Commit que se publicará', () => {
  const dirty = git('status --porcelain').trim();
  assert.equal(dirty, '', 'hay cambios sin guardar en commits: lo que se publique no los incluiría');
  const head = git('rev-parse HEAD').trim();
  const branch = git('rev-parse --abbrev-ref HEAD').trim();
  const subject = git('log -1 --format=%s').trim();
  return `${head}  (${branch}) «${subject}»`;
});

console.log(failed ? `\n${failed} revisión(es) fallaron: no publiques todavía.` : '\nRevisión previa superada.');
process.exit(failed ? 1 : 0);
