// Acceso temporal de testers por invitación (beta privada, mientras no haya Discord real).
//
// Cada tester recibe un código propio. El servidor NUNCA guarda el código: sólo su huella
// SHA-256, en la variable de entorno BETA_INVITES, con una fecha de vencimiento:
//
//   BETA_INVITES="ana:<sha256>:2026-12-15:Ana,luis:<sha256>:2026-12-15:Luis"
//
// El acceso sólo está activo con BETA_ACCESS=invite y SIN Discord configurado: en cuanto se
// definen DISCORD_CLIENT_ID y DISCORD_CLIENT_SECRET, las invitaciones dejan de servir y las
// sesiones abiertas con ellas se rechazan. Los códigos se generan con scripts/beta-invites.mjs.
import { createHash, randomInt, timingSafeEqual } from 'node:crypto';

export interface BetaInvite {
  /** Identificador estable del tester (no es secreto). De él se deriva su jugador. */
  id: string;
  /** SHA-256 en hexadecimal del código normalizado. */
  hash: string;
  /** Último instante válido (fin del día indicado, UTC), en milisegundos. */
  expiresAt: number;
  /** Nombre inicial del alux del tester. */
  name: string;
}

const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // sin 0/O ni 1/I
const ID_RE = /^[a-z0-9][a-z0-9-]{0,31}$/;
const HASH_RE = /^[0-9a-f]{64}$/;
const DATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/;

/** Mayúsculas y sin separadores: el tester puede escribirlo con o sin guiones o espacios. */
export function normalizeInviteCode(code: string): string {
  return code.toUpperCase().replace(/[^A-Z0-9]/g, '');
}

export function hashInviteCode(code: string): string {
  return createHash('sha256').update(normalizeInviteCode(code)).digest('hex');
}

/** Código nuevo con 100 bits de azar: ALUX-XXXXX-XXXXX-XXXXX-XXXXX */
export function generateInviteCode(): string {
  let out = 'ALUX';
  for (let g = 0; g < 4; g++) {
    out += '-';
    for (let i = 0; i < 5; i++) out += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
  }
  return out;
}

/** Lee BETA_INVITES. Las entradas mal formadas se descartan (y se cuentan en `rejected`). */
export function parseBetaInvites(raw: string | undefined): { invites: BetaInvite[]; rejected: number } {
  const invites: BetaInvite[] = [];
  let rejected = 0;
  for (const entry of (raw ?? '').split(/[,;\n]/).map((s) => s.trim()).filter(Boolean)) {
    const [id, hash, date, ...rest] = entry.split(':');
    const m = DATE_RE.exec(date ?? '');
    if (!ID_RE.test(id ?? '') || !HASH_RE.test(hash ?? '') || !m || invites.some((i) => i.id === id)) {
      rejected++;
      continue;
    }
    const expiresAt = Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]), 23, 59, 59, 999);
    if (!Number.isFinite(expiresAt)) { rejected++; continue; }
    invites.push({ id, hash, expiresAt, name: rest.join(':').trim().slice(0, 20) });
  }
  return { invites, rejected };
}

/** ¿Está activo el acceso por invitación? Sólo con BETA_ACCESS=invite y sin Discord configurado. */
export function betaAccessEnabled(env: Record<string, string | undefined> = process.env): boolean {
  if (env.BETA_ACCESS !== 'invite') return false;
  if (env.DISCORD_CLIENT_ID && env.DISCORD_CLIENT_SECRET) return false;
  return parseBetaInvites(env.BETA_INVITES).invites.length > 0;
}

/** Busca la invitación de un código. Compara contra todas en tiempo constante. */
export function findInvite(invites: BetaInvite[], code: string, now = Date.now()): BetaInvite | null {
  const normalized = normalizeInviteCode(code);
  if (normalized.length < 16 || normalized.length > 64) return null;
  const given = Buffer.from(hashInviteCode(normalized), 'hex');
  let found: BetaInvite | null = null;
  for (const inv of invites) {
    if (timingSafeEqual(given, Buffer.from(inv.hash, 'hex'))) found = inv;
  }
  return found && found.expiresAt >= now ? found : null;
}

/** ¿Sigue vigente la invitación con este id? (para rechazar sesiones revocadas o vencidas) */
export function inviteActive(invites: BetaInvite[], id: unknown, now = Date.now()): boolean {
  return typeof id === 'string' && invites.some((i) => i.id === id && i.expiresAt >= now);
}
