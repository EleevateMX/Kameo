"""Genera game/assets/characters/alux.glb — el alux (espíritu guardián maya).

Uso (desde la raíz del repo):
    .tools/blender-venv/bin/python art/blender/build_alux.py

Diseño original: cabezón, ojos grandes de jade que brillan, orejas largas y caídas,
huipil de corte recto con jubón y ruedo bordados, faja tejida, amuleto de jade,
pulseras, sabucán de henequén, huaraches, y cuatro tocados ocultables
(Hat_Palma, Hat_Penacho, Hat_Flor, Hair).

Materiales: el cuerpo usa «Body» (color en los vértices, con oclusión horneada),
«Tunic» (color del jugador), «Eye» y «Jade» (emisivos). Los tocados usan «Headwear».
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import kameo_common as kc  # noqa: E402  (importa bpy antes que mathutils)
from mathutils import Matrix, Vector  # noqa: E402
from kameo_common import (C, K, L, WHITE, Loft, MeshBuilder, Rig, add_pose, blend_pose, both,  # noqa: E402
                          bump, mixc, mulc, ngon, pose_keys, scale_pose, squash)

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(os.environ.get("KAMEO_OUT_DIR") or os.path.join(REPO, "game", "assets", "characters"), "alux.glb")

sin, cos, pi, rad = math.sin, math.cos, math.pi, math.radians

# ───────────────────────────────── Materiales ─────────────────────────────────

def make_materials():
    m = kc.make_material
    return {
        "Body": m("Body", "#ffffff", 0.8),
        "Tunic": m("Tunic", "#2ec4a6", 0.85),
        "Eye": m("Eye", "#59ffe0", 0.25, emission=1.2),
        "Jade": m("Jade", "#3ddba8", 0.3, emission=0.6),
        "Headwear": m("Headwear", "#ffffff", 0.85),
    }


def _pal(mat, **cols):
    return {k: (mat, C(v) if isinstance(v, str) else v) for k, v in cols.items()}


PAL = {
    **_pal("Body", Skin="#a9714b", SkinDeep="#8c563a", SkinLight="#bd8a62", Blush="#c96a55",
           Dark="#3a1c16", Pupil="#052a26", EyeRim="#0c5a4f", White="#fffaf0", Brow="#211712",
           Trim="#f8efdc", Lace="#ffffff", Thread="#c23b2e", Pink="#ff5fa2", Red="#e23a30",
           Yellow="#ffc233", Leaf="#3fa34d", Sash="#c93545", SashDeep="#8a2032",
           Sandal="#7d4c27", Sole="#4a2c17", Cord="#5b3a22", Gold="#e8b53a",
           Henequen="#d9c28c", HenequenDeep="#b0915a", JadeDull="#2a9c78"),
    **_pal("Tunic", Tunic=WHITE, TunicSeam=(0.6, 0.6, 0.6)),
    **_pal("Eye", Eye=WHITE),
    **_pal("Jade", Jade=WHITE),
    **_pal("Headwear", Straw="#dcb968", StrawDeep="#b98d43", HatBand="#b3372e", Hair="#211712",
           HairLight="#3d2a20", Petal="#fff7ec", PetalHeart="#ffc233", HLeaf="#3fa34d",
           HGold="#e8b53a", FGreen="#16a877", FRed="#d83a2e", FBlue="#2a8fdc", FYellow="#ffc233",
           FTeal="#35d6c0"),
}
SKIN, BLUSH, SKIN_DEEP, SKIN_LIGHT = (PAL[k][1] for k in ("Skin", "Blush", "SkinDeep", "SkinLight"))


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
    mb = MeshBuilder(PAL)
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

    # ── amuleto de jade: cordón al cuello y disco con aro dorado sobre el pecho
    pend = Vector((0.0, -0.163, 0.752))
    for s in (1, -1):
        pts = [(0.0, 0.085, 0.862), (0.070 * s, 0.050, 0.860), (0.112 * s, -0.020, 0.858),
               (0.085 * s, -0.098, 0.846), (0.045 * s, -0.150, 0.812), (0.006 * s, -0.160, 0.776)]
        cord = Loft([dict(c=p, rx=0.0055, ry=0.0055, w={"Chest": 1} if i < 4 else {"Chest": 0.4, "Amulet": 0.6})
                     for i, p in enumerate(pts)], side=(0, 0, 1))
        mb.add_loft(cord, "Cord", segs=4, cap0=False, cap1=False)
    AM = {"Amulet": 1}
    mb.add_sphere(pend, (0.036, 0.011, 0.036), "Gold", AM, segs=10, rings=4)
    mb.add_sphere(pend + Vector((0, -0.006, 0)), (0.026, 0.010, 0.026), "Jade", AM, segs=8, rings=4)
    mb.add_sphere(pend + Vector((0, -0.013, 0)), (0.008, 0.005, 0.008), "Gold", AM, segs=5, rings=3)
    for dx in (-0.016, 0.016):        # dos cuentas que flanquean el disco
        mb.add_sphere(pend + Vector((dx, 0.004, 0.036)), 0.008, "Thread", AM, segs=5, rings=3)

    # ── sabucán (morral de henequén) cruzado: correa del hombro izquierdo a la cadera derecha
    lofts = [(tunic, 0.28, 0.85), (jub, 0.698, 0.852), (sash, 0.508, 0.602)]
    for side_sign in (1, -1):         # mitad delantera (−) y trasera (+)… ángulos por delante y por detrás
        ring = []
        n = 9
        for i in range(n):
            g = i / (n - 1.0)
            z = 0.838 - 0.345 * g
            if side_sign < 0:
                th = rad(-28) + rad(-150) * g ** 0.9          # por delante: del hombro izq. a la cadera der.
            else:
                th = rad(30) + (BAG_TH - rad(30)) * g ** 0.8   # por detrás
            p, d = outer_point(lofts, z, th, 0.007)
            ring.append(dict(c=p, rx=0.0045, ry=0.013, w=body_weights(z), side=tuple(d)))
        mb.add_loft(Loft(ring), "Henequen", segs=4, cap0=False, cap1=False,
                    col=lambda p, u, th: PAL["HenequenDeep"][1] if abs(sin(th)) > 0.8 else PAL["Henequen"][1])
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
    mb = MeshBuilder(PAL)
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
    mb = MeshBuilder(PAL)
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
    mb = MeshBuilder(PAL)
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
    mb = MeshBuilder(PAL)
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

def build():
    kc.reset_scene()
    mats = make_materials()
    arm = kc.build_armature("Armature", make_bones())
    body, hair = build_body(), build_hair()
    hats = {"Hat_Palma": build_hat_palma(), "Hat_Penacho": build_hat_penacho(), "Hat_Flor": build_hat_flor()}
    kc.bake_ao([body])
    kc.bake_ao([hair], [hair, body], ground=False)
    for mb in hats.values():
        kc.bake_ao([mb], [mb, body], ground=False)
    objs = {"Alux": body.build("Alux", mats, arm), "Hair": hair.build("Hair", mats, arm)}
    for name, mb in hats.items():
        objs[name] = mb.build(name, mats, arm)
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
