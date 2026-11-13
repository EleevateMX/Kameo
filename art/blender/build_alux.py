"""Genera game/assets/characters/alux.glb — el alux (espíritu guardián maya).

Uso (desde la raíz del repo):
    .tools/blender-venv/bin/python art/blender/build_alux.py

Diseño original: cabezón, ojos grandes de jade que brillan, orejas largas y caídas,
huipil de corte recto con jubón y ruedo bordados, faja tejida, pulseras, huaraches y
cabello («Hair»). Encima, las piezas del personalizador, cada una en su malla, para que
el juego las encienda o las apague por nombre de nodo:
  · tocados: Hat_Palma, Hat_Penacho, Hat_Flor, Hat_Plumas, Hat_Panuelo, Hat_Hojas;
  · vestimenta sobre la túnica: Outfit_Capa, Outfit_Faja, Outfit_Bordado;
  · accesorios: Acc_Morral (el sabucán de siempre), Acc_Sonaja, Acc_Caracol, Acc_Farol;
  · amuletos: Amu_Jade (el de siempre), Amu_Concha, Amu_Obsidiana, Amu_Semillas.

Materiales: «Tunic» (color principal del jugador), «Trim» (color secundario: ribetes
del huipil y telas de las piezas) y «Skin» (tono de piel) son los que el juego tiñe:
sus vértices llevan solo el matiz, como factor, y el color está en el material.
«Body» y «Headwear» llevan todo el color en los vértices (con oclusión horneada);
«Eye», «Jade» y «Firefly» son emisivos; «Obsidian» es el único pulido.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import alux_common as kc  # noqa: E402  (importa bpy antes que mathutils)
from mathutils import Matrix, Vector  # noqa: E402
from alux_common import (C, K, L, WHITE, Loft, MeshBuilder, Rig, add_pose, blend_pose, both,  # noqa: E402
                          bump, mixc, mulc, ngon, pose_keys, scale_pose, squash)

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(os.environ.get("KAMEO_OUT_DIR") or os.path.join(REPO, "game", "assets", "characters"), "alux.glb")

sin, cos, pi, rad = math.sin, math.cos, math.pi, math.radians

# ───────────────────────────────── Materiales ─────────────────────────────────

# Albedo de fábrica de los materiales que el juego tiñe. En Godot (Compatibility) el
# color que se ve es albedo × color de vértice, los dos tal como están guardados (sRGB).
#  · Trim: los vértices van en blanco (con su sombra), así que el albedo es el color.
#  · Skin: el rubor y las palmas son más claros que la piel, y un vértice no pasa de 1;
#    por eso la piel media va en gris 0.75 y el albedo es el tono de piel × 4/3.
SKIN_HEX = "#a9714b"                   # tono de piel de fábrica (el que se ve)
SKIN_GAIN = 4.0 / 3.0                  # albedo de «Skin» = tono de piel × SKIN_GAIN
SKIN_ALBEDO = "#%02x%02x%02x" % tuple(int(round(c * SKIN_GAIN * 255)) for c in kc.hex_rgb(SKIN_HEX))  # #e19764
TRIM_HEX = "#f8efdc"                   # crema del jubón y del ruedo
VDIV = {"Skin": kc.hex_rgb(SKIN_ALBEDO), "Trim": kc.hex_rgb(TRIM_HEX)}


def make_materials():
    m = kc.make_material
    return {
        "Body": m("Body", "#ffffff", 0.8),
        "Skin": m("Skin", SKIN_ALBEDO, 0.8, tint=True),
        "Tunic": m("Tunic", "#2ec4a6", 0.85),
        "Trim": m("Trim", TRIM_HEX, 0.8, tint=True),
        "Eye": m("Eye", "#59ffe0", 0.25, emission=1.2),
        "Jade": m("Jade", "#3ddba8", 0.3, emission=0.6),
        "Headwear": m("Headwear", "#ffffff", 0.85),
        "Obsidian": m("Obsidian", "#ffffff", 0.12),
        "Firefly": m("Firefly", "#f6ffb4", 0.5, emission=0.7, emission_color="#c9f06a"),
    }


def _pal(mat, **cols):
    return {k: (mat, C(v) if isinstance(v, str) else v) for k, v in cols.items()}


def _gris(k):
    """Color de «Trim» que en el vértice queda en gris k (1 = blanco: manda el tinte)."""
    return tuple(kc.srgb_to_linear(c * k) for c in kc.hex_rgb(TRIM_HEX))


PAL = {
    **_pal("Skin", Skin=SKIN_HEX, SkinDeep="#8c563a", SkinLight="#bd8a62", Blush="#c96a55"),
    **_pal("Body", Dark="#3a1c16", Pupil="#052a26", EyeRim="#0c5a4f", White="#fffaf0", Brow="#211712",
           Lace="#ffffff", Thread="#c23b2e", Pink="#ff5fa2", Red="#e23a30",
           Yellow="#ffc233", Leaf="#3fa34d", Sash="#c93545", SashDeep="#8a2032",
           Sandal="#7d4c27", Sole="#4a2c17", Cord="#5b3a22", Gold="#e8b53a",
           Henequen="#d9c28c", HenequenDeep="#b0915a", JadeDull="#2a9c78",
           # piezas del personalizador
           Turq="#19b4c6", Wood="#6b4526", WoodDeep="#452b17", Leather="#8a5a33",
           Gourd="#a5522a", GourdDeep="#74381c", GourdLight="#e6bd80",
           Shell="#f6e7d2", ShellPink="#eea79c", ShellDeep="#c9906e", ShellRose="#e2788a",
           Coral="#f08468", CoralLight="#ffd6bc", CoralDeep="#bf5038",
           Seed="#cf241f", SeedDeep="#8e1414", SeedEye="#241210", PlumeA="#fff7ec", PlumeB="#e23a30"),
    **_pal("Tunic", Tunic=WHITE, TunicSeam=(0.6, 0.6, 0.6)),
    # tela teñible con el color secundario: blanco y grises (cenefas y pliegues)
    **_pal("Trim", Trim=TRIM_HEX, Cloth=TRIM_HEX, ClothMid=_gris(0.80), ClothDeep=_gris(0.62),
           ClothDark=_gris(0.42), Strap=_gris(0.86), StrapEdge=_gris(0.66)),
    **_pal("Eye", Eye=WHITE),
    **_pal("Jade", Jade=WHITE),
    **_pal("Headwear", Straw="#dcb968", StrawDeep="#b98d43", HatBand="#b3372e", Hair="#211712",
           HairLight="#3d2a20", Petal="#fff7ec", PetalHeart="#ffc233", HLeaf="#3fa34d",
           HGold="#e8b53a", FGreen="#16a877", FRed="#d83a2e", FBlue="#2a8fdc", FYellow="#ffc233",
           FTeal="#35d6c0",
           # tocados del personalizador
           HLeafDeep="#2a7a3c", HLeafLight="#86c95c", Twig="#6a4a2a", FlPink="#ff8fb8",
           FlViolet="#a377e0", Berry="#d83a2e", FWhite="#fff7ec"),
    **_pal("Obsidian", Obsid="#16131c", ObsidEdge="#2b2836", ObsidShine="#8f98b8"),
    **_pal("Firefly", Glow="#ffffff"),
}
SKIN, BLUSH, SKIN_DEEP, SKIN_LIGHT = (PAL[k][1] for k in ("Skin", "Blush", "SkinDeep", "SkinLight"))


def new_mb():
    """MeshBuilder del alux: los materiales teñibles guardan el matiz, no el color."""
    mb = MeshBuilder(PAL)
    mb.vdiv = VDIV
    return mb


# ───────────────────────────────── Medidas ─────────────────────────────────

HC = Vector((0.0, 0.0, 1.062))          # centro de la cabeza
HR = (0.272, 0.250, 0.240)              # radios de la cabeza
EYE_R = 0.086
EYE_LON, EYE_LAT = rad(24), rad(-4)

SHOULDER = Vector((0.172, 0.0, 0.80))
ELBOW = Vector((0.240, 0.0, 0.632))
WRIST = Vector((0.290, -0.012, 0.487))
HIP = Vector((0.088, 0.0, 0.42))
KNEE = Vector((0.092, 0.0, 0.235))
ANKLE = Vector((0.092, 0.0, 0.075))
BALL = {"L": Vector((0.092, -0.085, 0.0)), "R": Vector((-0.092, -0.085, 0.0))}   # apoyo del pie
EAR_PTS = [(0.185, 0.015, 1.050), (0.255, 0.020, 1.076), (0.322, 0.030, 1.106), (0.387, 0.042, 1.126),
           (0.442, 0.055, 1.126), (0.487, 0.066, 1.106), (0.517, 0.074, 1.076)]
EAR_RAD = [(0.092, 0.052), (0.086, 0.041), (0.078, 0.028), (0.060, 0.020), (0.040, 0.014), (0.022, 0.009),
           (0.004, 0.003)]
KNOT_TH = rad(38)        # nudo de la faja: costado izquierdo, hacia atrás
BAG_TH = rad(140)        # sabucán: cadera derecha, hacia atrás


def mx(v, s):
    """Refleja en X para el lado derecho (s = -1)."""
    return Vector((v[0] * s, v[1], v[2]))


def head_scale(d):
    lower = max(0.0, 0.25 - d.z)
    s = 1.0 + 0.18 * lower * abs(d.x) ** 1.5          # cachetes
    s += 0.07 * max(0.0, -d.z) * max(0.0, -d.y)       # barbilla
    s -= 0.03 * max(0.0, d.z) ** 2 * max(0.0, -d.y)   # frente un poco plana
    return s


def head_dir(lon, lat):
    return Vector((sin(lon) * cos(lat), -cos(lon) * cos(lat), sin(lat)))


def head_pt(lon, lat, off=0.0):
    """Punto de la cabeza. lon 0 = frente, + hacia la izquierda del personaje."""
    d = head_dir(lon, lat)
    s = head_scale(d)
    return HC + Vector((d.x * HR[0] * s, d.y * HR[1] * s, d.z * HR[2] * s)) + d * off


def eye_center(s):
    return head_pt(s * EYE_LON, EYE_LAT) - head_dir(s * EYE_LON, EYE_LAT) * 0.047


def brow_center(s):
    return head_pt(s * rad(24), rad(35), 0.006)


MOUTH_C = head_pt(0, rad(-37), 0.0)


# ───────────────────────────────── Esqueleto ─────────────────────────────────

def make_bones():
    b = [
        ("Root", (0, 0, 0), (0, 0, 0.15), None),
        ("Hips", (0, 0, 0.42), (0, 0, 0.55), "Root"),
        ("Spine", (0, 0, 0.55), (0, 0, 0.70), "Hips"),
        ("Chest", (0, 0, 0.70), (0, 0, 0.84), "Spine"),
        ("Head", (0, 0, 0.84), (0, 0, 1.10), "Chest"),
        ("Mouth", MOUTH_C, MOUTH_C + Vector((0, -0.05, 0)), "Head"),
        ("Amulet", (0, -0.13, 0.80), (0, -0.15, 0.73), "Chest"),
        ("SashTail", (0.17, 0.12, 0.555), (0.19, 0.13, 0.40), "Hips"),
        ("Bag", (-0.18, 0.14, 0.50), (-0.19, 0.15, 0.39), "Hips"),
    ]
    for s, sfx in ((1, "_L"), (-1, "_R")):
        ec = eye_center(s)
        bc = brow_center(s)
        b += [
            ("Ear" + sfx, mx((0.24, 0.02, 1.07), s), mx(EAR_PTS[3], s), "Head"),
            ("EarTip" + sfx, mx(EAR_PTS[3], s), mx(EAR_PTS[6], s), "Ear" + sfx),
            ("Lid" + sfx, ec, ec + Vector((0, -0.06, 0)), "Head"),
            ("LidLow" + sfx, ec, ec + Vector((0, -0.06, -0.01)), "Head"),
            ("Brow" + sfx, bc, bc + Vector((0, -0.04, 0)), "Head"),
            ("UpperArm" + sfx, mx(SHOULDER, s), mx(ELBOW, s), "Chest"),
            ("Forearm" + sfx, mx(ELBOW, s), mx(WRIST, s), "UpperArm" + sfx),
            ("Hand" + sfx, mx(WRIST, s), mx(WRIST + Vector((0.012, 0, -0.06)), s), "Forearm" + sfx),
            ("Fingers" + sfx, mx(WRIST + Vector((0.014, -0.004, -0.078)), s),
             mx(WRIST + Vector((0.008, -0.004, -0.125)), s), "Hand" + sfx),
            ("Thigh" + sfx, mx(HIP, s), mx(KNEE, s), "Hips"),
            ("Shin" + sfx, mx(KNEE, s), mx(ANKLE, s), "Thigh" + sfx),
            ("Foot" + sfx, mx(ANKLE, s), mx(ANKLE + Vector((0, -0.12, -0.05)), s), "Shin" + sfx),
        ]
    return b


RIG = Rig(make_bones())


# ─────────────────────────────── Cuerpo (malla) ───────────────────────────────

TUNIC_RINGS = [
    # z, rx, ry, pesos
    (0.280, 0.232, 0.178, {"Hips": 1}),
    (0.345, 0.226, 0.172, {"Hips": 1}),
    (0.420, 0.218, 0.165, {"Hips": 1}),
    (0.500, 0.208, 0.156, {"Hips": 1}),
    (0.560, 0.202, 0.150, {"Hips": 0.5, "Spine": 0.5}),
    (0.630, 0.196, 0.143, {"Spine": 1}),
    (0.700, 0.192, 0.136, {"Spine": 0.5, "Chest": 0.5}),
    (0.770, 0.188, 0.128, {"Chest": 1}),
    (0.825, 0.172, 0.112, {"Chest": 1}),
    (0.850, 0.100, 0.070, {"Chest": 1}),
]
JUB_RINGS = [(0.698, 0.212, 0.152), (0.704, 0.218, 0.158), (0.760, 0.210, 0.148), (0.822, 0.196, 0.134),
             (0.852, 0.125, 0.092)]
SASH_Z = ((0.508, 0.0), (0.512, 0.014), (0.538, 0.016), (0.572, 0.016), (0.598, 0.014), (0.602, 0.0))


def tun_r(z):
    for (z0, rx0, ry0, _), (z1, rx1, ry1, _) in zip(TUNIC_RINGS, TUNIC_RINGS[1:]):
        if z0 <= z <= z1:
            f = (z - z0) / (z1 - z0)
            return rx0 + (rx1 - rx0) * f, ry0 + (ry1 - ry0) * f
    raise ValueError(z)


def tunic_loft():
    return Loft([dict(c=(0, 0, z), rx=rx, ry=ry, n=3.0, w=w) for z, rx, ry, w in TUNIC_RINGS])


def jub_loft():
    return Loft([dict(c=(0, 0, z), rx=rx, ry=ry, n=4.0, w={"Chest": 1}) for z, rx, ry in JUB_RINGS])


def sash_loft():
    rings = []
    for z, d in SASH_Z:
        rx, ry = tun_r(z)
        rings.append(dict(c=(0, 0, z), rx=rx + d, ry=ry + d, n=3.0, w={"Hips": 0.6, "Spine": 0.4}))
    return Loft(rings)


def skirt_weights(base, p):
    """La falda del huipil sigue un poco a los muslos para que ondee al correr."""
    if p.z >= 0.50:
        return base
    k = min(1.0, (0.50 - p.z) / 0.22) * 0.5
    sl = min(1.0, max(0.0, 0.5 + p.x / 0.12))
    out = {b: v * (1.0 - k) for b, v in base.items()}
    out["Thigh_L"] = out.get("Thigh_L", 0.0) + k * sl
    out["Thigh_R"] = out.get("Thigh_R", 0.0) + k * (1.0 - sl)
    return {b: v for b, v in out.items() if v > 1e-4}


def u_at_z(loft, z):
    lo, hi = 0.0, loft.umax()
    inc = loft.frame(hi)[0].z > loft.frame(lo)[0].z
    for _ in range(40):
        mid = 0.5 * (lo + hi)
        if (loft.frame(mid)[0].z < z) == inc:
            lo = mid
        else:
            hi = mid
    return 0.5 * (lo + hi)


def face_theta(loft, u, face, v):
    """θ del punto de una cara (frente/espalda/costados) con coordenada lateral
    normalizada v ∈ (-1, 1): x = v·rx en frente y espalda, y = v·ry en los costados."""
    c, a, b, _t, rx, ry, ryn, _n = loft.frame(u)
    lo, hi = {"front": (-pi, 0.0), "back": (pi, 0.0), "left": (-pi / 2, pi / 2), "right": (1.5 * pi, pi / 2)}[face]
    axis, goal = (a, v * rx) if face in ("front", "back") else (b, v * ry)
    for _ in range(40):
        mid = 0.5 * (lo + hi)
        if (loft.point(u, mid) - c).dot(axis) < goal:
            lo = mid
        else:
            hi = mid
    return 0.5 * (lo + hi)


def flower_shapes(loft, u, th, r, color, heart="Yellow"):
    return [(loft.poly(u, th, ngon(10, r, star=0.5, phase=0.3)), color),
            (loft.poly(u, th, ngon(4, r * 0.36)), heart)]


def leaf_shape(loft, u, th, r, rot):
    return [(loft.poly(u, th, [(r * 2.3, 0), (0, r), (-r * 2.3, 0), (0, -r)], rot), "Leaf")]


def band(u_lo, u_hi, th0, key):
    return ([(u_lo, th0), (u_lo, th0 + 2 * pi), (u_hi, th0 + 2 * pi), (u_hi, th0)], key)


def outer_point(lofts, z, th, off=0.006):
    """Punto más externo (túnica, jubón o faja) a la altura z en la dirección θ."""
    best = None
    for lf, z0, z1 in lofts:
        if z0 <= z <= z1:
            p = lf.point(u_at_z(lf, z), th)
            if best is None or math.hypot(p.x, p.y) > math.hypot(best.x, best.y):
                best = p
    d = Vector((best.x, best.y, 0)).normalized()
    return best + d * off, d


def body_weights(z):
    for (z0, _a, _b, w0), (z1, _c, _d, w1) in zip(TUNIC_RINGS, TUNIC_RINGS[1:]):
        if z0 <= z <= z1:
            return kc.mix_weights(w0, w1, (z - z0) / (z1 - z0))
    return {"Chest": 1} if z > 0.5 else {"Hips": 1}


def build_body():
    mb = new_mb()
    HEAD = {"Head": 1}

    # ── cabeza: piel con rubor degradado en los cachetes y la nariz
    def head_col(p, d):
        c = SKIN
        for s in (1, -1):
            k = max(0.0, 1.0 - (p - head_pt(s * rad(47), rad(-27))).length / 0.09)
            c = mixc(c, BLUSH, 0.8 * k * k * (3 - 2 * k))
        k = max(0.0, 1.0 - (p - head_pt(0, rad(-17))).length / 0.07)
        return mixc(c, BLUSH, 0.35 * k)

    mb.add_sphere(HC, HR, "Skin", HEAD, segs=22, rings=14, deform=head_scale, col=head_col)
    neck = Loft([dict(c=(0, 0, 0.80), rx=0.075, ry=0.07, w={"Chest": 1}),
                 dict(c=(0, 0, 0.845), rx=0.07, ry=0.065, w={"Chest": 0.5, "Head": 0.5}),
                 dict(c=(0, 0, 0.90), rx=0.075, ry=0.07, w=HEAD)])
    mb.add_loft(neck, "SkinDeep", segs=8, cap0=False, cap1=False)

    # nariz de botón
    mb.add_sphere(head_pt(0, rad(-17), -0.004), (0.034, 0.03, 0.026), "Skin", HEAD, segs=8, rings=6,
                  col=lambda p, d: mixc(SKIN, BLUSH, 0.45 * max(0.0, -d.y)))

    # boca: media luna oscura pegada a la cara; el hueso Mouth la abre al escalarla
    mouth = []
    for i in range(7):
        f = i / 6.0 * 2.0 - 1.0
        mouth.append(dict(c=head_pt(rad(19) * f, rad(-38 + 8.0 * f * f), 0.001),
                          rx=0.0105 * (1.0 - 0.82 * f * f), ry=0.006, w={"Mouth": 1}))
    mb.add_loft(Loft(mouth, side=(0, 0, 1)), "Dark", segs=6)

    for s, sfx in ((1, "_L"), (-1, "_R")):
        # ── ojos: iris de jade que brilla, aro oscuro, pupila y dos brillos
        ce = eye_center(s)
        f = head_dir(s * rad(9), rad(1))
        rot = f.to_track_quat("Z", "Y").to_matrix()
        mb.add_sphere(ce, EYE_R, "Eye", HEAD, segs=16, rings=16, rot=rot, keep=lambda d: d.z > 0.3,
                      matfn=lambda d: "Pupil" if d.z > 0.93 else ("Eye" if d.z > 0.70 else "EyeRim"))

        def eye_surf(a, b, ce=ce, f=f):
            v = f + Vector((1, 0, 0)) * a + Vector((0, 0, 1)) * b
            v.normalize()
            return ce + v * EYE_R

        mb.add_decal(eye_surf, -0.30, 0.34, 0.019, "White", HEAD, nseg=7, offset=0.002, outward=ce)
        mb.add_decal(eye_surf, 0.30, -0.26, 0.009, "White", HEAD, nseg=5, offset=0.002, outward=ce)

        # párpados (medias esferas que giran sobre X): el de arriba con pestaña
        n = Vector((0, sin(rad(38)), cos(rad(38))))
        rl = n.to_track_quat("Z", "X").to_matrix()
        mb.add_sphere(ce, EYE_R + 0.007, "Skin", {"Lid" + sfx: 1}, segs=12, rings=12, rot=rl,
                      keep=lambda d: d.z > 0.0, matfn=lambda d: "Brow" if d.z < 0.26 else "Skin")
        n2 = Vector((0, sin(rad(50)), -cos(rad(50))))
        rl2 = n2.to_track_quat("Z", "X").to_matrix()
        mb.add_sphere(ce, EYE_R + 0.005, "Skin", {"LidLow" + sfx: 1}, segs=10, rings=8, rot=rl2,
                      keep=lambda d: d.z > 0.0, col=lambda p, d: mixc(SKIN_DEEP, SKIN, min(1.0, d.z * 3)))

        # ceja gruesa que se afina hacia fuera
        brow = []
        for i in range(5):
            g = i / 4.0
            brow.append(dict(c=head_pt(s * rad(10 + 28 * g), rad(33.5 + 5 * sin(pi * g) - 3 * g), 0.004),
                             rx=0.0165 * (1 - 0.55 * g) * (0.6 + 0.4 * min(1.0, g * 4)), ry=0.008,
                             w={"Brow" + sfx: 1}))
        mb.add_loft(Loft(brow, side=(0, 0, 1)), "Brow", segs=6)

        # ── orejas: largas, puntiagudas, caídas en la punta; nacen anchas de la cabeza
        ew = [HEAD, {"Head": 0.6, "Ear" + sfx: 0.4}, {"Ear" + sfx: 1}, {"Ear" + sfx: 0.5, "EarTip" + sfx: 0.5},
              {"EarTip" + sfx: 1}, {"EarTip" + sfx: 1}, {"EarTip" + sfx: 1}]
        rings = [dict(c=mx(c, s), rx=r[0], ry=r[1], w=w) for c, r, w in zip(EAR_PTS, EAR_RAD, ew)]

        def ear_col(p, u, th, s=s):
            front = max(0.0, sin(th) * s)                 # cara delantera de la oreja
            inner = front * max(0.0, 1.0 - abs(cos(th)) * 1.25) * min(1.0, u / 1.2)
            c = mixc(SKIN, BLUSH, 0.25 * min(1.0, u / 5.0))
            return mixc(c, mixc(BLUSH, SKIN_DEEP, 0.35), 0.85 * inner)

        mb.add_loft(Loft(rings, side=(0, 0, 1)), "Skin", segs=10, cap0=False, col=ear_col)

        # ── brazos
        sh, el, wr = mx(SHOULDER, s), mx(ELBOW, s), mx(WRIST, s)
        ua, fa, ha, fi = "UpperArm" + sfx, "Forearm" + sfx, "Hand" + sfx, "Fingers" + sfx
        arm_rings = [
            dict(c=sh + (sh - el) * 0.15, rx=0.05, ry=0.05, w={ua: 1}),
            dict(c=sh.lerp(el, 0.5), rx=0.051, ry=0.051, w={ua: 1}),
            dict(c=sh.lerp(el, 0.85), rx=0.048, ry=0.048, w={ua: 0.8, fa: 0.2}),
            dict(c=el, rx=0.047, ry=0.048, w={ua: 0.5, fa: 0.5}),
            dict(c=el.lerp(wr, 0.18), rx=0.048, ry=0.048, w={ua: 0.2, fa: 0.8}),
            dict(c=el.lerp(wr, 0.6), rx=0.045, ry=0.045, w={fa: 1}),
            dict(c=wr, rx=0.037, ry=0.037, w={fa: 0.5, ha: 0.5}),
        ]
        mb.add_loft(Loft(arm_rings, side=(0, 1, 0)), "Skin", segs=8, cap0=False, cap1=False,
                    col=lambda p, u, th: mixc(SKIN, BLUSH, 0.22 * max(0.0, 1 - abs(u - 3.0))))
        # pulsera: cuentas de jade a la izquierda, hilo rojo y oro a la derecha
        bc_ = el.lerp(wr, 0.84)
        bd = (wr - el).normalized()
        br = Loft([dict(c=bc_ - bd * 0.016, rx=0.039, ry=0.039, w={fa: 1}),
                   dict(c=bc_ - bd * 0.011, rx=0.049, ry=0.049, w={fa: 1}),
                   dict(c=bc_ + bd * 0.011, rx=0.047, ry=0.047, w={fa: 0.8, ha: 0.2}),
                   dict(c=bc_ + bd * 0.016, rx=0.037, ry=0.037, w={fa: 0.8, ha: 0.2})], side=(0, 1, 0))
        if s > 0:
            mb.add_loft(br, "Jade", segs=8, cap0=False, cap1=False,
                        matfn=lambda u, th, p: "Gold" if int(th / (2 * pi) * 8 + 0.01) % 4 == 0 else "Jade")
        else:
            mb.add_loft(br, "Thread", segs=8, cap0=False, cap1=False,
                        matfn=lambda u, th, p: "Gold" if 1.0 < u < 2.0 else "Thread")
        # mano: palma, pulgar y tres dedos agrupados que se cierran con el hueso Fingers
        pc = wr + mx((0.014, -0.004, -0.045), s)
        mb.add_sphere(pc, (0.027, 0.043, 0.047), "Skin", {ha: 1}, segs=8, rings=6,
                      col=lambda p, d, s=s: mixc(SKIN, SKIN_LIGHT, 0.7 * max(0.0, -d.x * s)))
        thumb = Loft([dict(c=pc + mx((-0.004, -0.030, 0.012), s), rx=0.016, ry=0.016, w={ha: 1}),
                      dict(c=pc + mx((-0.012, -0.052, -0.006), s), rx=0.014, ry=0.014, w={ha: 1}),
                      dict(c=pc + mx((-0.020, -0.062, -0.030), s), rx=0.011, ry=0.011, w={ha: 1}),
                      dict(c=pc + mx((-0.023, -0.063, -0.040), s), rx=0.004, ry=0.004, w={ha: 1})],
                     side=(1, 0, 0))
        mb.add_loft(thumb, "Skin", segs=6, cap0=False)
        for k, (dy, ln) in enumerate(((-0.026, 0.050), (0.0, 0.056), (0.026, 0.048))):
            root = pc + mx((0.004, dy, -0.034), s)
            fng = Loft([dict(c=root, rx=0.0145, ry=0.0145, w={ha: 0.7, fi: 0.3}),
                        dict(c=root + mx((-0.004, 0, -ln * 0.5), s), rx=0.0135, ry=0.0135, w={fi: 1}),
                        dict(c=root + mx((-0.016, 0, -ln * 0.92), s), rx=0.011, ry=0.011, w={fi: 1}),
                        dict(c=root + mx((-0.020, 0, -ln), s), rx=0.004, ry=0.004, w={fi: 1})], side=(0, 1, 0))
            mb.add_loft(fng, "Skin", segs=6, cap0=False,
                        col=lambda p, u, th: mixc(SKIN, BLUSH, 0.3 * min(1.0, u / 3.0)))

        # manga corta del huipil con puño bordado
        sl0, sl1 = sh + (sh - el) * 0.25, sh.lerp(el, 0.66)
        sleeve = [
            dict(c=sl0, rx=0.066, ry=0.066, w={"Chest": 0.6, ua: 0.4}),
            dict(c=sl0.lerp(sl1, 0.4), rx=0.075, ry=0.075, w={ua: 1}),
            dict(c=sl0.lerp(sl1, 0.74), rx=0.083, ry=0.083, w={ua: 1}),
            dict(c=sl0.lerp(sl1, 0.80), rx=0.084, ry=0.084, w={ua: 1}),
            dict(c=sl1, rx=0.088, ry=0.088, w={ua: 1}),
        ]
        mb.add_loft(Loft(sleeve, side=(0, 1, 0)), None, segs=10, cap0=False, cap1=False,
                    matfn=lambda u, th, p: "Tunic" if u < 2.0 else ("Thread" if u < 3.0 else "Trim"))
        cuff = [dict(c=sl1.lerp(sl0, 0.10), rx=0.046, ry=0.046, w={ua: 1}),
                dict(c=sl1, rx=0.088, ry=0.088, w={ua: 1})]
        mb.add_loft(Loft(cuff, side=(0, 1, 0)), "Dark", segs=10, cap0=False, cap1=False, flip=True)

        # ── piernas
        hp, kn, an = mx(HIP, s), mx(KNEE, s), mx(ANKLE, s)
        th_, sn, ft = "Thigh" + sfx, "Shin" + sfx, "Foot" + sfx
        leg_rings = [
            dict(c=hp + Vector((0, 0, 0.03)), rx=0.07, ry=0.07, w={"Hips": 0.5, th_: 0.5}),
            dict(c=hp.lerp(kn, 0.4), rx=0.068, ry=0.068, w={th_: 1}),
            dict(c=hp.lerp(kn, 0.85), rx=0.060, ry=0.060, w={th_: 0.8, sn: 0.2}),
            dict(c=kn, rx=0.057, ry=0.060, w={th_: 0.5, sn: 0.5}),
            dict(c=kn.lerp(an, 0.2) + Vector((0, 0.006, 0)), rx=0.060, ry=0.062, w={th_: 0.2, sn: 0.8}),
            dict(c=kn.lerp(an, 0.6) + Vector((0, 0.004, 0)), rx=0.054, ry=0.056, w={sn: 1}),
            dict(c=an + Vector((0, 0, 0.012)), rx=0.044, ry=0.046, w={sn: 0.6, ft: 0.4}),
            dict(c=an + Vector((0, -0.004, -0.024)), rx=0.043, ry=0.047, w={ft: 1}),
        ]
        mb.add_loft(Loft(leg_rings, side=(1, 0, 0)), "Skin", segs=8, cap0=False, cap1=False,
                    col=lambda p, u, th: mixc(SKIN, BLUSH, 0.25 * max(0.0, 1 - abs(u - 3.0))))
        # pie con dedos y huarache
        FT = {ft: 1}
        fx = an.x
        foot = Loft([dict(c=(fx, 0.052, 0.044), rx=0.020, ry=0.022, ryn=0.020, w=FT),
                     dict(c=(fx, 0.022, 0.046), rx=0.042, ry=0.040, ryn=0.026, w=FT),
                     dict(c=(fx, -0.030, 0.048), rx=0.052, ry=0.044, ryn=0.028, w=FT),
                     dict(c=(fx, -0.082, 0.042), rx=0.058, ry=0.030, ryn=0.022, w=FT),
                     dict(c=(fx, -0.124, 0.038), rx=0.056, ry=0.022, ryn=0.018, w=FT),
                     dict(c=(fx, -0.146, 0.036), rx=0.042, ry=0.015, ryn=0.014, w=FT)])
        mb.add_loft(foot, "Skin", segs=10)
        for k, dx in enumerate((-0.038, -0.013, 0.012, 0.036)):
            big = (k == 0) if s > 0 else (k == 3)
            mb.add_sphere((fx + dx, -0.150 + abs(dx) * 0.25, 0.034), (0.0165 if big else 0.013, 0.02,
                          0.0155 if big else 0.013), "SkinLight", FT, segs=5, rings=3)
        sole = Loft([dict(c=(fx, 0.062, 0.009), rx=0.026, ry=0.009, n=3.0, w=FT),
                     dict(c=(fx, 0.034, 0.009), rx=0.050, ry=0.009, n=3.0, w=FT),
                     dict(c=(fx, -0.050, 0.009), rx=0.066, ry=0.009, n=3.0, w=FT),
                     dict(c=(fx, -0.130, 0.009), rx=0.066, ry=0.009, n=3.0, w=FT),
                     dict(c=(fx, -0.170, 0.009), rx=0.046, ry=0.009, n=3.0, w=FT)])
        mb.add_loft(sole, None, segs=8, matfn=lambda u, th, p: "Sandal" if sin(th) > 0.5 else "Sole",
                    capmat=("Sole", "Sole"))
        for y0, zt, wd in ((-0.088, 0.078, 0.013), (-0.036, 0.094, 0.011)):   # tiras sobre el empeine
            strap = []
            for i in range(7):
                a = pi * i / 6.0
                strap.append(dict(c=(fx + 0.062 * cos(a), y0 + 0.012 * sin(a), 0.016 + (zt - 0.016) * sin(a)),
                                  rx=wd, ry=0.005, w=FT))
            mb.add_loft(Loft(strap, side=(0, 1, 0)), "Sandal", segs=4, cap0=False, cap1=False)
        ank = Loft([dict(c=an + Vector((0, 0, z)), rx=r, ry=r + 0.002, w={sn: 0.5, ft: 0.5})
                    for z, r in ((-0.004, 0.044), (0.0, 0.053), (0.018, 0.053), (0.022, 0.044))])
        mb.add_loft(ank, "Sandal", segs=8, cap0=False, cap1=False)
        heel = Loft([dict(c=(fx + 0.045 * cos(a), 0.022 + 0.05 * sin(a), 0.03 + 0.05 * sin(a)), rx=0.011,
                          ry=0.005, w=FT) for a in (0.0, pi / 4, pi / 2, 3 * pi / 4, pi)], side=(0, 0, 1))
        mb.add_loft(heel, "Sandal", segs=4, cap0=False, cap1=False)

    # ── huipil: túnica recta (material «Tunic») con cenefa bordada en el ruedo
    tunic = tunic_loft()
    TH0 = rad(147)        # costura de la triangulación, donde no hay bordado

    def tw(u, th, p):
        return skirt_weights(tunic.weights(u), p)

    shapes = [band(0.0, 1.0, TH0, "Trim"), band(0.93, 1.0, TH0, "Thread"), band(0.0, 0.07, TH0, "Thread")]
    hem_cols = ["Pink", "Yellow", "Red"]
    k = 0
    for face, vs in (("front", (-0.75, -0.45, -0.15, 0.15, 0.45, 0.75)), ("left", (-0.5, 0.0, 0.5)),
                     ("back", (0.75, 0.45, 0.15, -0.15, -0.45, -0.75)), ("right", (0.5, 0.0, -0.5))):
        for i, v in enumerate(vs):
            th = face_theta(tunic, 0.5, face, v)
            shapes += flower_shapes(tunic, 0.5, th, 0.027, hem_cols[k % 3], "Red" if hem_cols[k % 3] == "Yellow" else "Yellow")
            k += 1
            if i + 1 < len(vs):
                thm = face_theta(tunic, 0.5, face, 0.5 * (v + vs[i + 1]))
                shapes += leaf_shape(tunic, 0.5, thm, 0.0075, rad(60 if i % 2 else -60))
    for th in (0.0, pi):          # costuras laterales
        shapes.append(([(1.08, th - 0.022), (1.08, th + 0.022), (7.4, th + 0.03), (7.4, th - 0.03)], "TunicSeam"))
    mb.add_loft_painted(tunic, "Tunic", shapes, segs=20, cap0=False, cap1=True, wfn=tw, th0=TH0,
                        capmat=(None, "SkinDeep"),
                        col=lambda p, u, th: mulc(WHITE, 0.84 + 0.16 * min(1.0, max(0.0, (p.z - 0.33) / 0.4))))
    hem_under = Loft([dict(c=(0, 0, 0.280), rx=0.232, ry=0.178, n=3.0, w={"Hips": 1}),
                      dict(c=(0, 0, 0.284), rx=0.212, ry=0.158, n=3.0, w={"Hips": 1})])
    mb.add_loft(hem_under, "Trim", segs=20, cap0=False, cap1=False, flip=True,
                wfn=lambda u, th, p: skirt_weights({"Hips": 1}, p))
    # fustán: encaje blanco con ondas bajo el ruedo, y sombra interior
    fustan = Loft([dict(c=(0, 0, 0.30), rx=0.214, ry=0.160, n=3.0, w={"Hips": 1}),
                   dict(c=(0, 0, 0.262), rx=0.220, ry=0.166, n=3.0, w={"Hips": 1}),
                   dict(c=(0, 0, 0.236), rx=0.226, ry=0.172, n=3.0, w={"Hips": 1})])
    v0 = len(mb.verts)
    mb.add_loft(fustan, "Lace", segs=20, cap0=False, cap1=True,
                wfn=lambda u, th, p: skirt_weights({"Hips": 1}, p), capmat=(None, "Dark"))
    for j in range(20):           # ondas del encaje en el borde inferior
        mb.verts[v0 + 40 + j].z += 0.012 if j % 2 else -0.006

    # ── jubón: cuello cuadrado bordado sobre los hombros
    jub = jub_loft()
    JT0 = rad(152)
    shapes = [band(0.25, 0.42, JT0, "Thread")]
    for face in ("front", "back"):
        for v, r, col_ in ((0.0, 0.034, "Red"), (0.5, 0.030, "Pink"), (-0.5, 0.030, "Pink")):
            if face == "front" and v == 0.0:
                continue                      # ahí cuelga el amuleto
            shapes += flower_shapes(jub, 2.05, face_theta(jub, 2.05, face, v), r, col_)
        for v in (0.25, -0.25):
            th = face_theta(jub, 1.75, face, v)
            shapes += leaf_shape(jub, 1.75, th, 0.009, rad(35 if v > 0 else -35))
            shapes.append((jub.poly(2.6, face_theta(jub, 2.6, face, v), ngon(8, 0.016, star=0.5)), "Yellow"))
        if face == "front":
            for v in (0.78, -0.78):
                shapes.append((jub.poly(2.5, face_theta(jub, 2.5, face, v), ngon(8, 0.016, star=0.5)), "Yellow"))
    for face in ("left", "right"):
        shapes += flower_shapes(jub, 2.05, face_theta(jub, 2.05, face, 0.0), 0.028, "Yellow", "Red")
    mb.add_loft_painted(jub, "Trim", shapes, segs=20, cap0=False, cap1=True, th0=JT0, capmat=(None, "SkinDeep"))
    jub_under = Loft([dict(c=(0, 0, 0.698), rx=0.212, ry=0.152, n=4.0, w={"Chest": 1}),
                      dict(c=(0, 0, 0.702), rx=0.190, ry=0.132, n=3.4, w={"Chest": 1})])
    mb.add_loft(jub_under, "Trim", segs=20, cap0=False, cap1=False, flip=True)

    # ── faja tejida: franja dorada con rombos, nudo y puntas con flecos
    sash = sash_loft()
    SW = {"Hips": 0.6, "Spine": 0.4}
    ST0 = KNOT_TH + 0.02
    shapes = [band(2.0, 3.0, ST0, "Yellow")]
    for i in range(10):
        th = ST0 + 2 * pi * (i + 0.5) / 10
        shapes.append((sash.poly(2.5, th, [(0.011, 0), (0, 0.016), (-0.011, 0), (0, -0.016)]),
                       "SashDeep" if i % 2 else "JadeDull"))
    mb.add_loft_painted(sash, "Sash", shapes, segs=20, cap0=False, cap1=False, th0=ST0)
    kp = sash.point(2.5, KNOT_TH)
    kn_dir = Vector((kp.x, kp.y, 0)).normalized()
    mb.add_sphere(kp + kn_dir * 0.012, (0.036, 0.036, 0.04), "Sash", SW, segs=8, rings=5)
    tang = Vector((-kn_dir.y, kn_dir.x, 0))
    for spread, length in ((-0.03, 0.20), (0.035, 0.16)):
        base = kp + kn_dir * 0.016
        tail = []
        for i in range(5):
            f = i / 4.0
            c = base + tang * (spread * f) + kn_dir * (0.022 * f) + Vector((0, 0, -length * f - 0.01))
            tail.append(dict(c=c, rx=0.012 + 0.016 * min(1.0, f * 2.5), ry=0.007,
                             w={"Hips": 1} if i == 0 else {"SashTail": 1}, side=tuple(tang)))
        mb.add_loft(Loft(tail, side=tuple(tang)), None, segs=6, cap0=False, cap1=True,
                    matfn=lambda u, th, p: "Yellow" if u > 3.0 else "Sash")
        end = Vector(tail[-1]["c"])
        for j in (-1, 0, 1):          # flecos
            fr = Loft([dict(c=end + tang * (j * 0.016), rx=0.006, ry=0.005, w={"SashTail": 1}),
                       dict(c=end + tang * (j * 0.021) + Vector((0, 0, -0.035)), rx=0.004, ry=0.004,
                            w={"SashTail": 1})], side=tuple(tang))
            mb.add_loft(fr, "Yellow", segs=4, cap0=False)

    # ── arete en la oreja izquierda: aro dorado con cuenta de jade
    ec_ = Vector((0.305, 0.024, 1.030))
    hoop = Loft([dict(c=ec_ + Vector((0.020 * cos(a), 0, -0.020 + 0.020 * sin(a))), rx=0.0045, ry=0.0045,
                      w={"Ear_L": 1}) for a in [2 * pi * i / 8 for i in range(9)]], side=(0, 1, 0))
    mb.add_loft(hoop, "Gold", segs=4, cap0=False, cap1=False)
    mb.add_sphere(ec_ + Vector((0, 0, -0.046)), 0.011, "Jade", {"Ear_L": 1}, segs=6, rings=4)
    return mb


# ───────────────────────────────── Tocados ─────────────────────────────────

def hairline(lon):
    """Latitud (rad) de la línea del cabello según el ángulo alrededor de la cabeza."""
    a = abs(math.degrees(math.atan2(sin(lon), cos(lon))))
    pts = [(0, 41), (30, 40), (55, 32), (75, 25), (98, 26), (120, 2), (150, -27), (180, -31)]
    for (a0, v0), (a1, v1) in zip(pts, pts[1:]):
        if a0 <= a <= a1:
            f = (a - a0) / (a1 - a0)
            f = f * f * (3 - 2 * f)
            return rad(v0 + (v1 - v0) * f)
    return rad(pts[-1][1])


def build_hair():
    mb = new_mb()
    W = {"Head": 1}
    segs, rows = 24, 5
    dark, light = PAL["Hair"][1], PAL["HairLight"][1]

    def hp(lon, lat, off):
        return head_pt(lon, lat, off + 0.012 * max(0.0, sin(lat)))

    grid, cols = [], []
    for j in range(segs):
        lon = 2 * pi * j / segs
        hl = hairline(lon)
        a = abs(math.degrees(math.atan2(sin(lon), cos(lon))))
        if a < 60 and j % 2 == 1:
            hl -= rad(7)                       # flequillo en picos
        col = [mb.vert(hp(lon, hl + rad(2), -0.004), W)]
        cc = [dark]
        for k in range(rows):
            lat = hl + (pi / 2 - hl) * (k / rows)
            col.append(mb.vert(hp(lon, lat, 0.022 if k else 0.018), W))
            cc.append(mixc(dark, light, bump(math.degrees(lat), 38, 78)))      # brillo en banda
        grid.append(col)
        cols.append(cc)
    top = mb.vert(hp(0, pi / 2, 0.022), W)
    for j in range(segs):
        j2 = (j + 1) % segs
        for k in range(rows):
            mb.face((grid[j][k], grid[j2][k], grid[j2][k + 1], grid[j][k + 1]), "Hair",
                    (cols[j][k], cols[j2][k], cols[j2][k + 1], cols[j][k + 1]))
        mb.face((grid[j][rows], grid[j2][rows], top), "Hair")
    # remolino rebelde en la coronilla
    tuft = Loft([dict(c=(0.01, 0.045, 1.305), rx=0.034, ry=0.030, w=W),
                 dict(c=(0.02, 0.075, 1.345), rx=0.024, ry=0.020, w=W),
                 dict(c=(0.035, 0.115, 1.360), rx=0.012, ry=0.010, w=W),
                 dict(c=(0.045, 0.140, 1.350), rx=0.002, ry=0.002, w=W)])
    mb.add_loft(tuft, "Hair", segs=6, cap0=False)
    return mb


def build_hat_palma():
    mb = new_mb()
    W = {"Head": 1}
    under = [(0.398, 1.142), (0.300, 1.160), (0.205, 1.190)]   # cara inferior del ala
    mb.add_loft(Loft([dict(c=(0, 0, z), rx=r, ry=r, w=W) for r, z in under]), "StrawDeep", segs=20,
                cap0=False, cap1=False, flip=True)
    prof = [  # (radio, z) — ala ancha y copa cónica redondeada, tejido de palma
        (0.398, 1.142), (0.410, 1.150), (0.352, 1.172),
        (0.300, 1.190), (0.262, 1.206), (0.238, 1.228), (0.225, 1.262), (0.204, 1.305),
        (0.172, 1.350), (0.132, 1.394), (0.086, 1.434), (0.040, 1.462), (0.006, 1.474),
    ]
    loft = Loft([dict(c=(0, 0, z), rx=r, ry=r, w=W) for r, z in prof])

    def mat(u, th, p):
        if u < 1.0:
            return "StrawDeep"
        if 5.0 <= u < 6.0:
            return "HatBand"
        return "Straw" if int(u) % 2 else "StrawDeep"

    v0 = len(mb.verts)
    mb.add_loft(loft, None, segs=20, cap0=False, cap1=True, matfn=mat)
    for j in range(20):               # borde del ala un poco deshilachado
        for row in (0, 1):
            v = mb.verts[v0 + row * 20 + j]
            k = 1.0 + (0.022 if j % 2 else -0.012) + 0.012 * sin(j * 2.4)
            v.x *= k
            v.y *= k
            v.z += 0.006 * sin(j * 1.7)
    mb.add_sphere((0.0, -0.236, 1.245), (0.022, 0.014, 0.022), "Jade", W, segs=6, rings=4)
    # una pluma metida en la cinta
    fb = Vector((0.215, -0.085, 1.245))
    fd = Vector((0.25, 0.35, 1.0)).normalized()
    fs = fd.cross(Vector((1, -0.4, 0))).normalized()
    feather = Loft([dict(c=fb + fd * (0.22 * f) + Vector((0.03 * f * f, 0, 0)), rx=0.034 * wd, ry=0.006, w=W,
                         side=tuple(fs)) for f, wd in ((0.0, 0.2), (0.25, 0.8), (0.55, 1.0), (0.85, 0.7), (1.0, 0.05))],
                   side=tuple(fs))
    mb.add_loft(feather, "FRed", segs=4, cap0=True, cap1=True,
                col=lambda p, u, th: mixc(PAL["FRed"][1], PAL["FYellow"][1], max(0.0, u / 4.0 - 0.45) * 1.8))
    tilt = Matrix.Translation((0, 0, 1.2)) @ Matrix.Rotation(rad(-7), 4, "X") @ Matrix.Translation((0, 0, -1.2))
    mb.transform(tilt)
    return mb


def build_hat_penacho():
    mb = new_mb()
    W = {"Head": 1}
    band_ = []
    for z, d in ((1.166, 0.0), (1.172, 0.042), (1.205, 0.047), (1.238, 0.047), (1.244, 0.0)):
        lat = math.asin((z - HC.z) / HR[2])
        band_.append(dict(c=(0, 0, z), rx=HR[0] * cos(lat) + d + 0.004, ry=HR[1] * cos(lat) + d + 0.004, w=W))
    mb.add_loft(Loft(band_), None, segs=20, cap0=False, cap1=False,
                matfn=lambda u, th, p: "HatBand" if 1.5 < u < 2.5 and int(th / (2 * pi) * 20) % 2 else "HGold")
    mb.add_sphere(head_pt(0, rad(34), 0.050), (0.036, 0.016, 0.036), "Jade", W, segs=8, rings=5)
    for s in (1, -1):
        mb.add_sphere(head_pt(s * rad(38), rad(34), 0.047), (0.018, 0.012, 0.018), "FRed", W, segs=6, rings=4)

    def feather(base, direction, length, width, c0, c1, lean):
        d = Vector(direction).normalized()
        side = Vector((d.z, 0, -d.x))
        rings = []
        for f, wd in ((0.0, 0.25), (0.25, 0.8), (0.55, 1.0), (0.85, 0.75), (1.0, 0.05)):
            c = Vector(base) + d * (length * f) + Vector((0, 1, 0)) * (lean * f * f)
            rings.append(dict(c=c, rx=width * wd, ry=0.008, w=W, side=tuple(side)))
        a, b = PAL[c0][1], PAL[c1][1]
        mb.add_loft(Loft(rings, side=tuple(side)), c0, segs=4, cap0=True, cap1=True,
                    col=lambda p, u, th: mixc(a, b, max(0.0, u / 4.0 - 0.4) * 1.7))

    n = 9                              # abanico trasero de plumas largas
    for i in range(n):
        a = rad(-78 + 156 * i / (n - 1))
        ln = 0.35 - 0.10 * abs(sin(a))
        c0, c1 = ("FGreen", "FTeal") if i % 2 == 0 else ("FRed", "FYellow")
        feather((sin(a) * 0.20, 0.035, 1.215 + cos(a) * 0.05), (sin(a), 0.16, cos(a)), ln, 0.048, c0, c1, 0.05)
    n = 8                              # hilera corta al frente
    for i in range(n):
        a = rad(-66 + 132 * i / (n - 1))
        c0, c1 = ("FYellow", "FRed") if i % 2 == 0 else ("FBlue", "FTeal")
        feather((sin(a) * 0.21, -0.005, 1.225 + cos(a) * 0.045), (sin(a), 0.02, cos(a)), 0.18, 0.038, c0, c1, 0.02)
    return mb


def build_hat_flor():
    """Flor de mayo (plumeria) con un botón, sobre la sien izquierda."""
    mb = new_mb()
    W = {"Head": 1}
    white, heart = PAL["Petal"][1], PAL["PetalHeart"][1]

    def bloom(lon, lat, size, off):
        base = head_pt(lon, lat, off)
        nrm = (head_dir(lon, lat) + Vector((0, -0.45, 0.1))).normalized()
        ex = nrm.cross(Vector((0, 0, 1))).normalized()
        ey = nrm.cross(ex)
        for i in range(5):
            a = 2 * pi * i / 5 + 0.3
            d = ex * cos(a) + ey * sin(a)
            t = d.cross(nrm)
            m = Matrix((t, d, nrm)).transposed()
            m = Matrix.Rotation(rad(22), 3, d) @ Matrix.Rotation(rad(-14), 3, t) @ m
            c = base + d * 0.043 * size + nrm * 0.008 * size
            mb.add_sphere(c, (0.027 * size, 0.046 * size, 0.008 * size), "Petal", W, segs=6, rings=4, rot=m,
                          col=lambda p, q: mixc(white, heart, min(1.0, max(0.0, (-q.y - 0.15) * 1.6))))
        mb.add_sphere(base + nrm * 0.012 * size, (0.014 * size, 0.014 * size, 0.01 * size), "PetalHeart", W,
                      segs=6, rings=4, rot=Matrix((ex, ey, nrm)).transposed())
        return base, nrm, ex, ey

    base, nrm, ex, ey = bloom(rad(58), rad(34), 1.0, 0.026)
    bloom(rad(80), rad(44), 0.55, 0.030)
    for a, ln in ((2.5, 0.075), (3.6, 0.065)):
        d = ex * cos(a) + ey * sin(a)
        t = d.cross(nrm)
        m = Matrix((t, d, nrm)).transposed()
        mb.add_sphere(base + d * 0.065 - nrm * 0.004, (0.02, ln * 0.6, 0.006), "HLeaf", W, segs=6, rings=4, rot=m)
    return mb


# ──────────────────────── Piezas del personalizador ────────────────────────
# Cada función devuelve un MeshBuilder que se exporta como malla aparte, con el nombre
# que el juego busca. Todas van pesadas al esqueleto de siempre (no hay huesos nuevos):
# los tocados a «Head», las prendas a «Chest»/«Spine»/«Hips» (y a los muslos o a los
# brazos donde tienen que acompañarlos), lo que cuelga del cinto a «Bag» y lo que
# cuelga del cuello a «Amulet», que ya se balancean en todas las animaciones.

def body_lofts():
    """Túnica, jubón y faja, con su tramo de alturas: lo que hay debajo de una prenda."""
    return [(tunic_loft(), 0.28, 0.85), (jub_loft(), 0.698, 0.852), (sash_loft(), 0.508, 0.602)]


def face_out(mb, idx, key, cols=None, away=None, toward=None):
    """Añade una cara orientada hacia fuera del eje del cuerpo, lejos del punto `away`
    o hacia la dirección `toward`."""
    p = [mb.verts[i] for i in idx]
    n = Vector((0.0, 0.0, 0.0))
    for k in range(1, len(p) - 1):
        n += (p[k] - p[0]).cross(p[k + 1] - p[0])
    c = sum(p, Vector((0.0, 0.0, 0.0))) / len(p)
    if toward is not None:
        out = Vector(toward)
    elif away is not None:
        out = c - Vector(away)
    else:
        out = Vector((c.x, c.y, 0.0))
    idx = list(idx)
    cols = list(cols) if cols else None
    if n.dot(out) < 0.0:
        idx.reverse()
        if cols:
            cols.reverse()
    mb.face(idx, key, cols)


def blade(mb, base, d, side, length, width, key, w, tip=None, lean=(0.0, 0.0, 0.0), thick=0.006,
          prof=((0.0, 0.30), (0.32, 1.0), (0.70, 0.78), (1.0, 0.05)), tip0=0.45):
    """Pluma, hoja o punta de tela: loft fino de cuatro lados (24 triángulos con el
    perfil por omisión). `tip` es la clave del color hacia la punta, que empieza a
    notarse a la fracción `tip0` del largo."""
    base, d, lean, side = Vector(base), Vector(d).normalized(), Vector(lean), Vector(side)
    rings = [dict(c=base + d * (length * f) + lean * (f * f), rx=width * wd, ry=thick, w=w, side=tuple(side))
             for f, wd in prof]
    a, b = PAL[key][1], PAL[tip or key][1]
    n = len(prof) - 1.0
    mb.add_loft(Loft(rings, side=tuple(side)), key, segs=4, cap0=False, cap1=False,
                col=lambda p, u, th: mixc(a, b, max(0.0, u / n - tip0) / max(1e-3, 1.0 - tip0) * 1.05))


def leaf2(mb, base, d, nrm, length, width, key, w, tip=None, fold=0.006):
    """Hoja plana de dos caras (4 triángulos): rombo con el ancho máximo al 42 %,
    doblado por el nervio. `nrm` es hacia donde mira el haz."""
    base, d, nrm = Vector(base), Vector(d).normalized(), Vector(nrm)
    nrm = (nrm - d * nrm.dot(d)).normalized()
    t = d.cross(nrm)
    pts = [base, base + d * (length * 0.42) + t * (width * 0.5) - nrm * fold, base + d * length,
           base + d * (length * 0.42) - t * (width * 0.5) - nrm * fold]
    c0, c1 = PAL[key][1], PAL[tip or key][1]
    cols = [c0, mixc(c0, c1, 0.5), c1, mixc(c0, c1, 0.5)]
    for back in (False, True):
        v = [mb.vert(q, w) for q in pts]
        for tri in ((0, 1, 2), (0, 2, 3)):
            ids, cc = [v[i] for i in tri], [cols[i] for i in tri]
            if back:
                ids.reverse()
                cc.reverse()
            mb.face(ids, key, cc)


def zig_band(mb, P, rows, n, th0, strips, wfn, under=None, gap=0.003):
    """Franjas de bordado geométrico alrededor de una prenda, hechas con la propia malla.
    `P(row, θ)` da el punto; `rows` = [(row, medio_paso)]: las filas con medio_paso van
    desfasadas media columna. Entre dos filas con el mismo desfase sale una franja lisa
    (`strips[k]` = clave o fn(j) -> clave); entre dos con distinto desfase, una hilera de
    picos (`strips[k]` = (fn(j) -> clave del pico con la base en la fila sin desfase,
    clave del fondo)). Dos hileras de picos enfrentadas hacen rombos.
    `under(row, θ)` es el radio (en planta) de la prenda que queda debajo: con pocas
    columnas, el tramo recto entre dos vértices ataja por dentro de las esquinas, así
    que cada fila se separa lo que haga falta para que su punto medio libre `gap`."""
    ids = []
    for row, half in rows:
        pts = [P(row, th0 + 2 * pi * (j + (0.5 if half else 0.0)) / n) for j in range(n)]
        if under:
            push = [0.0] * n
            for j in range(n):
                j2 = (j + 1) % n
                m = (pts[j] + pts[j2]) * 0.5
                need = under(row, math.atan2(m.y, m.x)) + gap - math.hypot(m.x, m.y)
                if need > 0.0:
                    push[j], push[j2] = max(push[j], need), max(push[j2], need)
            pts = [q + Vector((q.x, q.y, 0)).normalized() * (1.1 * k) for q, k in zip(pts, push)]
        ids.append([mb.vert(q, wfn(row, q)) for q in pts])
    for k, spec in enumerate(strips):
        a, b = ids[k], ids[k + 1]
        ha, hb = rows[k][1], rows[k + 1][1]
        for j in range(n):
            j2 = (j + 1) % n
            if ha == hb:
                face_out(mb, (a[j], a[j2], b[j2], b[j]), spec(j) if callable(spec) else spec)
                continue
            peak, ground = spec
            base, tips = (a, b) if not ha else (b, a)        # base: fila sin desfase
            face_out(mb, (base[j], base[j2], tips[j]), peak(j))
            face_out(mb, (tips[j], tips[j2], base[j2]), ground)


# ── tocados nuevos ───────────────────────────────────────────────────────────

def _head_ring(z, d):
    """Radios de un aro horizontal a la altura z, separado d de la cabeza."""
    lat = math.asin((z - HC.z) / HR[2])
    return HR[0] * cos(lat) + d, HR[1] * cos(lat) + d


def build_hat_plumas():
    """Diadema baja: cinta tejida y una vuelta de plumas cortas."""
    mb = new_mb()
    W = {"Head": 1}
    band_ = []
    for z, d in ((1.170, 0.006), (1.193, 0.046), (1.216, 0.006)):
        rx, ry = _head_ring(z, d)
        band_.append(dict(c=(0, 0, z), rx=rx, ry=ry, w=W))
    mb.add_loft(Loft(band_), None, segs=16, cap0=False, cap1=False,
                matfn=lambda u, th, p: "FTeal" if int(th / (2 * pi) * 16 + 0.25) % 2 else "FWhite")
    rx, ry = _head_ring(1.196, 0.034)
    n = 12
    for k in range(n):
        lon = 2 * pi * (k + 0.5) / n
        out = Vector((sin(lon), -cos(lon), 0.0))
        front = 0.5 * (cos(lon) + 1.0)
        c0, c1 = ("FWhite", "FRed") if k % 2 == 0 else ("FTeal", "FBlue")
        blade(mb, (out.x * rx, out.y * ry, 1.196), out * 0.40 + Vector((0, 0, 1.0)), (cos(lon), sin(lon), 0.0),
              0.112 + 0.034 * front, 0.046, c0, W, tip=c1, lean=out * 0.024, thick=0.007, tip0=0.30)
    return mb


def build_hat_panuelo():
    """Pañuelo doblado en banda ancha, anudado atrás, con dos puntas sueltas. La
    coronilla queda al aire: el remolino del cabello asoma por arriba."""
    mb = new_mb()
    W = {"Head": 1}

    def hp(lon, lat, off):                 # como el cabello: un poco más alto arriba
        return head_pt(lon, lat, off + 0.012 * max(0.0, sin(lat)))

    def lat_lo(lon):
        c = cos(lon)
        return rad(43 - 14 * (1 - c)) if c >= 0 else rad(29 - 24 * (-c) ** 1.5)

    segs = 20
    cols = []
    for j in range(segs):
        lon = 2 * pi * j / segs
        lo = lat_lo(lon)
        wd = rad(31 + 5 * (1 - cos(lon)) / 2)
        cols.append([mb.vert(hp(lon, lo, 0.010), W), mb.vert(hp(lon, lo + 0.2 * wd, 0.034), W),
                     mb.vert(hp(lon, lo + 0.8 * wd, 0.035), W), mb.vert(hp(lon, lo + wd, 0.012), W)])
    for j in range(segs):
        a, b = cols[j], cols[(j + 1) % segs]
        for k, key in enumerate(("ClothMid", "Cloth", "ClothMid")):
            face_out(mb, (a[k], b[k], b[k + 1], a[k + 1]), key, away=HC)
    # nudo en la nuca, algo a la derecha, y dos puntas que caen
    lon = rad(180 + 12)
    kc_ = hp(lon, lat_lo(lon) + rad(9), 0.050)
    out = head_dir(lon, rad(8))
    tang = Vector((cos(lon), sin(lon), 0.0))
    mb.add_sphere(kc_, (0.030, 0.027, 0.027), "Cloth", W, segs=6, rings=4)
    for sgn, ln in ((1, 0.135), (-1, 0.105)):
        d = tang * (0.22 * sgn) + out * 0.40 + Vector((0, 0, -1.0))
        blade(mb, kc_ + out * 0.006, d, tang, ln, 0.050, "Cloth", W, tip="ClothDeep", lean=out * 0.02, thick=0.008,
              prof=((0.0, 0.35), (0.40, 0.75), (0.78, 1.0), (1.0, 0.10)))
    return mb


def build_hat_hojas():
    """Corona de la selva: aro de bejuco con hojas, florecillas y bayas."""
    mb = new_mb()
    W = {"Head": 1}

    def ring_pt(lon, off=0.040):
        return head_pt(lon, rad(36 + 6 * cos(lon)), off)

    n = 16                                  # aro de bejuco (sección triangular)
    rings = []
    for j in range(n + 1):
        lon = pi + 2 * pi * j / n           # la unión queda en la nuca
        rings.append(dict(c=ring_pt(lon, 0.043), rx=0.014, ry=0.014, w=W))
    mb.add_loft(Loft(rings, side=(0, 0, 1)), "Twig", segs=3, cap0=False, cap1=False)

    up = Vector((0, 0, 1.0))
    n = 18
    for k in range(n):
        lon = 2 * pi * (k + 0.5) / n
        out = head_dir(lon, rad(20))
        back = Vector((cos(lon), sin(lon), 0.0)) * (1.0 if sin(lon) >= 0 else -1.0)   # hacia la nuca
        if k % 2 == 0:
            d, ln, keys = back * 0.62 + up * 0.62 + out * 0.30, 0.125, ("HLeaf", "HLeafLight")
        else:
            d, ln, keys = back * 0.70 - up * 0.26 + out * 0.50, 0.098, ("HLeafDeep", "HLeaf")
        leaf2(mb, ring_pt(lon, 0.050), d, out + up * 0.25, ln, 0.058, keys[0], W, tip=keys[1], fold=0.009)
    for i, (deg, key) in enumerate(((-24, "FlPink"), (22, "FWhite"), (68, "FlViolet"), (-66, "FWhite"),
                                    (126, "FlPink"), (-124, "FlViolet"))):
        lon = rad(deg)                      # florecillas de cinco pétalos
        nrm = (head_dir(lon, rad(26)) + up * 0.15).normalized()
        ex = nrm.cross(up).normalized()
        ey = nrm.cross(ex)
        c = ring_pt(lon, 0.064)
        heart = mb.vert(c + nrm * 0.011, W)
        rim = []
        for q in range(10):
            a = 2 * pi * q / 10 + 0.3 * i
            r = 0.041 if q % 2 == 0 else 0.018
            rim.append(mb.vert(c + (ex * cos(a) + ey * sin(a)) * r, W))
        pk, hk = PAL[key][1], PAL["PetalHeart"][1]
        for q in range(10):
            ca, cb = (pk, mixc(pk, hk, 0.6)) if q % 2 == 0 else (mixc(pk, hk, 0.6), pk)
            face_out(mb, (heart, rim[q], rim[(q + 1) % 10]), key, (hk, ca, cb), toward=nrm)
    for deg in (-46, 44, 98, -96):          # bayas rojas
        lon = rad(deg)
        mb.add_sphere(ring_pt(lon, 0.058) + Vector((0, 0, -0.016)), 0.017, "Berry", W, segs=5, rings=3)
    return mb


# ── vestimenta sobre la túnica ───────────────────────────────────────────────

# Capa: filas de arriba abajo (z, rx, ry, alza). El «alza» levanta la fila sobre los
# hombros (a los lados) para que pase por encima del arranque de las mangas.
CAPA_ROWS = [(0.860, 0.112, 0.084, 0.004), (0.853, 0.162, 0.124, 0.022), (0.838, 0.228, 0.162, 0.040),
             (0.806, 0.272, 0.180, 0.034), (0.764, 0.292, 0.188, 0.012)]
CAPA_HEM = [(0.5, 0.300, 0.194), (1.0, 0.305, 0.198)]        # fracción hacia el borde, rx, ry


def _capa_zbot(phi):
    """Altura del borde de la capa: más larga por la espalda (phi = 180°)."""
    return 0.744 - 0.082 * (0.5 * (1 - cos(phi))) ** 1.6


def _capa_pt(row, phi):
    """Punto de la fila `row` de la capa; phi = 0 al frente, 90° a la izquierda, 180° atrás."""
    if row < len(CAPA_ROWS):
        z, rx, ry, lift = CAPA_ROWS[row]
        z += lift * sin(phi) ** 2
    else:
        f, rx, ry = CAPA_HEM[row - len(CAPA_ROWS)]
        z0 = CAPA_ROWS[-1][0] + CAPA_ROWS[-1][3] * sin(phi) ** 2
        z = z0 + (_capa_zbot(phi) - z0) * f
    th = phi - pi / 2
    c, s_ = cos(th), sin(th)
    r = (abs(c / rx) ** 3.2 + abs(s_ / ry) ** 3.2) ** (-1.0 / 3.2)
    return Vector((r * c, r * s_, z))


def _capa_w(p):
    def ss(x):
        x = min(1.0, max(0.0, x))
        return x * x * (3 - 2 * x)
    a = 0.88 * ss((abs(p.x) - 0.115) / 0.09)                 # sobre el hombro, con el brazo
    s_ = 0.5 * min(1.0, max(0.0, (0.74 - p.z) / 0.08))
    w = {"Chest": (1 - a) * (1 - s_), "Spine": (1 - a) * s_, ("UpperArm_L" if p.x > 0 else "UpperArm_R"): a}
    return {b: v for b, v in w.items() if v > 1e-4}


def build_outfit_capa():
    """Capa corta sobre los hombros, más larga por la espalda, abierta en pico por
    delante (ahí cuelga el amuleto) y cerrada con un broche."""
    mb = new_mb()
    rows = len(CAPA_ROWS) + len(CAPA_HEM)

    def phi0(row):                         # semiángulo de la abertura delantera en esa fila
        gap = 0.006 + 0.85 * max(0.0, 0.832 - _capa_pt(row, 0.0).z)
        lo, hi = 0.0, rad(70)
        for _ in range(30):
            mid = 0.5 * (lo + hi)
            if _capa_pt(row, mid).x < gap:
                lo = mid
            else:
                hi = mid
        return 0.5 * (lo + hi)

    N = 18
    grid = []
    for k in range(rows):
        p0 = phi0(k)
        row = []
        for j in range(N + 1):
            p = _capa_pt(k, p0 + (2 * pi - 2 * p0) * j / N)
            if k == rows - 1:
                p.z += 0.006 if j % 2 else -0.004                  # borde en ondas
            row.append(mb.vert(p, _capa_w(p)))
        grid.append(row)
    keys = ("ClothMid", "Cloth", "Cloth", "Cloth", "Cloth", "ClothMid")
    for k in range(rows - 1):
        for j in range(N):
            face_out(mb, (grid[k][j], grid[k][j + 1], grid[k + 1][j + 1], grid[k + 1][j]), keys[k])
    # forro: una vuelta hacia dentro en el borde de abajo y en los dos de la abertura
    inner = []
    for j in range(N + 1):
        p = mb.verts[grid[-1][j]]
        q = Vector((p.x * 0.84, p.y * 0.84, p.z + 0.024))
        inner.append(mb.vert(q, _capa_w(q)))
    for j in range(N):
        face_out(mb, (grid[-1][j], grid[-1][j + 1], inner[j + 1], inner[j]), "ClothDark", toward=(0, 0, -1))
    for j, sx in ((0, -1.0), (N, 1.0)):
        edge = []
        for k in range(1, rows):
            p = mb.verts[grid[k][j]]
            q = Vector((p.x, p.y * 0.86, p.z))
            edge.append(mb.vert(q, _capa_w(q)))
        for k in range(1, rows - 1):
            face_out(mb, (grid[k][j], grid[k + 1][j], edge[k], edge[k - 1]), "ClothDark", toward=(sx, 0, 0))
    # broche
    bp = _capa_pt(2, 0.0) + Vector((0, -0.004, -0.010))
    CH = {"Chest": 1}
    mb.add_sphere(bp, (0.023, 0.009, 0.023), "Gold", CH, segs=8, rings=4)
    mb.add_sphere(bp + Vector((0, -0.007, 0)), (0.012, 0.006, 0.012), "Turq", CH, segs=5, rings=3)
    return mb


def build_outfit_faja():
    """Faja ancha tejida, con nudo y puntas con flecos al costado, y un delantal corto
    bordado por delante. Tapa la faja de siempre."""
    mb = new_mb()
    tunic = tunic_loft()
    SW = {"Hips": 0.6, "Spine": 0.4}

    def P(row, th):
        z, d = row
        rx, ry = tun_r(z)
        c, s_ = cos(th), sin(th)
        r = (abs(c / (rx + d)) ** 3.0 + abs(s_ / (ry + d)) ** 3.0) ** (-1.0 / 3.0)
        return Vector((r * c, r * s_, z))

    zig_band(mb, P, [((0.487, 0.004), False), ((0.513, 0.0215), False), ((0.599, 0.0215), True),
                     ((0.625, 0.004), True)], 16, KNOT_TH,
             ["ClothMid", (lambda j: "Cloth", "ClothDeep"), "ClothMid"], lambda row, p: SW,
             under=lambda row, th: math.hypot(*P((row[0], min(row[1], 0.016)), th).xy), gap=0.004)
    # nudo y puntas (cubren los de la faja de siempre)
    kp = P((0.556, 0.0215), KNOT_TH)
    kn = Vector((kp.x, kp.y, 0)).normalized()
    tang = Vector((-kn.y, kn.x, 0))
    mb.add_sphere(kp + kn * 0.016, (0.046, 0.046, 0.050), "Cloth", SW, segs=6, rings=4)
    for spread, length in ((-0.046, 0.215), (0.052, 0.175)):
        base = kp + kn * 0.034
        tail = []
        for i in range(5):
            f = i / 4.0
            c = base + tang * (spread * f) + kn * (0.030 * f) + Vector((0, 0, -length * f - 0.01))
            tail.append(dict(c=c, rx=0.016 + 0.022 * min(1.0, f * 2.5), ry=0.008,
                             w={"Hips": 1} if i == 0 else {"SashTail": 1}, side=tuple(tang)))
        mb.add_loft(Loft(tail, side=tuple(tang)), None, segs=4, cap0=False, cap1=True,
                    matfn=lambda u, th, p: "ClothDeep" if u > 3.0 else "Cloth")
        end = Vector(tail[-1]["c"])
        for j in (-1, 0, 1):          # flecos
            leaf2(mb, end + tang * (j * 0.024), tang * (j * 0.18) + Vector((0, 0, -1.0)), kn, 0.046, 0.016,
                  "ClothMid", {"SashTail": 1}, fold=0.0)
    # delantal corto
    zs = (0.505, 0.462, 0.420, 0.384, 0.356)
    vs = (-0.56, -0.28, 0.0, 0.28, 0.56)
    grid = []
    for z in zs:
        u = u_at_z(tunic, z)
        row = []
        for i, v in enumerate(vs):
            p = tunic.point(u, face_theta(tunic, u, "front", v))
            p = p + Vector((p.x, p.y, 0)).normalized() * (0.004 if i in (0, 4) else 0.013)
            row.append(mb.vert(p, skirt_weights(tunic.weights(u), p)))
        grid.append(row)
    check = ("Pink", "Yellow", "Turq", "Pink")
    for k in range(4):
        for i in range(4):
            q = (grid[k][i], grid[k][i + 1], grid[k + 1][i + 1], grid[k + 1][i])
            if k < 2 and i in (1, 2):
                # rombo central: los cuatro cuadros que tocan el centro se parten hacia él
                corner = q[(2 if k == 0 else 1) if i == 1 else (3 if k == 0 else 0)]
                o = list(q).index(corner)
                r_ = [q[(o + s) % 4] for s in range(4)]
                face_out(mb, (r_[0], r_[1], r_[3]), "Turq")
                face_out(mb, (r_[1], r_[2], r_[3]), "Cloth")
            else:
                face_out(mb, q, "Cloth" if k < 2 else (check[i] if k == 2 else "Thread"))
    for i in range(4):                # fleco del delantal: dos picos por cuadro
        a, b = mb.verts[grid[4][i]], mb.verts[grid[4][i + 1]]
        m = (a + b) * 0.5
        wa = mb.weights[grid[4][i]]
        vm = mb.vert(m, wa)
        for p0, p1 in ((grid[4][i], vm), (vm, grid[4][i + 1])):
            tip = (mb.verts[p0] + mb.verts[p1]) * 0.5 + Vector((0, 0, -0.026))
            face_out(mb, (p0, p1, mb.vert(tip, wa)), "ClothMid")
    return mb


def build_outfit_bordado():
    """Pechera y bajo de bordado geométrico: rombos de colores entre dos hilos, sobre
    tela del color secundario. Dibujo propio, hecho con la malla (dos hileras de picos)."""
    mb = new_mb()
    jub, tunic = jub_loft(), tunic_loft()
    gems = ("Pink", "Yellow", "Turq", "Red")

    def chest(u, th):
        p = jub.point(u, th)
        return p + Vector((p.x, p.y, 0)).normalized() * 0.0035 + Vector((0, 0, -0.004 if u == 0.0 else 0.0))

    n = 20
    zig_band(mb, chest, [(0.0, True), (1.0, True), (1.95, False), (3.0, True), (3.85, True)], n,
             -pi / 2 - pi / n, ["Thread", (lambda j: gems[j % 4], "Cloth"), (lambda j: gems[j % 4], "Cloth"), "Cloth"],
             lambda u, p: {"Chest": 1}, under=lambda u, th: math.hypot(*jub.point(u, th).xy))

    def hem(z, th):
        p = tunic.point(u_at_z(tunic, z), th)
        return p + Vector((p.x, p.y, 0)).normalized() * 0.0045

    n = 24
    zig_band(mb, hem, [(0.2795, True), (0.297, True), (0.345, False), (0.393, True), (0.409, True)], n,
             -pi / 2 - pi / n, ["Thread", (lambda j: gems[(j + 2) % 4], "Cloth"), (lambda j: gems[(j + 2) % 4], "Cloth"),
                                "Yellow"],
             lambda z, p: skirt_weights(tunic.weights(u_at_z(tunic, z)), p),
             under=lambda z, th: math.hypot(*tunic.point(u_at_z(tunic, z), th).xy))
    return mb


# ── accesorios ───────────────────────────────────────────────────────────────

def _bandolera(mb, lofts, key, edge, front, back, rx=0.0045, ry=0.013, segs=4, n=9):
    """Correa cruzada del hombro izquierdo a la cadera derecha, pegada a la ropa.
    `front` y `back` = (ángulo final, exponente, altura final) de cada mitad."""
    a, b = PAL[key][1], PAL[edge][1]
    for th0, (th1, ex, z1) in ((rad(-28), front), (rad(30), back)):
        ring = []
        for i in range(n):
            g = i / (n - 1.0)
            z = 0.838 - (0.838 - z1) * g
            p, d = outer_point(lofts, z, th0 + (th1 - th0) * g ** ex, 0.007)
            ring.append(dict(c=p, rx=rx, ry=ry, w=body_weights(z), side=tuple(d)))
        mb.add_loft(Loft(ring), key, segs=segs, cap0=False, cap1=False,
                    col=lambda p, u, th: b if abs(sin(th)) > 0.8 else a)


def build_acc_morral():
    """Sabucán (morral de henequén) cruzado: la correa lleva el color secundario."""
    mb = new_mb()
    lofts = body_lofts()
    _bandolera(mb, lofts, "Strap", "StrapEdge", (rad(-178), 0.9, 0.493), (BAG_TH, 0.8, 0.493))
    bp, bd_ = outer_point(lofts, 0.47, BAG_TH, 0.03)
    bt = Vector((-bd_.y, bd_.x, 0))
    BW = {"Bag": 1}
    bag = Loft([dict(c=bp + Vector((0, 0, 0.045)), rx=0.045, ry=0.016, w=BW),
                dict(c=bp + Vector((0, 0, 0.02)), rx=0.062, ry=0.030, w=BW),
                dict(c=bp + Vector((0, 0, -0.03)), rx=0.066, ry=0.034, w=BW),
                dict(c=bp + Vector((0, 0, -0.062)), rx=0.056, ry=0.027, w=BW),
                dict(c=bp + Vector((0, 0, -0.074)), rx=0.02, ry=0.01, w=BW)], side=tuple(bt))

    def bag_mat(u, th, p):
        if 1.5 < u < 2.0:
            return "Thread"
        if 2.5 < u < 3.0:
            return "JadeDull"
        return "Henequen"

    mb.add_loft(bag, None, segs=10, sub=2, matfn=bag_mat)
    mb.add_sphere(bp + bd_ * 0.032 + Vector((0, 0, 0.012)), (0.012, 0.012, 0.012), "Gold", BW, segs=5, rings=3)
    for j in (-1, 0, 1):
        fr = Loft([dict(c=bp + bt * (j * 0.028) + Vector((0, 0, -0.066)), rx=0.007, ry=0.006, w=BW),
                   dict(c=bp + bt * (j * 0.034) + Vector((0, 0, -0.108)), rx=0.004, ry=0.004, w=BW)], side=tuple(bt))
        mb.add_loft(fr, "HenequenDeep", segs=4, cap0=False)
    return mb


def build_acc_sonaja():
    """Sonaja de jícara colgada del cinto por el mango, con dos plumitas."""
    mb = new_mb()
    lofts = body_lofts()
    bp, bd_ = outer_point(lofts, 0.425, BAG_TH, 0.072)
    bt = Vector((-bd_.y, bd_.x, 0))
    BW = {"Bag": 1}

    def gourd(d):
        if d.z < -0.55:
            return "GourdDeep"
        if abs(d.z) < 0.5:                 # cenefa grabada: ajedrezado en dos hileras
            seg = int((math.atan2(d.y, d.x) % (2 * pi)) / (2 * pi) * 8)
            return "GourdLight" if (seg + (1 if d.z > 0 else 0)) % 2 else "Gourd"
        return "Gourd"

    mb.add_sphere(bp, (0.056, 0.056, 0.060), None, BW, segs=8, rings=6, matfn=gourd)
    top = bp + Vector((0, 0, 0.050))
    mb.add_loft(Loft([dict(c=top, rx=0.025, ry=0.025, w=BW), dict(c=top + Vector((0, 0, 0.013)), rx=0.016, ry=0.016, w=BW)]),
                "Leather", segs=6, cap0=False, cap1=False)
    end = top + Vector((0, 0, 0.092)) - bd_ * 0.014
    mb.add_loft(Loft([dict(c=top + Vector((0, 0, 0.008)), rx=0.015, ry=0.015, w=BW),
                      dict(c=top + Vector((0, 0, 0.048)) - bd_ * 0.006, rx=0.013, ry=0.013, w=BW),
                      dict(c=end, rx=0.0145, ry=0.0145, w=BW)]), "Wood", segs=5, cap0=False, cap1=True)
    tie, _d = outer_point(lofts, 0.592, BAG_TH, 0.006)
    mb.add_loft(Loft([dict(c=end + Vector((0, 0, -0.012)), rx=0.0045, ry=0.0045, w=BW),
                      dict(c=end.lerp(tie, 0.5) + bd_ * 0.008, rx=0.0045, ry=0.0045, w={"Bag": 0.5, "Hips": 0.5}),
                      dict(c=tie, rx=0.0045, ry=0.0045, w={"Hips": 1})], side=tuple(bt)), "Cord", segs=3,
                cap0=False, cap1=False)
    for sg in (1, -1):
        blade(mb, bp + Vector((0, 0, -0.054)), bt * (0.45 * sg) + bd_ * 0.25 + Vector((0, 0, -1.0)), bt, 0.085, 0.032,
              "PlumeA", BW, tip="PlumeB", thick=0.006, tip0=0.3)
    return mb


def build_acc_caracol():
    """Caracol marino colgado a la espalda, a la altura de la cintura, de un cordón
    cruzado. Va apoyado en la ropa: cada anillo se separa lo justo según su grosor."""
    mb = new_mb()
    lofts = body_lofts()
    tunic = [(tunic_loft(), 0.28, 0.85)]
    c0, cd = outer_point(tunic, 0.550, rad(110), 0.0)
    ct = Vector((-cd.y, cd.x, 0))                           # hacia la derecha del alux
    ax = (ct * 0.74 + Vector((0, 0, -0.67))).normalized()   # de la espira (arriba) al canal (abajo)
    sd = ax.cross(cd).normalized()
    W = {"Hips": 0.5, "Spine": 0.5}
    sh, pk, rose, deep = (PAL[k][1] for k in ("Shell", "ShellPink", "ShellRose", "ShellDeep"))
    tan = mixc(deep, PAL["Leather"][1], 0.35)
    # (posición en el eje, radio, color): la espira sube en terrazas, con el surco tostado
    prof = [(-0.130, 0.004, deep), (-0.112, 0.014, tan), (-0.094, 0.019, sh), (-0.086, 0.031, tan),
            (-0.064, 0.037, sh), (-0.056, 0.051, tan), (-0.026, 0.059, sh), (-0.016, 0.074, mixc(sh, pk, 0.5)),
            (0.030, 0.070, sh), (0.078, 0.045, mixc(sh, pk, 0.4)), (0.112, 0.022, pk), (0.128, 0.008, mixc(pk, deep, 0.4))]

    def on_back(s_, r):
        """Centro del anillo: sobre la faja (la de siempre o la ancha), sin hundirse."""
        q = c0 + ax * s_
        return outer_point(tunic, q.z, math.atan2(q.y, q.x), 0.026 + r * 0.62)[0]

    shell = Loft([dict(c=on_back(s_, r), rx=r, ry=r * 0.62, w=W) for s_, r, _c in prof], side=tuple(sd))
    mid = on_back(0.03, 0.07)

    def shell_col(p, u, th):
        i = min(int(u), len(prof) - 2)
        c = mixc(prof[i][2], prof[i + 1][2], u - i)
        out = (p - mid).dot(cd)
        if u > 6.6 and out > 0.0:                                    # boca rosada, hacia fuera
            c = mixc(c, rose, min(1.0, out / 0.02) * min(1.0, (u - 6.6) / 0.6) * max(0.0, 1.0 - abs(cos(th)) * 1.1))
        return c

    mb.add_loft(shell, "Shell", segs=8, cap0=False, cap1=True, col=shell_col)
    tip, lip = c0 + ax * -0.122, c0 + ax * 0.118
    th_tip = math.atan2(tip.y, tip.x)
    th_lip = math.atan2(lip.y, lip.x) - 2 * pi
    _bandolera(mb, lofts, "Cord", "Cord", (th_lip, 0.9, lip.z + 0.012), (th_tip, 0.8, tip.z - 0.006), rx=0.004,
               ry=0.0065, segs=3, n=10)
    return mb


def build_acc_farol():
    """Farolito de luciérnagas colgado del cinto: jaula de madera, techo de palma y luz."""
    mb = new_mb()
    lofts = body_lofts()
    bp, bd_ = outer_point(lofts, 0.415, BAG_TH, 0.074)
    bt = Vector((-bd_.y, bd_.x, 0))
    BW = {"Bag": 1}
    prof = [(-0.058, 0.026), (-0.051, 0.042), (-0.003, 0.051), (0.043, 0.042), (0.050, 0.028)]
    body = Loft([dict(c=bp + Vector((0, 0, z)), rx=r, ry=r, w=BW) for z, r in prof])
    mb.add_loft(body, None, segs=6, matfn=lambda u, th, p: "Glow" if 1.0 < u < 3.0 else "Wood", capmat=("Wood", "Wood"))
    for k in range(6):                     # barrotes en las aristas
        a = 2 * pi * k / 6
        d = Vector((cos(a), sin(a), 0))
        mb.add_loft(Loft([dict(c=bp + d * (r + 0.002) + Vector((0, 0, z)), rx=0.0065, ry=0.0065, w=BW)
                          for z, r in prof[1:4]]), "WoodDeep", segs=3, cap0=False, cap1=False)
    roof = Loft([dict(c=bp + Vector((0, 0, 0.047)), rx=0.064, ry=0.064, w=BW),
                 dict(c=bp + Vector((0, 0, 0.070)), rx=0.037, ry=0.037, w=BW),
                 dict(c=bp + Vector((0, 0, 0.096)), rx=0.005, ry=0.005, w=BW)])
    hq, hd = PAL["Henequen"][1], PAL["HenequenDeep"][1]
    mb.add_loft(roof, "Henequen", segs=6, cap0=True, cap1=False, capmat=("WoodDeep", None),
                col=lambda p, u, th: mixc(hd, hq, min(1.0, u / 1.2)))
    tie, _d = outer_point(lofts, 0.588, BAG_TH, 0.006)
    top = bp + Vector((0, 0, 0.094))
    mb.add_loft(Loft([dict(c=top, rx=0.0045, ry=0.0045, w=BW),
                      dict(c=top.lerp(tie, 0.5) + bd_ * 0.006, rx=0.0045, ry=0.0045, w={"Bag": 0.5, "Hips": 0.5}),
                      dict(c=tie, rx=0.0045, ry=0.0045, w={"Hips": 1})], side=tuple(bt)), "Cord", segs=3,
                cap0=False, cap1=False)
    for off in (bd_ * 0.080 + Vector((0, 0, 0.040)), bt * 0.078 + bd_ * 0.02 + Vector((0, 0, -0.024)),
                bt * -0.070 + bd_ * 0.03 + Vector((0, 0, 0.074))):     # tres luciérnagas alrededor
        mb.add_sphere(bp + off, 0.010, "Glow", BW, segs=4, rings=2)
    return mb


# ── amuletos ─────────────────────────────────────────────────────────────────

AMULET_AT = Vector((0.0, -0.163, 0.752))      # donde cuelga el colgante, sobre el pecho


def _cordon(mb, key, segs=4, end=(0.006, -0.160, 0.776), r=0.0055):
    """Cordón al cuello: sale de debajo de la cabeza por los hombros y baja al pecho."""
    for s in (1, -1):
        pts = [(0.0, 0.085, 0.862), (0.070 * s, 0.050, 0.860), (0.112 * s, -0.020, 0.858),
               (0.085 * s, -0.098, 0.846), (0.045 * s, -0.150, 0.812), (end[0] * s, end[1], end[2])]
        cord = Loft([dict(c=p, rx=r, ry=r, w={"Chest": 1} if i < 4 else {"Chest": 0.4, "Amulet": 0.6})
                     for i, p in enumerate(pts)], side=(0, 0, 1))
        mb.add_loft(cord, key, segs=segs, cap0=False, cap1=False)


def build_amu_jade():
    """Amuleto de jade: disco con aro dorado y dos cuentas (el de siempre)."""
    mb = new_mb()
    pend = AMULET_AT
    _cordon(mb, "Cord")
    AM = {"Amulet": 1}
    mb.add_sphere(pend, (0.036, 0.011, 0.036), "Gold", AM, segs=10, rings=4)
    mb.add_sphere(pend + Vector((0, -0.006, 0)), (0.026, 0.010, 0.026), "Jade", AM, segs=8, rings=4)
    mb.add_sphere(pend + Vector((0, -0.013, 0)), (0.008, 0.005, 0.008), "Gold", AM, segs=5, rings=3)
    for dx in (-0.016, 0.016):        # dos cuentas que flanquean el disco
        mb.add_sphere(pend + Vector((dx, 0.004, 0.036)), 0.008, "Thread", AM, segs=5, rings=3)
    return mb


def build_amu_concha():
    """Concha de abanico en un cordón de henequén, con tres cuentas."""
    mb = new_mb()
    AM = {"Amulet": 1}
    _cordon(mb, "Henequen", segs=3, end=(0.004, -0.160, 0.792))
    apex = Vector((0.0, -0.163, 0.790))
    R, n = 0.062, 8
    sh, pk, deep = (PAL[k][1] for k in ("CoralLight", "Coral", "CoralDeep"))
    va = mb.vert(apex + Vector((0, -0.004, 0)), AM)
    mid, rim, cm, cr = [], [], [], []
    for i in range(n + 1):
        a = rad(-68 + 136 * i / n)
        dx, dz = sin(a), -cos(a)
        rr = R * (1.0 if i % 2 == 0 else 0.92) * (0.90 + 0.10 * cos(a))
        mid.append(mb.vert(apex + Vector((dx * R * 0.52, -0.012, dz * R * 0.52)), AM))
        rim.append(mb.vert(apex + Vector((dx * rr, -0.003, dz * rr)), AM))
        cm.append(mixc(sh, pk, 0.25) if i % 2 == 0 else pk)           # costillas
        cr.append(mixc(sh, pk, 0.6) if i % 2 == 0 else mixc(pk, deep, 0.22))
    behind = apex + Vector((0, 0.05, -0.03))
    for i in range(n):
        face_out(mb, (va, mid[i], mid[i + 1]), "Coral", (deep, cm[i], cm[i + 1]), away=behind)
        face_out(mb, (mid[i], rim[i], rim[i + 1], mid[i + 1]), "Coral", (cm[i], cr[i], cr[i + 1], cm[i + 1]), away=behind)
    vb = mb.vert(apex + Vector((0, 0.002, 0)), AM)                     # dorso liso
    for i in range(n):
        face_out(mb, (vb, rim[i], rim[i + 1]), "CoralDeep", toward=(0, 1, 0))
    mb.add_sphere(apex + Vector((0, -0.003, 0.006)), 0.0095, "Turq", AM, segs=5, rings=3)
    for dx in (-0.017, 0.017):
        mb.add_sphere(apex + Vector((dx, 0.002, 0.016)), 0.007, "Thread", AM, segs=5, rings=3)
    return mb


def build_amu_obsidiana():
    """Espejo de obsidiana pulida: óvalo negro con un destello, en marco de madera."""
    mb = new_mb()
    AM = {"Amulet": 1}
    pend = AMULET_AT + Vector((0, -0.001, -0.004))
    _cordon(mb, "Cord", segs=3)
    mb.add_sphere(pend, (0.040, 0.011, 0.046), "Wood", AM, segs=10, rings=4,
                  col=lambda p, d: mixc(PAL["WoodDeep"][1], PAL["Wood"][1], 0.5 + 0.5 * d.z))
    ob, edge, shine = (PAL[k][1] for k in ("Obsid", "ObsidEdge", "ObsidShine"))
    n = 8
    vc = mb.vert(pend + Vector((0, -0.0150, 0)), AM)
    inn, out, ci = [], [], []
    for i in range(n):
        a = 2 * pi * (i + 0.5) / n
        dx, dz = cos(a), sin(a)
        inn.append(mb.vert(pend + Vector((dx * 0.0165, -0.0145, dz * 0.0195)), AM))
        out.append(mb.vert(pend + Vector((dx * 0.0300, -0.0100, dz * 0.0355)), AM))
        ci.append(mixc(ob, shine, max(0.0, cos(a - rad(128))) ** 1.5))   # destello arriba a la izquierda
    for i in range(n):
        j = (i + 1) % n
        face_out(mb, (vc, inn[i], inn[j]), "Obsid", (mixc(ob, shine, 0.25), ci[i], ci[j]), toward=(0, -1, 0))
        face_out(mb, (inn[i], out[i], out[j], inn[j]), "Obsid", (ci[i], edge, edge, ci[j]), toward=(0, -1, 0))
    mb.add_sphere(pend + Vector((0, 0.0, 0.046)), 0.009, "Gold", AM, segs=5, rings=3)
    for dx in (-0.018, 0.018):
        mb.add_sphere(pend + Vector((dx, 0.004, 0.056)), 0.007, "Turq", AM, segs=5, rings=3)
    return mb


def build_amu_semillas():
    """Collar de semillas rojas con su ojo oscuro, en U sobre el pecho."""
    mb = new_mb()
    half = [(0.112, -0.020, 0.860), (0.102, -0.070, 0.853), (0.078, -0.124, 0.830), (0.044, -0.157, 0.797),
            (0.0, -0.169, 0.774)]
    pts = [Vector(p) for p in half] + [Vector((-x, y, z)) for x, y, z in reversed(half[:-1])]
    path = Loft([dict(c=p, rx=0.01, ry=0.01) for p in pts], side=(0, 0, 1))
    samples = [path.frame(path.umax() * k / 240.0)[0] for k in range(241)]
    acc = [0.0]
    for a, b in zip(samples, samples[1:]):
        acc.append(acc[-1] + (b - a).length)
    n = 13
    red, deep, eye = (PAL[k][1] for k in ("Seed", "SeedDeep", "SeedEye"))
    for i in range(n):
        s_ = acc[-1] * (0.085 + 0.83 * i / (n - 1.0))
        k = min(range(len(acc)), key=lambda q: abs(acc[q] - s_))
        c = samples[k]
        t = (samples[min(k + 1, 240)] - samples[max(k - 1, 0)]).normalized()
        mid = 1.0 - abs(i - (n - 1) / 2.0) / ((n - 1) / 2.0)          # 1 en el centro del collar
        r = 0.0130 + 0.0030 * mid
        wa = 0.55 * mid * mid
        w = {"Chest": 1.0 - wa, "Amulet": wa} if wa > 1e-3 else {"Chest": 1}
        rot = t.to_track_quat("Z", "Y").to_matrix()
        look = Vector((c.x * 0.6, -1.0, 0.35)).normalized()             # hacia quien mira el collar
        mb.add_sphere(c, (r, r, r * 1.22), "Seed", w, segs=5, rings=3, rot=rot,
                      col=lambda p, d, c=c, r=r, look=look: eye if (p - c).dot(look) > 0.80 * r
                      else mixc(red, deep, max(0.0, -(p - c).dot(look) / r) * 0.6))
    return mb


# nombre del nodo → función; el orden es el de los catálogos del juego
PIECES = [
    ("Hat_Plumas", build_hat_plumas), ("Hat_Panuelo", build_hat_panuelo), ("Hat_Hojas", build_hat_hojas),
    ("Outfit_Capa", build_outfit_capa), ("Outfit_Faja", build_outfit_faja), ("Outfit_Bordado", build_outfit_bordado),
    ("Acc_Morral", build_acc_morral), ("Acc_Sonaja", build_acc_sonaja), ("Acc_Caracol", build_acc_caracol),
    ("Acc_Farol", build_acc_farol),
    ("Amu_Jade", build_amu_jade), ("Amu_Concha", build_amu_concha), ("Amu_Obsidiana", build_amu_obsidiana),
    ("Amu_Semillas", build_amu_semillas),
]
# Lo que el alux llevaba fijo antes de existir el personalizador. En los renders de
# referencia (previews, retratos, hojas de personaje) solo se ven estas dos piezas.
LEGACY = ("Acc_Morral", "Amu_Jade")


# ──────────────────────────────── Animaciones ────────────────────────────────
# Las poses son {hueso: (rx, ry, rz)} en grados y ejes del modelo. Los pies se dan con
# pseudo-canales que resuelve `finish`: "IK_L"/"IK_R" = desplazamiento (x, y, z) del
# apoyo del pie respecto al reposo, "IKR_L"/"IKR_R" = giro del pie en el mundo. Sin
# ellos, las piernas van por cinemática directa (Thigh/Shin/Foot).

CONTACTS = {"L": ("Foot_L", BALL["L"]), "R": ("Foot_R", BALL["R"])}
RUN_SPEED = 5.2          # m/s para los que se compuso «Run»
RUN_FRAMES = 10          # ciclo de 10 cuadros a 30 fps (1/3 s)


def finish(p):
    p = dict(p)
    for s in ("L", "R"):
        ik = p.pop("IK_" + s, None)
        ikr = p.pop("IKR_" + s, (0, 0, 0))
        if ik is not None:
            RIG.ik(p, "Thigh_" + s, "Shin_" + s, [("Foot_" + s, ikr)], BALL[s], BALL[s] + Vector(ik), bend=-1.0)
    return p


def window(t, t0, t1, ramp):
    """Meseta suave: sube en `ramp`, se mantiene entre t0+ramp y t1-ramp, y baja."""
    def ss(x):
        x = min(1.0, max(0.0, x))
        return x * x * (3 - 2 * x)
    return ss((t - t0) / ramp) * ss((t1 - t) / ramp)


GROUND = {"IK_L": (0, 0, 0), "IK_R": (0, 0, 0)}
ARMS = both({"UpperArm": (3, -6, 0), "Forearm": (-16, 0, 0), "Fingers": (0, 24, 0)})
STAND = {**GROUND, **ARMS}
SMILE = {"Mouth.scale": (1.0, 1.0, 1.0)}


def mouth(wide, open_):
    return {"Mouth.scale": (wide, 1.0, open_)}


def idle(t):
    T = 3.0
    ph = 2 * pi * t / T
    sway = sin(ph)
    br = sin(2 * ph - 0.6)                       # dos respiraciones por ciclo
    g = window(t, 1.0, 1.95, 0.22)               # mirada de reojo a la izquierda
    p = dict(GROUND)
    p["Hips.loc"] = (0.017 * sway, 0.004 * sin(ph + 1.0), -0.007 - 0.004 * cos(2 * ph))
    p["Hips"] = (0, -2.6 * sway, 2.0 * sin(ph + 0.5))
    p["Spine"] = (1.2 + 0.9 * br, 2.2 * sway, -1.5 * sin(ph + 0.5))
    p["Chest"] = (-1.0 - 1.6 * br, 1.2 * sway, 3 * g)
    p["Head"] = (1.8 * sin(2 * ph + 1.0) - 5 * g, -2.4 * sway + 3 * g, 3.5 * sin(ph + 0.4) + 25 * g)
    p.update(both({"UpperArm": (3 + 2.2 * br, -6 - 2.0 * br, 0), "Forearm": (-16 - 3 * br, 0, 0),
                   "Fingers": (0, 24 + 6 * br, 0)}))
    p["UpperArm_L"] = add_pose({"a": p["UpperArm_L"]}, {"a": (2.5 * sway, 0, 0)})["a"]
    p["UpperArm_R"] = add_pose({"a": p["UpperArm_R"]}, {"a": (-2.5 * sway, 0, 0)})["a"]
    tw = bump(t, 2.05, 2.20) + bump(t, 2.22, 2.37)          # doble sacudida de la oreja derecha
    tw2 = bump(t, 2.09, 2.24) + bump(t, 2.26, 2.41)
    p["Ear_L"] = (0, 2.5 * sin(2 * ph + 0.4) - 9 * g, -6 * g)
    p["EarTip_L"] = (0, 3.5 * sin(2 * ph - 0.3) - 5 * g, 0)
    p["Ear_R"] = (0, -2.5 * sin(2 * ph + 0.4) + 6 * g + 12 * tw, -16 * tw)
    p["EarTip_R"] = (0, -3.5 * sin(2 * ph - 0.3) + 10 * tw2, -14 * tw2)
    blink = bump(t, 0.42, 0.60) + bump(t, 2.52, 2.70)
    p.update(both({"Lid": (100 * blink - 5 * g, 0, 0), "LidLow": (-12 * blink, 0, 0),
                   "Brow.loc": (0, 0, -0.006 * blink + 0.010 * g), "Brow": (0, 4 * g, 0)}))
    p["SashTail"] = (2 + 2.5 * sin(2 * ph + 0.7), 0, 4 * sin(ph - 0.6))
    p["Bag"] = (1.5 * sin(2 * ph + 1.4), -3.5 * sin(ph - 0.8), 0)
    p["Amulet"] = (1.5 * br, 3 * sin(ph - 0.7), 0)
    p.update(mouth(1.0 + 0.05 * br + 0.06 * g, 1.0 + 0.5 * g))
    return finish(p)


def _run_foot(f):
    """Apoyo del pie (y, z) y cabeceo durante un ciclo de RUN_FRAMES cuadros. Entre los
    cuadros 0 y 2 el pie está plantado y retrocede exactamente a RUN_SPEED."""
    d = RUN_SPEED / kc.FPS
    keys = [(0, (-d, 0.0, 0.0)), (1, (0.0, 0.0, 0.0)), (2, (d, 0.0, 33.0)), (3.5, (0.33, 0.125, 70.0)),
            (5, (0.22, 0.25, 80.0)), (6.5, (-0.02, 0.215, 40.0)), (8, (-0.225, 0.14, -6.0)),
            (9, (-0.25, 0.06, -12.0)), (10, (-d, 0.0, 0.0))]
    f = f % RUN_FRAMES
    if f <= 2.0:
        return L(f, keys[:3])
    return K(f, keys, loop=RUN_FRAMES)


def run(t):
    f = t * kc.FPS
    w = 2 * pi / RUN_FRAMES
    step = 2 * pi / (RUN_FRAMES / 2)
    p = {}
    for s, off, sx in (("L", 0.0, -0.022), ("R", RUN_FRAMES / 2, 0.022)):
        y, z, pitch = _run_foot(f + off)
        p["IK_" + s] = (sx, y, z)
        p["IKR_" + s] = (pitch, 0, 0)
    p["Hips.loc"] = (0, 0, K(f % (RUN_FRAMES / 2), [(0, -0.057), (1, -0.078), (2, -0.052), (3.5, -0.014),
                                                    (5, -0.057)], loop=RUN_FRAMES / 2))
    st = 1.0 - 0.04 * cos(step * (f - 1.0))                       # se aplasta al pisar, se estira en el aire
    p["Hips.scale"] = squash(st)
    yaw = cos(w * (f - 8.5))                                      # +1 cuando la pierna izquierda va delante
    p["Hips"] = (9, 2.5 * sin(w * (f - 1.0)), -8 * yaw)
    p["Spine"] = (6, -2.0 * sin(w * (f - 1.0)), 11 * yaw)
    p["Chest"] = (4, 0, 7 * yaw)
    p["Head"] = (-15 + 3.0 * cos(step * (f - 1.6)), 0, -10 * yaw)
    arm = cos(w * (f - 3.5))                                      # brazo izquierdo delante con la pierna derecha
    p["UpperArm_L"] = (-6 - 46 * arm, -10, 0)
    p["UpperArm_R"] = (-6 + 46 * arm, 10, 0)
    p["Forearm_L"] = (-78 - 18 * cos(w * (f - 2.6)), 0, 0)
    p["Forearm_R"] = (-78 + 18 * cos(w * (f - 2.6)), 0, 0)
    p.update(both({"Fingers": (0, 62, 0)}))
    p.update(both({"Ear": (0, 12 + 11 * sin(step * (f - 2.0)), 22),
                   "EarTip": (0, 6 + 15 * sin(step * (f - 2.9)), 12)}))
    p["SashTail"] = (24 + 14 * sin(step * (f - 2.4)), 0, 8 * yaw)
    p["Bag"] = (20 + 13 * sin(step * (f - 2.8)), 6 * sin(step * (f - 2.0)), 0)
    p["Amulet"] = (-8 - 14 * sin(step * (f - 2.2)), 0, 0)
    p.update(both({"Brow.loc": (0, 0, 0.004)}))
    p.update(mouth(1.05, 1.9))
    return finish(p)


def jump(t):
    crouch = {**GROUND, "Hips.loc": (0, 0.01, -0.115), "Hips.scale": squash(0.90), "Spine": (17, 0, 0),
              "Chest": (10, 0, 0), "Head": (-14, 0, 0),
              **both({"UpperArm": (52, -14, 0), "Forearm": (-26, 0, 0), "Fingers": (0, 50, 0),
                      "Ear": (0, 16, 10), "EarTip": (0, 14, 6), "Brow": (0, -6, 0)}),
              "SashTail": (-10, 0, 0), "Bag": (-8, 0, 0), **mouth(0.9, 1.0)}
    launch = {"IK_L": (0, 0, 0.0), "IK_R": (0, 0, 0.0), "IKR_L": (42, 0, 0), "IKR_R": (42, 0, 0),
              "Hips.loc": (0, 0, 0.035), "Hips.scale": squash(1.10), "Spine": (-6, 0, 0), "Chest": (-5, 0, 0),
              "Head": (-16, 0, 0),
              **both({"UpperArm": (-98, -16, 0), "Forearm": (-34, 0, 0), "Fingers": (0, 10, 0),
                      "Ear": (0, 22, 14), "EarTip": (0, 26, 8), "Brow.loc": (0, 0, 0.008)}),
              "SashTail": (22, 0, 0), "Bag": (20, 0, 0), "Amulet": (-14, 0, 0), **mouth(1.1, 2.4)}
    rise = {"IK_L": (-0.01, -0.11, 0.215), "IK_R": (0.01, 0.10, 0.075), "IKR_L": (22, 0, 0), "IKR_R": (58, 0, 0),
            "Hips.loc": (0, 0, 0.03), "Hips.scale": squash(1.05), "Spine": (-7, 0, 0), "Chest": (-5, 0, 0),
            "Head": (-13, 0, 0),
            **both({"UpperArm": (-132, 40, 0), "Forearm": (-22, 0, 0), "Fingers": (0, -6, 0),
                    "Ear": (0, 26, 10), "EarTip": (0, 24, 6), "Brow.loc": (0, 0, 0.010)}),
            "SashTail": (30, 0, 0), "Bag": (26, 0, 0), "Amulet": (-20, 0, 0), **mouth(1.15, 2.8)}
    hold = add_pose(rise, {"IK_L": (0, 0.02, -0.02), "Hips.scale": squash(0.97),
                           **both({"UpperArm": (8, 4, 0), "Ear": (0, -6, 0), "EarTip": (0, -8, 0)})})
    return finish(pose_keys(t, [(0.0, STAND), (0.07, crouch), (0.14, launch), (0.25, rise), (0.40, hold)]))


def fall(t):
    ph = 2 * pi * t / 0.6
    s1, s2 = sin(ph), sin(2 * ph)
    p = {"Hips": (5, 0, 0), "Spine": (8, 0, 0), "Chest": (4, 0, 2 * s1), "Head": (9, 0, 0),
         "IK_L": (0.03, -0.05 + 0.05 * s1, 0.11 + 0.03 * cos(ph)), "IKR_L": (30, 0, 0),
         "IK_R": (-0.03, -0.05 - 0.05 * s1, 0.11 - 0.03 * cos(ph)), "IKR_R": (30, 0, 0),
         "UpperArm_L": (-28 + 10 * cos(ph), -82 + 10 * s1, 0), "UpperArm_R": (-28 - 10 * cos(ph), 82 + 10 * s1, 0),
         "SashTail": (-32 + 8 * s2, 0, 0), "Bag": (-28 + 8 * sin(2 * ph + 1), 0, 0), "Amulet": (26 + 6 * s2, 0, 0)}
    p.update(both({"Forearm": (-40 + 7 * s2, 0, 0), "Fingers": (0, -8, 0),
                   "Ear": (0, -30 + 6 * s2, -6), "EarTip": (0, -24 + 9 * sin(2 * ph - 0.8), 0),
                   "Brow": (0, 12, 0), "Brow.loc": (0, 0, 0.008)}))
    p.update(mouth(0.72, 2.8))
    return finish(p)


def land(t):
    hit0 = {"IK_L": (0.015, 0, 0), "IK_R": (-0.015, 0, 0), "Hips.loc": (0, 0, -0.05), "Spine": (8, 0, 0),
            "Head": (4, 0, 0), **both({"UpperArm": (-30, -60, 0), "Forearm": (-36, 0, 0),
                                       "Ear": (0, -22, 0), "EarTip": (0, -20, 0)}), **mouth(0.8, 2.2)}
    low = {"IK_L": (0.02, 0, 0), "IK_R": (-0.02, 0, 0), "Hips.loc": (0, 0.01, -0.15), "Hips.scale": squash(0.85),
           "Spine": (22, 0, 0), "Chest": (10, 0, 0), "Head": (10, 0, 0),
           **both({"UpperArm": (14, -40, 0), "Forearm": (-30, 0, 0), "Fingers": (0, -4, 0),
                   "Ear": (0, 30, 6), "EarTip": (0, 30, 0), "Lid": (55, 0, 0), "Brow.loc": (0, 0, -0.006)}),
           "SashTail": (-16, 0, 0), "Bag": (-14, 0, 0), "Amulet": (12, 0, 0), **mouth(1.0, 1.2)}
    up = add_pose(STAND, {"Hips.loc": (0, 0, 0.012), "Hips.scale": squash(1.04), "Spine": (-3, 0, 0),
                          **both({"Ear": (0, -10, 0), "EarTip": (0, -14, 0)}), **mouth(1.0, 1.0)})
    return finish(pose_keys(t, [(0.0, hit0), (0.067, low), (0.167, up), (0.267, STAND)]))


SWIM_ARM = [
    (0.00, {"UpperArm": (-150, 6, 0), "Forearm": (-10, 0, 0), "Fingers": (0, -6, 0)}),
    (0.35, {"UpperArm": (-92, 0, 68), "Forearm": (-14, 0, 0), "Fingers": (0, 4, 0)}),
    (0.62, {"UpperArm": (-18, -26, 20), "Forearm": (-72, 0, 0), "Fingers": (0, 18, 0)}),
    (0.90, {"UpperArm": (-70, -14, 0), "Forearm": (-112, 0, 0), "Fingers": (0, 30, 0)}),
    (1.20, {"UpperArm": (-150, 6, 0), "Forearm": (-10, 0, 0), "Fingers": (0, -6, 0)}),
]


def swim(t):
    ph = 2 * pi * t / 1.2
    p = both(pose_keys(t, SWIM_ARM, loop=1.2))
    p["Hips"] = (60 + 4 * sin(ph - 0.6), 0, 3 * sin(2 * ph))
    p["Hips.loc"] = (0, 0.14 + 0.03 * sin(ph - 2.0), -0.05 + 0.03 * sin(ph - 1.2))
    p["Spine"] = (-6, 0, -3 * sin(2 * ph))
    p["Chest"] = (-8, 0, 0)
    p["Head"] = (-42 + 4 * sin(ph - 0.4), 0, 0)
    p["Thigh_L"] = (8 + 22 * sin(2 * ph), 0, 0)
    p["Thigh_R"] = (8 - 22 * sin(2 * ph), 0, 0)
    p["Shin_L"] = (20 + 18 * sin(2 * ph - 1.0), 0, 0)
    p["Shin_R"] = (20 - 18 * sin(2 * ph - 1.0), 0, 0)
    p.update(both({"Foot": (40, 0, 0), "Ear": (0, 6 + 5 * sin(ph), 20), "EarTip": (0, 8 + 7 * sin(ph - 0.7), 10)}))
    p["SashTail"] = (-25 + 10 * sin(2 * ph), 0, 0)
    p["Bag"] = (-20 + 8 * sin(2 * ph + 1), 0, 0)
    p["Amulet"] = (30 + 5 * sin(ph), 0, 0)
    p.update(mouth(0.85, 1.6 + 0.8 * bump(t, 0.5, 0.95)))
    return p


def cast(t):
    wind = {"IK_L": (0, -0.03, 0.03), "IK_R": (0, 0, 0), "Hips.loc": (0, 0.03, -0.03), "Hips": (0, 0, -8),
            "Spine": (-4, 0, -20), "Chest": (-5, 0, -14), "Head": (2, 0, 30),
            "UpperArm_R": (62, 20, 0), "Forearm_R": (-108, 0, 0), "Hand_R": (-12, 0, 0), "Fingers_R": (0, -70, 0),
            "UpperArm_L": (-48, -12, 0), "Forearm_L": (-40, 0, 0), "Fingers_L": (0, 0, 0),
            **both({"Ear": (0, -12, -10), "EarTip": (0, -10, -6), "Brow": (0, -12, 0)}),
            "SashTail": (-10, 0, -8), "Bag": (-6, 0, 0), **mouth(0.85, 1.4)}
    throw = {"IK_L": (0, -0.15, 0), "IK_R": (0, 0.01, 0), "IKR_R": (26, 0, 0),
             "Hips.loc": (0, -0.075, -0.045), "Hips": (5, 0, 8), "Spine": (12, 0, 16),
             "Chest": (9, 0, 14), "Head": (-14, 0, -32), "Hips.scale": squash(1.03),
             "UpperArm_R": (-98, 0, -34), "Forearm_R": (-3, 0, 0), "Hand_R": (-30, 0, 0), "Fingers_R": (0, 18, 0),
             "UpperArm_L": (48, -24, 0), "Forearm_L": (-56, 0, 0), "Fingers_L": (0, 60, 0),
             **both({"Ear": (0, 20, 20), "EarTip": (0, 22, 14), "Brow": (0, -15, 0)}),
             "SashTail": (20, 0, 10), "Bag": (18, 0, 0), "Amulet": (-18, 0, 0), **mouth(0.8, 3.2)}
    follow = add_pose(throw, {"Hips.loc": (0, -0.01, -0.012), "Spine": (4, 0, 5), "UpperArm_R": (14, 0, -8),
                              "Forearm_R": (-10, 0, 0), "Hand_R": (16, 0, 0),
                              **both({"Ear": (0, -14, -14), "EarTip": (0, -24, -16)}), "Amulet": (26, 0, 0)})
    settle = blend_pose(throw, STAND, 0.45)
    settle.update({"IK_L": (0, -0.15, 0), "IK_R": (0, 0.01, 0)})
    back = add_pose(STAND, {"IK_L": (0, -0.07, 0.035)})
    keys = [(0.0, STAND), (0.04, wind), (0.10, throw), (0.17, follow), (0.28, settle), (0.35, back), (0.40, STAND)]
    return finish(pose_keys(t, keys))


TUCK = {"Spine": (30, 0, 0), "Chest": (28, 0, 0), "Head": (28, 0, 0),
        **both({"Thigh": (-108, 0, 0), "Shin": (122, 0, 0), "Foot": (10, 0, 0),
                "UpperArm": (-72, 6, 0), "Forearm": (-96, 0, 0), "Fingers": (0, 55, 0),
                "Ear": (0, 10, 34), "EarTip": (0, 16, 20), "Lid": (40, 0, 0)}),
        "SashTail": (30, 0, 0), "Bag": (30, 0, 0), **mouth(0.9, 1.0)}
DIVE = {"Spine": (14, 0, 0), "Chest": (10, 0, 0), "Head": (-20, 0, 0),
        **both({"Thigh": (-30, 0, 0), "Shin": (66, 0, 0), "Foot": (30, 0, 0),
                "UpperArm": (-150, 12, 0), "Forearm": (-12, 0, 0), "Fingers": (0, -10, 0),
                "Ear": (0, 14, 30), "EarTip": (0, 18, 16), "Brow": (0, -10, 0)}), **mouth(0.9, 2.2)}


def dodge(t):
    """Voltereta: se lanza de cabeza con los brazos por delante, rueda hecho bola y sale agachado."""
    ang = K(t, [(0.0, 26.0), (0.05, 70.0), (0.25, 322.0), (0.30, 360.0)])
    k = K(t, [(0.0, 0.0), (0.08, 1.0), (0.22, 1.0), (0.30, 0.5)])
    p = blend_pose(DIVE, TUCK, k) if t < 0.15 else scale_pose(TUCK, k)
    a = rad(ang)

    def rot(y, z):
        return y * cos(a) - z * sin(a), y * sin(a) + z * cos(a)

    kk = max(k, 0.45)
    hy, hz = rot(-0.43 * kk, 0.655 - 0.305 * kk)    # centro de la cabeza respecto a la cadera
    _fy, fz = rot(-0.10 * kk, -0.42 + 0.24 * kk)    # pies
    hips_z = max(0.19, 0.26 - hz, 0.05 - fz)
    p["Hips"] = (ang, 0, 0)
    p["Hips.loc"] = (0, -0.45 * hy, hips_z - 0.42)
    return p


def interact(t):
    reach = {**GROUND, "IKR_L": (0, 0, 0), "Hips.loc": (0, -0.03, -0.035), "Spine": (15, 0, 0), "Chest": (11, 0, 0),
             "Head": (4, 0, 0),
             **both({"UpperArm": (-80, 0, -10), "Forearm": (-22, 0, 0), "Hand": (-18, 0, 0), "Fingers": (0, -8, 0),
                     "Ear": (0, -14, -8), "EarTip": (0, -10, -4), "Brow.loc": (0, 0, 0.008)}),
             "Amulet": (-14, 0, 0), "Bag": (10, 0, 0), **mouth(0.9, 1.8)}
    press = add_pose(reach, {"Hips.loc": (0, -0.012, 0), "Spine": (3, 0, 0), "Head": (6, 0, 0),
                             **both({"UpperArm": (-8, 0, -4), "Forearm": (16, 0, 0), "Fingers": (0, 16, 0),
                                     "Ear": (0, 8, 6), "EarTip": (0, 12, 6)})})
    keys = [(0.0, STAND), (0.17, reach), (0.30, press), (0.42, reach), (0.60, STAND)]
    return finish(pose_keys(t, keys))


def hit(t):
    impact = {"IK_L": (0, 0, 0), "IK_R": (0, 0.05, 0.03), "Hips.loc": (0, 0.055, -0.055), "Hips.scale": squash(0.93),
              "Hips": (-8, 0, 3), "Spine": (-20, 0, 4), "Chest": (-12, 0, 6), "Head": (20, 5, 12),
              **both({"UpperArm": (-46, -30, 0), "Forearm": (-50, 0, 0), "Fingers": (0, -12, 0),
                      "Ear": (0, -6, -22), "EarTip": (0, -10, -20), "Brow": (0, 18, 0), "Brow.loc": (0, 0, -0.010),
                      "LidLow": (-30, 0, 0)}),
              "SashTail": (-24, 0, 0), "Bag": (-20, 0, 0), "Amulet": (-26, 0, 0), **mouth(0.7, 3.4)}
    whip = {"IK_L": (0, 0, 0), "IK_R": (0, 0.12, 0), "Hips.loc": (0, 0.08, -0.04), "Hips": (-5, 0, 2),
            "Spine": (-13, 0, 2), "Chest": (-9, 0, 3), "Head": (-17, -4, 6),
            **both({"UpperArm": (-20, -58, 0), "Forearm": (-62, 0, 0), "Fingers": (0, -12, 0),
                    "Ear": (0, 28, 26), "EarTip": (0, 34, 22), "Brow": (0, 16, 0), "Brow.loc": (0, 0, -0.008),
                    "LidLow": (-26, 0, 0)}),
            "SashTail": (16, 0, 0), "Bag": (14, 0, 0), "Amulet": (22, 0, 0), **mouth(0.75, 2.8)}
    over = add_pose(STAND, {"IK_R": (0, 0.10, 0), "Hips.loc": (0, 0.035, -0.02), "Spine": (7, 0, 0), "Head": (6, 0, 0),
                            **both({"Ear": (0, -8, -8), "EarTip": (0, -14, -10), "Brow": (0, 8, 0)}),
                            **mouth(0.9, 1.4)})
    back = add_pose(STAND, {"IK_R": (0, 0.05, 0.03)})
    keys = [(0.0, STAND), (0.045, impact), (0.11, whip), (0.20, over), (0.26, back), (0.30, STAND)]
    p = pose_keys(t, keys)
    lid = K(t, [(0.0, 0.0), (0.035, 98.0), (0.17, 98.0), (0.27, 0.0)])
    p.update(both({"Lid": (lid, 0, 0)}))
    return finish(p)


DEATH_FALL = {"Hips": (-36, 0, 0), "Hips.loc": (0, 0.14, -0.10), "Spine": (-8, 0, 0), "Head": (-14, 0, 6),
              **both({"Thigh": (-30, 0, 0), "Shin": (70, 0, 0), "UpperArm": (-70, -30, 0),
                      "Forearm": (-40, 0, 0), "Fingers": (0, -10, 0), "Lid": (100, 0, 0),
                      "Ear": (0, -10, -10), "EarTip": (0, -18, -10), "Brow": (0, 16, 0)}),
              "Amulet": (-30, 0, 0), **mouth(0.7, 3.0)}
DEATH_END = {"Hips": (-87, 0, 0), "Hips.loc": (0, 0.38, -0.25), "Spine": (9, 0, 0), "Chest": (7, 0, 0),
             "Head": (8, 0, 20),
             "Thigh_L": (-8, -12, 0), "Thigh_R": (-14, 14, 0), "Shin_L": (12, 0, 0), "Shin_R": (20, 0, 0),
             "UpperArm_L": (0, -68, 0), "UpperArm_R": (0, 52, 0),
             **both({"Forearm": (-26, 0, 0), "Fingers": (0, 20, 0), "Foot": (30, 0, 0), "Lid": (100, 0, 0),
                     "Ear": (0, 30, 0), "EarTip": (0, 26, 0), "Brow": (0, 8, 0)}),
             "SashTail": (-60, 0, 0), "Bag": (-40, 0, 0), "Amulet": (-50, 0, 20), **mouth(0.8, 1.6)}
DEATH_HIT = {"Hips.loc": (0, 0.05, -0.03), "Hips": (-6, 0, 0), "Spine": (-16, 0, 0), "Chest": (-10, 0, 4),
             "Head": (18, 4, 12),
             **both({"UpperArm": (-25, -42, 0), "Forearm": (-58, 0, 0), "Thigh": (-14, 0, 0), "Shin": (26, 0, 0),
                     "Foot": (-12, 0, 0), "Brow": (0, 16, 0), "Ear": (0, 26, 20), "EarTip": (0, 20, 14)}),
             **mouth(0.7, 3.2)}


def death(t):
    bounce = add_pose(DEATH_END, {"Hips.loc": (0, 0, 0.035), "Head": (-8, 0, 0),
                                  **both({"UpperArm": (-14, 0, 0), "Thigh": (-10, 0, 0),
                                          "Ear": (0, -14, 0), "EarTip": (0, -20, 0)})})
    fk_arms = {k: v for k, v in ARMS.items()}
    keys = [(0.0, fk_arms), (0.10, DEATH_HIT), (0.36, DEATH_FALL), (0.60, DEATH_END), (0.70, bounce),
            (0.80, DEATH_END), (0.90, DEATH_END)]
    p = pose_keys(t, keys)
    lid = K(t, [(0.0, 0.0), (0.08, 100.0), (0.9, 100.0)])
    p.update(both({"Lid": (lid, 0, 0)}))
    return p


def transform(t):
    """El alux vuelve a su forma: sale de una bolita, da un saltito con los brazos
    abiertos y cae sonriendo."""
    ball = {**GROUND, "Hips.loc": (0, 0, -0.20), "Hips.scale": (0.55, 0.55, 0.52), "Spine": (26, 0, 0),
            "Chest": (22, 0, 0), "Head": (24, 0, 0),
            **both({"UpperArm": (-60, 14, 0), "Forearm": (-110, 0, 0), "Fingers": (0, 60, 0),
                    "Ear": (0, 40, 20), "EarTip": (0, 40, 10), "Lid": (100, 0, 0)}), **mouth(0.8, 1.0)}
    pop = {"IK_L": (0.06, 0, 0.10), "IK_R": (-0.06, 0, 0.10), "IKR_L": (30, 0, 0), "IKR_R": (30, 0, 0),
           "Hips.loc": (0, 0, 0.12), "Hips.scale": squash(1.14), "Spine": (-9, 0, 0), "Chest": (-7, 0, 0),
           "Head": (-18, 0, 0),
           **both({"UpperArm": (-150, 52, 0), "Forearm": (-14, 0, 0), "Fingers": (0, -14, 0),
                   "Ear": (0, -34, -10), "EarTip": (0, -30, -8), "LidLow": (-34, 0, 0),
                   "Brow.loc": (0, 0, 0.012)}),
           "SashTail": (34, 0, 0), "Bag": (30, 0, 0), "Amulet": (-30, 0, 0), **mouth(1.2, 3.6)}
    hang = add_pose(pop, {"Hips.loc": (0, 0, 0.02), "Hips.scale": squash(0.93), "IK_L": (0.01, 0, 0.02),
                          "IK_R": (-0.01, 0, 0.02), **both({"UpperArm": (14, 6, 0), "Ear": (0, 20, 0),
                                                            "EarTip": (0, 30, 0)})})
    down = {"IK_L": (0.02, 0, 0), "IK_R": (-0.02, 0, 0), "Hips.loc": (0, 0, -0.085), "Hips.scale": squash(0.90),
            "Spine": (12, 0, 0), "Head": (2, 0, 0),
            **both({"UpperArm": (-40, -62, 0), "Forearm": (-30, 0, 0), "Fingers": (0, 0, 0),
                    "Ear": (0, 26, 6), "EarTip": (0, 34, 4), "LidLow": (-30, 0, 0)}),
            "SashTail": (-14, 0, 0), "Bag": (-12, 0, 0), "Amulet": (14, 0, 0), **mouth(1.2, 2.6)}
    up = add_pose(STAND, {"Hips.loc": (0, 0, 0.012), "Hips.scale": squash(1.03),
                          **both({"UpperArm": (-6, -16, 0), "Ear": (0, -10, 0), "EarTip": (0, -16, 0),
                                  "LidLow": (-14, 0, 0)}), **mouth(1.1, 1.6)})
    keys = [(0.0, ball), (0.10, pop), (0.20, hang), (0.30, down), (0.40, up), (0.50, STAND)]
    p = pose_keys(t, keys)
    lid = K(t, [(0.0, 100.0), (0.07, 0.0), (0.5, 0.0)])
    p.update(both({"Lid": (lid, 0, 0)}))
    return finish(p)


ANIMS = [
    ("Idle", 3.0, idle),
    ("Run", RUN_FRAMES / 30.0, run),
    ("Jump", 0.4, jump),
    ("Fall", 0.6, fall),
    ("Land", 0.2667, land),
    ("Swim", 1.2, swim),
    ("Cast", 0.4, cast),
    ("Dodge", 0.3, dodge),
    ("Interact", 0.6, interact),
    ("Hit", 0.3, hit),
    ("Death", 0.9, death),
    ("Transform", 0.5, transform),
]


# ─────────────────────────────────── Main ───────────────────────────────────

def build(only=None):
    """Construye el alux completo. `only` (lista de nombres) limita las piezas opcionales
    que se generan, para probar una sin esperar a las demás."""
    kc.reset_scene()
    mats = make_materials()
    arm = kc.build_armature("Armature", make_bones())
    body, hair = build_body(), build_hair()
    hats = {"Hat_Palma": build_hat_palma(), "Hat_Penacho": build_hat_penacho(), "Hat_Flor": build_hat_flor()}
    pieces = {name: fn() for name, fn in PIECES if only is None or name in only}
    # La oclusión del cuerpo se hornea sin ninguna pieza opcional (si no, quedaría su
    # sombra aunque no se lleve puesta); cada pieza recibe la del cuerpo y la suya.
    kc.bake_ao([body])
    kc.bake_ao([hair], [hair, body], ground=False)
    for mb in list(hats.values()) + list(pieces.values()):
        kc.bake_ao([mb], [mb, body], ground=False)
    objs = {"Alux": body.build("Alux", mats, arm), "Hair": hair.build("Hair", mats, arm)}
    for name, mb in list(hats.items()) + list(pieces.items()):
        objs[name] = mb.build(name, mats, arm)
        if name in pieces and name not in LEGACY:
            objs[name].hide_render = True          # no cambia el .glb: solo los renders de Blender
    kc.bake_actions(arm, ANIMS)
    return arm, objs


def main():
    arm, objs = build()
    kc.export_glb(OUT)
    rep = kc.glb_report(OUT)
    print("== alux.glb ==")
    for k, v in rep.items():
        print(" ", k, ":", v)
    for name, ob in objs.items():
        print("  tris", name, sum(len(p.vertices) - 2 for p in ob.data.polygons))


if __name__ == "__main__":
    main()
