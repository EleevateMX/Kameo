import { redirect } from 'next/navigation';
import { PlayFrame } from '@/components/PlayFrame';
import { getSessionPlayerId } from '@/lib/session';

export const dynamic = 'force-dynamic';

// La plaza social (prototipo): «Mérida, la Ciudad Blanca». El juego se abre contra el servidor
// de zonas; desde su portal se entra a una sala del Claro de los Aluxes.
export default async function PlazaPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  if (!(await getSessionPlayerId())) redirect(`/?next=${encodeURIComponent('/plaza')}`);
  const given = await searchParams;
  let query = '';
  for (const key of ['q', 'debug', 'fs']) {
    const value = given[key];
    if (typeof value === 'string' && /^[a-z0-9]{1,8}$/i.test(value)) query += `&${key}=${value}`;
  }
  return <PlayFrame src={`/game/index.html?mode=plaza${query}`} title="ALUX: la plaza" destino="plaza" />;
}
