// Secretos compartidos entre portal, API y servidor de juego.
// En desarrollo hay valores por defecto para poder arrancar sin configurar nada;
// en producción (NODE_ENV=production) son obligatorios.
export const DEV_SECRETS = {
  SESSION_SECRET: 'dev-session-secret-no-usar-en-produccion',
  GAME_TICKET_SECRET: 'dev-ticket-secret-no-usar-en-produccion',
  SERVICE_KEY: 'dev-service-key-no-usar-en-produccion',
} as const;

export function readSecret(name: keyof typeof DEV_SECRETS): string {
  const v = process.env[name];
  if (v && v.length >= 16) return v;
  if (process.env.NODE_ENV === 'production' && process.env.ALUX_ALLOW_DEV_SECRETS !== '1') {
    throw new Error(`Falta ${name} (mínimo 16 caracteres) en producción.`);
  }
  return DEV_SECRETS[name];
}
