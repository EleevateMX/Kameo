import 'dotenv/config';
import crypto from 'node:crypto';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import express from 'express';
import session from 'express-session';
import { Server } from 'socket.io';
import { createAuthRouter } from './auth.js';
import { Store } from './store.js';
import { Game } from './game.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.join(__dirname, '..');

const PORT = Number(process.env.PORT) || 3000;
const BASE_URL = (process.env.BASE_URL || `http://localhost:${PORT}`).replace(/\/$/, '');
const CLIENT_ID = process.env.DISCORD_CLIENT_ID;
const CLIENT_SECRET = process.env.DISCORD_CLIENT_SECRET;
const REDIRECT_URI = process.env.DISCORD_REDIRECT_URI || `${BASE_URL}/auth/discord/callback`;
const discordEnabled = Boolean(CLIENT_ID && CLIENT_SECRET);
// Por defecto se permite entrar como invitado sólo si Discord no está configurado
const allowGuest = process.env.ALLOW_GUEST ? process.env.ALLOW_GUEST === 'true' : !discordEnabled;

let SESSION_SECRET = process.env.SESSION_SECRET;
if (!SESSION_SECRET) {
  SESSION_SECRET = crypto.randomBytes(32).toString('hex');
  console.warn('[aviso] SESSION_SECRET no definido: se generó uno temporal (las sesiones se pierden al reiniciar).');
}

const app = express();
if (BASE_URL.startsWith('https://')) app.set('trust proxy', 1);

const sessionMiddleware = session({
  name: 'alux.sid',
  secret: SESSION_SECRET,
  resave: false,
  saveUninitialized: false,
  cookie: {
    httpOnly: true,
    sameSite: 'lax',
    secure: BASE_URL.startsWith('https://'),
    maxAge: 1000 * 60 * 60 * 24 * 7,
  },
});

const store = new Store(path.join(ROOT, 'data', 'players.json'));

app.use(sessionMiddleware);
app.use(express.json());
app.use(createAuthRouter({ clientId: CLIENT_ID, clientSecret: CLIENT_SECRET, redirectUri: REDIRECT_URI, allowGuest }));

app.get('/api/config', (req, res) => {
  res.json({ discordEnabled, allowGuest });
});

app.get('/api/me', (req, res) => {
  const user = req.session.user;
  if (!user) return res.json({ user: null });
  const progress = store.getPlayer(user);
  res.json({ user, progress });
});

app.post('/api/prologue-seen', (req, res) => {
  const user = req.session.user;
  if (!user) return res.status(401).end();
  store.update(user.id, (p) => { p.seenPrologue = true; });
  res.json({ ok: true });
});

app.get('/api/leaderboard', (req, res) => {
  res.json(store.leaderboard(10));
});

app.use('/shared', express.static(path.join(ROOT, 'shared')));
app.use(express.static(path.join(ROOT, 'public')));

const server = http.createServer(app);
const io = new Server(server);
io.engine.use(sessionMiddleware);

const game = new Game(io, store);
game.start();

io.on('connection', (socket) => {
  const user = socket.request.session?.user;
  if (!user) {
    socket.emit('auth_required');
    socket.disconnect(true);
    return;
  }
  game.addPlayer(socket, user);
});

server.listen(PORT, () => {
  console.log(`ALUX: Ecos del Cenote corriendo en ${BASE_URL}`);
  console.log(`Login con Discord: ${discordEnabled ? 'activado' : 'NO configurado (ver README)'} · Invitados: ${allowGuest ? 'sí' : 'no'}`);
});
