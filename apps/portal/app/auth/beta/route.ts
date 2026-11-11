import { NextResponse, type NextRequest } from 'next/server';
import { cleanName, findInvite } from '@alux/shared-contracts';
import { BASE_URL, betaInvites, betaLoginEnabled } from '@/lib/env';
import { safeNext, sessionCookie, upsertPlayer } from '@/lib/session';

// Acceso temporal de testers (beta privada): cada persona entra con su propio código de
// invitación, que vence en la fecha fijada al generarlo. Sólo existe mientras no haya
// Discord configurado y BETA_ACCESS=invite; en cualquier otro caso esta ruta rechaza todo.

const WINDOW_MS = 10 * 60_000;
const MAX_PER_IP = 8;
const MAX_GLOBAL = 120;
const attempts = new Map<string, { n: number; reset: number }>();

/** Cuenta un intento. Devuelve false si esa clave ya agotó su cupo en la ventana. */
function allow(key: string, max: number): boolean {
  const now = Date.now();
  const a = attempts.get(key);
  if (!a || a.reset < now) {
    attempts.set(key, { n: 1, reset: now + WINDOW_MS });
    if (attempts.size > 5000) for (const [k, v] of attempts) if (v.reset < now) attempts.delete(k);
    return true;
  }
  a.n++;
  return a.n <= max;
}

export async function POST(req: NextRequest) {
  const back = (error: string, next = '/hub') =>
    NextResponse.redirect(`${BASE_URL}/?error=${error}${next !== '/hub' ? `&next=${encodeURIComponent(next)}` : ''}`, 303);
  if (!betaLoginEnabled) return back('beta_desactivada');

  const form = await req.formData();
  const next = safeNext(form.get('next'));
  // Detrás del proxy, la IP del visitante llega en x-forwarded-for
  const ip = (req.headers.get('x-forwarded-for') ?? '').split(',')[0].trim() || 'desconocida';
  if (!allow(`ip:${ip}`, MAX_PER_IP) || !allow('global', MAX_GLOBAL)) return back('beta_intentos', next);

  const code = form.get('code');
  const invite = typeof code === 'string' ? findInvite(betaInvites, code) : null;
  if (!invite) return back('beta_codigo', next);

  try {
    const playerId = await upsertPlayer({
      provider: 'beta', providerId: invite.id,
      displayName: cleanName(invite.name || invite.id, 'Alux'), avatarUrl: null,
    });
    const res = NextResponse.redirect(`${BASE_URL}${next}`, 303);
    // La sesión nunca dura más que la invitación
    res.cookies.set(sessionCookie(playerId, { invite: invite.id, expiresAt: invite.expiresAt }));
    console.log(`[auth] Tester «${invite.id}» inició sesión`);
    return res;
  } catch (err) {
    console.error('[auth] Error en el acceso de testers:', err instanceof Error ? err.message : err);
    return back('api', next);
  }
}
