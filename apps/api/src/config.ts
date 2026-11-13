import path from 'node:path';
import { fileURLToPath } from 'node:url';
import dotenv from 'dotenv';
import { betaAccessEnabled, parseBetaInvites, readSecret, type BetaInvite } from '@alux/shared-contracts';

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
  /** URL pública del servidor de zonas sociales (ws:// o wss://); '' si no hay. */
  zoneWsUrl: string;
  production: boolean;
  /** Interfaz en la que escucha la API (127.0.0.1 detrás del proxy interno). */
  host: string;
  /** Acceso temporal de testers por invitación (ver packages/shared-contracts/src/beta.ts). */
  betaEnabled: boolean;
  betaInvites: BetaInvite[];
  /** Commit de Git desplegado (lo informa la plataforma); '' si no se conoce. */
  commit: string;
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
    zoneWsUrl: process.env.ZONE_WS_URL ?? (production ? '' : 'ws://localhost:9081'),
    sessionSecret: readSecret('SESSION_SECRET'),
    ticketSecret: readSecret('GAME_TICKET_SECRET'),
    serviceKey: readSecret('SERVICE_KEY'),
    databaseUrl: process.env.DATABASE_URL || null,
    dataFile: process.env.DATABASE_URL ? null : path.join(root, 'apps/api/data/dev-store.json'),
    gameServers: parseGameServers(process.env.GAME_SERVERS),
    production,
    host: process.env.API_HOST || '0.0.0.0',
    betaEnabled: betaAccessEnabled(process.env),
    betaInvites: parseBetaInvites(process.env.BETA_INVITES).invites,
    commit: (process.env.RENDER_GIT_COMMIT || process.env.ALUX_COMMIT || '').replace(/[^0-9a-f]/gi, '').slice(0, 40),
  };
}
