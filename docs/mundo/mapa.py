#!/usr/bin/env python3
"""Mapa conceptual del Mayab: docs/img/mapa-mayab.svg.

Coloca las ocho localidades según sus coordenadas reales (las de docs/mundo/FUENTES_YUCATAN.md,
sin cotejar todavía contra el Marco Geoestadístico de INEGI) y une las que tienen carretera
directa según las mismas fuentes. Es un esquema: conserva la posición relativa y el orden de los
caminos, no las distancias del juego. La costa sólo se sugiere con dos trazos.

    python3 docs/mundo/mapa.py
"""
from pathlib import Path

# nombre, latitud, longitud, sobrenombre en el juego, papel
LUGARES = [
    ("Mérida", 20.968, -89.622, "la Ciudad Blanca", "lugar social"),
    ("Progreso", 21.283, -89.664, "el muelle en la bruma", "puerto"),
    ("Motul", 21.095, -89.283, "campos de agave", "región abierta"),
    ("Izamal", 20.931, -89.018, "la ciudad dorada", "lugar social"),
    ("Valladolid", 20.689, -88.202, "la ciudad del cenote", "misiones de agua"),
    ("Tizimín", 21.138, -88.150, "los llanos y la feria", "eventos"),
    ("Tekax", 20.202, -89.288, "las lomas y sus cuevas", "exploración"),
    ("Celestún", 20.859, -90.400, "el manglar rosa", "región tranquila"),
]
# tramos con carretera según las fuentes: (de, a, km aproximados)
CAMINOS = [
    ("Mérida", "Progreso", "36 km"), ("Mérida", "Motul", "44 km"), ("Mérida", "Izamal", "70 km"),
    ("Mérida", "Tekax", "120 km"), ("Mérida", "Celestún", "89 km"), ("Motul", "Tizimín", "123 km"),
    ("Izamal", "Valladolid", "113 km"), ("Valladolid", "Tizimín", "50 km"), ("Motul", "Izamal", ""),
]
W, H, M = 1100, 700, 110
lats = [p[1] for p in LUGARES]
lons = [p[2] for p in LUGARES]
# un grado de longitud mide a esta latitud 0.934 de uno de latitud: se respeta la proporción
kx = 0.934
span_x = (max(lons) - min(lons)) * kx
span_y = max(lats) - min(lats)
scale = min((W - 2 * M) / span_x, (H - 2 * M) / span_y)
ox = (W - span_x * scale) / 2
oy = (H - span_y * scale) / 2 + 26


def xy(lat, lon):
    return ox + (lon - min(lons)) * kx * scale, oy + (max(lats) - lat) * scale


pos = {n: xy(lat, lon) for n, lat, lon, _, _ in LUGARES}
out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" font-family="system-ui, sans-serif">',
       f'<rect width="{W}" height="{H}" fill="#0f1f1b"/>',
       '<text x="24" y="38" fill="#ffd23f" font-size="24" font-weight="700">El Mayab de los aluxes · mapa conceptual</text>',
       '<text x="24" y="60" fill="#9ff0dc" font-size="13">Posición relativa real de ocho localidades de Yucatán y sus caminos. Esquema, no cartografía.</text>']
# costa sugerida: norte (golfo) y oeste
px, py = pos["Progreso"]
cx, cy = pos["Celestún"]
tx, ty = pos["Tizimín"]
out.append(f'<path d="M {cx - 26:.0f} {cy + 70:.0f} Q {cx - 34:.0f} {cy - 40:.0f} {cx + 60:.0f} {py + 34:.0f} T {px:.0f} {py - 22:.0f} T {tx + 70:.0f} {py - 46:.0f}" '
           'fill="none" stroke="#19b4d6" stroke-width="3" stroke-dasharray="2 9" stroke-linecap="round" opacity="0.75"/>')
out.append(f'<text x="{px + 300:.0f}" y="{py - 52:.0f}" fill="#19b4d6" font-size="13" opacity="0.85">Golfo de México</text>')
for a, b, km in CAMINOS:
    (x1, y1), (x2, y2) = pos[a], pos[b]
    out.append(f'<line x1="{x1:.0f}" y1="{y1:.0f}" x2="{x2:.0f}" y2="{y2:.0f}" stroke="#c9b78a" stroke-width="2.5" opacity="0.55"/>')
    if km:
        out.append(f'<text x="{(x1 + x2) / 2 + 8:.0f}" y="{(y1 + y2) / 2 + 16:.0f}" fill="#c9b78a" font-size="11" opacity="0.9">{km}</text>')
for name, lat, lon, alias, role in LUGARES:
    x, y = pos[name]
    main = name == "Mérida"
    out.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{13 if main else 9}" fill="{"#ffd23f" if main else "#2ec4a6"}" stroke="#0b1512" stroke-width="3"/>')
    left = name in ("Tizimín", "Valladolid", "Mérida")
    anchor = 'end' if left else 'start'
    dx = -16 if left else 16
    up = -16 if main else 0   # la etiqueta de Mérida, por encima de sus caminos
    out.append(f'<text x="{x + dx:.0f}" y="{y - 4 + up:.0f}" fill="#fff8ea" font-size="17" font-weight="700" text-anchor="{anchor}">{name}</text>')
    out.append(f'<text x="{x + dx:.0f}" y="{y + 13 + up:.0f}" fill="#9ff0dc" font-size="12" text-anchor="{anchor}">{alias} · {role}</text>')
out.append(f'<text x="24" y="{H - 20}" fill="#d8cfe0" font-size="11" opacity="0.8">Coordenadas y distancias: docs/mundo/FUENTES_YUCATAN.md (pendientes de cotejar con INEGI). '
           'Los sobrenombres son del juego, no topónimos.</text>')
out.append('</svg>')
dest = Path(__file__).resolve().parents[1] / "img" / "mapa-mayab.svg"
dest.write_text("\n".join(out), encoding="utf-8")
print("escrito", dest)
