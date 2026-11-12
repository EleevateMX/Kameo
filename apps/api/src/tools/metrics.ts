// Muestra las métricas de las últimas sesiones de juego guardadas en la base de datos.
//
//   DATABASE_URL=postgres://… npm run beta:metrics            últimas 30 sesiones
//   DATABASE_URL=postgres://… npm run beta:metrics -- 100 --json
//
// Necesita llegar a la base de datos (en Render: URL externa y tu IP en la lista de acceso,
// sólo mientras lo consultas). Sin eso, las mismas cifras salen en los registros del servicio,
// en las líneas que empiezan por «[metrics]».
import dotenv from 'dotenv';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { PgStore } from '../store/pg.ts';

dotenv.config({ path: path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../../.env') });
const url = process.env.DATABASE_URL;
if (!url) {
  console.error('Define DATABASE_URL con la cadena de conexión de la base de datos.');
  process.exit(1);
}
const limit = Math.max(1, Math.min(500, Number(process.argv.find((a) => /^\d+$/.test(a)) ?? 30)));
const store = await PgStore.connect(url);
const rows = await store.listMetrics(limit);
await store.close();

if (process.argv.includes('--json')) {
  console.log(JSON.stringify(rows, null, 2));
} else {
  const n = (v: number | null, digits = 0) => (v === null || v === undefined ? '—' : v.toFixed(digits));
  console.table(rows.map((r) => {
    const d = r.data as Record<string, any>;
    return {
      fecha: r.createdAt.toISOString().slice(0, 16).replace('T', ' '),
      jugador: r.playerId.slice(0, 8), sala: r.room, calidad: `${r.quality}${d.qualityAuto ? ' (auto)' : ''}`,
      'FPS med': n(r.fpsAvg), 'FPS p5': n(r.fpsMin), 'ping ms': n(r.pingAvg), 'ping máx': n(r.pingMax),
      'carga s': r.loadMs === null ? '—' : (r.loadMs / 1000).toFixed(1), 'min jugados': (r.seconds / 60).toFixed(1),
      'JS MB': n(d.heapMb ?? null), reconex: d.rejoins ?? 0, 'G/P': `${d.wins ?? 0}/${d.losses ?? 0}`,
      audio: d.audio?.context || '—',
      // ¿llegó a sonar? pico máximo medido en la salida del navegador durante la sesión
      'sonó': typeof d.audio?.peak === 'number' ? (d.audio.peak > 0.001 ? `sí (${(20 * Math.log10(d.audio.peak)).toFixed(0)} dB)` : 'NO') : '—',
      // combate con el guardián: segundos en cada fase / derrotas por fase / daño recibido / % del tiempo como Balam
      jefe: d.boss && (d.boss.secs || []).some((x: number) => x > 0)
        ? `${(d.boss.secs || []).join('+')} s · derrotas ${(d.boss.fails || []).join('/')} · daño ${d.boss.dmg ?? 0} · Balam ${Math.round(100 * (d.boss.balam ?? 0) / Math.max(1, (d.boss.secs || []).reduce((a: number, x: number) => a + x, 0)))} %${d.boss.freed ? ' · liberado' : ''}`
        : '—',
      cine: d.cine ? `${d.cine.video ?? 0} vídeo / ${d.cine.engine ?? 0} motor / ${d.cine.skipped ?? 0} omitidas` : '—',
      pantalla: d.viewport || '—', gráfica: String(d.renderer || '—').slice(0, 44),
    };
  }));
  console.log(`${rows.length} sesión(es). Navegador de cada una: añade --json para ver el detalle completo.`);
}
