// Aplica las migraciones de supabase/migrations a la base de datos de DATABASE_URL.
//
//   npm run migrate -w @alux/api             aplica las pendientes
//   npm run migrate -w @alux/api -- --status sólo muestra el estado
//
// Es seguro ejecutarlo en cada arranque:
//  - lleva la cuenta en la tabla schema_migrations (versión + huella del archivo);
//  - cada migración va en su propia transacción: o entra entera o no entra;
//  - un candado de PostgreSQL evita que dos arranques migren a la vez;
//  - se niega a ejecutar sentencias destructivas (DROP TABLE, DROP COLUMN, TRUNCATE, DELETE)
//    salvo que se defina ALLOW_DESTRUCTIVE_MIGRATIONS=1 después de haber hecho un respaldo;
//  - si un archivo ya aplicado cambió, se detiene: las migraciones aplicadas no se editan.
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import dotenv from 'dotenv';
import { connectPool } from './store/pg.ts';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
dotenv.config({ path: path.join(root, '.env') });

const DIR = process.env.MIGRATIONS_DIR || path.join(root, 'supabase/migrations');
const LOCK_KEY = 0x414c5558; // "ALUX"
const DESTRUCTIVE = /\b(drop\s+table|drop\s+column|drop\s+schema|drop\s+database|truncate|delete\s+from)\b/i;

export interface MigrationState { version: string; applied: boolean; changed: boolean; destructive: boolean }

function readMigrations() {
  return fs.readdirSync(DIR).filter((f) => f.endsWith('.sql')).sort().map((file) => {
    const sql = fs.readFileSync(path.join(DIR, file), 'utf8');
    // (los comentarios no cuentan para decidir si es destructiva)
    const code = sql.replace(/--.*$/gm, '').replace(/\/\*[\s\S]*?\*\//g, '');
    return { version: file.replace(/\.sql$/, ''), sql, checksum: createHash('sha256').update(sql).digest('hex'), destructive: DESTRUCTIVE.test(code) };
  });
}

export async function migrate(databaseUrl: string, opts: { statusOnly?: boolean; log?: (line: string) => void } = {}): Promise<MigrationState[]> {
  const log = opts.log ?? ((line: string) => console.log(`[migraciones] ${line}`));
  const pool = await connectPool(databaseUrl, 2);
  const client = await pool.connect();
  try {
    await client.query('select pg_advisory_lock($1)', [LOCK_KEY]);
    await client.query(`create table if not exists schema_migrations (
      version text primary key, checksum text not null, applied_at timestamptz not null default now())`);
    const { rows } = await client.query('select version, checksum from schema_migrations');
    const done = new Map<string, string>(rows.map((r) => [r.version, r.checksum]));
    const files = readMigrations();
    const states: MigrationState[] = files.map((m) => ({
      version: m.version, applied: done.has(m.version),
      changed: done.has(m.version) && done.get(m.version) !== m.checksum, destructive: m.destructive,
    }));
    const changed = states.filter((s) => s.changed);
    if (changed.length) {
      throw new Error(`Estas migraciones ya aplicadas cambiaron en el repositorio: ${changed.map((s) => s.version).join(', ')}. ` +
        'No se editan migraciones aplicadas: crea una nueva.');
    }
    if (opts.statusOnly) return states;

    for (const m of files) {
      if (done.has(m.version)) continue;
      if (m.destructive && process.env.ALLOW_DESTRUCTIVE_MIGRATIONS !== '1') {
        throw new Error(`La migración ${m.version} borra datos (DROP/TRUNCATE/DELETE). Haz un respaldo (scripts/beta-backup.sh) ` +
          'y vuelve a desplegar con ALLOW_DESTRUCTIVE_MIGRATIONS=1.');
      }
      await client.query('begin');
      try {
        await client.query(m.sql);
        await client.query('insert into schema_migrations (version, checksum) values ($1, $2)', [m.version, m.checksum]);
        await client.query('commit');
        log(`aplicada ${m.version}`);
      } catch (err) {
        await client.query('rollback');
        throw new Error(`La migración ${m.version} falló y se deshizo: ${(err as Error).message}`);
      }
    }
    return files.map((m) => ({ version: m.version, applied: true, changed: false, destructive: m.destructive }));
  } finally {
    await client.query('select pg_advisory_unlock($1)', [LOCK_KEY]).catch(() => {});
    client.release();
    await pool.end();
  }
}

// Ejecución directa
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const url = process.env.DATABASE_URL;
  if (!url) {
    console.log('[migraciones] Sin DATABASE_URL: no hay base de datos que migrar (modo archivo local).');
    process.exit(0);
  }
  const statusOnly = process.argv.includes('--status');
  migrate(url, { statusOnly }).then((states) => {
    const pending = states.filter((s) => !s.applied);
    for (const s of states) console.log(`[migraciones] ${s.applied ? 'aplicada ' : 'PENDIENTE'}  ${s.version}${s.destructive ? '  (destructiva)' : ''}`);
    console.log(`[migraciones] ${states.length} en total, ${pending.length} pendiente(s).`);
    process.exit(0);
  }).catch((err) => {
    console.error(`[migraciones] ERROR: ${(err as Error).message}`);
    process.exit(1);
  });
}
