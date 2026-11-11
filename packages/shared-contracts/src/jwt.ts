// JWT HS256 mínimo, sin dependencias. Se usa para dos cosas distintas:
//  - la sesión del portal (cookie)            → audiencia "alux-session"
//  - el ticket de acceso al servidor de juego → audiencia "alux-game"
// El servidor Godot verifica el mismo formato en game/scripts/shared/ticket.gd.
import { createHmac, timingSafeEqual } from 'node:crypto';

const b64url = (data: Buffer | string) => Buffer.from(data).toString('base64url');

export interface JwtClaims {
  aud: string;
  sub: string;
  iat: number;
  exp: number;
  [key: string]: unknown;
}

export function signJwt(payload: Omit<JwtClaims, 'iat' | 'exp'>, secret: string, ttlSeconds: number): string {
  if (!secret) throw new Error('signJwt: falta el secreto');
  const now = Math.floor(Date.now() / 1000);
  const head = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const body = b64url(JSON.stringify({ ...payload, iat: now, exp: now + ttlSeconds }));
  const sig = createHmac('sha256', secret).update(`${head}.${body}`).digest('base64url');
  return `${head}.${body}.${sig}`;
}

export function verifyJwt<T extends { aud: string; sub: string; exp: number } = JwtClaims>(token: unknown, secret: string, audience: string): T | null {
  if (typeof token !== 'string' || token.length > 4096 || !secret) return null;
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  const [head, body, sig] = parts;
  const expected = createHmac('sha256', secret).update(`${head}.${body}`).digest();
  const given = Buffer.from(sig, 'base64url');
  if (given.length !== expected.length || !timingSafeEqual(given, expected)) return null;
  try {
    const header = JSON.parse(Buffer.from(head, 'base64url').toString('utf8'));
    if (header.alg !== 'HS256') return null;
    const claims = JSON.parse(Buffer.from(body, 'base64url').toString('utf8')) as T;
    if (typeof claims.exp !== 'number' || claims.exp < Date.now() / 1000) return null;
    if (claims.aud !== audience) return null;
    if (typeof claims.sub !== 'string' || !claims.sub) return null;
    return claims;
  } catch {
    return null;
  }
}
