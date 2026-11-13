import { redirect } from 'next/navigation';
import { PlayFrame } from '@/components/PlayFrame';
import { getSessionPlayerId } from '@/lib/session';

export const dynamic = 'force-dynamic';

// Enlace de invitación y destino del botón JUGAR: /play/ABC123. Si no hay sesión, primero se
// inicia y luego se vuelve aquí. El juego se muestra dentro de esta página para conservar la
// pantalla completa que pidió el botón.
export default async function PlayPage({ params, searchParams }: {
  params: Promise<{ code: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const code = (await params).code.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 12);
  if (!code) redirect('/hub');
  if (!(await getSessionPlayerId())) redirect(`/?next=${encodeURIComponent(`/play/${code}`)}`);
  // Sólo pasan al juego los ajustes que entiende (calidad, cinemáticas, depuración, pantalla completa)
  const given = await searchParams;
  let query = '';
  for (const key of ['q', 'cine', 'debug', 'fs']) {
    const value = given[key];
    if (typeof value === 'string' && /^[a-z0-9]{1,8}$/i.test(value)) query += `&${key}=${value}`;
  }
  return <PlayFrame src={`/game/index.html?room=${code}${query}`} />;
}
