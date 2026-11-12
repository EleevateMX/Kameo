import { randomInt, randomUUID, timingSafeEqual } from 'node:crypto';
import express, { type NextFunction, type Request, type Response } from 'express';
import {
  GAME_TICKET_AUDIENCE, GAME_TICKET_TTL_SECONDS, MAX_PLAYERS_PER_ROOM, REWARDS, SESSION_AUDIENCE,
  cleanName, inviteActive, isValidColor, signJwt, verifyJwt,
  type HeartbeatBody, type RewardBody, type RewardResult, type RoomInfo,
} from '@alux/shared-contracts';
import type { Config } from './config.ts';
import type { RoomRow, Store } from './store/types.ts';

const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const CODE_RE = /^[A-Z0-9]{4,12}$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const LIVE_TTL_MS = 12_000;
const MEMBER_GRACE_MS = 150_000;
const ROOM_IDLE_CLOSE_MS = 15 * 60_000;

interface LiveRoom {
  serverId: string;
  players: Map<string, boolean>; // id → conectado
  seenAt: number;
}

type AuthedRequest = Request & { playerId: string };

function safeEqual(a: string, b: string) {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
}

function readCookie(req: Request, name: string): string | null {
  const raw = req.headers.cookie;
  if (!raw) return null;
  for (const part of raw.split(';')) {
    const i = part.indexOf('=');
    if (i > 0 && part.slice(0, i).trim() === name) return decodeURIComponent(part.slice(i + 1).trim());
  }
  return null;
}

/** Límite sencillo de peticiones por clave (en memoria). */
function limiter(max: number, windowMs: number) {
  const hits = new Map<string, { n: number; reset: number }>();
  return (key: string) => {
    const now = Date.now();
    const h = hits.get(key);
    if (!h || h.reset < now) {
      hits.set(key, { n: 1, reset: now + windowMs });
      if (hits.size > 10_000) for (const [k, v] of hits) if (v.reset < now) hits.delete(k);
      return true;
    }
    h.n++;
    return h.n <= max;
  };
}

