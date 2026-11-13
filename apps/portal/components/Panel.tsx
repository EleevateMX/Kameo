'use client';

import { useEffect, useRef, useState, type ReactNode } from 'react';

// Un apartado del menú que se abre encima de la pantalla (la leyenda, cómo se juega) y se cierra
// con Esc, con «Volver» o pulsando fuera. Al cerrar, el foco vuelve a la opción que lo abrió.
export function Panel({ etiqueta, titulo, clase, nav, children }: {
  etiqueta: ReactNode;
  titulo: string;
  clase?: string;
  /** Columna del menú a la que pertenece la opción (navegación con flechas). */
  nav?: string;
  children: ReactNode;
}) {
  const [abierto, setAbierto] = useState(false);
  const boton = useRef<HTMLButtonElement>(null);
  const volver = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!abierto) return;
    const origen = boton.current;
    volver.current?.focus();
    const tecla = (e: KeyboardEvent) => {
      if (e.key === 'Escape') { e.preventDefault(); setAbierto(false); }
      // Sólo hay un control dentro: el tabulador no sale del apartado
      if (e.key === 'Tab') { e.preventDefault(); volver.current?.focus(); }
    };
    document.addEventListener('keydown', tecla);
    return () => {
      document.removeEventListener('keydown', tecla);
      origen?.focus();
    };
  }, [abierto]);

  return (
    <>
      <button ref={boton} type="button" className={clase} data-nav={nav} aria-haspopup="dialog" onClick={() => setAbierto(true)}>
        {etiqueta}
      </button>
      {abierto && (
        <div className="apartado-fondo" onClick={() => setAbierto(false)}>
          <section className="apartado" role="dialog" aria-modal="true" aria-label={titulo} onClick={(e) => e.stopPropagation()}>
            <h2>{titulo}</h2>
            <div className="apartado-cuerpo">{children}</div>
            <button ref={volver} type="button" className="btn ghost" onClick={() => setAbierto(false)}>
              Volver <kbd>Esc</kbd>
            </button>
          </section>
        </div>
      )}
    </>
  );
}
