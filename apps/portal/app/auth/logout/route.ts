import { NextResponse } from 'next/server';
import { BASE_URL } from '@/lib/env';
import { SESSION_COOKIE } from '@/lib/session';

export async function POST() {
  const res = NextResponse.redirect(`${BASE_URL}/`, 303);
  res.cookies.delete(SESSION_COOKIE);
  return res;
}
