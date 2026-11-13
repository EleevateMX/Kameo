'use client';

import { useCallback, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { ALUX_COLORS, HATS, REWARDS, type PlayerProfile, type RoomInfo } from '@alux/shared-contracts/domain';
import { AluxPreview } from '@/components/AluxPreview';

const FORM_NAMES: Record<string, string> = { alux: 'Alux', balam: 'Balam, el jaguar' };

async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`/api/v1${path}`, {
    ...init,
    headers: { 'content-type': 'application/json', 'x-alux-csrf': '1', ...(init?.headers ?? {}) },
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    const messages: Record<string, string> = {
      room_not_found: 'Esa sala no existe o ya cerró.',
      room_full: 'La sala ya tiene 4 aluxes.',
      rate_limited: 'Demasiados intentos. Espera un momento.',
      no_session: 'Tu sesión terminó. Vuelve a iniciar sesión.',
    };
    throw new Error(data.message || messages[data.error] || 'No se pudo completar la acción.');
  }
  return data as T;
}

export function HubClient({ initialProfile, baseUrl }: { initialProfile: PlayerProfile; baseUrl: string }) {
  const [profile, setProfile] = useState(initialProfile);
  const [name, setName] = useState(initialProfile.character.name);
  const [color, setColor] = useState(initialProfile.character.color);
  const [hat, setHat] = useState(initialProfile.character.hat);
  const [saving, setSaving] = useState(false);
  const [savedMsg, setSavedMsg] = useState('');
  const [room, setRoom] = useState<RoomInfo | null>(null);
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [copied, setCopied] = useState('');

  const dirty = name !== profile.character.name || color !== profile.character.color || hat !== profile.character.hat;

  const saveCharacter = async () => {
    setSaving(true);
    setError('');
    try {
      const p = await api<PlayerProfile>('/me/character', { method: 'PUT', body: JSON.stringify({ name, color, hat }) });
      setProfile(p);
      setName(p.character.name);
      setSavedMsg('Guardado');
      setTimeout(() => setSavedMsg(''), 2000);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setSaving(false);
    }
  };

  const run = async (fn: () => Promise<RoomInfo>) => {
    setBusy(true);
    setError('');
    try {
      setRoom(await fn());
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const refreshRoom = useCallback(async (roomCode: string) => {
    try {
      setRoom(await api<RoomInfo>(`/rooms/${roomCode}`));
    } catch { /* la sala pudo cerrarse; se conserva lo último */ }
  }, []);

  useEffect(() => {
    if (!room) return;
    const t = setInterval(() => refreshRoom(room.code), 3000);
    return () => clearInterval(t);
  }, [room?.code, refreshRoom]); // eslint-disable-line react-hooks/exhaustive-deps

  // JUGAR: la pantalla completa sólo se puede pedir dentro del propio clic. Si el navegador la
  // niega o no la tiene, se entra igual, en ventana.
  const router = useRouter();
  const [fullscreen, setFullscreen] = useState(true);
  const [canFullscreen, setCanFullscreen] = useState(false);
  useEffect(() => {
    setCanFullscreen(typeof document.documentElement.requestFullscreen === 'function' && document.fullscreenEnabled !== false);
    try { setFullscreen(localStorage.getItem('alux_fullscreen') !== '0'); } catch { /* sin almacenamiento */ }
  }, []);
  const chooseFullscreen = (on: boolean) => {
    setFullscreen(on);
    try { localStorage.setItem('alux_fullscreen', on ? '1' : '0'); } catch { /* sin almacenamiento */ }
  };
  const play = async () => {
    if (!room) return;
    if (fullscreen && canFullscreen && !document.fullscreenElement) {
      try { await document.documentElement.requestFullscreen({ navigationUI: 'hide' }); } catch { /* en ventana */ }
    }
    router.push(`/play/${room.code}`);
  };

  const inviteUrl = room ? `${baseUrl}/play/${room.code}` : '';
  const copy = async (what: 'link' | 'discord') => {
    const text = what === 'link' ? inviteUrl : `¡Vamos a jugar ALUX! Entra a mi sala **${room!.code}**: ${inviteUrl}`;
    try {
      await navigator.clipboard.writeText(text);
      setCopied(what);
      setTimeout(() => setCopied(''), 2000);
    } catch {
      setError('No se pudo copiar. Copia el enlace a mano.');
    }
  };

  return (
    <main className="hub">
      <header className="hub-header">
        <a className="logo" href="/hub">ALUX</a>
        <div className="user">
          {profile.avatarUrl ? <img src={profile.avatarUrl} alt="" width={36} height={36} /> : <span className="avatar-fallback" style={{ background: profile.character.color }} />}
          <span>{profile.displayName}</span>
          <form method="post" action="/auth/logout"><button className="link" type="submit">Salir</button></form>
        </div>
      </header>

      {error && <p className="error banner" role="alert">{error}</p>}

      <div className="hub-grid">
        <section className="panel">
          <h2>Tu alux</h2>
          <div className="alux-editor">
            <div className="alux-stage"><AluxPreview color={color} hat={hat} size={190} /></div>
            <div className="alux-fields">
              <label htmlFor="alux-name">Nombre</label>
              <input id="alux-name" value={name} maxLength={20} onChange={(e) => setName(e.target.value)} />
              <span className="label">Color</span>
              <div className="swatches" role="radiogroup" aria-label="Color de la túnica">
                {ALUX_COLORS.map((c) => (
                  <button key={c} type="button" role="radio" aria-checked={color === c} aria-label={c}
                    className={color === c ? 'swatch on' : 'swatch'} style={{ background: c }} onClick={() => setColor(c)} />
                ))}
              </div>
              <span className="label">Accesorio</span>
              <div className="hats" role="radiogroup" aria-label="Accesorio">
                {HATS.map((h, i) => (
                  <button key={h} type="button" role="radio" aria-checked={hat === i} className={hat === i ? 'chip on' : 'chip'} onClick={() => setHat(i)}>{h}</button>
                ))}
              </div>
              <div className="row">
                <button className="btn" disabled={!dirty || saving || name.trim().length < 2} onClick={saveCharacter}>
                  {saving ? 'Guardando…' : 'Guardar alux'}
                </button>
                <span className="saved">{savedMsg}</span>
              </div>
            </div>
          </div>

          <h3>Tu progreso</h3>
          <ul className="progress">
            {profile.unlocks.map((f) => (
              <li key={f}><span className="tag form">Forma</span>{FORM_NAMES[f] ?? f}</li>
            ))}
            {Object.entries(REWARDS).map(([key, r]) => {
              const have = profile.rewards.includes(key);
              const tag = !have ? 'Pendiente' : r.kind === 'object' ? 'Objeto ancestral' : 'Capítulo I';
              return (
                <li key={key} className={have ? '' : 'locked'}>
                  <span className={`tag ${r.kind === 'object' ? 'relic' : 'seal'}`}>{tag}</span>{r.title}
                  {have && r.note ? <small className="reward-note"> · {r.note}</small> : null}
                </li>
              );
            })}
          </ul>
        </section>

        <section className="panel">
          <h2>Jugar</h2>
          {!room ? (
            <div className="play-options">
              <button className="btn big" disabled={busy} onClick={() => run(() => api<RoomInfo>('/rooms', { method: 'POST', body: JSON.stringify({ visibility: 'private' }) }))}>
                Crear sala privada
                <small>Invita a tus amigos con un código</small>
              </button>
              <button className="btn big alt" disabled={busy} onClick={() => run(() => api<RoomInfo>('/rooms/quick', { method: 'POST' }))}>
                Partida pública
                <small>Te unimos con otros aluxes</small>
              </button>
              <form className="join" onSubmit={(e) => { e.preventDefault(); if (code.trim()) run(() => api<RoomInfo>(`/rooms/${code.trim().toUpperCase()}`)); }}>
                <label htmlFor="join-code">¿Tienes un código?</label>
                <div>
                  <input id="join-code" value={code} maxLength={12} placeholder="ABC123" autoComplete="off"
                    onChange={(e) => setCode(e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, ''))} />
                  <button className="btn ghost" disabled={busy || code.length < 4}>Unirme</button>
                </div>
              </form>
            </div>
          ) : (
            <div className="room">
              <p className="eyebrow">{room.visibility === 'private' ? 'Sala privada' : 'Sala pública'}</p>
              <div className="room-code" aria-label="Código de sala">{room.code}</div>
              <ul className="members">
                {[0, 1, 2, 3].map((i) => {
                  const m = room.members[i];
                  return m ? (
                    <li key={m.id}><i style={{ background: m.color }} />{m.name}<em>{m.online ? 'en el claro' : 'en el portal'}</em></li>
                  ) : (
                    <li key={i} className="empty"><i />Lugar libre</li>
                  );
                })}
              </ul>
              {room.gateOpen && <p className="note">Esta sala ya abrió el santuario.</p>}
              <button className="btn big enter" onClick={play}>
                JUGAR
                <small>Entrar al claro</small>
              </button>
              {canFullscreen && (
                <label className="fs-pref">
                  <input type="checkbox" checked={fullscreen} onChange={(e) => chooseFullscreen(e.target.checked)} />
                  Pantalla completa al jugar
                </label>
              )}
              <div className="invite">
                <input readOnly value={inviteUrl} onFocus={(e) => e.currentTarget.select()} aria-label="Enlace de invitación" />
                <button className="btn ghost" onClick={() => copy('link')}>{copied === 'link' ? 'Copiado' : 'Copiar enlace'}</button>
                <button className="btn ghost discord-outline" onClick={() => copy('discord')}>{copied === 'discord' ? 'Copiado' : 'Copiar para Discord'}</button>
              </div>
              <button className="link" onClick={() => setRoom(null)}>← Elegir otra sala</button>
            </div>
          )}
          <div className="howto">
            <h3>Cómo se juega</h3>
            <ul>
              <li>Pisen los altares a la vez para abrir el santuario y venzan la emboscada</li>
              <li><kbd>W A S D</kbd> moverse · <kbd>Espacio</kbd> saltar · ratón para mirar</li>
              <li><kbd>Clic</kbd> atacar · <kbd>Clic derecho</kbd> esquivar · <kbd>F</kbd> tocar o purificar</li>
              <li><kbd>1</kbd> Alux · <kbd>2</kbd> Balam, el jaguar (corre, salta y pega más)</li>
              <li><kbd>Esc</kbd> menú: volumen, sensibilidad y salir · <kbd>H</kbd> controles</li>
              <li>Una partida dura unos 10 minutos y se puede jugar de 1 a 4</li>
            </ul>
          </div>
        </section>
      </div>
    </main>
  );
}
