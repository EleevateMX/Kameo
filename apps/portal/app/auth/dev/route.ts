import { randomUUID } from 'node:crypto';
import { NextResponse, type NextRequest } from 'next/server';
import { cleanName } from '@alux/shared-contracts';
import { BASE_URL, devLoginEnabled, secureCookies } from '@/lib/env';
import { safeNext, sessionCookie, upsertPlayer } from '@/lib/session';

// Entrada de prueba sin Discord (sólo desarrollo). Cada navegador conserva su identidad.
export async function POST(req: NextRequest) {
  if (!devLoginEnabled) return NextResponse.redirect(`${BASE_URL}/?error=dev_desactivado`, 303);
  const form = await req.formData();
  const name = cleanName(form.get('name'), `Alux ${Math.floor(100 + Math.random() * 900)}`);
  let devId = req.cookies.get('alux_dev_id')?.value;
  if (!devId || !/^[0-9a-f-]{36}$/.test(devId)) devId = randomUUID();
  try {
    const playerId = await upsertPlayer({ provider: 'dev', providerId: devId, displayName: name, avatarUrl: null });
    const res = NextResponse.redirect(`${BASE_URL}${safeNext(form.get('next'))}`, 303);
    res.cookies.set(sessionCookie(playerId));
    res.cookies.set('alux_dev_id', devId, { httpOnly: true, sameSite: 'lax', secure: secureCookies, path: '/', maxAge: 60 * 60 * 24 * 365 });
    return res;
  } catch (err) {
    console.error('[auth] Error en la entrada de prueba:', err instanceof Error ? err.message : err);
    return NextResponse.redirect(`${BASE_URL}/?error=api`, 303);
  }
}
