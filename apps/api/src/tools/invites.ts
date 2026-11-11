// Genera invitaciones individuales para testers de la beta privada.
//
//   npm run beta:invites -- --testers "Ana,Luis,Marta,Paco" --days 14
//   npm run beta:invites -- --testers "Sofía" --days 7 --keep "<valor actual de BETA_INVITES>"
//
// Imprime, por un lado, el código de cada persona (se lo envías sólo a ella, por un canal
// privado) y, por otro, el valor de BETA_INVITES para el panel del proveedor. Ese valor sólo
// contiene huellas SHA-256: con él no se puede reconstruir ningún código. No escribe archivos.
import { cleanName, generateInviteCode, hashInviteCode, parseBetaInvites } from '@alux/shared-contracts';

function arg(name: string): string | undefined {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

const testers = (arg('testers') ?? '').split(',').map((s) => s.trim()).filter(Boolean);
const days = Math.max(1, Math.min(90, Number(arg('days') ?? 14)));
const keep = parseBetaInvites(arg('keep'));
if (!testers.length) {
  console.error('Uso: npm run beta:invites -- --testers "Ana,Luis,Marta,Paco" [--days 14] [--keep "<BETA_INVITES actual>"]');
  process.exit(1);
}
if (keep.rejected) console.error(`Aviso: ${keep.rejected} entrada(s) de --keep estaban mal formadas y se descartan.`);

const until = new Date(Date.now() + days * 86_400_000);
const date = until.toISOString().slice(0, 10);
const used = new Set(keep.invites.map((i) => i.id));
const entries = keep.invites.map((i) => `${i.id}:${i.hash}:${new Date(i.expiresAt).toISOString().slice(0, 10)}${i.name ? `:${i.name}` : ''}`);
const lines: string[] = [];

for (const raw of testers) {
  const name = cleanName(raw, 'Tester');
  let id = name.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 24) || 'tester';
  for (let n = 2; used.has(id); n++) id = `${id.replace(/-\d+$/, '')}-${n}`;
  used.add(id);
  const code = generateInviteCode();
  entries.push(`${id}:${hashInviteCode(code)}:${date}:${name}`);
  lines.push(`  ${name.padEnd(20)}  ${code}`);
}

console.log(`\nCódigos de invitación (válidos hasta el ${date}, 23:59 UTC). Envía a cada persona SÓLO el suyo:\n`);
console.log(lines.join('\n'));
console.log('\nValor para la variable BETA_INVITES del servicio (sólo huellas; no revela los códigos):\n');
console.log(entries.join(','));
console.log('\nPara retirar a alguien, borra su entrada de BETA_INVITES y guarda: su sesión deja de valer al reiniciarse el servicio.');
