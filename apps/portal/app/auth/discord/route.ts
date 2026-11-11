import { randomBytes } from 'node:crypto';
import { NextResponse, type NextRequest } from 'next/server';
import { BASE_URL, DISCORD_CLIENT_ID, DISCORD_REDIRECT_URI, discordEnabled, secureCookies } from '@/lib/env';
import { safeNext } from '@/lib/session';

// Paso 1 de OAuth2 (Authorization Code): mandar al jugador a Discord con un `state` aleatorio
export async function GET(req: NextRequest) {
  if (!discordEnabled) return NextResponse.redirect(`${BASE_URL}/?error=discord_no_configurado`);
  const state = randomBytes(24).toString('base64url');
  const next = safeNext(req.nextUrl.searchParams.get('next'));
  const params = new URLSearchParams({
    client_id: DISCORD_CLIENT_ID,
    redirect_uri: DISCORD_REDIRECT_URI,
    response_type: 'code',
    scope: 'identify',
    state,
    prompt: 'none',
  });
  const res = NextResponse.redirect(`https://discord.com/oauth2/authorize?${params}`);
  res.cookies.set('alux_oauth', JSON.stringify({ state, next }), {
    httpOnly: true, sameSite: 'lax', secure: secureCookies, path: '/auth', maxAge: 600,
  });
  return res;
}
