import { redirect } from 'next/navigation';
import { getSessionPlayerId } from '@/lib/session';

export const dynamic = 'force-dynamic';

// Enlace de invitación: /play/ABC123. Si no hay sesión, primero se inicia y luego se vuelve aquí.
export default async function PlayPage({ params }: { params: Promise<{ code: string }> }) {
  const code = (await params).code.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 12);
  if (!code) redirect('/hub');
  if (!(await getSessionPlayerId())) redirect(`/?next=${encodeURIComponent(`/play/${code}`)}`);
  redirect(`/game/index.html?room=${code}`);
}
