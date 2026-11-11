// Login con Discord (OAuth2, flujo "authorization code", scope "identify").
import crypto from 'node:crypto';
import express from 'express';

const DISCORD_API = 'https://discord.com/api';

function discordAvatar(user) {
  if (user.avatar) {
    const ext = user.avatar.startsWith('a_') ? 'gif' : 'png';
    return `https://cdn.discordapp.com/avatars/${user.id}/${user.avatar}.${ext}?size=64`;
  }
  const index = Number((BigInt(user.id) >> 22n) % 6n);
  return `https://cdn.discordapp.com/embed/avatars/${index}.png`;
}

export function createAuthRouter({ clientId, clientSecret, redirectUri, allowGuest }) {
  const router = express.Router();
  const discordEnabled = Boolean(clientId && clientSecret);

  router.get('/auth/discord', (req, res) => {
    if (!discordEnabled) return res.redirect('/?error=discord_no_configurado');
    const state = crypto.randomBytes(16).toString('hex');
    req.session.oauthState = state;
    const params = new URLSearchParams({
      client_id: clientId,
      redirect_uri: redirectUri,
      response_type: 'code',
      scope: 'identify',
      state,
      prompt: 'none',
    });
    req.session.save(() => res.redirect(`https://discord.com/oauth2/authorize?${params}`));
  });

  router.get('/auth/discord/callback', async (req, res) => {
    const { code, state, error } = req.query;
    if (error) return res.redirect('/?error=cancelado');
    if (!code || !state || state !== req.session.oauthState) {
      return res.redirect('/?error=estado_invalido');
    }
    delete req.session.oauthState;

    try {
      const tokenRes = await fetch(`${DISCORD_API}/oauth2/token`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
          client_id: clientId,
          client_secret: clientSecret,
          grant_type: 'authorization_code',
          code: String(code),
          redirect_uri: redirectUri,
        }),
      });
      if (!tokenRes.ok) throw new Error(`token ${tokenRes.status}`);
      const token = await tokenRes.json();

      const userRes = await fetch(`${DISCORD_API}/users/@me`, {
        headers: { Authorization: `Bearer ${token.access_token}` },
      });
      if (!userRes.ok) throw new Error(`user ${userRes.status}`);
      const du = await userRes.json();

      const user = {
        id: `discord-${du.id}`,
        discordId: du.id,
        name: du.global_name || du.username,
        avatar: discordAvatar(du),
        guest: false,
      };
      // Nueva sesión para evitar fijación de sesión
      req.session.regenerate((err) => {
        if (err) return res.redirect('/?error=sesion');
        req.session.user = user;
        req.session.save(() => res.redirect('/'));
      });
    } catch (err) {
      console.error('[auth] Error con Discord:', err.message);
      res.redirect('/?error=discord');
    }
  });

  router.get('/auth/guest', (req, res) => {
    if (!allowGuest) return res.redirect('/?error=invitados_desactivados');
    const tag = crypto.randomBytes(2).toString('hex').toUpperCase();
    const user = {
      id: `guest-${crypto.randomBytes(8).toString('hex')}`,
      name: `Invitado-${tag}`,
      avatar: null,
      guest: true,
    };
    req.session.regenerate((err) => {
      if (err) return res.redirect('/?error=sesion');
      req.session.user = user;
      req.session.save(() => res.redirect('/'));
    });
  });

  router.post('/auth/logout', (req, res) => {
    req.session.destroy(() => {
      res.clearCookie('alux.sid');
      res.json({ ok: true });
    });
  });

  return router;
}
