'use client';

import { useCallback, useEffect, useRef, useState, type MouseEvent as ClicReact } from 'react';
import { useRouter } from 'next/navigation';
import { ACCESSORIES, ALUX_COLORS, AMULETS, HATS, OUTFITS, REWARDS, type PlayerProfile, type RoomInfo } from '@alux/shared-contracts/domain';
import { AluxPreview } from '@/components/AluxPreview';
import { Luciernagas } from '@/components/Luciernagas';
import { Panel } from '@/components/Panel';
import { Velo, type Destino } from '@/components/Velo';

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

/** Lo que lleva puesto el alux, en una línea (se elige en el personalizador 3D). */
function lookLine(p: PlayerProfile): string {
  const c = p.character;
  const parts: string[] = [HATS[c.hat] ?? HATS[0], OUTFITS[c.look?.outfit ?? 0]];
  if (c.look?.accessory) parts.push(ACCESSORIES[c.look.accessory]);
  if (c.look?.amulet) parts.push(AMULETS[c.look.amulet]);
  return parts.join(' · ');
}

// El menú principal del juego: entrar al mundo (la plaza), misión cooperativa (salas del Claro),
// personalizar el alux, progreso, pantalla completa y cerrar sesión. Se maneja con el ratón o con
// el teclado: ↑ ↓ recorren las opciones, ← → cambian entre el menú y la ficha del alux, Enter elige.
export function HubClient({ initialProfile, baseUrl }: { initialProfile: PlayerProfile; baseUrl: string }) {
  const [profile, setProfile] = useState(initialProfile);
  const [name, setName] = useState(initialProfile.character.name);
  const [color, setColor] = useState(initialProfile.character.color);
  const hat = profile.character.hat;   // el tocado se elige en el personalizador 3D
  const [saving, setSaving] = useState(false);
  const [savedMsg, setSavedMsg] = useState('');
  const [room, setRoom] = useState<RoomInfo | null>(null);
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [copied, setCopied] = useState('');

  const dirty = name !== profile.character.name || color !== profile.character.color;
  const canSave = dirty && !saving && name.trim().length >= 2;

  const saveCharacter = async () => {
    setSaving(true);
    setError('');
    try {
      const p = await api<PlayerProfile>('/me/character', { method: 'PUT', body: JSON.stringify({ name, color, hat }) });
      setProfile((prev) => ({ ...p, rpg: p.rpg ?? prev.rpg }));
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

  // Pantalla completa: sólo se puede pedir dentro del propio clic (o Enter). Si el navegador la
  // niega o no la tiene, se entra igual, en ventana.
  const router = useRouter();
  const [fullscreen, setFullscreen] = useState(true);
  const [canFullscreen, setCanFullscreen] = useState(false);
  const [enPantalla, setEnPantalla] = useState(false);
  useEffect(() => {
    setCanFullscreen(typeof document.documentElement.requestFullscreen === 'function' && document.fullscreenEnabled !== false);
    try { setFullscreen(localStorage.getItem('alux_fullscreen') !== '0'); } catch { /* sin almacenamiento */ }
    const alCambiar = () => setEnPantalla(Boolean(document.fullscreenElement));
    alCambiar();
    document.addEventListener('fullscreenchange', alCambiar);
    return () => document.removeEventListener('fullscreenchange', alCambiar);
  }, []);
  const chooseFullscreen = (on: boolean) => {
    setFullscreen(on);
    try { localStorage.setItem('alux_fullscreen', on ? '1' : '0'); } catch { /* sin almacenamiento */ }
  };

  // Salir del menú hacia el juego: aparece la pantalla de carga y se cambia de página sin
  // recargar (así la pantalla completa, si la hay, sigue puesta mientras el juego carga).
  const [saliendo, setSaliendo] = useState<{ destino: Destino; sala?: string } | null>(null);
  const ocupado = useRef(false);
  ocupado.current = saliendo !== null;
  const partir = async (destino: Destino, url: string, pedirPantalla: boolean, sala?: string) => {
    setSaliendo({ destino, sala });
    if (pedirPantalla && fullscreen && canFullscreen && !document.fullscreenElement) {
      try { await document.documentElement.requestFullscreen({ navigationUI: 'hide' }); } catch { /* en ventana */ }
    }
    router.push(url);
  };
  useEffect(() => {
    if (!saliendo) return;
    // Si el cambio de página no llega, el menú vuelve a estar a mano
    const t = setTimeout(() => { setSaliendo(null); setError('No se pudo entrar. Inténtalo de nuevo.'); }, 15_000);
    const alVolver = (e: PageTransitionEvent) => { if (e.persisted) setSaliendo(null); };
    window.addEventListener('pageshow', alVolver);
    return () => { clearTimeout(t); window.removeEventListener('pageshow', alVolver); };
  }, [saliendo]);
  // Los destinos son enlaces de verdad: con Ctrl, Mayús o el botón central se abren como cualquier enlace
  const alIr = (destino: Destino, url: string, pedirPantalla: boolean) => (e: ClicReact<HTMLAnchorElement>) => {
    if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    e.preventDefault();
    void partir(destino, url, pedirPantalla);
  };
  const play = () => { if (room) void partir('sala', `/play/${room.code}`, true, room.code); };

  // Teclado y ratón del menú. Las opciones llevan `data-nav` con su columna: «menu» o «alux».
  const raiz = useRef<HTMLElement>(null);
  useEffect(() => {
    const menu = raiz.current;
    if (!menu) return;
    const opciones = (columna: string) => Array.from(menu.querySelectorAll<HTMLElement>(`[data-nav="${columna}"]`))
      .filter((n) => !(n as HTMLButtonElement).disabled);
    const recuerdo: Record<string, HTMLElement | undefined> = {};
    let ultima = 'menu';   // la columna en la que se estuvo por última vez (el foco puede perderse, p. ej. al guardar)
    const columnaDe = (n: HTMLElement) => n.dataset.nav ?? (n.closest('.ficha') ? 'alux' : 'menu');
    const alEnfocar = (e: FocusEvent) => {
      const n = e.target as HTMLElement | null;
      if (!n) return;
      ultima = columnaDe(n);
      if (n.dataset.nav) recuerdo[n.dataset.nav] = n;
    };
    const tecla = (e: KeyboardEvent) => {
      if (e.defaultPrevented || e.altKey || e.ctrlKey || e.metaKey || ocupado.current) return;
      if (document.querySelector('.apartado-fondo')) return;   // hay un apartado abierto encima
      const activo = document.activeElement as HTMLElement | null;
      const el = activo && menu.contains(activo) ? activo : null;
      const esTexto = el instanceof HTMLInputElement && el.type !== 'checkbox';
      const columna = el ? columnaDe(el) : ultima;
      const ir = (n?: HTMLElement | null) => { if (n) { e.preventDefault(); n.focus(); } };
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        const lista = opciones(columna);
        if (!lista.length) return;
        const paso = e.key === 'ArrowDown' ? 1 : -1;
        const i = el ? lista.indexOf(el) : -1;
        ir(i < 0 ? lista[paso > 0 ? 0 : lista.length - 1] : lista[(i + paso + lista.length) % lista.length]);
      } else if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
        const derecha = e.key === 'ArrowRight';
        if (esTexto) {
          // Dentro de un campo las flechas mueven el cursor; sólo en su borde se cambia de columna
          const borde = derecha ? el.value.length : 0;
          if (el.selectionStart !== borde || el.selectionEnd !== borde) return;
        }
        if (el?.classList.contains('swatch')) {
          // Entre colores, ← → eligen el de al lado
          const colores = Array.from(el.parentElement!.querySelectorAll<HTMLElement>('.swatch'));
          const otro = colores[colores.indexOf(el) + (derecha ? 1 : -1)];
          if (otro) { e.preventDefault(); otro.focus(); otro.click(); return; }
        }
        const hacia = derecha ? 'alux' : 'menu';
        if (hacia === columna) return;
        const lista = opciones(hacia);
        const previa = recuerdo[hacia];
        ir(previa && lista.includes(previa) ? previa : lista[0]);
      } else if (e.key === 'Enter' && el instanceof HTMLInputElement && el.type === 'checkbox') {
        e.preventDefault();
        el.click();
      }
    };
    // El ratón mueve el mismo cursor que el teclado: la opción bajo el puntero queda elegida
    const alPasar = (e: MouseEvent) => {
      const opcion = (e.target as HTMLElement).closest<HTMLElement>('.opcion');
      const activo = document.activeElement;
      if (!opcion || opcion === activo || (opcion as HTMLButtonElement).disabled) return;
      if (activo instanceof HTMLInputElement && activo.type !== 'checkbox') return;   // no se le quita el foco a quien escribe
      opcion.focus({ preventScroll: true });
    };
    document.addEventListener('keydown', tecla);
    menu.addEventListener('focusin', alEnfocar);
    menu.addEventListener('mouseover', alPasar);
    return () => {
      document.removeEventListener('keydown', tecla);
      menu.removeEventListener('focusin', alEnfocar);
      menu.removeEventListener('mouseover', alPasar);
    };
  }, []);
  // Al llegar al menú queda elegida «Entrar al mundo»; al abrir una sala, «JUGAR»
  const enSala = room !== null;
  useEffect(() => {
    raiz.current?.querySelector<HTMLElement>('[data-nav="menu"]:not(:disabled)')?.focus({ preventScroll: true });
  }, [enSala]);

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
    <main className="menu" ref={raiz}>
      <Luciernagas />
      <header className="menu-cabecera">
        <p className="logo">ALUX <small>El Despertar de Kukulkán</small></p>
        <div className="user">
          {profile.avatarUrl ? <img src={profile.avatarUrl} alt="" width={36} height={36} /> : <span className="avatar-fallback" style={{ background: profile.character.color }} />}
          <span>{profile.displayName}</span>
        </div>
      </header>

      {error && <p className="error banner" role="alert">{error}</p>}

      <div className="menu-cuerpo">
        {!room ? (
          <nav className="menu-lista" aria-label="Menú principal">
            <p className="eyebrow">Menú principal</p>
            {/* El mundo: la plaza social, donde se pasea, se ve a otros aluxes y se cruza el portal al Claro */}
            <a className="opcion principal plaza" href="/plaza" data-nav="menu" onClick={alIr('plaza', '/plaza', true)}>
              <span className="opcion-titulo">Entrar al mundo</span>
              <small>Mérida, la Ciudad Blanca · la plaza de los aluxes</small>
            </a>
            <div className="grupo" role="group" aria-labelledby="grupo-mision">
              <h2 id="grupo-mision" className="grupo-titulo">Misión cooperativa <small>El Claro de los Aluxes</small></h2>
              <button type="button" className="opcion" data-nav="menu" disabled={busy}
                onClick={() => run(() => api<RoomInfo>('/rooms', { method: 'POST', body: JSON.stringify({ visibility: 'private' }) }))}>
                <span className="opcion-titulo">Crear sala privada</span>
                <small>Invita a tus amigos con un código</small>
              </button>
              <button type="button" className="opcion" data-nav="menu" disabled={busy} onClick={() => run(() => api<RoomInfo>('/rooms/quick', { method: 'POST' }))}>
                <span className="opcion-titulo">Partida pública</span>
                <small>Te unimos con otros aluxes</small>
              </button>
              <form className="join" onSubmit={(e) => { e.preventDefault(); if (code.trim()) run(() => api<RoomInfo>(`/rooms/${code.trim().toUpperCase()}`)); }}>
                <label htmlFor="join-code">Unirme con código</label>
                <div>
                  <input id="join-code" data-nav="menu" value={code} maxLength={12} placeholder="ABC123" autoComplete="off"
                    onChange={(e) => setCode(e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, ''))} />
                  <button className="btn ghost" disabled={busy || code.length < 4}>Unirme</button>
                </div>
              </form>
            </div>
            <a className="opcion look-3d" href="/alux" data-nav="menu" onClick={alIr('alux', '/alux', false)}>
              <span className="opcion-titulo">Personalizar mi alux</span>
              <small>Vestimenta, tocados, accesorios y amuletos, en 3D</small>
            </a>
            <div className="menu-menores">
              <Panel clase="opcion menor" nav="menu" etiqueta={<span className="opcion-titulo">Cómo se juega</span>} titulo="Cómo se juega">
                <ul className="howto">
                  <li>Pisen los altares a la vez para abrir el santuario y venzan la emboscada</li>
                  <li><kbd>W A S D</kbd> moverse · <kbd>Espacio</kbd> saltar · ratón para mirar</li>
                  <li><kbd>Clic</kbd> atacar · <kbd>Clic derecho</kbd> esquivar · <kbd>F</kbd> tocar o purificar</li>
                  <li><kbd>1</kbd> Alux · <kbd>2</kbd> Balam, el jaguar (corre, salta y pega más)</li>
                  <li><kbd>Esc</kbd> menú: volumen, sensibilidad y salir · <kbd>H</kbd> controles</li>
                  <li>Una partida dura unos 10 minutos y se puede jugar de 1 a 4</li>
                </ul>
              </Panel>
              <form method="post" action="/auth/logout">
                <button className="opcion menor" type="submit" data-nav="menu"><span className="opcion-titulo">Cerrar sesión</span></button>
              </form>
            </div>
          </nav>
        ) : (
          <section className="menu-lista room" aria-label="Sala">
            <p className="eyebrow">Misión cooperativa · {room.visibility === 'private' ? 'sala privada' : 'sala pública'}</p>
            <div className="room-code" aria-label="Código de sala">{room.code}</div>
            <ul className="members">
              {[0, 1, 2, 3].map((i) => {
                const m = room.members[i];
                return m ? (
                  <li key={m.id}><i style={{ background: m.color }} /><span>{m.name}</span><em>{m.online ? 'en el claro' : 'en el menú'}</em></li>
                ) : (
                  <li key={i} className="empty"><i />Lugar libre</li>
                );
              })}
            </ul>
            {room.gateOpen && <p className="note">Esta sala ya abrió el santuario.</p>}
            <button className="btn big enter" data-nav="menu" onClick={play}>
              JUGAR
              <small>Entrar al Claro de los Aluxes</small>
            </button>
            <div className="invite">
              <input readOnly value={inviteUrl} onFocus={(e) => e.currentTarget.select()} aria-label="Enlace de invitación" />
              <button className="btn ghost" data-nav="menu" onClick={() => copy('link')}>{copied === 'link' ? 'Copiado' : 'Copiar enlace'}</button>
              <button className="btn ghost discord-outline" data-nav="menu" onClick={() => copy('discord')}>{copied === 'discord' ? 'Copiado' : 'Copiar para Discord'}</button>
            </div>
            <button className="link" data-nav="menu" onClick={() => setRoom(null)}>← Volver al menú</button>
          </section>
        )}

        <section className="ficha" aria-label="Tu alux">
          <div className="alux-editor">
            <div className="alux-stage"><AluxPreview color={color} hat={hat} size={150} /></div>
            <div className="alux-fields">
              <p className="eyebrow">Tu alux</p>
              <label htmlFor="alux-name">Nombre</label>
              <input id="alux-name" data-nav="alux" value={name} maxLength={20} onChange={(e) => setName(e.target.value)}
                onKeyDown={(e) => { if (e.key === 'Enter' && canSave) void saveCharacter(); }} />
              <span className="label">Color</span>
              <div className="swatches" role="radiogroup" aria-label="Color de la túnica">
                {ALUX_COLORS.map((c) => (
                  <button key={c} type="button" role="radio" aria-checked={color === c} aria-label={c} tabIndex={color === c ? 0 : -1}
                    data-nav={color === c ? 'alux' : undefined}
                    className={color === c ? 'swatch on' : 'swatch'} style={{ background: c }} onClick={() => setColor(c)} />
                ))}
              </div>
            </div>
          </div>
          <p className="look-line"><span className="label">Lleva</span> {lookLine(profile)}</p>
          <div className="row">
            <button className="btn" data-nav="alux" disabled={!canSave} onClick={saveCharacter}>
              {saving ? 'Guardando…' : 'Guardar alux'}
            </button>
            <span className="saved">{savedMsg}</span>
          </div>

          <h3>Tu progreso</h3>
          <ul className="progress">
            {profile.rpg ? (
              <li>
                <span className="tag relic">Nivel {profile.rpg.level}</span>
                <span>
                  {profile.rpg.xpToNext > 0 ? `${profile.rpg.xpInLevel} / ${profile.rpg.xpToNext} de experiencia` : 'nivel máximo'}
                  {' · '}{profile.rpg.seeds} {profile.rpg.seeds === 1 ? 'semilla' : 'semillas'} de jade
                </span>
              </li>
            ) : null}
            {profile.unlocks.map((f) => (
              <li key={f}><span className="tag form">Forma</span><span>{FORM_NAMES[f] ?? f}</span></li>
            ))}
            {Object.entries(REWARDS).map(([key, r]) => {
              const have = profile.rewards.includes(key);
              const tag = !have ? 'Pendiente' : r.kind === 'object' ? 'Objeto ancestral' : 'Capítulo I';
              return (
                <li key={key} className={have ? '' : 'locked'}>
                  <span className={`tag ${r.kind === 'object' ? 'relic' : 'seal'}`}>{tag}</span>
                  <span>{r.title}{have && r.note ? <small className="reward-note"> · {r.note}</small> : null}</span>
                </li>
              );
            })}
          </ul>
        </section>
      </div>

      <footer className="menu-pie">
        <div className="menu-ajustes">
          {canFullscreen && (
            <label className="fs-pref">
              <input type="checkbox" data-nav="menu" checked={fullscreen} onChange={(e) => chooseFullscreen(e.target.checked)} />
              Pantalla completa al jugar
            </label>
          )}
          {enPantalla && (
            <button className="link" type="button" onClick={() => { void document.exitFullscreen().catch(() => {}); }}>Salir de pantalla completa</button>
          )}
        </div>
        <p className="teclas" aria-hidden="true"><kbd>↑</kbd><kbd>↓</kbd> moverse <kbd>←</kbd><kbd>→</kbd> menú / alux <kbd>Enter</kbd> elegir</p>
      </footer>

      {saliendo && <Velo destino={saliendo.destino} sala={saliendo.sala} fase="entra" />}
    </main>
  );
}
