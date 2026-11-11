import { createApp } from './app.ts';
import { loadConfig } from './config.ts';
import { MemoryStore } from './store/memory.ts';
import { PgStore } from './store/pg.ts';

const config = loadConfig();
const store = config.databaseUrl ? await PgStore.connect(config.databaseUrl) : new MemoryStore(config.dataFile);
const app = createApp(store, config);

const server = app.listen(config.port, config.host, () => {
  console.log(`[api] ALUX API en http://${config.host}:${config.port}`);
  if (config.betaEnabled) console.log(`[api] Acceso de testers por invitación: ${config.betaInvites.length} invitación(es) cargada(s).`);
  console.log(`[api] Datos: ${config.databaseUrl ? 'PostgreSQL / Supabase' : `archivo local (${config.dataFile})`}`);
  console.log(`[api] Servidores de juego: ${config.gameServers.map((s) => `${s.id} → ${s.wsUrl}`).join(', ')}`);
  if (!config.production && !process.env.SESSION_SECRET) {
    console.warn('[api] Usando secretos de desarrollo. Define SESSION_SECRET, GAME_TICKET_SECRET y SERVICE_KEY antes de publicar.');
  }
});

for (const sig of ['SIGINT', 'SIGTERM'] as const) {
  process.on(sig, () => {
    server.close(async () => {
      await store.close();
      process.exit(0);
    });
  });
}
