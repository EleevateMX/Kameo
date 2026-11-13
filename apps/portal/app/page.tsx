import { redirect } from 'next/navigation';
import { AluxPreview } from '@/components/AluxPreview';
import { Luciernagas } from '@/components/Luciernagas';
import { Panel } from '@/components/Panel';
import { betaLoginEnabled, devLoginEnabled, discordEnabled } from '@/lib/env';
import { getProfile, safeNext } from '@/lib/session';

export const dynamic = 'force-dynamic';

const ERRORS: Record<string, string> = {
  cancelado: 'Cancelaste el inicio de sesión con Discord.',
  estado_invalido: 'La sesión de inicio expiró. Inténtalo de nuevo.',
  discord: 'Discord no respondió. Inténtalo de nuevo en un momento.',
  discord_no_configurado: 'El inicio de sesión con Discord aún no está configurado en este servidor.',
  dev_desactivado: 'La entrada de prueba está desactivada.',
  beta_desactivada: 'El acceso de testers está cerrado.',
  beta_codigo: 'Ese código de invitación no es válido o ya venció. Revísalo o pide uno nuevo a quien te invitó.',
  beta_intentos: 'Demasiados intentos. Espera unos minutos y vuelve a probar.',
  api: 'El servidor del juego no está disponible. Inténtalo de nuevo en un momento.',
};

const FEATURES = [
  { big: '4', title: 'Jugadores por partida', text: 'Cooperativo con salas privadas por código y partidas públicas.' },
  { big: '3D', title: 'Sin instalación', text: 'Se juega desde el navegador de tu computadora.' },
  { big: '∞', title: 'Transformaciones', text: 'Toma la forma de Balam, el jaguar. Vendrán más hasta llegar a Kukulkán.' },
  { big: '✓', title: 'Progreso guardado', text: 'Tu alux, tus sellos y tus formas te esperan al volver.' },
];

// La pantalla de título del juego: el arte, el nombre y, en la misma pantalla, la entrada
// (invitación de tester, Discord o entrada de prueba). Ocupa la ventana entera, sin página debajo:
// la leyenda se abre como un apartado del título.
export default async function Home({ searchParams }: { searchParams: Promise<{ error?: string; next?: string }> }) {
  const sp = await searchParams;
  const next = safeNext(sp.next);
  if (await getProfile()) redirect(next);
  const error = sp.error ? ERRORS[sp.error] ?? 'Algo salió mal. Inténtalo de nuevo.' : null;
  const invited = next.startsWith('/play/');

  return (
    <main className="landing titulo">
      <div className="hero-art" aria-hidden="true" />
      <Luciernagas />
      <section className="hero">
        <div className="hero-inner">
          <p className="eyebrow">Aventura cooperativa · Yucatán</p>
          <h1>ALUX</h1>
          <h2>El Despertar de Kukulkán</h2>
          {/* Si la entrada falló, el aviso ocupa el sitio del lema: justo encima de por donde se entra */}
          {error ? <p className="error" role="alert">{error}</p> : (
            <p className="tagline">
              {invited ? 'Te invitaron a una sala. Inicia sesión para entrar con tu alux.' : 'Tu leyenda comienza aquí. Explora los misterios de Yucatán junto a tus amigos.'}
            </p>
          )}
          <div className="entrada">
            {betaLoginEnabled ? null : discordEnabled ? (
              <div className="cta">
                <a className="btn discord" href={`/auth/discord?next=${encodeURIComponent(next)}`}>
                  <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true"><path fill="currentColor" d="M19.6 5.2A17 17 0 0 0 15.4 4l-.5 1a15.600 15.600 0 0 0-5.800 0L8.600 4a17 17 0 0 0-4.200 1.200C1.700 9.200 1 13 1.300 16.900a17 17 0 0 0 5.200 2.600l1.100-1.800c-.600-.200-1.200-.500-1.700-.800l.400-.300a12.200 12.200 0 0 0 11.400 0l.400.300c-.500.300-1.100.600-1.700.800l1.100 1.800a17 17 0 0 0 5.200-2.600c.400-4.500-.700-8.300-3.100-11.700ZM8.700 14.600c-1 0-1.900-1-1.900-2.100s.800-2.100 1.900-2.100 1.900 1 1.900 2.100-.800 2.100-1.900 2.100Zm6.600 0c-1 0-1.900-1-1.900-2.100s.800-2.100 1.900-2.100 1.900 1 1.900 2.100-.800 2.100-1.900 2.100Z" /></svg>
                  Iniciar sesión con Discord
                </a>
              </div>
            ) : (
              <div className="cta">
                <span className="btn discord disabled" title="Configura DISCORD_CLIENT_ID y DISCORD_CLIENT_SECRET">Discord aún no está configurado</span>
              </div>
            )}
            {betaLoginEnabled && (
              <form className="dev-login beta-login" method="post" action="/auth/beta">
                <input type="hidden" name="next" value={next} />
                <label htmlFor="beta-code">Closed Alpha 0.4 · entra con tu código de invitación</label>
                <div>
                  <input id="beta-code" name="code" maxLength={64} placeholder="ALUX-XXXXX-XXXXX-XXXXX-XXXXX" autoComplete="off"
                    autoCapitalize="characters" spellCheck={false} required autoFocus />
                  <button className="btn" type="submit">Entrar</button>
                </div>
                <small>El código es personal: no lo compartas. Si no tienes uno, pídelo a quien organiza la prueba.</small>
              </form>
            )}
            {devLoginEnabled && (
              <form className="dev-login" method="post" action="/auth/dev">
                <input type="hidden" name="next" value={next} />
                <label htmlFor="dev-name">Entrada de prueba (sin Discord)</label>
                <div>
                  <input id="dev-name" name="name" maxLength={20} placeholder="Nombre de tu alux" autoComplete="off" />
                  <button className="btn ghost" type="submit">Entrar</button>
                </div>
              </form>
            )}
          </div>
        </div>
      </section>

      <footer className="titulo-pie">
        <ul className="features">
          {FEATURES.map((f) => (
            <li key={f.title} className="feature">
              <b>{f.big}</b>
              <h3>{f.title}</h3>
              <p>{f.text}</p>
            </li>
          ))}
        </ul>
        <div className="titulo-credito">
          <Panel clase="btn ghost leyenda" etiqueta="La leyenda" titulo="Cuatro aluxes, un mismo camino">
            <div className="story">
              <div className="story-aluxes" aria-hidden="true">
                <AluxPreview color="#19b4d6" hat={0} size={96} />
                <AluxPreview color="#e4007c" hat={1} size={96} />
                <AluxPreview color="#ffd23f" hat={2} size={96} />
                <AluxPreview color="#ff7a1a" hat={0} size={96} />
              </div>
              <p>
                Los aluxes han cuidado la selva desde antes de que hubiera caminos. Ahora algo se mueve bajo los cenotes y los
                santuarios antiguos se han sellado. Ningún alux puede abrirlos solo: cada sello pide que varios guardianes actúen
                a la vez.
              </p>
              <p>
                Crea tu alux, reúne a tu grupo y entren juntos al Claro de los Aluxes. Transfórmate en Balam para llegar donde
                otros no alcanzan y abran el primer santuario. Es el comienzo del camino hacia Kukulkán.
              </p>
            </div>
          </Panel>
          <span>ALUX es un proyecto original inspirado en las leyendas mayas de Yucatán.</span>
        </div>
      </footer>
    </main>
  );
}
