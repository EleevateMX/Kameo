import 'server-only';
import { cookies } from 'next/headers';
import { SESSION_AUDIENCE, inviteActive, signJwt, verifyJwt, type PlayerProfile } from '@alux/shared-contracts';
import { API_URL, betaInvites, betaLoginEnabled, secureCookies, serviceKey, sessionSecret } from './env';

export const SESSION_COOKIE = 'alux_session';
const WEEK = 60 * 60 * 24 * 7;

/**
 * Cookie de sesión. Para un tester (`beta`), la sesión lleva el id de su invitación y
 * dura como mucho hasta que ésta vence; la API la rechaza si la invitación se retira.
 */
export function sessionCookie(playerId: string, beta?: { invite: string; expiresAt: number }) {
  const ttl = beta ? Math.max(60, Math.min(WEEK, Math.floor((beta.expiresAt - Date.now()) / 1000))) : WEEK;
  return {
    name: SESSION_COOKIE,
    value: signJwt({ aud: SESSION_AUDIENCE, sub: playerId, ...(beta ? { inv: beta.invite } : {}) }, sessionSecret(), ttl),
    httpOnly: true,
    sameSite: 'lax' as const,
    secure: secureCookies,
    path: '/',
    maxAge: ttl,
  };
}

export async function getSessionPlayerId(): Promise<string | null> {
  const jar = await cookies();
  const claims = verifyJwt(jar.get(SESSION_COOKIE)?.value, sessionSecret(), SESSION_AUDIENCE);
  if (!claims) return null;
  if (claims.inv !== undefined && !(betaLoginEnabled && inviteActive(betaInvites, claims.inv))) return null;
  return claims.sub;
}

/** Perfil del jugador con sesión, o null. */
export async function getProfile(): Promise<PlayerProfile | null> {
  const jar = await cookies();
  const token = jar.get(SESSION_COOKIE)?.value;
  if (!token || !verifyJwt(token, sessionSecret(), SESSION_AUDIENCE)) return null;
  try {
    const res = await fetch(`${API_URL}/v1/me`, { headers: { cookie: `${SESSION_COOKIE}=${token}` }, cache: 'no-store' });
    return res.ok ? ((await res.json()) as PlayerProfile) : null;
  } catch {
    return null;
  }
}

/** Crea o actualiza al jugador en la API y devuelve su id. */
export async function upsertPlayer(p: { provider: 'discord' | 'dev' | 'beta'; providerId: string; displayName: string; avatarUrl: string | null }): Promise<string> {
  const res = await fetch(`${API_URL}/internal/players/upsert`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-service-key': serviceKey() },
    body: JSON.stringify(p),
    cache: 'no-store',
  });
  if (!res.ok) throw new Error(`La API respondió ${res.status} al registrar al jugador`);
  return ((await res.json()) as { id: string }).id;
}

/** Sólo se permiten redirecciones internas (evita redirecciones abiertas). */
export function safeNext(next: unknown, fallback = '/hub'): string {
  if (typeof next !== 'string' || !next.startsWith('/') || next.startsWith('//') || next.includes('\\')) return fallback;
  return next.slice(0, 200);
}
