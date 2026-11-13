import type { CSSProperties } from 'react';

// Luciérnagas del fondo (título, menú y pantalla de carga). Las posiciones son fijas, no al azar:
// así el servidor y el navegador pintan lo mismo. El movimiento lo pone la hoja de estilos.
const LUCES: [x: number, y: number, tamano: number, segundos: number, retraso: number, dx: number, dy: number][] = [
  [6, 72, 7, 9, 0, 26, -34],
  [14, 38, 5, 11, -3, -18, -26],
  [23, 84, 6, 8, -5, 30, -20],
  [31, 22, 4, 13, -2, 16, 22],
  [42, 64, 5, 10, -7, -24, -30],
  [51, 90, 7, 12, -1, 20, -40],
  [58, 30, 4, 9, -6, -14, 18],
  [66, 76, 6, 14, -4, 28, -24],
  [74, 48, 5, 10, -8, -22, -18],
  [82, 86, 7, 11, -2, -30, -36],
  [89, 26, 4, 12, -9, 14, 26],
  [95, 62, 6, 9, -5, -26, -22],
];

export function Luciernagas() {
  return (
    <div className="luciernagas" aria-hidden="true">
      {LUCES.map(([x, y, s, d, r, dx, dy], i) => (
        <i key={i} style={{ '--x': `${x}%`, '--y': `${y}%`, '--s': `${s}px`, '--d': `${d}s`, '--r': `${r}s`, '--dx': `${dx}px`, '--dy': `${dy}px` } as CSSProperties} />
      ))}
    </div>
  );
}
