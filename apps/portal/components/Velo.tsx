'use client';

import { useEffect, useLayoutEffect, useState } from 'react';
import { Luciernagas } from './Luciernagas';

/** A dónde se va: la plaza de Mérida, una sala del Claro de los Aluxes o el personalizador. */
export type Destino = 'plaza' | 'sala' | 'alux';

const DESTINOS: Record<Destino, { rumbo: string; titulo: string; lugar: string; consejos: string[] }> = {
  plaza: {
    rumbo: 'Entrando al mundo',
    titulo: 'Mérida, la Ciudad Blanca',
    lugar: 'La plaza de los aluxes',
    consejos: [
      'En la plaza puedes pasear, ver a otros aluxes y cruzar el portal hacia el Claro.',
      'W A S D para moverte, Espacio para saltar y el ratón para mirar.',
      'Esc abre el menú del juego: volumen, sensibilidad y salir.',
    ],
  },
  sala: {
    rumbo: 'Misión cooperativa',
    titulo: 'El Claro de los Aluxes',
    lugar: 'Misión para 1 a 4 aluxes',
    consejos: [
      'Pisen los altares a la vez: ningún alux abre el santuario solo.',
      'Pulsa 2 para tomar la forma de Balam, el jaguar: corre, salta y pega más.',
      'Clic para atacar, clic derecho para esquivar y F para tocar o purificar.',
      'Una partida dura unos 10 minutos y se puede jugar de 1 a 4.',
      'Esc abre el menú del juego y H muestra los controles.',
    ],
  },
  alux: {
    rumbo: 'Personalizador',
    titulo: 'Tu alux',
    lugar: 'Vestimenta, tocados, accesorios y amuletos',
    consejos: [
      'Lo que elijas aquí es lo que verán tus compañeros en la partida.',
      'Tu alux se guarda en tu perfil: te espera tal cual al volver.',
    ],
  },
};

// El consejo elegido al salir del menú es el mismo que se ve al llegar: se apunta unos segundos
const CLAVE = 'alux_consejo';
function consejoInicial(destino: Destino, cuantos: number): number {
  try {
    const visto = JSON.parse(sessionStorage.getItem(CLAVE) || 'null') as { d: string; i: number; t: number } | null;
    if (visto && visto.d === destino && Date.now() - visto.t < 20_000 && visto.i < cuantos) return visto.i;
  } catch { /* sin almacenamiento */ }
  const i = Math.floor(Math.random() * cuantos);
  try { sessionStorage.setItem(CLAVE, JSON.stringify({ d: destino, i, t: Date.now() })); } catch { /* sin almacenamiento */ }
  return i;
}

// En el servidor no hay efectos de disposición: allí basta el efecto normal (que no se ejecuta)
const alMontar = typeof window === 'undefined' ? useEffect : useLayoutEffect;

/** El sello que gira: cuatro luces (los cuatro aluxes de una partida) alrededor de un ojo de jade. */
function Sello() {
  return (
    <svg className="sello" viewBox="0 0 64 64" width="54" height="54" aria-hidden="true">
      <circle className="sello-aro" cx="32" cy="32" r="26" fill="none" stroke="currentColor" strokeWidth="2" strokeDasharray="5 9" strokeLinecap="round" />
      <g className="sello-giro">
        <circle cx="32" cy="6" r="4.5" fill="#2ec4a6" />
        <circle cx="58" cy="32" r="4.5" fill="#e4007c" />
        <circle cx="32" cy="58" r="4.5" fill="#ffd23f" />
        <circle cx="6" cy="32" r="4.5" fill="#ff7a1a" />
      </g>
      <path className="sello-ojo" d="M32 19 45 32 32 45 19 32z" fill="#5ff5e0" />
    </svg>
  );
}

/**
 * Pantalla de carga con la identidad del portal. Es sólo imagen: no recibe clics ni teclas, así
 * que el juego que hay debajo se comporta igual con ella puesta.
 *  - `entra`: aparece sobre el menú al elegir un destino (ahí sí tapa los clics).
 *  - `puesto`: cubre el juego mientras carga.
 *  - `sale`: se desvanece y deja ver el juego.
 */
export function Velo({ destino, sala, progreso = null, fase = 'puesto' }: {
  destino: Destino;
  sala?: string;
  /** Avance de la descarga del juego, de 0 a 100; `null` si aún no se sabe. */
  progreso?: number | null;
  fase?: 'entra' | 'puesto' | 'sale';
}) {
  const info = DESTINOS[destino];
  const [consejo, setConsejo] = useState<number | null>(null);
  alMontar(() => { setConsejo(consejoInicial(destino, info.consejos.length)); }, [destino, info.consejos.length]);
  // En una carga larga, los consejos van pasando
  useEffect(() => {
    const t = setInterval(() => setConsejo((i) => (i === null ? 0 : (i + 1) % info.consejos.length)), 8000);
    return () => clearInterval(t);
  }, [info.consejos.length]);

  const lugar = destino === 'sala' && sala ? `Sala ${sala}` : info.lugar;
  const avance = progreso === null ? null : Math.max(0, Math.min(100, Math.round(progreso)));
  return (
    <div className={`velo ${fase}`} role="status" aria-live="polite" aria-label={`Cargando: ${info.titulo}`}>
      <div className="velo-arte" aria-hidden="true" />
      <Luciernagas />
      <p className="velo-marca" aria-hidden="true">ALUX</p>
      <div className="velo-destino">
        <p className="eyebrow">{info.rumbo}</p>
        <h1>{info.titulo}</h1>
        <p className="velo-lugar">{lugar}</p>
      </div>
      <div className="velo-pie">
        <Sello />
        <div className="velo-texto">
          <p className="velo-consejo" key={consejo ?? -1}>
            {consejo !== null && <><b>Consejo</b>{info.consejos[consejo]}</>}
          </p>
          <div className={avance === null ? 'velo-barra espera' : 'velo-barra'}>
            <i style={{ width: `${avance ?? 100}%` }} />
          </div>
        </div>
        <p className="velo-avance">{avance === null || avance >= 100 ? 'Cargando…' : `${avance} %`}</p>
      </div>
    </div>
  );
}
