'use client';

import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Velo, type Destino } from './Velo';

// La pantalla de carga nunca se queda puesta: pasado este tiempo se retira y deja ver lo que
// haya debajo (la carga propia del juego, que sigue mostrando su avance).
const MAXIMO_MS = 45_000;
// Con la página del juego ya cargada, lo que se espera a que la descarga del motor dé señales
const SIN_AVANCE_MS = 12_000;
// Lo que tarda en desvanecerse (igual que la transición de `.velo` en la hoja de estilos)
const DESVANECE_MS = 750;

/** Lo que el juego deja a la vista en su página sin depuración (game/web/shell.html). */
type VentanaJuego = Window & { ALUX?: { engineMs?: number }; Engine?: unknown };

/** La parte de la Navigation API que se usa aquí (no está en todos los navegadores). */
type AvisoDeNavegacion = Event & {
  destination: { url: string; sameDocument: boolean };
  hashChange: boolean;
  downloadRequest: string | null;
  formData: FormData | null;
};

// El juego dentro del portal (una sala, la plaza o el personalizador del alux). Así la pantalla
// completa que pidió el menú sigue puesta mientras carga: cambiar de página la quitaría. El juego
// es la misma página de siempre (/game/index.html), que también funciona abierta directamente.
// Encima va la pantalla de carga del portal, hasta que el motor del juego arranca.
export function PlayFrame({ src, title = 'ALUX: El Despertar de Kukulkán', destino, sala }: {
  src: string;
  title?: string;
  destino: Destino;
  /** Código de la sala, si se entra a una. */
  sala?: string;
}) {
  const frame = useRef<HTMLIFrameElement>(null);
  const router = useRouter();
  const [fase, setFase] = useState<'puesto' | 'sale' | 'fuera'>('puesto');
  const [progreso, setProgreso] = useState<number | null>(null);
  // Sala a la que salta el juego desde la plaza sin recargar la página (ver más abajo)
  const [salto, setSalto] = useState<string | null>(null);

  useEffect(() => {
    const focus = () => frame.current?.focus();
    focus();
    window.addEventListener('focus', focus);
    document.addEventListener('fullscreenchange', focus);
    return () => {
      window.removeEventListener('focus', focus);
      document.removeEventListener('fullscreenchange', focus);
    };
  }, []);

  // Cuándo se retira la pantalla de carga. El marco es del mismo origen, así que se mira la página
  // del juego, sin depender de ?debug=1:
  //  - `ALUX.engineMs > 0`: el motor arrancó (lo apunta el juego al quitar su propia carga) → fuera.
  //  - El texto de `#status` cambia: el juego está contando algo suyo (un error, un navegador que
  //    no sirve) → fuera al momento, para no taparlo.
  //  - Un error sin atrapar en la página del juego, una página que no es el juego (no se exportó,
  //    la sesión caducó) o un marco que no se puede leer → fuera al momento.
  //  - La página del juego terminó de cargar y la descarga no llega a empezar, o se cumple el
  //    tiempo máximo → fuera.
  // Mientras tanto se copia el avance de la barra del juego (`#bar`).
  useEffect(() => {
    const inicio = performance.now();
    // El texto de `#status` tal como viene escrito en la página del juego: se lee de la propia
    // página (no del marco, donde el juego ya pudo cambiarlo). `undefined` mientras llega.
    let estadoNormal: string | null | undefined;
    let primerEstado = '';
    let cancelado = false;
    fetch(src, { credentials: 'same-origin' })
      .then((r) => (r.ok ? r.text() : Promise.reject(new Error(String(r.status)))))
      .then((html) => new DOMParser().parseFromString(html, 'text/html').getElementById('status')?.textContent?.trim() || null)
      .catch(() => null)
      .then((texto) => { if (!cancelado) estadoNormal = texto; });
    let completa = 0;   // cuándo se vio cargada del todo la página del juego
    let avance = 0;
    let vista: Window | null = null;
    let reloj = 0;
    let retirada = 0;
    const retirar = () => {
      window.clearInterval(reloj);
      vista?.removeEventListener('error', retirar, true);
      vista?.removeEventListener('unhandledrejection', retirar);
      setFase((f) => (f === 'puesto' ? 'sale' : f));
      retirada = window.setTimeout(() => setFase('fuera'), DESVANECE_MS);
    };
    const mirar = () => {
      if (performance.now() - inicio > MAXIMO_MS) return retirar();
      try {
        const w = frame.current?.contentWindow as VentanaJuego | null | undefined;
        if (!w || w.location.href === 'about:blank') return;   // el marco aún no ha empezado
        const doc = w.document;
        if (w !== vista) {
          vista?.removeEventListener('error', retirar, true);
          vista?.removeEventListener('unhandledrejection', retirar);
          vista = w;
          w.addEventListener('error', retirar, true);
          w.addEventListener('unhandledrejection', retirar);
        }
        if (Number(w.ALUX?.engineMs) > 0) return retirar();
        const estado = doc.getElementById('status')?.textContent?.trim() ?? '';
        if (estado && estadoNormal !== undefined) {
          // Si no se pudo leer el texto de la página, vale el primero que se vio en el marco
          if (!estadoNormal && !primerEstado) primerEstado = estado;
          if (estado !== (estadoNormal || primerEstado)) return retirar();
        }
        const ancho = parseFloat(doc.querySelector<HTMLElement>('#bar > div')?.style.width ?? '');
        if (ancho > 0) { avance = ancho; setProgreso(ancho); }
        if (doc.readyState === 'complete') {
          if (!w.ALUX || typeof w.Engine !== 'function') return retirar();   // no es el juego, o no llegó entero
          if (!completa) completa = performance.now();
          if (!avance && performance.now() - completa > SIN_AVANCE_MS) return retirar();
        }
      } catch {
        retirar();   // no se puede leer el marco: no se tapa lo que no se ve
      }
    };
    reloj = window.setInterval(mirar, 60);
    return () => {
      cancelado = true;
      window.clearInterval(reloj);
      window.clearTimeout(retirada);
      vista?.removeEventListener('error', retirar, true);
      vista?.removeEventListener('unhandledrejection', retirar);
    };
  }, [src]);

  // Con la pantalla completa puesta, los saltos de página que pide el juego (de la plaza a una
  // sala, o salir al menú) se hacen sin recargar: una recarga la quitaría. Sólo donde el navegador
  // tiene la Navigation API y sólo para esas dos rutas; en ventana, o si falla, se recarga como
  // siempre.
  useEffect(() => {
    const navegacion = (window as unknown as { navigation?: EventTarget }).navigation;
    if (!navegacion) return;
    let ultima = '';
    let cuando = 0;
    const alNavegar = (ev: Event) => {
      const e = ev as AvisoDeNavegacion;
      if (!document.fullscreenElement || !e.cancelable || e.destination.sameDocument || e.hashChange || e.downloadRequest || e.formData) return;
      const url = new URL(e.destination.url);
      const ruta = /^\/(?:hub|play\/([A-Za-z0-9]{1,12}))$/.exec(url.pathname);
      if (url.origin !== window.location.origin || !ruta) return;
      const destinoUrl = url.pathname + url.search;
      // Si la misma ruta se pide otra vez enseguida es que no salió bien: se deja recargar
      if (destinoUrl === ultima && performance.now() - cuando < 10_000) return;
      ultima = destinoUrl;
      cuando = performance.now();
      e.preventDefault();
      if (ruta[1]) setSalto(ruta[1].toUpperCase());
      router.push(destinoUrl);
    };
    navegacion.addEventListener('navigate', alNavegar);
    return () => navegacion.removeEventListener('navigate', alNavegar);
  }, [router]);

  // El juego bloquea Esc mientras hay pantalla completa (abre su menú). Al irse el juego, Esc
  // vuelve a ser del navegador: en el menú sirve para salir de la pantalla completa.
  useEffect(() => () => {
    try { (navigator as unknown as { keyboard?: { unlock?: () => void } }).keyboard?.unlock?.(); } catch { /* sin bloqueo de teclado */ }
  }, []);

  return (
    <>
      <iframe
        ref={frame}
        className="play-frame"
        title={title}
        src={src}
        allow="fullscreen; autoplay; gamepad; keyboard-lock; pointer-lock"
        allowFullScreen
        onLoad={() => frame.current?.focus()}
      />
      {fase !== 'fuera' && <Velo destino={destino} sala={sala} progreso={progreso} fase={fase} />}
      {salto && <Velo destino="sala" sala={salto} fase="entra" />}
    </>
  );
}
