import { timingSafeEqual } from 'node:crypto';
import { NextResponse, type NextRequest } from 'next/server';
import { BASE_URL, DISCORD_CLIENT_ID, DISCORD_CLIENT_SECRET, DISCORD_REDIRECT_URI, discordEnabled } from '@/lib/env';
import { safeNext, sessionCookie, upsertPlayer } from '@/lib/session';

const DISCORD_API = 'https://discord.com/api/v10';

function fail(code: string) {
  const res = NextResponse.redirect(`${BASE_URL}/?error=${code}`);
  res.cookies.delete({ name: 'alux_oauth', path: '/auth' });
  return res;
}

function avatarUrl(user: { id: string; avatar: string | null }) {
  if (user.avatar) {
    const ext = user.avatar.startsWith('a_') ? 'gif' : 'png';
    return `https://cdn.discordapp.com/avatars/${user.id}/${user.avatar}.${ext}?size=128`;
  }
  return `https://cdn.discordapp.com/embed/avatars/${Number((BigInt(user.id) >> 22n) % 6n)}.png`;
}

// Paso 2: Discord regresa con ?code&state. Se valida el state, se canjea el código
// en el servidor (el client secret nunca llega al navegador) y se crea la sesión.
export async function GET(req: NextRequest) {
  if (!discordEnabled) return fail('discord_no_configurado');
  const q = req.nextUrl.searchParams;
  if (q.get('error')) return fail('cancelado');
  const code = q.get('code');
  const state = q.get('state');

  let saved: { state?: string; next?: string } = {};
  try {
    saved = JSON.parse(req.cookies.get('alux_oauth')?.value || '{}');
  } catch { /* cookie dañada */ }
  const a = Buffer.from(state || '');
  const b = Buffer.from(saved.state || '');
  if (!code || !a.length || a.length !== b.length || !timingSafeEqual(a, b)) return fail('estado_invalido');

  try {
    const tokenRes = await fetch(`${DISCORD_API}/oauth2/token`, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: DISCORD_CLIENT_ID,
        client_secret: DISCORD_CLIENT_SECRET,
        grant_type: 'authorization_code',
        code,
        redirect_uri: DISCORD_REDIRECT_URI,
      }),
      cache: 'no-store',
    });
    if (!tokenRes.ok) throw new Error(`token ${tokenRes.status}`);
    const token = (await tokenRes.json()) as { access_token: string };

    const userRes = await fetch(`${DISCORD_API}/users/@me`, {
      headers: { authorization: `Bearer ${token.access_token}` },
      cache: 'no-store',
    });
    if (!userRes.ok) throw new Error(`user ${userRes.status}`);
    const user = (await userRes.json()) as { id: string; username: string; global_name: string | null; avatar: string | null };

    const playerId = await upsertPlayer({
      provider: 'discord',
      providerId: user.id,
      displayName: user.global_name || user.username,
      avatarUrl: avatarUrl(user),
    });
    const res = NextResponse.redirect(`${BASE_URL}${safeNext(saved.next)}`);
    res.cookies.set(sessionCookie(playerId));
    res.cookies.delete({ name: 'alux_oauth', path: '/auth' });
    return res;
  } catch (err) {
    console.error('[auth] Error en el login con Discord:', err instanceof Error ? err.message : err);
    return fail('discord');
  }
}
