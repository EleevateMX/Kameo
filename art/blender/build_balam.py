"""Genera game/assets/characters/balam.glb — Balam, la forma de jaguar del alux.

Uso (desde la raíz del repo):
    .tools/blender-venv/bin/python art/blender/build_balam.py

Jaguar estilizado: pecho profundo, hombros y ancas fuertes, cabeza ancha con
hocico corto, rosetas oscuras, vientre crema, ojos de jade que brillan (los
mismos del alux) y un collar tejido con cuentas cuyo color es el del jugador.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import kameo_common as kc  # noqa: E402  (importa bpy antes que mathutils)
from mathutils import Matrix, Vector  # noqa: E402
from kameo_common import K, Loft, MeshBuilder, add_pose, pose_keys  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(REPO, "game", "assets", "characters", "balam.glb")

sin, cos, pi, rad = math.sin, math.cos, math.pi, math.radians


def make_materials():
    m = kc.make_material
    return {
        "Fur": m("Fur", "#e9962a", 0.8),
        "FurLight": m("FurLight", "#f9e6bb", 0.8),
        "Spots": m("Spots", "#2a1a11", 0.75),
        "Eye": m("Eye", "#59ffe0", 0.25, emission=1.2),
        "Collar": m("Collar", "#2ec4a6", 0.7),
        "Gold": m("Gold", "#e8b53a", 0.4, metallic=0.35),
        "Mouth": m("Mouth", "#8a2f33", 0.6),
        "Fang": m("Fang", "#fff6e0", 0.5),
    }


# ───────────────────────────────── Medidas ─────────────────────────────────
# El jaguar mira a -Y. Largo nariz–grupa ≈ 1.6 m, altura a la cruz ≈ 0.8 m.

SK = Vector((0.0, -0.66, 0.865))           # centro del cráneo
HS = 1.13                                  # escala de la cabeza (cabezón, como buen jaguar)
SKR = (0.142 * HS, 0.15 * HS, 0.118 * HS)
EYE_R = 0.028 * HS
LEG = 1.22                                 # grosor de las patas

F_SHOULDER = Vector((0.172, -0.33, 0.60))
F_ELBOW = Vector((0.185, -0.27, 0.40))
F_WRIST = Vector((0.185, -0.31, 0.12))
H_HIP = Vector((0.158, 0.45, 0.62))
H_KNEE = Vector((0.185, 0.31, 0.41))
H_HOCK = Vector((0.185, 0.50, 0.24))
H_BALL = Vector((0.185, 0.46, 0.06))

TAIL_PTS = [(0.70, 0.70), (0.80, 0.675), (0.88, 0.60), (0.945, 0.515), (1.00, 0.44), (1.05, 0.375),
            (1.105, 0.325), (1.17, 0.30), (1.235, 0.305), (1.275, 0.325)]   # (y, z)


def mx(v, s):
    return Vector((v[0] * s, v[1], v[2]))


def hp(x, y, z):
    """Punto relativo al centro del cráneo (escalado con la cabeza)."""
    return SK + Vector((x, y, z)) * HS


def hr(*r):
    return tuple(v * HS for v in r)


def skull_scale(d):
    s = 1.0 + 0.18 * abs(d.x) ** 1.6 * max(0.0, 0.35 - d.z)     # carrillos anchos
    s -= 0.07 * max(0.0, d.z) * max(0.0, -d.y)                  # frente inclinada
    return s


def sdir(lon, lat):
    return Vector((sin(lon) * cos(lat), -cos(lon) * cos(lat), sin(lat)))


def skull_pt(lon, lat, off=0.0):
    d = sdir(lon, lat)
    s = skull_scale(d)
    return SK + Vector((d.x * SKR[0] * s, d.y * SKR[1] * s, d.z * SKR[2] * s)) + d * off


EYE_LON, EYE_LAT = rad(34), rad(16)


def eye_center(s):
    return skull_pt(s * EYE_LON, EYE_LAT) - sdir(s * EYE_LON, EYE_LAT) * (0.6 * EYE_R)


def make_bones():
    b = [
        ("Root", (0, 0, 0), (0, 0, 0.15), None),
        ("Hips", (0, 0.48, 0.70), (0, 0.25, 0.69), "Root"),
        ("Spine", (0, 0.25, 0.69), (0, -0.05, 0.69), "Hips"),
        ("Chest", (0, -0.05, 0.69), (0, -0.38, 0.72), "Spine"),
        ("Neck", (0, -0.38, 0.73), (0, -0.55, 0.83), "Chest"),
        ("Head", (0, -0.55, 0.83), (0, -0.80, 0.83), "Neck"),
        ("Jaw", hp(0, 0.03, -0.062), hp(0, -0.17, -0.085), "Head"),
    ]
    prev = "Hips"
    for i in range(4):
        head = (0, 0.72, 0.70) if i == 0 else (0, *TAIL_PTS[2 * i])
        tail = (0, *TAIL_PTS[2 * i + 2])
        b.append(("Tail%d" % (i + 1), head, tail, prev))
        prev = "Tail%d" % (i + 1)
    for s, sfx in ((1, "_L"), (-1, "_R")):
        ec = eye_center(s)
        eb = hp(s * 0.108, 0.07, 0.085)
        b += [
            ("Ear" + sfx, eb, eb + Vector((s * 0.03, 0, 0.07)), "Head"),
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


# ─────────────────────────────────── Malla ───────────────────────────────────

TORSO = [
    # y, z, rx, ry (arriba), ryn (abajo), pesos
    (0.770, 0.665, 0.030, 0.030, 0.030, {"Hips": 1}),
    (0.735, 0.662, 0.115, 0.095, 0.115, {"Hips": 1}),
    (0.640, 0.652, 0.178, 0.140, 0.172, {"Hips": 1}),
    (0.480, 0.640, 0.204, 0.156, 0.196, {"Hips": 1}),
    (0.300, 0.630, 0.198, 0.152, 0.184, {"Hips": 0.5, "Spine": 0.5}),
    (0.100, 0.622, 0.206, 0.158, 0.212, {"Spine": 1}),
    (-0.100, 0.615, 0.218, 0.174, 0.250, {"Spine": 0.3, "Chest": 0.7}),
    (-0.280, 0.612, 0.224, 0.190, 0.272, {"Chest": 1}),
    (-0.400, 0.630, 0.202, 0.172, 0.240, {"Chest": 1}),
    (-0.480, 0.660, 0.135, 0.125, 0.160, {"Chest": 1}),
    (-0.520, 0.680, 0.030, 0.030, 0.030, {"Chest": 1}),
]

NECK = [
    (-0.300, 0.690, 0.172, 0.128, 0.185, {"Chest": 1}),
    (-0.420, 0.745, 0.160, 0.130, 0.165, {"Chest": 0.5, "Neck": 0.5}),
    (-0.520, 0.805, 0.150, 0.126, 0.145, {"Neck": 1}),
    (-0.600, 0.846, 0.142, 0.118, 0.125, {"Neck": 0.4, "Head": 0.6}),
    (-0.660, 0.862, 0.100, 0.090, 0.090, {"Head": 1}),
]


def body_loft(rows):
    return Loft([dict(c=(0, y, z), rx=rx, ry=ry, ryn=ryn, n=2.25, w=w) for y, z, rx, ry, ryn, w in rows])


def ellipsoid_surf(center, radii, rot):
    center = Vector(center)

    def P(lon, lat):
        d = Vector((sin(lon) * cos(lat), -cos(lon) * cos(lat), sin(lat)))
        return center + rot @ Vector((d.x * radii[0], d.y * radii[1], d.z * radii[2]))

    return P


def rosette(mb, rng, P, a0, b0, r, w, outward, dot_chance=0.35):
    """Roseta: anillo roto e irregular, a veces con un punto al centro.
    `w`: pesos fijos (dict) o un Loft, para tomar los pesos de cada vértice según u."""
    wfn = (lambda a, b, p: w.weights(a)) if isinstance(w, Loft) else None
    gap = rng.uniform(0.0, 1.0)
    mb.add_decal(P, a0, b0, r, "Spots", w, nseg=6, inner=rng.uniform(0.48, 0.6), offset=0.004,
                 aspect=rng.uniform(0.78, 1.1), rot=rng.uniform(0, pi), outward=outward,
                 arc=(gap, gap + rng.uniform(0.8, 0.9)), wfn=wfn)
    if rng.random() < dot_chance:
        mb.add_decal(P, a0, b0, r * 0.22, "Spots", w, nseg=4, offset=0.004, rot=rng.uniform(0, pi),
                     outward=outward, wfn=wfn)


def spot(mb, rng, P, a0, b0, r, w, outward, nseg=6):
    wfn = (lambda a, b, p: w.weights(a)) if isinstance(w, Loft) else None
    mb.add_decal(P, a0, b0, r, "Spots", w, nseg=nseg, offset=0.004, aspect=rng.uniform(0.75, 1.15),
                 rot=rng.uniform(0, pi), outward=outward, wfn=wfn)


def build_body(mats, arm):
    mb = MeshBuilder()
    rng = random.Random(7)
    HEAD = {"Head": 1}

    def belly(u, th, p):
        return "FurLight" if sin(th) < -0.55 else "Fur"

    # ── tronco y cuello
    torso = body_loft(TORSO)
    mb.add_loft(torso, None, segs=18, sub=2, matfn=belly)
    neck = body_loft(NECK)
    mb.add_loft(neck, None, segs=14, sub=2, cap0=False, cap1=False, matfn=belly)

    # rosetas del lomo y los costados
    for col in range(10):
        y = 0.655 - col * 0.115
        u = 0.0
        for i in range(len(TORSO) - 1):
            if TORSO[i][0] >= y >= TORSO[i + 1][0]:
                u = i + (TORSO[i][0] - y) / (TORSO[i][0] - TORSO[i + 1][0])
        nrow = 9
        for row in range(nrow):
            th = rad(-28 + (236.0 / (nrow - 1)) * row + (13 if col % 2 else 0))
            uu = u + rng.uniform(-0.07, 0.07)
            tt = th + rng.uniform(-0.05, 0.05)
            if sin(tt) < -0.45:
                continue
            p = torso.point(uu, tt)
            rosette(mb, rng, torso.point, uu, tt, rng.uniform(0.037, 0.046), torso, (0, p.y, 0.62))
    for uu, n_row, r in ((0.35, 5, 0.032), (1.75, 5, 0.028), (2.6, 4, 0.023)):
        for row in range(n_row):
            tt = rad(8 + 164.0 / (n_row - 1) * row) + rng.uniform(-0.08, 0.08)
            rosette(mb, rng, neck.point, uu, tt, r, neck, neck.frame(uu)[0], 0.2)

    # ── collar tejido con cuentas y medallón (color del jugador)
    CW = {"Chest": 0.5, "Neck": 0.5}
    col_rings = []
    for u, d in ((0.70, 0.0), (0.76, 0.022), (1.0, 0.028), (1.24, 0.022), (1.30, 0.0)):
        c, a, b, t, rx, ry, ryn, n = neck.frame(u)
        col_rings.append(dict(c=c, rx=rx + d, ry=ry + d, ryn=ryn + d, n=2.25, w=CW))
    collar = Loft(col_rings)
    mb.add_loft(collar, "Collar", segs=14, cap0=False, cap1=False)
    for i in range(6):
        th = rad(-30 + 48 * i)
        mb.add_sphere(collar.point(2.0, th), 0.023, "Gold", CW, segs=6, rings=3)
    pend = collar.point(2.0, rad(-90)) + Vector((0, -0.012, -0.034))
    mb.add_sphere(pend, (0.046, 0.016, 0.046), "Gold", CW, segs=8, rings=4)
    mb.add_sphere(pend + Vector((0, -0.012, 0)), (0.024, 0.01, 0.024), "Collar", CW, segs=6, rings=3)

    # ── cabeza
    mb.add_sphere(SK, SKR, "Fur", HEAD, segs=16, rings=10, deform=skull_scale)
    # puente de la nariz (dorado) y hocico ancho (crema)
    mb.add_sphere(hp(0, -0.105, 0.010), hr(0.052, 0.088, 0.045), "Fur", HEAD, segs=8, rings=6)
    mb.add_sphere(hp(0, -0.116, -0.034), hr(0.094, 0.078, 0.056), "FurLight", HEAD, segs=12, rings=6)
    for s in (1, -1):   # almohadillas de los bigotes
        mb.add_sphere(hp(s * 0.040, -0.158, -0.038), hr(0.048, 0.038, 0.038), "FurLight", HEAD, segs=8, rings=5)
        for dx, dz in ((0.010, 0.008), (0.030, -0.004), (0.048, 0.010)):
            mb.add_sphere(hp(s * (0.04 + dx * 0.75), -0.192 + dx * 0.3, -0.036 + dz), 0.006 * HS,
                          "Spots", HEAD, segs=4, rings=2)
    # nariz
    mb.add_sphere(hp(0, -0.188, -0.006), hr(0.034, 0.018, 0.021), "Spots", HEAD, segs=8, rings=4)
    # interior de la boca, mandíbula y colmillos
    mb.add_sphere(hp(0, -0.085, -0.066), hr(0.062, 0.084, 0.028), "Mouth", HEAD, segs=8, rings=4)
    JAW = {"Jaw": 1}
    mb.add_sphere(hp(0, -0.090, -0.085), hr(0.076, 0.096, 0.036), "FurLight", JAW, segs=10, rings=6)
    mb.add_sphere(hp(0, -0.078, -0.066), hr(0.054, 0.072, 0.014), "Mouth", JAW, segs=8, rings=4)
    for s in (1, -1):
        fang = Loft([dict(c=hp(s * 0.043, -0.160, -0.054), rx=0.012, ry=0.012, w=HEAD),
                     dict(c=hp(s * 0.043, -0.162, -0.075), rx=0.009, ry=0.009, w=HEAD),
                     dict(c=hp(s * 0.043, -0.160, -0.094), rx=0.002, ry=0.002, w=HEAD)])
        mb.add_loft(fang, "Fang", segs=5, cap0=False)
        fang2 = Loft([dict(c=hp(s * 0.032, -0.166, -0.064), rx=0.009, ry=0.009, w=JAW),
                      dict(c=hp(s * 0.032, -0.168, -0.048), rx=0.007, ry=0.007, w=JAW),
                      dict(c=hp(s * 0.032, -0.166, -0.034), rx=0.002, ry=0.002, w=JAW)])
        mb.add_loft(fang2, "Fang", segs=5, cap0=False)

    for s, sfx in ((1, "_L"), (-1, "_R")):
        # ── ojos de jade con pupila redonda, delineados, y párpado sesgado (mirada felina)
        ce = eye_center(s)
        nd = sdir(s * EYE_LON, EYE_LAT)
        f = sdir(s * rad(24), rad(8))
        rot = f.to_track_quat("Z", "Y").to_matrix()
        mb.add_sphere(ce, EYE_R, "Eye", HEAD, segs=10, rings=12, rot=rot, keep=lambda d: d.z > 0.0,
                      matfn=lambda d: "Spots" if d.z > 0.87 else "Eye")
        liner = nd.to_track_quat("Z", "Y").to_matrix()
        mb.add_sphere(ce + nd * (0.42 * EYE_R), (EYE_R * 1.24, EYE_R * 1.12, EYE_R * 0.34), "Spots", HEAD,
                      segs=10, rings=4, rot=liner)
        n = Vector((0, sin(rad(30)), cos(rad(30))))
        rl = Matrix.Rotation(s * rad(-20), 3, "Y") @ n.to_track_quat("Z", "X").to_matrix()
        mb.add_sphere(ce, EYE_R * 1.2, "Fur", {"Lid" + sfx: 1}, segs=10, rings=10, rot=rl,
                      keep=lambda d: d.z > 0.0, matfn=lambda d: "Spots" if d.z < 0.32 else "Fur")

        # ── orejas redondas y pequeñas: dorso oscuro, interior claro
        ec = hp(s * 0.112, 0.068, 0.108)
        er = Matrix.Rotation(s * rad(-30), 3, "Y") @ Matrix.Rotation(rad(-8), 3, "X")
        EW = {"Ear" + sfx: 1}
        mb.add_sphere(ec, hr(0.046, 0.020, 0.046), "Fur", EW, segs=10, rings=6, rot=er)
        mb.add_sphere(ec + er @ Vector((0, -0.012, -0.004)), hr(0.031, 0.011, 0.033), "FurLight", EW, segs=8,
                      rings=4, rot=er)
        mb.add_sphere(ec + er @ Vector((0, 0.012, 0.004)), hr(0.036, 0.012, 0.037), "Spots", EW, segs=8, rings=4,
                      rot=er)

        # manchas de la cara
        for lon, lat, r in ((13, 50, 0.011), (30, 55, 0.010), (52, 42, 0.012), (68, 22, 0.012),
                            (64, -6, 0.011), (82, 6, 0.012), (80, -24, 0.010), (102, 22, 0.014),
                            (106, -8, 0.013), (42, 70, 0.011), (8, 68, 0.009), (88, 46, 0.012)):
            spot(mb, rng, skull_pt, s * rad(lon), rad(lat), r * HS, HEAD, SK, nseg=5)

        # ── pata delantera: hombro macizo + antebrazo + garra
        fu, fl, fp = "FrontUpper" + sfx, "FrontLower" + sfx, "FrontPaw" + sfx
        X = 0.185
        sh_c = mx((0.166, -0.325, 0.565), s)
        sh_r = (0.098, 0.128, 0.185)
        sh_rot = Matrix.Rotation(rad(10), 3, "X")
        mb.add_sphere(sh_c, sh_r, "Fur", {fu: 1}, segs=12, rings=8, rot=sh_rot)
        fleg = Loft([
            dict(c=mx((X - 0.005, -0.305, 0.52), s), rx=0.070 * LEG, ry=0.086 * LEG, w={fu: 1}),
            dict(c=mx((X, -0.275, 0.40), s), rx=0.062 * LEG, ry=0.072 * LEG, w={fu: 0.5, fl: 0.5}),
            dict(c=mx((X, -0.285, 0.30), s), rx=0.056 * LEG, ry=0.061 * LEG, w={fl: 1}),
            dict(c=mx((X, -0.303, 0.19), s), rx=0.051 * LEG, ry=0.055 * LEG, w={fl: 1}),
            dict(c=mx((X, -0.310, 0.12), s), rx=0.051 * LEG, ry=0.056 * LEG, w={fl: 0.5, fp: 0.5}),
            dict(c=mx((X, -0.322, 0.055), s), rx=0.056 * LEG, ry=0.060 * LEG, w={fp: 1}),
        ])
        mb.add_loft(fleg, "Fur", segs=10, cap0=False, cap1=False)
        paw_c = mx((X, -0.360, 0.050), s)
        mb.add_sphere(paw_c, (0.084, 0.108, 0.050), "Fur", {fp: 1}, segs=10, rings=6)
        for k in (-1, 0, 1):
            tc = paw_c + Vector((k * 0.048, -0.084 + abs(k) * 0.018, -0.014))
            mb.add_sphere(tc, (0.031, 0.038, 0.032), "FurLight", {fp: 1}, segs=6, rings=3)
            claw = Loft([dict(c=tc + Vector((0, -0.028, 0.002)), rx=0.007, ry=0.007, w={fp: 1}),
                         dict(c=tc + Vector((0, -0.040, -0.008)), rx=0.005, ry=0.005, w={fp: 1}),
                         dict(c=tc + Vector((0, -0.046, -0.020)), rx=0.001, ry=0.001, w={fp: 1})])
            mb.add_loft(claw, "Fang", segs=4, cap0=False)
        shP = ellipsoid_surf(sh_c, sh_r, sh_rot)
        for lon, lat in ((62, 38), (100, 42), (80, 12), (118, 8), (58, -14), (98, -20), (132, -12), (76, -44)):
            lo, la = s * rad(lon + rng.uniform(-5, 5)), rad(lat + rng.uniform(-5, 5))
            rosette(mb, rng, shP, lo, la, rng.uniform(0.030, 0.037), {fu: 1}, sh_c, 0.3)
        for uu, deg in ((1.5, 20), (1.6, 160), (2.2, 95), (2.7, 10), (2.8, 170), (3.3, 90), (3.6, 30), (3.8, 150),
                        (0.6, 90), (0.8, 5), (0.8, 175)):
            th = rad(deg + rng.uniform(-12, 12))
            th = th if s > 0 else pi - th
            spot(mb, rng, fleg.point, uu, th, rng.uniform(0.015, 0.021), fleg, fleg.frame(uu)[0])

        # ── pata trasera: anca maciza + pierna con corvejón + garra
        hu, hl, hf, hpw = "HindUpper" + sfx, "HindLower" + sfx, "HindFoot" + sfx, "HindPaw" + sfx
        ha_c = mx((0.166, 0.405, 0.535), s)
        ha_r = (0.108, 0.158, 0.190)
        ha_rot = Matrix.Rotation(rad(-30), 3, "X")
        mb.add_sphere(ha_c, ha_r, "Fur", {hu: 1}, segs=12, rings=8, rot=ha_rot)
        hleg = Loft([
            dict(c=mx((X, 0.335, 0.43), s), rx=0.066 * LEG, ry=0.078 * LEG, w={hu: 0.6, hl: 0.4}),
            dict(c=mx((X, 0.405, 0.335), s), rx=0.054 * LEG, ry=0.064 * LEG, w={hl: 1}),
            dict(c=mx((X, 0.490, 0.255), s), rx=0.046 * LEG, ry=0.054 * LEG, w={hl: 0.6, hf: 0.4}),
            dict(c=mx((X, 0.498, 0.195), s), rx=0.043 * LEG, ry=0.050 * LEG, w={hl: 0.2, hf: 0.8}),
            dict(c=mx((X, 0.478, 0.12), s), rx=0.043 * LEG, ry=0.048 * LEG, w={hf: 1}),
            dict(c=mx((X, 0.462, 0.055), s), rx=0.050 * LEG, ry=0.054 * LEG, w={hf: 0.5, hpw: 0.5}),
        ])
        mb.add_loft(hleg, "Fur", segs=10, sub=2, cap0=False, cap1=False)
        hpaw_c = mx((X, 0.415, 0.050), s)
        mb.add_sphere(hpaw_c, (0.080, 0.106, 0.050), "Fur", {hpw: 1}, segs=10, rings=6)
        for k in (-1, 0, 1):
            tc = hpaw_c + Vector((k * 0.046, -0.082 + abs(k) * 0.018, -0.014))
            mb.add_sphere(tc, (0.030, 0.037, 0.032), "FurLight", {hpw: 1}, segs=6, rings=3)
        haP = ellipsoid_surf(ha_c, ha_r, ha_rot)
        for lon, lat in ((60, 44), (96, 48), (130, 40), (74, 14), (108, 16), (140, 6), (60, -16), (92, -14),
                         (124, -22), (80, -44), (112, -48)):
            lo, la = s * rad(lon + rng.uniform(-5, 5)), rad(lat + rng.uniform(-5, 5))
            rosette(mb, rng, haP, lo, la, rng.uniform(0.032, 0.040), {hu: 1}, ha_c, 0.4)
        for uu, deg in ((0.7, 10), (0.9, 170), (1.5, 90), (2.1, 20), (2.4, 160), (3.2, 90), (3.8, 20), (4.2, 150)):
            th = rad(deg + rng.uniform(-12, 12))
            th = th if s > 0 else pi - th
            spot(mb, rng, hleg.point, uu, th, rng.uniform(0.014, 0.020), hleg, hleg.frame(uu)[0])

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
    rad_t = [0.062, 0.056, 0.050, 0.046, 0.043, 0.041, 0.040, 0.040, 0.040, 0.014]
    tail = Loft([dict(c=(0, y, z), rx=r, ry=r, w=w) for (y, z), r, w in zip(TAIL_PTS, rad_t, tw)])

    def tail_mat(u, th, p):
        if u > 7.5 or 6.5 < u < 7.0 or 5.5 < u < 6.0:
            return "Spots"
        return "FurLight" if sin(th) > 0.6 else "Fur"

    mb.add_loft(tail, None, segs=8, sub=2, cap0=False, cap1=True, matfn=tail_mat)
    for uu, deg in ((1.2, -90), (1.7, -30), (1.9, -150), (2.5, -90), (3.1, -25), (3.2, -155), (3.9, -90),
                    (4.5, -30), (4.6, -150), (5.1, -90)):
        th = rad(deg)
        spot(mb, rng, tail.point, uu, th, 0.018, tail, tail.frame(uu)[0])

    return mb.build("Balam", mats, arm)


# ──────────────────────────────── Animaciones ────────────────────────────────

def both(d):
    out = {}
    for k, v in d.items():
        bone, _, suf = k.partition(".")
        suf = "." + suf if suf else ""
        out[bone + "_L" + suf] = v
        if suf == ".loc":
            out[bone + "_R" + suf] = (-v[0], v[1], v[2])
        elif suf == ".scale":
            out[bone + "_R" + suf] = v
        else:
            out[bone + "_R" + suf] = (v[0], -v[1], -v[2])
    return out


def scaled(p, k):
    out = {}
    for ch, v in p.items():
        if ch.endswith(".scale"):
            out[ch] = tuple(1 + (x - 1) * k for x in v)
        else:
            out[ch] = tuple(x * k for x in v)
    return out


def bump(t, t0, t1):
    if t <= t0 or t >= t1:
        return 0.0
    return sin(pi * (t - t0) / (t1 - t0)) ** 2


def tail_wave(ph, amp=1.0, lift=0.0):
    return {
        "Tail1": (lift, 0, amp * 10 * sin(ph)),
        "Tail2": (lift * 0.5, 0, amp * 14 * sin(ph - 0.7)),
        "Tail3": (0, 0, amp * 18 * sin(ph - 1.4)),
        "Tail4": (8 * amp * sin(ph - 1.0), 0, amp * 22 * sin(ph - 2.1)),
    }


STAND = {}


def idle(t):
    ph = 2 * pi * t / 2.4
    b = sin(ph)
    p = tail_wave(ph, 1.0, 4 + 3 * b)
    p["Hips.loc"] = (0, 0, -0.004 + 0.004 * b)
    p["Spine"] = (0.8 * b, 0, 0)
    p["Chest"] = (-1.2 * b, 0, 0)
    p["Neck"] = (2 * sin(ph + 0.6), 0, 6 * sin(ph))
    p["Head"] = (2 * sin(ph + 1.2), 3 * sin(ph + 0.5), 9 * sin(ph))
    tw = bump(t, 1.5, 1.8)
    p["Ear_L"] = (10 * tw, -8 * tw, 0)
    p["Ear_R"] = (0, 0, 0)
    blink = bump(t, 0.7, 0.9)
    p.update(both({"Lid": (95 * blink, 0, 0)}))
    p["Jaw"] = (1.5 + 1.5 * b, 0, 0)
    return p


def run(t):
    """Galope: fase recogida (lomo arqueado) ↔ fase extendida (vuelo)."""
    ph = 2 * pi * t / 0.45
    p = {}

    def front(sfx, f):
        flex = (0.5 - 0.5 * cos(f)) ** 2
        p["FrontUpper" + sfx] = (-10 + 40 * sin(f), 0, 0)
        p["FrontLower" + sfx] = (-6 - 62 * flex, 0, 0)
        p["FrontPaw" + sfx] = (52 * flex - 16 * max(0.0, -sin(f)), 0, 0)

    def hind(sfx, f):
        flex = (0.5 + 0.5 * cos(f)) ** 2
        p["HindUpper" + sfx] = (6 - 44 * sin(f), 0, 0)
        p["HindLower" + sfx] = (8 + 52 * flex, 0, 0)
        p["HindFoot" + sfx] = (-36 * flex + 26 * max(0.0, -sin(f)), 0, 0)
        p["HindPaw" + sfx] = (20 * max(0.0, -sin(f)), 0, 0)

    front("_L", ph - 0.25)
    front("_R", ph + 0.25)
    hind("_L", ph - 0.35)
    hind("_R", ph - 0.75)
    s = sin(ph)
    p["Hips.loc"] = (0, 0, -0.02 - 0.05 * s)
    p["Hips"] = (-9 * s + 1, 0, 0)
    p["Spine"] = (12 * s + 2, 0, 0)
    p["Chest"] = (7 * s, 0, 0)
    p["Neck"] = (-7 * s + 6, 0, 0)
    p["Head"] = (-5 * s - 6 + 2 * cos(ph), 0, 0)
    p["Tail1"] = (26 + 10 * sin(ph + 1.0), 0, 0)
    p["Tail2"] = (14 + 12 * sin(ph + 0.3), 0, 0)
    p["Tail3"] = (6 + 14 * sin(ph - 0.4), 0, 0)
    p["Tail4"] = (-16 + 16 * sin(ph - 1.1), 0, 0)
    p.update(both({"Ear": (-22 + 5 * cos(ph), 0, 0)}))
    p["Jaw"] = (5 + 3 * s, 0, 0)
    return p


CROUCH = {"Hips.loc": (0, 0.03, -0.13), "Hips": (3, 0, 0), "Spine": (3, 0, 0), "Chest": (2, 0, 0),
          "Neck": (16, 0, 0), "Head": (-20, 0, 0),
          **both({"FrontUpper": (30, 0, 0), "FrontLower": (-62, 0, 0), "FrontPaw": (28, 0, 0),
                  "HindUpper": (-24, 0, 0), "HindLower": (52, 0, 0), "HindFoot": (-30, 0, 0),
                  "Ear": (-28, 0, 0)}),
          "Tail1": (-6, 0, 0), "Tail2": (4, 0, 0)}

JUMP_KEYS = [
    (0.00, CROUCH),
    (0.11, {"Hips.loc": (0, -0.03, -0.02), "Hips": (-22, 0, 0), "Spine": (-6, 0, 0), "Neck": (8, 0, 0),
            "Head": (4, 0, 0),
            **both({"FrontUpper": (-38, 0, 0), "FrontLower": (-78, 0, 0), "FrontPaw": (44, 0, 0),
                    "HindUpper": (30, 0, 0), "HindLower": (10, 0, 0), "HindFoot": (26, 0, 0),
                    "HindPaw": (26, 0, 0), "Ear": (-20, 0, 0)}),
            "Tail1": (20, 0, 0), "Tail2": (10, 0, 0)}),
    (0.26, {"Hips.loc": (0, 0, 0.04), "Hips": (-17, 0, 0), "Spine": (-5, 0, 0), "Chest": (-3, 0, 0),
            "Neck": (10, 0, 0), "Head": (4, 0, 0),
            **both({"FrontUpper": (-62, 0, 0), "FrontLower": (-26, 0, 0), "FrontPaw": (-12, 0, 0),
                    "HindUpper": (46, 0, 0), "HindLower": (18, 0, 0), "HindFoot": (34, 0, 0),
                    "HindPaw": (30, 0, 0), "Ear": (-26, 0, 0)}),
            "Tail1": (34, 0, 0), "Tail2": (16, 0, 0), "Tail3": (10, 0, 0), "Jaw": (8, 0, 0)}),
    (0.40, {"Hips.loc": (0, 0, 0.04), "Hips": (-13, 0, 0), "Spine": (-4, 0, 0), "Chest": (-2, 0, 0),
            "Neck": (8, 0, 0), "Head": (4, 0, 0),
            **both({"FrontUpper": (-56, 0, 0), "FrontLower": (-30, 0, 0), "FrontPaw": (-10, 0, 0),
                    "HindUpper": (40, 0, 0), "HindLower": (24, 0, 0), "HindFoot": (30, 0, 0),
                    "HindPaw": (30, 0, 0), "Ear": (-24, 0, 0)}),
            "Tail1": (30, 0, 0), "Tail2": (18, 0, 0), "Tail3": (14, 0, 0), "Jaw": (6, 0, 0)}),
]


def jump(t):
    return pose_keys(t, JUMP_KEYS)


def fall(t):
    ph = 2 * pi * t / 0.6
    s = sin(ph)
    p = {"Hips": (9, 0, 0), "Spine": (4, 0, 0), "Neck": (-6, 0, 0), "Head": (-6, 0, 0), "Jaw": (6, 0, 0),
         "FrontUpper_L": (-34 + 6 * s, 0, 0), "FrontUpper_R": (-34 - 6 * s, 0, 0),
         "FrontLower_L": (-22 - 6 * s, 0, 0), "FrontLower_R": (-22 + 6 * s, 0, 0),
         "HindUpper_L": (-22 - 6 * s, 0, 0), "HindUpper_R": (-22 + 6 * s, 0, 0),
         "HindLower_L": (50 + 6 * s, 0, 0), "HindLower_R": (50 - 6 * s, 0, 0),
         "Tail1": (40 + 5 * s, 0, 8 * s), "Tail2": (18, 0, 12 * sin(ph - 0.7)),
         "Tail3": (10, 0, 14 * sin(ph - 1.4)), "Tail4": (6, 0, 16 * sin(ph - 2.1))}
    p.update(both({"FrontPaw": (-18, 0, 0), "HindFoot": (-28, 0, 0), "Ear": (-18 + 4 * sin(2 * ph), 0, 0)}))
    return p


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
    p.update(tail_wave(ph, 0.9))
    p["Tail1"] = (34, 0, 9 * sin(ph))
    p["Tail2"] = (22, 0, 12 * sin(ph - 0.7))
    p["Tail3"] = (14, 0, 16 * sin(ph - 1.4))
    p.update(both({"Ear": (-14, 0, 0)}))
    return p


CLAW_WIND = {"Hips": (-9, 0, 0), "Hips.loc": (0, 0.03, -0.02), "Spine": (-4, 0, -6), "Chest": (-4, 0, -8),
             "Neck": (4, 0, 8), "Head": (-4, 0, 6), "Jaw": (10, 0, 0),
             "FrontUpper_R": (-72, 24, 0), "FrontLower_R": (-84, 0, 0), "FrontPaw_R": (-26, 0, 0),
             "FrontUpper_L": (12, 0, 0), "FrontLower_L": (-8, 0, 0),
             **both({"HindUpper": (-10, 0, 0), "HindLower": (22, 0, 0), "HindFoot": (-12, 0, 0),
                     "Ear": (-30, 0, 0)}),
             "Tail1": (16, 0, 18), "Tail2": (6, 0, 16), "Tail3": (0, 0, 14)}
CLAW_HIT = {"Hips": (3, 0, 4), "Hips.loc": (0, -0.05, -0.05), "Spine": (4, 0, 8), "Chest": (6, 0, 12),
            "Neck": (8, 0, -8), "Head": (-10, 0, -10), "Jaw": (26, 0, 0),
            "FrontUpper_R": (-46, -6, -30), "FrontLower_R": (-10, 0, 0), "FrontPaw_R": (36, 0, 0),
            "FrontUpper_L": (22, 0, 0), "FrontLower_L": (-36, 0, 0), "FrontPaw_L": (16, 0, 0),
            **both({"HindUpper": (4, 0, 0), "HindLower": (14, 0, 0), "HindFoot": (4, 0, 0), "Ear": (-34, 0, 0)}),
            "Tail1": (22, 0, -20), "Tail2": (10, 0, -22), "Tail3": (4, 0, -20), "Tail4": (0, 0, -16)}


def claw(t):
    keys = [(0.0, STAND), (0.09, CLAW_WIND), (0.17, CLAW_HIT),
            (0.24, add_pose(scaled(CLAW_HIT, 0.9), {"FrontUpper_R": (10, 0, -6)})),
            (0.35, scaled(CLAW_HIT, 0.12))]
    return pose_keys(t, keys)


def charge(t):
    """Agazapado y tenso: tiembla, menea las ancas y azota la cola."""
    ph = 2 * pi * t / 0.5
    p = add_pose(CROUCH, {"Hips.loc": (0, 0.03, -0.02), "Hips": (-4, 0, 0), "Neck": (4, 0, 0),
                          **both({"HindUpper": (-6, 0, 0), "HindLower": (10, 0, 0), "HindFoot": (-6, 0, 0)})})
    sh = sin(3 * ph)
    p = add_pose(p, {"Hips.loc": (0.004 * sh, 0, 0.003 * sin(3 * ph + 1)), "Hips": (0, 2.2 * sin(ph), 1.2 * sh),
                     "Spine": (1.0 * sin(3 * ph + 0.8), 0, 0), "Chest": (0, -1.2 * sh, 0),
                     "Head": (1.2 * sin(3 * ph + 2), 0, 0), "Jaw": (9 + 3 * sin(3 * ph), 0, 0),
                     **both({"Ear": (-6 + 3 * sh, 0, 0), "FrontLower": (1.5 * sh, 0, 0)})})
    p = add_pose(p, {"Tail1": (10, 0, 24 * sin(ph)), "Tail2": (6, 0, 28 * sin(ph - 0.8)),
                     "Tail3": (4, 0, 30 * sin(ph - 1.6)), "Tail4": (10, 0, 32 * sin(ph - 2.4))})
    return p


RELEASE_UP = {"Hips.loc": (0, -0.12, 0.02), "Hips": (-17, 0, 0), "Spine": (-7, 0, 0), "Chest": (-5, 0, 0),
              "Neck": (10, 0, 0), "Head": (2, 0, 0), "Jaw": (30, 0, 0),
              **both({"FrontUpper": (-98, 10, 0), "FrontLower": (-46, 0, 0), "FrontPaw": (-24, 0, 0),
                      "HindUpper": (30, 0, 0), "HindLower": (8, 0, 0), "HindFoot": (24, 0, 0),
                      "HindPaw": (24, 0, 0), "Ear": (-34, 0, 0)}),
              "Tail1": (30, 0, 0), "Tail2": (14, 0, 0), "Tail3": (8, 0, 0)}
RELEASE_SLAM = {"Hips.loc": (0, -0.20, -0.07), "Hips": (8, 0, 0), "Spine": (8, 0, 0), "Chest": (6, 0, 0),
                "Neck": (2, 0, 0), "Head": (-14, 0, 0), "Jaw": (24, 0, 0),
                **both({"FrontUpper": (-44, 4, -6), "FrontLower": (-10, 0, 0), "FrontPaw": (30, 0, 0),
                        "HindUpper": (22, 0, 0), "HindLower": (16, 0, 0), "HindFoot": (4, 0, 0),
                        "HindPaw": (10, 0, 0), "Ear": (-30, 0, 0)}),
                "Tail1": (36, 0, 0), "Tail2": (20, 0, 0), "Tail3": (10, 0, 0), "Tail4": (-10, 0, 0)}


def charge_release(t):
    start = add_pose(CROUCH, {"Hips.loc": (0, 0.03, -0.02), "Hips": (-4, 0, 0)})
    keys = [(0.0, start), (0.10, RELEASE_UP), (0.19, RELEASE_SLAM),
            (0.27, add_pose(RELEASE_SLAM, {"Hips.loc": (0, 0.01, 0.02), "Hips": (-3, 0, 0),
                                           **both({"FrontUpper": (6, 0, 0)})})),
            (0.45, scaled(RELEASE_SLAM, 0.12))]
    return pose_keys(t, keys)


POUNCE_AIR = {"Hips.loc": (0, -0.05, 0.10), "Hips": (-12, 0, 0), "Spine": (-5, 0, 0), "Chest": (-3, 0, 0),
              "Neck": (10, 0, 0), "Head": (0, 0, 0), "Jaw": (24, 0, 0),
              **both({"FrontUpper": (-78, 6, 0), "FrontLower": (-10, 0, 0), "FrontPaw": (-18, 0, 0),
                      "HindUpper": (54, 0, 0), "HindLower": (12, 0, 0), "HindFoot": (38, 0, 0),
                      "HindPaw": (30, 0, 0), "Ear": (-30, 0, 0)}),
              "Tail1": (28, 0, 0), "Tail2": (16, 0, 0), "Tail3": (10, 0, 0), "Tail4": (4, 0, 0)}
POUNCE_LAND = {"Hips.loc": (0, -0.04, -0.05), "Hips": (11, 0, 0), "Spine": (6, 0, 0), "Neck": (-4, 0, 0),
               "Head": (-10, 0, 0), "Jaw": (14, 0, 0),
               **both({"FrontUpper": (-30, 0, 0), "FrontLower": (-22, 0, 0), "FrontPaw": (22, 0, 0),
                       "HindUpper": (-14, 0, 0), "HindLower": (46, 0, 0), "HindFoot": (-30, 0, 0),
                       "Ear": (-20, 0, 0)}),
               "Tail1": (44, 0, 0), "Tail2": (20, 0, 0), "Tail3": (6, 0, 0)}


def pounce(t):
    keys = [(0.0, scaled(CROUCH, 0.7)), (0.12, add_pose(scaled(POUNCE_AIR, 0.8), {"Hips": (-10, 0, 0)})),
            (0.25, POUNCE_AIR), (0.38, add_pose(POUNCE_AIR, {"Hips": (10, 0, 0), "Hips.loc": (0, 0, -0.02),
                                                             **both({"FrontUpper": (14, 0, 0)})})),
            (0.50, POUNCE_LAND)]
    return pose_keys(t, keys)


HIT_POSE = {"Hips.loc": (0, 0.06, -0.05), "Hips": (-5, 0, 0), "Spine": (-4, 0, 6), "Chest": (-5, 3, 8),
            "Neck": (-20, 0, 12), "Head": (14, 8, 12), "Jaw": (16, 0, 0),
            **both({"FrontUpper": (-18, 0, 0), "FrontLower": (-10, 0, 0), "FrontPaw": (20, 0, 0),
                    "HindUpper": (-12, 0, 0), "HindLower": (26, 0, 0), "HindFoot": (-14, 0, 0),
                    "Ear": (-38, 0, 0), "Lid": (90, 0, 0)}),
            "Tail1": (34, 0, 10), "Tail2": (16, 0, 10), "Tail3": (10, 0, 6)}


def hit(t):
    keys = [(0.0, STAND), (0.07, HIT_POSE), (0.16, scaled(HIT_POSE, 0.65)), (0.30, STAND)]
    p = pose_keys(t, keys)
    lid = K(t, [(0.0, 0.0), (0.05, 90.0), (0.2, 90.0), (0.3, 0.0)])
    p.update(both({"Lid": (lid, 0, 0)}))
    return p


DEATH_BUCKLE = {"Hips.loc": (0.04, 0.03, -0.24), "Hips": (2, -28, 0), "Spine": (4, 0, 6), "Neck": (14, 0, 8),
                "Head": (10, -10, 0), "Jaw": (12, 0, 0),
                **both({"FrontUpper": (26, 0, 0), "FrontLower": (-78, 0, 0), "FrontPaw": (40, 0, 0),
                        "HindUpper": (-30, 0, 0), "HindLower": (70, 0, 0), "HindFoot": (-40, 0, 0),
                        "Ear": (-30, 0, 0), "Lid": (95, 0, 0)}),
                "Tail1": (-8, 0, 10)}
DEATH_END = {"Hips.loc": (0.10, 0.0, -0.50), "Hips": (0, -84, 0), "Spine": (2, 0, 4), "Chest": (0, 0, 4),
             "Neck": (10, -4, 16), "Head": (6, 0, 10), "Jaw": (9, 0, 0),
             "FrontUpper_L": (-26, 8, 0), "FrontLower_L": (-22, 0, 0), "FrontPaw_L": (34, 0, 0),
             "FrontUpper_R": (-8, 0, 0), "FrontLower_R": (-30, 0, 0), "FrontPaw_R": (34, 0, 0),
             "HindUpper_L": (22, 8, 0), "HindLower_L": (14, 0, 0), "HindFoot_L": (26, 0, 0),
             "HindUpper_R": (6, 0, 0), "HindLower_R": (20, 0, 0), "HindFoot_R": (22, 0, 0),
             **both({"Ear": (-16, 0, 0), "Lid": (95, 0, 0)}),
             "Tail1": (6, 0, -30), "Tail2": (10, 0, -24), "Tail3": (6, 0, -20), "Tail4": (-10, 0, -16)}


def death(t):
    bounce = add_pose(DEATH_END, {"Hips.loc": (0, 0, 0.035), "Hips": (0, 5, 0), "Neck": (-8, 0, 0),
                                  **both({"FrontUpper": (-8, 0, 0), "HindUpper": (8, 0, 0)})})
    keys = [(0.0, STAND), (0.12, HIT_POSE), (0.38, DEATH_BUCKLE), (0.66, DEATH_END), (0.77, bounce),
            (0.88, DEATH_END), (1.0, DEATH_END)]
    p = pose_keys(t, keys)
    lid = K(t, [(0.0, 0.0), (0.1, 95.0), (1.0, 95.0)])
    p.update(both({"Lid": (lid, 0, 0)}))
    return p


ANIMS = [
    ("Idle", 2.4, idle),
    ("Run", 0.45, run),
    ("Jump", 0.4, jump),
    ("Fall", 0.6, fall),
    ("Swim", 0.9, swim),
    ("Claw", 0.35, claw),
    ("Charge", 0.5, charge),
    ("ChargeRelease", 0.45, charge_release),
    ("Pounce", 0.5, pounce),
    ("Hit", 0.3, hit),
    ("Death", 1.0, death),
]


# ─────────────────────────────────── Main ───────────────────────────────────

def build():
    kc.reset_scene()
    mats = make_materials()
    arm = kc.build_armature("Armature", make_bones())
    objs = {"Balam": build_body(mats, arm)}
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
