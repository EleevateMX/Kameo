'use client';

import { useEffect, useRef } from 'react';

// El juego dentro del portal (una sala o el personalizador del alux). Así la pantalla completa
// que pidió el botón JUGAR sigue puesta mientras carga: cambiar de página la quitaría. El juego
// es la misma página de siempre (/game/index.html), que también funciona abierta directamente.
export function PlayFrame({ src, title = 'ALUX: El Despertar de Kukulkán' }: { src: string; title?: string }) {
  const frame = useRef<HTMLIFrameElement>(null);
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
  return (
    <iframe
      ref={frame}
      className="play-frame"
      title={title}
      src={src}
      allow="fullscreen; autoplay; gamepad; keyboard-lock; pointer-lock"
      allowFullScreen
      onLoad={() => frame.current?.focus()}
    />
  );
}
