"""Genera game/assets/characters/balam.glb — Balam, la forma de jaguar del alux.

Uso (desde la raíz del repo):
    .tools/blender-venv/bin/python art/blender/build_balam.py

Jaguar heroico y estilizado: pecho profundo, hombros y ancas marcados, cabeza ancha de
ceño fruncido y hocico largo, rosetas pintadas en la propia piel (color de vértice),
vientre crema, ojos de jade que brillan (los del alux), glifos de jade en los hombros,
ajorcas de jade y un collar tejido con amuleto cuyo color es el del jugador.

Materiales: «Body» (color en los vértices, con oclusión horneada), «Collar» (color del
jugador), «Eye» y «Jade» (emisivos).
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import kameo_common as kc  # noqa: E402  (importa bpy antes que mathutils)
from mathutils import Matrix, Vector  # noqa: E402
from kameo_common import (C, K, L, WHITE, Loft, MeshBuilder, Rig, add_pose, blend_pose, both,  # noqa: E402
                          bump, mixc, mulc, ngon, pose_keys, scale_pose)

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(os.environ.get("KAMEO_OUT_DIR") or os.path.join(REPO, "game", "assets", "characters"), "balam.glb")

sin, cos, pi, rad = math.sin, math.cos, math.pi, math.radians


def make_materials():
    m = kc.make_material
    return {
        "Body": m("Body", "#ffffff", 0.8),
        "Collar": m("Collar", "#2ec4a6", 0.7),
        "Eye": m("Eye", "#59ffe0", 0.25, emission=1.2),
        "Jade": m("Jade", "#3ddba8", 0.3, emission=0.6),
    }


def _pal(mat, **cols):
    return {k: (mat, C(v) if isinstance(v, str) else v) for k, v in cols.items()}


PAL = {
    **_pal("Body", Fur="#eb9a2c", FurDeep="#c26f18", FurLight="#fbe9c2", Spots="#2a1a11", Nose="#2b1a16",
           Mouth="#8a2f33", Fang="#fff6e0", Gold="#e8b53a", Pink="#d98a7a"),
    **_pal("Collar", Collar=WHITE, CollarDeep=(0.62, 0.62, 0.62)),
    **_pal("Eye", Eye=WHITE),
    **_pal("Jade", Jade=WHITE),
}
FUR, DEEP, LIGHT, SPOT = (PAL[k][1] for k in ("Fur", "FurDeep", "FurLight", "Spots"))


def smooth(x, a, b):
    x = min(1.0, max(0.0, (x - a) / (b - a)))
    return x * x * (3 - 2 * x)


# ───────────────────────────────── Medidas ─────────────────────────────────
# El jaguar mira a -Y. Largo nariz–grupa ≈ 1.7 m, altura a la cruz ≈ 0.8 m.

LX = 0.188                                   # separación lateral de las patas
F_SHOULDER = Vector((0.172, -0.33, 0.60))
F_ELBOW = Vector((LX, -0.27, 0.40))
F_WRIST = Vector((LX, -0.31, 0.12))
H_HIP = Vector((0.158, 0.45, 0.62))
H_KNEE = Vector((LX, 0.31, 0.41))
H_HOCK = Vector((LX, 0.50, 0.24))
H_BALL = Vector((LX, 0.46, 0.06))
F_CONTACT = Vector((LX, -0.36, 0.0))         # apoyo de la garra delantera
H_CONTACT = Vector((LX, 0.415, 0.0))         # apoyo de la garra trasera

TAIL_PTS = [(0.70, 0.70), (0.80, 0.675), (0.88, 0.60), (0.95, 0.515), (1.01, 0.44), (1.065, 0.375),
            (1.125, 0.325), (1.195, 0.30), (1.265, 0.31), (1.31, 0.335)]   # (y, z)

TORSO = [
    # y, z, rx, ry (arriba), ryn (abajo), pesos
    (0.780, 0.660, 0.030, 0.030, 0.030, {"Hips": 1}),
    (0.745, 0.662, 0.120, 0.100, 0.120, {"Hips": 1}),
    (0.650, 0.655, 0.188, 0.145, 0.185, {"Hips": 1}),
    (0.500, 0.645, 0.214, 0.158, 0.215, {"Hips": 1}),
    (0.320, 0.640, 0.208, 0.150, 0.206, {"Hips": 0.5, "Spine": 0.5}),
    (0.120, 0.630, 0.220, 0.158, 0.232, {"Spine": 1}),
    (-0.080, 0.622, 0.240, 0.176, 0.272, {"Spine": 0.3, "Chest": 0.7}),
    (-0.260, 0.618, 0.254, 0.192, 0.300, {"Chest": 1}),
    (-0.400, 0.635, 0.232, 0.176, 0.262, {"Chest": 1}),
    (-0.490, 0.665, 0.160, 0.130, 0.180, {"Chest": 1}),
    (-0.530, 0.685, 0.030, 0.030, 0.030, {"Chest": 1}),
]
NECK = [
    (-0.300, 0.700, 0.200, 0.140, 0.215, {"Chest": 1}),
    (-0.420, 0.755, 0.186, 0.142, 0.190, {"Chest": 0.5, "Neck": 0.5}),
    (-0.520, 0.815, 0.174, 0.136, 0.162, {"Neck": 1}),
    (-0.600, 0.855, 0.162, 0.128, 0.140, {"Neck": 0.4, "Head": 0.6}),
    (-0.660, 0.870, 0.110, 0.098, 0.098, {"Head": 1}),
]
HEAD = [
    # y, z, rx, ry (arriba), ryn (abajo) — cráneo ancho, frente marcada y hocico corto y cuadrado
    (-0.500, 0.862, 0.060, 0.050, 0.050),
    (-0.550, 0.872, 0.160, 0.124, 0.120),
    (-0.620, 0.882, 0.198, 0.152, 0.144),
    (-0.690, 0.884, 0.200, 0.150, 0.150),     # pómulos y ceño
    (-0.746, 0.876, 0.178, 0.118, 0.140),     # línea de los ojos
    (-0.792, 0.856, 0.138, 0.076, 0.106),     # arranque del hocico
    (-0.836, 0.848, 0.130, 0.070, 0.096),
    (-0.872, 0.845, 0.116, 0.062, 0.082),
    (-0.898, 0.843, 0.076, 0.042, 0.054),
]
EYE_R = 0.024
EYE_U, EYE_TH = 3.95, rad(40)


def mx(v, s):
    return Vector((v[0] * s, v[1], v[2]))


def body_loft(rows, n=2.25):
    return Loft([dict(c=(0, y, z), rx=rx, ry=ry, ryn=ryn, n=n, w=w) for y, z, rx, ry, ryn, w in rows])


HEAD_LOFT = Loft([dict(c=(0, y, z), rx=rx, ry=ry, ryn=ryn, n=2.6, w={"Head": 1}) for y, z, rx, ry, ryn in HEAD])


def eye_center(s):
    th = EYE_TH if s > 0 else pi - EYE_TH
    p = HEAD_LOFT.point(EYE_U, th)
    c = HEAD_LOFT.frame(EYE_U)[0]
    return p - (p - c).normalized() * 0.012


def make_bones():
    b = [
        ("Root", (0, 0, 0), (0, 0, 0.15), None),
        ("Hips", (0, 0.48, 0.70), (0, 0.25, 0.69), "Root"),
        ("Spine", (0, 0.25, 0.69), (0, -0.05, 0.69), "Hips"),
        ("Chest", (0, -0.05, 0.69), (0, -0.38, 0.72), "Spine"),
        ("Neck", (0, -0.38, 0.73), (0, -0.55, 0.83), "Chest"),
        ("Head", (0, -0.55, 0.83), (0, -0.80, 0.83), "Neck"),
        ("Jaw", (0, -0.655, 0.815), (0, -0.86, 0.79), "Head"),
        ("Amulet", (0, -0.50, 0.62), (0, -0.52, 0.53), "Chest"),
    ]
    prev = "Hips"
    for i in range(4):
        head = (0, 0.72, 0.70) if i == 0 else (0, *TAIL_PTS[2 * i])
        b.append(("Tail%d" % (i + 1), head, (0, *TAIL_PTS[2 * i + 2]), prev))
        prev = "Tail%d" % (i + 1)
    for s, sfx in ((1, "_L"), (-1, "_R")):
        ec = eye_center(s)
        b += [
            ("Ear" + sfx, mx((0.132, -0.60, 0.97), s), mx((0.18, -0.60, 1.055), s), "Head"),
            ("Lid" + sfx, ec, ec + Vector((0, -0.04, 0)), "Head"),
            ("FrontUpper" + sfx, mx(F_SHOULDER, s), mx(F_ELBOW, s), "Chest"),
            ("FrontLower" + sfx, mx(F_ELBOW, s), mx(F_WRIST, s), "FrontUpper" + sfx),
            ("FrontPaw" + sfx, mx(F_WRIST, s), mx(F_WRIST + Vector((0, -0.11, -0.09)), s), "FrontLower" + sfx),
            ("HindUpper" + sfx, mx(H_HIP, s), mx(H_KNEE, s), "Hips"),
            ("HindLower" + sfx, mx(H_KNEE, s), mx(H_HOCK, s), "HindUpper" + sfx),
            ("HindFoot" + sfx, mx(H_HOCK, s), mx(H_BALL, s), "HindLower" + sfx),
            ("HindPaw" + sfx, mx(H_BALL, s), mx(H_BALL + Vector((0, -0.10, -0.03)), s), "HindFoot" + sfx),
        ]
    return b


RIG = Rig(make_bones())


# ─────────────────────────────────── Malla ───────────────────────────────────

def rosette(loft, rng, u, th, r, squash_=1.0, heart=True, dot=0.3):
    """Roseta pintada: mancha oscura irregular (dos «mordidas» la parten en trazos) con
    el corazón más tostado que el pelaje, y a veces un punto dentro."""
    radii = [rng.uniform(0.86, 1.12) for _ in range(8)]
    for k in rng.sample(range(8), 2):
        radii[k] = 0.62
    rot = rng.uniform(0, pi)
    out = [(loft.poly(u, th, ngon(8, r, radii=radii, sy=squash_), rot), "Spots")]
    if heart:
        out.append((loft.poly(u, th, ngon(6, r * 0.56, sy=squash_), rot + 0.4), "FurDeep"))
        if rng.random() < dot:
            out.append((loft.poly(u, th, ngon(4, r * 0.17), rot), "Spots"))
    return out


def spot(loft, rng, u, th, r, squash_=1.0):
    return [(loft.poly(u, th, ngon(6, r, radii=[rng.uniform(0.8, 1.15) for _ in range(6)], sy=squash_),
                       rng.uniform(0, pi)), "Spots")]


def glyph(loft, u, th, r):
    """Glifo de jade (aro con punto y tres rayas): brilla sobre el hombro."""
    out = [(loft.poly(u, th, ngon(8, r)), "Jade"), (loft.poly(u, th, ngon(8, r * 0.66)), "Fur"),
           (loft.poly(u, th, ngon(5, r * 0.30)), "Jade")]
    for k in (-1, 0, 1):
        cx = -r * 1.55
        out.append((loft.poly(u, th, [(cx - r * 0.22, k * r * 0.62 - r * 0.2), (cx + r * 0.22, k * r * 0.62 - r * 0.2),
                                      (cx + r * 0.22, k * r * 0.62 + r * 0.2), (cx - r * 0.22, k * r * 0.62 + r * 0.2)]),
                    "Jade"))
    return out


def build_body():
    mb = MeshBuilder(PAL)
    rng = random.Random(11)
    HD = {"Head": 1}

    def coat(p, u, th):
        """Pelaje: vientre crema que se funde con el dorado, lomo más tostado."""
        s = sin(th)
        c = mixc(FUR, DEEP, 0.45 * smooth(s, 0.55, 1.0))
        return mixc(c, LIGHT, 1.0 - smooth(s, -0.8, -0.3))

    # ── tronco con rosetas pintadas
    torso = body_loft(TORSO)
    shapes = []
    for col in range(10):
        y = 0.66 - col * 0.118
        u = 0.0
        for i in range(len(TORSO) - 1):
            if TORSO[i][0] >= y >= TORSO[i + 1][0]:
                u = i + (TORSO[i][0] - y) / (TORSO[i][0] - TORSO[i + 1][0])
        nrow = 8
        for row in range(nrow):
            th = rad(-34 + (248.0 / (nrow - 1)) * row + (15 if col % 2 else 0))
            uu = u + rng.uniform(-0.06, 0.06)
            tt = th + rng.uniform(-0.04, 0.04)
            if sin(tt) < -0.5 or not (0.9 < uu < 9.3):
                continue
            p = torso.point(uu, tt)
            if abs(p.x) > 0.12 and p.z < 0.74 and (-0.47 < p.y < -0.17 or 0.30 < p.y < 0.60):
                continue                          # tapado por el hombro o el anca
            if sin(tt) > 0.93:                    # lomo: manchas macizas y alargadas
                shapes += spot(torso, rng, uu, tt, rng.uniform(0.030, 0.036), 0.6)
            else:
                shapes += rosette(torso, rng, uu, tt, rng.uniform(0.044, 0.054))
    mb.add_loft_painted(torso, "Fur", shapes, segs=16, sub=2, th0=rad(-90), col=coat)

    # ── cuello
    neck = body_loft(NECK)
    shapes = []
    for uu, n_row, r in ((0.40, 6, 0.036), (1.75, 5, 0.030), (2.65, 5, 0.024)):
        for row in range(n_row):
            tt = rad(4 + 172.0 / (n_row - 1) * row) + rng.uniform(-0.06, 0.06)
            shapes += rosette(neck, rng, uu, tt, r, dot=0.0) if r > 0.028 else spot(neck, rng, uu, tt, r * 0.7)
    mb.add_loft_painted(neck, "Fur", shapes, segs=14, sub=2, cap0=False, cap1=False, th0=rad(-90), col=coat)

    # ── collar tejido (color del jugador) con ribetes dorados, cuentas y amuleto de jade
    CW = {"Chest": 0.5, "Neck": 0.5}
    col_rings = []
    for u, d in ((0.66, 0.0), (0.72, 0.024), (0.86, 0.030), (1.14, 0.030), (1.28, 0.024), (1.34, 0.0)):
        c, a, b, t, rx, ry, ryn, n = neck.frame(u)
        col_rings.append(dict(c=c, rx=rx + d, ry=ry + d, ryn=ryn + d, n=2.25, w=CW))
    collar = Loft(col_rings)

    def collar_mat(u, th, p):
        if u < 1.0 or u > 4.0:
            return "Gold"
        return "CollarDeep" if (int(th / (2 * pi) * 14 + 100) + int(u)) % 2 else "Collar"

    mb.add_loft(collar, None, segs=14, cap0=False, cap1=False, matfn=collar_mat)
    for i in range(6):
        th = rad(-30 + 48 * i)
        mb.add_sphere(collar.point(2.5, th), 0.022, "Gold", CW, segs=6, rings=3)
    AM = {"Amulet": 1}
    pend = Vector((0.0, -0.548, 0.615))
    mb.add_sphere(pend, (0.054, 0.016, 0.054), "Gold", AM, segs=10, rings=4)
    mb.add_sphere(pend + Vector((0, -0.010, 0)), (0.040, 0.012, 0.040), "Jade", AM, segs=8, rings=4)
    mb.add_sphere(pend + Vector((0, -0.020, 0)), (0.013, 0.006, 0.013), "Gold", AM, segs=5, rings=3)
    for dx in (-0.03, 0.03):
        fang = Loft([dict(c=pend + Vector((dx * 2.0, 0.006, 0.02)), rx=0.010, ry=0.008, w=AM),
                     dict(c=pend + Vector((dx * 2.3, 0.004, -0.02)), rx=0.007, ry=0.006, w=AM),
                     dict(c=pend + Vector((dx * 2.2, 0.0, -0.05)), rx=0.001, ry=0.001, w=AM)], side=(1, 0, 0))
        mb.add_loft(fang, "Fang", segs=4, cap0=False)

    # ── cabeza: cráneo ancho, ceño marcado y hocico largo
    def face(p, u, th):
        s = sin(th)
        c = mixc(FUR, DEEP, 0.35 * smooth(s, 0.5, 1.0) * (1.0 - smooth(u, 4.0, 6.0)))
        muzzle = smooth(u, 4.6, 5.6) * (1.0 - smooth(s, 0.35, 0.8))      # hocico crema, puente dorado
        chin = 1.0 - smooth(s, -0.85, -0.45)
        return mixc(c, LIGHT, max(muzzle, chin))

    shapes = []
    for s in (1, -1):
        def T(deg, s=s):
            return rad(deg) if s > 0 else pi - rad(deg)
        # antifaz oscuro que afila la mirada, con «lágrima» hacia el hocico
        shapes.append((HEAD_LOFT.poly(EYE_U, T(40), [(0.050, 0.004), (0.020, 0.030), (-0.030, 0.034), (-0.052, 0.012),
                                                      (-0.040, -0.022), (0.004, -0.030), (0.040, -0.016)],
                                      0.35 * s), "Spots"))
        shapes.append(([(5.5, T(-33)), (7.6, T(-40)), (7.6, T(-47)), (5.5, T(-41))], "Spots"))     # línea del labio
        # manchas de la frente y los carrillos
        for uu, deg, r in ((1.5, 80, 0.015), (2.1, 74, 0.014), (2.7, 80, 0.013), (3.3, 76, 0.011), (1.8, 60, 0.014),
                           (2.5, 62, 0.012), (3.1, 64, 0.011), (1.4, 44, 0.015), (1.3, 22, 0.016), (2.1, 26, 0.014),
                           (2.8, 20, 0.013), (1.7, 4, 0.015), (2.5, 2, 0.013), (3.2, 4, 0.012), (2.1, -16, 0.014),
                           (2.9, -18, 0.012), (3.6, -10, 0.011), (1.3, -30, 0.015), (2.5, -34, 0.012)):
            shapes += spot(HEAD_LOFT, rng, uu, T(deg), r)
        for uu, deg in ((6.1, -4), (6.6, -10), (6.25, -22), (6.8, -26), (7.1, -14)):     # nacimiento de los bigotes
            shapes.append((HEAD_LOFT.poly(uu, T(deg), ngon(4, 0.006)), "Spots"))
    shapes.append((HEAD_LOFT.poly(2.4, rad(90), [(0.05, 0.012), (0.05, -0.012), (-0.06, -0.008), (-0.06, 0.008)]), "Spots"))
    mb.add_loft_painted(HEAD_LOFT, "Fur", shapes, segs=16, sub=1, cap0=False, th0=rad(-90), col=face,
                        capmat=(None, "Nose"))
    mb.add_sphere((0, -0.902, 0.858), (0.046, 0.020, 0.028), "Nose", HD, segs=8, rings=4,
                  col=lambda p, d: mixc(PAL["Nose"][1], PAL["Pink"][1], 0.35 * max(0.0, d.z)))
    # interior de la boca, mandíbula y colmillos
    mb.add_sphere((0, -0.785, 0.800), (0.086, 0.100, 0.026), "Mouth", HD, segs=8, rings=4)
    JAW = {"Jaw": 1}
    jaw = Loft([dict(c=(0, -0.665, 0.790), rx=0.090, ry=0.024, ryn=0.040, n=2.6, w=JAW),
                dict(c=(0, -0.735, 0.780), rx=0.126, ry=0.028, ryn=0.060, n=2.6, w=JAW),
                dict(c=(0, -0.800, 0.776), rx=0.120, ry=0.026, ryn=0.056, n=2.6, w=JAW),
                dict(c=(0, -0.855, 0.778), rx=0.102, ry=0.024, ryn=0.046, n=2.6, w=JAW),
                dict(c=(0, -0.888, 0.784), rx=0.052, ry=0.016, ryn=0.026, n=2.6, w=JAW)])
    mb.add_loft(jaw, "FurLight", segs=10, col=lambda p, u, th: mixc(LIGHT, PAL["Mouth"][1],
                                                                  0.9 * smooth(sin(th), 0.75, 0.95)))
    for s in (1, -1):
        up = Loft([dict(c=(s * 0.070, -0.860, 0.806), rx=0.015, ry=0.015, w=HD),
                   dict(c=(s * 0.072, -0.864, 0.776), rx=0.012, ry=0.012, w=HD),
                   dict(c=(s * 0.070, -0.860, 0.738), rx=0.002, ry=0.002, w=HD)])
        mb.add_loft(up, "Fang", segs=5, cap0=False)
        lo = Loft([dict(c=(s * 0.052, -0.872, 0.790), rx=0.010, ry=0.010, w=JAW),
                   dict(c=(s * 0.053, -0.875, 0.812), rx=0.008, ry=0.008, w=JAW),
                   dict(c=(s * 0.052, -0.872, 0.832), rx=0.002, ry=0.002, w=JAW)])
        mb.add_loft(lo, "Fang", segs=5, cap0=False)

    for s, sfx in ((1, "_L"), (-1, "_R")):
        # ── ojos pequeños y fieros: jade que brilla, pupila vertical y párpado sesgado
        ce = eye_center(s)
        f = Vector((s * 0.42, -0.86, 0.12)).normalized()
        rot = f.to_track_quat("Z", "Y").to_matrix()
        mb.add_sphere(ce, EYE_R, "Eye", HD, segs=10, rings=10, rot=rot, keep=lambda d: d.z > 0.0,
                      matfn=lambda d: "Spots" if (abs(d.x) < 0.2 and d.z > 0.55) else "Eye")
        n = Vector((0, sin(rad(24)), cos(rad(24))))
        rl = Matrix.Rotation(s * rad(-26), 3, "Y") @ n.to_track_quat("Z", "X").to_matrix()
        mb.add_sphere(ce, EYE_R * 1.22, "Fur", {"Lid" + sfx: 1}, segs=10, rings=10, rot=rl,
                      keep=lambda d: d.z > 0.0, matfn=lambda d: "Spots" if d.z < 0.34 else "Fur")
        # ceño: un arco de hueso sobre cada ojo, inclinado hacia la nariz
        br = Matrix.Rotation(s * rad(-24), 3, "Y") @ Matrix.Rotation(s * rad(-20), 3, "Z")
        mb.add_sphere(ce + Vector((s * 0.008, 0.012, 0.030)), (0.058, 0.036, 0.020), "Fur", HD, segs=8, rings=5,
                      rot=br, col=lambda p, d: mixc(FUR, DEEP, 0.5 * max(0.0, d.z)))

        # ── orejas angulosas: dorso oscuro con mancha clara, interior crema
        EW = {"Ear" + sfx: 1}
        ear = Loft([dict(c=mx((0.126, -0.600, 0.975), s), rx=0.060, ry=0.030, w={"Head": 1}),
                    dict(c=mx((0.142, -0.598, 1.010), s), rx=0.058, ry=0.022, w=EW),
                    dict(c=mx((0.158, -0.595, 1.042), s), rx=0.046, ry=0.016, w=EW),
                    dict(c=mx((0.170, -0.592, 1.064), s), rx=0.024, ry=0.010, w=EW)])

        def ear_col(p, u, th):
            if sin(th) > 0.25:                            # dorso
                return mixc(SPOT, LIGHT, bump(u, 0.9, 2.1) * (1.0 - abs(cos(th))))
            return mixc(FUR, mixc(LIGHT, PAL["Pink"][1], 0.4), smooth(-sin(th), 0.2, 0.7) * (1.0 - abs(cos(th)) * 0.7))

        mb.add_loft(ear, "Fur", segs=8, cap0=False, col=ear_col)
        # mechones del carrillo: dan a la cabeza una silueta más angulosa
        for (dy, dz, ln, r) in ((0.0, -0.035, 0.085, 0.040), (0.035, -0.075, 0.07, 0.034)):
            base = Vector((s * 0.158, -0.650 + dy, 0.855 + dz))
            d = Vector((s * 0.80, 0.42, -0.42)).normalized()
            tuft = Loft([dict(c=base, rx=r, ry=r * 0.8, w=HD), dict(c=base + d * ln * 0.55, rx=r * 0.7, ry=r * 0.5, w=HD),
                         dict(c=base + d * ln, rx=0.004, ry=0.003, w=HD)], side=(0, 0, 1))
            mb.add_loft(tuft, "Fur", segs=6, cap0=False, col=lambda p, u, th: mixc(FUR, LIGHT, 0.75 * min(1.0, u / 1.6)))

        out_th = 0.0 if s > 0 else pi            # θ del lado exterior de la pata
        seam = pi if s > 0 else 0.0              # costura por la cara interior

        def limb(p, u, th, s=s):
            inner = smooth(-cos(th) * s, 0.2, 0.9)
            return mixc(FUR, LIGHT, 0.75 * inner)

        def T(deg, s=s):
            return rad(deg) if s > 0 else pi - rad(deg)

        # ── pata delantera: hombro musculoso con glifo de jade, antebrazo, ajorca y garra
        fu, fl, fp = "FrontUpper" + sfx, "FrontLower" + sfx, "FrontPaw" + sfx
        fleg = Loft([
            dict(c=mx((0.150, -0.310, 0.730), s), rx=0.085, ry=0.115, ryn=0.110, w={"Chest": 0.5, fu: 0.5}),
            dict(c=mx((0.172, -0.325, 0.620), s), rx=0.106, ry=0.136, ryn=0.126, w={fu: 1}),
            dict(c=mx((0.185, -0.305, 0.500), s), rx=0.096, ry=0.116, ryn=0.106, w={fu: 1}),
            dict(c=mx((LX, -0.275, 0.400), s), rx=0.087, ry=0.099, ryn=0.094, w={fu: 0.5, fl: 0.5}),
            dict(c=mx((LX, -0.285, 0.300), s), rx=0.076, ry=0.083, ryn=0.076, w={fl: 1}),
            dict(c=mx((LX, -0.303, 0.190), s), rx=0.067, ry=0.072, ryn=0.065, w={fl: 1}),
            dict(c=mx((LX, -0.310, 0.120), s), rx=0.065, ry=0.069, ryn=0.065, w={fl: 0.5, fp: 0.5}),
            dict(c=mx((LX, -0.322, 0.055), s), rx=0.072, ry=0.076, ryn=0.069, w={fp: 1}),
        ])
        shapes = glyph(fleg, 1.25, out_th, 0.034)
        for uu, deg in ((0.75, 62), (0.8, -62), (1.5, 78), (1.55, -80), (2.2, 40), (2.2, -42), (2.15, 0)):
            shapes += rosette(fleg, rng, uu, T(deg + rng.uniform(-6, 6)), rng.uniform(0.030, 0.036), dot=0.0)
        for uu, deg in ((3.0, 55), (3.1, -50), (3.3, 0), (3.9, 70), (3.9, -70), (4.3, 25), (4.4, -30), (5.6, 60),
                        (5.6, -55), (5.8, 5), (6.5, 40), (6.5, -40)):
            shapes += spot(fleg, rng, uu, T(deg + rng.uniform(-8, 8)), rng.uniform(0.015, 0.021))
        mb.add_loft_painted(fleg, "Fur", shapes, segs=10, cap0=False, cap1=False, th0=seam, col=limb)
        anklet = Loft([dict(c=mx((LX, -0.3065, 0.168 + dz), s), rx=0.065 + d, ry=0.070 + d, ryn=0.064 + d, w={fl: 1})
                       for dz, d in ((0.030, 0.0), (0.024, 0.012), (-0.024, 0.012), (-0.030, 0.0))])
        mb.add_loft(anklet, None, segs=10, cap0=False, cap1=False,
                    matfn=lambda u, th, p: "Jade" if 1.0 < u < 2.0 else "Gold")
        paw_c = mx((LX, -0.362, 0.052), s)
        mb.add_sphere(paw_c, (0.090, 0.112, 0.052), "Fur", {fp: 1}, segs=10, rings=6,
                      col=lambda p, d: mixc(FUR, LIGHT, 0.5 * smooth(-d.y, 0.2, 0.9)))
        for k in (-1.5, -0.5, 0.5, 1.5):
            tc = paw_c + Vector((k * 0.040, -0.092 + abs(k) * 0.016, -0.016))
            mb.add_sphere(tc, (0.026, 0.036, 0.032), "FurLight", {fp: 1}, segs=6, rings=3)
            claw = Loft([dict(c=tc + Vector((0, -0.026, 0.002)), rx=0.007, ry=0.007, w={fp: 1}),
                         dict(c=tc + Vector((0, -0.042, -0.008)), rx=0.005, ry=0.005, w={fp: 1}),
                         dict(c=tc + Vector((0, -0.050, -0.022)), rx=0.001, ry=0.001, w={fp: 1})])
            mb.add_loft(claw, "Fang", segs=4, cap0=False)

        # ── pata trasera: anca maciza, corvejón y garra
        hu, hl, hf, hpw = "HindUpper" + sfx, "HindLower" + sfx, "HindFoot" + sfx, "HindPaw" + sfx
        hleg = Loft([
            dict(c=mx((0.150, 0.470, 0.720), s), rx=0.090, ry=0.120, ryn=0.120, w={"Hips": 0.5, hu: 0.5}),
            dict(c=mx((0.166, 0.440, 0.605), s), rx=0.114, ry=0.150, ryn=0.150, w={hu: 1}),
            dict(c=mx((0.180, 0.385, 0.505), s), rx=0.106, ry=0.132, ryn=0.142, w={hu: 1}),
            dict(c=mx((LX, 0.335, 0.425), s), rx=0.092, ry=0.105, ryn=0.119, w={hu: 0.6, hl: 0.4}),
            dict(c=mx((LX, 0.405, 0.335), s), rx=0.072, ry=0.078, ryn=0.083, w={hl: 1}),
            dict(c=mx((LX, 0.490, 0.255), s), rx=0.060, ry=0.067, ryn=0.069, w={hl: 0.6, hf: 0.4}),
            dict(c=mx((LX, 0.498, 0.195), s), rx=0.056, ry=0.063, ryn=0.063, w={hl: 0.2, hf: 0.8}),
            dict(c=mx((LX, 0.478, 0.120), s), rx=0.056, ry=0.060, ryn=0.060, w={hf: 1}),
            dict(c=mx((LX, 0.462, 0.055), s), rx=0.065, ry=0.069, ryn=0.067, w={hf: 0.5, hpw: 0.5}),
        ])
        shapes = []
        for uu, deg in ((0.7, 55), (0.75, -55), (0.7, 0), (1.35, 80), (1.4, 28), (1.4, -28), (1.35, -82),
                        (2.0, 55), (2.05, 0), (2.0, -58)):
            shapes += rosette(hleg, rng, uu, T(deg + rng.uniform(-5, 5)), rng.uniform(0.032, 0.040), dot=0.2)
        for uu, deg in ((2.8, 40), (2.8, -40), (3.5, 60), (3.6, -50), (3.9, 5), (4.6, 50), (4.7, -45), (5.5, 0),
                        (6.3, 55), (6.4, -50), (7.3, 10)):
            shapes += spot(hleg, rng, uu, T(deg + rng.uniform(-8, 8)), rng.uniform(0.014, 0.020))
        mb.add_loft_painted(hleg, "Fur", shapes, segs=10, sub=2, cap0=False, cap1=False, th0=seam, col=limb)
        hpaw_c = mx((LX, 0.416, 0.052), s)
        mb.add_sphere(hpaw_c, (0.084, 0.108, 0.052), "Fur", {hpw: 1}, segs=10, rings=6,
                      col=lambda p, d: mixc(FUR, LIGHT, 0.5 * smooth(-d.y, 0.2, 0.9)))
        for k in (-1.5, -0.5, 0.5, 1.5):
            tc = hpaw_c + Vector((k * 0.038, -0.088 + abs(k) * 0.016, -0.016))
            mb.add_sphere(tc, (0.025, 0.035, 0.032), "FurLight", {hpw: 1}, segs=6, rings=3)

    # ── cola larga con anillos y punta oscura
    tw = []
    for i in range(len(TAIL_PTS)):
        seg = min(3, max(0, (i - 1) // 2))
        if i == 0:
            w = {"Hips": 1}
        elif i % 2 == 0 and i < 8:
            w = {"Tail%d" % (seg + 1): 0.5, "Tail%d" % min(4, seg + 2): 0.5}
        else:
            w = {"Tail%d" % (seg + 1): 1}
        tw.append(w)
    rad_t = [0.070, 0.064, 0.058, 0.054, 0.051, 0.049, 0.048, 0.048, 0.048, 0.016]
    tail = Loft([dict(c=(0, y, z), rx=r, ry=r, w=w) for (y, z), r, w in zip(TAIL_PTS, rad_t, tw)])
    TT0 = rad(90)                                 # costura por debajo
    shapes = [([(a, TT0), (a, TT0 + 2 * pi), (b, TT0 + 2 * pi), (b, TT0)], "Spots")
              for a, b in ((5.45, 5.85), (6.35, 6.75), (7.3, 9.0))]
    for uu, deg in ((1.2, -90), (1.7, -30), (1.9, -150), (2.5, -90), (3.1, -25), (3.2, -155), (3.9, -90),
                    (4.5, -30), (4.6, -150), (5.0, -90)):
        shapes += spot(tail, rng, uu, rad(deg), 0.019)
    mb.add_loft_painted(tail, "Fur", shapes, segs=8, sub=2, cap0=False, cap1=True, th0=TT0, capmat=(None, "Spots"),
                        col=lambda p, u, th: mixc(FUR, LIGHT, 0.8 * smooth(sin(th), 0.3, 0.9)))
    return mb


# ──────────────────────────────── Animaciones ────────────────────────────────
# Las cuatro patas pueden ir por cinemática inversa con los pseudo-canales
# "IK_FL", "IK_FR", "IK_HL", "IK_HR" (desplazamiento del apoyo de la garra respecto al
# reposo) e "IKR_*" (giro en el mundo de la garra delantera o del metatarso trasero).
# Sin ellos, la pata va por cinemática directa.

RUN_SPEED = 8.4          # m/s para los que se compuso «Run»
RUN_FRAMES = 12          # galope de 12 cuadros a 30 fps (0.4 s)
LEGS = {"FL": ("Front", "L", 1), "FR": ("Front", "R", -1), "HL": ("Hind", "L", 1), "HR": ("Hind", "R", -1)}
CONTACTS = {"FL": ("FrontPaw_L", mx(F_CONTACT, 1)), "FR": ("FrontPaw_R", mx(F_CONTACT, -1)),
            "HL": ("HindPaw_L", mx(H_CONTACT, 1)), "HR": ("HindPaw_R", mx(H_CONTACT, -1))}


def finish(p):
    p = dict(p)
    for leg, (kind, side, s) in LEGS.items():
        ik = p.pop("IK_" + leg, None)
        ikr = p.pop("IKR_" + leg, (0, 0, 0))
        if ik is None:
            continue
        bone, rest = CONTACTS[leg]
        if kind == "Front":
            RIG.ik(p, "FrontUpper_" + side, "FrontLower_" + side, [("FrontPaw_" + side, ikr)], rest,
                   rest + Vector(ik), bend=1.0)
        else:
            toe = (0, 0, 0) if ik[2] < 0.02 else (ikr[0] * 0.6, 0, 0)     # plantada: dedos planos
            RIG.ik(p, "HindUpper_" + side, "HindLower_" + side,
                   [("HindFoot_" + side, ikr), ("HindPaw_" + side, toe)], rest, rest + Vector(ik), bend=-1.0)
    return p


GROUND = {"IK_FL": (0, 0, 0), "IK_FR": (0, 0, 0), "IK_HL": (0, 0, 0), "IK_HR": (0, 0, 0)}
STAND = dict(GROUND)


def window(t, t0, t1, ramp):
    def ss(x):
        x = min(1.0, max(0.0, x))
        return x * x * (3 - 2 * x)
    return ss((t - t0) / ramp) * ss((t1 - t) / ramp)


def tail_wave(ph, amp=1.0, lift=0.0):
    return {
        "Tail1": (lift, 0, amp * 10 * sin(ph)),
        "Tail2": (lift * 0.5, 0, amp * 14 * sin(ph - 0.7)),
        "Tail3": (0, 0, amp * 18 * sin(ph - 1.4)),
        "Tail4": (8 * amp * sin(ph - 1.0), 0, amp * 22 * sin(ph - 2.1)),
    }


def idle(t):
    T = 3.0
    ph = 2 * pi * t / T
    sway = sin(ph)
    br = sin(2 * ph - 0.5)
    g = window(t, 1.1, 2.0, 0.25)                         # mirada atenta hacia un lado
    p = dict(GROUND)
    p.update(tail_wave(ph, 1.0, 5 + 3 * br))
    p["Hips.loc"] = (0.014 * sway, 0, -0.006 - 0.005 * br)
    p["Hips"] = (0, -1.6 * sway, 1.2 * sin(ph + 0.6))
    p["Spine"] = (0.8 * br, 1.0 * sway, 0)
    p["Chest"] = (-1.4 * br, 0.8 * sway, -1.0 * sin(ph + 0.6))
    p["Neck"] = (2 * sin(ph + 0.6) - 4 * g, 0, 5 * sway * (1 - g) - 14 * g)
    p["Head"] = (2 * sin(2 * ph + 1.2) - 3 * g, 3 * sin(ph + 0.5) * (1 - g), 7 * sway * (1 - g) - 20 * g)
    tw = bump(t, 2.15, 2.32) + bump(t, 2.35, 2.52)
    p["Ear_L"] = (12 * tw - 4 * g, -10 * tw, 0)
    p["Ear_R"] = (-6 * g, 6 * g, 0)
    blink = bump(t, 0.55, 0.72) + bump(t, 2.6, 2.77)
    p.update(both({"Lid": (95 * blink + 10 * g, 0, 0)}))
    p["Jaw"] = (1.5 + 1.5 * br + 3 * bump(t, 2.0, 2.6), 0, 0)
    p["Amulet"] = (2 * br, 3 * sin(ph - 0.7), 0)
    return finish(p)


def _hind_path(f):
    d = RUN_SPEED / kc.FPS
    keys = [(0, (-0.365, 0.0, -8.0)), (1, (-0.365 + d, 0.0, 0.0)), (2, (-0.365 + 2 * d, 0.0, -26.0)),
            (3.5, (0.44, 0.15, -55.0)), (5.5, (0.42, 0.24, -62.0)), (7.5, (0.12, 0.27, -22.0)),
            (9.5, (-0.24, 0.20, 8.0)), (11, (-0.42, 0.08, 4.0)), (12, (-0.365, 0.0, -8.0))]
    f = f % RUN_FRAMES
    return L(f, keys[:3]) if f <= 2.0 else K(f, keys, loop=RUN_FRAMES)


def _front_path(f):
    d = RUN_SPEED / kc.FPS
    keys = [(0, (-0.30, 0.0, -10.0)), (1, (-0.30 + d, 0.0, 0.0)), (2, (-0.30 + 2 * d, 0.0, 32.0)),
            (3.5, (0.43, 0.16, 72.0)), (5.5, (0.26, 0.30, 82.0)), (7.5, (-0.14, 0.30, 40.0)),
            (9.5, (-0.45, 0.22, -20.0)), (11, (-0.44, 0.10, -25.0)), (12, (-0.30, 0.0, -10.0))]
    f = f % RUN_FRAMES
    return L(f, keys[:3]) if f <= 2.0 else K(f, keys, loop=RUN_FRAMES)


def run(t):
    """Galope: las traseras empujan (cuadros 0–3), vuelo estirado, las delanteras reciben
    (6–9) y vuelo recogido. Cada garra plantada retrocede exactamente a RUN_SPEED."""
    f = t * kc.FPS
    N = RUN_FRAMES
    p = {}
    for leg, off, path in (("HL", 0, _hind_path), ("HR", 1, _hind_path), ("FL", 6, _front_path),
                           ("FR", 7, _front_path)):
        y, z, rot = path(f - off)
        p["IK_" + leg] = (0, y, z)
        p["IKR_" + leg] = (rot, 0, 0)
    p["Hips.loc"] = (0, 0, K(f, [(0, -0.095), (1.5, -0.115), (3, -0.075), (4.5, -0.02), (6, -0.045), (7.5, -0.075),
                                 (9, -0.06), (10.5, -0.06), (12, -0.095)], loop=N))
    pitch = K(f, [(0, -5.0), (1.5, -8.0), (4.5, -2.0), (7.5, 9.0), (9, 7.0), (10.5, 2.0), (12, -5.0)], loop=N)
    flex = K(f, [(0, 0.8), (1.5, 0.35), (3, -0.5), (4.5, -1.0), (6, -0.6), (7.5, 0.1), (9.5, 0.9), (11, 1.0),
                 (12, 0.8)], loop=N)                     # +1 lomo arqueado (recogido), -1 estirado
    p["Hips"] = (pitch - 6 * flex, 0, 0)
    p["Spine"] = (13 * flex + 2, 0, 0)
    p["Chest"] = (8 * flex, 0, 0)
    p["Neck"] = (-8 * flex + 4 - pitch * 0.5, 0, 0)
    p["Head"] = (-6 * flex - 4 - pitch * 0.5 + 2 * cos(2 * pi * f / N), 0, 0)
    st = 1.0 - 0.035 * flex
    p["Hips.scale"] = (1.0, st, 1.0 / st)
    w = 2 * pi / N
    p["Tail1"] = (26 + 12 * sin(w * (f - 2.0)), 0, 0)
    p["Tail2"] = (12 + 14 * sin(w * (f - 3.2)), 0, 0)
    p["Tail3"] = (4 + 16 * sin(w * (f - 4.4)), 0, 0)
    p["Tail4"] = (-12 + 18 * sin(w * (f - 5.6)), 0, 0)
    p.update(both({"Ear": (-24 + 6 * sin(w * (f - 3.0)), 0, 0)}))
    p["Jaw"] = (6 - 3 * flex, 0, 0)
    p["Amulet"] = (10 * sin(w * (f - 2.5)) - 8, 0, 0)
    return finish(p)


CROUCH = {**GROUND, "Hips.loc": (0, 0.05, -0.15), "Hips": (3, 0, 0), "Spine": (5, 0, 0), "Chest": (3, 0, 0),
          "Neck": (14, 0, 0), "Head": (-20, 0, 0), **both({"Ear": (-28, 0, 0)}),
          "Tail1": (-6, 0, 0), "Tail2": (4, 0, 0), "Jaw": (4, 0, 0)}
AIR_STRETCH = {"IK_FL": (0, -0.36, 0.34), "IK_FR": (0, -0.30, 0.30), "IKR_FL": (-28, 0, 0), "IKR_FR": (-24, 0, 0),
               "IK_HL": (0, 0.40, 0.20), "IK_HR": (0, 0.34, 0.16), "IKR_HL": (-58, 0, 0), "IKR_HR": (-52, 0, 0),
               "Hips.loc": (0, 0, 0.06), "Hips": (-13, 0, 0), "Spine": (-7, 0, 0), "Chest": (-4, 0, 0),
               "Neck": (10, 0, 0), "Head": (2, 0, 0), "Hips.scale": (1.0, 1.05, 0.96), "Jaw": (10, 0, 0),
               **both({"Ear": (-28, 0, 0)}), "Tail1": (32, 0, 0), "Tail2": (16, 0, 0), "Tail3": (10, 0, 0)}


def jump(t):
    coil = add_pose(CROUCH, {"Hips.loc": (0, 0.03, -0.03), "Hips": (-6, 0, 0), "Spine": (6, 0, 0),
                             "Hips.scale": (1.0, 0.95, 1.04), "Tail1": (-10, 0, 0)})
    launch = {"IK_FL": (0, -0.20, 0.28), "IK_FR": (0, -0.14, 0.24), "IKR_FL": (40, 0, 0), "IKR_FR": (44, 0, 0),
              "IK_HL": (0, 0.04, 0), "IK_HR": (0, 0.04, 0), "IKR_HL": (-30, 0, 0), "IKR_HR": (-30, 0, 0),
              "Hips.loc": (0, -0.05, 0.02), "Hips": (-26, 0, 0), "Spine": (-8, 0, 0), "Neck": (10, 0, 0),
              "Head": (6, 0, 0), "Hips.scale": (1.0, 1.06, 0.95), **both({"Ear": (-22, 0, 0)}),
              "Tail1": (18, 0, 0), "Tail2": (10, 0, 0), "Jaw": (6, 0, 0)}
    hold = add_pose(AIR_STRETCH, {"Hips": (4, 0, 0), "IK_FL": (0, 0.04, -0.03), "IK_HL": (0, -0.06, 0.02),
                                  "Tail1": (-6, 0, 0), "Tail3": (8, 0, 0)})
    return finish(pose_keys(t, [(0.0, STAND), (0.07, coil), (0.14, launch), (0.26, AIR_STRETCH), (0.40, hold)]))


def fall(t):
    ph = 2 * pi * t / 0.6
    s = sin(ph)
    p = {"IK_FL": (0, -0.16 + 0.03 * s, 0.10 + 0.02 * s), "IK_FR": (0, -0.12 - 0.03 * s, 0.09 - 0.02 * s),
         "IKR_FL": (-22, 0, 0), "IKR_FR": (-22, 0, 0),
         "IK_HL": (0, -0.06 - 0.03 * s, 0.17 - 0.02 * s), "IK_HR": (0, -0.02 + 0.03 * s, 0.15 + 0.02 * s),
         "IKR_HL": (-6, 0, 0), "IKR_HR": (-6, 0, 0),
         "Hips": (9, 0, 0), "Spine": (4, 0, 0), "Neck": (-6, 0, 0), "Head": (-6, 0, 0), "Jaw": (7, 0, 0),
         "Tail1": (40 + 5 * s, 0, 8 * s), "Tail2": (18, 0, 12 * sin(ph - 0.7)),
         "Tail3": (10, 0, 14 * sin(ph - 1.4)), "Tail4": (6, 0, 16 * sin(ph - 2.1)), "Amulet": (14, 0, 0)}
    p.update(both({"Ear": (-18 + 4 * sin(2 * ph), 0, 0)}))
    return finish(p)


def land(t):
    hit0 = {**GROUND, "IK_FL": (0, -0.05, 0), "IK_FR": (0, -0.05, 0), "Hips.loc": (0, 0, -0.06), "Hips": (6, 0, 0),
            "Neck": (-6, 0, 0), "Jaw": (6, 0, 0), **both({"Ear": (-20, 0, 0)}), "Tail1": (36, 0, 0)}
    low = {**GROUND, "IK_FL": (0, -0.05, 0), "IK_FR": (0, -0.05, 0), "Hips.loc": (0, -0.01, -0.21),
           "Hips.scale": (1.04, 1.03, 0.90), "Hips": (5, 0, 0), "Spine": (6, 0, 0), "Chest": (4, 0, 0),
           "Neck": (10, 0, 0), "Head": (6, 0, 0), "Jaw": (3, 0, 0), **both({"Ear": (-34, 0, 0), "Lid": (40, 0, 0)}),
           "Tail1": (-12, 0, 0), "Tail2": (-10, 0, 0), "Tail3": (-14, 0, 0), "Amulet": (-20, 0, 0)}
    up = add_pose(STAND, {"Hips.loc": (0, 0, 0.012), "Hips.scale": (1.0, 1.0, 1.03), "Neck": (-5, 0, 0),
                          "Tail1": (14, 0, 0), "Tail3": (10, 0, 0), **both({"Ear": (-6, 0, 0)})})
    return finish(pose_keys(t, [(0.0, hit0), (0.067, low), (0.167, up), (0.267, STAND)]))


def swim(t):
    ph = 2 * pi * t / 0.9
    p = {"Hips.loc": (0, 0, -0.02 + 0.015 * sin(ph + 1)), "Hips": (-5 + 2 * sin(ph), 0, 3 * sin(ph)),
         "Spine": (0, 0, -4 * sin(ph)), "Neck": (-24, 0, 0), "Head": (-8 + 2 * sin(ph), 0, 0), "Jaw": (4, 0, 0)}

    def front(sfx, f):
        p["FrontUpper" + sfx] = (-28 + 30 * sin(f), 0, 0)
        p["FrontLower" + sfx] = (-48 - 32 * cos(f), 0, 0)
        p["FrontPaw" + sfx] = (20 + 24 * cos(f), 0, 0)

    def hind(sfx, f):
        p["HindUpper" + sfx] = (6 - 26 * sin(f), 0, 0)
        p["HindLower" + sfx] = (36 + 24 * cos(f), 0, 0)
        p["HindFoot" + sfx] = (-10 - 22 * cos(f), 0, 0)

    front("_L", ph)
    front("_R", ph + pi)
    hind("_L", ph + pi)
    hind("_R", ph)
    p["Tail1"] = (34, 0, 9 * sin(ph))
    p["Tail2"] = (22, 0, 12 * sin(ph - 0.7))
    p["Tail3"] = (14, 0, 16 * sin(ph - 1.4))
    p["Tail4"] = (6, 0, 20 * sin(ph - 2.1))
    p.update(both({"Ear": (-14, 0, 0)}))
    p["Amulet"] = (20, 0, 0)
    return p


def claw(t):
    """Zarpazo con la derecha: la garra ya está arriba en el cuadro 1 y golpea a 0.10 s."""
    wind = {**GROUND, "IK_FR": (-0.04, -0.06, 0.50), "IKR_FR": (-50, 0, 0),
            "Hips.loc": (0, 0.03, -0.03), "Hips": (-9, 0, 0), "Spine": (-4, 0, -7), "Chest": (-5, 0, -10),
            "Neck": (2, 0, 10), "Head": (-6, 0, 8), "Jaw": (14, 0, 0), **both({"Ear": (-30, 0, 0)}),
            "Tail1": (16, 0, 18), "Tail2": (6, 0, 16), "Tail3": (0, 0, 14)}
    strike = {**GROUND, "IK_FR": (0.20, -0.46, 0.30), "IKR_FR": (46, 0, 0),
              "Hips.loc": (0, -0.10, -0.06), "Hips": (2, 0, 5), "Spine": (5, 0, 9), "Chest": (7, 0, 14),
              "Neck": (8, 0, -8), "Head": (-12, 0, -10), "Jaw": (32, 0, 0), "Hips.scale": (1.0, 1.04, 0.97),
              **both({"Ear": (-36, 0, 0)}),
              "Tail1": (22, 0, -22), "Tail2": (10, 0, -24), "Tail3": (4, 0, -22), "Tail4": (0, 0, -16),
              "Amulet": (-16, 0, 10)}
    follow = add_pose(strike, {"IK_FR": (0.08, 0.16, -0.20), "IKR_FR": (20, 0, 0), "Hips.loc": (0, 0.02, -0.02),
                               "Chest": (2, 0, 4), "Jaw": (-10, 0, 0), "Tail1": (0, 0, 14), "Tail2": (0, 0, 18),
                               "Tail3": (0, 0, 22), "Amulet": (26, 0, -16)})
    settle = scale_pose(strike, 0.3)
    settle.update(GROUND)
    settle["IK_FR"] = (0.06, -0.10, 0.03)
    keys = [(0.0, STAND), (0.035, wind), (0.10, strike), (0.167, follow), (0.26, settle), (0.333, STAND)]
    return finish(pose_keys(t, keys))


def charge_pose(t):
    """Agazapado y tenso: tiembla, menea las ancas y azota la cola."""
    ph = 2 * pi * t / 0.5
    sh = sin(3 * ph)
    p = add_pose(CROUCH, {"Hips.loc": (0.004 * sh, 0.03, -0.02 + 0.003 * sin(3 * ph + 1)),
                          "Hips": (-5, 2.4 * sin(ph), 1.2 * sh), "Spine": (2 + 1.0 * sin(3 * ph + 0.8), 0, 0),
                          "Chest": (0, -1.2 * sh, 0), "Neck": (4, 0, 0), "Head": (1.2 * sin(3 * ph + 2), 0, 0),
                          "Jaw": (9 + 3 * sin(3 * ph), 0, 0), **both({"Ear": (-6 + 3 * sh, 0, 0)}),
                          "Amulet": (4 * sh, 0, 0)})
    p = add_pose(p, {"Tail1": (10, 0, 24 * sin(ph)), "Tail2": (6, 0, 28 * sin(ph - 0.8)),
                     "Tail3": (4, 0, 30 * sin(ph - 1.6)), "Tail4": (10, 0, 32 * sin(ph - 2.4))})
    return p


def charge(t):
    return finish(charge_pose(t))


def charge_release(t):
    """Gran golpe a dos garras: sale del agazapo, se alza y descarga a 0.15 s."""
    start = charge_pose(0.0)
    up = {**GROUND, "IK_FL": (0.03, -0.22, 0.62), "IK_FR": (-0.03, -0.22, 0.62), "IKR_FL": (-55, 0, 0),
          "IKR_FR": (-55, 0, 0), "IKR_HL": (-12, 0, 0), "IKR_HR": (-12, 0, 0),
          "Hips.loc": (0, -0.14, 0.0), "Hips": (-24, 0, 0), "Spine": (-9, 0, 0), "Chest": (-6, 0, 0),
          "Neck": (12, 0, 0), "Head": (2, 0, 0), "Jaw": (34, 0, 0), "Hips.scale": (1.0, 1.06, 0.96),
          **both({"Ear": (-36, 0, 0)}), "Tail1": (30, 0, 0), "Tail2": (14, 0, 0), "Tail3": (8, 0, 0),
          "Amulet": (-24, 0, 0)}
    slam = {**GROUND, "IK_FL": (0.02, -0.44, 0.0), "IK_FR": (-0.02, -0.44, 0.0), "IKR_FL": (8, 0, 0),
            "IKR_FR": (8, 0, 0), "IKR_HL": (-20, 0, 0), "IKR_HR": (-20, 0, 0),
            "Hips.loc": (0, -0.30, -0.10), "Hips": (9, 0, 0), "Spine": (9, 0, 0), "Chest": (7, 0, 0),
            "Neck": (0, 0, 0), "Head": (-14, 0, 0), "Jaw": (26, 0, 0), "Hips.scale": (1.0, 1.03, 0.94),
            **both({"Ear": (-30, 0, 0)}), "Tail1": (38, 0, 0), "Tail2": (22, 0, 0), "Tail3": (10, 0, 0),
            "Tail4": (-10, 0, 0), "Amulet": (26, 0, 0)}
    rebound = add_pose(slam, {"Hips.loc": (0, 0.04, 0.05), "Hips": (-5, 0, 0), "Hips.scale": (1.0, 0.97, 1.08),
                              "Jaw": (-12, 0, 0), "Tail1": (-14, 0, 0), "Amulet": (-30, 0, 0)})
    back = add_pose(STAND, {"IK_FL": (0, -0.20, 0.05), "IK_FR": (0, -0.24, 0.0), "Hips.loc": (0, -0.12, -0.03),
                            "Jaw": (8, 0, 0)})
    keys = [(0.0, start), (0.075, up), (0.15, slam), (0.23, rebound), (0.36, back), (0.467, STAND)]
    return finish(pose_keys(t, keys))


POUNCE_END = {"IK_FL": (0, -0.30, 0.10), "IK_FR": (0, -0.24, 0.08), "IKR_FL": (-34, 0, 0), "IKR_FR": (-30, 0, 0),
              "IK_HL": (0, 0.30, 0.26), "IK_HR": (0, 0.24, 0.24), "IKR_HL": (-50, 0, 0), "IKR_HR": (-46, 0, 0),
              "Hips.loc": (0, 0, 0.04), "Hips": (14, 0, 0), "Spine": (2, 0, 0), "Neck": (-4, 0, 0),
              "Head": (-12, 0, 0), "Jaw": (30, 0, 0), **both({"Ear": (-32, 0, 0)}),
              "Tail1": (40, 0, 0), "Tail2": (20, 0, 0), "Tail3": (12, 0, 0), "Amulet": (10, 0, 0)}


def pounce(t):
    """Salto de ataque: se recoge un instante, se estira en el aire con las garras por
    delante y termina cayendo sobre ellas (sigue «PounceLand»)."""
    coil = add_pose(CROUCH, {"Hips.loc": (0, 0.04, -0.02), "Hips": (-8, 0, 0), "Hips.scale": (1.0, 0.94, 1.05)})
    leap = add_pose(AIR_STRETCH, {"Hips.loc": (0, -0.04, 0.06), "Jaw": (18, 0, 0),
                                  "IK_FL": (0, -0.06, 0.06), "IK_FR": (0, -0.06, 0.06)})
    keys = [(0.0, scale_pose(coil, 0.6)), (0.06, coil), (0.16, add_pose(leap, {"Hips": (-12, 0, 0)})),
            (0.30, leap), (0.50, POUNCE_END)]
    p = pose_keys(t, keys)
    for k in GROUND:
        p.setdefault(k, (0, 0, 0))
    return finish(p)


def pounce_land(t):
    """Impacto pesado sobre las garras delanteras; las traseras llegan después."""
    hit0 = dict(POUNCE_END)
    hit0.update({"IK_FL": (0, -0.22, 0.0), "IK_FR": (0, -0.18, 0.0), "IKR_FL": (0, 0, 0), "IKR_FR": (0, 0, 0),
                 "Hips.loc": (0, -0.04, -0.02)})
    crash = {"IK_FL": (0, -0.22, 0), "IK_FR": (0, -0.18, 0), "IK_HL": (0, 0.06, 0.05), "IK_HR": (0, 0.02, 0.09),
             "IKR_HL": (-16, 0, 0), "IKR_HR": (-20, 0, 0),
             "Hips.loc": (0, -0.08, -0.12), "Hips": (17, 0, 0), "Spine": (10, 0, 0), "Chest": (8, 0, 0),
             "Neck": (-14, 0, 0), "Head": (-6, 0, 0), "Jaw": (22, 0, 0), "Hips.scale": (1.03, 1.0, 0.93),
             **both({"Ear": (-36, 0, 0)}), "Tail1": (52, 0, 0), "Tail2": (26, 0, 0), "Tail3": (16, 0, 0),
             "Amulet": (30, 0, 0)}
    sit = {**GROUND, "IK_FL": (0, -0.14, 0), "IK_FR": (0, -0.12, 0), "Hips.loc": (0, -0.05, -0.19),
           "Hips": (2, 0, 0), "Spine": (8, 0, 0), "Chest": (4, 0, 0), "Neck": (6, 0, 0), "Head": (-10, 0, 0),
           "Jaw": (10, 0, 0), "Hips.scale": (1.04, 1.03, 0.90), **both({"Ear": (-28, 0, 0)}),
           "Tail1": (-10, 0, 0), "Tail2": (-12, 0, 0), "Tail3": (-12, 0, 0), "Amulet": (-22, 0, 0)}
    up = add_pose(STAND, {"IK_FL": (0, -0.06, 0.03), "Hips.loc": (0, -0.01, 0.012), "Hips.scale": (1.0, 1.0, 1.03),
                          "Neck": (-5, 0, 0), "Tail1": (12, 0, 0), "Jaw": (4, 0, 0)})
    return finish(pose_keys(t, [(0.0, hit0), (0.067, crash), (0.167, sit), (0.267, up), (0.367, STAND)]))


def hit(t):
    impact = {**GROUND, "IK_FR": (0, 0.03, 0.06), "IKR_FR": (30, 0, 0), "Hips.loc": (0, 0.07, -0.06),
              "Hips": (-5, 0, 2), "Spine": (-5, 0, 6), "Chest": (-6, 3, 9), "Neck": (8, 0, 10), "Head": (20, 8, 10),
              "Jaw": (22, 0, 0), "Hips.scale": (1.0, 0.96, 1.02), **both({"Ear": (-40, 0, 0)}),
              "Tail1": (36, 0, 12), "Tail2": (18, 0, 12), "Tail3": (10, 0, 8), "Amulet": (-24, 0, 0)}
    whip = {**GROUND, "IK_FR": (0, 0.10, 0.0), "Hips.loc": (0, 0.09, -0.04), "Hips": (-4, 0, 1),
            "Spine": (-3, 0, 3), "Chest": (-4, 2, 5), "Neck": (-22, 0, 8), "Head": (-10, 4, 8), "Jaw": (14, 0, 0),
            **both({"Ear": (-34, 0, 0)}), "Tail1": (20, 0, -10), "Tail2": (22, 0, -6), "Tail3": (18, 0, 4),
            "Amulet": (22, 0, 0)}
    back = add_pose(STAND, {"IK_FR": (0, 0.05, 0.04), "Hips.loc": (0, 0.03, -0.01), "Neck": (4, 0, 0),
                            "Jaw": (6, 0, 0), **both({"Ear": (-16, 0, 0)})})
    p = pose_keys(t, [(0.0, STAND), (0.045, impact), (0.12, whip), (0.23, back), (0.30, STAND)])
    lid = K(t, [(0.0, 0.0), (0.035, 92.0), (0.17, 92.0), (0.27, 0.0)])
    p.update(both({"Lid": (lid, 0, 0)}))
    return finish(p)


DEATH_HIT = {"Hips.loc": (0, 0.06, -0.05), "Hips": (-5, 0, 0), "Spine": (-4, 0, 6), "Chest": (-5, 3, 8),
             "Neck": (-20, 0, 12), "Head": (14, 8, 12), "Jaw": (16, 0, 0),
             **both({"FrontUpper": (-18, 0, 0), "FrontLower": (-10, 0, 0), "FrontPaw": (20, 0, 0),
                     "HindUpper": (-12, 0, 0), "HindLower": (26, 0, 0), "HindFoot": (-14, 0, 0),
                     "Ear": (-38, 0, 0), "Lid": (90, 0, 0)}),
             "Tail1": (34, 0, 10), "Tail2": (16, 0, 10), "Tail3": (10, 0, 6)}
DEATH_BUCKLE = {"Hips.loc": (0.04, 0.03, -0.24), "Hips": (2, -28, 0), "Spine": (4, 0, 6), "Neck": (14, 0, 8),
                "Head": (10, -10, 0), "Jaw": (12, 0, 0),
                **both({"FrontUpper": (26, 0, 0), "FrontLower": (-78, 0, 0), "FrontPaw": (40, 0, 0),
                        "HindUpper": (-30, 0, 0), "HindLower": (70, 0, 0), "HindFoot": (-40, 0, 0),
                        "Ear": (-30, 0, 0), "Lid": (95, 0, 0)}),
                "Tail1": (-8, 0, 10), "Amulet": (0, 20, 0)}
DEATH_END = {"Hips.loc": (0.10, 0.0, -0.49), "Hips": (0, -84, 0), "Spine": (2, 0, 4), "Chest": (0, 0, 4),
             "Neck": (10, -4, 16), "Head": (6, 0, 10), "Jaw": (9, 0, 0),
             "FrontUpper_L": (-26, 8, 0), "FrontLower_L": (-22, 0, 0), "FrontPaw_L": (34, 0, 0),
             "FrontUpper_R": (-8, 0, 0), "FrontLower_R": (-30, 0, 0), "FrontPaw_R": (34, 0, 0),
             "HindUpper_L": (22, 8, 0), "HindLower_L": (14, 0, 0), "HindFoot_L": (26, 0, 0),
             "HindUpper_R": (6, 0, 0), "HindLower_R": (20, 0, 0), "HindFoot_R": (22, 0, 0),
             **both({"Ear": (-16, 0, 0), "Lid": (95, 0, 0)}),
             "Tail1": (6, 0, -30), "Tail2": (10, 0, -24), "Tail3": (6, 0, -20), "Tail4": (-10, 0, -16),
             "Amulet": (0, 60, 0)}


def death(t):
    bounce = add_pose(DEATH_END, {"Hips.loc": (0, 0, 0.035), "Hips": (0, 5, 0), "Neck": (-8, 0, 0),
                                  **both({"FrontUpper": (-8, 0, 0), "HindUpper": (8, 0, 0)})})
    keys = [(0.0, {}), (0.12, DEATH_HIT), (0.38, DEATH_BUCKLE), (0.66, DEATH_END), (0.77, bounce),
            (0.88, DEATH_END), (1.0, DEATH_END)]
    p = pose_keys(t, keys)
    lid = K(t, [(0.0, 0.0), (0.1, 95.0), (1.0, 95.0)])
    p.update(both({"Lid": (lid, 0, 0)}))
    return p


def transform(t):
    """Balam emerge: brota agazapado, se alza rugiendo sobre las patas traseras, deja
    caer las garras y se asienta."""
    seed = add_pose(CROUCH, {"Hips.loc": (0, 0.0, -0.10), "Hips.scale": (0.6, 0.6, 0.6), "Neck": (10, 0, 0),
                             "Head": (10, 0, 0), **both({"Lid": (95, 0, 0)}), "Tail1": (-20, 0, 0)})
    rear = {**GROUND, "IK_FL": (0.05, -0.16, 0.72), "IK_FR": (-0.05, -0.20, 0.64), "IKR_FL": (-60, 0, 0),
            "IKR_FR": (-50, 0, 0), "IKR_HL": (-10, 0, 0), "IKR_HR": (-10, 0, 0),
            "Hips.loc": (0, -0.06, -0.03), "Hips": (-34, 0, 0), "Spine": (-10, 0, 0), "Chest": (-8, 0, 0),
            "Neck": (16, 0, 0), "Head": (-6, 0, 0), "Jaw": (38, 0, 0), "Hips.scale": (1.06, 1.06, 1.08),
            **both({"Ear": (-34, 0, 0)}), "Tail1": (34, 0, 14), "Tail2": (18, 0, 16), "Tail3": (10, 0, 14),
            "Amulet": (-30, 0, 0)}
    roar = add_pose(rear, {"Hips": (3, 0, 0), "Head": (-6, 0, 6), "Neck": (0, 0, 5), "Jaw": (-4, 0, 0),
                           "Hips.scale": (0.96, 0.96, 0.95), "Tail1": (0, 0, -26), "Tail2": (0, 0, -30),
                           "Tail3": (0, 0, -26), "IK_FL": (0, -0.03, -0.04)})
    slam = {**GROUND, "IK_FL": (0, -0.08, 0), "IK_FR": (0, -0.05, 0), "Hips.loc": (0, -0.03, -0.11),
            "Hips": (6, 0, 0), "Spine": (6, 0, 0), "Neck": (4, 0, 0), "Head": (-10, 0, 0), "Jaw": (12, 0, 0),
            "Hips.scale": (1.03, 1.02, 0.93), **both({"Ear": (-24, 0, 0)}), "Tail1": (30, 0, 0), "Tail2": (16, 0, 0),
            "Amulet": (26, 0, 0)}
    up = add_pose(STAND, {"IK_FL": (0, -0.04, 0.02), "Hips.loc": (0, 0, 0.01), "Hips.scale": (1.0, 1.0, 1.03),
                          "Neck": (-4, 0, 0), "Jaw": (4, 0, 0), "Tail1": (10, 0, 0)})
    keys = [(0.0, seed), (0.14, rear), (0.28, roar), (0.40, slam), (0.50, up), (0.60, STAND)]
    p = pose_keys(t, keys)
    lid = K(t, [(0.0, 95.0), (0.08, 0.0), (0.6, 0.0)])
    p.update(both({"Lid": (lid, 0, 0)}))
    return finish(p)


ANIMS = [
    ("Idle", 3.0, idle),
    ("Run", RUN_FRAMES / 30.0, run),
    ("Jump", 0.4, jump),
    ("Fall", 0.6, fall),
    ("Land", 0.2667, land),
    ("Swim", 0.9, swim),
    ("Claw", 0.3333, claw),
    ("Charge", 0.5, charge),
    ("ChargeRelease", 0.4667, charge_release),
    ("Pounce", 0.5, pounce),
    ("PounceLand", 0.3667, pounce_land),
    ("Hit", 0.3, hit),
    ("Death", 1.0, death),
    ("Transform", 0.6, transform),
]


# ─────────────────────────────────── Main ───────────────────────────────────

def build():
    kc.reset_scene()
    mats = make_materials()
    arm = kc.build_armature("Armature", make_bones())
    body = build_body()
    kc.bake_ao([body], dist=0.26)
    objs = {"Balam": body.build("Balam", mats, arm)}
    kc.bake_actions(arm, ANIMS)
    return arm, objs


def main():
    arm, objs = build()
    kc.export_glb(OUT)
    rep = kc.glb_report(OUT)
    print("== balam.glb ==")
    for k, v in rep.items():
        print(" ", k, ":", v)


if __name__ == "__main__":
    main()