export function createApp(store: Store, config: Config) {
  const app = express();
  app.disable('x-powered-by');
  app.use(express.json({ limit: '32kb' }));

  const live = new Map<string, LiveRoom>();
  const recentTickets = new Map<string, number>(); // "code:player" → ms
  const lastPrune = new Map<string, number>();
  const roomLimit = limiter(12, 60_000);
  const ticketLimit = limiter(30, 60_000);

  const liveOf = (code: string) => {
    const l = live.get(code);
    return l && Date.now() - l.seenAt < LIVE_TTL_MS ? l : null;
  };

  async function roomInfo(room: RoomRow): Promise<RoomInfo> {
    const members = await store.listMembers(room.code);
    const l = liveOf(room.code);
    return {
      code: room.code,
      visibility: room.visibility,
      ownerId: room.ownerId,
      createdAt: room.createdAt.toISOString(),
      members: members.map((m) => ({ id: m.id, name: m.name, color: m.color, online: l?.players.get(m.id) === true })),
      online: l ? [...l.players.values()].filter(Boolean).length : 0,
      gateOpen: room.gateOpen,
    };
  }

  function pickServer(rooms: RoomRow[]) {
    // El servidor con menos salas abiertas
    const load = new Map(config.gameServers.map((s) => [s.id, 0]));
    for (const r of rooms) if (load.has(r.serverId)) load.set(r.serverId, load.get(r.serverId)! + 1);
    return [...load.entries()].sort((a, b) => a[1] - b[1])[0][0];
  }

  async function createRoom(ownerId: string, visibility: 'private' | 'public') {
    const serverId = pickServer(await store.listOpenRooms());
    for (let attempt = 0; attempt < 8; attempt++) {
      let code = '';
      for (let i = 0; i < 6; i++) code += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
      if (await store.createRoom({ code, visibility, ownerId, serverId })) {
        return (await store.getRoom(code))!;
      }
    }
    throw new Error('No se pudo generar un código de sala');
  }

  // ───────────── Sesión del jugador (cookie firmada por el portal) ─────────────

  const requireSession = (req: Request, res: Response, next: NextFunction) => {
    const claims = verifyJwt(readCookie(req, 'alux_session'), config.sessionSecret, SESSION_AUDIENCE);
    if (!claims) return res.status(401).json({ error: 'no_session' });
    // Sesión de tester: vale mientras su invitación exista, no haya vencido y el acceso
    // por invitación siga activo (se apaga solo al configurar Discord).
    if (claims.inv !== undefined && !(config.betaEnabled && inviteActive(config.betaInvites, claims.inv))) {
      return res.status(401).json({ error: 'no_session' });
    }
    // Las peticiones que cambian algo deben venir de nuestro propio portal
    if (req.method !== 'GET' && req.headers['x-alux-csrf'] !== '1') {
      return res.status(403).json({ error: 'csrf' });
    }
    (req as AuthedRequest).playerId = claims.sub;
    next();
  };

  const requireService = (req: Request, res: Response, next: NextFunction) => {
    const key = req.headers['x-service-key'];
    if (typeof key !== 'string' || !safeEqual(key, config.serviceKey)) {
      return res.status(401).json({ error: 'bad_service_key' });
    }
    next();
  };

  // Disponibilidad: siempre 200 si la API está en pie; `db` dice si la base de datos responde.
  // `commit` es la versión desplegada (Render la pone en RENDER_GIT_COMMIT); vacío en local.
  app.get('/health', async (_req, res) => res.json({ ok: true, db: await store.ping(), commit: config.commit }));

  // ───────────── Métricas de sesión (beta) ─────────────
  // El navegador informa de su rendimiento cada minuto y al terminar. Una fila por sesión.
  const metricsLimit = limiter(20, 60_000);
  const num = (v: unknown, min: number, max: number): number | null =>
    typeof v === 'number' && Number.isFinite(v) ? Math.min(max, Math.max(min, v)) : null;
  const text = (v: unknown, max: number) => (typeof v === 'string' ? v.replace(/[\u0000-\u001f]/g, ' ').slice(0, max) : '');

  app.post('/v1/telemetry', requireSession, async (req, res) => {
    const playerId = (req as AuthedRequest).playerId;
    if (!metricsLimit(playerId)) return res.status(429).json({ error: 'rate_limited' });
    const b = (req.body ?? {}) as Record<string, unknown>;
    if (typeof b.sid !== 'string' || !UUID_RE.test(b.sid)) return res.status(400).json({ error: 'invalid_session' });
    const quality = ['high', 'low', 'min'].includes(b.quality as string) ? (b.quality as string) : '';
    const audio = (b.audio ?? {}) as Record<string, unknown>;
    const metrics = {
      sessionId: b.sid.toLowerCase(), playerId,
      room: text(b.room, 12).toUpperCase().replace(/[^A-Z0-9]/g, ''),
      quality,
      fpsAvg: num(b.fpsAvg, 0, 1000), fpsMin: num(b.fpsMin, 0, 1000),
      pingAvg: num(b.pingAvg, 0, 60_000), pingMax: num(b.pingMax, 0, 60_000),
      loadMs: num(b.loadMs, 0, 3_600_000) === null ? null : Math.round(num(b.loadMs, 0, 3_600_000)!),
      seconds: Math.round(num(b.seconds, 0, 86_400) ?? 0),
      data: {
        qualityAuto: b.qualityAuto === true, qualityChanges: num(b.qualityChanges, 0, 1000),
        heapMb: num(b.heapMb, 0, 65_536), memMb: num(b.memMb, 0, 65_536),
        rejoins: num(b.rejoins, 0, 10_000), wins: num(b.wins, 0, 10_000), losses: num(b.losses, 0, 10_000),
        falls: num(b.falls, 0, 100_000), players: num(b.players, 0, 8),
        viewport: text(b.viewport, 16), dpr: num(b.dpr, 0, 16), renderer: text(b.renderer, 160),
        audio: { master: num(audio.master, 0, 1), music: num(audio.music, 0, 1), sfx: num(audio.sfx, 0, 1), amb: num(audio.amb, 0, 1),
          context: text(audio.context, 16) },
        build: text(b.build, 40), final: b.final === true,
        ua: text(req.headers['user-agent'], 200),
      },
    };
    await store.saveMetrics(metrics);
    // Una línea por informe en el registro del servicio: se puede seguir sin abrir la base de datos.
    console.log(`[metrics] ${JSON.stringify({ player: playerId.slice(0, 8), sid: metrics.sessionId.slice(0, 8), room: metrics.room,
      q: quality, auto: metrics.data.qualityAuto, fps: metrics.fpsAvg, fpsMin: metrics.fpsMin, ping: metrics.pingAvg, pingMax: metrics.pingMax,
      loadMs: metrics.loadMs, s: metrics.seconds, heapMb: metrics.data.heapMb, rejoins: metrics.data.rejoins, final: metrics.data.final })}`);
    res.json({ ok: true });
  });

  app.get('/v1/me', requireSession, async (req, res) => {
    const profile = await store.getProfile((req as AuthedRequest).playerId);
    if (!profile) return res.status(401).json({ error: 'no_session' });
    res.json(profile);
  });

  app.put('/v1/me/character', requireSession, async (req, res) => {
    const { name, color, hat } = req.body ?? {};
    const clean = cleanName(name, '');
    if (!clean) return res.status(400).json({ error: 'invalid_name', message: 'El nombre debe tener entre 2 y 20 caracteres.' });
    if (!isValidColor(color)) return res.status(400).json({ error: 'invalid_color' });
    if (!Number.isInteger(hat) || hat < 0 || hat > 3) return res.status(400).json({ error: 'invalid_hat' });
    await store.updateCharacter((req as AuthedRequest).playerId, { name: clean, color: color.toLowerCase(), hat });
    res.json(await store.getProfile((req as AuthedRequest).playerId));
  });

  // ───────────── Salas ─────────────

  app.post('/v1/rooms', requireSession, async (req, res) => {
    const playerId = (req as AuthedRequest).playerId;
    if (!roomLimit(playerId)) return res.status(429).json({ error: 'rate_limited' });
    const visibility = req.body?.visibility === 'public' ? 'public' : 'private';
    const room = await createRoom(playerId, visibility);
    res.status(201).json(await roomInfo(room));
  });

  // Emparejamiento: busca una sala pública con espacio, o crea una
  app.post('/v1/rooms/quick', requireSession, async (req, res) => {
    const playerId = (req as AuthedRequest).playerId;
    if (!roomLimit(playerId)) return res.status(429).json({ error: 'rate_limited' });
    const candidates: { room: RoomRow; members: number; online: number }[] = [];
    for (const room of await store.listOpenPublicRooms()) {
      const members = await store.listMembers(room.code);
      const mine = members.some((m) => m.id === playerId);
      if (!mine && members.length >= MAX_PLAYERS_PER_ROOM) continue;
      const l = liveOf(room.code);
      const online = l ? [...l.players.values()].filter(Boolean).length : 0;
      const fresh = Date.now() - room.createdAt.getTime() < 120_000;
      if (online === 0 && !fresh && !mine) continue; // sala abandonada
      candidates.push({ room, members: members.length, online });
    }
    candidates.sort((a, b) => b.online - a.online || b.members - a.members);
    const room = candidates[0]?.room ?? (await createRoom(playerId, 'public'));
    res.json(await roomInfo(room));
  });

  app.get('/v1/rooms/:code', requireSession, async (req, res) => {
    const code = String(req.params.code).toUpperCase();
    const room = CODE_RE.test(code) ? await store.getRoom(code) : null;
    if (!room || room.status !== 'open') return res.status(404).json({ error: 'room_not_found' });
    res.json(await roomInfo(room));
  });

  // Ticket de un solo uso para entrar al servidor de juego
  app.post('/v1/rooms/:code/ticket', requireSession, async (req, res) => {
    const playerId = (req as AuthedRequest).playerId;
    if (!ticketLimit(playerId)) return res.status(429).json({ error: 'rate_limited' });
    const code = String(req.params.code).toUpperCase();
    const room = CODE_RE.test(code) ? await store.getRoom(code) : null;
    if (!room || room.status !== 'open') return res.status(404).json({ error: 'room_not_found', message: 'Esa sala no existe o ya cerró.' });
    const server = config.gameServers.find((s) => s.id === room.serverId);
    if (!server) return res.status(503).json({ error: 'server_unavailable' });
    const profile = await store.getProfile(playerId);
    if (!profile) return res.status(401).json({ error: 'no_session' });

    const members = await store.listMembers(code);
    if (!members.some((m) => m.id === playerId)) {
      if (members.length >= MAX_PLAYERS_PER_ROOM) {
        return res.status(409).json({ error: 'room_full', message: 'La sala ya tiene 4 aluxes.' });
      }
      await store.addMember(code, playerId);
    }
    const jti = randomUUID();
    const ticket = signJwt({
      aud: GAME_TICKET_AUDIENCE, sub: playerId, jti, room: code,
      name: profile.character.name, color: profile.character.color, hat: profile.character.hat,
      forms: profile.unlocks,
    }, config.ticketSecret, GAME_TICKET_TTL_SECONDS);
    recentTickets.set(`${code}:${playerId}`, Date.now());
    await store.recordSession({ jti, playerId, code, expiresAt: new Date(Date.now() + GAME_TICKET_TTL_SECONDS * 1000) });
    await store.updateRoom(code, { touch: true });
    res.json({ ticket, wsUrl: server.wsUrl, room: code });
  });

  // ───────────── Interno: portal y servidor de juego (x-service-key) ─────────────

  app.post('/internal/players/upsert', requireService, async (req, res) => {
    const { provider, providerId, displayName, avatarUrl } = req.body ?? {};
    if ((provider !== 'discord' && provider !== 'dev' && provider !== 'beta') || typeof providerId !== 'string' || !providerId || providerId.length > 64) {
      return res.status(400).json({ error: 'invalid_player' });
    }
    const id = await store.upsertPlayer({
      provider, providerId,
      displayName: cleanName(displayName, 'Alux'),
      avatarUrl: typeof avatarUrl === 'string' && avatarUrl.startsWith('https://') ? avatarUrl.slice(0, 300) : null,
    });
    res.json({ id });
  });

  app.post('/internal/game/heartbeat', requireService, async (req, res) => {
    const body = req.body as HeartbeatBody;
    if (typeof body?.server_id !== 'string' || !Array.isArray(body.rooms)) return res.status(400).json({ error: 'invalid_heartbeat' });
    const now = Date.now();
    const seen = new Set<string>();
    for (const r of body.rooms) {
      if (typeof r?.code !== 'string' || !CODE_RE.test(r.code) || !Array.isArray(r.players)) continue;
      seen.add(r.code);
      live.set(r.code, {
        serverId: body.server_id,
        players: new Map(r.players.filter((p) => typeof p?.id === 'string').map((p) => [p.id, !!p.on])),
        seenAt: now,
      });
    }
    for (const [code, l] of live) if (l.serverId === body.server_id && !seen.has(code)) live.delete(code);

    // Limpieza periódica de miembros que ya no están y de salas abandonadas
    if (now - (lastPrune.get(body.server_id) ?? 0) > 15_000) {
      lastPrune.set(body.server_id, now);
      for (const room of await store.listOpenRooms()) {
        if (room.serverId !== body.server_id) continue;
        const l = live.get(room.code);
        const members = await store.listMembers(room.code);
        let remaining = members.length;
        for (const m of members) {
          const ticketAge = now - (recentTickets.get(`${room.code}:${m.id}`) ?? 0);
          if (!l?.players.has(m.id) && ticketAge > MEMBER_GRACE_MS) {
            await store.removeMember(room.code, m.id);
            remaining--;
          }
        }
        const reported = body.rooms.find((r) => r.code === room.code);
        if (l) {
          await store.updateRoom(room.code, { touch: true, gateOpen: reported?.gate_open ? true : undefined });
        } else if (remaining === 0 && now - room.lastSeenAt.getTime() > ROOM_IDLE_CLOSE_MS) {
          await store.updateRoom(room.code, { status: 'closed' });
        }
      }
      for (const [k, t] of recentTickets) if (now - t > MEMBER_GRACE_MS * 2) recentTickets.delete(k);
    }
    res.json({ ok: true });
  });

  // El servidor de juego avisa de una recompensa ganada. Idempotente: reintentar no duplica.
  app.post('/internal/game/rewards', requireService, async (req, res) => {
    const body = req.body as RewardBody;
    const def = typeof body?.reward === 'string' ? REWARDS[body.reward] : undefined;
    if (!def || !Array.isArray(body.players) || typeof body.idempotency_key !== 'string' || !body.idempotency_key
        || typeof body.room !== 'string' || !CODE_RE.test(body.room)) {
      return res.status(400).json({ error: 'invalid_reward' });
    }
    const members = new Set((await store.listMembers(body.room)).map((m) => m.id));
    const result: RewardResult = { granted: [] };
    for (const playerId of new Set(body.players)) {
      // Sólo quienes realmente pidieron ticket para esa sala
      if (typeof playerId !== 'string' || !UUID_RE.test(playerId) || !members.has(playerId)) continue;
      const fresh = await store.grantReward({
        playerId, reward: body.reward,
        source: body.idempotency_key.slice(0, 120),
        // Recompensas únicas: una sola vez por jugador, sin importar la sala
        idempotencyKey: `once:${body.reward}:${playerId}`,
        effect: { quest: def.quest, unlock: def.unlock },
      });
      if (fresh) result.granted.push(playerId);
    }
    if (body.reward === 'sello_del_claro') await store.updateRoom(body.room, { gateOpen: true });
    res.json(result);
  });

  app.use((_req, res) => res.status(404).json({ error: 'not_found' }));
  app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
    const status = (err as { status?: number })?.status;
    if (status && status >= 400 && status < 500) return res.status(status).json({ error: 'bad_request' });
    console.error('[api] Error no controlado:', err);
    res.status(500).json({ error: 'internal' });
  });

  return app;
}
