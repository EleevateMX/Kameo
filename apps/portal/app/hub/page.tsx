import { redirect } from 'next/navigation';
import { getProfile } from '@/lib/session';
import { BASE_URL } from '@/lib/env';
import { HubClient } from './HubClient';

export const dynamic = 'force-dynamic';

export default async function HubPage() {
  const profile = await getProfile();
  if (!profile) redirect('/');
  return <HubClient initialProfile={profile} baseUrl={BASE_URL} />;
}
