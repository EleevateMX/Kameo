import { redirect } from 'next/navigation';
import { PlayFrame } from '@/components/PlayFrame';
import { getSessionPlayerId } from '@/lib/session';

export const dynamic = 'force-dynamic';

// Personalizador 3D: el juego se abre sólo para vestir al alux, con el modelo real y sin sala.
// Guarda en el perfil a través de la API y, al terminar, vuelve al portal.
export default async function AluxPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  if (!(await getSessionPlayerId())) redirect(`/?next=${encodeURIComponent('/alux')}`);
  // Sólo pasan al juego los ajustes que entiende (calidad y depuración)
  const given = await searchParams;
  let query = '';
  for (const key of ['q', 'debug']) {
    const value = given[key];
    if (typeof value === 'string' && /^[a-z0-9]{1,8}$/i.test(value)) query += `&${key}=${value}`;
  }
  return <PlayFrame src={`/game/index.html?mode=alux${query}`} title="ALUX: tu alux" />;
}
