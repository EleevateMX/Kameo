"""Genera art/propuestas/nojoch/nojoch.glb — Nojoch Tuunich, el Guardián Dormido.

Uso (desde la raíz del repo):
    .tools/blender-venv/bin/python art/blender/build_nojoch.py

Modelo definitivo del primer jefe (diseño en docs/BOSS.md). Coloso de sillares de caliza
cálida, tallados y encajados con las juntas a la vista: torso ancho, brazos largos y
gruesos, manos enormes de tres dedos y pulgar, piernas cortas y una cabeza ancha, sin
cuello, con un tocado escalonado como la crestería de un templo. Mide 5 m de pie y
3.4 m sentado.

A diferencia de los demás personajes (tubos suaves), aquí casi todo son sillares de
caras planas con las aristas matadas; la oclusión horneada oscurece las juntas. Cada
sillar va pegado a un solo hueso (no hay piel que se doble) y las articulaciones son
piezas: rótulas de piedra oscura en hombros, muñecas, caderas y tobillos, y goznes de
tambor con tapas en codos y rodillas, con los sillares vecinos rebajados para que no se
crucen al doblarse. Los relieves (cenefas, rombos, cabrios, tachones) son geometría
abstracta inventada para este personaje: no son glifos mayas ni escritura.

La cara tiene cejas, párpados y boca móviles. En reposo es triste y algo confusa (cejas
caídas hacia fuera, una más alta que la otra; comisuras bajas). Las animaciones del
cuerpo no llevan pista en «Brow_*» ni «Mouth_*»: la expresión la pone el juego con las
tres poses de un cuadro «Face_Sad», «Face_Pain» y «Face_Serene».

Materiales:
  «Body»      caliza, musgo y raíces: blanco, todo el color va en los vértices.
  «Eye»       ojos hundidos, de jade emisivo.
  «Glyph1»…«Glyph4»  los cuatro glifos del pecho, de izquierda a derecha de quien lo
              mira. Se exportan apagados: piedra tallada oscura, sin emisión.
  «Heart»     corazón de cristal de la espalda, emisivo.
  «Silence»   vetas base del Silencio (brazos, pecho, espalda y cabeza), finas, de
              anchura y color irregulares; emisivas.
  «Silence2»  grietas de la furia: más anchas y ramificadas. Se exportan apagadas, del
              color de la piedra que pisan (algo más oscuro), para que no se noten.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import alux_common as kc  # noqa: E402  (importa bpy antes que mathutils)
import bpy  # noqa: E402
from mathutils import Euler, Matrix, Vector  # noqa: E402
from alux_common import C, WHITE, Loft, MeshBuilder, Rig, both, bump, mixc, mulc, ngon, pose_keys  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(os.environ.get("KAMEO_OUT_DIR") or os.path.join(REPO, "art", "propuestas", "nojoch"), "nojoch.glb")

sin, cos, pi, rad = math.sin, math.cos, math.pi, math.radians

# ───────────────────────────────── Paleta ─────────────────────────────────
# Caliza cálida: crema y arena. Los tonos están ajustados mirando el modelo con el
# renderer de Godot y la luz del juego (art/godot/render_nojoch.gd): el ambiente del
# juego es frío (0.62, 0.76, 0.80) y vuelve verdosa en la sombra cualquier piedra
# amarillenta, y el sol, con el resplandor, quema a blanco los tonos claros. Por eso la
# caliza va más rojiza y más oscura de lo que se esperaría de un «crema» (compárese con
# LIME #dbcca8 del santuario) y casi sin verdín.
HEX = {
    "Caliza": "#ba8f6b",          # arena: tono medio de los sillares
    "CalizaArena": "#aa805e",     # sillares más tostados
    "CalizaCrema": "#d0a781",     # sillares claros, tachones y relieves
    "CalizaOscura": "#8e6a50",    # sillares en sombra, rótulas y goznes
    "CalizaCalida": "#c99565",    # placas talladas: pectoral, ajorcas, banda, espaldar
    "Junta": "#4f3d30",           # fondo de cuencas, boca y juntas
    "Rotura": "#dfbf9c",          # caliza recién partida en los desportillados
    "Tierra": "#7d6248",          # pátina de tierra cerca del suelo
    "Musgo": "#737544",           # musgo seco, discreto
    "MusgoOscuro": "#565a36",
    "MusgoClaro": "#8d8a52",
    "Raiz": "#6a4c33",
    "RaizOscura": "#45301f",
    "Jade": "#2ec4a6",            # corazón y ojos (albedo)
    "JadeLuz": "#59ffe0",         # emisión de los ojos (la de los ojos del alux)
    "JadeVivo": "#3fe8c4",        # emisión del corazón y de los glifos encendidos
    "GlifoApagado": "#5a564b",    # los glifos sin encender: piedra tallada oscura
    "Silencio": "#fa3399",        # = MAGENTA del santuario: emisión de las vetas
    "SilencioNucleo": "#ffc4e6",  # el filo de las vetas, donde más arden
    "SilencioBorde": "#b01c66",   # la falda de las vetas y sus tramos finos
    "SilencioApagado": "#8a7460",  # las vetas base cuando recuerda: cicatrices en la piedra
    "Silencio2Apagado": "#ece4d8",  # multiplica al color de la piedra: grieta apenas más oscura
}
EMISION = {"Eye": 1.2, "Heart": 1.0, "Silence": 1.8}       # tal como se exporta


def make_materials():
    m = kc.make_material
    mats = {
        "Body": m("Body", "#ffffff", 0.92),
        "Eye": m("Eye", HEX["Jade"], 0.3, emission=EMISION["Eye"], emission_color=HEX["JadeLuz"]),
        "Heart": m("Heart", HEX["Jade"], 0.15, emission=EMISION["Heart"], emission_color=HEX["JadeVivo"]),
        # el magenta va en los vértices (núcleo claro, bordes oscuros); la emisión es uniforme
        "Silence": m("Silence", "#ffffff", 0.4, emission=EMISION["Silence"], emission_color=HEX["Silencio"]),
        "Silence2": m("Silence2", HEX["Silencio2Apagado"], 0.9),
    }
    for i in range(1, 5):
        mats["Glyph%d" % i] = m("Glyph%d" % i, HEX["GlifoApagado"], 0.85)
    return mats


def _pal(mat, **cols):
    return {k: (mat, C(v) if isinstance(v, str) else v) for k, v in cols.items()}


PAL = {
    **_pal("Body", Stone=HEX["Caliza"], Deep=HEX["Junta"], Moss=HEX["Musgo"], Root=HEX["Raiz"]),
    **_pal("Eye", Eye=WHITE),
    **_pal("Heart", Heart=WHITE),
    **_pal("Silence", Silence=WHITE),
    **_pal("Silence2", Silence2=WHITE),
    **{"Glyph%d" % i: ("Glyph%d" % i, WHITE) for i in range(1, 5)},
}
S_MID, S_SAND, S_CREAM, S_DARK, S_WARM = (C(HEX[k]) for k in ("Caliza", "CalizaArena", "CalizaCrema", "CalizaOscura",
                                                              "CalizaCalida"))
DEEP, CHIP, EARTH = C(HEX["Junta"]), C(HEX["Rotura"]), C(HEX["Tierra"])
MOSS, MOSS_D, MOSS_L = C(HEX["Musgo"]), C(HEX["MusgoOscuro"]), C(HEX["MusgoClaro"])
ROOT, ROOT_D = C(HEX["Raiz"]), C(HEX["RaizOscura"])
V_CORE, V_EDGE, V_MID = C(HEX["SilencioNucleo"]), C(HEX["SilencioBorde"]), C(HEX["Silencio"])


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
PALM_Z, FINGER_Z, TIP_Z = (0.74, 1.11), (0.49, 0.72), (0.24, 0.47)
HZ = 3.30                                    # base de la cabeza (mentón); la cabeza y su crestería miden 1.70 m
HEAD_PIVOT = Vector((0.0, 0.12, 3.34))
HEART_C = Vector((0.0, 0.82, 3.54))          # centro del cristal, en lo alto de la espalda
GLYPH_Z, GLYPH_DX, GLYPH_S = 2.91, 0.48, 0.19   # fila de glifos: altura, separación y media anchura

# ── cara ──
BROW_PIVOT = Vector((0.16, -0.60, HZ + 0.715))   # gozne de cada ceja, en su extremo interior
MOUTH_PIVOT = Vector((0.10, -0.672, HZ + 0.27))  # gozne de cada comisura, junto al centro de la boca
LID_TRAVEL = 0.20                                # lo que bajan los párpados para cerrarse
# Expresiones: caída de la ceja hacia fuera (grados) y su alzada (m), por lado; caída de
# la comisura (grados; negativo = sube), cuánto se estira (m); párpados (0 abiertos, 1
# cerrados) y mandíbula (grados). La malla se construye en la primera: triste y confusa.
FACES = {
    "Face_Sad": dict(brow={"L": (17.0, 0.085), "R": (12.0, 0.055)}, mouth={"L": (21.0, 0.0), "R": (16.0, 0.0)},
                     lids=0.26, jaw=0.0),
    "Face_Pain": dict(brow={"L": (25.0, 0.02), "R": (25.0, 0.02)}, mouth={"L": (13.0, 0.035), "R": (13.0, 0.035)},
                      lids=0.78, jaw=2.5),
    "Face_Serene": dict(brow={"L": (4.0, 0.045), "R": (4.0, 0.045)}, mouth={"L": (-12.0, 0.0), "R": (-12.0, 0.0)},
                        lids=0.46, jaw=0.0),
}
REST_FACE = FACES["Face_Sad"]
FACE_BONES = ("Brow_L", "Brow_R", "Mouth_L", "Mouth_R", "Lids", "Jaw")
FACE_ONLY = ("Brow_L", "Brow_R", "Mouth_L", "Mouth_R")       # sin pista en las animaciones del cuerpo


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
    # huesos de la cara, al final para no mover los índices de los que ya había
    for s, sfx in ((1, "_L"), (-1, "_R")):
        b += [
            ("Brow" + sfx, mx(BROW_PIVOT + Vector((0, 0, REST_FACE["brow"]["LR"[s < 0]][1])), s),
             mx(BROW_PIVOT + Vector((0.42, 0, REST_FACE["brow"]["LR"[s < 0]][1])), s), "Head"),
            ("Mouth" + sfx, mx(MOUTH_PIVOT, s), mx(MOUTH_PIVOT + Vector((0.24, 0, 0)), s), "Head"),
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


def face_idx(mb, ids, key, cols=None, inside=None, out=None, occ=True):
    """Como add_face, pero con vértices ya creados (compartidos: arista suave)."""
    ids = list(ids)
    pts = [mb.verts[i] for i in ids]
    ref = (sum(pts, Vector()) / len(pts) - Vector(inside)) if inside is not None else Vector(out)
    if _newell(pts).dot(ref) < 0.0:
        ids.reverse()
        cols = cols[::-1] if cols else None
    mb.face(ids, key, cols, occ)


class Blk:
    """Sillar: caja con conicidad (`taper`: escala de la cara de arriba), inclinación
    (`lean`: desplazamiento de la cara de arriba), deformación opcional (`warp(l, p) -> p`,
    con l en coordenadas locales: para rebajar una arista) y giro alrededor de `pivot`.
    Coordenadas locales en [-1, 1]³."""

    def __init__(self, lo, hi, taper=(1.0, 1.0), lean=(0.0, 0.0), rot=None, pivot=None, warp=None):
        lo, hi = Vector(lo), Vector(hi)
        self.c, self.h = (lo + hi) * 0.5, (hi - lo) * 0.5
        self.taper, self.lean, self.rot, self.warp = taper, lean, rot, warp
        self.pivot = Vector(pivot) if pivot is not None else self.c
        self.tone = None

    def P(self, l):
        f = 0.5 * (l[2] + 1.0)
        p = self.c + Vector((l[0] * self.h.x * (1.0 + (self.taper[0] - 1.0) * f) + self.lean[0] * f,
                             l[1] * self.h.y * (1.0 + (self.taper[1] - 1.0) * f) + self.lean[1] * f,
                             l[2] * self.h.z))
        if self.warp is not None:
            p = self.warp(l, p)
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

    def frame(self, face, u=0.0, v=0.0, off=0.0):
        """Origen, ejes (a lo largo de u y de v) y normal sobre una cara: para tallar relieves."""
        o, n = self.at(face, u, v, off)
        ex = (self.at(face, u + 0.01, v)[0] - self.at(face, u - 0.01, v)[0]).normalized()
        ey = n.cross(ex).normalized()
        if ey.dot(self.at(face, u, v + 0.01)[0] - self.at(face, u, v - 0.01)[0]) < 0.0:
            ey = -ey
        return o, ex, ey, n


def slope(zs, ys, d):
    """Deformación para Blk: rebaja en bisel la arista de la cara de arriba (zs = +1) o de
    abajo (zs = -1) del lado de delante (ys = -1) o de atrás (ys = +1), d metros. Es lo
    que deja sitio para doblar codos y rodillas."""
    def warp(l, p):
        if l[2] * zs > 0.0:
            return p - Vector((0.0, 0.0, zs * d * 0.5 * (l[1] * ys + 1.0)))
        return p
    return warp


def stone_tone(rng):
    base = mixc(S_MID, S_SAND, rng.random())
    r = rng.random()
    if r < 0.28:
        base = mixc(base, S_CREAM, 0.8)
    elif r < 0.46:
        base = mixc(base, S_DARK, 0.6)
    elif r < 0.60:
        base = mixc(base, S_WARM, 0.5)
    return base


def add_block(mb, lo, hi, w, rng, tone=None, bevel=0.035, taper=(1.0, 1.0), lean=(0.0, 0.0), rot=None,
              pivot=None, chips=None, skip="", moss=0.0, key="Stone", flat=False, warp=None):
    """Sillar de caras planas con las aristas matadas (44 triángulos; 12 si bevel = 0).
    Las seis caras llevan vértices propios (planas); los chaflanes de aristas y esquinas
    comparten los suyos, así se ven redondeados y la pieza cuesta la mitad de vértices.
    `chips`: esquinas desportilladas (índices 0–7: bit 0 = +x, bit 1 = +y, bit 2 = +z);
    None = al azar, () = ninguna. `moss`: musgo en la cara de arriba y lo alto de los
    costados. `skip`: caras principales que no se generan (p. ej. "z-y+")."""
    blk = Blk(lo, hi, taper, lean, rot, pivot, warp)
    base = tone if tone is not None else stone_tone(rng)
    blk.tone = base
    if chips is None:
        chips = (4 + rng.randrange(4),) if (bevel > 0.0 and rng.random() < 0.3) else ()
    centre = blk.P((0.0, 0.0, 0.0))
    mvar = mixc(MOSS, MOSS_D if rng.random() < 0.5 else MOSS_L, rng.random() * 0.6)

    def shade(l, kind):
        p = blk.P(l)
        f = 0.5 * (l[2] + 1.0)
        if flat:
            return p, base
        c = mulc(base, 0.88 + 0.14 * f)
        if kind == "top":
            c = mulc(base, 1.05)
        elif kind == "bot":
            c = mulc(base, 0.74)
        elif kind == "bevel":
            c = mulc(c, 1.08)
        elif kind == "chip":
            c = mixc(c, CHIP, 0.8)
        if moss > 0.0 and kind != "bot":
            c = mixc(c, mvar, moss * (1.0 if kind == "top" else 0.7 * f * f))
        c = mixc(c, EARTH, 0.26 * (1.0 - smooth(p.z, 0.05, 1.2)))
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
    shared = {}                     # vértices compartidos de los chaflanes

    def bv(i, k):
        if (i, k) not in shared:
            p, c = shade(corner[i][k], "bevel")
            shared[(i, k)] = (mb.vert(p, w), c)
        return shared[(i, k)]

    for ax in range(3):             # aristas paralelas al eje `ax`
        a, b = ((1, 2), (0, 2), (0, 1))[ax]
        for sa in (0, 1):
            for sb in (0, 1):
                i0 = (sa << a) | (sb << b)
                i1 = i0 | (1 << ax)
                q = [bv(i0, a), bv(i0, b), bv(i1, b), bv(i1, a)]
                face_idx(mb, [v for v, _c in q], key, [c for _v, c in q], inside=centre)
    for i in range(8):
        if i in chipped:
            emit(corner[i], "chip")
        else:
            q = [bv(i, k) for k in range(3)]
            face_idx(mb, [v for v, _c in q], key, [c for _v, c in q], inside=centre)
    return blk


def add_prism(mb, o, ex, ey, n, poly, depth, key, w, col=None, occ=True, side_k=0.8, back=False, inset=0.0):
    """Relieve: polígono convexo `poly` (metros, en el plano de origen `o` y ejes ex, ey)
    que sobresale `depth` según la normal `n`. La tapa es plana, con vértices propios; los
    costados comparten los suyos (canto suave) y, con `inset`, caen en bisel. El fondo,
    solo con `back` (cuando la pieza se puede ver por detrás)."""
    o, ex, ey, n = Vector(o), Vector(ex), Vector(ey), Vector(n)
    cx = sum(x for x, _y in poly) / len(poly)
    cy = sum(y for _x, y in poly) / len(poly)
    base = [o + ex * x + ey * y for x, y in poly]
    top = []
    for x, y in poly:
        d = math.hypot(x - cx, y - cy)
        k = max(0.0, 1.0 - inset / d) if d > 1e-6 else 1.0
        top.append(o + ex * (cx + (x - cx) * k) + ey * (cy + (y - cy) * k) + n * depth)
    add_face(mb, top, key, w, [col] * len(top) if col else None, out=n, occ=occ)
    cs = mulc(col, side_k) if col else None
    ct = mulc(col, 0.5 * (1.0 + side_k)) if col else None
    cen = sum(base, Vector()) / len(base)
    ib = [mb.vert(p, w) for p in base]
    it = [mb.vert(p, w) for p in top]
    for i in range(len(poly)):
        j = (i + 1) % len(poly)
        face_idx(mb, [ib[i], ib[j], it[j], it[i]], key, [cs, cs, ct, ct] if col else None, inside=cen, occ=occ)
    if back:
        add_face(mb, base, key, w, [cs] * len(base) if col else None, out=-n, occ=occ)


def add_drum(mb, c, r, hl, w, rng, axis=0, n=10, tone=None, bevel=0.035, cap=0.0):
    """Gozne de tambor: cilindro sobre el eje `axis`, costado suave. Con `cap`, cada
    extremo lleva una tapa: un disco más pequeño que sobresale `cap` metros."""
    c = Vector(c)
    base = tone if tone is not None else stone_tone(rng)
    a, b = ((1, 2), (0, 2), (0, 1))[axis]

    def P(t, rr, ang):
        v = Vector((0.0, 0.0, 0.0))
        v[axis], v[a], v[b] = t, rr * cos(ang), rr * sin(ang)
        return c + v

    def col(p, k=1.0):
        return mixc(mulc(base, k), EARTH, 0.26 * (1.0 - smooth(p.z, 0.05, 1.2)))

    angs = [2.0 * pi * (k + 0.5) / n for k in range(n)]
    rings = [[mb.vert(P(t, r, ang), w) for ang in angs] for t in (-hl + bevel, hl - bevel)]
    for k in range(n):
        k2 = (k + 1) % n
        q = [rings[0][k], rings[0][k2], rings[1][k2], rings[1][k]]
        face_idx(mb, q, "Stone", [col(mb.verts[i], 0.93) for i in q], inside=c)
    for sg in (-1.0, 1.0):
        capv = [P(sg * hl, r - bevel, ang) for ang in angs]
        edge = [P(sg * (hl - bevel), r, ang) for ang in angs]
        add_face(mb, capv, "Stone", w, [col(p, 1.03) for p in capv], inside=c)
        ie = [mb.vert(p, w) for p in edge]
        ic = [mb.vert(p, w) for p in capv]
        for k in range(n):
            k2 = (k + 1) % n
            q = [ie[k], ie[k2], ic[k2], ic[k]]
            face_idx(mb, q, "Stone", [col(mb.verts[i], 1.08) for i in q], inside=c)
        if cap > 0.0:
            nrm = Vector((0.0, 0.0, 0.0))
            nrm[axis] = sg
            e1, e2 = Vector((0.0, 0.0, 0.0)), Vector((0.0, 0.0, 0.0))
            e1[a], e2[b] = 1.0, 1.0
            add_prism(mb, c + nrm * hl, e1, e2, nrm, ngon(6, r * 0.52, phase=pi / 6), cap, "Stone", w,
                      col=mixc(S_WARM, base, 0.3), inset=0.02)


def add_ball(mb, c, r, w, tone=None, segs=8, rings=5):
    """Rótula: esfera de piedra oscura, de facetas suaves."""
    tone = tone if tone is not None else mulc(S_DARK, 0.92)
    c = Vector(c)
    mb.add_sphere(c, r, "Stone", w, segs=segs, rings=rings,
                  col=lambda p, d: mixc(mixc(mulc(tone, 0.78), mulc(tone, 1.12), smooth(d.z, -0.8, 0.9)), EARTH,
                                        0.26 * (1.0 - smooth(p.z, 0.05, 1.2))))


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


def add_moss(mb, c, r, w, rng, flat=0.42):
    """Mata de musgo: media esfera chata y abollada."""
    ph = [rng.uniform(0, 6.28) for _ in range(3)]
    tone = mixc(MOSS, MOSS_D if rng.random() < 0.5 else MOSS_L, rng.uniform(0.2, 0.7))
    mb.add_sphere(c, (r, r * rng.uniform(0.8, 1.15), r * flat), "Moss", w, segs=6, rings=4,
                  deform=lambda d: 1.0 + 0.16 * sin(5.0 * d.x + ph[0]) * sin(4.0 * d.y + ph[1]) + 0.10 * sin(7.0 * d.z + ph[2]),
                  keep=lambda d: d.z > -0.3,
                  col=lambda p, d: mixc(mulc(tone, 0.72), mulc(tone, 1.12), smooth(d.z, -0.2, 0.9)))


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


def add_root(mb, pts, r0, r1, w, segs=4):
    """Raíz: tubo fino que serpentea sobre la piedra."""
    pts = [Vector(p) for p in pts]
    ext = [max(abs((b - a)[k]) for a, b in zip(pts, pts[1:])) for k in range(3)]
    side = [(1, 0, 0), (0, 1, 0), (0, 0, 1)][ext.index(min(ext))]
    n = len(pts)
    rings = [dict(c=p, rx=r0 + (r1 - r0) * i / (n - 1), ry=r0 + (r1 - r0) * i / (n - 1), w=w) for i, p in enumerate(pts)]
    loft = Loft(rings, side=side)
    mb.add_loft(loft, "Root", segs=segs, sub=2, cap0=False, cap1=True, w=w,
                col=lambda p, u, th: mixc(ROOT_D, ROOT, 0.5 + 0.5 * sin(th + 2.0 * u)))


def add_vein(mb, pn, width, w, rng, key="Silence", lift=0.022, tones=None):
    """Veta del Silencio: cresta de dos aguas que sigue la superficie y se afila hacia
    el final. pn = [(punto, normal), ...]. La anchura late a lo largo del recorrido
    (nudos anchos, tramos de hilo) y el color va del núcleo claro a los bordes oscuros:
    así el brillo no es uniforme aunque la emisión del material lo sea. Con `tones`
    (un color de piedra por punto) la cresta se pinta de esa piedra: grieta apagada."""
    k = len(pn)
    rows = []
    ph, fr = rng.uniform(0.0, 6.28), rng.uniform(1.3, 2.1)
    for i, (p, n) in enumerate(pn):
        t = (pn[min(i + 1, k - 1)][0] - pn[max(i - 1, 0)][0]).normalized()
        sd = t.cross(n).normalized()
        beat = 0.5 + 0.5 * sin(fr * i + ph)                      # 0 = hilo, 1 = nudo
        m = (0.42 + 0.58 * beat) if tones is None else (0.7 + 0.3 * beat)
        wd = 0.5 * width * m * (1.0 - 0.78 * i / (k - 1)) * (0.4 if i == 0 else 1.0)
        if tones is None:
            core = mixc(V_MID, V_CORE, 0.25 + 0.75 * beat)
            edge = mixc(V_EDGE, V_MID, 0.5 * beat)
        else:
            core, edge = mulc(tones[i], 0.97), mulc(tones[i], 0.86)
        rows.append(((mb.vert(p + n * 0.004 + sd * wd, w), mb.vert(p + n * lift * (0.6 + 0.4 * m), w),
                      mb.vert(p + n * 0.004 - sd * wd, w)), (edge, core, edge)))
    for i in range(k - 1):
        for a, b in ((0, 1), (1, 2)):
            q = [rows[i][0][a], rows[i][0][b], rows[i + 1][0][b], rows[i + 1][0][a]]
            cc = [rows[i][1][a], rows[i][1][b], rows[i + 1][1][b], rows[i + 1][1][a]]
            pts = [mb.verts[j] for j in q]
            if _newell(pts).dot(pn[i][1]) < 0.0:
                q.reverse()
                cc.reverse()
            mb.face(q, key, cc, False)


def vein_path(B, spec, rng, amp=0.05):
    """Recorrido en zigzag: spec = [(bloque, cara, u, v), ...] → [(punto, normal, tono), ...]."""
    pts = []
    for i, (name, fc, u, v) in enumerate(spec):
        blk = B[name][0]
        if i > 0 and spec[i - 1][0] == name and spec[i - 1][1] == fc:
            u0, v0 = spec[i - 1][2], spec[i - 1][3]
            p1, p2 = blk.at(fc, u0, v0)[0], blk.at(fc, u, v)[0]
            for f, sg in ((0.33, 1.0), (0.66, -1.0)):
                p, n = blk.at(fc, u0 + (u - u0) * f, v0 + (v - v0) * f)
                sd = (p2 - p1).cross(n).normalized()
                pts.append((p + sd * amp * sg * rng.uniform(0.6, 1.3), n, blk.tone))
        pts.append(blk.at(fc, u, v) + (blk.tone,))
    return pts


# ─────────────────────────────────── Relieves ───────────────────────────────────
# Motivos geométricos abstractos, en metros sobre el plano de una cara. Cada uno es una
# lista de polígonos convexos. No copian ningún glifo ni signo real.

def _r(u0, v0, u1, v1):
    return [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]


def m_frame(hw, hh, t):
    """Marco rectangular de grosor t."""
    return [_r(-hw, hh - t, hw, hh), _r(-hw, -hh, hw, -hh + t), _r(-hw, -hh + t, -hw + t, hh - t),
            _r(hw - t, -hh + t, hw, hh - t)]


def m_diamond(rx, ry=None):
    ry = rx if ry is None else ry
    return [[(0.0, -ry), (rx, 0.0), (0.0, ry), (-rx, 0.0)]]


def m_chevron(hw, drop, t, y=0.0):
    """Cabrio: «V» de brazo hw, caída drop y grosor t, con el vértice hacia abajo (drop > 0)."""
    return [[(-hw, y + drop), (-hw, y + drop - t), (0.0, y - t), (0.0, y)],
            [(0.0, y), (0.0, y - t), (hw, y + drop - t), (hw, y + drop)]]


def m_steps(hw, h, n=3, up=True):
    """Almena escalonada: n barras apiladas, cada una más estrecha."""
    out = []
    for k in range(n):
        f = 1.0 - k / n
        y0 = (k * h / n) if up else (-(k + 1) * h / n)
        out.append(_r(-hw * f, y0, hw * f, y0 + h / n))
    return out


def m_row(n, pitch, hw, hh):
    """Cenefa: n tacos en fila."""
    return [_r((k - 0.5 * (n - 1)) * pitch - hw, -hh, (k - 0.5 * (n - 1)) * pitch + hw, hh) for k in range(n)]


def moved(polys, dx, dy):
    return [[(x + dx, y + dy) for x, y in poly] for poly in polys]


# ─────────────────────────────────── Glifos ───────────────────────────────────
# Cuatro signos abstractos, originales, de trazo geométrico (no son escritura maya):
# cada uno es una lista de polígonos convexos en una celda de [-1, 1] × [-1.3, 1.3].

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
        add_prism(mb, c, ex, ey, nrm, ngon(n, r, phase=pi / n), depth, "Stone", w, col=tone, inset=0.02)
        add_prism(mb, Vector(c) + nrm * depth, ex, ey, nrm, ngon(n, r * inner, phase=pi / n), depth * 0.6, "Stone", w,
                  col=mulc(tone, 1.08), inset=0.015)

    def carve(name, face, polys, depth=0.03, tone=None, u=0.0, v=0.0, inset=0.012, off=0.0):
        """Talla un motivo en relieve sobre una cara de un sillar."""
        b, w = B[name]
        o, ex, ey, n = b.frame(face, u, v, off)
        col = tone if tone is not None else mulc(b.tone, 1.12)
        for poly in polys:
            add_prism(mb, o, ex, ey, n, poly, depth, "Stone", w, col=col, inset=inset)

    # ── piernas ──
    for s, sfx in ((1, "_L"), (-1, "_R")):
        wt, wsh, wf = {"Thigh" + sfx: 1}, {"Shin" + sfx: 1}, {"Foot" + sfx: 1}
        ox = "x+" if s > 0 else "x-"
        add_ball(mb, mx(HIP, s), 0.30, {"Hips": 1})                          # rótula de la cadera
        boss(mx((0.82, 0.0, HIP.z), s), s, 0.19, 0.05, wt, S_WARM)           # su tapa, que gira con el muslo
        blk("thigh" + sfx, (0.22, -0.30, 0.98), (0.82, 0.30, 1.27), wt, s, taper=(0.93, 0.9), bevel=0.04,
            warp=slope(-1, 1, 0.15), chips=())
        carve("thigh" + sfx, "y-", m_diamond(0.15, 0.10) + m_row(2, 0.44, 0.035, 0.035), tone=S_WARM)
        carve("thigh" + sfx, ox, m_row(3, 0.16, 0.05, 0.06), tone=S_CREAM, v=0.1)
        add_drum(mb, mx(KNEE, s), 0.235, 0.31, wt, rng, tone=mixc(S_DARK, S_SAND, 0.35), cap=0.035)   # gozne de la rodilla
        blk("kneecap" + sfx, (0.30, -0.44, 0.68), (0.74, -0.24, 0.99), wt, s, taper=(0.72, 1.0), bevel=0.03,
            tone=S_CREAM, chips=())
        boss(mx((0.52, -0.44, 0.83), s), -2, 0.11, 0.03, wt, S_WARM, n=6)
        up_back, down_front = slope(1, 1, 0.13), slope(-1, -1, 0.11)
        blk("shin" + sfx, (0.21, -0.31, 0.45), (0.83, 0.31, 0.69), wsh, s, taper=(0.9, 0.86), bevel=0.04,
            warp=lambda l, p: down_front(l, up_back(l, p)))
        blk("greave" + sfx, (0.33, -0.345, 0.545), (0.71, -0.29, 0.675), wsh, s, bevel=0.02, tone=S_WARM, chips=(),
            skip="y+")
        carve("greave" + sfx, "y-", m_chevron(0.14, 0.05, 0.03, -0.045) + m_chevron(0.14, 0.05, 0.03, 0.015), tone=S_CREAM,
              depth=0.022)
        carve("shin" + sfx, ox, m_row(3, 0.17, 0.045, 0.05), tone=S_CREAM)
        add_ball(mb, mx(ANKLE, s), 0.185, wsh, segs=8, rings=4)              # rótula del tobillo
        blk("anklet" + sfx, (0.17, -0.34, 0.265), (0.87, 0.36, 0.365), wf, s, bevel=0.025, tone=S_WARM, chips=())
        carve("anklet" + sfx, "y-", m_row(4, 0.16, 0.04, 0.025), tone=S_CREAM, depth=0.02)
        blk("foot" + sfx, (0.18, -0.50, 0.0), (0.86, 0.36, 0.28), wf, s, taper=(0.92, 0.86), lean=(0.0, 0.05),
            bevel=0.04, moss=0.12)
        for k, tx in enumerate((0.30, 0.52, 0.74)):
            blk("toe%d%s" % (k, sfx), (tx - 0.10, -0.72, 0.0), (tx + 0.10, -0.46, 0.19), wf, s, taper=(0.85, 0.9),
                bevel=0.03, chips=(4,) if (k == 2 and s > 0) else (), skip="y+")

    # ── pelvis y cinturón ──
    wh = {"Hips": 1}
    blk("pelvis", (-0.25, -0.36, 1.06), (0.25, 0.36, 1.73), wh, chips=(), skip="z+")
    blk("apron", (-0.23, -0.52, 1.10), (0.23, -0.36, 1.73), wh, bevel=0.03, chips=(0,), skip="z+y+")
    blk("apronpl", (-0.15, -0.565, 1.20), (0.15, -0.52, 1.66), wh, bevel=0.015, tone=S_WARM, chips=(), skip="y+")
    carve("apronpl", "y-", m_steps(0.10, 0.15, 3, up=False) + moved(m_diamond(0.05, 0.065), 0.0, -0.13),
          tone=S_CREAM, depth=0.02, v=0.45)
    blk("tail", (-0.23, 0.36, 1.14), (0.23, 0.50, 1.73), wh, bevel=0.03, skip="z+y-", chips=())
    carve("tail", "y+", moved(m_steps(0.15, 0.18, 3, up=False), 0.0, 0.2) + moved(m_diamond(0.06, 0.08), 0.0, -0.1), tone=S_WARM)
    blk("belt", (-0.90, -0.50, 1.71), (0.90, 0.50, SPINE_Z), wh, bevel=0.04, tone=mixc(S_WARM, S_MID, 0.4), chips=())
    for k in range(-3, 4):
        if k:
            x = k * 0.25
            add_prism(mb, (x, -0.50, 1.82), (1, 0, 0), (0, 0, 1), (0, -1, 0), _r(-0.07, -0.06, 0.07, 0.06), 0.035, "Stone",
                      wh, col=S_CREAM, inset=0.012)
            add_prism(mb, (x, 0.50, 1.82), (-1, 0, 0), (0, 0, 1), (0, 1, 0), _r(-0.07, -0.06, 0.07, 0.06), 0.035, "Stone",
                      wh, col=S_CREAM, inset=0.012)
    boss((0.0, -0.50, 1.82), -2, 0.17, 0.06, wh, S_CREAM)
    boss((0.0, 0.50, 1.82), 2, 0.13, 0.05, wh, S_CREAM, n=6)

    # ── abdomen (dos hiladas) ──
    wsp = {"Spine": 1}
    for i, (x0, x1) in enumerate(((-0.74, 0.0), (0.0, 0.74))):
        blk("abdA%d" % i, (x0, -0.45, SPINE_Z), (x1, 0.45, 2.15), wsp, skip="z-")
    for i, (x0, x1) in enumerate(((-0.86, -0.29), (-0.29, 0.29), (0.29, 0.86))):
        blk("abdB%d" % i, (x0, -0.50, 2.15), (x1, 0.50, CHEST_Z), wsp)

    # ── pecho (tres hiladas de sillares a matajunta) ──
    wc = {"Chest": 1}
    for i, (x0, x1) in enumerate(((-1.0, -0.34), (-0.34, 0.34), (0.34, 1.0))):
        blk("chA%d" % i, (x0, -0.56, CHEST_Z), (x1, 0.56, 2.68), wc, chips=())
    for i, (x0, x1) in enumerate(((-1.06, -0.54), (-0.54, 0.0), (0.0, 0.54), (0.54, 1.06))):
        blk("chB%d" % i, (x0, -0.60, 2.68), (x1, 0.60, 2.99), wc, chips=())
    for i, (x0, x1) in enumerate(((-1.10, -0.38), (-0.38, 0.38), (0.38, 1.10))):
        blk("chC%d" % i, (x0, -0.60, 2.99), (x1, 0.60, 3.29), wc, chips=(), moss=0.22 if i != 1 else 0.0)
    # pectoral: la placa que lleva los cuatro glifos, y su cornisa
    plate = blk("plate", (-1.0, -0.71, 2.61), (1.0, -0.59, 3.21), wc, tone=S_WARM, bevel=0.03, chips=(1,), skip="y+")
    blk("collar", (-0.80, -0.69, 3.21), (0.80, -0.52, 3.31), wc, bevel=0.025, tone=S_CREAM, chips=())
    for s, sfx in ((1, "_L"), (-1, "_R")):
        blk("pend" + sfx, (0.30, -0.69, 2.47), (0.52, -0.57, 2.61), wc, s, bevel=0.02, tone=S_WARM, chips=(), skip="z+")
    blk("pendc", (-0.16, -0.70, 2.41), (0.16, -0.57, 2.61), wc, bevel=0.02, tone=S_WARM, chips=(), skip="z+")
    # espaldar: el marco que sube por detrás de la cabeza y guarda el corazón
    for s, sfx in ((1, "_L"), (-1, "_R")):
        blk("rackpost" + sfx, (0.27, 0.62, 3.14), (0.43, 0.86, 3.92), wc, s, bevel=0.025, chips=())
        blk("rackwing" + sfx, (0.43, 0.62, 3.26), (0.82, 0.74, 3.72), wc, s, bevel=0.025, tone=S_WARM, taper=(0.7, 1.0),
            lean=(-0.05, 0.0))
        carve("rackwing" + sfx, "y+", m_chevron(0.10, 0.07, 0.04, 0.02) + m_chevron(0.10, 0.07, 0.04, -0.10), tone=S_CREAM,
              depth=0.02)
    blk("racktop", (-0.50, 0.62, 3.92), (0.50, 0.90, 4.04), wc, bevel=0.03, moss=0.3, chips=(5,))
    blk("racksill", (-0.56, 0.58, 2.98), (0.56, 0.92, 3.14), wc, bevel=0.03, chips=())
    blk("rackback", (-0.27, 0.62, 3.14), (0.27, 0.66, 3.92), wc, bevel=0.0, tone=DEEP, flat=True)
    # losa tallada de la espalda: marco, tres cabrios en la espina y dos cuadros con rombo
    blk("backplate", (-0.80, 0.58, 2.06), (0.80, 0.70, 2.94), wc, bevel=0.035, tone=mixc(S_WARM, S_MID, 0.35),
        chips=(2,), skip="y-")
    carve("backplate", "y+", m_frame(0.72, 0.38, 0.05), tone=S_CREAM)
    for k in range(3):
        carve("backplate", "y+", m_chevron(0.13, 0.09, 0.05, 0.14 - 0.17 * k), tone=S_CREAM, depth=0.035)
    for sx in (-1, 1):
        carve("backplate", "y+", moved(m_frame(0.185, 0.24, 0.045), sx * 0.43, 0.0), tone=mulc(S_WARM, 1.05))
        carve("backplate", "y+", moved(m_diamond(0.075, 0.11), sx * 0.43, 0.0), tone=S_CREAM, depth=0.04)
    # omóplatos: tres listones a cada lado del espaldar
    for i, sx in ((0, -1), (2, 1)):
        o = Vector((sx * 0.83, 0.60, 3.14))
        for poly in (_r(-0.19, 0.06, 0.19, 0.11), _r(-0.15, -0.025, 0.15, 0.025), _r(-0.11, -0.11, 0.11, -0.06)):
            add_prism(mb, o, (-1, 0, 0), (0, 0, 1), (0, 1, 0), poly, 0.03, "Stone", wc, col=S_CREAM, inset=0.012)
    # collarines de los hombros: el asiento de cada rótula en el costado del pecho
    for s in (1, -1):
        boss(mx((1.085, 0.0, SHOULDER.z), s), s, 0.40, 0.07, wc, mixc(S_WARM, S_DARK, 0.3), inner=0.72)

    # ── glifos (apagados: piedra tallada oscura) ──
    for i in range(4):
        gx = (i - 1.5) * GLYPH_DX
        o = Vector((gx, plate.c.y - plate.h.y, GLYPH_Z))
        add_prism(mb, o, (1, 0, 0), (0, 0, 1), (0, -1, 0), _r(-GLYPH_S * 1.18, -GLYPH_S * 1.48, GLYPH_S * 1.18, GLYPH_S * 1.48),
                  0.012, "Stone", wc, col=mulc(S_DARK, 0.5))
        for poly in GLYPHS[i]:
            add_prism(mb, o + Vector((0, -0.012, 0)), (1, 0, 0), (0, 0, 1), (0, -1, 0),
                      [(u * GLYPH_S, v * GLYPH_S) for u, v in poly], 0.03, "Glyph%d" % (i + 1), wc, occ=False, side_k=1.0)

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
        ox = "x+" if s > 0 else "x-"
        add_ball(mb, mx(SHOULDER, s), 0.37, wc)                              # rótula del hombro
        blk("shoulder" + sfx, (1.40, -0.50, 2.80), (2.08, 0.50, 3.54), wu, s, taper=(0.93, 0.9), bevel=0.05, moss=0.3,
            chips=(5,) if s > 0 else (6,))
        blk("shtop" + sfx, (1.50, -0.34, 3.54), (1.96, 0.34, 3.72), wu, s, taper=(0.86, 0.86), bevel=0.04, moss=0.5,
            skip="z-")
        boss(mx((2.08 - 0.02, 0.0, 3.16), s), s, 0.26, 0.06, wu, S_WARM)
        blk("uarm" + sfx, (AX - 0.30, -0.31, 2.46), (AX + 0.30, 0.31, 2.80), wu, s, taper=(1.08, 1.06),
            warp=slope(-1, -1, 0.12), skip="z+")
        carve("uarm" + sfx, ox, m_row(3, 0.17, 0.05, 0.07), tone=S_CREAM, v=0.15)
        add_drum(mb, mx(ELBOW, s), 0.245, 0.33, wu, rng, tone=mixc(S_DARK, S_SAND, 0.35), cap=0.04)    # gozne del codo
        blk("foreA" + sfx, (AX - 0.29, -0.30, 1.62), (AX + 0.29, 0.30, 1.86), wfa, s, taper=(0.9, 0.9),
            warp=slope(1, -1, 0.11), skip="z-")
        blk("foreB" + sfx, (AX - 0.36, -0.37, 1.36), (AX + 0.36, 0.37, 1.62), wfa, s, taper=(0.93, 0.93), bevel=0.04)
        blk("brace" + sfx, (AX - 0.405, -0.415, 1.25), (AX + 0.405, 0.415, 1.36), wfa, s, bevel=0.03, tone=S_WARM, chips=())
        for fc in ("y-", "y+", ox):
            carve("brace" + sfx, fc, m_row(4, 0.18, 0.045, 0.03), tone=S_CREAM, depth=0.02)
        # brazal: la losa tallada del canto de fuera, con tres cabrios
        blk("forepl" + sfx, (AX + 0.27, -0.25, 1.40), (AX + 0.43, 0.25, 1.83), wfa, s, bevel=0.02, tone=S_WARM, chips=(),
            skip="x-")
        for k in range(3):
            carve("forepl" + sfx, ox, m_chevron(0.16, 0.08, 0.045, 0.10 - 0.135 * k), tone=S_CREAM, depth=0.025)
        carve("foreB" + sfx, "y-", m_frame(0.24, 0.09, 0.03) + m_diamond(0.06, 0.04), tone=S_WARM, depth=0.022)
        carve("foreB" + sfx, "y+", [_r(-0.24, 0.03, 0.24, 0.075), _r(-0.24, -0.075, 0.24, -0.03)], tone=S_WARM, depth=0.022)
        add_ball(mb, mx(WRIST, s), 0.20, wfa, segs=8, rings=4)               # rótula de la muñeca
        blk("palm" + sfx, (AX - 0.17, -0.42, PALM_Z[0]), (AX + 0.17, 0.42, PALM_Z[1]), wha, s, bevel=0.04, chips=())
        blk("handpl" + sfx, (AX + 0.16, -0.33, 0.80), (AX + 0.215, 0.33, 1.05), wha, s, bevel=0.015, tone=S_WARM, chips=(),
            skip="x-")
        carve("handpl" + sfx, ox, m_row(3, 0.2, 0.045, 0.045), tone=S_CREAM, depth=0.02)
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
    blk("skullB", (-0.68, -0.46, HZ + 0.42), (0.68, 0.56, HZ + 0.78), wk, chips=(), skip="z+z-")
    blk("socket", (-0.66, -0.49, HZ + 0.42), (0.66, -0.45, HZ + 0.68), wk, bevel=0.0, tone=DEEP, flat=True, skip="y+")
    blk("mouth", (-0.50, -0.54, HZ + 0.02), (0.50, -0.45, HZ + 0.30), wk, bevel=0.0, tone=mulc(DEEP, 0.8), flat=True,
        skip="y+")
    # frente: el fondo sobre el que giran las cejas
    blk("forehead", (-0.70, -0.535, HZ + 0.64), (0.70, -0.44, HZ + 0.78), wk, bevel=0.02, chips=(), skip="y+z+")
    # mandíbula: la losa del mentón y sus dos quijadas, que abrazan el morro
    blk("jaw", (-0.67, -0.685, HZ + 0.0), (0.67, -0.08, HZ + 0.125), wj, taper=(0.97, 0.98), bevel=0.04, chips=())
    blk("chin", (-0.22, -0.715, HZ + 0.02), (0.22, -0.685, HZ + 0.105), wj, bevel=0.012, tone=S_WARM, chips=(), skip="y+")
    for s, sfx in ((1, "_L"), (-1, "_R")):
        blk("jawside" + sfx, (0.43, -0.645, HZ + 0.115), (0.675, -0.10, HZ + 0.275), wj, s, bevel=0.03, chips=(), skip="z-")
    # morro: la losa donde va tallada la boca
    blk("muzzle", (-0.42, -0.66, HZ + 0.13), (0.42, -0.36, HZ + 0.375), wk, bevel=0.03, tone=mixc(S_CREAM, S_MID, 0.3),
        chips=())
    # boca: una ranura oscura con su labio; el tramo central es fijo y cada comisura gira
    mo = Vector((0.0, -0.66, HZ + 0.27))
    add_prism(mb, mo, (1, 0, 0), (0, 0, 1), (0, -1, 0), _r(-0.105, -0.026, 0.105, 0.026), 0.012, "Stone", wk,
              col=mulc(DEEP, 0.75))
    add_prism(mb, mo, (1, 0, 0), (0, 0, 1), (0, -1, 0), _r(-0.115, -0.07, 0.115, -0.026), 0.03, "Stone", wk,
              col=S_CREAM, inset=0.012)
    for s, sfx in ((1, "_L"), (-1, "_R")):
        ang = REST_FACE["mouth"]["LR"[s < 0]][0]
        rm = Matrix.Rotation(rad(ang * s), 3, "Y")
        o = mx(MOUTH_PIVOT, s) + Vector((0.0, 0.012, 0.0))
        ex, ey = rm @ Vector((s, 0, 0)), rm @ Vector((0, 0, 1))
        wm = {"Mouth" + sfx: 1}
        add_prism(mb, o, ex, ey, (0, -1, 0), [(-0.012, -0.026), (0.27, -0.012), (0.27, 0.012), (-0.012, 0.026)], 0.012,
                  "Stone", wm, col=mulc(DEEP, 0.75))
        add_prism(mb, o, ex, ey, (0, -1, 0), [(-0.012, -0.07), (0.25, -0.045), (0.27, -0.012), (-0.012, -0.026)], 0.03,
                  "Stone", wm, col=S_CREAM, inset=0.01)
    for s, sfx in ((1, "_L"), (-1, "_R")):
        lado = "LR"[s < 0]
        blk("cheek" + sfx, (0.20, -0.605, HZ + 0.285), (0.70, -0.08, HZ + 0.455), wk, s, bevel=0.04, chips=(),
            taper=(0.96, 0.97))
        # párpado: baja con «Lids»; su borde cae hacia fuera
        blk("lid" + sfx, (0.17, -0.547, HZ + 0.615), (0.67, -0.505, HZ + 0.82), wl, s, bevel=0.0, tone=mixc(S_MID, S_CREAM, 0.4),
            skip="y+z+", warp=(lambda l, p, s=s: p + Vector((0.0, 0.0, 0.035 * (1.0 - 0.5 * (l[0] * s + 1.0))))
                               if l[2] < 0.0 else p))
        # ceja: un sillar que gira sobre su extremo interior; en reposo cae hacia fuera
        tilt, lift = REST_FACE["brow"][lado]
        rb = Matrix.Rotation(rad(tilt), 3, "Y")
        dz = Vector((0.0, 0.0, lift))
        blk("brow" + sfx, Vector((0.105, -0.70, HZ + 0.665)) + dz, Vector((0.72, -0.50, HZ + 0.775)) + dz, {"Brow" + sfx: 1}, s, bevel=0.035, chips=(), rot=rb, pivot=BROW_PIVOT + dz, tone=mixc(S_MID, S_CREAM, 0.25),
            warp=(lambda l, p, s=s: p + Vector((0.0, 0.0, (0.022 if l[2] < 0.0 else -0.022) * 0.5 * (l[0] * s + 1.0)))))
        blk("flare" + sfx, (0.68, -0.30, HZ + 0.18), (0.97, 0.25, HZ + 0.70), wk, s, bevel=0.04)
        boss(mx((0.97, -0.02, HZ + 0.44), s), s, 0.18, 0.06, wk, S_WARM)
        blk("drop" + sfx, (0.74, -0.16, HZ + 0.0), (0.93, 0.11, HZ + 0.18), wk, s, bevel=0.03, taper=(1.0, 1.25), chips=())
        # ojos: almendras de jade al fondo de la cuenca, con el rabillo algo caído
        add_prism(mb, mx((0.42, -0.49, HZ + 0.545), s), (s, 0, 0), (0, 0, 1), (0, -1, 0),
                  [(-0.235, 0.014), (-0.13, 0.096), (0.10, 0.096), (0.235, -0.03), (0.12, -0.094), (-0.13, -0.086)],
                  0.02, "Eye", wk, occ=False, side_k=1.0)
    blk("nose", (-0.15, -0.80, HZ + 0.365), (0.15, -0.53, HZ + 0.70), wk, taper=(0.6, 0.5), lean=(0.0, 0.10),
        bevel=0.035, chips=())
    blk("band", (-0.78, -0.635, HZ + 0.77), (0.78, 0.61, HZ + 0.88), wk, bevel=0.03, tone=S_WARM, chips=(), skip="z+")
    for k in range(-2, 3):
        add_prism(mb, (k * 0.29, -0.635, HZ + 0.825), (1, 0, 0), (0, 0, 1), (0, -1, 0),
                  ngon(4, 0.062 if k else 0.078, phase=0.0 if k else pi / 4), 0.04, "Stone", wk, col=S_CREAM, inset=0.012)
    # nuca: una cenefa de almenas bajo la banda
    for k in range(-2, 3):
        add_prism(mb, (k * 0.25, 0.56, HZ + 0.60), (-1, 0, 0), (0, 0, 1), (0, 1, 0), _r(-0.08, -0.07, 0.08, 0.07), 0.03,
                  "Stone", wk, col=S_WARM, inset=0.012)
    # crestería: cornisas y pilares calados, cada vez más estrechos; le falta un pilar
    blk("t1", (-1.03, -0.56, HZ + 0.88), (1.03, 0.56, HZ + 1.00), wk, bevel=0.04, moss=0.3, chips=(4,))
    for k, cx in enumerate((-0.74, -0.37, 0.0, 0.37, 0.74)):
        broken = (k == 4)
        blk("t2_%d" % k, (cx - 0.135, -0.38, HZ + 1.00), (cx + 0.135, 0.38, HZ + (1.09 if broken else 1.22)), wk, bevel=0.03,
            chips=(4, 7) if broken else None, taper=(0.8, 0.8) if broken else (1.0, 1.0), skip="z-" if broken else "z-z+")
    blk("t3", (-0.88, -0.45, HZ + 1.22), (0.56, 0.45, HZ + 1.31), wk, bevel=0.03, moss=0.35, chips=(5, 7))
    for k, cx in enumerate((-0.46, 0.0, 0.46)):
        blk("t4_%d" % k, (cx - 0.145, -0.31, HZ + 1.31), (cx + 0.145, 0.31, HZ + 1.49), wk, bevel=0.03, skip="z-z+")
    blk("t5", (-0.64, -0.37, HZ + 1.49), (0.64, 0.37, HZ + 1.57), wk, bevel=0.025, moss=0.3, chips=())
    blk("t6", (-0.26, -0.26, HZ + 1.57), (0.26, 0.26, HZ + 1.70), wk, bevel=0.03, moss=0.2, chips=(), taper=(0.8, 0.8),
        skip="z-")
    # placa escalonada al frente de la crestería
    for k, (hw, z0, z1) in enumerate(((0.32, 0.97, 1.09), (0.21, 1.09, 1.20), (0.11, 1.20, 1.30))):
        add_prism(mb, (0.0, -0.38, HZ), (1, 0, 0), (0, 0, 1), (0, -1, 0), _r(-hw, z0, hw, z1), 0.08, "Stone", wk, col=S_WARM,
                  back=True)

    # ── musgo (poco: unas matas en lo alto) ──
    def moss_on(name, u, v, r, flat=0.42):
        b, w = B[name]
        add_moss(mb, b.at("z+", u, v)[0] - Vector((0, 0, r * 0.12)), r, w, rng, flat)

    for name, u, v, r in (("shtop_L", -0.2, 0.2, 0.20), ("shoulder_L", 0.72, 0.55, 0.14), ("shtop_R", 0.1, -0.2, 0.17),
                          ("shoulder_R", -0.7, -0.5, 0.15), ("t1", -0.82, 0.1, 0.14), ("t3", -0.7, 0.0, 0.10),
                          ("racktop", 0.4, 0.2, 0.11), ("t2_4", 0.0, 0.0, 0.10)):
        moss_on(name, u, v, r)

    def tufts(name, face, us, w_len, out):
        b, w = B[name]
        for u in us:
            p = b.at(face, u, 0.93)[0]
            add_tuft(mb, p, w_len * rng.uniform(0.6, 1.3), w, rng, out)

    tufts("t1", "y-", (-0.9, -0.7, 0.85), 0.13, (0, -1, 0))
    tufts("t1", "y+", (-0.8, 0.5), 0.15, (0, 1, 0))
    tufts("racktop", "y+", (-0.6, 0.7), 0.15, (0, 1, 0))

    # ── raíces ──
    def on(name, face, u, v, off=0.03):
        return B[name][0].at(face, u, v, off)[0]

    wuL = {"UpperArm_L": 1}
    add_root(mb, [on("shtop_L", "z+", -0.5, 0.5), on("shtop_L", "z+", 0.3, -0.2), on("shtop_L", "y-", 0.75, 0.2),
                  on("shoulder_L", "z+", 0.55, -0.85), on("shoulder_L", "y-", 0.5, 0.6), on("shoulder_L", "y-", 0.15, -0.2),
                  on("shoulder_L", "y-", 0.35, -0.9), on("uarm_L", "y-", 0.3, 0.3), on("uarm_L", "y-", -0.1, -0.7)],
             0.055, 0.018, wuL)
    add_root(mb, [on("t3", "z+", -0.6, -0.3), on("t3", "x-", -0.2, 0.0), on("t2_0", "x-", 0.0, 0.2), on("t1", "z+", -0.92, 0.0),
                  on("t1", "x-", 0.1, 0.0), on("band", "x-", 0.2, 0.3), on("flare_R", "z+", -0.2, 0.3),
                  on("flare_R", "x-", 0.4, 0.2), on("flare_R", "x-", 0.6, -0.7)], 0.045, 0.014, wk)
    add_root(mb, [on("t5", "z+", 0.5, 0.4), on("t5", "y+", 0.55, 0.0), on("t4_2", "y+", 0.2, 0.0), on("t3", "z+", 0.45, 0.8),
                  on("t3", "y+", 0.3, 0.0), on("t2_3", "y+", 0.2, 0.2), on("t1", "z+", 0.3, 0.9), on("t1", "y+", 0.25, 0.0),
                  on("band", "y+", 0.3, 0.2), on("skullB", "y+", 0.45, -0.3)], 0.04, 0.012, wk)
    add_root(mb, [on("chC2", "z+", 0.5, 0.2), on("chC2", "z+", 0.62, 0.9), on("chC2", "y+", 0.72, 0.3),
                  on("chC2", "y+", 0.88, -0.6), on("chB3", "y+", 0.78, 0.3), on("chB3", "y+", 0.9, -0.7),
                  on("chA2", "y+", 0.72, 0.2), on("chA2", "y+", 0.85, -0.85)], 0.05, 0.015, wc)

    # ── vetas base del Silencio: finas, de anchura irregular ──
    vr = random.Random(77)

    def vein(width, spec, amp=0.05):
        path = vein_path(B, spec, vr, amp)
        add_vein(mb, [(p, n) for p, n, _t in path], width * 0.62, B[spec[0][0]][1], vr)

    for s, sfx in ((1, "_L"), (-1, "_R")):
        ox = "x+" if s > 0 else "x-"
        # del hombro al codo, por fuera y por delante
        vein(0.12, [("shoulder" + sfx, "z+", 0.2 * s, 0.5), ("shoulder" + sfx, "z+", 0.95 * s, -0.1),
                    ("shoulder" + sfx, ox, -0.15, 0.95), ("shoulder" + sfx, ox, 0.45, -0.1), ("shoulder" + sfx, ox, 0.1, -0.95),
                    ("uarm" + sfx, ox, 0.2, 0.9), ("uarm" + sfx, ox, -0.35, -0.6)])
        vein(0.07, [("shoulder" + sfx, ox, 0.45, -0.1), ("shoulder" + sfx, ox, 0.85, -0.6)])
        vein(0.10, [("shoulder" + sfx, "y-", 0.75 * s, 0.9), ("shoulder" + sfx, "y-", 0.1 * s, 0.1),
                    ("shoulder" + sfx, "y-", 0.4 * s, -0.95), ("uarm" + sfx, "y-", 0.3 * s, 0.9), ("uarm" + sfx, "y-", -0.3 * s, -0.5)])
        vein(0.06, [("shoulder" + sfx, "y-", 0.1 * s, 0.1), ("shoulder" + sfx, "y-", -0.55 * s, -0.35)])
        # antebrazo y dorso de la mano
        vein(0.10, [("foreA" + sfx, "y-", -0.5 * s, 0.6), ("foreA" + sfx, "y-", 0.35 * s, -0.9),
                    ("foreB" + sfx, "y-", 0.75 * s, 0.9), ("foreB" + sfx, "y-", 0.85 * s, -0.9)])
        vein(0.09, [("foreA" + sfx, "y+", 0.4 * s, 0.9), ("foreA" + sfx, "y+", -0.3 * s, -0.9),
                    ("foreB" + sfx, "y+", -0.75 * s, 0.9), ("foreB" + sfx, "y+", -0.8 * s, -0.9)])
        vein(0.08, [("palm" + sfx, "y-", -0.3 * s, 0.9), ("palm" + sfx, "y-", 0.35 * s, -0.8)], amp=0.03)
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
    # espalda: bajan por los costados de la losa tallada, hacia el corazón
    vein(0.11, [("chC2", "y+", 0.95, 0.7), ("chC2", "y+", 0.62, -0.9), ("chB3", "y+", 0.75, 0.9), ("chB3", "y+", 0.3, -0.9),
                ("chA2", "y+", 0.72, 0.9), ("chA2", "y+", 0.5, -0.2)])
    vein(0.11, [("chC0", "y+", -0.92, 0.5), ("chC0", "y+", -0.6, -0.9), ("chB0", "y+", -0.7, 0.9), ("chB0", "y+", -0.25, -0.9),
                ("chA0", "y+", -0.75, 0.9), ("chA0", "y+", -0.55, -0.4)])
    vein(0.09, [("abdB1", "y+", -0.5, -0.9), ("abdB1", "y+", 0.3, 0.2), ("abdB1", "y+", -0.1, 0.9)])
    vein(0.08, [("racksill", "y+", -0.7, 0.9), ("racksill", "y+", -0.3, -0.9), ("backplate", "z+", -0.3, 0.0),
                ("backplate", "y+", -0.33, 0.96)], amp=0.02)
    # cabeza: de la crestería a la sien y por la mejilla
    vein(0.09, [("t1", "y-", -0.42, 0.9), ("t1", "y-", -0.5, -0.9), ("band", "y-", -0.62, 0.9), ("band", "y-", -0.52, -0.9)])
    vein(0.08, [("cheek_R", "y-", 0.6, 0.95), ("cheek_R", "y-", -0.1, 0.0), ("cheek_R", "y-", 0.5, -0.95)], amp=0.03)
    vein(0.08, [("t3", "y-", 0.1, 0.9), ("t3", "y-", 0.3, -0.9), ("t2_3", "y-", -0.3, 0.9), ("t2_3", "y-", 0.4, -0.9),
                ("t1", "y-", 0.5, 0.9), ("t1", "y-", 0.62, -0.9)], amp=0.02)
    vein(0.09, [("band", "x+", -0.2, 0.9), ("band", "x+", 0.1, -0.9), ("skullB", "x+", 0.3, 0.9), ("skullB", "x+", 0.75, -0.6)])
    vein(0.08, [("jaw", "y-", 0.75, 0.9), ("jaw", "y-", 0.6, -0.8)], amp=0.015)

    # ── grietas de la furia («Silence2»): más anchas, con ramas; apagadas son piedra ──
    fr = random.Random(4242)

    def crack(width, spec, amp=0.07, ramas=2):
        path = vein_path(B, spec, fr, amp)
        w = B[spec[0][0]][1]
        add_vein(mb, [(p, n) for p, n, _t in path], width, w, fr, key="Silence2", lift=0.016, tones=[t for _p, _n, t in path])
        # ramas: salen de los tramos interiores de una misma cara
        cand = [i for i in range(1, len(spec)) if spec[i][0] == spec[i - 1][0] and spec[i][1] == spec[i - 1][1]]
        fr.shuffle(cand)
        for i in cand[:ramas]:
            name, fc, u1, v1 = spec[i]
            _n, _f, u0, v0 = spec[i - 1]
            f = fr.uniform(0.35, 0.65)
            um, vm = u0 + (u1 - u0) * f, v0 + (v1 - v0) * f
            du, dv = -(v1 - v0), (u1 - u0)
            k = fr.choice((-1.0, 1.0)) * fr.uniform(0.35, 0.6) / max(1e-6, math.hypot(du, dv))
            ue, ve = max(-0.95, min(0.95, um + du * k)), max(-0.95, min(0.95, vm + dv * k))
            sub = vein_path(B, [(name, fc, um, vm), (name, fc, ue, ve)], fr, amp * 0.5)
            add_vein(mb, [(p, n) for p, n, _t in sub], width * 0.7, w, fr, key="Silence2", lift=0.014,
                     tones=[t for _p, _n, t in sub])

    for s, sfx in ((1, "_L"), (-1, "_R")):
        ox = "x+" if s > 0 else "x-"
        crack(0.19, [("shoulder" + sfx, "y-", -0.8 * s, 0.75), ("shoulder" + sfx, "y-", -0.1 * s, 0.45),
                     ("shoulder" + sfx, "y-", 0.75 * s, -0.25), ("shoulder" + sfx, "y-", 0.9 * s, -0.9)])
        crack(0.19, [("shoulder" + sfx, "y+", 0.8 * s, 0.8), ("shoulder" + sfx, "y+", 0.0, 0.2),
                     ("shoulder" + sfx, "y+", -0.7 * s, -0.4), ("shoulder" + sfx, "y+", -0.3 * s, -0.95)])
        crack(0.16, [("foreB" + sfx, "y-", -0.85 * s, 0.9), ("foreB" + sfx, "y-", -0.5 * s, -0.9)], ramas=1)
        crack(0.16, [("thigh" + sfx, "y-", 0.85 * s, 0.9), ("thigh" + sfx, "y-", 0.6 * s, 0.0), ("thigh" + sfx, "y-", 0.88 * s, -0.9)],
              ramas=1)
        crack(0.15, [("shin" + sfx, ox, -0.7, 0.9), ("shin" + sfx, ox, 0.1, 0.0), ("shin" + sfx, ox, -0.4, -0.9)], ramas=1)
        crack(0.15, [("foot" + sfx, "z+", 0.6 * s, 0.5), ("foot" + sfx, "z+", 0.1 * s, -0.2), ("foot" + sfx, "z+", 0.5 * s, -0.9)],
              ramas=1)
    crack(0.20, [("chB1", "y-", -0.6, -0.95), ("abdB1", "y-", -0.5, 0.9), ("abdB1", "y-", 0.2, 0.2), ("abdB1", "y-", -0.3, -0.9),
                 ("abdA0", "y-", 0.75, 0.9), ("abdA0", "y-", 0.55, -0.6)])
    crack(0.18, [("chA2", "y-", 0.85, 0.9), ("chA2", "y-", 0.75, -0.9), ("abdB2", "y-", 0.8, 0.9), ("abdB2", "y-", 0.55, -0.7)])
    crack(0.18, [("chA0", "y-", -0.9, 0.9), ("chA0", "y-", -0.8, -0.9), ("abdB0", "y-", -0.75, 0.9), ("abdB0", "y-", -0.85, -0.8)])
    crack(0.20, [("backplate", "y+", 0.95, 0.9), ("backplate", "y+", 0.5, 0.3), ("backplate", "y+", 0.85, -0.3),
                 ("backplate", "y+", 0.35, -0.95)], amp=0.05)
    crack(0.20, [("backplate", "y+", -0.2, 0.95), ("backplate", "y+", -0.75, 0.2), ("backplate", "y+", -0.45, -0.5),
                 ("backplate", "y+", -0.9, -0.95)], amp=0.05)
    crack(0.17, [("abdB0", "y+", 0.8, 0.9), ("abdB0", "y+", 0.2, 0.0), ("abdB0", "y+", 0.6, -0.9), ("abdA0", "y+", -0.3, 0.9),
                 ("abdA0", "y+", 0.1, -0.8)])
    crack(0.16, [("skullA", "x-", -0.5, 0.95), ("skullA", "x-", 0.0, 0.2), ("skullA", "x-", -0.6, -0.8)], ramas=1)
    crack(0.16, [("t1", "y-", 0.05, 0.9), ("t1", "y-", 0.2, -0.9), ("band", "y-", 0.3, 0.9), ("band", "y-", 0.22, -0.9)], amp=0.02,
          ramas=0)
    crack(0.15, [("cheek_L", "y-", -0.7, 0.9), ("cheek_L", "y-", 0.1, 0.1), ("cheek_L", "y-", -0.5, -0.9)], amp=0.03, ramas=1)
    crack(0.16, [("skullB", "y+", -0.8, 0.9), ("skullB", "y+", -0.3, 0.0), ("skullA", "y+", -0.6, 0.9), ("skullA", "y+", -0.2, -0.7)])
    return mb


# ──────────────────────────────── Animaciones ────────────────────────────────
# Las piernas van por cinemática inversa con los pseudo-canales "IK_L" / "IK_R"
# (desplazamiento de la punta del pie respecto al reposo) e "IKR_*" (giro del pie en el
# mundo). Sin ellos, la pierna va por cinemática directa (de rodillas). Las manos que se
# apoyan (dormido, al levantarse, golpes) van con `reach`: cinemática inversa del brazo
# hasta un punto fijo del suelo, con un peso que entra y sale suave para que no haya
# saltos al pasar de apoyada a libre.
#
# Ninguna animación del cuerpo toca «Brow_*» ni «Mouth_*»: la expresión es cosa del
# juego (FACES). Sí mueven «Lids» (parpadeo, dormir) y «Jaw».

CONTACT = {"L": TOE, "R": mx(TOE, -1)}
WALK_T, WALK_SPEED, WALK_STANCE = 1.2, 1.7, 0.56     # «Walk» está compuesta para 1.7 m/s (Boss.SPEED)
CHARGE_T, CHARGE_SPEED = 0.8, 12.0                   # «Charge» resbala adrede: el juego la mueve a 12 m/s
PALM_C = Vector((AX, 0.0, 0.92))                     # centro de la palma (para apoyar la mano)
LID0 = 0.30                                          # párpados de las animaciones del cuerpo: entornados


def _euler(m):
    return tuple(math.degrees(a) for a in m.to_euler("XYZ"))


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
    for bone, (z0, z1), hx, hy in (("Hand_", PALM_Z, 0.215, 0.42), ("Fingers_", FINGER_Z, 0.14, 0.41),
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


def arm_ik(p, s, palm, rot):
    """Cinemática inversa del brazo, en el espacio: coloca el centro de la palma en `palm`
    con la mano girada `rot` (grados, ejes del mundo) y el codo hacia atrás y hacia fuera
    del pecho. El gozne del codo (eje X del brazo) queda perpendicular al plano del brazo.
    Si el punto no se alcanza, el brazo se estira hacia él."""
    sx = 1.0 if s == "L" else -1.0
    up, fo, ha = "UpperArm_" + s, "Forearm_" + s, "Hand_" + s
    Dc = RIG.deform(p, "Chest")
    Rc = Dc.to_3x3().normalized()
    Rh = kc._rot(rot)
    S = Dc @ RIG.head[up]
    W = Vector(palm) - Rh @ (mx(PALM_C, sx) - RIG.head[ha])
    r1, r2 = RIG.head[fo] - RIG.head[up], RIG.head[ha] - RIG.head[fo]
    L1, L2 = r1.length, r2.length
    v = W - S
    d = min(max(v.length, abs(L1 - L2) + 1e-3), L1 + L2 - 1e-3)
    wv = v.normalized()
    pole = Rc @ Vector((0.75 * sx, 1.0, 0.0)) + Vector((0.0, 0.0, 0.25))
    pole = (pole - wv * pole.dot(wv)).normalized()
    a = (L1 * L1 - L2 * L2 + d * d) / (2.0 * d)
    E = S + wv * a + pole * math.sqrt(max(0.0, L1 * L1 - a * a))
    hinge = wv.cross(pole).normalized()
    Wc = S + wv * d

    def frame(u, h):
        h = (h - u * h.dot(u)).normalized()
        return Matrix((h, u.cross(h), u)).transposed()

    X = Vector((1.0, 0.0, 0.0))
    Ru = frame((E - S).normalized(), hinge) @ frame(r1.normalized(), X).transposed()
    Rf = frame((Wc - E).normalized(), hinge) @ frame(r2.normalized(), X).transposed()
    p[up] = _euler(Rc.inverted() @ Ru)
    p[fo] = _euler(Ru.inverted() @ Rf)
    p[ha] = _euler(Rf.inverted() @ Rh)
    return p


def lift_hand(p, s, z=0.0, soft=0.05):
    """Si la mano se hunde por debajo de z, la sube: lleva la palma con el brazo entero
    (cinemática inversa) a su mismo sitio, pero más arriba, conservando el giro de la
    mano. La corrección entra poco a poco con la profundidad (`soft` metros), así no da
    saltos de un cuadro al siguiente; a cambio deja hundirse la mano un par de centímetros."""
    pen = z - hand_low(p, s)
    if pen <= 1e-4:
        return p
    sx = 1.0 if s == "L" else -1.0
    names = ["UpperArm_" + s, "Forearm_" + s, "Hand_" + s]
    old = [tuple(p.get(n, (0.0, 0.0, 0.0))) for n in names]
    D = RIG.deform(p, names[2])
    arm_ik(p, s, D @ mx(PALM_C, sx) + Vector((0.0, 0.0, pen + 0.5 * soft)), _euler(D.to_3x3().normalized()))
    w = smooth(pen, 0.0, soft)
    for n, o in zip(names, old):
        q = kc._rot(o).to_quaternion().slerp(kc._rot(p[n]).to_quaternion(), w)
        p[n] = _euler(q.to_matrix())
    return p


def reach(p, s, target, rot=(0.0, 0.0, 0.0), ground=None, w=1.0):
    """Lleva el centro de la palma del lado `s` al punto `target` (cinemática inversa de
    dos huesos, con el codo hacia atrás) y deja la mano con el giro `rot` en el mundo
    (descrito para la izquierda). Con `ground`, sube o baja el punto hasta que lo más bajo
    de la mano quede a esa altura. `w` mezcla el resultado con la pose que ya había."""
    if w <= 0.0:
        return p
    sx = 1.0 if s == "L" else -1.0
    names = ["UpperArm_" + s, "Forearm_" + s, "Hand_" + s]
    old = [tuple(p.get(n, (0.0, 0.0, 0.0))) for n in names]
    r = rot if s == "L" else (rot[0], -rot[1], -rot[2])
    tgt = Vector(target)
    for _ in range(5 if ground is not None else 1):
        arm_ik(p, s, tgt, r)
        if ground is None:
            break
        tgt.z += ground - hand_low(p, s)
    if w < 1.0:                               # mezcla por el camino corto (cuaterniones)
        for n, o in zip(names, old):
            q = kc._rot(o).to_quaternion().slerp(kc._rot(p[n]).to_quaternion(), w)
            p[n] = _euler(q.to_matrix())
    return p


def heart(s):
    return {"HeartBone.scale": (s, s, s)}


def lids(close):
    """Párpados de piedra: 0 = abiertos (bajo la ceja), 1 = cerrados."""
    return {"Lids.loc": (0.0, 0.0, -LID_TRAVEL * close)}


def face_pose(name):
    """Pose de un cuadro de una expresión, relativa al reposo (que es «Face_Sad»)."""
    f, r = FACES[name], REST_FACE
    p = {**lids(f["lids"]), "Jaw": (f["jaw"], 0.0, 0.0)}
    for s, sx in (("L", 1.0), ("R", -1.0)):
        p["Brow_" + s] = (0.0, sx * (f["brow"][s][0] - r["brow"][s][0]), 0.0)
        p["Brow_" + s + ".loc"] = (0.0, 0.0, f["brow"][s][1] - r["brow"][s][1])
        p["Mouth_" + s] = (0.0, sx * (f["mouth"][s][0] - r["mouth"][s][0]), 0.0)
        p["Mouth_" + s + ".loc"] = (sx * (f["mouth"][s][1] - r["mouth"][s][1]), 0.0, 0.0)
    return p


GROUND = {"IK_L": (0, 0, 0), "IK_R": (0, 0, 0)}
RELAX = both({"Fingers": (0, 20, 0), "FingerTips": (0, 24, 0), "Thumb": (0, 6, 0)})
FIST = both({"Fingers": (0, 92, 0), "FingerTips": (0, 86, 0), "Thumb": (10, 30, 0)})
OPEN = both({"Fingers": (0, -6, 0), "FingerTips": (0, 6, 0), "Thumb": (-12, -14, 0)})


def idle_pose(t):
    ph = 2 * pi * t / 4.0
    br = sin(ph)
    blink = bump(t, 2.85, 3.15)
    p = {**GROUND, **RELAX, **lids(LID0 + (1.0 - LID0) * blink), **heart(1.0 + 0.05 * bump(t % 2.0, 0.0, 0.7))}
    p["Hips.loc"] = (0.0, 0.0, -0.03 - 0.012 * br)
    p["Hips"] = (0.5, 0, 0)
    p["Spine"] = (1.5 + 0.9 * br, 0, 0)
    p["Chest"] = (1.5 + 1.1 * br, 0, 1.2 * sin(ph + 1.0) - 1.2 * sin(1.0))
    p["Head"] = (5.0 - 1.6 * br, 0, 3.0 * sin(ph + 0.6) - 3.0 * sin(0.6))
    p.update(both({"UpperArm": (3 + 1.4 * br, -5 - 1.0 * br, 0), "Forearm": (-12 - 1.8 * br, 0, 0)}))
    return p


def idle(t):
    return finish(idle_pose(t))


I0 = idle_pose(0.0)


def _step(f, half, lift, stance, heel=16.0):
    """Trayectoria de un pie: (avance, altura, giro) para la fase f del ciclo. Durante el
    apoyo el pie retrocede a velocidad constante: no patina si el cuerpo avanza a esa."""
    f %= 1.0
    if f < stance:
        return -half + 2.0 * half * f / stance, 0.0, heel * smooth(f / stance, 0.72, 1.0)
    g = (f - stance) / (1.0 - stance)
    e = g * g * (3 - 2 * g)
    return half - 2.0 * half * e, lift * sin(pi * g) ** 1.3, heel * (1.0 - smooth(g, 0.0, 0.45)) - 6.0 * bump(g, 0.5, 1.0)


def walk(t):
    u = t / WALK_T
    half = 0.5 * WALK_SPEED * WALK_T * WALK_STANCE
    p = {**RELAX, **lids(LID0), **heart(1.0)}
    for s, off in (("L", 0.0), ("R", 0.5)):
        y, z, pitch = _step(u + off, half, 0.24, WALK_STANCE)
        p["IK_" + s] = (0.05 if s == "L" else -0.05, y, z)
        p["IKR_" + s] = (pitch, 0, 0)
    c = cos(2 * pi * u)
    sway = cos(2 * pi * (u - 0.22))
    thud = bump(u % 0.5, 0.0, 0.22)                      # el pisotón, justo al plantar cada pie
    p["Hips.loc"] = (0.13 * sway, -0.05, -0.17 - 0.025 * cos(4 * pi * u) - 0.03 * thud)
    p["Hips"] = (4, 2.5 * sway, -9 * c)
    p["Spine"] = (4, -1.5 * sway, 5 * c)
    p["Chest"] = (3 + 1.5 * thud, -2.0 * sway, 9 * c)
    p["Head"] = (3 + 2.5 * thud, 0.5 * sway, -5 * c)
    p.update(side({"UpperArm": (3 + 13 * c, -7, 0), "Forearm": (-32 + 7 * c, 0, 0)}, "L"))
    p.update(side({"UpperArm": (3 - 13 * c, -7, 0), "Forearm": (-32 - 7 * c, 0, 0)}, "R"))
    return finish(p)


def _world(lean, yaw, roll=0.0):
    """Giro en ejes del mundo: primero gira sobre sí (yaw) y después se inclina hacia
    delante (lean) y hacia un lado (roll), se mire adonde se mire."""
    return (Matrix.Rotation(rad(lean), 3, "X") @ Matrix.Rotation(rad(roll), 3, "Y") @ Matrix.Rotation(rad(yaw), 3, "Z"))


def charge(t):
    """Embestida de hombro: se lanza de lado, con el hombro derecho por delante y bajo, el
    antebrazo cruzado como un ariete y las piernas abiertas y clavadas. No da pasos:
    resbala sobre las losas (el juego lo mueve a 12 m/s) y todo él traquetea."""
    u = t / CHARGE_T
    j1, j2 = sin(4 * pi * u), sin(8 * pi * u + 0.7)          # traqueteo: 2 y 4 golpes por ciclo
    p = {**lids(0.5), **heart(1.0), "Jaw": (1.5, 0, 0)}
    p.update(side({"Fingers": (0, 92, 0), "FingerTips": (0, 86, 0), "Thumb": (10, 30, 0)}, "R"))
    p.update(side({"Fingers": (0, 70, 0), "FingerTips": (0, 60, 0), "Thumb": (6, 20, 0)}, "L"))
    # pierna derecha delante, flexionada; la izquierda atrás, empujando sobre la punta
    p["IK_R"] = (-0.20, -0.66 + 0.035 * j1, 0.02 * max(0.0, j2))
    p["IKR_R"] = (0, 0, 14)
    p["IK_L"] = (0.26, 0.92 - 0.04 * j1, 0.025 * max(0.0, -j2))
    p["IKR_L"] = (26 + 3 * j1, 0, 22)
    p["Hips.loc"] = (0.03 * j2, -0.22, -0.43 + 0.03 * j1)
    # el tronco gira sobre sí hasta poner el hombro derecho delante y se vence hacia donde va
    w1 = _world(13 + 1.2 * j1, 26, -3)
    w2 = _world(27 + 1.0 * j2, 42, -6)
    w3 = _world(40 + 1.5 * j2, 58 + 1.5 * j1, -9)
    wh = _world(14 - 1.5 * j2, 10, 0)
    p["Hips"], p["Spine"], p["Chest"] = _euler(w1), _euler(w1.inverted() @ w2), _euler(w2.inverted() @ w3)
    p["Head"] = _euler(w3.inverted() @ wh)
    p.update(side({"UpperArm": (-12 + 2 * j1, -10, -18), "Forearm": (-112 + 3 * j2, 0, 0), "Hand": (0, 0, -8)}, "R"))
    p.update(side({"UpperArm": (52 + 4 * j2, -30, 0), "Forearm": (-30 - 5 * j1, 0, 0)}, "L"))
    return finish(p)


def stunned(t):
    ph = 2 * pi * t / 2.4
    p = {**GROUND, **RELAX, **lids(0.7), **heart(1.0), "Jaw": (6 + 2 * sin(2 * ph), 0, 0)}
    p["Hips.loc"] = (0.10 * sin(ph), -0.05 + 0.07 * cos(ph), -0.14 - 0.02 * sin(2 * ph))
    p["Hips"] = (2 + 3 * cos(ph), 3 * sin(ph), 0)
    p["Spine"] = (7 + 5 * cos(ph + 0.4), 5 * sin(ph + 0.4), 0)
    p["Chest"] = (6 + 4 * cos(ph + 0.8), 4 * sin(ph + 0.8), 3 * sin(ph))
    p["Head"] = (14 + 7 * cos(ph + 1.5), 9 * sin(ph + 1.5), 6 * sin(ph + 0.7))
    p.update(side({"UpperArm": (-4 + 7 * cos(ph + 1.9), -9 - 3 * sin(ph + 1.9), 0), "Forearm": (-26 - 6 * cos(ph + 2.4), 0, 0)}, "L"))
    p.update(side({"UpperArm": (-4 + 7 * cos(ph + 2.3), -9 + 3 * sin(ph + 2.3), 0), "Forearm": (-26 - 6 * cos(ph + 2.8), 0, 0)}, "R"))
    for s in ("L", "R"):
        lift_hand(p, s, 0.04)
    return finish(p)


# ── golpes ──
SLAM_T, SLAM_HIT, SLAM_HOLD = 2.6, 1.45, 1.85    # alza el puño derecho hasta 1.2 s y golpea a 1.45 s
SLAM_SPOT = Vector((-0.50, -3.05, 0.5))          # adonde cae el puño (centro de la palma)
SLAM_ROT = (-52.0, 0.0, 0.0)                     # la mano, en el golpe: nudillos al suelo
_FIST_R = side({"Fingers": (0, 92, 0), "FingerTips": (0, 86, 0), "Thumb": (10, 30, 0)}, "R")
_RELAX_L = side({"Fingers": (0, 20, 0), "FingerTips": (0, 24, 0), "Thumb": (0, 6, 0)}, "L")
SLAM_PREP = {**GROUND, **_FIST_R, **_RELAX_L, **lids(0.3), "Hips.loc": (0.04, 0.04, -0.18), "Hips": (2, 0, -5),
             "Spine": (4, 0, -6), "Chest": (2, 0, -10), "Head": (0, 0, 10),
             **side({"UpperArm": (-70, -22, 0), "Forearm": (-80, 0, 0)}, "R"),
             **side({"UpperArm": (8, -14, 0), "Forearm": (-24, 0, 0)}, "L")}
SLAM_UP = {**GROUND, **_FIST_R, **_RELAX_L, **lids(0.2), "Hips.loc": (0.05, 0.10, -0.09), "Hips": (-4, 0, -8),
           "Spine": (-6, 0, -10), "Chest": (-8, 0, -16), "Head": (-4, 0, 16), "Jaw": (4, 0, 0),
           **side({"UpperArm": (-160, 28, 0), "Forearm": (-34, 0, 0)}, "R"),
           **side({"UpperArm": (16, -24, 0), "Forearm": (-30, 0, 0)}, "L")}
SLAM_DOWN = reach({**GROUND, **_FIST_R, **_RELAX_L, **lids(0.45), "Hips.loc": (0.0, -0.30, -0.32), "Hips": (17, 0, 4),
                   "Spine": (20, 0, 6), "Chest": (20, 0, 10), "Head": (-36, 0, -10), "Jaw": (7, 0, 0),
                   **side({"UpperArm": (38, -20, 0), "Forearm": (-40, 0, 0)}, "L")}, "R", SLAM_SPOT, SLAM_ROT, ground=0.0)


def slam(t):
    p = pose_keys(t, [(0.0, I0), (0.5, SLAM_PREP), (1.2, SLAM_UP), (SLAM_HIT, SLAM_DOWN), (SLAM_HOLD, SLAM_DOWN), (SLAM_T, I0)])
    p.update(heart(1.0))
    if SLAM_HIT <= t <= SLAM_HOLD + 0.2:
        k = bump(t, SLAM_HIT, SLAM_HOLD)
        p["Chest"] = (p["Chest"][0] + 1.5 * k * sin(60 * t), p["Chest"][1], p["Chest"][2])
        # el puño se queda clavado donde cayó, y suelta suave
        reach(p, "R", SLAM_SPOT, SLAM_ROT, ground=0.0, w=1.0 - smooth(t, SLAM_HOLD, SLAM_HOLD + 0.2))
    lift_hand(p, "R")
    lift_hand(p, "L", 0.04)
    return finish(p)


SUMMON_T, SUMMON_HIT, SUMMON_HOLD = 2.6, 1.40, 1.95     # los dos puños golpean el suelo a 1.4 s
SUMMON_SPOT = Vector((1.25, -2.35, 0.5))                # el puño izquierdo; el derecho, reflejado
SUMMON_ROT = (-50.0, 0.0, 0.0)
_WIDE = {"IK_L": (0.14, 0, 0), "IK_R": (-0.14, 0, 0)}
SUMMON_PREP = {**_WIDE, **FIST, **lids(0.3), "Hips.loc": (0, 0.02, -0.22), "Hips": (2, 0, 0), "Spine": (6, 0, 0),
               "Chest": (4, 0, 0), "Head": (0, 0, 0), **both({"UpperArm": (-60, -20, 0), "Forearm": (-85, 0, 0)})}
SUMMON_UP = {**_WIDE, **FIST, **lids(0.2), "Hips.loc": (0.0, 0.12, -0.08), "Hips": (-5, 0, 0), "Spine": (-8, 0, 0),
             "Chest": (-10, 0, 0), "Head": (-8, 0, 0), "Jaw": (5, 0, 0),
             **both({"UpperArm": (-168, 16, 0), "Forearm": (-28, 0, 0)})}
SUMMON_DOWN = {**_WIDE, **FIST, **lids(0.5), "Hips.loc": (0.0, -0.24, -0.32), "Hips": (19, 0, 0), "Spine": (22, 0, 0),
               "Chest": (22, 0, 0), "Head": (-42, 0, 0), "Jaw": (8, 0, 0)}
for _s in ("L", "R"):
    reach(SUMMON_DOWN, _s, mx(SUMMON_SPOT, 1 if _s == "L" else -1), SUMMON_ROT, ground=0.0)


def summon(t):
    p = pose_keys(t, [(0.0, I0), (0.5, SUMMON_PREP), (1.1, SUMMON_UP), (SUMMON_HIT, SUMMON_DOWN), (SUMMON_HOLD, SUMMON_DOWN),
                      (SUMMON_T, I0)])
    p.update(heart(1.0))
    lift = 0.08 * bump(t, 0.05, 0.4) + 0.08 * bump(t, 2.1, 2.55)             # abre y cierra los pies
    k = bump(t, SUMMON_HIT, SUMMON_HOLD)
    p["Chest"] = (p["Chest"][0] + 1.2 * k * sin(55 * t), p["Chest"][1], p["Chest"][2])
    for s, sx in (("L", 1), ("R", -1)):
        p["IK_" + s] = (p["IK_" + s][0], 0.0, lift)
        if SUMMON_HIT <= t <= SUMMON_HOLD + 0.2:
            reach(p, s, mx(SUMMON_SPOT, sx), SUMMON_ROT, ground=0.0, w=1.0 - smooth(t, SUMMON_HOLD, SUMMON_HOLD + 0.2))
        lift_hand(p, s)
    return finish(p)


# Barrido: el brazo derecho recorre un arco a ras de suelo, de su derecha a su izquierda.
SWEEP_T, SWEEP_START, SWEEP_END = 2.2, 0.9, 1.35       # se carga hasta 0.9 s y barre hasta 1.35 s
SWEEP_AZ = (-74.0, 70.0)                               # acimut de la mano al empezar y al acabar (0 = al frente)
SWEEP_R, SWEEP_Z = 2.45, 0.56                          # radio del arco y altura del centro de la palma
_OPEN_R = side({"Fingers": (0, 4, 0), "FingerTips": (0, 10, 0), "Thumb": (-8, -8, 0)}, "R")
_STEP = {"IK_L": (0.12, -0.14, 0), "IK_R": (-0.16, 0.14, 0)}
SWEEP_BACK = {**_STEP, **_OPEN_R, **_RELAX_L, **lids(0.3), "Hips.loc": (-0.12, 0.0, -0.40), "Hips": (19, 0, -20),
              "Spine": (19, 0, -18), "Chest": (19, 0, -24), "Head": (-30, 0, 46),
              **side({"UpperArm": (-58, -34, 12), "Forearm": (-12, 0, 0), "Hand": (0, 0, 60)}, "R"),
              **side({"UpperArm": (34, -24, 0), "Forearm": (-50, 0, 0)}, "L")}
SWEEP_MID = {**_STEP, **_OPEN_R, **_RELAX_L, **lids(0.3), "Hips.loc": (0.0, -0.12, -0.42), "Hips": (21, 0, 2),
             "Spine": (21, 0, 4), "Chest": (21, 0, 8), "Head": (-38, 0, -8),
             **side({"UpperArm": (-62, -20, 0), "Forearm": (-8, 0, 0), "Hand": (0, 0, 60)}, "R"),
             **side({"UpperArm": (56, -30, 0), "Forearm": (-40, 0, 0)}, "L")}
SWEEP_FWD = {**_STEP, **_OPEN_R, **_RELAX_L, **lids(0.3), "Hips.loc": (0.14, -0.06, -0.40), "Hips": (19, 0, 22),
             "Spine": (19, 0, 24), "Chest": (19, 0, 28), "Head": (-30, 0, -44),
             **side({"UpperArm": (-58, -6, -22), "Forearm": (-16, 0, 0), "Hand": (0, 0, 60)}, "R"),
             **side({"UpperArm": (70, -34, 0), "Forearm": (-30, 0, 0)}, "L")}


def sweep_hand(az):
    """Punto y giro de la mano derecha en el acimut `az` del arco (grados; 0 = al frente, + = a su izquierda)."""
    a = rad(az)
    return Vector((SWEEP_R * sin(a), -SWEEP_R * cos(a), SWEEP_Z)), (-82.0, 0.0, -az)


def sweep(t):
    p = pose_keys(t, [(0.0, I0), (0.35, {**I0, **_STEP, "Hips.loc": (-0.04, 0.0, -0.18), "Chest": (4, 0, -8)}),
                      (SWEEP_START, SWEEP_BACK), (0.5 * (SWEEP_START + SWEEP_END), SWEEP_MID), (SWEEP_END, SWEEP_FWD),
                      (1.65, {**SWEEP_FWD, "Hips.loc": (0.14, -0.04, -0.34), "Chest": (15, 0, 31)}),
                      (SWEEP_T, I0)])
    p.update(heart(1.0))
    lift = 0.10 * bump(t, 0.05, 0.35) + 0.10 * bump(t, 1.75, 2.15)          # recoloca los pies al abrir y al cerrar
    for s in ("L", "R"):
        v = p["IK_" + s]
        p["IK_" + s] = (v[0], v[1], lift if s == "R" else 0.6 * lift)
    # la mano sigue el arco: se coloca atrás durante el aviso, barre y se suelta al final
    a0, a1 = SWEEP_AZ
    az = kc.K(t, [(0.45, a0 + 22.0), (SWEEP_START, a0), (SWEEP_END, a1), (1.6, a1 + 8.0), (2.0, a1 + 2.0)])
    if SWEEP_START < t < SWEEP_END:
        f = (t - SWEEP_START) / (SWEEP_END - SWEEP_START)
        az = a0 + (a1 - a0) * (f * f * (3 - 2 * f) * 0.6 + f * 0.4)
    pos, rot = sweep_hand(az)
    w = smooth(t, 0.45, 0.82) * (1.0 - smooth(t, 1.5, 1.9))
    reach(p, "R", pos, rot, w=w)        # `reach` describe los giros para la izquierda y los refleja
    lift_hand(p, "L", 0.04)
    lift_hand(p, "R")
    return finish(p)


# ── sentado, de rodillas ──
SEAT_Z = -1.015                               # la pelvis descansa en el suelo
_SEAT_FEET = {"IK_L": (0.46, 0.06, 0), "IK_R": (-0.46, 0.06, 0)}       # rodillas abiertas
SEAT = {**_SEAT_FEET, **lids(1.0), "Hips.loc": (0.0, 0.80, SEAT_Z), "Hips": (-4, 0, 0), "Spine": (10, 0, 0),
        "Chest": (11, 0, 0), "Head": (39, 0, 0),
        **both({"Fingers": (0, 34, 0), "FingerTips": (0, 38, 0), "Thumb": (0, 10, 0)})}
SEAT_HAND = Vector((1.86, 0.18, 0.5))         # la mano izquierda descansa en el suelo, junto a la cadera
SEAT_ROT = (-28.0, 0.0, 0.0)
KNEEL_Z = -0.47                               # de rodillas: las espinillas descansan en el suelo
KNEEL_LEGS = both({"Thigh": (-6, 0, 0), "Shin": (96, 0, 0), "Foot": (62, 0, 0)})
KNEEL_HAND = Vector((1.95, -0.42, 0.5))       # el puño izquierdo, de rodillas, apoyado en el suelo
KNEEL_ROT = (-18.0, 0.0, 0.0)
KNEEL_TOP = {**FIST, **lids(0.6), "Hips.loc": (0.0, 0.10, KNEEL_Z), "Hips": (2, 0, 0), "Spine": (5, 0, 0),
             "Chest": (6, 0, 0), "Head": (20, 0, 0)}


def kneel_hands(p, w=1.0):
    for s, sx in (("L", 1), ("R", -1)):
        reach(p, s, mx(KNEEL_HAND, sx), KNEEL_ROT, ground=0.0, w=w)
    return p


kneel_hands(KNEEL_TOP)
KNEEL = {**KNEEL_LEGS, **KNEEL_TOP}
# para arrodillarse por cinemática inversa: adónde va a parar la punta del pie, y con qué giro
KNEEL_TOE = RIG.point(KNEEL, "Foot_L", TOE) - TOE
KNEEL_FOOT = (-6.0 + 96.0 + 62.0, 0.0, 0.0)


def seat_hands(p, w=1.0):
    for s, sx in (("L", 1), ("R", -1)):
        reach(p, s, mx(SEAT_HAND, sx), SEAT_ROT, ground=0.0, w=w)
    return p


def sleep(t):
    br = sin(2 * pi * t / 4.0)
    p = dict(SEAT)
    p["Chest"] = (SEAT["Chest"][0] + 0.45 * br, 0, 0)
    p["Head"] = (SEAT["Head"][0] - 0.35 * br, 0, 0)
    p.update(heart(1.0 + 0.04 * bump(t, 0.2, 1.4)))
    return finish(seat_hands(p))


AWAKEN_T, AWAKEN_SIT = 4.0, 1.45              # hasta 1.45 s sigue sentado; a 3.3 s ya está en pie
AWAKEN_FREE = (2.25, 2.7)                     # las manos sueltan el suelo entre estos dos momentos
_A_SIT = {**SEAT, **lids(LID0), "Spine": (5, 0, 0), "Chest": (3, 0, 0), "Head": (-4, 0, 0), "Jaw": (4, 0, 0), **FIST}
_A_PUSH = {**GROUND, **FIST, **lids(LID0), "Hips.loc": (0.0, 0.46, -0.86), "Hips": (16, 0, 0), "Spine": (16, 0, 0),
           "Chest": (12, 0, 0), "Head": (-24, 0, 0), "Jaw": (6, 0, 0)}
_A_RISE = {**GROUND, **FIST, **lids(LID0), "Hips.loc": (0.0, -0.02, -0.50), "Hips": (22, 0, 0), "Spine": (15, 0, 0),
           "Chest": (9, 0, 0), "Head": (-26, 0, 0), "Jaw": (3, 0, 0), **both({"UpperArm": (34, -12, 0), "Forearm": (-16, 0, 0)})}
_A_UP = {**GROUND, **RELAX, **lids(LID0), "Hips.loc": (0.0, 0.0, -0.10), "Hips": (5, 0, 0), "Spine": (4, 0, 0),
         "Chest": (0, 0, 0), "Head": (-4, 0, 0), **both({"UpperArm": (10, -14, 0), "Forearm": (-22, 0, 0)})}
_A_SETTLE = {**GROUND, **RELAX, **lids(LID0), "Hips.loc": (0.0, 0.0, -0.02), "Hips": (-1, 0, 0), "Spine": (-2, 0, 0),
             "Chest": (-4, 0, 0), "Head": (2, 0, 0), **both({"UpperArm": (6, -12, 0), "Forearm": (-16, 0, 0)})}
seat_hands(_A_PUSH)                           # los brazos de esta pose, ya con las manos en su sitio
AWAKEN_KEYS = [(0.0, SEAT), (0.7, SEAT), (AWAKEN_SIT, _A_SIT), (2.1, _A_PUSH), (2.75, _A_RISE), (3.3, _A_UP),
               (3.6, _A_SETTLE), (AWAKEN_T, I0)]


def awaken(t):
    p = pose_keys(t, AWAKEN_KEYS)
    p.update(heart(1.0 + 0.10 * bump(t, 0.1, 0.7) + 0.10 * bump(t, 0.8, 1.4)))
    # dos sacudidas: el temblor con que se resquebraja (0.3–1.4 s) y la de quitarse el polvo ya en pie
    q1, q2 = bump(t, 0.25, 1.45), bump(t, 3.15, 3.95)
    wob = 1.6 * q1 * sin(2 * pi * 9.0 * t) + 6.5 * q2 * sin(2 * pi * 4.0 * (t - 3.15))
    p["Chest"] = (p["Chest"][0], p["Chest"][1] + 0.5 * wob, p["Chest"][2] + wob)
    p["Head"] = (p["Head"][0], p["Head"][1] - 0.3 * wob, p["Head"][2] - 0.7 * wob + 1.2 * q1 * sin(2 * pi * 7.0 * t))
    p["Hips.loc"] = (p["Hips.loc"][0] + 0.012 * q1 * sin(2 * pi * 11.0 * t), p["Hips.loc"][1], p["Hips.loc"][2])
    seat_hands(p, w=1.0 - smooth(t, *AWAKEN_FREE))      # apoyadas donde dormían hasta que se empuja y las suelta
    for s in ("L", "R"):
        lift_hand(p, s)
    return finish(p)


KNEEL_T, KNEEL_HIT = 2.0, 0.95                # las rodillas tocan el suelo a 0.95 s
KNEEL_KEYS = [
    (0.0, I0),
    (0.45, {**GROUND, **RELAX, **lids(0.5), "Hips.loc": (0.0, -0.06, -0.26), "Hips": (8, 0, 0), "Spine": (8, 0, 0),
            "Chest": (6, 0, 0), "Head": (10, 0, 0), **both({"UpperArm": (-10, -12, 0), "Forearm": (-26, 0, 0)})}),
    (KNEEL_HIT, {**GROUND, **FIST, **lids(0.75), "Hips.loc": (0.0, 0.06, KNEEL_Z - 0.02), "Hips": (10, 0, 0), "Spine": (12, 0, 0),
                 "Chest": (10, 0, 0), "Head": (26, 0, 0), "Jaw": (5, 0, 0), **both({"UpperArm": (-14, -10, 0), "Forearm": (-14, 0, 0)})}),
    (1.4, {**GROUND, **KNEEL_TOP, "Spine": (3, 0, 0), "Chest": (3, 0, 0), "Head": (15, 0, 0)}),
    (KNEEL_T, {**GROUND, **KNEEL_TOP}),
]


def kneel(t):
    p = pose_keys(t, KNEEL_KEYS)
    p.update(heart(1.0))
    g = smooth(t, 0.30, KNEEL_HIT)       # el pie gira sobre su punta y se tiende; la rodilla baja hasta el suelo
    kneel_hands(p, w=smooth(t, 0.5, 0.95))       # los puños llegan al suelo con las rodillas y ahí se quedan
    for s, sx in (("L", 1.0), ("R", -1.0)):
        lift_hand(p, s)
        p["IK_" + s] = (sx * KNEEL_TOE.x * g, KNEEL_TOE.y * g, KNEEL_TOE.z * g + 0.10 * bump(g, 0.0, 1.0))
        p["IKR_" + s] = (KNEEL_FOOT[0] * g, 0.0, 0.0)
    return finish(p)


REMEMBER_T = 3.0
REMEMBER_MID = {**KNEEL, **lids(0.45), "Spine": (3, 0, 0), "Chest": (2, 0, 0), "Head": (2, 0, 0),
                **both({"UpperArm": (-14, -10, 0), "Forearm": (-30, 0, 0), "Hand": (0, 0, 30)}),
                **both({"Fingers": (0, 40, 0), "FingerTips": (0, 40, 0), "Thumb": (0, 10, 0)})}
REMEMBER_END = {**KNEEL_LEGS, **OPEN, **lids(0.3), "Hips.loc": (0.0, 0.10, KNEEL_Z), "Hips": (0, 0, 0), "Spine": (1, 0, 0),
                "Chest": (-1, 0, 0), "Head": (-8, 0, 0),
                **both({"UpperArm": (-34, -10, 0), "Forearm": (-62, 0, 0), "Hand": (-8, 0, 84)})}


def remember(t):
    p = pose_keys(t, [(0.0, KNEEL), (0.5, KNEEL), (1.4, REMEMBER_MID), (2.5, REMEMBER_END), (REMEMBER_T, REMEMBER_END)])
    br = sin(2 * pi * t / 3.0) * smooth(t, 2.0, 3.0)
    p["Chest"] = (p["Chest"][0] - 0.8 * br, 0, 0)
    p.update(heart(1.0 + 0.16 * smooth(t, 0.6, 2.4) + 0.05 * bump(t % 1.0, 0.0, 0.5)))
    kneel_hands(p, w=1.0 - smooth(t, 0.45, 1.0))         # suelta el suelo poco a poco
    for s in ("L", "R"):
        lift_hand(p, s)
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
# expresiones: un cuadro, solo huesos de la cara
FACE_ANIMS = [(name, 1.0 / kc.FPS, (lambda t, name=name: face_pose(name))) for name in FACES]


# ─────────────────────────────────── Main ───────────────────────────────────

def _fcurve_bags(act):
    """(colección de curvas, curva) de una acción, con acciones por capas o de las antiguas."""
    try:
        return [(act.fcurves, fc) for fc in act.fcurves]
    except AttributeError:
        out = []
        for layer in act.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    out.extend((bag.fcurves, fc) for fc in bag.fcurves)
        return out


def strip_tracks(names_body, names_face):
    """Las animaciones del cuerpo se quedan sin pista en cejas y comisuras (la expresión
    que ponga el juego no se pisa) y las expresiones, solo con las de la cara."""
    for act in bpy.data.actions:
        if act.name in names_face:
            keep = lambda bone: bone in FACE_BONES
        elif act.name in names_body:
            keep = lambda bone: bone not in FACE_ONLY
        else:
            continue
        for bag, fc in _fcurve_bags(act):
            if not keep(fc.data_path.split('"')[1]):
                bag.remove(fc)


def build():
    kc.reset_scene()
    mats = make_materials()
    arm = kc.build_armature("Armature", make_bones())
    body = build_body()
    kc.bake_ao([body], dist=0.75, samples=32, strength=0.85, floor=0.28)
    for f, mat in zip(body.faces, body.fmat):          # lo emisivo y las grietas no llevan sombra horneada
        if mat != "Body":
            for i in f:
                body.ao[i] = 1.0
    objs = {"Nojoch": body.build("Nojoch", mats, arm)}
    kc.bake_actions(arm, ANIMS + FACE_ANIMS)
    strip_tracks({a[0] for a in ANIMS}, {a[0] for a in FACE_ANIMS})
    return arm, objs


def apply_face(arm, name, other=None, w=0.0):
    """Para los renders: pone en el esqueleto la expresión `name` (o su mezcla con `other`)
    encima de la pose que tenga. Hay que llamarla después de fijar el cuadro."""
    a = face_pose(name)
    b = face_pose(other) if other else a
    for pb in arm.pose.bones:
        n = pb.name
        if n not in FACE_BONES:
            continue
        rest = arm.data.bones[n].matrix_local.to_3x3()
        rq = rest.to_quaternion()
        ra, rb_ = a.get(n, (0, 0, 0)), b.get(n, (0, 0, 0))
        r = [x + (y - x) * w for x, y in zip(ra, rb_)]
        qm = Euler([math.radians(x) for x in r], "XYZ").to_quaternion()
        pb.rotation_quaternion = rq.inverted() @ qm @ rq
        la, lb = a.get(n + ".loc", (0, 0, 0)), b.get(n + ".loc", (0, 0, 0))
        pb.location = rest.inverted() @ Vector([x + (y - x) * w for x, y in zip(la, lb)])


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
