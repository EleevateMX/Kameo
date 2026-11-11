// Retrato del alux en SVG, con el mismo aspecto que el modelo 3D del juego.
export function AluxPreview({ color, hat, size = 200 }: { color: string; hat: number; size?: number }) {
  return (
    <svg viewBox="0 0 200 220" width={size} height={size * 1.1} role="img" aria-label="Vista previa de tu alux">
      <defs>
        <radialGradient id="eye" cx="50%" cy="50%" r="50%">
          <stop offset="0%" stopColor="#ffffff" />
          <stop offset="45%" stopColor="#5ff5e0" />
          <stop offset="100%" stopColor="#1fb89c" />
        </radialGradient>
        <filter id="glow" x="-80%" y="-80%" width="260%" height="260%">
          <feGaussianBlur stdDeviation="4" result="b" />
          <feMerge><feMergeNode in="b" /><feMergeNode in="SourceGraphic" /></feMerge>
        </filter>
      </defs>
      <ellipse cx="100" cy="208" rx="52" ry="8" fill="rgba(0,0,0,.35)" />
      {/* piernas y brazos */}
      <rect x="78" y="168" width="16" height="36" rx="8" fill="#8c5b3c" />
      <rect x="106" y="168" width="16" height="36" rx="8" fill="#8c5b3c" />
      <rect x="52" y="126" width="14" height="40" rx="7" fill="#8c5b3c" transform="rotate(14 59 126)" />
      <rect x="134" y="126" width="14" height="40" rx="7" fill="#8c5b3c" transform="rotate(-14 141 126)" />
      {/* túnica */}
      <path d="M72 122h56l14 58H58z" fill={color} />
      <path d="M70 122h60l6 22-12-6-12 8-12-8-12 8-12-8-12 6z" fill="#fff" opacity=".28" />
      <rect x="62" y="150" width="76" height="7" rx="3" fill="#f2c041" />
      {/* cabeza */}
      <circle cx="100" cy="92" r="42" fill="#8c5b3c" />
      <ellipse cx="57" cy="94" rx="7" ry="11" fill="#7d5034" />
      <ellipse cx="143" cy="94" rx="7" ry="11" fill="#7d5034" />
      <g filter="url(#glow)">
        <circle cx="84" cy="94" r="12" fill="url(#eye)" />
        <circle cx="116" cy="94" r="12" fill="url(#eye)" />
      </g>
      <path d="M90 114q10 7 20 0" stroke="#5a3722" strokeWidth="3" fill="none" strokeLinecap="round" />
      {hat === 0 && (
        <g>
          <path d="M100 6 30 66q70 18 140 0z" fill="#c9944a" />
          <path d="M100 6 30 66q70 18 140 0z" fill="none" stroke="#9c6f33" strokeWidth="3" />
          <path d="M100 6 76 70M100 6l24 64M100 6v68" stroke="#9c6f33" strokeWidth="2" opacity=".6" />
        </g>
      )}
      {hat === 1 && (
        <g>
          {[-48, -32, -16, 0, 16, 32, 48].map((a, i) => (
            <rect key={a} x="93" y="2" width="14" height="52" rx="7" fill={i % 2 ? '#f2d24b' : color} transform={`rotate(${a} 100 66)`} />
          ))}
          <rect x="60" y="52" width="80" height="12" rx="6" fill="#f2c041" />
        </g>
      )}
      {hat >= 2 && <path d="M58 86q-2-40 42-40t42 40q-18-22-42-22T58 86z" fill="#1f1714" />}
      {hat === 2 && (
        <g transform="translate(134 56)">
          {[0, 72, 144, 216, 288].map((a) => (
            <ellipse key={a} cx="0" cy="-9" rx="6" ry="9" fill="#fff4ea" transform={`rotate(${a})`} />
          ))}
          <circle r="5" fill="#f2c041" />
        </g>
      )}
    </svg>
  );
}
