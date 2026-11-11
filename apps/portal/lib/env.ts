import 'server-only';
import { readSecret } from '@alux/shared-contracts';

export const BASE_URL = (process.env.BASE_URL || 'http://localhost:3000').replace(/\/$/, '');
export const API_URL = (process.env.API_URL || 'http://127.0.0.1:4000').replace(/\/$/, '');
export const DISCORD_CLIENT_ID = process.env.DISCORD_CLIENT_ID || '';
export const DISCORD_CLIENT_SECRET = process.env.DISCORD_CLIENT_SECRET || '';
export const DISCORD_REDIRECT_URI = process.env.DISCORD_REDIRECT_URI || `${BASE_URL}/auth/discord/callback`;
export const discordEnabled = Boolean(DISCORD_CLIENT_ID && DISCORD_CLIENT_SECRET);

// Entrada de prueba sin Discord: activa por defecto sólo si Discord no está configurado
// y no estamos en producción. Se puede forzar con ALLOW_DEV_LOGIN=true/false.
export const devLoginEnabled = process.env.ALLOW_DEV_LOGIN
  ? process.env.ALLOW_DEV_LOGIN === 'true'
  : !discordEnabled && process.env.NODE_ENV !== 'production';

export const secureCookies = BASE_URL.startsWith('https://');
export const sessionSecret = () => readSecret('SESSION_SECRET');
export const serviceKey = () => readSecret('SERVICE_KEY');
