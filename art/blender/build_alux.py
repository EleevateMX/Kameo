"""Genera game/assets/characters/alux.glb — el alux (espíritu guardián maya).

Uso (desde la raíz del repo):
    .tools/blender-venv/bin/python art/blender/build_alux.py

Diseño original: cabeza grande, ojos de jade que brillan, orejas largas y
caídas, huipil de corte recto con jubón y ruedo bordados, faja tejida,
huaraches, y cuatro tocados ocultables (Hat_Palma, Hat_Penacho, Hat_Flor, Hair).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import kameo_common as kc  # noqa: E402  (importa bpy antes que mathutils)
from mathutils import Matrix, Vector  # noqa: E402
from kameo_common import K, Loft, MeshBuilder, add_pose, pose_keys  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(REPO, "game", "assets", "characters", "alux.glb")

sin, cos, pi, rad = math.sin, math.cos, math.pi, math.radians

# ───────────────────────────────── Materiales ─────────────────────────────────

def make_materials():
    m = kc.make_material
    return {
        "Tunic": m("Tunic", "#2ec4a6", 0.85),
        "TunicTrim": m("TunicTrim", "#f8efdc", 0.85),
        "Skin": m("Skin", "#a8704a", 0.7),
        "Eye": m("Eye", "#59ffe0", 0.25, emission=1.2),
        "Sash": m("Sash", "#c93545", 0.8),
        "EyePupil": m("EyePupil", "#0b6f5c", 0.3, emission=0.25),
        "White": m("White", "#fffaf0", 0.6),
        "Hair": m("Hair", "#211712", 0.6),
        "Blush": m("Blush", "#c47a5c", 0.75),
        "Dark": m("Dark", "#3a1c16", 0.9),
        "Sandal": m("Sandal", "#6a4326", 0.8),
        "Pink": m("Pink", "#ff5fa2", 0.75),
        "Red": m("Red", "#e23a30", 0.75),
        "Yellow": m("Yellow", "#ffc233", 0.7),
        "Leaf": m("Leaf", "#3fa34d", 0.8),
        "Straw": m("Straw", "#dcb968", 0.9),
        "StrawDark": m("StrawDark", "#b98d43", 0.9),
        "HatBand": m("HatBand", "#b3372e", 0.8),
        "Gold": m("Gold", "#e8b53a", 0.4, metallic=0.35),
        "Jade": m("Jade", "#2fbf8f", 0.3, emission=0.3),
        "FeatherGreen": m("FeatherGreen", "#16a877", 0.7),
        "FeatherRed": m("FeatherRed", "#d83a2e", 0.7),
        "FeatherBlue": m("FeatherBlue", "#2a8fdc", 0.7),
    }


# ───────────────────────────────── Medidas ─────────────────────────────────

HC = Vector((0.0, 0.0, 1.075))          # centro de la cabeza
HR = (0.255, 0.235, 0.225)              # radios de la cabeza
EYE_R = 0.078
EYE_LON, EYE_LAT = rad(23), rad(-4)

SHOULDER = Vector((0.17, 0.0, 0.80))
ELBOW = Vector((0.238, 0.0, 0.63))
WRIST = Vector((0.288, -0.012, 0.485))
HIP = Vector((0.088, 0.0, 0.42))
KNEE = Vector((0.092, 0.0, 0.235))
ANKLE = Vector((0.092, 0.0, 0.075))


def mx(v, s):
    """Refleja en X para el lado derecho (s = -1)."""
    return Vector((v[0] * s, v[1], v[2]))


def head_scale(d):
    lower = max(0.0, 0.25 - d.z)
    s = 1.0 + 0.17 * lower * abs(d.x) ** 1.5          # cachetes
    s += 0.06 * max(0.0, -d.z) * max(0.0, -d.y)       # barbilla
    return s


def head_dir(lon, lat):
    return Vector((sin(lon) * cos(lat), -cos(lon) * cos(lat), sin(lat)))


def head_pt(lon, lat, off=0.0):
    """Punto de la cabeza. lon 0 = frente, + hacia la izquierda del personaje."""
    d = head_dir(lon, lat)
    s = head_scale(d)
    return HC + Vector((d.x * HR[0] * s, d.y * HR[1] * s, d.z * HR[2] * s)) + d * off


def eye_center(s):
    d = head_dir(s * EYE_LON, EYE_LAT)
    return head_pt(s * EYE_LON, EYE_LAT) - d * 0.043


def eye_forward(s):
    return head_dir(s * rad(9), rad(0))


def brow_center(s):
    return head_pt(s * rad(24), rad(33), 0.004)


# ───────────────────────────────── Esqueleto ─────────────────────────────────

def make_bones():
    b = [
        ("Root", (0, 0, 0), (0, 0, 0.15), None),
        ("Hips", (0, 0, 0.42), (0, 0, 0.55), "Root"),
        ("Spine", (0, 0, 0.55), (0, 0, 0.70), "Hips"),
        ("Chest", (0, 0, 0.70), (0, 0, 0.84), "Spine"),
        ("Head", (0, 0, 0.84), (0, 0, 1.10), "Chest"),
        ("Mouth", (0, -0.23, 0.95), (0, -0.28, 0.95), "Head"),
        ("SashTail", (0.16, -0.13, 0.555), (0.17, -0.14, 0.40), "Hips"),
    ]
    for s, sfx in ((1, "_L"), (-1, "_R")):
        ec = eye_center(s)
        bc = brow_center(s)
        b += [
            ("Ear" + sfx, mx((0.22, 0.0, 1.07), s), mx((0.40, 0.03, 1.10), s), "Head"),
            ("Lid" + sfx, ec, ec + Vector((0, -0.06, 0)), "Head"),
            ("Brow" + sfx, bc, bc + Vector((0, -0.04, 0)), "Head"),
            ("UpperArm" + sfx, mx(SHOULDER, s), mx(ELBOW, s), "Chest"),
            ("Forearm" + sfx, mx(ELBOW, s), mx(WRIST, s), "UpperArm" + sfx),
            ("Hand" + sfx, mx(WRIST, s), mx(WRIST + Vector((0.02, 0, -0.07)), s), "Forearm" + sfx),
            ("Thigh" + sfx, mx(HIP, s), mx(KNEE, s), "Hips"),
            ("Shin" + sfx, mx(KNEE, s), mx(ANKLE, s), "Thigh" + sfx),
            ("Foot" + sfx, mx(ANKLE, s), mx(ANKLE + Vector((0, -0.12, -0.05)), s), "Shin" + sfx),
        ]
    return b


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


def tunic_loft():
    return Loft([dict(c=(0, 0, z), rx=rx, ry=ry, n=3.0, w=w) for z, rx, ry, w in TUNIC_RINGS])


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


def face_surf(loft, face):
    """Una cara del tubo (frente/espalda/costados) parametrizada por la coordenada
    lateral normalizada v ∈ (-1, 1). Evita la singularidad de la superelipse en los ejes,
    que deformaría las calcomanías puestas justo al centro de cada cara."""
    def P(u, v):
        n = loft.frame(u)[7]
        c = max(-1.0, min(1.0, math.copysign(abs(v) ** (n / 2.0), v)))
        if face == "front":
            th = -math.acos(c)
        elif face == "back":
            th = math.acos(c)
        elif face == "left":
            th = math.asin(c)
        else:
            th = pi - math.asin(c)
        return loft.point(u, th)
    return P


def flower(mb, P, a0, b0, r, color, w, outward, wfn=None):
    mb.add_decal(P, a0, b0, r, color, w, nseg=10, star=0.55, offset=0.004, outward=outward, wfn=wfn)
    mb.add_decal(P, a0, b0, r * 0.36, "Red" if color == "Yellow" else "Yellow", w, nseg=6,
                 offset=0.007, outward=outward, wfn=wfn)


def leaf(mb, P, a0, b0, r, rot, w, outward, wfn=None):
    mb.add_decal(P, a0, b0, r, "Leaf", w, nseg=4, aspect=2.3, rot=rot, offset=0.004, outward=outward, wfn=wfn)


def build_body(mats, arm):
    mb = MeshBuilder()
    HEAD = {"Head": 1}

    # ── cabeza y cuello
    mb.add_sphere(HC, HR, "Skin", HEAD, segs=20, rings=12, deform=head_scale)
    neck = Loft([dict(c=(0, 0, 0.80), rx=0.075, ry=0.07, w={"Chest": 1}),
                 dict(c=(0, 0, 0.845), rx=0.07, ry=0.065, w={"Chest": 0.5, "Head": 0.5}),
                 dict(c=(0, 0, 0.90), rx=0.075, ry=0.07, w=HEAD)])
    mb.add_loft(neck, "Skin", segs=10, cap0=False, cap1=False)

    # nariz
    mb.add_sphere(head_pt(0, rad(-16), -0.004), (0.03, 0.028, 0.024), "Skin", HEAD, segs=8, rings=6)

    # boca: sonrisa
    mouth = []
    for i in range(7):
        f = i / 6.0 * 2.0 - 1.0
        lon = rad(18) * f
        lat = rad(-37 + 7.0 * f * f)
        th = 0.010 * (1.0 - 0.8 * f * f)
        mouth.append(dict(c=head_pt(lon, lat, 0.0), rx=th, ry=0.006 + 0.004 * (1 - f * f), w={"Mouth": 1}))
    mb.add_loft(Loft(mouth, side=(0, 0, 1)), "Dark", segs=6)

    for s, sfx in ((1, "_L"), (-1, "_R")):
        # ── ojos
        ce = eye_center(s)
        f = eye_forward(s)
        rot = f.to_track_quat("Z", "Y").to_matrix()
        mb.add_sphere(ce, EYE_R, "Eye", HEAD, segs=16, rings=10, rot=rot,
                      keep=lambda d: d.z > -0.2,
                      matfn=lambda d: "EyePupil" if d.z > 0.88 else "Eye")

        def eye_surf(a, b, ce=ce, f=f):
            v = f + Vector((1, 0, 0)) * a + Vector((0, 0, 1)) * b
            v.normalize()
            return ce + v * EYE_R

        mb.add_decal(eye_surf, -0.36, 0.40, 0.015, "White", HEAD, nseg=6, offset=0.002, outward=ce)

        # párpado superior (media esfera que gira sobre X para parpadear)
        alpha = rad(40)
        n = Vector((0, sin(alpha), cos(alpha)))
        rl = n.to_track_quat("Z", "X").to_matrix()
        mb.add_sphere(ce, EYE_R + 0.007, "Skin", {"Lid" + sfx: 1}, segs=12, rings=12, rot=rl,
                      keep=lambda d: d.z > 0.0,
                      matfn=lambda d: "Hair" if d.z < 0.26 else "Skin")

        # ceja
        bc = brow_center(s)
        e = 1e-3
        ex = (head_pt(s * rad(24) + e, rad(33)) - head_pt(s * rad(24) - e, rad(33))).normalized()
        nz = (bc - HC).normalized()
        ey = nz.cross(ex).normalized()
        ex = ey.cross(nz)
        mrot = Matrix((ex, ey, nz)).transposed()
        mrot = Matrix.Rotation(s * rad(9), 3, nz) @ mrot
        mb.add_sphere(bc, (0.052, 0.014, 0.012), "Hair", {"Brow" + sfx: 1}, segs=8, rings=4, rot=mrot)

        # chapas (rubor)
        mb.add_decal(lambda a, b: head_pt(a, b), s * rad(45), rad(-25), 0.031, "Blush", HEAD, nseg=12,
                     aspect=1.3, offset=0.003, outward=HC)

        # ── orejas: largas, puntiagudas, un poco caídas hacia afuera
        ear_w = [{"Head": 1}, {"Head": 0.5, "Ear" + sfx: 0.5}, {"Ear" + sfx: 1}, {"Ear" + sfx: 1},
                 {"Ear" + sfx: 1}, {"Ear" + sfx: 1}]
        ear_c = [(0.20, 0.010, 1.062), (0.275, 0.018, 1.088), (0.335, 0.030, 1.106),
                 (0.390, 0.042, 1.108), (0.432, 0.054, 1.092), (0.462, 0.064, 1.066)]
        ear_r = [(0.062, 0.030), (0.078, 0.028), (0.066, 0.022), (0.046, 0.016), (0.026, 0.011), (0.004, 0.003)]
        rings = [dict(c=mx(c, s), rx=r[0], ry=r[1], w=w) for c, r, w in zip(ear_c, ear_r, ear_w)]
        mb.add_loft(Loft(rings, side=(0, 0, 1)), "Skin", segs=10, cap0=False)
        # interior de la oreja (cara frontal)
        inner = [dict(c=mx(c, s) + Vector((0, -0.004, 0)), rx=r[0] * 0.62, ry=r[1] * 0.9, w=w)
                 for c, r, w in zip(ear_c[1:5], ear_r[1:5], ear_w[1:5])]
        front = (lambda th: sin(th) > 0.25) if s > 0 else (lambda th: sin(th) < -0.25)
        mb.add_loft(Loft(inner, side=(0, 0, 1)), None, segs=10, cap0=False, cap1=False,
                    matfn=lambda u, th, p, front=front: "Blush" if front(th) else None)

        # ── brazos
        sh, el, wr = mx(SHOULDER, s), mx(ELBOW, s), mx(WRIST, s)
        ua, fa, ha = "UpperArm" + sfx, "Forearm" + sfx, "Hand" + sfx
        arm_rings = [
            dict(c=sh + (sh - el) * 0.15, rx=0.05, ry=0.05, w={ua: 1}),
            dict(c=sh.lerp(el, 0.5), rx=0.05, ry=0.05, w={ua: 1}),
            dict(c=sh.lerp(el, 0.85), rx=0.048, ry=0.048, w={ua: 0.8, fa: 0.2}),
            dict(c=el, rx=0.048, ry=0.048, w={ua: 0.5, fa: 0.5}),
            dict(c=el.lerp(wr, 0.18), rx=0.047, ry=0.047, w={ua: 0.2, fa: 0.8}),
            dict(c=el.lerp(wr, 0.6), rx=0.044, ry=0.044, w={fa: 1}),
            dict(c=wr, rx=0.038, ry=0.038, w={fa: 0.5, ha: 0.5}),
        ]
        mb.add_loft(Loft(arm_rings, side=(0, 1, 0)), "Skin", segs=8, cap0=False, cap1=False)
        hand_c = wr + mx((0.012, -0.004, -0.045), s)
        mb.add_sphere(hand_c, (0.044, 0.05, 0.056), "Skin", {ha: 1}, segs=8, rings=6)
        mb.add_sphere(hand_c + mx((-0.012, -0.045, 0.004), s), (0.018, 0.024, 0.02), "Skin", {ha: 1},
                      segs=6, rings=4)

        # manga corta del huipil con puño bordado
        sl0, sl1 = sh + (sh - el) * 0.25, sh.lerp(el, 0.66)
        sleeve = [
            dict(c=sl0, rx=0.066, ry=0.066, w={"Chest": 0.6, ua: 0.4}),
            dict(c=sl0.lerp(sl1, 0.4), rx=0.074, ry=0.074, w={ua: 1}),
            dict(c=sl0.lerp(sl1, 0.8), rx=0.082, ry=0.082, w={ua: 1}),
            dict(c=sl1, rx=0.086, ry=0.086, w={ua: 1}),
        ]
        mb.add_loft(Loft(sleeve, side=(0, 1, 0)), None, segs=10, cap0=False, cap1=False,
                    matfn=lambda u, th, p: "Tunic" if u < 2.0 else "TunicTrim")
        # interior oscuro de la manga (cara hacia la mano)
        cuff = [dict(c=sl1.lerp(sl0, 0.08), rx=0.046, ry=0.046, w={ua: 1}),
                dict(c=sl1, rx=0.086, ry=0.086, w={ua: 1})]
        mb.add_loft(Loft(cuff, side=(0, 1, 0)), "Dark", segs=10, cap0=False, cap1=False, flip=True)

        # ── piernas
        hp, kn, an = mx(HIP, s), mx(KNEE, s), mx(ANKLE, s)
        th_, sn, ft = "Thigh" + sfx, "Shin" + sfx, "Foot" + sfx
        leg_rings = [
            dict(c=hp + Vector((0, 0, 0.03)), rx=0.07, ry=0.07, w={"Hips": 0.5, th_: 0.5}),
            dict(c=hp.lerp(kn, 0.4), rx=0.068, ry=0.068, w={th_: 1}),
            dict(c=hp.lerp(kn, 0.85), rx=0.06, ry=0.06, w={th_: 0.8, sn: 0.2}),
            dict(c=kn, rx=0.058, ry=0.06, w={th_: 0.5, sn: 0.5}),
            dict(c=kn.lerp(an, 0.18), rx=0.058, ry=0.058, w={th_: 0.2, sn: 0.8}),
            dict(c=kn.lerp(an, 0.6), rx=0.054, ry=0.056, w={sn: 1}),
            dict(c=an, rx=0.046, ry=0.048, w={sn: 0.6, ft: 0.4}),
            dict(c=an + Vector((0, -0.006, -0.035)), rx=0.046, ry=0.05, w={ft: 1}),
        ]
        mb.add_loft(Loft(leg_rings, side=(1, 0, 0)), "Skin", segs=8, cap0=False, cap1=False)
        # pie y huarache
        fc = an + Vector((0, -0.042, -0.027))
        mb.add_sphere(fc, (0.056, 0.10, 0.042), "Skin", {ft: 1}, segs=10, rings=6)
        mb.add_sphere(Vector((fc.x, fc.y - 0.004, 0.016)), (0.066, 0.114, 0.016), "Sandal", {ft: 1},
                      segs=10, rings=4)
        strap = []
        for i in range(7):
            a = pi * i / 6.0
            strap.append(dict(c=(fc.x + 0.060 * cos(a), fc.y - 0.045, 0.018 + 0.068 * sin(a)),
                              rx=0.013, ry=0.006, w={ft: 1}))
        mb.add_loft(Loft(strap, side=(0, 1, 0)), "Sandal", segs=6, cap0=False, cap1=False)
        ank = Loft([dict(c=an + Vector((0, 0, z)), rx=r, ry=r + 0.002, w={sn: 0.6, ft: 0.4})
                    for z, r in ((-0.012, 0.047), (-0.008, 0.055), (0.012, 0.055), (0.016, 0.047))])
        mb.add_loft(ank, "Sandal", segs=8, cap0=False, cap1=False)

    # ── huipil (túnica recta) con cenefa bordada en el ruedo
    tunic = tunic_loft()

    def tw(u, th, p):
        return skirt_weights(tunic.weights(u), p)

    mb.add_loft(tunic, None, segs=20, cap0=False, cap1=True, wfn=tw,
                matfn=lambda u, th, p: "TunicTrim" if u < 1.0 else "Tunic", capmat=(None, "Skin"))
    # cierre por debajo del ruedo (cara hacia abajo) para que no se vea hueco
    hem_under = Loft([dict(c=(0, 0, 0.280), rx=0.232, ry=0.178, n=3.0, w={"Hips": 1}),
                      dict(c=(0, 0, 0.284), rx=0.212, ry=0.158, n=3.0, w={"Hips": 1})])
    mb.add_loft(hem_under, "TunicTrim", segs=20, cap0=False, cap1=False, flip=True,
                wfn=lambda u, th, p: skirt_weights({"Hips": 1}, p))
    # fustán (encaje blanco bajo el ruedo) y sombra interior
    fustan = Loft([dict(c=(0, 0, 0.30), rx=0.214, ry=0.160, n=3.0, w={"Hips": 1}),
                   dict(c=(0, 0, 0.262), rx=0.220, ry=0.166, n=3.0, w={"Hips": 1}),
                   dict(c=(0, 0, 0.232), rx=0.226, ry=0.172, n=3.0, w={"Hips": 1})])
    mb.add_loft(fustan, "White", segs=20, cap0=False, cap1=True,
                wfn=lambda u, th, p: skirt_weights({"Hips": 1}, p), capmat=(None, "Dark"))

    # flores y hojas del ruedo (por caras: frente, espalda y costados)
    hem_cols = ["Pink", "Yellow", "Red"]
    hw = lambda a, b, q: skirt_weights({"Hips": 1}, q)   # noqa: E731
    k = 0
    for face, vs in (("front", (-0.75, -0.45, -0.15, 0.15, 0.45, 0.75)), ("left", (-0.5, 0.0, 0.5)),
                     ("back", (0.75, 0.45, 0.15, -0.15, -0.45, -0.75)), ("right", (0.5, 0.0, -0.5))):
        P = face_surf(tunic, face)
        for i, v in enumerate(vs):
            ctr = (0, 0, P(0.5, v).z)
            flower(mb, P, 0.5, v, 0.030, hem_cols[k % 3], None, ctr, wfn=hw)
            k += 1
            if i + 1 < len(vs):
                vm = 0.5 * (v + vs[i + 1])
                leaf(mb, P, 0.5, vm, 0.0085, rad(60 if i % 2 else -60), None, ctr, wfn=hw)

    # ── jubón: cuello cuadrado bordado sobre los hombros
    CH = {"Chest": 1}
    jub = Loft([dict(c=(0, 0, 0.698), rx=0.212, ry=0.152, n=4.0, w=CH),
                dict(c=(0, 0, 0.704), rx=0.218, ry=0.158, n=4.0, w=CH),
                dict(c=(0, 0, 0.760), rx=0.210, ry=0.148, n=4.0, w=CH),
                dict(c=(0, 0, 0.822), rx=0.196, ry=0.134, n=4.0, w=CH),
                dict(c=(0, 0, 0.852), rx=0.125, ry=0.092, n=4.0, w=CH)])
    mb.add_loft(jub, "TunicTrim", segs=20, cap0=False, cap1=True, capmat=(None, "Skin"))
    jub_under = Loft([dict(c=(0, 0, 0.698), rx=0.212, ry=0.152, n=4.0, w=CH),
                      dict(c=(0, 0, 0.702), rx=0.190, ry=0.132, n=3.4, w=CH)])
    mb.add_loft(jub_under, "TunicTrim", segs=20, cap0=False, cap1=False, flip=True)
    # cenefa de flores grandes al frente y atrás, con hojas y flores chicas entre ellas
    for face in ("front", "back"):
        P = face_surf(jub, face)
        ctr = (0, 0, 0.77)
        flower(mb, P, 2.0, 0.0, 0.036, "Red", CH, ctr)
        for sgn in (1, -1):
            flower(mb, P, 2.0, sgn * 0.5, 0.031, "Pink", CH, ctr)
            flower(mb, P, 2.55, sgn * 0.25, 0.017, "Yellow", CH, ctr)
            flower(mb, P, 2.5, sgn * 0.76, 0.017, "Yellow", CH, ctr)
            leaf(mb, P, 1.7, sgn * 0.25, 0.010, rad(sgn * 35), CH, ctr)
            leaf(mb, P, 1.7, sgn * 0.76, 0.010, rad(-sgn * 35), CH, ctr)
    for face in ("left", "right"):
        P = face_surf(jub, face)
        ctr = (0, 0, 0.77)
        flower(mb, P, 2.0, 0.0, 0.030, "Yellow", CH, ctr)
        for sgn in (1, -1):
            leaf(mb, P, 1.9, sgn * 0.55, 0.010, rad(sgn * 35), CH, ctr)

    # ── faja tejida con nudo y puntas colgantes
    def tun_r(z):
        for (z0, rx0, ry0, _), (z1, rx1, ry1, _) in zip(TUNIC_RINGS, TUNIC_RINGS[1:]):
            if z0 <= z <= z1:
                f = (z - z0) / (z1 - z0)
                return rx0 + (rx1 - rx0) * f, ry0 + (ry1 - ry0) * f
        raise ValueError(z)

    SW = {"Hips": 0.6, "Spine": 0.4}
    sash_rings = []
    for z, d in ((0.508, 0.0), (0.512, 0.014), (0.538, 0.016), (0.572, 0.016), (0.598, 0.014), (0.602, 0.0)):
        rx, ry = tun_r(z)
        sash_rings.append(dict(c=(0, 0, z), rx=rx + d, ry=ry + d, n=3.0, w=SW))
    sash = Loft(sash_rings)
    mb.add_loft(sash, None, segs=20, cap0=False, cap1=False,
                matfn=lambda u, th, p: "Yellow" if 2.0 < u < 3.0 else "Sash")
    kth = rad(-52)
    kp = sash.point(2.5, kth)
    kn_dir = Vector((kp.x, kp.y, 0)).normalized()
    mb.add_sphere(kp + kn_dir * 0.012, (0.036, 0.036, 0.04), "Sash", SW, segs=8, rings=5)
    tang = Vector((-kn_dir.y, kn_dir.x, 0))
    for j, (spread, length) in enumerate(((-0.03, 0.20), (0.035, 0.16))):
        base = kp + kn_dir * 0.016
        tail = []
        for i in range(5):
            f = i / 4.0
            c = base + tang * (spread * f) + kn_dir * (0.022 * f) + Vector((0, 0, -length * f - 0.01))
            tail.append(dict(c=c, rx=0.012 + 0.016 * min(1.0, f * 2.5), ry=0.007,
                             w={"Hips": 1} if i == 0 else {"SashTail": 1}, side=tuple(tang)))
        mb.add_loft(Loft(tail, side=tuple(tang)), None, segs=6, cap0=False, cap1=True,
                    matfn=lambda u, th, p: "Yellow" if u > 3.0 else "Sash")

    return mb.build("Alux", mats, arm)


# ───────────────────────────────── Tocados ─────────────────────────────────

def hairline(lon):
    """Latitud (rad) de la línea del cabello según el ángulo alrededor de la cabeza."""
    a = abs(math.degrees(math.atan2(sin(lon), cos(lon))))
    pts = [(0, 40), (30, 39), (55, 31), (75, 24), (98, 25), (120, 2), (150, -27), (180, -31)]
    for (a0, v0), (a1, v1) in zip(pts, pts[1:]):
        if a0 <= a <= a1:
            f = (a - a0) / (a1 - a0)
            f = f * f * (3 - 2 * f)
            return rad(v0 + (v1 - v0) * f)
    return rad(pts[-1][1])


def build_hair(mats, arm):
    mb = MeshBuilder()
    W = {"Head": 1}
    segs, rows = 24, 5

    def hp(lon, lat, off):
        return head_pt(lon, lat, off + 0.012 * max(0.0, sin(lat)))

    grid = []
    for j in range(segs):
        lon = 2 * pi * j / segs
        hl = hairline(lon)
        a = abs(math.degrees(math.atan2(sin(lon), cos(lon))))
        if a < 60 and j % 2 == 1:
            hl -= rad(7)                       # flequillo en picos
        col = [mb.vert(hp(lon, hl + rad(2), -0.004), W)]
        for k in range(rows):
            lat = hl + (pi / 2 - hl) * (k / rows)
            col.append(mb.vert(hp(lon, lat, 0.022 if k else 0.018), W))
        grid.append(col)
    top = mb.vert(hp(0, pi / 2, 0.022), W)
    for j in range(segs):
        j2 = (j + 1) % segs
        for k in range(rows):
            mb.face((grid[j][k], grid[j2][k], grid[j2][k + 1], grid[j][k + 1]), "Hair")
        mb.face((grid[j][rows], grid[j2][rows], top), "Hair")
    return mb.build("Hair", mats, arm)


def build_hat_palma(mats, arm):
    mb = MeshBuilder()
    W = {"Head": 1}
    under = [(0.398, 1.142), (0.300, 1.160), (0.205, 1.190)]   # cara inferior del ala
    mb.add_loft(Loft([dict(c=(0, 0, z), rx=r, ry=r, w=W) for r, z in under]), "StrawDark", segs=20,
                cap0=False, cap1=False, flip=True)
    prof = [  # (radio, z) — ala ancha y copa cónica redondeada, tejido de palma
        (0.398, 1.142), (0.410, 1.150), (0.352, 1.172),
        (0.300, 1.190), (0.262, 1.206), (0.238, 1.228), (0.225, 1.262), (0.204, 1.305),
        (0.172, 1.350), (0.132, 1.394), (0.086, 1.434), (0.040, 1.462), (0.006, 1.474),
    ]
    loft = Loft([dict(c=(0, 0, z), rx=r, ry=r, w=W) for r, z in prof])

    def mat(u, th, p):
        if u < 1.0:
            return "StrawDark"
        if 5.0 <= u < 6.0:
            return "HatBand"
        return "Straw" if int(u) % 2 else "StrawDark"

    mb.add_loft(loft, None, segs=20, cap0=False, cap1=True, matfn=mat)
    # cuenta de jade en la cinta
    mb.add_sphere((0.0, -0.236, 1.245), (0.022, 0.014, 0.022), "Jade", W, segs=6, rings=4)
    tilt = Matrix.Translation((0, 0, 1.2)) @ Matrix.Rotation(rad(-7), 4, "X") @ Matrix.Translation((0, 0, -1.2))
    mb.transform(tilt)
    return mb.build("Hat_Palma", mats, arm)


def build_hat_penacho(mats, arm):
    mb = MeshBuilder()
    W = {"Head": 1}
    # diadema dorada
    band = []
    for z, d in ((1.166, 0.0), (1.172, 0.042), (1.205, 0.047), (1.238, 0.047), (1.244, 0.0)):
        lat = math.asin((z - HC.z) / HR[2])
        band.append(dict(c=(0, 0, z), rx=HR[0] * cos(lat) + d + 0.004, ry=HR[1] * cos(lat) + d + 0.004, w=W))
    mb.add_loft(Loft(band), "Gold", segs=20, cap0=False, cap1=False)
    mb.add_sphere(head_pt(0, rad(35), 0.049), (0.034, 0.016, 0.034), "Jade", W, segs=8, rings=5)
    for s in (1, -1):
        mb.add_sphere(head_pt(s * rad(38), rad(35), 0.047), (0.018, 0.012, 0.018), "FeatherRed", W, segs=6, rings=4)

    def feather(base, direction, length, width, colors, lean):
        d = Vector(direction).normalized()
        side = Vector((d.z, 0, -d.x))
        rings = []
        prof = [(0.0, 0.25), (0.2, 0.75), (0.5, 1.0), (0.8, 0.8), (0.95, 0.45), (1.0, 0.05)]
        for f, wd in prof:
            c = Vector(base) + d * (length * f) + Vector((0, 1, 0)) * (lean * f * f)
            rings.append(dict(c=c, rx=width * wd, ry=0.007, w=W, side=tuple(side)))
        mb.add_loft(Loft(rings, side=tuple(side)), None, segs=6, cap0=True, cap1=True,
                    matfn=lambda u, th, p: colors[1] if u > 3.0 else colors[0])

    # abanico trasero de plumas largas y una hilera corta al frente
    n = 9
    for i in range(n):
        a = rad(-78 + 156 * i / (n - 1))
        ln = 0.34 - 0.10 * abs(sin(a))
        col = ("FeatherGreen", "FeatherBlue") if i % 2 == 0 else ("FeatherRed", "Yellow")
        feather((sin(a) * 0.185, 0.035, 1.215 + cos(a) * 0.045), (sin(a), 0.16, cos(a)), ln, 0.046, col, 0.05)
    n = 8
    for i in range(n):
        a = rad(-66 + 132 * i / (n - 1))
        col = ("Yellow", "FeatherRed") if i % 2 == 0 else ("FeatherBlue", "FeatherGreen")
        feather((sin(a) * 0.195, -0.005, 1.225 + cos(a) * 0.04), (sin(a), 0.02, cos(a)), 0.17, 0.036, col, 0.02)
    return mb.build("Hat_Penacho", mats, arm)


def build_hat_flor(mats, arm):
    """Flor de mayo (plumeria) sobre la sien izquierda."""
    mb = MeshBuilder()
    W = {"Head": 1}
    lon, lat = rad(58), rad(34)
    base = head_pt(lon, lat, 0.026)
    nrm = (head_dir(lon, lat) + Vector((0, -0.45, 0.1))).normalized()
    ex = nrm.cross(Vector((0, 0, 1))).normalized()
    ey = nrm.cross(ex)
    for i in range(5):
        a = 2 * pi * i / 5 + 0.3
        d = ex * cos(a) + ey * sin(a)
        t = d.cross(nrm)
        # pétalo ovalado, un poco girado (molinillo) y levantado en la punta
        m = Matrix((t, d, nrm)).transposed()
        m = Matrix.Rotation(rad(22), 3, d) @ Matrix.Rotation(rad(-14), 3, t) @ m
        c = base + d * 0.043 + nrm * 0.008
        mb.add_sphere(c, (0.027, 0.046, 0.008), "White", W, segs=8, rings=4, rot=m,
                      matfn=lambda q: "Yellow" if q.y < -0.55 else "White")
    mb.add_sphere(base + nrm * 0.012, (0.014, 0.014, 0.01), "Yellow", W, segs=6, rings=4,
                  rot=Matrix((ex, ey, nrm)).transposed())
    for a, ln in ((2.5, 0.075), (3.6, 0.065)):
        d = ex * cos(a) + ey * sin(a)
        t = d.cross(nrm)
        m = Matrix((t, d, nrm)).transposed()
        mb.add_sphere(base + d * 0.065 - nrm * 0.004, (0.02, ln * 0.6, 0.006), "Leaf", W, segs=6, rings=4, rot=m)
    return mb.build("Hat_Flor", mats, arm)


# ──────────────────────────────── Animaciones ────────────────────────────────

def both(d):
    """{"UpperArm": (rx, ry, rz)} → lado izquierdo tal cual y derecho reflejado."""
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


STAND = {**both({"UpperArm": (2, -5, 0), "Forearm": (-14, 0, 0)})}


def idle(t):
    ph = 2 * pi * t / 2.0
    b = sin(ph)
    p = dict(STAND)
    p["Hips.loc"] = (0, 0, -0.004 + 0.004 * b)
    p["Spine"] = (1.5 + 1.2 * b, 0, 0)
    p["Chest"] = (-1.0 - 1.5 * b, 0, 2.0 * sin(ph - 0.4))
    p["Head"] = (2.0 * sin(ph + 0.9), 3.0 * sin(ph + 1.2), 9.0 * sin(ph))
    p.update(both({"UpperArm": (2 + 2.5 * b, -5 - 2.5 * b, 0), "Forearm": (-14 - 3 * b, 0, 0)}))
    tw = bump(t, 1.15, 1.45)
    p.update(both({"Ear": (0, 3 * sin(ph + 0.5) - 6 * tw, 10 * tw)}))
    p["Ear_R"] = (0, -3 * sin(ph + 0.5), 0)
    blink = bump(t, 0.52, 0.72)
    p.update(both({"Lid": (100 * blink, 0, 0), "Brow.loc": (0, 0, -0.006 * blink)}))
    p["SashTail"] = (2 + 3 * sin(ph + 0.7), 0, 0)
    return p


def run(t):
    ph = 2 * pi * t / 0.6
    p = {}

    def leg(sfx, f):
        p["Thigh" + sfx] = (-42 * sin(f) - 7, 0, 0)
        p["Shin" + sfx] = (12 + 62 * (0.5 + 0.5 * cos(f + 0.35)) ** 1.4, 0, 0)
        p["Foot" + sfx] = (-18 * sin(f) + 8, 0, 0)

    def armf(sfx, f, s):
        p["UpperArm" + sfx] = (40 * sin(f), -s * 9, 0)
        p["Forearm" + sfx] = (-64 - 18 * sin(f - 0.4), 0, 0)

    leg("_L", ph)
    leg("_R", ph + pi)
    armf("_L", ph, 1)
    armf("_R", ph + pi, -1)
    p["Hips.loc"] = (0, 0, 0.004 - 0.028 * cos(2 * ph))
    p["Hips"] = (6, 2.5 * sin(ph), -7 * sin(ph))
    p["Spine"] = (6, -2 * sin(ph), 10 * sin(ph))
    p["Chest"] = (5, 0, 5 * sin(ph))
    p["Head"] = (-12 + 2.5 * cos(2 * ph + 0.5), 0, -8 * sin(ph))
    p.update(both({"Ear": (0, 14 + 11 * sin(2 * ph + 0.6), 18 + 7 * sin(2 * ph))}))
    p["SashTail"] = (22 + 14 * sin(2 * ph + 1.0), 0, 0)
    return p


JUMP_KEYS = [
    (0.00, {"Hips.loc": (0, 0, -0.075), "Spine": (14, 0, 0), "Chest": (8, 0, 0), "Head": (-10, 0, 0),
            **both({"Thigh": (-40, 0, 0), "Shin": (75, 0, 0), "Foot": (-35, 0, 0),
                    "UpperArm": (42, -10, 0), "Forearm": (-30, 0, 0), "Ear": (0, -8, 0)})}),
    (0.10, {"Hips.loc": (0, 0, 0.02), "Spine": (-4, 0, 0), "Chest": (-4, 0, 0), "Head": (-14, 0, 0),
            **both({"Thigh": (6, 0, 0), "Shin": (6, 0, 0), "Foot": (42, 0, 0),
                    "UpperArm": (-110, -16, 0), "Forearm": (-28, 0, 0), "Ear": (0, 18, 6)}),
            "SashTail": (20, 0, 0)}),
    (0.24, {"Hips.loc": (0, 0, 0.03), "Spine": (-6, 0, 0), "Chest": (-5, 0, 0), "Head": (-12, 0, 0),
            "Thigh_L": (-58, 0, 0), "Shin_L": (84, 0, 0), "Foot_L": (22, 0, 0),
            "Thigh_R": (14, 0, 0), "Shin_R": (20, 0, 0), "Foot_R": (42, 0, 0),
            **both({"UpperArm": (-130, 40, 0), "Forearm": (-24, 0, 0), "Ear": (0, 26, 10)}),
            "SashTail": (30, 0, 0)}),
    (0.40, {"Hips.loc": (0, 0, 0.03), "Spine": (-4, 0, 0), "Chest": (-4, 0, 0), "Head": (-10, 0, 0),
            "Thigh_L": (-50, 0, 0), "Shin_L": (76, 0, 0), "Foot_L": (22, 0, 0),
            "Thigh_R": (10, 0, 0), "Shin_R": (24, 0, 0), "Foot_R": (40, 0, 0),
            **both({"UpperArm": (-122, 44, 0), "Forearm": (-30, 0, 0), "Ear": (0, 20, 8)}),
            "SashTail": (24, 0, 0)}),
]


def jump(t):
    return pose_keys(t, JUMP_KEYS)


def fall(t):
    ph = 2 * pi * t / 0.6
    p = {"Spine": (8, 0, 0), "Chest": (4, 0, 2 * sin(ph)), "Head": (8, 0, 0),
         "Hips": (4, 0, 0), "SashTail": (-30 + 8 * sin(2 * ph), 0, 0)}
    p["UpperArm_L"] = (-25, -78 + 9 * sin(ph), 0)
    p["UpperArm_R"] = (-25, 78 + 9 * sin(ph), 0)
    p.update(both({"Forearm": (-38 + 6 * sin(2 * ph), 0, 0),
                   "Ear": (0, -30 + 6 * sin(2 * ph), -6), "Foot": (28, 0, 0)}))
    p["Thigh_L"] = (-30 + 9 * sin(ph), -8, 0)
    p["Thigh_R"] = (-30 - 9 * sin(ph), 8, 0)
    p["Shin_L"] = (48 - 9 * sin(ph + 0.6), 0, 0)
    p["Shin_R"] = (48 + 9 * sin(ph + 0.6), 0, 0)
    return p


SWIM_ARM = [
    (0.00, {"UpperArm": (-150, 6, 0), "Forearm": (-10, 0, 0)}),
    (0.35, {"UpperArm": (-92, 0, 68), "Forearm": (-14, 0, 0)}),
    (0.62, {"UpperArm": (-18, -26, 20), "Forearm": (-72, 0, 0)}),
    (0.90, {"UpperArm": (-70, -14, 0), "Forearm": (-112, 0, 0)}),
    (1.20, {"UpperArm": (-150, 6, 0), "Forearm": (-10, 0, 0)}),
]


def swim(t):
    ph = 2 * pi * t / 1.2
    p = both(pose_keys(t, SWIM_ARM, loop=1.2))
    p["Hips"] = (60 + 4 * sin(ph - 0.6), 0, 0)
    p["Hips.loc"] = (0, 0.14, -0.05 + 0.03 * sin(ph - 1.2))
    p["Spine"] = (-6, 0, 0)
    p["Chest"] = (-8, 0, 0)
    p["Head"] = (-40 + 3 * sin(ph), 0, 0)
    p["Thigh_L"] = (8 + 20 * sin(2 * ph), 0, 0)
    p["Thigh_R"] = (8 - 20 * sin(2 * ph), 0, 0)
    p["Shin_L"] = (18 + 16 * sin(2 * ph - 1.0), 0, 0)
    p["Shin_R"] = (18 - 16 * sin(2 * ph - 1.0), 0, 0)
    p.update(both({"Foot": (38, 0, 0), "Ear": (0, 6 + 5 * sin(ph), 20)}))
    p["SashTail"] = (-25 + 10 * sin(2 * ph), 0, 0)
    return p


CAST_WIND = {"Hips.loc": (0, 0.02, -0.02), "Spine": (-2, 0, -18), "Chest": (-4, 0, -12), "Head": (2, 0, 24),
             "UpperArm_R": (58, 16, 0), "Forearm_R": (-104, 0, 0), "Hand_R": (-10, 0, 0),
             "UpperArm_L": (-38, -10, 0), "Forearm_L": (-42, 0, 0),
             "Thigh_L": (-12, 0, 0), "Shin_L": (16, 0, 0), "Thigh_R": (10, 0, 0), "Shin_R": (6, 0, 0),
             **both({"Ear": (0, -10, -8), "Brow": (0, -10, 0)})}
CAST_THROW = {"Hips.loc": (0, -0.035, -0.035), "Hips": (4, 0, 6), "Spine": (10, 0, 14), "Chest": (8, 0, 12),
              "Head": (-12, 0, -26),
              "UpperArm_R": (-96, 0, -30), "Forearm_R": (-4, 0, 0), "Hand_R": (-28, 0, 0),
              "UpperArm_L": (44, -20, 0), "Forearm_L": (-52, 0, 0),
              "Thigh_L": (-26, 0, 0), "Shin_L": (34, 0, 0), "Foot_L": (-8, 0, 0),
              "Thigh_R": (16, 0, 0), "Shin_R": (10, 0, 0), "Foot_R": (12, 0, 0),
              **both({"Ear": (0, 16, 16), "Brow": (0, -14, 0)}), "SashTail": (18, 0, 0)}


def cast(t):
    keys = [(0.0, STAND), (0.10, CAST_WIND), (0.18, CAST_THROW),
            (0.27, add_pose(scaled(CAST_THROW, 0.94), {"UpperArm_R": (6, 0, 0)})),
            (0.40, add_pose(scaled(CAST_THROW, 0.25), scaled(STAND, 0.75)))]
    return pose_keys(t, keys)


TUCK = {"Spine": (30, 0, 0), "Chest": (28, 0, 0), "Head": (28, 0, 0),
        **both({"Thigh": (-108, 0, 0), "Shin": (122, 0, 0), "Foot": (10, 0, 0),
                "UpperArm": (-72, 6, 0), "Forearm": (-96, 0, 0), "Ear": (0, 10, 34)})}


def dodge(t):
    ang = K(t, [(0.0, 18.0), (0.05, 62.0), (0.25, 318.0), (0.30, 360.0)])
    k = K(t, [(0.0, 0.45), (0.07, 1.0), (0.22, 1.0), (0.30, 0.5)])
    p = scaled(TUCK, k)
    a = rad(ang)
    p["Hips"] = (ang, 0, 0)
    # altura de las caderas: la parte más baja (cadera, cabeza o pies) toca el suelo

    def rot(y, z):
        return y * cos(a) - z * sin(a), y * sin(a) + z * cos(a)

    hy, hz = rot(-0.43 * k, 0.655 - 0.305 * k)      # centro de la cabeza respecto a la cadera
    _fy, fz = rot(-0.10 * k, -0.42 + 0.24 * k)      # pies
    hips_z = max(0.19, 0.25 - hz, 0.05 - fz)
    p["Hips.loc"] = (0, -0.45 * hy, hips_z - 0.42)
    return p


INTERACT_REACH = {"Hips.loc": (0, -0.02, -0.03), "Spine": (14, 0, 0), "Chest": (10, 0, 0), "Head": (6, 0, 0),
                  **both({"UpperArm": (-78, 0, -10), "Forearm": (-20, 0, 0), "Hand": (-16, 0, 0),
                          "Thigh": (-12, 0, 0), "Shin": (24, 0, 0), "Foot": (-12, 0, 0),
                          "Ear": (0, -12, -6), "Brow.loc": (0, 0, 0.006)})}


def interact(t):
    press = add_pose(INTERACT_REACH, {"Spine": (3, 0, 0), **both({"UpperArm": (-8, 0, -4), "Forearm": (14, 0, 0)})})
    keys = [(0.0, STAND), (0.2, INTERACT_REACH), (0.34, press), (0.44, INTERACT_REACH), (0.6, STAND)]
    return pose_keys(t, keys)


HIT_POSE = {"Hips.loc": (0, 0.05, -0.03), "Hips": (-6, 0, 0), "Spine": (-16, 0, 0), "Chest": (-10, 0, 4),
            "Head": (18, 4, 12),
            **both({"UpperArm": (-25, -42, 0), "Forearm": (-58, 0, 0), "Thigh": (-14, 0, 0),
                    "Shin": (26, 0, 0), "Foot": (-12, 0, 0), "Lid": (96, 0, 0), "Brow": (0, 16, 0),
                    "Brow.loc": (0, 0, -0.008), "Ear": (0, 26, 20)}), "SashTail": (-20, 0, 0)}


def hit(t):
    keys = [(0.0, STAND), (0.07, HIT_POSE), (0.16, scaled(HIT_POSE, 0.7)),
            (0.30, add_pose(scaled(HIT_POSE, 0.0), STAND))]
    p = pose_keys(t, keys)
    lid = K(t, [(0.0, 0.0), (0.05, 96.0), (0.2, 96.0), (0.3, 0.0)])
    p.update(both({"Lid": (lid, 0, 0)}))
    return p


DEATH_FALL = {"Hips": (-36, 0, 0), "Hips.loc": (0, 0.14, -0.10), "Spine": (-8, 0, 0), "Head": (-14, 0, 6),
              **both({"Thigh": (-30, 0, 0), "Shin": (70, 0, 0), "UpperArm": (-70, -30, 0),
                      "Forearm": (-40, 0, 0), "Lid": (100, 0, 0), "Ear": (0, -10, -10), "Brow": (0, 16, 0)})}
DEATH_END = {"Hips": (-87, 0, 0), "Hips.loc": (0, 0.38, -0.25), "Spine": (9, 0, 0), "Chest": (7, 0, 0),
             "Head": (8, 0, 20),
             "Thigh_L": (-8, -12, 0), "Thigh_R": (-14, 14, 0), "Shin_L": (12, 0, 0), "Shin_R": (20, 0, 0),
             "UpperArm_L": (0, -68, 0), "UpperArm_R": (0, 52, 0),
             **both({"Forearm": (-26, 0, 0), "Foot": (30, 0, 0), "Lid": (100, 0, 0), "Ear": (0, 30, 0),
                     "Brow": (0, 8, 0)}), "SashTail": (-60, 0, 0)}


def death(t):
    bounce = add_pose(DEATH_END, {"Hips.loc": (0, 0, 0.035), "Head": (-8, 0, 0),
                                  **both({"UpperArm": (-14, 0, 0), "Thigh": (-10, 0, 0)})})
    keys = [(0.0, STAND), (0.12, HIT_POSE), (0.36, DEATH_FALL), (0.60, DEATH_END), (0.70, bounce),
            (0.80, DEATH_END), (0.90, DEATH_END)]
    p = pose_keys(t, keys)
    lid = K(t, [(0.0, 0.0), (0.08, 100.0), (0.9, 100.0)])
    p.update(both({"Lid": (lid, 0, 0)}))
    return p


ANIMS = [
    ("Idle", 2.0, idle),
    ("Run", 0.6, run),
    ("Jump", 0.4, jump),
    ("Fall", 0.6, fall),
    ("Swim", 1.2, swim),
    ("Cast", 0.4, cast),
    ("Dodge", 0.3, dodge),
    ("Interact", 0.6, interact),
    ("Hit", 0.3, hit),
    ("Death", 0.9, death),
]


# ─────────────────────────────────── Main ───────────────────────────────────

def build():
    kc.reset_scene()
    mats = make_materials()
    arm = kc.build_armature("Armature", make_bones())
    objs = {
        "Alux": build_body(mats, arm),
        "Hair": build_hair(mats, arm),
        "Hat_Palma": build_hat_palma(mats, arm),
        "Hat_Penacho": build_hat_penacho(mats, arm),
        "Hat_Flor": build_hat_flor(mats, arm),
    }
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
