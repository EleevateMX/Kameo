import path from 'node:path';
import { fileURLToPath } from 'node:url';
import dotenv from 'dotenv';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
dotenv.config({ path: path.join(root, '.env') });

export interface GameServerRef {
  id: string;
  wsUrl: string; // URL pública que usa el navegador (ws:// o wss://)
}

export interface Config {
  port: number;
  sessionSecret: string;
  ticketSecret: string;
  serviceKey: string;
  databaseUrl: string | null;
  dataFile: string | null;
  gameServers: GameServerRef[];
  production: boolean;
}

const DEV_DEFAULTS = {
  SESSION_SECRET: 'dev-session-secret-no-usar-en-produccion',
  GAME_TICKET_SECRET: 'dev-ticket-secret-no-usar-en-produccion',
  SERVICE_KEY: 'dev-service-key-no-usar-en-produccion',
};

function secret(name: keyof typeof DEV_DEFAULTS, production: boolean): string {
  const v = process.env[name];
  if (v && v.length >= 16) return v;
  if (production) throw new Error(`Falta ${name} (mínimo 16 caracteres) en producción.`);
  return DEV_DEFAULTS[name];
}

export function parseGameServers(raw: string | undefined): GameServerRef[] {
  const list = (raw || 'local-1=ws://localhost:9080')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean)
    .map((entry) => {
      const i = entry.indexOf('=');
      if (i < 1) throw new Error(`GAME_SERVERS mal formado: "${entry}" (usa id=ws://host:puerto)`);
      return { id: entry.slice(0, i), wsUrl: entry.slice(i + 1) };
    });
  if (!list.length) throw new Error('GAME_SERVERS está vacío');
  return list;
}

export function loadConfig(): Config {
  const production = process.env.NODE_ENV === 'production';
  return {
    port: Number(process.env.API_PORT) || 4000,
    sessionSecret: secret('SESSION_SECRET', production),
    ticketSecret: secret('GAME_TICKET_SECRET', production),
    serviceKey: secret('SERVICE_KEY', production),
    databaseUrl: process.env.DATABASE_URL || null,
    dataFile: process.env.DATABASE_URL ? null : path.join(root, 'apps/api/data/dev-store.json'),
    gameServers: parseGameServers(process.env.GAME_SERVERS),
    production,
  };
}
