"""Genera art/propuestas/nojoch/nojoch.glb — Nojoch Tuunich, el Guardián Dormido.

Uso (desde la raíz del repo):
    .tools/blender-venv/bin/python art/blender/build_nojoch.py

PROPUESTA de modelo del primer jefe (diseño en docs/BOSS.md); todavía no se integra en
el juego. Coloso de bloques de caliza tallada, encajados y con las juntas a la vista:
torso ancho, brazos largos y gruesos, manos enormes de tres dedos y pulgar, piernas
cortas y una cabeza ancha, sin cuello, con un tocado escalonado como la crestería de
un templo. Mide 5 m de pie y 3.4 m sentado.

A diferencia de los demás personajes (tubos suaves), aquí casi todo son bloques de
caras planas: cada cara lleva sus propios vértices, así las aristas quedan vivas y la
oclusión horneada oscurece las juntas. Cada bloque va pegado a un solo hueso (no hay
piel que se doble); las articulaciones son tambores de piedra.

Materiales:
  «Body»      caliza, musgo y raíces: blanco, todo el color va en los vértices.
  «Eye»       ojos hundidos, de jade emisivo.
  «Glyph1»…«Glyph4»  los cuatro glifos del pecho, de izquierda a derecha de quien lo
              mira. Se exportan apagados (jade sin emisión) para encenderlos uno a uno.
  «Heart»     corazón de cristal de la espalda, emisivo.
  «Silence»   vetas magenta de corrupción (brazos, pecho, espalda y cabeza), emisivas;
              se apagan cuando el guardián recuerda.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import alux_common as kc  # noqa: E402  (importa bpy antes que mathutils)
from mathutils import Matrix, Vector  # noqa: E402
from alux_common import C, WHITE, Loft, MeshBuilder, Rig, both, bump, mixc, mulc, ngon, pose_keys  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(os.environ.get("KAMEO_OUT_DIR") or os.path.join(REPO, "art", "propuestas", "nojoch"), "nojoch.glb")

sin, cos, pi, rad = math.sin, math.cos, math.pi, math.radians

# ───────────────────────────────── Paleta ─────────────────────────────────
# Caliza del santuario (game/scripts/client/world_builder.gd: LIME #dbcca8, LIME_DARK
# #a19680, LIME_WARM #e6c794, MOSS #5c8c45, JADE #2ef2b8, MAGENTA #fa3399), llevada a un
# gris cálido algo más apagado para que el coloso no se confunda con los muros y para que
# las caras al sol no se quemen del todo con la luz del juego.
HEX = {
    "Caliza": "#c4b89e",          # gris cálido: tono medio de los bloques
    "CalizaGris": "#aba089",      # bloques más grises
    "CalizaCrema": "#d9ccab",     # bloques más claros (≈ LIME)
    "CalizaOscura": "#928873",    # bloques en sombra (≈ LIME_DARK)
    "CalizaCalida": "#d8c193",    # placas talladas: pectoral, ajorcas, banda (≈ LIME_WARM)
    "Junta": "#584f45",           # fondo de cuencas, boca y juntas
    "Rotura": "#efe6cc",          # caliza recién partida en los desportillados
    "Verdin": "#7d8a63",          # pátina verdosa cerca del suelo
    "Musgo": "#5c8c45",           # = MOSS del santuario
    "MusgoOscuro": "#3c6a32",
    "MusgoClaro": "#8fb155",
    "Raiz": "#6e5338",
    "RaizOscura": "#47341f",
    "Jade": "#2ec4a6",            # glifos y corazón (color del jugador por omisión)
    "JadeLuz": "#59ffe0",         # emisión de los ojos (la de los ojos del alux)
    "JadeVivo": "#3fe8c4",        # emisión del corazón y de los glifos encendidos
    "Silencio": "#fa3399",        # = MAGENTA del santuario
    "SilencioApagado": "#4d423b",  # las vetas cuando recuerda: cicatrices en la piedra
}
EMISION = {"Eye": 1.2, "Heart": 1.0, "Silence": 1.8, "Glyph": 0.0}       # tal como se exporta
EMISION_RECUERDA = {"Eye": 1.6, "Heart": 2.4, "Silence": 0.0, "Glyph": 1.8}   # «el guardián recuerda»


def make_materials():
    m = kc.make_material
    mats = {
        "Body": m("Body", "#ffffff", 0.92),
        "Eye": m("Eye", HEX["Jade"], 0.3, emission=EMISION["Eye"], emission_color=HEX["JadeLuz"]),
        "Heart": m("Heart", HEX["Jade"], 0.15, emission=EMISION["Heart"], emission_color=HEX["JadeVivo"]),
        "Silence": m("Silence", HEX["Silencio"], 0.4, emission=EMISION["Silence"]),
    }
    for i in range(1, 5):
        mats["Glyph%d" % i] = m("Glyph%d" % i, HEX["Jade"], 0.3)
    return mats


def _pal(mat, **cols):
    return {k: (mat, C(v) if isinstance(v, str) else v) for k, v in cols.items()}


PAL = {
    **_pal("Body", Stone=HEX["Caliza"], Deep=HEX["Junta"], Moss=HEX["Musgo"], Root=HEX["Raiz"]),
    **_pal("Eye", Eye=WHITE),
    **_pal("Heart", Heart=WHITE),
    **_pal("Silence", Silence=WHITE),
    **{"Glyph%d" % i: ("Glyph%d" % i, WHITE) for i in range(1, 5)},
}
S_MID, S_GREY, S_CREAM, S_DARK, S_WARM = (C(HEX[k]) for k in ("Caliza", "CalizaGris", "CalizaCrema", "CalizaOscura",
                                                              "CalizaCalida"))
DEEP, CHIP, GRIME = C(HEX["Junta"]), C(HEX["Rotura"]), C(HEX["Verdin"])
MOSS, MOSS_D, MOSS_L = C(HEX["Musgo"]), C(HEX["MusgoOscuro"]), C(HEX["MusgoClaro"])
ROOT, ROOT_D = C(HEX["Raiz"]), C(HEX["RaizOscura"])


def smooth(x, a, b):
    x = min(1.0, max(0.0, (x - a) / (b - a)))
    return x * x * (3 - 2 * x)


# ───────────────────────────────── Medidas ─────────────────────────────────
# Mira a -Y; su izquierda es +X; pies en z = 0. De pie mide 5.00 m.
HIP = Vector((0.52, 0.0, 1.40))
KNEE = Vector((0.52, -0.02, 0.82))
ANKLE = Vector((0.52, 0.05, 0.33))
TOE = Vector((0.52, -0.72, 0.0))             # apoyo de la punta del pie (para la cinemática inversa)
SPINE_Z, CHEST_Z = 1.93, 2.38                # cinturón | abdomen | pecho
SHOULDER = Vector((1.50, 0.0, 3.10))
AX = 1.64                                    # eje del brazo colgando
ELBOW = Vector((AX, 0.0, 2.14))
WRIST = Vector((AX, 0.0, 1.20))
KNUCKLE = Vector((AX, 0.0, 0.73))
MIDFINGER = Vector((AX, 0.0, 0.48))
PALM_Z, FINGER_Z, TIP_Z = (0.74, 1.14), (0.49, 0.72), (0.24, 0.47)
HZ = 3.30                                    # base de la cabeza (mentón); la cabeza y su crestería miden 1.70 m
HEAD_PIVOT = Vector((0.0, 0.12, 3.34))
HEART_C = Vector((0.0, 0.82, 3.54))          # centro del cristal, en lo alto de la espalda
GLYPH_Z, GLYPH_DX, GLYPH_S = 2.91, 0.48, 0.19   # fila de glifos: altura, separación y media anchura


def mx(v, s):
    return Vector((v[0] * s, v[1], v[2]))


def make_bones():
    b = [
        ("Root", (0, 0, 0), (0, 0, 0.5), None),
        ("Hips", (0, 0, HIP.z), (0, 0, SPINE_Z), "Root"),
        ("Spine", (0, 0, SPINE_Z), (0, 0, CHEST_Z), "Hips"),
        ("Chest", (0, 0, CHEST_Z), (0, 0, 3.25), "Spine"),
        ("Head", HEAD_PIVOT, HEAD_PIVOT + Vector((0, 0, 0.8)), "Chest"),
        ("Jaw", (0, -0.06, HZ + 0.245), (0, -0.60, HZ + 0.18), "Head"),
        ("Lids", (0, -0.50, HZ + 0.62), (0, -0.62, HZ + 0.62), "Head"),
        # no se llama «Heart» para no chocar con nombres del juego; sirve para el latido
        ("HeartBone", (0, 0.66, HEART_C.z), (0, 1.0, HEART_C.z), "Chest"),
    ]
    for s, sfx in ((1, "_L"), (-1, "_R")):
        b += [
            ("UpperArm" + sfx, mx(SHOULDER, s), mx(ELBOW, s), "Chest"),
            ("Forearm" + sfx, mx(ELBOW, s), mx(WRIST, s), "UpperArm" + sfx),
            ("Hand" + sfx, mx(WRIST, s), mx(KNUCKLE, s), "Forearm" + sfx),
            ("Fingers" + sfx, mx(KNUCKLE, s), mx(MIDFINGER, s), "Hand" + sfx),
            ("FingerTips" + sfx, mx(MIDFINGER, s), mx((AX, 0, TIP_Z[0]), s), "Fingers" + sfx),
            ("Thumb" + sfx, mx((AX, -0.40, 1.04), s), mx((AX, -0.62, 0.80), s), "Hand" + sfx),
            ("Thigh" + sfx, mx(HIP, s), mx(KNEE, s), "Hips"),
            ("Shin" + sfx, mx(KNEE, s), mx(ANKLE, s), "Thigh" + sfx),
            ("Foot" + sfx, mx(ANKLE, s), mx((0.52, -0.45, 0.06), s), "Shin" + sfx),
        ]
    return b


RIG = Rig(make_bones())


# ───────────────────────────── Piezas de cantería ─────────────────────────────

def _newell(pts):
    n = Vector((0.0, 0.0, 0.0))
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        n += Vector(((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)))
    return n


def add_face(mb, pts, key, w, cols=None, inside=None, out=None, occ=True):
    """Cara plana con vértices propios (arista viva), orientada hacia fuera: lejos del
    punto `inside` o según la dirección `out`."""
    pts = [Vector(p) for p in pts]
    ref = (sum(pts, Vector()) / len(pts) - Vector(inside)) if inside is not None else Vector(out)
    if _newell(pts).dot(ref) < 0.0:
        pts.reverse()
        cols = cols[::-1] if cols else None
    mb.face([mb.vert(p, w) for p in pts], key, cols, occ)


class Blk:
    """Sillar: caja con conicidad (`taper`: escala de la cara de arriba), inclinación
    (`lean`: desplazamiento de la cara de arriba) y giro opcional alrededor de `pivot`.
    Coordenadas locales en [-1, 1]³."""

    def __init__(self, lo, hi, taper=(1.0, 1.0), lean=(0.0, 0.0), rot=None, pivot=None):
        lo, hi = Vector(lo), Vector(hi)
        self.c, self.h = (lo + hi) * 0.5, (hi - lo) * 0.5
        self.taper, self.lean, self.rot = taper, lean, rot
        self.pivot = Vector(pivot) if pivot is not None else self.c

    def P(self, l):
        f = 0.5 * (l[2] + 1.0)
        p = self.c + Vector((l[0] * self.h.x * (1.0 + (self.taper[0] - 1.0) * f) + self.lean[0] * f,
                             l[1] * self.h.y * (1.0 + (self.taper[1] - 1.0) * f) + self.lean[1] * f,
                             l[2] * self.h.z))
        if self.rot is not None:
            p = self.pivot + self.rot @ (p - self.pivot)
        return p

    def at(self, face, u, v, off=0.0):
        """Punto (y normal) sobre la cara «x+», «x-», «y+», «y-», «z+» o «z-»; u, v en
        [-1, 1] sobre los otros dos ejes, en orden (x, y, z)."""
        ax = "xyz".index(face[0])
        sg = 1.0 if face[1] == "+" else -1.0
        a, b = ((1, 2), (0, 2), (0, 1))[ax]

        def pt(uu, vv):
            l = [0.0, 0.0, 0.0]
            l[ax], l[a], l[b] = sg, uu, vv
            return self.P(l)

        p, e = pt(u, v), 1e-3
        n = (pt(u + e, v) - pt(u - e, v)).cross(pt(u, v + e) - pt(u, v - e)).normalized()
        if n.dot(p - self.P((0.0, 0.0, 0.0))) < 0.0:
            n = -n
        return p + n * off, n


def stone_tone(rng):
    base = mixc(S_MID, S_GREY, rng.random())
    r = rng.random()
    if r < 0.26:
        base = mixc(base, S_CREAM, 0.8)
    elif r < 0.50:
        base = mixc(base, S_DARK, 0.75)
    elif r < 0.62:
        base = mixc(base, S_WARM, 0.5)
    return base


def add_block(mb, lo, hi, w, rng, tone=None, bevel=0.035, taper=(1.0, 1.0), lean=(0.0, 0.0), rot=None,
              pivot=None, chips=None, skip="", moss=0.0, key="Stone", flat=False):
    """Sillar achaflanado de caras planas (44 triángulos; 12 si bevel = 0).
    `chips`: esquinas desportilladas (índices 0–7: bit 0 = +x, bit 1 = +y, bit 2 = +z);
    None = al azar, () = ninguna. `moss`: musgo en la cara de arriba y lo alto de los
    costados. `skip`: caras principales que no se generan (p. ej. "z-y+")."""
    blk = Blk(lo, hi, taper, lean, rot, pivot)
    base = tone if tone is not None else stone_tone(rng)
    if chips is None:
        chips = (4 + rng.randrange(4),) if (bevel > 0.0 and rng.random() < 0.3) else ()
    centre = blk.P((0.0, 0.0, 0.0))
    mvar = mixc(MOSS, MOSS_D if rng.random() < 0.5 else MOSS_L, rng.random() * 0.6)

    def shade(l, kind):
        p = blk.P(l)
        f = 0.5 * (l[2] + 1.0)
        if flat:
            return p, base
        c = mulc(base, 0.86 + 0.16 * f)
        if kind == "top":
            c = mulc(base, 1.06)
        elif kind == "bot":
            c = mulc(base, 0.72)
        elif kind == "bevel":
            c = mulc(c, 1.07)
        elif kind == "chip":
            c = mixc(c, CHIP, 0.8)
        if moss > 0.0 and kind != "bot":
            c = mixc(c, mvar, moss * (1.0 if kind == "top" else 0.8 * f * f))
        c = mixc(c, GRIME, 0.30 * (1.0 - smooth(p.z, 0.05, 1.5)))
        return p, c

    def emit(ls, kind):
        pc = [shade(l, kind) for l in ls]
        add_face(mb, [p for p, _c in pc], key, w, [c for _p, c in pc], inside=centre)

    if bevel <= 0.0:
        for ax in range(3):
            a, b = ((1, 2), (0, 2), (0, 1))[ax]
            for sg in (-1.0, 1.0):
                if "xyz"[ax] + ("+" if sg > 0 else "-") in skip:
                    continue
                ls = []
                for ua, ub in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                    l = [0.0, 0.0, 0.0]
                    l[ax], l[a], l[b] = sg, ua, ub
                    ls.append(l)
                emit(ls, "top" if (ax == 2 and sg > 0) else ("bot" if ax == 2 else "side"))
        return blk
    bl = [min(0.42, bevel / max(blk.h[k], 1e-6)) for k in range(3)]
    corner = []                 # por esquina: sus tres vértices (uno por cara) en coordenadas locales
    chipped = set(chips)
    for i in range(8):
        sg = [1.0 if i & (1 << k) else -1.0 for k in range(3)]
        b = list(bl)
        if i in chipped:
            b = [min(0.6, max(bl[k], rng.uniform(0.10, 0.23) / max(blk.h[k], 1e-6))) for k in range(3)]
        tri = []
        for k in range(3):
            l = list(sg)
            for j in range(3):
                if j != k:
                    l[j] -= sg[j] * b[j]
            tri.append(l)
        corner.append(tri)
    for ax in range(3):
        a, b = ((1, 2), (0, 2), (0, 1))[ax]
        for sg in (0, 1):
            if "xyz"[ax] + ("+" if sg else "-") in skip:
                continue
            ids = [i for i in range(8) if ((i >> ax) & 1) == sg]
            ids.sort(key=lambda i: math.atan2(((i >> b) & 1) - 0.5, ((i >> a) & 1) - 0.5))
            emit([corner[i][ax] for i in ids], "top" if (ax == 2 and sg) else ("bot" if ax == 2 else "side"))
    for ax in range(3):             # aristas paralelas al eje `ax`
        a, b = ((1, 2), (0, 2), (0, 1))[ax]
        for sa in (0, 1):
            for sb in (0, 1):
                i0 = (sa << a) | (sb << b)
                i1 = i0 | (1 << ax)
                emit([corner[i0][a], corner[i0][b], corner[i1][b], corner[i1][a]], "bevel")
    for i in range(8):
        emit(corner[i], "chip" if i in chipped else "bevel")
    return blk


def add_prism(mb, o, ex, ey, n, poly, depth, key, w, col=None, occ=True, side_k=0.82, back=False):
    """Relieve: polígono convexo `poly` (metros, en el plano de origen `o` y ejes ex, ey)
    que sobresale `depth` según la normal `n`. Tapa y costados; el fondo, solo con `back`
    (cuando la pieza se puede ver por detrás)."""
    o, ex, ey, n = Vector(o), Vector(ex), Vector(ey), Vector(n)
    base = [o + ex * x + ey * y for x, y in poly]
    top = [p + n * depth for p in base]
    add_face(mb, top, key, w, [col] * len(top) if col else None, out=n, occ=occ)
    cs = mulc(col, side_k) if col else None
    cen = sum(base, Vector()) / len(base)
    for i in range(len(poly)):
        j = (i + 1) % len(poly)
        add_face(mb, [base[i], base[j], top[j], top[i]], key, w, [cs] * 4 if col else None, inside=cen, occ=occ)
    if back:
        add_face(mb, base, key, w, [cs] * len(base) if col else None, out=-n, occ=occ)


def add_drum(mb, c, r, hl, w, rng, axis=0, n=10, tone=None, bevel=0.035):
    """Tambor de piedra (articulación): cilindro sobre el eje `axis`, costado suave."""
    c = Vector(c)
    base = tone if tone is not None else stone_tone(rng)
    a, b = ((1, 2), (0, 2), (0, 1))[axis]

    def P(t, rr, ang):
        v = Vector((0.0, 0.0, 0.0))
        v[axis], v[a], v[b] = t, rr * cos(ang), rr * sin(ang)
        return c + v

    def col(p, k=1.0):
        return mixc(mulc(base, k), GRIME, 0.30 * (1.0 - smooth(p.z, 0.05, 1.5)))

    angs = [2.0 * pi * (k + 0.5) / n for k in range(n)]
    rings = [[mb.vert(P(t, r, ang), w) for ang in angs] for t in (-hl + bevel, hl - bevel)]
    for k in range(n):
        k2 = (k + 1) % n
        q = [rings[0][k], rings[0][k2], rings[1][k2], rings[1][k]]
        pts = [mb.verts[i] for i in q]
        cc = [col(p, 0.93) for p in pts]
        if _newell(pts).dot(sum(pts, Vector()) / 4.0 - c) < 0.0:
            q.reverse()
            cc.reverse()
        mb.face(q, "Stone", cc)
    for sg in (-1.0, 1.0):
        cap = [P(sg * hl, r - bevel, ang) for ang in angs]
        edge = [P(sg * (hl - bevel), r, ang) for ang in angs]
        add_face(mb, cap, "Stone", w, [col(p, 1.03) for p in cap], inside=c)
        for k in range(n):
            k2 = (k + 1) % n
            q = [edge[k], edge[k2], cap[k2], cap[k]]
            add_face(mb, q, "Stone", w, [col(p, 1.08) for p in q], inside=c)


def add_crystal(mb, c, axis, length, r, w, rng, n=6, key="Heart"):
    """Cristal: prisma hexagonal con dos puntas, de facetas planas."""
    c, axis = Vector(c), Vector(axis).normalized()
    ref = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0))
    e1 = axis.cross(ref).normalized()
    e2 = axis.cross(e1)
    ph = rng.random()
    ring = lambda t, rr: [c + axis * t + (e1 * cos(2 * pi * (k + ph) / n) + e2 * sin(2 * pi * (k + ph) / n)) * rr
                          for k in range(n)]
    lo, hi = ring(-0.24 * length, r * 0.86), ring(0.20 * length, r)
    tip0, tip1 = c - axis * 0.5 * length, c + axis * 0.5 * length
    for k in range(n):
        k2 = (k + 1) % n
        for pts in ([lo[k], lo[k2], hi[k2], hi[k]], [hi[k], hi[k2], tip1], [lo[k2], lo[k], tip0]):
            g = rng.uniform(0.62, 1.0)
            add_face(mb, pts, key, w, [(g, g, g)] * len(pts), inside=c, occ=False)


def add_moss(mb, c, r, w, rng, flat=0.5):
    """Mata de musgo: media esfera chata y abollada."""
    ph = [rng.uniform(0, 6.28) for _ in range(3)]
    tone = mixc(MOSS, MOSS_D if rng.random() < 0.5 else MOSS_L, rng.uniform(0.2, 0.7))
    mb.add_sphere(c, (r, r * rng.uniform(0.8, 1.15), r * flat), "Moss", w, segs=7, rings=4,
                  deform=lambda d: 1.0 + 0.16 * sin(5.0 * d.x + ph[0]) * sin(4.0 * d.y + ph[1]) + 0.10 * sin(7.0 * d.z + ph[2]),
                  keep=lambda d: d.z > -0.3,
                  col=lambda p, d: mixc(mulc(tone, 0.72), mulc(tone, 1.15), smooth(d.z, -0.2, 0.9)))


def add_tuft(mb, p, length, w, rng, out=(0.0, -1.0, 0.0)):
    """Barba de musgo que cuelga de un borde: una púa de tres caras."""
    p, out = Vector(p), Vector(out).normalized()
    sd = out.cross(Vector((0, 0, 1))).normalized()
    r = 0.028 + 0.016 * rng.random()
    top = [p + sd * r, p - sd * r, p + out * r * 1.2]
    tip = p + out * 0.03 - Vector((0, 0, length)) + sd * rng.uniform(-0.03, 0.03)
    cen = (sum(top, Vector()) + tip) / 4.0
    c0, c1 = mixc(MOSS, MOSS_L, rng.random() * 0.5), mulc(MOSS_D, 0.9)
    for k in range(3):
        add_face(mb, [top[k], top[(k + 1) % 3], tip], "Moss", w, [c0, c0, c1], inside=cen)
    add_face(mb, top, "Moss", w, [c0] * 3, inside=cen)


def add_root(mb, pts, r0, r1, w, segs=5):
    """Raíz: tubo fino que serpentea sobre la piedra."""
    pts = [Vector(p) for p in pts]
    ext = [max(abs((b - a)[k]) for a, b in zip(pts, pts[1:])) for k in range(3)]
    side = [(1, 0, 0), (0, 1, 0), (0, 0, 1)][ext.index(min(ext))]
    n = len(pts)
    rings = [dict(c=p, rx=r0 + (r1 - r0) * i / (n - 1), ry=r0 + (r1 - r0) * i / (n - 1), w=w) for i, p in enumerate(pts)]
    loft = Loft(rings, side=side)
    mb.add_loft(loft, "Root", segs=segs, sub=2, cap0=True, cap1=True, w=w,
                col=lambda p, u, th: mixc(ROOT_D, ROOT, 0.5 + 0.5 * sin(th + 2.0 * u)))


def add_vein(mb, pn, width, w, lift=0.035):
    """Veta del Silencio: cresta fina de dos aguas que sigue la superficie.
    pn = [(punto, normal), ...]; se afila hacia el final."""
    k = len(pn)
    rows = []
    for i, (p, n) in enumerate(pn):
        t = (pn[min(i + 1, k - 1)][0] - pn[max(i - 1, 0)][0]).normalized()
        sd = t.cross(n).normalized()
        wd = 0.5 * width * (1.0 - 0.72 * i / (k - 1)) * (0.45 if i == 0 else 1.0)
        rows.append((mb.vert(p + n * 0.004 + sd * wd, w), mb.vert(p + n * lift, w), mb.vert(p + n * 0.004 - sd * wd, w)))
    for i in range(k - 1):
        for a, b in ((0, 1), (1, 2)):
            q = [rows[i][a], rows[i][b], rows[i + 1][b], rows[i + 1][a]]
            pts = [mb.verts[j] for j in q]
            if _newell(pts).dot(pn[i][1]) < 0.0:
                q.reverse()
            mb.face(q, "Silence", None, False)


def vein_path(B, spec, rng, amp=0.05):
    """Recorrido en zigzag: spec = [(bloque, cara, u, v), ...] → [(punto, normal), ...]."""
    pts = []
    for i, (name, fc, u, v) in enumerate(spec):
        blk = B[name][0]
        if i > 0 and spec[i - 1][0] == name and spec[i - 1][1] == fc:
            u0, v0 = spec[i - 1][2], spec[i - 1][3]
            p1, p2 = blk.at(fc, u0, v0)[0], blk.at(fc, u, v)[0]
            for f, sg in ((0.33, 1.0), (0.66, -1.0)):
                p, n = blk.at(fc, u0 + (u - u0) * f, v0 + (v - v0) * f)
                sd = (p2 - p1).cross(n).normalized()
                pts.append((p + sd * amp * sg * rng.uniform(0.6, 1.3), n))
        pts.append(blk.at(fc, u, v))
    return pts


# ─────────────────────────────────── Glifos ───────────────────────────────────
# Cuatro signos abstractos, originales, de trazo geométrico (no son escritura maya):
# cada uno es una lista de polígonos convexos en una celda de [-1, 1] × [-1.3, 1.3].

def _r(u0, v0, u1, v1):
    return [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]


def _chevron(v):
    return [[(-1.0, v + 0.50), (-1.0, v + 0.18), (0.0, v - 0.32), (0.0, v + 0.0)],
            [(0.0, v + 0.0), (0.0, v - 0.32), (1.0, v + 0.18), (1.0, v + 0.50)]]


GLYPHS = [
    # 1 · «la vuelta»: una espiral cuadrada que se cierra hacia dentro (recordar)
    [_r(-1.0, 1.0, 1.0, 1.3), _r(0.7, -1.3, 1.0, 1.0), _r(-1.0, -1.3, 0.7, -1.0), _r(-1.0, -1.0, -0.7, 0.45),
     _r(-0.7, 0.15, 0.3, 0.45), _r(0.0, -0.55, 0.3, 0.15), _r(-0.42, -0.55, 0.0, -0.25)],
    # 2 · «la escalera»: tres peldaños que suben sobre una base, y una cuenta (el camino)
    [_r(-1.0, -1.3, 1.0, -1.02), _r(-1.0, -0.84, -0.4, -0.24), _r(-0.3, -0.14, 0.3, 0.46), _r(0.4, 0.56, 1.0, 1.16),
     [(-0.72, 0.62), (-0.44, 0.92), (-0.72, 1.22), (-1.0, 0.92)]],
    # 3 · «el patio»: un marco con un rombo en el centro (lo que se guarda)
    [_r(-1.0, 1.02, 1.0, 1.3), _r(-1.0, -1.3, 1.0, -1.02), _r(-1.0, -0.84, -0.72, 0.84), _r(0.72, -0.84, 1.0, 0.84),
     [(0.0, -0.62), (0.46, 0.0), (0.0, 0.62), (-0.46, 0.0)]],
    # 4 · «la lluvia»: dos cabrios que bajan sobre tres cuentas (lo que vuelve)
    _chevron(0.80) + _chevron(0.05) + [_r(-0.92, -1.3, -0.52, -0.9), _r(-0.2, -1.3, 0.2, -0.9), _r(0.52, -1.3, 0.92, -0.9)],
]


# ─────────────────────────────────── Malla ───────────────────────────────────

def build_body():
    mb = MeshBuilder(PAL)
    rng = random.Random(1217)
    B = {}

    def blk(name, lo, hi, w, s=1, **kw):
        """Sillar con nombre (para apoyar luego vetas, musgo y raíces); s = -1 lo refleja."""
        lo, hi = Vector(lo), Vector(hi)
        if s < 0:
            lo.x, hi.x = -hi.x, -lo.x
            if "lean" in kw:
                kw["lean"] = (-kw["lean"][0], kw["lean"][1])
            if "pivot" in kw:
                kw["pivot"] = mx(kw["pivot"], -1)
            if kw.get("rot") is not None:
                m = Matrix.Diagonal((-1.0, 1.0, 1.0))
                kw["rot"] = m @ kw["rot"] @ m
            if kw.get("chips"):
                kw["chips"] = tuple(i ^ 1 for i in kw["chips"])
            if kw.get("skip"):
                kw["skip"] = kw["skip"].replace("x+", "x?").replace("x-", "x+").replace("x?", "x-")
        b = add_block(mb, lo, hi, w, rng, **kw)
        B[name] = (b, w)
        return b

    def boss(c, axis, r, depth, w, tone, n=8, inner=0.55):
        """Disco tallado de dos escalones sobre una cara (normal = ±eje `axis`)."""
        nrm = Vector((0, 0, 0))
        nrm[abs(axis) - 1] = 1.0 if axis > 0 else -1.0
        ex = Vector((0, 0, 1)).cross(nrm).normalized() if abs(axis) != 3 else Vector((1, 0, 0))
        ey = nrm.cross(ex)
        add_prism(mb, c, ex, ey, nrm, ngon(n, r, phase=pi / n), depth, "Stone", w, col=tone)
        add_prism(mb, Vector(c) + nrm * depth, ex, ey, nrm, ngon(n, r * inner, phase=pi / n), depth * 0.6, "Stone", w,
                  col=mulc(tone, 1.08))

    # ── piernas ──
    for s, sfx in ((1, "_L"), (-1, "_R")):
        wt, wsh, wf = {"Thigh" + sfx: 1}, {"Shin" + sfx: 1}, {"Foot" + sfx: 1}
        add_drum(mb, mx(HIP, s), 0.32, 0.33, wt, rng, tone=S_DARK)
        boss(mx((0.85, 0.0, HIP.z), s), s, 0.22, 0.05, {"Hips": 1}, S_WARM)
        blk("thigh" + sfx, (0.22, -0.31, 1.02), (0.82, 0.31, 1.46), wt, s, taper=(1.06, 1.08), bevel=0.04)
        blk("thighpl" + sfx, (0.34, -0.36, 1.08), (0.70, -0.31, 1.38), wt, s, bevel=0.015, tone=S_WARM, chips=(), skip="y+")
        add_drum(mb, mx(KNEE, s), 0.25, 0.28, wt, rng, tone=S_DARK)
        blk("kneecap" + sfx, (0.28, -0.43, 0.66), (0.76, -0.22, 1.00), wt, s, taper=(0.8, 1.0), bevel=0.03)
        boss(mx((0.52, -0.43, 0.82), s), -2, 0.13, 0.035, wt, S_WARM)
        blk("shin" + sfx, (0.20, -0.32, 0.38), (0.84, 0.32, 0.66), wsh, s, taper=(0.86, 0.88), bevel=0.04)
        blk("anklet" + sfx, (0.16, -0.36, 0.28), (0.88, 0.37, 0.38), wf, s, bevel=0.025, tone=S_WARM, chips=())
        blk("foot" + sfx, (0.18, -0.50, 0.0), (0.86, 0.36, 0.29), wf, s, taper=(0.92, 0.86), lean=(0.0, 0.05),
            bevel=0.04, moss=0.25)
        for k, tx in enumerate((0.30, 0.52, 0.74)):
            blk("toe%d%s" % (k, sfx), (tx - 0.10, -0.72, 0.0), (tx + 0.10, -0.46, 0.19), wf, s, taper=(0.85, 0.9),
                bevel=0.03, chips=(4,) if (k == 2 and s > 0) else ())

    # ── pelvis y cinturón ──
    wh = {"Hips": 1}
    blk("pelvis", (-0.25, -0.36, 1.06), (0.25, 0.36, 1.73), wh, chips=())
    blk("apron", (-0.23, -0.52, 1.10), (0.23, -0.36, 1.73), wh, bevel=0.03, chips=(0,))
    blk("apronpl", (-0.14, -0.56, 1.22), (0.14, -0.52, 1.65), wh, bevel=0.015, tone=S_WARM, chips=(), skip="y+")
    blk("tail", (-0.23, 0.36, 1.16), (0.23, 0.50, 1.73), wh, bevel=0.03)
    blk("belt", (-0.90, -0.50, 1.71), (0.90, 0.50, SPINE_Z), wh, bevel=0.04, tone=mixc(S_WARM, S_MID, 0.4), chips=())
    for k in range(-3, 4):
        if k:
            x = k * 0.25
            add_prism(mb, (x, -0.50, 1.82), (1, 0, 0), (0, 0, 1), (0, -1, 0), _r(-0.07, -0.06, 0.07, 0.06), 0.035, "Stone",
                      wh, col=S_CREAM)
            add_prism(mb, (x, 0.50, 1.82), (-1, 0, 0), (0, 0, 1), (0, 1, 0), _r(-0.07, -0.06, 0.07, 0.06), 0.035, "Stone",
                      wh, col=S_CREAM)
    boss((0.0, -0.50, 1.82), -2, 0.17, 0.06, wh, S_CREAM)

    # ── abdomen (dos hiladas) ──
    wsp = {"Spine": 1}
    for i, (x0, x1) in enumerate(((-0.74, 0.0), (0.0, 0.74))):
        blk("abdA%d" % i, (x0, -0.45, SPINE_Z), (x1, 0.45, 2.15), wsp)
    for i, (x0, x1) in enumerate(((-0.86, -0.29), (-0.29, 0.29), (0.29, 0.86))):
        blk("abdB%d" % i, (x0, -0.50, 2.15), (x1, 0.50, CHEST_Z), wsp)

    # ── pecho (tres hiladas de sillares a matajunta) ──
    wc = {"Chest": 1}
    for i, (x0, x1) in enumerate(((-1.0, -0.34), (-0.34, 0.34), (0.34, 1.0))):
        blk("chA%d" % i, (x0, -0.56, CHEST_Z), (x1, 0.56, 2.68), wc, chips=())
    for i, (x0, x1) in enumerate(((-1.08, -0.54), (-0.54, 0.0), (0.0, 0.54), (0.54, 1.08))):
        blk("chB%d" % i, (x0, -0.60, 2.68), (x1, 0.60, 2.99), wc, chips=())
    for i, (x0, x1) in enumerate(((-1.12, -0.38), (-0.38, 0.38), (0.38, 1.12))):
        blk("chC%d" % i, (x0, -0.60, 2.99), (x1, 0.60, 3.29), wc, chips=(), moss=0.35 if i != 1 else 0.0)
    # pectoral: la placa que lleva los cuatro glifos, y su cornisa
    plate = blk("plate", (-1.0, -0.71, 2.61), (1.0, -0.59, 3.21), wc, tone=S_WARM, bevel=0.03, chips=(1,))
    blk("collar", (-0.80, -0.69, 3.21), (0.80, -0.52, 3.31), wc, bevel=0.025, tone=S_CREAM, chips=())
    for s, sfx in ((1, "_L"), (-1, "_R")):
        blk("pend" + sfx, (0.30, -0.69, 2.47), (0.52, -0.57, 2.61), wc, s, bevel=0.02, tone=S_WARM, chips=())
    blk("pendc", (-0.16, -0.70, 2.41), (0.16, -0.57, 2.61), wc, bevel=0.02, tone=S_WARM, chips=())
    # espaldar: el marco que sube por detrás de la cabeza y guarda el corazón
    for s, sfx in ((1, "_L"), (-1, "_R")):
        blk("rackpost" + sfx, (0.27, 0.62, 3.14), (0.43, 0.86, 3.92), wc, s, bevel=0.025, chips=())
        blk("rackwing" + sfx, (0.43, 0.62, 3.26), (0.82, 0.74, 3.72), wc, s, bevel=0.025, tone=S_WARM, taper=(0.7, 1.0),
            lean=(-0.05, 0.0))
    blk("racktop", (-0.50, 0.62, 3.92), (0.50, 0.90, 4.04), wc, bevel=0.03, moss=0.5, chips=(5,))
    blk("racksill", (-0.56, 0.58, 2.98), (0.56, 0.92, 3.14), wc, bevel=0.03, chips=())
    blk("rackback", (-0.27, 0.62, 3.14), (0.27, 0.66, 3.92), wc, bevel=0.0, tone=DEEP, flat=True)

    # ── glifos ──
    for i in range(4):
        gx = (i - 1.5) * GLYPH_DX
        o = Vector((gx, plate.c.y - plate.h.y, GLYPH_Z))
        add_prism(mb, o, (1, 0, 0), (0, 0, 1), (0, -1, 0), _r(-GLYPH_S * 1.18, -GLYPH_S * 1.48, GLYPH_S * 1.18, GLYPH_S * 1.48),
                  0.012, "Stone", wc, col=mulc(S_DARK, 0.62))
        for poly in GLYPHS[i]:
            add_prism(mb, o + Vector((0, -0.012, 0)), (1, 0, 0), (0, 0, 1), (0, -1, 0),
                      [(u * GLYPH_S, v * GLYPH_S) for u, v in poly], 0.03, "Glyph%d" % (i + 1), wc, occ=False)

    # ── corazón ──
    whb = {"HeartBone": 1}
    add_crystal(mb, HEART_C, (0, 0.10, 1), 0.74, 0.21, whb, rng)
    add_crystal(mb, HEART_C + Vector((-0.15, -0.02, -0.20)), (-0.55, 0.35, 0.7), 0.36, 0.10, whb, rng)
    add_crystal(mb, HEART_C + Vector((0.16, -0.02, -0.22)), (0.6, 0.4, 0.6), 0.32, 0.09, whb, rng)
    add_crystal(mb, HEART_C + Vector((0.03, 0.10, -0.26)), (0.1, 0.9, 0.3), 0.26, 0.08, whb, rng)

    # ── brazos ──
    for s, sfx in ((1, "_L"), (-1, "_R")):
        wu, wfa, wha = {"UpperArm" + sfx: 1}, {"Forearm" + sfx: 1}, {"Hand" + sfx: 1}
        wfi, wft, wth = {"Fingers" + sfx: 1}, {"FingerTips" + sfx: 1}, {"Thumb" + sfx: 1}
        blk("shoulder" + sfx, (1.15, -0.52, 2.78), (2.08, 0.52, 3.56), wu, s, taper=(0.94, 0.92), bevel=0.05, moss=0.6,
            chips=(5,) if s > 0 else (6,))
        blk("shtop" + sfx, (1.30, -0.36, 3.56), (1.92, 0.36, 3.76), wu, s, taper=(0.86, 0.86), bevel=0.04, moss=0.8)
        boss(mx((2.08 - 0.02, 0.0, 3.16), s), s, 0.26, 0.06, wu, S_WARM)
        blk("uarm" + sfx, (AX - 0.31, -0.32, 2.38), (AX + 0.31, 0.32, 2.78), wu, s, taper=(1.1, 1.08))
        add_drum(mb, mx(ELBOW, s), 0.27, 0.31, wu, rng, tone=S_DARK)
        blk("foreA" + sfx, (AX - 0.30, -0.31, 1.62), (AX + 0.30, 0.31, 1.90), wfa, s, taper=(0.9, 0.9))
        blk("foreB" + sfx, (AX - 0.37, -0.38, 1.32), (AX + 0.37, 0.38, 1.62), wfa, s, taper=(0.92, 0.92), bevel=0.04)
        blk("brace" + sfx, (AX - 0.42, -0.43, 1.20), (AX + 0.42, 0.43, 1.32), wfa, s, bevel=0.03, tone=S_WARM, chips=())
        blk("forepl" + sfx, (AX + 0.32, -0.22, 1.36), (AX + 0.40, 0.22, 1.58), wfa, s, bevel=0.015, tone=S_WARM, chips=(),
            skip="x-")
        boss(mx((AX + 0.40, 0.0, 1.47), s), s, 0.09, 0.03, wfa, S_CREAM, n=4)
        add_drum(mb, mx((AX, 0.0, 1.17), s), 0.20, 0.30, wfa, rng, axis=1, tone=S_DARK, n=8)
        blk("palm" + sfx, (AX - 0.17, -0.42, PALM_Z[0]), (AX + 0.17, 0.42, PALM_Z[1]), wha, s, bevel=0.04, chips=())
        for k, fy in enumerate((-0.285, 0.0, 0.285)):
            blk("fing%d%s" % (k, sfx), (AX - 0.14, fy - 0.125, FINGER_Z[0]), (AX + 0.14, fy + 0.125, FINGER_Z[1]), wfi, s,
                bevel=0.03, chips=())
            blk("ftip%d%s" % (k, sfx), (AX - 0.13, fy - 0.115, TIP_Z[0]), (AX + 0.13, fy + 0.115, TIP_Z[1]), wft, s,
                bevel=0.03, chips=(0,) if (k == 1 and s < 0) else ())
        tr = Matrix.Rotation(rad(-38), 3, "X")
        blk("thumbA" + sfx, (AX - 0.13, -0.53, 0.80), (AX + 0.13, -0.29, 1.08), wth, s, bevel=0.03, rot=tr,
            pivot=(AX, -0.40, 1.04), chips=())
        blk("thumbB" + sfx, (AX - 0.12, -0.52, 0.56), (AX + 0.12, -0.30, 0.79), wth, s, bevel=0.03, rot=tr,
            pivot=(AX, -0.40, 1.04), chips=())

    # ── cabeza ──
    wk, wj, wl = {"Head": 1}, {"Jaw": 1}, {"Lids": 1}
    blk("skullA", (-0.68, -0.46, HZ + 0.02), (0.68, 0.56, HZ + 0.42), wk, chips=())
    blk("skullB", (-0.68, -0.46, HZ + 0.42), (0.68, 0.56, HZ + 0.78), wk, chips=())
    blk("socket", (-0.66, -0.49, HZ + 0.445), (0.66, -0.45, HZ + 0.635), wk, bevel=0.0, tone=DEEP, flat=True, skip="y+")
    blk("mouth", (-0.50, -0.54, HZ + 0.205), (0.50, -0.45, HZ + 0.29), wk, bevel=0.0, tone=mulc(DEEP, 0.8), flat=True,
        skip="y+")
    blk("jaw", (-0.67, -0.67, HZ + 0.0), (0.67, -0.08, HZ + 0.225), wj, taper=(0.96, 0.98), bevel=0.045, chips=())
    blk("chin", (-0.24, -0.705, HZ + 0.03), (0.24, -0.67, HZ + 0.175), wj, bevel=0.015, tone=S_WARM, chips=(), skip="y+")
    for s, sfx in ((1, "_L"), (-1, "_R")):
        blk("cheek" + sfx, (0.185, -0.61, HZ + 0.27), (0.70, -0.08, HZ + 0.465), wk, s, bevel=0.035, chips=())
        blk("lid" + sfx, (0.16, -0.535, HZ + 0.62), (0.66, -0.50, HZ + 0.79), wl, s, bevel=0.0, tone=S_MID, skip="y+z+")
        blk("flare" + sfx, (0.68, -0.30, HZ + 0.18), (0.97, 0.25, HZ + 0.70), wk, s, bevel=0.04)
        boss(mx((0.97, -0.02, HZ + 0.44), s), s, 0.18, 0.06, wk, S_WARM)
        blk("drop" + sfx, (0.74, -0.16, HZ + 0.0), (0.93, 0.11, HZ + 0.18), wk, s, bevel=0.03, taper=(1.0, 1.25), chips=())
        # ojos: almendras de jade al fondo de la cuenca, con el rabillo algo caído (sereno)
        add_prism(mb, mx((0.42, -0.49, HZ + 0.54), s), (s, 0, 0), (0, 0, 1), (0, -1, 0),
                  [(-0.225, 0.008), (-0.13, 0.066), (0.10, 0.066), (0.225, -0.024), (0.12, -0.066), (-0.13, -0.062)],
                  0.02, "Eye", wk, occ=False)
    blk("lip", (-0.185, -0.64, HZ + 0.27), (0.185, -0.36, HZ + 0.365), wk, bevel=0.03, chips=())
    blk("nose", (-0.17, -0.81, HZ + 0.345), (0.17, -0.53, HZ + 0.71), wk, taper=(0.62, 0.5), lean=(0.0, 0.10),
        bevel=0.035, chips=())
    blk("brow", (-0.74, -0.685, HZ + 0.615), (0.74, -0.08, HZ + 0.77), wk, bevel=0.04, chips=())
    blk("band", (-0.78, -0.635, HZ + 0.77), (0.78, 0.61, HZ + 0.88), wk, bevel=0.03, tone=S_WARM, chips=())
    for k in range(-2, 3):
        add_prism(mb, (k * 0.29, -0.635, HZ + 0.825), (1, 0, 0), (0, 0, 1), (0, -1, 0),
                  ngon(4, 0.062 if k else 0.078, phase=0.0 if k else pi / 4), 0.04, "Stone", wk, col=S_CREAM)
    # crestería: cornisas y pilares calados, cada vez más estrechos; le falta un pilar
    blk("t1", (-1.03, -0.56, HZ + 0.88), (1.03, 0.56, HZ + 1.00), wk, bevel=0.04, moss=0.45, chips=(4,))
    for k, cx in enumerate((-0.74, -0.37, 0.0, 0.37, 0.74)):
        broken = (k == 4)
        blk("t2_%d" % k, (cx - 0.135, -0.38, HZ + 1.00), (cx + 0.135, 0.38, HZ + (1.09 if broken else 1.22)), wk, bevel=0.03,
            chips=(4, 7) if broken else None, taper=(0.8, 0.8) if broken else (1.0, 1.0))
    blk("t3", (-0.88, -0.45, HZ + 1.22), (0.56, 0.45, HZ + 1.31), wk, bevel=0.03, moss=0.5, chips=(5, 7))
    for k, cx in enumerate((-0.46, 0.0, 0.46)):
        blk("t4_%d" % k, (cx - 0.145, -0.31, HZ + 1.31), (cx + 0.145, 0.31, HZ + 1.49), wk, bevel=0.03)
    blk("t5", (-0.64, -0.37, HZ + 1.49), (0.64, 0.37, HZ + 1.57), wk, bevel=0.025, moss=0.4, chips=())
    blk("t6", (-0.26, -0.26, HZ + 1.57), (0.26, 0.26, HZ + 1.70), wk, bevel=0.03, moss=0.3, chips=(), taper=(0.8, 0.8))
    # placa escalonada al frente de la crestería
    for k, (hw, z0, z1) in enumerate(((0.32, 0.97, 1.09), (0.21, 1.09, 1.20), (0.11, 1.20, 1.30))):
        add_prism(mb, (0.0, -0.38, HZ), (1, 0, 0), (0, 0, 1), (0, -1, 0), _r(-hw, z0, hw, z1), 0.08, "Stone", wk, col=S_WARM,
                  back=True)

    # ── musgo ──
    def moss_on(name, u, v, r, flat=0.5):
        b, w = B[name]
        add_moss(mb, b.at("z+", u, v)[0] - Vector((0, 0, r * 0.12)), r, w, rng, flat)

    for name, u, v, r in (("shtop_L", -0.2, 0.2, 0.24), ("shtop_L", 0.5, -0.4, 0.17), ("shoulder_L", 0.72, 0.55, 0.19),
                          ("shoulder_L", -0.6, -0.7, 0.15), ("shtop_R", 0.1, -0.2, 0.22), ("shoulder_R", -0.7, -0.5, 0.2),
                          ("shoulder_R", 0.55, 0.6, 0.16), ("chC2", 0.75, 0.3, 0.15), ("chC0", -0.7, -0.4, 0.13),
                          ("t1", -0.82, 0.1, 0.16), ("t1", 0.86, -0.3, 0.13), ("t3", -0.7, 0.0, 0.12),
                          ("t5", 0.7, 0.1, 0.09), ("t3", 0.2, -0.4, 0.10), ("racktop", 0.4, 0.2, 0.13),
                          ("foot_R", 0.3, 0.6, 0.14), ("t2_4", 0.0, 0.0, 0.12)):
        moss_on(name, u, v, r)

    def tufts(name, face, us, w_len, out):
        b, w = B[name]
        for u in us:
            p = b.at(face, u, 0.93)[0]
            add_tuft(mb, p, w_len * rng.uniform(0.6, 1.3), w, rng, out)

    tufts("shoulder_L", "y-", (-0.7, -0.35, 0.1, 0.5, 0.8), 0.22, (0, -1, 0))
    tufts("shoulder_L", "x+", (-0.6, 0.0, 0.55), 0.20, (1, 0, 0))
    tufts("shoulder_L", "y+", (-0.5, 0.2, 0.7), 0.24, (0, 1, 0))
    tufts("shoulder_R", "y-", (-0.75, -0.2, 0.3), 0.18, (0, -1, 0))
    tufts("shoulder_R", "x-", (-0.4, 0.3), 0.22, (-1, 0, 0))
    tufts("shoulder_R", "y+", (-0.6, -0.1, 0.5), 0.22, (0, 1, 0))
    tufts("t1", "y-", (-0.9, -0.7, 0.62, 0.85), 0.14, (0, -1, 0))
    tufts("t1", "y+", (-0.8, -0.3, 0.5), 0.16, (0, 1, 0))
    tufts("racktop", "y+", (-0.6, 0.1, 0.7), 0.16, (0, 1, 0))

    # ── raíces ──
    def on(name, face, u, v, off=0.03):
        return B[name][0].at(face, u, v, off)[0]

    wuL, wuR = {"UpperArm_L": 1}, {"UpperArm_R": 1}
    add_root(mb, [on("shtop_L", "z+", -0.5, 0.5), on("shtop_L", "z+", 0.3, -0.2), on("shtop_L", "y-", 0.75, 0.2),
                  on("shoulder_L", "z+", 0.55, -0.85), on("shoulder_L", "y-", 0.5, 0.6), on("shoulder_L", "y-", 0.15, -0.2),
                  on("shoulder_L", "y-", 0.35, -0.9), on("uarm_L", "y-", 0.3, 0.3), on("uarm_L", "y-", -0.1, -0.7)],
             0.055, 0.018, wuL)
    add_root(mb, [on("shtop_L", "z+", 0.1, 0.6), on("shtop_L", "x+", 0.4, 0.3), on("shoulder_L", "z+", 0.85, 0.3),
                  on("shoulder_L", "x+", 0.35, 0.5), on("shoulder_L", "x+", 0.6, -0.3), on("shoulder_L", "x+", 0.3, -0.9)],
             0.045, 0.015, wuL)
    add_root(mb, [on("shtop_R", "z+", 0.4, -0.3), on("shtop_R", "y+", 0.2, 0.2), on("shoulder_R", "z+", 0.3, 0.85),
                  on("shoulder_R", "y+", 0.1, 0.5), on("shoulder_R", "y+", -0.3, -0.2), on("shoulder_R", "y+", -0.1, -0.9),
                  on("uarm_R", "y+", 0.2, 0.2), on("uarm_R", "y+", -0.2, -0.8)], 0.05, 0.016, wuR)
    add_root(mb, [on("t3", "z+", -0.6, -0.3), on("t3", "x-", -0.2, 0.0), on("t2_0", "x-", 0.0, 0.2), on("t1", "z+", -0.92, 0.0),
                  on("t1", "x-", 0.1, 0.0), on("band", "x-", 0.2, 0.3), on("flare_R", "z+", -0.2, 0.3),
                  on("flare_R", "x-", 0.4, 0.2), on("flare_R", "x-", 0.6, -0.7)], 0.045, 0.014, wk)
    add_root(mb, [on("t5", "z+", 0.5, 0.4), on("t5", "y+", 0.55, 0.0), on("t4_2", "y+", 0.2, 0.0), on("t3", "z+", 0.45, 0.8),
                  on("t3", "y+", 0.3, 0.0), on("t2_3", "y+", 0.2, 0.2), on("t1", "z+", 0.3, 0.9), on("t1", "y+", 0.25, 0.0),
                  on("band", "y+", 0.3, 0.2), on("skullB", "y+", 0.45, -0.3)], 0.04, 0.012, wk)
    add_root(mb, [on("chC2", "z+", 0.5, 0.2), on("chC2", "z+", 0.62, 0.9), on("chC2", "y+", 0.55, 0.3),
                  on("chC2", "y+", 0.75, -0.6), on("chB3", "y+", 0.3, 0.3), on("chB3", "y+", 0.55, -0.7),
                  on("chA2", "y+", 0.2, 0.2), on("chA2", "y+", 0.45, -0.85)], 0.05, 0.015, wc)
    add_root(mb, [on("racksill", "z+", -0.8, 0.5), on("racksill", "y+", -0.7, 0.0), on("chB1", "y+", -0.2, 0.1),
                  on("chB1", "y+", -0.5, -0.8), on("chA0", "y+", 0.5, 0.2), on("chA0", "y+", 0.2, -0.8)], 0.04, 0.012, wc)

    # ── vetas del Silencio ──
    vr = random.Random(77)

    def vein(width, spec, amp=0.05):
        add_vein(mb, vein_path(B, spec, vr, amp), width, B[spec[0][0]][1])

    for s, sfx in ((1, "_L"), (-1, "_R")):
        ox = "x+" if s > 0 else "x-"
        # del hombro al codo, por fuera y por delante
        vein(0.12, [("shoulder" + sfx, "z+", 0.2 * s, 0.5), ("shoulder" + sfx, "z+", 0.95 * s, -0.1),
                    ("shoulder" + sfx, ox, -0.15, 0.95), ("shoulder" + sfx, ox, 0.45, -0.1), ("shoulder" + sfx, ox, 0.1, -0.95),
                    ("uarm" + sfx, ox, 0.2, 0.9), ("uarm" + sfx, ox, -0.35, -0.9)])
        vein(0.07, [("shoulder" + sfx, ox, 0.45, -0.1), ("shoulder" + sfx, ox, 0.85, -0.6)])
        vein(0.10, [("shoulder" + sfx, "y-", 0.75 * s, 0.9), ("shoulder" + sfx, "y-", 0.1 * s, 0.1),
                    ("shoulder" + sfx, "y-", 0.4 * s, -0.95), ("uarm" + sfx, "y-", 0.3 * s, 0.9), ("uarm" + sfx, "y-", -0.3 * s, -0.8)])
        vein(0.06, [("shoulder" + sfx, "y-", 0.1 * s, 0.1), ("shoulder" + sfx, "y-", -0.55 * s, -0.35)])
        # antebrazo y dorso de la mano
        vein(0.11, [("foreA" + sfx, ox, -0.4, 0.95), ("foreA" + sfx, ox, 0.3, -0.9), ("foreB" + sfx, ox, 0.65, 0.9),
                    ("foreB" + sfx, ox, 0.8, -0.85)])
        vein(0.10, [("foreA" + sfx, "y-", -0.5 * s, 0.95), ("foreA" + sfx, "y-", 0.35 * s, -0.9),
                    ("foreB" + sfx, "y-", 0.3 * s, 0.9), ("foreB" + sfx, "y-", -0.45 * s, -0.9)])
        vein(0.06, [("foreB" + sfx, "y-", 0.1 * s, 0.1), ("foreB" + sfx, "y-", 0.75 * s, -0.5)])
        vein(0.08, [("palm" + sfx, ox, -0.3, 0.9), ("palm" + sfx, ox, 0.35, -0.8)], amp=0.03)
    # pecho: trepan desde el vientre hacia el pectoral y bajan de los hombros
    vein(0.10, [("abdA0", "y-", 0.1, -0.9), ("abdA0", "y-", -0.4, 0.9), ("abdB0", "y-", 0.5, -0.9), ("abdB0", "y-", -0.1, 0.9)])
    vein(0.09, [("abdA1", "y-", 0.2, -0.9), ("abdA1", "y-", 0.6, 0.9), ("abdB2", "y-", -0.3, -0.9), ("abdB2", "y-", 0.3, 0.9)])
    vein(0.10, [("chA0", "y-", -0.35, -0.9), ("chA0", "y-", 0.2, 0.0), ("chA0", "y-", -0.5, 0.9)])
    vein(0.10, [("chA2", "y-", 0.5, -0.9), ("chA2", "y-", -0.15, 0.1), ("chA2", "y-", 0.55, 0.9)])
    vein(0.08, [("chA1", "y-", -0.9, -0.95), ("chA1", "y-", -0.6, 0.5)])
    vein(0.07, [("plate", "y-", -0.96, 0.95), ("plate", "y-", -0.955, -0.2), ("plate", "y-", -0.97, -0.9)], amp=0.012)
    vein(0.07, [("plate", "y-", 0.97, 0.9), ("plate", "y-", 0.955, 0.0), ("plate", "y-", 0.965, -0.95)], amp=0.012)
    vein(0.09, [("chC2", "z+", 0.55, 0.5), ("chC2", "z+", 0.8, -0.95), ("chC2", "y-", 0.84, 0.9), ("chC2", "y-", 0.9, -0.8)], amp=0.03)
    vein(0.09, [("chC0", "z+", -0.5, 0.3), ("chC0", "z+", -0.85, -0.95), ("chC0", "y-", -0.86, 0.9), ("chC0", "y-", -0.9, -0.7)], amp=0.03)
    # espalda: se cierran sobre el corazón
    vein(0.11, [("chC2", "y+", 0.9, 0.7), ("chC2", "y+", 0.3, -0.2), ("chB3", "y+", -0.2, 0.9), ("chB3", "y+", -0.7, 0.2)])
    vein(0.11, [("chC0", "y+", -0.92, 0.5), ("chC0", "y+", -0.25, -0.5), ("chB0", "y+", 0.4, 0.9), ("chB0", "y+", 0.8, 0.0)])
    vein(0.10, [("chA1", "y+", 0.6, -0.9), ("chA1", "y+", -0.2, 0.0), ("chA1", "y+", 0.25, 0.95), ("chB2", "y+", -0.7, -0.5)])
    vein(0.09, [("abdB1", "y+", -0.5, -0.9), ("abdB1", "y+", 0.3, 0.9), ("chA1", "y+", -0.55, -0.6)])
    # cabeza: de la crestería a la mejilla, y por la sien
    vein(0.09, [("t1", "y-", -0.42, 0.9), ("t1", "y-", -0.5, -0.9), ("band", "y-", -0.62, 0.9), ("band", "y-", -0.48, -0.9),
                ("brow", "y-", -0.68, 0.9), ("brow", "y-", -0.86, -0.9)])
    vein(0.08, [("cheek_R", "y-", 0.6, 0.95), ("cheek_R", "y-", -0.1, 0.0), ("cheek_R", "y-", 0.5, -0.95)], amp=0.03)
    vein(0.08, [("t3", "y-", 0.1, 0.9), ("t3", "y-", 0.3, -0.9), ("t2_3", "y-", -0.3, 0.9), ("t2_3", "y-", 0.4, -0.9),
                ("t1", "y-", 0.5, 0.9), ("t1", "y-", 0.62, -0.9)], amp=0.02)
    vein(0.09, [("band", "x+", -0.2, 0.9), ("band", "x+", 0.1, -0.9), ("skullB", "x+", 0.3, 0.9), ("skullB", "x+", 0.75, -0.6)])
    vein(0.08, [("jaw", "y-", 0.75, 0.9), ("jaw", "y-", 0.55, -0.9)], amp=0.02)
    return mb


# ──────────────────────────────── Animaciones ────────────────────────────────
# Las piernas van por cinemática inversa con los pseudo-canales "IK_L" / "IK_R"
# (desplazamiento de la punta del pie respecto al reposo) e "IKR_*" (giro del pie en el
# mundo). Sin ellos, la pierna va por cinemática directa (de rodillas).

CONTACT = {"L": TOE, "R": mx(TOE, -1)}
WALK_T, WALK_SPEED, WALK_STANCE = 1.6, 1.0, 0.6      # «Walk» está compuesta para 1.0 m/s
CHARGE_T, CHARGE_SPEED, CHARGE_STANCE = 0.8, 2.2, 0.5   # «Charge», para 2.2 m/s


def side(d, s):
    """Como both(), pero de un solo lado: la pose se describe para el izquierdo."""
    out = {}
    for k, v in d.items():
        bone, _, suf = k.partition(".")
        suf = "." + suf if suf else ""
        if s == "L":
            out[bone + "_L" + suf] = v
        elif suf == ".loc":
            out[bone + "_R" + suf] = (-v[0], v[1], v[2])
        elif suf == ".scale":
            out[bone + "_R" + suf] = v
        else:
            out[bone + "_R" + suf] = (v[0], -v[1], -v[2])
    return out


def finish(p):
    p = dict(p)
    for s in ("L", "R"):
        ik = p.pop("IK_" + s, None)
        ikr = p.pop("IKR_" + s, (0, 0, 0))
        if ik is not None:
            RIG.ik(p, "Thigh_" + s, "Shin_" + s, [("Foot_" + s, ikr)], CONTACT[s], CONTACT[s] + Vector(ik), bend=-1.0)
    return p


def _hand_points(s):
    sx = 1 if s == "L" else -1
    pts = []
    for bone, (z0, z1), hx, hy in (("Hand_", PALM_Z, 0.17, 0.42), ("Fingers_", FINGER_Z, 0.14, 0.41),
                                   ("FingerTips_", TIP_Z, 0.13, 0.40)):
        pts.append((bone + s, [Vector((sx * (AX + a * hx), b * hy, z)) for a in (-1, 1) for b in (-1, 1) for z in (z0, z1)]))
    tr, piv = Matrix.Rotation(rad(-38), 3, "X"), Vector((AX, -0.40, 1.04))        # como los sillares del pulgar
    thumb = [piv + tr @ (Vector((AX + a * 0.12, y, 0.56)) - piv) for a in (-1, 1) for y in (-0.52, -0.30)]
    pts.append(("Thumb_" + s, [mx(q, sx) for q in thumb]))
    return pts


HAND_PTS = {"L": _hand_points("L"), "R": _hand_points("R")}


def hand_low(p, s):
    """Altura del punto más bajo de la mano (palma y dedos) en la pose `p`."""
    low = 1e9
    for bone, pts in HAND_PTS[s]:
        D = RIG.deform(p, bone)
        low = min(low, min((D @ q).z for q in pts))
    return low


def plant_hand(p, s, z=0.0, only_up=False, joint="UpperArm"):
    """Ajusta la flexión del hombro (o del codo, joint="Forearm") para que lo más bajo de
    la mano quede a la altura z: puños apoyados en el suelo. Con only_up solo corrige si
    la mano se hunde. Método de la secante desde el ángulo dado: da la solución más cercana."""
    bone = joint + "_" + s
    r0 = tuple(p.get(bone, (0.0, 0.0, 0.0)))

    def f(a):
        p[bone] = (a, r0[1], r0[2])
        return hand_low(p, s) - z

    a0, f0 = r0[0], f(r0[0])
    if abs(f0) < 2e-4 or (only_up and f0 > 0.0):
        p[bone] = r0
        return p
    a1 = a0 + 2.0
    f1 = f(a1)
    for _ in range(14):
        if abs(f1) < 2e-4 or abs(f1 - f0) < 1e-9:
            break
        a2 = a1 - f1 * (a1 - a0) / (f1 - f0)
        a2 = min(max(a2, a1 - 25.0), a1 + 25.0)
        a0, f0, a1 = a1, f1, a2
        f1 = f(a1)
    if abs(f1) > 5e-3:                          # sin solución cerca: se queda como estaba
        p[bone] = r0
    return p


def heart(s):
    return {"HeartBone.scale": (s, s, s)}


def lids(close):
    """Párpados de piedra: 0 = abiertos (ocultos bajo la ceja), 1 = cerrados."""
    return {"Lids.loc": (0.0, 0.0, -0.155 * close)}


GROUND = {"IK_L": (0, 0, 0), "IK_R": (0, 0, 0)}
RELAX = both({"Fingers": (0, 20, 0), "FingerTips": (0, 24, 0), "Thumb": (0, 6, 0)})
FIST = both({"Fingers": (0, 92, 0), "FingerTips": (0, 86, 0), "Thumb": (10, 30, 0)})
OPEN = both({"Fingers": (0, -6, 0), "FingerTips": (0, 6, 0), "Thumb": (-12, -14, 0)})
ARMS = both({"UpperArm": (3, -5, 0), "Forearm": (-12, 0, 0)})


def idle_pose(t):
    ph = 2 * pi * t / 4.0
    br = sin(ph)
    p = {**GROUND, **RELAX, **lids(0.3), **heart(1.0 + 0.05 * bump(t % 2.0, 0.0, 0.7))}
    p["Hips.loc"] = (0.0, 0.0, -0.03 - 0.012 * br)
    p["Hips"] = (0.5, 0, 0)
    p["Spine"] = (1.5 + 0.9 * br, 0, 0)
    p["Chest"] = (1.5 + 1.1 * br, 0, 1.2 * sin(ph + 1.0) - 1.2 * sin(1.0))
    p["Head"] = (4.0 - 1.6 * br, 0, 3.0 * sin(ph + 0.6) - 3.0 * sin(0.6))
    p.update(both({"UpperArm": (3 + 1.4 * br, -5 - 1.0 * br, 0), "Forearm": (-12 - 1.8 * br, 0, 0)}))
    return p


def idle(t):
    return finish(idle_pose(t))


I0 = idle_pose(0.0)


def _step(f, half, lift, stance, heel=16.0):
    """Trayectoria de un pie: (avance, altura, giro) para la fase f del ciclo."""
    f %= 1.0
    if f < stance:
        return -half + 2.0 * half * f / stance, 0.0, heel * smooth(f / stance, 0.7, 1.0)
    g = (f - stance) / (1.0 - stance)
    e = g * g * (3 - 2 * g)
    return half - 2.0 * half * e, lift * sin(pi * g), heel * (1.0 - smooth(g, 0.0, 0.4)) - 7.0 * bump(g, 0.45, 1.0)


def walk(t):
    u = t / WALK_T
    half = 0.5 * WALK_SPEED * WALK_T * WALK_STANCE
    p = {**RELAX, **lids(0.3), **heart(1.0)}
    for s, off in (("L", 0.0), ("R", 0.5)):
        y, z, pitch = _step(u + off, half, 0.30, WALK_STANCE)
        p["IK_" + s] = (0.04 if s == "L" else -0.04, y, z)
        p["IKR_" + s] = (pitch, 0, 0)
    c = cos(2 * pi * u)
    sway = cos(2 * pi * (u - 0.3))
    thud = bump(u % 0.5, 0.0, 0.2)                       # el pisotón, justo al plantar cada pie
    p["Hips.loc"] = (0.12 * sway, -0.03, -0.15 - 0.03 * cos(4 * pi * u) - 0.035 * thud)
    p["Hips"] = (3, 2.5 * sway, -6 * c)
    p["Spine"] = (4, -1.5 * sway, 4 * c)
    p["Chest"] = (4 + 1.5 * thud, -1.5 * sway, 7 * c)
    p["Head"] = (2 + 2.5 * thud, 0, -5 * c)
    p.update(side({"UpperArm": (2 + 13 * c, -6, 0), "Forearm": (-16 + 5 * c, 0, 0)}, "L"))
    p.update(side({"UpperArm": (2 - 13 * c, -6, 0), "Forearm": (-16 - 5 * c, 0, 0)}, "R"))
    return finish(p)


def charge(t):
    u = t / CHARGE_T
    half = 0.5 * CHARGE_SPEED * CHARGE_T * CHARGE_STANCE
    p = {**FIST, **lids(0.0), **heart(1.0)}
    for s, off in (("L", 0.0), ("R", 0.5)):
        y, z, pitch = _step(u + off, half, 0.40, CHARGE_STANCE, heel=22.0)
        p["IK_" + s] = (0.0, y, z)
        p["IKR_" + s] = (pitch, 0, 0)
    c = cos(2 * pi * u)
    thud = bump(u % 0.5, 0.0, 0.3)
    p["Hips.loc"] = (0.05 * cos(2 * pi * (u - 0.25)), -0.20, -0.27 - 0.04 * cos(4 * pi * u))
    p["Hips"] = (16, 0, -5 * c)
    p["Spine"] = (14, 0, 3 * c)
    p["Chest"] = (12 + 2 * thud, 0, 6 * c)
    p["Head"] = (-24 + 3 * thud, 0, -4 * c)
    p.update(side({"UpperArm": (24 + 8 * c, -16, 0), "Forearm": (-52 + 6 * c, 0, 0)}, "L"))
    p.update(side({"UpperArm": (24 - 8 * c, -16, 0), "Forearm": (-52 - 6 * c, 0, 0)}, "R"))
    return finish(p)


def stunned(t):
    ph = 2 * pi * t / 2.4
    p = {**GROUND, **RELAX, **lids(0.6), **heart(1.0), "Jaw": (7 + 2 * sin(2 * ph), 0, 0)}
    p["Hips.loc"] = (0.10 * sin(ph), -0.05 + 0.07 * cos(ph), -0.14 - 0.02 * sin(2 * ph))
    p["Hips"] = (2 + 3 * cos(ph), 3 * sin(ph), 0)
    p["Spine"] = (7 + 5 * cos(ph + 0.4), 5 * sin(ph + 0.4), 0)
    p["Chest"] = (6 + 4 * cos(ph + 0.8), 4 * sin(ph + 0.8), 3 * sin(ph))
    p["Head"] = (14 + 7 * cos(ph + 1.5), 9 * sin(ph + 1.5), 6 * sin(ph + 0.7))
    p.update(side({"UpperArm": (-4 + 7 * cos(ph + 1.9), -9 - 3 * sin(ph + 1.9), 0), "Forearm": (-10 - 5 * cos(ph + 2.4), 0, 0)}, "L"))
    p.update(side({"UpperArm": (-4 + 7 * cos(ph + 2.3), -9 + 3 * sin(ph + 2.3), 0), "Forearm": (-10 - 5 * cos(ph + 2.8), 0, 0)}, "R"))
    for s in ("L", "R"):
        plant_hand(p, s, only_up=True)
    return finish(p)


# ── golpes ──
SLAM_T, SLAM_HIT, SLAM_HOLD = 2.6, 1.45, 1.85    # alza el puño derecho hasta 1.2 s y golpea a 1.45 s
_FIST_R = side({"Fingers": (0, 92, 0), "FingerTips": (0, 86, 0), "Thumb": (10, 30, 0)}, "R")
_RELAX_L = side({"Fingers": (0, 20, 0), "FingerTips": (0, 24, 0), "Thumb": (0, 6, 0)}, "L")
SLAM_PREP = {**GROUND, **_FIST_R, **_RELAX_L, **lids(0.1), "Hips.loc": (0.04, 0.04, -0.18), "Hips": (2, 0, -5),
             "Spine": (4, 0, -6), "Chest": (2, 0, -10), "Head": (0, 0, 10),
             **side({"UpperArm": (-70, -22, 0), "Forearm": (-80, 0, 0)}, "R"),
             **side({"UpperArm": (8, -14, 0), "Forearm": (-24, 0, 0)}, "L")}
SLAM_UP = {**GROUND, **_FIST_R, **_RELAX_L, **lids(0.0), "Hips.loc": (0.05, 0.10, -0.09), "Hips": (-4, 0, -8),
           "Spine": (-6, 0, -10), "Chest": (-8, 0, -16), "Head": (-4, 0, 16), "Jaw": (5, 0, 0),
           **side({"UpperArm": (-160, 28, 0), "Forearm": (-34, 0, 0)}, "R"),
           **side({"UpperArm": (16, -24, 0), "Forearm": (-30, 0, 0)}, "L")}
SLAM_DOWN = plant_hand({**GROUND, **_FIST_R, **_RELAX_L, **lids(0.0), "Hips.loc": (0.0, -0.30, -0.42), "Hips": (16, 0, 4),
                        "Spine": (20, 0, 6), "Chest": (20, 0, 10), "Head": (-36, 0, -10), "Jaw": (9, 0, 0),
                        **side({"UpperArm": (-82, -4, 0), "Forearm": (-20, 0, 0)}, "R"),
                        **side({"UpperArm": (38, -20, 0), "Forearm": (-40, 0, 0)}, "L")}, "R")


def slam(t):
    p = pose_keys(t, [(0.0, I0), (0.5, SLAM_PREP), (1.2, SLAM_UP), (SLAM_HIT, SLAM_DOWN), (SLAM_HOLD, SLAM_DOWN), (SLAM_T, I0)])
    p.update(heart(1.0))
    if SLAM_HIT <= t <= SLAM_HOLD:
        k = bump(t, SLAM_HIT, SLAM_HOLD)
        p["Chest"] = (p["Chest"][0] + 1.5 * k * sin(60 * t), p["Chest"][1], p["Chest"][2])
        plant_hand(p, "R")
    else:
        plant_hand(p, "R", only_up=True)
    plant_hand(p, "L", only_up=True)
    return finish(p)


SUMMON_T, SUMMON_HIT, SUMMON_HOLD = 2.6, 1.30, 1.90
_WIDE = {"IK_L": (0.12, 0, 0), "IK_R": (-0.12, 0, 0)}
SUMMON_PREP = {**_WIDE, **FIST, **lids(0.1), "Hips.loc": (0, 0.02, -0.24), "Hips": (2, 0, 0), "Spine": (6, 0, 0),
               "Chest": (4, 0, 0), "Head": (0, 0, 0), **both({"UpperArm": (-60, -20, 0), "Forearm": (-85, 0, 0)})}
SUMMON_UP = {**_WIDE, **FIST, **lids(0.0), "Hips.loc": (0.0, 0.12, -0.08), "Hips": (-5, 0, 0), "Spine": (-8, 0, 0),
             "Chest": (-10, 0, 0), "Head": (-8, 0, 0), "Jaw": (6, 0, 0),
             **both({"UpperArm": (-168, 16, 0), "Forearm": (-28, 0, 0)})}
SUMMON_DOWN = {**_WIDE, **FIST, **lids(0.0), "Hips.loc": (0.0, -0.26, -0.50), "Hips": (18, 0, 0), "Spine": (22, 0, 0),
               "Chest": (22, 0, 0), "Head": (-42, 0, 0), "Jaw": (10, 0, 0), **both({"UpperArm": (-84, 6, 0), "Forearm": (-18, 0, 0)})}
for _s in ("L", "R"):
    plant_hand(SUMMON_DOWN, _s)


def summon(t):
    p = pose_keys(t, [(0.0, I0), (0.45, SUMMON_PREP), (1.0, SUMMON_UP), (SUMMON_HIT, SUMMON_DOWN), (SUMMON_HOLD, SUMMON_DOWN),
                      (SUMMON_T, I0)])
    p.update(heart(1.0))
    lift = 0.08 * bump(t, 0.05, 0.4) + 0.08 * bump(t, 2.1, 2.55)             # abre y cierra los pies
    for s in ("L", "R"):
        p["IK_" + s] = (p["IK_" + s][0], 0.0, lift)
        plant_hand(p, s, only_up=not (SUMMON_HIT <= t <= SUMMON_HOLD))
    return finish(p)


SWEEP_T, SWEEP_START, SWEEP_END = 2.2, 0.9, 1.35       # el brazo derecho barre entre 0.9 y 1.35 s
_OPEN_R = side({"Fingers": (0, 4, 0), "FingerTips": (0, 10, 0), "Thumb": (-8, -8, 0)}, "R")
_STEP = {"IK_L": (0.10, -0.10, 0), "IK_R": (-0.14, 0.12, 0)}
SWEEP_BACK = {**_STEP, **_OPEN_R, **_RELAX_L, **lids(0.0), "Hips.loc": (-0.10, 0.0, -0.36), "Hips": (8, 0, -16),
              "Spine": (10, 0, -16), "Chest": (10, 0, -24), "Head": (-12, 0, 40),
              **side({"UpperArm": (-58, -34, 12), "Forearm": (-12, 0, 0), "Hand": (0, 0, 60)}, "R"),
              **side({"UpperArm": (20, -18, 0), "Forearm": (-35, 0, 0)}, "L")}
SWEEP_MID = {**_STEP, **_OPEN_R, **_RELAX_L, **lids(0.0), "Hips.loc": (0.0, -0.10, -0.42), "Hips": (10, 0, 2),
             "Spine": (12, 0, 4), "Chest": (12, 0, 8), "Head": (-16, 0, -6),
             **side({"UpperArm": (-62, -20, 0), "Forearm": (-8, 0, 0), "Hand": (0, 0, 60)}, "R"),
             **side({"UpperArm": (26, -22, 0), "Forearm": (-45, 0, 0)}, "L")}
SWEEP_FWD = {**_STEP, **_OPEN_R, **_RELAX_L, **lids(0.0), "Hips.loc": (0.12, -0.06, -0.38), "Hips": (8, 0, 18),
             "Spine": (10, 0, 20), "Chest": (10, 0, 30), "Head": (-12, 0, -36),
             **side({"UpperArm": (-58, -6, -22), "Forearm": (-16, 0, 0), "Hand": (0, 0, 60)}, "R"),
             **side({"UpperArm": (30, -26, 0), "Forearm": (-50, 0, 0)}, "L")}


def sweep(t):
    p = pose_keys(t, [(0.0, I0), (0.35, {**I0, **_STEP, "Hips.loc": (-0.04, 0.0, -0.18), "Chest": (4, 0, -8)}),
                      (SWEEP_START, SWEEP_BACK), (0.5 * (SWEEP_START + SWEEP_END), SWEEP_MID), (SWEEP_END, SWEEP_FWD),
                      (1.65, {**SWEEP_FWD, "Hips.loc": (0.12, -0.04, -0.32), "Chest": (8, 0, 34)}),
                      (SWEEP_T, I0)])
    p.update(heart(1.0))
    lift = 0.10 * bump(t, 0.05, 0.35) + 0.10 * bump(t, 1.75, 2.15)          # recoloca los pies al abrir y al cerrar
    for s in ("L", "R"):
        v = p["IK_" + s]
        p["IK_" + s] = (v[0], v[1], lift if s == "R" else 0.6 * lift)
        plant_hand(p, s, z=0.2 if s == "R" else 0.0, only_up=True)
    return finish(p)


# ── sentado, de rodillas ──
SEAT_Z = -1.03                                # la pelvis descansa en el suelo
_SEAT_FEET = {"IK_L": (0.46, 0.06, 0), "IK_R": (-0.46, 0.06, 0)}       # rodillas abiertas
SEAT = {**_SEAT_FEET, **lids(1.0), "Hips.loc": (0.0, 0.80, SEAT_Z), "Hips": (-4, 0, 0), "Spine": (10, 0, 0),
        "Chest": (11, 0, 0), "Head": (39, 0, 0),
        **both({"UpperArm": (-27, 9, 0), "Forearm": (-56, 0, 0), "Hand": (58, 0, 0), "Fingers": (0, 30, 0),
                "FingerTips": (0, 34, 0), "Thumb": (0, 10, 0)})}
KNEEL_Z = -0.50                               # de rodillas: las espinillas descansan en el suelo
KNEEL_LEGS = both({"Thigh": (-6, 0, 0), "Shin": (96, 0, 0), "Foot": (62, 0, 0)})
KNEEL_TOP = {**FIST, **lids(0.55), "Hips.loc": (0.0, 0.10, KNEEL_Z), "Hips": (2, 0, 0), "Spine": (5, 0, 0),
             "Chest": (6, 0, 0), "Head": (20, 0, 0), **both({"UpperArm": (-6, -7, 0), "Forearm": (-10, 0, 0)})}
for _s in ("L", "R"):
    plant_hand(KNEEL_TOP, _s)
KNEEL = {**KNEEL_LEGS, **KNEEL_TOP}
# para arrodillarse por cinemática inversa: adónde va a parar la punta del pie, y con qué giro
KNEEL_TOE = RIG.point(KNEEL, "Foot_L", TOE) - TOE
KNEEL_FOOT = (-6.0 + 96.0 + 62.0, 0.0, 0.0)


def sleep(t):
    br = sin(2 * pi * t / 4.0)
    p = dict(SEAT)
    p["Chest"] = (SEAT["Chest"][0] + 0.45 * br, 0, 0)
    p["Head"] = (SEAT["Head"][0] - 0.35 * br, 0, 0)
    p.update(heart(1.0 + 0.04 * bump(t, 0.2, 1.4)))
    for s in ("L", "R"):
        plant_hand(p, s, only_up=True)
    return finish(p)


AWAKEN_T, AWAKEN_SIT = 4.0, 1.45              # hasta 1.45 s sigue sentado; a 3.3 s ya está en pie
AWAKEN_KEYS = [
    (0.0, SEAT), (0.7, SEAT),
    (AWAKEN_SIT, {**SEAT, **lids(0.0), "Spine": (5, 0, 0), "Chest": (3, 0, 0), "Head": (-4, 0, 0), "Jaw": (6, 0, 0),
                  **both({"UpperArm": (-20, 4, 0), "Forearm": (-40, 0, 0), "Hand": (20, 0, 0)}), **FIST}),
    (2.1, {**GROUND, **FIST, "Hips.loc": (0.0, 0.50, -0.90), "Hips": (14, 0, 0), "Spine": (16, 0, 0), "Chest": (12, 0, 0),
           "Head": (-22, 0, 0), "Jaw": (8, 0, 0), **both({"UpperArm": (-30, -9, 0), "Forearm": (-30, 0, 0)})}),
    (2.75, {**GROUND, **FIST, "Hips.loc": (0.0, -0.04, -0.52), "Hips": (22, 0, 0), "Spine": (16, 0, 0), "Chest": (10, 0, 0),
            "Head": (-28, 0, 0), "Jaw": (4, 0, 0), **both({"UpperArm": (-30, -10, 0), "Forearm": (-22, 0, 0)})}),
    (3.3, {**GROUND, **RELAX, "Hips.loc": (0.0, 0.0, -0.10), "Hips": (5, 0, 0), "Spine": (4, 0, 0), "Chest": (0, 0, 0),
           "Head": (-4, 0, 0), **both({"UpperArm": (8, -14, 0), "Forearm": (-22, 0, 0)})}),
    (3.6, {**GROUND, **RELAX, "Hips.loc": (0.0, 0.0, -0.02), "Hips": (-1, 0, 0), "Spine": (-2, 0, 0), "Chest": (-4, 0, 0),
           "Head": (2, 0, 0), **both({"UpperArm": (6, -12, 0), "Forearm": (-16, 0, 0)})}),
    (AWAKEN_T, I0),
]
for _t, _p in AWAKEN_KEYS[3:5]:
    for _s in ("L", "R"):
        plant_hand(_p, _s)


def awaken(t):
    p = pose_keys(t, AWAKEN_KEYS)
    p.update(heart(1.0 + 0.10 * bump(t, 0.1, 0.7) + 0.10 * bump(t, 0.8, 1.4)))
    # dos sacudidas: el temblor con que se resquebraja (0.3–1.4 s) y la de quitarse el polvo ya en pie
    q1, q2 = bump(t, 0.25, 1.45), bump(t, 3.15, 3.95)
    wob = 1.6 * q1 * sin(2 * pi * 9.0 * t) + 6.5 * q2 * sin(2 * pi * 4.0 * (t - 3.15))
    p["Chest"] = (p["Chest"][0], p["Chest"][1] + 0.5 * wob, p["Chest"][2] + wob)
    p["Head"] = (p["Head"][0], p["Head"][1] - 0.3 * wob, p["Head"][2] - 0.7 * wob + 1.2 * q1 * sin(2 * pi * 7.0 * t))
    p["Hips.loc"] = (p["Hips.loc"][0] + 0.012 * q1 * sin(2 * pi * 11.0 * t), p["Hips.loc"][1], p["Hips.loc"][2])
    for s in ("L", "R"):
        plant_hand(p, s, only_up=not (2.0 <= t <= 2.8))
    return finish(p)


KNEEL_T, KNEEL_HIT = 2.0, 0.95                # las rodillas tocan el suelo a 0.95 s
KNEEL_KEYS = [
    (0.0, I0),
    (0.45, {**GROUND, **RELAX, **lids(0.4), "Hips.loc": (0.0, -0.06, -0.26), "Hips": (8, 0, 0), "Spine": (8, 0, 0),
            "Chest": (6, 0, 0), "Head": (10, 0, 0), **both({"UpperArm": (-10, -12, 0), "Forearm": (-26, 0, 0)})}),
    (KNEEL_HIT, {**GROUND, **FIST, **lids(0.7), "Hips.loc": (0.0, 0.06, KNEEL_Z - 0.02), "Hips": (10, 0, 0), "Spine": (12, 0, 0),
                 "Chest": (10, 0, 0), "Head": (26, 0, 0), "Jaw": (6, 0, 0), **both({"UpperArm": (-14, -10, 0), "Forearm": (-14, 0, 0)})}),
    (1.4, {**GROUND, **KNEEL_TOP, "Spine": (3, 0, 0), "Chest": (3, 0, 0), "Head": (15, 0, 0)}),
    (KNEEL_T, {**GROUND, **KNEEL_TOP}),
]


def kneel(t):
    p = pose_keys(t, KNEEL_KEYS)
    p.update(heart(1.0))
    g = smooth(t, 0.30, KNEEL_HIT)       # el pie gira sobre su punta y se tiende; la rodilla baja hasta el suelo
    for s, sx in (("L", 1.0), ("R", -1.0)):
        plant_hand(p, s, only_up=t < 1.4)
        p["IK_" + s] = (sx * KNEEL_TOE.x * g, KNEEL_TOE.y * g, KNEEL_TOE.z * g + 0.10 * bump(g, 0.0, 1.0))
        p["IKR_" + s] = (KNEEL_FOOT[0] * g, 0.0, 0.0)
    return finish(p)


REMEMBER_T = 3.0
REMEMBER_MID = {**KNEEL, **lids(0.1), "Spine": (3, 0, 0), "Chest": (2, 0, 0), "Head": (2, 0, 0),
                **both({"UpperArm": (-14, -10, 0), "Forearm": (-30, 0, 0), "Hand": (0, 0, 30)}),
                **both({"Fingers": (0, 40, 0), "FingerTips": (0, 40, 0), "Thumb": (0, 10, 0)})}
REMEMBER_END = {**KNEEL_LEGS, **OPEN, **lids(0.0), "Hips.loc": (0.0, 0.10, KNEEL_Z), "Hips": (0, 0, 0), "Spine": (1, 0, 0),
                "Chest": (-1, 0, 0), "Head": (-8, 0, 0),
                **both({"UpperArm": (-34, -10, 0), "Forearm": (-62, 0, 0), "Hand": (-8, 0, 84)})}


def remember(t):
    p = pose_keys(t, [(0.0, KNEEL), (0.5, KNEEL), (1.4, REMEMBER_MID), (2.5, REMEMBER_END), (REMEMBER_T, REMEMBER_END)])
    br = sin(2 * pi * t / 3.0) * smooth(t, 2.0, 3.0)
    p["Chest"] = (p["Chest"][0] - 0.8 * br, 0, 0)
    p.update(heart(1.0 + 0.16 * smooth(t, 0.6, 2.4) + 0.05 * bump(t % 1.0, 0.0, 0.5)))
    for s in ("L", "R"):
        plant_hand(p, s, only_up=True)
    return p


ANIMS = [
    ("Sleep", 4.0, sleep),
    ("Awaken", AWAKEN_T, awaken),
    ("Idle", 4.0, idle),
    ("Walk", WALK_T, walk),
    ("Slam", SLAM_T, slam),
    ("Sweep", SWEEP_T, sweep),
    ("Summon", SUMMON_T, summon),
    ("Charge", CHARGE_T, charge),
    ("Stunned", 2.4, stunned),
    ("Kneel", KNEEL_T, kneel),
    ("Remember", REMEMBER_T, remember),
]


# ─────────────────────────────────── Main ───────────────────────────────────

def build():
    kc.reset_scene()
    mats = make_materials()
    arm = kc.build_armature("Armature", make_bones())
    body = build_body()
    kc.bake_ao([body], dist=0.75, samples=32, strength=0.85, floor=0.28)
    for f, mat in zip(body.faces, body.fmat):          # lo emisivo no lleva sombra horneada
        if mat != "Body":
            for i in f:
                body.ao[i] = 1.0
    objs = {"Nojoch": body.build("Nojoch", mats, arm)}
    kc.bake_actions(arm, ANIMS)
    return arm, objs


def main():
    arm, objs = build()
    kc.export_glb(OUT)
    rep = kc.glb_report(OUT)
    print("== nojoch.glb ==")
    for k, v in rep.items():
        print(" ", k, ":", v)
    me = objs["Nojoch"].data
    print("  vértices (Blender):", len(me.vertices), " altura en reposo: %.3f m" % max(v.co.z for v in me.vertices))


if __name__ == "__main__":
    main()
