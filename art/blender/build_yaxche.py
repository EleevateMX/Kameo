"""Genera game/assets/characters/yaxche.glb — Chiich Yaxché, «la abuela del claro».

Uso (desde la raíz del repo):
    .tools/blender-venv/bin/python art/blender/build_yaxche.py

La más vieja de los aluxes, guardiana de la gran ceiba. Diseño original: la misma
cabeza, orejas y ojos de jade que el alux (se reutilizan sus medidas de
`build_alux.py`), pero con cuerpo de abuela: espalda encorvada, panza redonda y
piernas cortas bajo un vestido blanco largo de corte regional (cenefas de flores en
el canesú y en el ruedo, fustán de encaje), rebozo lila pálido con puntas de flecos,
collar de cuentas de jade, cabello de plata en un moño bajo con mechones sueltos, una
flor de mayo junto a la oreja izquierda y un bastón de madera de ceiba, más alto que
ella, con un retoño vivo que sostiene un botón de jade y tres luciérnagas de jade.

Nodos de malla: «Yaxche» (cuerpo) y «Staff» (bastón, con piel sobre el hueso StaffBone).
Materiales: «Body» (color en los vértices, con oclusión horneada), «Eye» y «Jade»
(emisivos). No hay «Tunic» ni «Collar»: el juego no debe recolorearla.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import alux_common as kc  # noqa: E402  (importa bpy antes que mathutils)
from mathutils import Matrix, Vector  # noqa: E402
from alux_common import C, K, WHITE, Loft, MeshBuilder, Rig, bump, mixc, ngon  # noqa: E402
import build_alux as A  # noqa: E402  (solo medidas y utilidades de la cabeza; no se modifica)

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(os.environ.get("KAMEO_OUT_DIR") or os.path.join(REPO, "game", "assets", "characters"),
                   "yaxche.glb")

sin, cos, pi, rad = math.sin, math.cos, math.pi, math.radians


# ───────────────────────────────── Materiales ─────────────────────────────────

def make_materials():
    m = kc.make_material
    return {
        "Body": m("Body", "#ffffff", 0.8),
        "Eye": m("Eye", "#59ffe0", 0.25, emission=1.2),
        "Jade": m("Jade", "#3ddba8", 0.3, emission=0.6),
    }


def _pal(mat, **cols):
    return {k: (mat, C(v) if isinstance(v, str) else v) for k, v in cols.items()}


PAL = {
    **_pal("Body", Skin="#a9714b", SkinDeep="#8c563a", SkinLight="#bd8a62", Blush="#c96a55",
           Dark="#3a1c16", Pupil="#052a26", EyeRim="#0c5a4f", White="#fffaf0", LidLine="#4a2e25",
           Brow="#c9c4bc", Hair="#dedad3", HairDeep="#8a8785", HairLight="#f6f4f0",
           Dress="#f0eadf", DressShade="#cbc2b2", Lace="#f7f4ee",
           Magenta="#e0368c", Yellow="#ffc233", Turq="#1fb8b0", Leaf="#3fa34d", Orange="#f0822e",
           Shawl="#b9a2df", ShawlDeep="#9379c2", ShawlLine="#644093",
           Sandal="#7d4c27", Sole="#4a2c17", Gold="#e8b53a",
           Petal="#fff7ec", PetalHeart="#ffc233",
           Wood="#a08a68", WoodDeep="#6c573e", WoodLight="#c0ad8b", Thorn="#574330",
           Sprout="#5cb84c", SproutDeep="#2f8a3c"),
    **_pal("Eye", Eye=WHITE),
    **_pal("Jade", Jade=WHITE),
}
SKIN, BLUSH, SKIN_DEEP, SKIN_LIGHT = (PAL[k][1] for k in ("Skin", "Blush", "SkinDeep", "SkinLight"))


# ───────────────────────────────── Medidas ─────────────────────────────────
# Mismo tamaño de cabeza que el alux; piernas 6 cm más cortas y la espalda curvada
# hacia delante (la cabeza queda 9 cm adelantada). Coronilla a 1.23 m.

def yo(z):
    """Encorvado: desplazamiento hacia delante (−Y) del eje del tronco según la altura."""
    return -0.55 * max(0.0, z - 0.45) ** 2


HC = Vector((0.0, -0.093, 0.990))        # centro de la cabeza
HOFF = HC - A.HC                         # la cabeza del alux, trasladada
EYE_R = A.EYE_R
LID_REST = 11.0                          # párpado superior más caído que el del alux (grados)
BLINK = 100.0 - LID_REST                 # giro que lo cierra del todo

HIP = Vector((0.086, 0.012, 0.36))
KNEE = Vector((0.088, 0.008, 0.20))
ANKLE = Vector((0.088, 0.0, 0.075))
BALL = {"L": Vector((0.088, -0.085, 0.0)), "R": Vector((-0.088, -0.085, 0.0))}

SHOULDER = Vector((0.158, yo(0.735), 0.735))             # se refleja para el lado derecho
ELBOW_L = Vector((0.222, -0.040, 0.575))
WRIST_L = Vector((0.266, -0.054, 0.437))
# brazo derecho: construido ya en la pose de sostener el bastón (antebrazo al frente)
ELBOW_R = Vector((-0.238, -0.046, 0.578))
FORE_R = Vector((-0.36, -0.92, -0.12)).normalized()
WRIST_R = ELBOW_R + FORE_R * 0.154
HAND_M = (Vector((1, 0, 0)) - FORE_R * FORE_R.x).normalized()   # normal de la palma (hacia el cuerpo)
HAND_U = FORE_R.cross(HAND_M)                                   # lado del pulgar (arriba)


def hand_r(f, u, m):
    """Punto en el marco de la mano derecha: f a lo largo del antebrazo, u arriba, m hacia dentro."""
    return WRIST_R + FORE_R * f + HAND_U * u + HAND_M * m


# bastón: pasa por el puño derecho, a un lado de la cara; la contera se apoya en el suelo
# un poco hacia dentro, así que el palo se abre ligeramente hacia fuera al subir
ROD_R = 0.021
GRIP = hand_r(0.055, 0.0, 0.050)
STAFF_BASE = Vector((GRIP.x + 0.024, GRIP.y - 0.020, 0.0))
STAFF_AXIS = (GRIP - STAFF_BASE).normalized()


def staff_c(z):
    """Eje del bastón a la altura z: recto en la empuñadura, algo chueco lejos de ella."""
    c = STAFF_BASE + (GRIP - STAFF_BASE) * (z / GRIP.z)
    e = min(1.0, abs(z - GRIP.z) / 0.16)
    e = e * e * (3 - 2 * e)
    return c + Vector((0.013 * sin(9.0 * z + 0.6), 0.011 * sin(7.0 * z + 2.1), 0.0)) * e


STAFF_TOP = staff_c(1.34)
SPROUT_BASE = STAFF_TOP + Vector((0.0, -0.034, 0.066))
BUD_C = SPROUT_BASE + Vector((0.006, -0.004, 0.138))

EAR_PTS = [(0.185, 0.015, 1.050), (0.255, 0.020, 1.070), (0.322, 0.030, 1.088), (0.387, 0.042, 1.094),
           (0.444, 0.055, 1.082), (0.492, 0.066, 1.052), (0.524, 0.074, 1.012)]      # más caídas
EAR_RAD = A.EAR_RAD


def mx(v, s):
    return Vector((v[0] * s, v[1], v[2]))


def hpt(lon, lat, off=0.0):
    """Punto de la cabeza (lon 0 = frente, + hacia la izquierda del personaje)."""
    return A.head_pt(lon, lat, off) + HOFF


def eye_center(s):
    return A.eye_center(s) + HOFF


def brow_center(s):
    return hpt(s * rad(24), rad(36), 0.006)


MOUTH_C = hpt(0, rad(-37), 0.0)


# ──────────────────────────────── Vestido y rebozo ────────────────────────────────

DRESS_RINGS = [
    # z, centro y, rx, ry (espalda), ryn (frente), pesos
    (0.175, 0.030, 0.250, 0.180, 0.165, {"Hips": 1}),
    (0.240, 0.028, 0.247, 0.182, 0.172, {"Hips": 1}),
    (0.310, 0.022, 0.243, 0.184, 0.184, {"Hips": 1}),
    (0.380, 0.014, 0.238, 0.184, 0.196, {"Hips": 1}),
    (0.450, 0.008, 0.230, 0.180, 0.196, {"Hips": 0.7, "Spine": 0.3}),
    (0.520, 0.004, 0.220, 0.174, 0.186, {"Hips": 0.2, "Spine": 0.8}),
    (0.590, 0.000, 0.208, 0.168, 0.168, {"Spine": 0.8, "Chest": 0.2}),
    (0.650, 0.000, 0.196, 0.160, 0.148, {"Spine": 0.3, "Chest": 0.7}),
    (0.705, 0.000, 0.178, 0.142, 0.124, {"Chest": 1}),
    (0.748, 0.000, 0.122, 0.098, 0.088, {"Chest": 1}),
    (0.778, 0.000, 0.085, 0.075, 0.070, {"Chest": 1}),
]
CAPE_RINGS = [
    # z, rx, ry (espalda), ryn (frente) — de abajo arriba, como el vestido
    (0.605, 0.279, 0.201, 0.179),
    (0.618, 0.275, 0.199, 0.176),
    (0.628, 0.272, 0.197, 0.173),
    (0.650, 0.264, 0.193, 0.167),
    (0.700, 0.242, 0.182, 0.154),
    (0.742, 0.214, 0.164, 0.138),
    (0.772, 0.140, 0.116, 0.100),
    (0.784, 0.100, 0.090, 0.082),
]
CAPE_OPEN = rad(30)                      # media abertura en V del rebozo, por delante
END_TH = rad(37)                         # las puntas cuelgan de los bordes de la V
END_Z = {"L": 0.300, "R": 0.335}         # hasta dónde bajan las puntas (sin los flecos)


def dress_loft():
    return Loft([dict(c=(0, cy + yo(z), z), rx=rx, ry=ry, ryn=ryn, n=2.4, w=w)
                 for z, cy, rx, ry, ryn, w in DRESS_RINGS])


def cape_loft():
    return Loft([dict(c=(0, yo(z) + 0.004, z), rx=rx, ry=ry, ryn=ryn, n=2.15, w={"Chest": 1})
                 for z, rx, ry, ryn in CAPE_RINGS])


def body_weights(z):
    for (z0, *_r0, w0), (z1, *_r1, w1) in zip(DRESS_RINGS, DRESS_RINGS[1:]):
        if z0 <= z <= z1:
            return kc.mix_weights(w0, w1, (z - z0) / (z1 - z0))
    return {"Chest": 1} if z > 0.5 else {"Hips": 1}


def surf_frame(loft, u, th):
    """Punto, normal exterior y tangente lateral (con x creciente) de un loft."""
    e = 1e-3
    p = loft.point(u, th)
    pu = loft.point(min(u + e, loft.umax()), th) - loft.point(max(u - e, 0.0), th)
    pt = loft.point(u, th + e) - loft.point(u, th - e)
    n = pt.cross(pu)
    n.normalize()
    if n.dot(p - loft.frame(u)[0]) < 0.0:
        n = -n
    t = pt.normalized()
    if t.x < 0.0:
        t = -t
    return p, n, t


def front_at_x(loft, z, x):
    u = A.u_at_z(loft, z)
    rx = loft.frame(u)[4]
    return u, A.face_theta(loft, u, "front", max(-0.97, min(0.97, x / rx)))


def cape_drape(v):
    """El borde del rebozo cuelga más por la espalda (se aplica a sus vértices)."""
    f = min(1.0, max(0.0, (0.700 - v.z) / 0.095))
    back = min(1.0, max(0.0, (v.y - yo(v.z)) / 0.15))
    v.z -= 0.085 * f * f * back ** 1.5


def shawl_end_path(s):
    """Anillos (centro, normal, tangente, z) de una punta del rebozo: baja por el borde
    de la V sobre el hombro y luego cuelga a plomo por delante de la panza."""
    cape, dress = cape_loft(), dress_loft()
    th = rad(-90) + s * END_TH
    out = []
    for z in (0.776, 0.757, 0.728, 0.690, 0.650, 0.612):
        p, n, t = surf_frame(cape, A.u_at_z(cape, z), th)
        out.append((p + n * 0.009, n, t, z))
    x_e, y_e = out[-1][0].x, out[-1][0].y
    zs = [0.570, 0.525, 0.480, 0.435, 0.390, 0.345]
    zs = [z for z in zs if z > END_Z["L" if s > 0 else "R"] + 0.02] + [END_Z["L" if s > 0 else "R"]]
    for z in zs:
        x = x_e - s * 0.012 * min(1.0, (0.612 - z) / 0.2)
        u, thd = front_at_x(dress, z, x)
        p, n, t = surf_frame(dress, u, thd)
        p = p + n * 0.013
        if p.y > y_e:                     # la tela cae a plomo desde el borde del rebozo
            p = Vector((p.x, y_e, p.z))
            n, t = Vector((0, -1, 0)), Vector((1, 0, 0))
        out.append((p, n, t, z))
    return out


END_PATH = {"L": shawl_end_path(1), "R": shawl_end_path(-1)}


def end_bone(sfx):
    path = END_PATH[sfx]
    head = min(path, key=lambda q: abs(q[3] - 0.525))[0]
    return head, Vector((head.x, head.y, path[-1][3]))


# ───────────────────────────────── Esqueleto ─────────────────────────────────
# Los 33 huesos del alux con los mismos nombres (SashTail y Bag quedan sin malla, solo
# por compatibilidad), más Index_L (dedo que regaña), ShawlEnd_L/R (puntas del rebozo),
# StaffBone (bastón, hijo de Hand_R; no se llama Staff porque Godot lo renombraría al
# chocar con el nodo de malla), Sprout (retoño) y Fireflies (luciérnagas).

def make_bones():
    hd = Vector((0, yo(0.775), 0.775))
    pend = Vector((0.0, yo(0.66) - 0.158, 0.668))
    b = [
        ("Root", (0, 0, 0), (0, 0, 0.15), None),
        ("Hips", (0, 0.012, 0.36), (0, 0.008, 0.49), "Root"),
        ("Spine", (0, 0.006, 0.49), (0, yo(0.635), 0.635), "Hips"),
        ("Chest", (0, yo(0.635), 0.635), hd, "Spine"),
        ("Head", hd, (0, HC.y, HC.z + 0.05), "Chest"),
        ("Mouth", MOUTH_C, MOUTH_C + Vector((0, -0.05, 0)), "Head"),
        ("Amulet", pend + Vector((0, 0, 0.03)), pend + Vector((0, -0.01, -0.03)), "Chest"),
        ("SashTail", (0.17, 0.14, 0.50), (0.19, 0.15, 0.36), "Hips"),
        ("Bag", (-0.18, 0.15, 0.45), (-0.19, 0.16, 0.34), "Hips"),
    ]
    for s, sfx in ((1, "_L"), (-1, "_R")):
        ec = eye_center(s)
        bc = brow_center(s)
        ear = [mx(Vector(p) + HOFF, s) for p in EAR_PTS]
        b += [
            ("Ear" + sfx, mx(Vector((0.24, 0.02, 1.066)) + HOFF, s), ear[3], "Head"),
            ("EarTip" + sfx, ear[3], ear[6], "Ear" + sfx),
            ("Lid" + sfx, ec, ec + Vector((0, -0.06, 0)), "Head"),
            ("LidLow" + sfx, ec, ec + Vector((0, -0.06, -0.01)), "Head"),
            ("Brow" + sfx, bc, bc + Vector((0, -0.04, 0)), "Head"),
            ("Thigh" + sfx, mx(HIP, s), mx(KNEE, s), "Hips"),
            ("Shin" + sfx, mx(KNEE, s), mx(ANKLE, s), "Thigh" + sfx),
            ("Foot" + sfx, mx(ANKLE, s), mx(ANKLE + Vector((0, -0.12, -0.05)), s), "Shin" + sfx),
        ]
        eh, et = end_bone(sfx[1])
        b.append(("ShawlEnd" + sfx, eh, et, "Spine"))
    wl = WRIST_L
    b += [
        ("UpperArm_L", SHOULDER, ELBOW_L, "Chest"),
        ("Forearm_L", ELBOW_L, wl, "UpperArm_L"),
        ("Hand_L", wl, wl + Vector((0.012, 0, -0.06)), "Forearm_L"),
        ("Fingers_L", wl + Vector((0.014, -0.004, -0.078)), wl + Vector((0.008, -0.004, -0.125)), "Hand_L"),
        ("Index_L", wl + Vector((0.016, -0.030, -0.078)), wl + Vector((0.010, -0.030, -0.125)), "Hand_L"),
        ("UpperArm_R", mx(SHOULDER, -1), ELBOW_R, "Chest"),
        ("Forearm_R", ELBOW_R, WRIST_R, "UpperArm_R"),
        ("Hand_R", WRIST_R, hand_r(0.06, 0, 0), "Forearm_R"),
        ("Fingers_R", hand_r(0.082, 0, 0.026), hand_r(0.092, 0, 0.066), "Hand_R"),
        ("StaffBone", GRIP, GRIP + STAFF_AXIS * 0.30, "Hand_R"),
        ("Sprout", SPROUT_BASE, SPROUT_BASE + Vector((0, 0, 0.10)), "StaffBone"),
        ("Fireflies", BUD_C, BUD_C + Vector((0, 0, 0.06)), "StaffBone"),
    ]
    return b


RIG = Rig(make_bones())


# ─────────────────────────────── Cuerpo (malla) ───────────────────────────────

def hairline(lon):
    """Latitud (rad) de la línea del cabello: frente despejada, recogido hacia atrás."""
    a = abs(math.degrees(math.atan2(sin(lon), cos(lon))))
    pts = [(0, 48), (30, 46), (55, 37), (75, 28), (98, 27), (120, 4), (150, -26), (180, -30)]
    for (a0, v0), (a1, v1) in zip(pts, pts[1:]):
        if a0 <= a <= a1:
            f = (a - a0) / (a1 - a0)
            f = f * f * (3 - 2 * f)
            return rad(v0 + (v1 - v0) * f)
    return rad(pts[-1][1])


def build_head(mb):
    HEAD = {"Head": 1}
    hair, hair_deep, hair_light = (PAL[k][1] for k in ("Hair", "HairDeep", "HairLight"))

    def head_col(p, d):
        c = SKIN
        for s in (1, -1):
            k = max(0.0, 1.0 - (p - hpt(s * rad(47), rad(-27))).length / 0.09)
            c = mixc(c, BLUSH, 0.7 * k * k * (3 - 2 * k))
            k = max(0.0, 1.0 - (p - hpt(s * rad(25), rad(-21))).length / 0.075)     # ojeras suaves
            c = mixc(c, SKIN_DEEP, 0.55 * k * k)
        k = max(0.0, 1.0 - (p - hpt(0, rad(-17))).length / 0.07)
        return mixc(c, BLUSH, 0.35 * k)

    mb.add_sphere(HC, A.HR, "Skin", HEAD, segs=22, rings=14, deform=A.head_scale, col=head_col)
    neck = Loft([dict(c=(0, yo(0.74), 0.74), rx=0.075, ry=0.07, w={"Chest": 1}),
                 dict(c=(0, yo(0.79) - 0.012, 0.795), rx=0.07, ry=0.065, w={"Chest": 0.5, "Head": 0.5}),
                 dict(c=(0, HC.y + 0.035, 0.85), rx=0.075, ry=0.07, w=HEAD)])
    mb.add_loft(neck, "Skin", segs=8, cap0=False, cap1=False)

    # nariz de botón, un poco más ancha que la del alux
    mb.add_sphere(hpt(0, rad(-17), -0.004), (0.039, 0.032, 0.029), "Skin", HEAD, segs=8, rings=6,
                  col=lambda p, d: mixc(SKIN, BLUSH, 0.5 * max(0.0, -d.y)))

    # boca: media sonrisa (la comisura izquierda más alta); el hueso Mouth la abre
    mouth = []
    for i in range(7):
        f = i / 6.0 * 2.0 - 1.0
        mouth.append(dict(c=hpt(rad(17) * f + rad(1.5), rad(-38.5 + 7.0 * f * f + 2.4 * f), 0.001),
                          rx=0.0098 * (1.0 - 0.82 * f * f), ry=0.006, w={"Mouth": 1}))
    mb.add_loft(Loft(mouth, side=(0, 0, 1)), "Dark", segs=6)
    for s, top in ((1, -27.0), (-1, -30.5)):          # surcos de la sonrisa
        fold = [dict(c=hpt(s * rad(lo), rad(la), 0.0015), rx=r, ry=0.004, w=HEAD)
                for lo, la, r in ((22.5, top, 0.0015), (25.5, top - 5.5, 0.0042), (25.0, top - 11.5, 0.0015))]
        mb.add_loft(Loft(fold, side=(1, 0, 0)), "SkinDeep", segs=4)

    for la, half, r in ((23.0, 15.0, 0.0030), (29.5, 11.0, 0.0026)):      # dos arrugas en la frente
        line = [dict(c=hpt(rad(half * g), rad(la + 1.6 * g * g), 0.0012), rx=r * (1.0 - 0.75 * g * g), ry=0.0035,
                     w=HEAD) for g in (-1.0, -0.5, 0.0, 0.5, 1.0)]
        mb.add_loft(Loft(line, side=(0, 0, 1)), "SkinDeep", segs=4)

    for s, sfx in ((1, "_L"), (-1, "_R")):
        # ── ojos: el mismo iris de jade que brilla, aro oscuro, pupila y dos brillos
        ce = eye_center(s)
        f = A.head_dir(s * rad(9), rad(1))
        rot = f.to_track_quat("Z", "Y").to_matrix()
        mb.add_sphere(ce, EYE_R, "Eye", HEAD, segs=16, rings=16, rot=rot, keep=lambda d: d.z > 0.3,
                      matfn=lambda d: "Pupil" if d.z > 0.93 else ("Eye" if d.z > 0.70 else "EyeRim"))

        def eye_surf(a, b, ce=ce, f=f):
            v = f + Vector((1, 0, 0)) * a + Vector((0, 0, 1)) * b
            v.normalize()
            return ce + v * EYE_R

        mb.add_decal(eye_surf, -0.30, 0.26, 0.018, "White", HEAD, nseg=7, offset=0.002, outward=ce)
        mb.add_decal(eye_surf, 0.30, -0.26, 0.009, "White", HEAD, nseg=5, offset=0.002, outward=ce)

        # párpados: el de arriba pesa más (LID_REST) y lleva una pestaña más suave
        a_up = rad(38.0 - LID_REST)
        n = Vector((0, sin(a_up), cos(a_up)))
        rl = n.to_track_quat("Z", "X").to_matrix()
        mb.add_sphere(ce, EYE_R + 0.007, "Skin", {"Lid" + sfx: 1}, segs=12, rings=12, rot=rl,
                      keep=lambda d: d.z > 0.0, matfn=lambda d: "LidLine" if d.z < 0.2 else "Skin",
                      col=lambda p, d: mixc(SKIN_DEEP, SKIN, min(1.0, max(0.0, (d.z - 0.2) * 2.2))))
        n2 = Vector((0, sin(rad(44)), -cos(rad(44))))
        rl2 = n2.to_track_quat("Z", "X").to_matrix()
        mb.add_sphere(ce, EYE_R + 0.005, "Skin", {"LidLow" + sfx: 1}, segs=10, rings=8, rot=rl2,
                      keep=lambda d: d.z > 0.0, col=lambda p, d: mixc(SKIN_DEEP, SKIN, min(1.0, d.z * 2.2)))
        # bolsa bajo el ojo: un pliegue fino
        bag = []
        for i in range(5):
            g = i / 4.0 * 2.0 - 1.0
            bag.append(dict(c=hpt(s * (A.EYE_LON + rad(14.5) * g), A.EYE_LAT + rad(-24.5 + 5.0 * g * g), 0.0015),
                            rx=0.0042 * (1.0 - 0.7 * g * g), ry=0.004, w=HEAD))
        mb.add_loft(Loft(bag, side=(0, 0, 1)), "SkinDeep", segs=4)

        # ceja canosa, poblada, caída hacia fuera (gesto amable)
        brow = []
        for i in range(6):
            g = i / 5.0
            brow.append(dict(c=hpt(s * rad(9 + 28 * g), rad(35.5 + 6.0 * sin(pi * g) - 5.0 * g * g), 0.005),
                             rx=0.0225 * (1 - 0.6 * g) * (0.6 + 0.4 * min(1.0, g * 4)), ry=0.011,
                             w={"Brow" + sfx: 1}))
        mb.add_loft(Loft(brow, side=(0, 0, 1)), "Brow", segs=6,
                    col=lambda p, u, th: mixc(PAL["Brow"][1], hair_deep, 0.5 * max(0.0, -sin(th))))

        # ── orejas largas, más caídas que las del alux, con un arete de oro
        ew = [HEAD, {"Head": 0.6, "Ear" + sfx: 0.4}, {"Ear" + sfx: 1}, {"Ear" + sfx: 0.5, "EarTip" + sfx: 0.5},
              {"EarTip" + sfx: 1}, {"EarTip" + sfx: 1}, {"EarTip" + sfx: 1}]
        rings = [dict(c=mx(Vector(c) + HOFF, s), rx=r[0], ry=r[1], w=w) for c, r, w in zip(EAR_PTS, EAR_RAD, ew)]

        def ear_col(p, u, th, s=s):
            front = max(0.0, sin(th) * s)
            inner = front * max(0.0, 1.0 - abs(cos(th)) * 1.25) * min(1.0, u / 1.2)
            c = mixc(SKIN, BLUSH, 0.25 * min(1.0, u / 5.0))
            return mixc(c, mixc(BLUSH, SKIN_DEEP, 0.35), 0.85 * inner)

        mb.add_loft(Loft(rings, side=(0, 0, 1)), "Skin", segs=10, cap0=False, col=ear_col)
        ring_c = mx(Vector((0.300, 0.022, 0.990)) + HOFF, s)
        mb.add_sphere(ring_c, (0.012, 0.012, 0.016), "Gold", {"Ear" + sfx: 1}, segs=6, rings=4)

        # mechón suelto que cae por delante de la oreja
        lock = [dict(c=hpt(s * rad(lo), rad(la), off), rx=r, ry=r * 0.7, w=HEAD)
                for lo, la, off in ((66, 31, 0.014), (71, 12, 0.026), (72, -8, 0.032),
                                       (69, -25, 0.030), (65, -37, 0.024))
                for r in (0.022 * (1.0 - 0.9 * ((31 - la) / 68.0) ** 2),)]
        mb.add_loft(Loft(lock, side=(0, 1, 0)), "Hair", segs=5, cap0=False,
                    col=lambda p, u, th: mixc(hair, hair_deep, 0.25 + 0.3 * abs(sin(th))))

    # ── cabello de plata, peinado hacia atrás
    segs, rows = 24, 5

    def hp(lon, lat, off):
        return hpt(lon, lat, off + 0.012 * max(0.0, sin(lat)))

    def hair_col(lon, lat):
        streak = 0.5 + 0.5 * sin(lon * 9.0 + 0.7)
        c = mixc(hair, hair_deep, 0.8 * streak * streak)
        return mixc(c, hair_light, 0.6 * bump(math.degrees(lat), 40, 80))

    grid, cols = [], []
    for j in range(segs):
        lon = 2 * pi * j / segs
        hl = hairline(lon)
        col = [mb.vert(hp(lon, hl + rad(2), -0.004), HEAD)]
        cc = [mixc(hair_deep, hair, 0.3)]
        for k in range(rows):
            lat = hl + (pi / 2 - hl) * (k / rows)
            col.append(mb.vert(hp(lon, lat, 0.026 if k else 0.018), HEAD))
            cc.append(hair_col(lon, lat))
        grid.append(col)
        cols.append(cc)
    top = mb.vert(hp(0, pi / 2, 0.026), HEAD)
    for j in range(segs):
        j2 = (j + 1) % segs
        for k in range(rows):
            mb.face((grid[j][k], grid[j2][k], grid[j2][k + 1], grid[j][k + 1]), "Hair",
                    (cols[j][k], cols[j2][k], cols[j2][k + 1], cols[j][k + 1]))
        mb.face((grid[j][rows], grid[j2][rows], top), "Hair", (cols[j][rows], cols[j2][rows], hair))

    # moño bajo en la nuca, con su cinta y un mechón que se escapa
    bun = hpt(pi, rad(-9), 0.050)
    mb.add_sphere(bun, (0.084, 0.064, 0.076), "Hair", HEAD, segs=10, rings=7,
                  col=lambda p, d: mixc(mixc(hair, hair_deep, 0.5 * (0.5 + 0.5 * sin(d.x * 9.0 + d.z * 6.0)) ** 2),
                                        hair_light, 0.5 * max(0.0, d.z) ** 2))
    base = hpt(pi, rad(-9), 0.0)
    ribbon = Loft([dict(c=base + Vector((0, y, 0)), rx=r, ry=r * 0.92, w=HEAD)
                   for y, r in ((-0.004, 0.050), (0.004, 0.064), (0.018, 0.066), (0.026, 0.052))], side=(1, 0, 0))
    mb.add_loft(ribbon, "Magenta", segs=10, cap0=False, cap1=False)
    for s, ln in ((1, 0.085), (-1, 0.105)):          # las dos puntas de la cinta cuelgan bajo el moño
        tail = Loft([dict(c=bun + Vector((s * (0.012 + 0.022 * f), 0.040 - 0.012 * f, -0.060 - ln * f)),
                          rx=0.010 + 0.006 * f, ry=0.004, w=HEAD) for f in (0.0, 0.5, 1.0)], side=(1, 0, 0))
        mb.add_loft(tail, "Magenta", segs=4, cap0=False)
    wisp = Loft([dict(c=bun + Vector(o), rx=r, ry=r * 0.7, w=HEAD)
                 for o, r in (((-0.050, 0.020, -0.045), 0.014), ((-0.066, 0.036, -0.082), 0.012),
                              ((-0.064, 0.040, -0.118), 0.008), ((-0.052, 0.034, -0.140), 0.002))], side=(1, 0, 0))
    mb.add_loft(wisp, "Hair", segs=5, cap0=False)

    # ── flor de mayo (blanca, corazón amarillo) junto a la oreja izquierda
    white, heart = PAL["Petal"][1], PAL["PetalHeart"][1]
    lon, lat, size = rad(63), rad(31), 1.12
    fb = hpt(lon, lat, 0.030)
    nrm = (A.head_dir(lon, lat) + Vector((0, -0.45, 0.1))).normalized()
    ex = nrm.cross(Vector((0, 0, 1))).normalized()
    ey = nrm.cross(ex)
    for i in range(5):
        a = 2 * pi * i / 5 + 0.3
        d = ex * cos(a) + ey * sin(a)
        t = d.cross(nrm)
        m = Matrix((t, d, nrm)).transposed()
        m = Matrix.Rotation(rad(22), 3, d) @ Matrix.Rotation(rad(-14), 3, t) @ m
        mb.add_sphere(fb + d * 0.043 * size + nrm * 0.008 * size, (0.027 * size, 0.046 * size, 0.008 * size),
                      "Petal", HEAD, segs=6, rings=4, rot=m,
                      col=lambda p, q: mixc(white, heart, min(1.0, max(0.0, (-q.y - 0.15) * 1.6))))
    mb.add_sphere(fb + nrm * 0.012 * size, (0.014 * size, 0.014 * size, 0.01 * size), "PetalHeart", HEAD,
                  segs=6, rings=4, rot=Matrix((ex, ey, nrm)).transposed())
    for a, ln in ((2.4, 0.078), (3.7, 0.066)):
        d = ex * cos(a) + ey * sin(a)
        m = Matrix((d.cross(nrm), d, nrm)).transposed()
        mb.add_sphere(fb + d * 0.068 - nrm * 0.004, (0.02, ln * 0.6, 0.006), "Leaf", HEAD, segs=6, rings=4, rot=m)


def build_left_arm(mb):
    s, sfx = 1, "_L"
    sh, el, wr = SHOULDER, ELBOW_L, WRIST_L
    ua, fa, ha, fi = "UpperArm_L", "Forearm_L", "Hand_L", "Fingers_L"
    arm_rings = [
        dict(c=sh + (sh - el) * 0.15, rx=0.05, ry=0.05, w={ua: 1}),
        dict(c=sh.lerp(el, 0.5), rx=0.051, ry=0.051, w={ua: 1}),
        dict(c=sh.lerp(el, 0.85), rx=0.048, ry=0.048, w={ua: 0.8, fa: 0.2}),
        dict(c=el, rx=0.047, ry=0.048, w={ua: 0.5, fa: 0.5}),
        dict(c=el.lerp(wr, 0.18), rx=0.048, ry=0.048, w={ua: 0.2, fa: 0.8}),
        dict(c=el.lerp(wr, 0.6), rx=0.044, ry=0.044, w={fa: 1}),
        dict(c=wr, rx=0.036, ry=0.036, w={fa: 0.5, ha: 0.5}),
    ]
    mb.add_loft(Loft(arm_rings, side=(0, 1, 0)), "Skin", segs=8, cap0=False, cap1=False,
                col=lambda p, u, th: mixc(SKIN, BLUSH, 0.22 * max(0.0, 1 - abs(u - 3.0))))
    # dos pulseras finas de oro
    bd = (wr - el).normalized()
    for k, f in enumerate((0.78, 0.88)):
        bc_ = el.lerp(wr, f)
        r = 0.045 - 0.006 * k
        br = Loft([dict(c=bc_ - bd * 0.006, rx=r - 0.006, ry=r - 0.006, w={fa: 1}),
                   dict(c=bc_ - bd * 0.003, rx=r, ry=r, w={fa: 1}),
                   dict(c=bc_ + bd * 0.003, rx=r, ry=r, w={fa: 1}),
                   dict(c=bc_ + bd * 0.006, rx=r - 0.006, ry=r - 0.006, w={fa: 1})], side=(0, 1, 0))
        mb.add_loft(br, "Gold", segs=8, cap0=False, cap1=False)
    # mano abierta: palma, pulgar, índice con hueso propio (para regañar) y dos dedos agrupados
    pc = wr + Vector((0.014, -0.004, -0.045))
    mb.add_sphere(pc, (0.027, 0.043, 0.047), "Skin", {ha: 1}, segs=8, rings=6,
                  col=lambda p, d: mixc(SKIN, SKIN_LIGHT, 0.7 * max(0.0, -d.x)))
    thumb = Loft([dict(c=pc + Vector((-0.004, -0.030, 0.012)), rx=0.016, ry=0.016, w={ha: 1}),
                  dict(c=pc + Vector((-0.012, -0.052, -0.006)), rx=0.014, ry=0.014, w={ha: 1}),
                  dict(c=pc + Vector((-0.020, -0.062, -0.030)), rx=0.011, ry=0.011, w={ha: 1}),
                  dict(c=pc + Vector((-0.023, -0.063, -0.040)), rx=0.004, ry=0.004, w={ha: 1})], side=(1, 0, 0))
    mb.add_loft(thumb, "Skin", segs=6, cap0=False)
    for k, (dy, ln) in enumerate(((-0.026, 0.052), (0.0, 0.056), (0.026, 0.048))):
        bone = "Index_L" if k == 0 else fi
        root = pc + Vector((0.004, dy, -0.034))
        fng = Loft([dict(c=root, rx=0.0145, ry=0.0145, w={ha: 0.7, bone: 0.3}),
                    dict(c=root + Vector((-0.004, 0, -ln * 0.5)), rx=0.0135, ry=0.0135, w={bone: 1}),
                    dict(c=root + Vector((-0.016, 0, -ln * 0.92)), rx=0.011, ry=0.011, w={bone: 1}),
                    dict(c=root + Vector((-0.020, 0, -ln)), rx=0.004, ry=0.004, w={bone: 1})], side=(0, 1, 0))
        mb.add_loft(fng, "Skin", segs=6, cap0=False,
                    col=lambda p, u, th: mixc(SKIN, BLUSH, 0.3 * min(1.0, u / 3.0)))


def build_right_arm(mb):
    """Brazo derecho en la pose de reposo: antebrazo al frente y el puño cerrado sobre el bastón."""
    sh, el, wr = mx(SHOULDER, -1), ELBOW_R, WRIST_R
    ua, fa, ha, fi = "UpperArm_R", "Forearm_R", "Hand_R", "Fingers_R"
    up = (sh - el).normalized()
    arm_rings = [
        dict(c=sh + up * 0.024, rx=0.05, ry=0.05, w={ua: 1}),
        dict(c=sh.lerp(el, 0.5), rx=0.051, ry=0.051, w={ua: 1}),
        dict(c=sh.lerp(el, 0.82), rx=0.049, ry=0.049, w={ua: 0.8, fa: 0.2}),
        dict(c=el + up * 0.004 - FORE_R * 0.004, rx=0.049, ry=0.049, w={ua: 0.5, fa: 0.5}),
        dict(c=el.lerp(wr, 0.22), rx=0.048, ry=0.048, w={ua: 0.2, fa: 0.8}),
        dict(c=el.lerp(wr, 0.6), rx=0.044, ry=0.044, w={fa: 1}),
        dict(c=wr, rx=0.036, ry=0.036, w={fa: 0.5, ha: 0.5}),
    ]
    mb.add_loft(Loft(arm_rings, side=(1, 0, 0)), "Skin", segs=8, cap0=False, cap1=False,
                col=lambda p, u, th: mixc(SKIN, BLUSH, 0.22 * max(0.0, 1 - abs(u - 3.0))))
    # pulsera de hilo
    bc_ = el.lerp(wr, 0.84)
    br = Loft([dict(c=bc_ - FORE_R * 0.012, rx=0.036, ry=0.036, w={fa: 1}),
               dict(c=bc_ - FORE_R * 0.008, rx=0.045, ry=0.045, w={fa: 1}),
               dict(c=bc_ + FORE_R * 0.008, rx=0.043, ry=0.043, w={fa: 1}),
               dict(c=bc_ + FORE_R * 0.012, rx=0.034, ry=0.034, w={fa: 1})], side=(1, 0, 0))
    mb.add_loft(br, None, segs=8, cap0=False, cap1=False,
                matfn=lambda u, th, p: "Yellow" if 1.0 < u < 2.0 else "Magenta")
    # puño: palma, tres dedos que rodean el bastón y el pulgar por detrás
    rot = Matrix((FORE_R, HAND_U, HAND_M)).transposed()
    mb.add_sphere(hand_r(0.045, 0, 0.004), (0.047, 0.043, 0.027), "Skin", {ha: 1}, segs=8, rings=6, rot=rot,
                  col=lambda p, d: mixc(SKIN, SKIN_LIGHT, 0.6 * max(0.0, d.z)))
    rho = ROD_R + 0.0125
    for du, a1 in ((-0.027, 228), (0.0, 236), (0.027, 222)):
        rings = []
        for i in range(6):
            a = rad(38 + (a1 - 38) * i / 5.0)
            c = hand_r(0.055 + rho * sin(a), du, 0.050 - rho * cos(a))
            r = 0.0138 if i < 4 else (0.0115 if i == 4 else 0.004)
            rings.append(dict(c=c, rx=r, ry=r, w={ha: 0.7, fi: 0.3} if i == 0 else {fi: 1}))
        mb.add_loft(Loft(rings, side=tuple(HAND_U)), "Skin", segs=6, cap0=False,
                    col=lambda p, u, th: mixc(SKIN, BLUSH, 0.3 * min(1.0, u / 5.0)))
    thumb = Loft([dict(c=hand_r(0.034, 0.030, 0.014), rx=0.016, ry=0.016, w={ha: 1}),
                  dict(c=hand_r(0.024, 0.040, 0.046), rx=0.015, ry=0.015, w={ha: 1}),
                  dict(c=hand_r(0.034, 0.040, 0.076), rx=0.012, ry=0.012, w={ha: 1}),
                  dict(c=hand_r(0.050, 0.036, 0.088), rx=0.004, ry=0.004, w={ha: 1})], side=tuple(HAND_U))
    mb.add_loft(thumb, "Skin", segs=6, cap0=False)


def build_legs(mb):
    for s, sfx in ((1, "_L"), (-1, "_R")):
        an = mx(ANKLE, s)
        sn, ft = "Shin" + sfx, "Foot" + sfx
        leg = Loft([dict(c=(an.x, 0.006, 0.150), rx=0.056, ry=0.058, w={sn: 1}),
                    dict(c=(an.x, 0.004, 0.110), rx=0.050, ry=0.052, w={sn: 1}),
                    dict(c=an + Vector((0, 0, 0.012)), rx=0.044, ry=0.046, w={sn: 0.6, ft: 0.4}),
                    dict(c=an + Vector((0, -0.004, -0.024)), rx=0.043, ry=0.047, w={ft: 1})], side=(1, 0, 0))
        mb.add_loft(leg, "Skin", segs=8, cap0=False, cap1=False)
        FT = {ft: 1}
        fx = an.x
        foot = Loft([dict(c=(fx, 0.052, 0.044), rx=0.020, ry=0.022, ryn=0.020, w=FT),
                     dict(c=(fx, 0.022, 0.046), rx=0.042, ry=0.040, ryn=0.026, w=FT),
                     dict(c=(fx, -0.030, 0.048), rx=0.052, ry=0.044, ryn=0.028, w=FT),
                     dict(c=(fx, -0.082, 0.042), rx=0.058, ry=0.030, ryn=0.022, w=FT),
                     dict(c=(fx, -0.124, 0.038), rx=0.056, ry=0.022, ryn=0.018, w=FT),
                     dict(c=(fx, -0.146, 0.036), rx=0.042, ry=0.015, ryn=0.014, w=FT)])
        mb.add_loft(foot, "Skin", segs=8)
        for k, dx in enumerate((-0.038, -0.013, 0.012, 0.036)):
            big = (k == 0) if s > 0 else (k == 3)
            mb.add_sphere((fx + dx, -0.150 + abs(dx) * 0.25, 0.034), (0.0165 if big else 0.013, 0.02,
                          0.0155 if big else 0.013), "SkinLight", FT, segs=5, rings=3)
        # sandalia sencilla: suela y dos tiras
        sole = Loft([dict(c=(fx, 0.062, 0.009), rx=0.026, ry=0.009, n=3.0, w=FT),
                     dict(c=(fx, 0.034, 0.009), rx=0.050, ry=0.009, n=3.0, w=FT),
                     dict(c=(fx, -0.050, 0.009), rx=0.066, ry=0.009, n=3.0, w=FT),
                     dict(c=(fx, -0.130, 0.009), rx=0.066, ry=0.009, n=3.0, w=FT),
                     dict(c=(fx, -0.170, 0.009), rx=0.046, ry=0.009, n=3.0, w=FT)])
        mb.add_loft(sole, None, segs=8, matfn=lambda u, th, p: "Sandal" if sin(th) > 0.5 else "Sole",
                    capmat=("Sole", "Sole"))
        for y0, zt, wd in ((-0.094, 0.076, 0.014), (-0.040, 0.094, 0.011)):
            strap = []
            for i in range(7):
                a = pi * i / 6.0
                strap.append(dict(c=(fx + 0.062 * cos(a), y0 + 0.012 * sin(a), 0.016 + (zt - 0.016) * sin(a)),
                                  rx=wd, ry=0.005, w=FT))
            mb.add_loft(Loft(strap, side=(0, 1, 0)), "Sandal", segs=4, cap0=False, cap1=False)


def flower(loft, u, th, r, color, heart, phase=0.0):
    """Flor de cinco pétalos redondeados, recortada en la superficie, con su corazón."""
    return [(loft.poly(u, th, ngon(15, r, radii=(0.48, 0.96, 0.96), phase=phase)), color),
            (loft.poly(u, th, ngon(5, r * 0.32, phase=phase + 0.3)), heart)]


def build_dress(mb):
    """Vestido blanco de una pieza con cenefas de flores recortadas en la malla, y fustán."""
    dress = dress_loft()
    white, shade = PAL["Dress"][1], PAL["DressShade"][1]
    z_hem, z_band = DRESS_RINGS[0][0], 0.305
    u_band, u_fl = A.u_at_z(dress, z_band), A.u_at_z(dress, 0.240)
    faces = (("front", (-0.72, -0.36, 0.0, 0.36, 0.72)), ("left", (-0.42, 0.42)),
             ("back", (0.72, 0.36, 0.0, -0.36, -0.72)), ("right", (0.42, -0.42)))
    # costura de la triangulación: entre la última flor de la espalda y la primera del costado derecho
    TH0 = 0.5 * (A.face_theta(dress, u_fl, "back", -0.72) + A.face_theta(dress, u_fl, "right", 0.42))
    shapes = [A.band(0.0, A.u_at_z(dress, z_hem + 0.013), TH0, "Turq"),
              A.band(A.u_at_z(dress, z_band - 0.010), u_band, TH0, "Magenta")]
    cols = ["Magenta", "Yellow", "Turq"]
    k = 0
    for face, vs in faces:
        for i, v in enumerate(vs):
            th = A.face_theta(dress, u_fl, face, v)
            c = cols[k % 3]
            shapes += flower(dress, u_fl, th, 0.038, c, "Magenta" if c == "Yellow" else "Yellow", 0.4 * k)
            k += 1
            if i + 1 < len(vs):
                thm = A.face_theta(dress, u_fl, face, 0.5 * (v + vs[i + 1]))
                shapes += A.leaf_shape(dress, u_fl, thm, 0.0095, rad(55 if i % 2 else -55))
    # canesú: dos hilos y tres flores al frente (lo demás lo tapa el rebozo)
    u_y = A.u_at_z(dress, 0.612)
    shapes += [A.band(A.u_at_z(dress, 0.566), A.u_at_z(dress, 0.574), TH0, "Turq"),
               A.band(A.u_at_z(dress, 0.652), A.u_at_z(dress, 0.660), TH0, "Magenta")]
    for v, r, c, h in ((0.0, 0.031, "Magenta", "Yellow"), (0.37, 0.026, "Yellow", "Magenta"),
                       (-0.37, 0.026, "Turq", "Yellow")):
        shapes += flower(dress, u_y, A.face_theta(dress, u_y, "front", v), r, c, h)
    for v in (0.19, -0.19):
        shapes += A.leaf_shape(dress, u_y, A.face_theta(dress, u_y, "front", v), 0.0085, rad(50 if v > 0 else -50))
    mb.add_loft_painted(dress, "Dress", shapes, segs=24, cap0=False, cap1=True, th0=TH0,
                        capmat=(None, "SkinDeep"),
                        col=lambda p, u, th: mixc(shade, white, 0.35 + 0.65 * min(1.0, max(0.0, (p.z - 0.2) / 0.3))))
    r0 = DRESS_RINGS[0]
    hem_under = Loft([dict(c=(0, r0[1], z_hem), rx=r0[2], ry=r0[3], ryn=r0[4], n=2.4, w={"Hips": 1}),
                      dict(c=(0, r0[1], z_hem + 0.004), rx=r0[2] - 0.02, ry=r0[3] - 0.02, ryn=r0[4] - 0.02, n=2.4,
                           w={"Hips": 1})])
    mb.add_loft(hem_under, "DressShade", segs=24, cap0=False, cap1=False, flip=True)
    # fustán: encaje con ondas que asoma bajo el ruedo, y sombra interior
    fustan = Loft([dict(c=(0, 0.030, 0.104), rx=0.242, ry=0.176, ryn=0.158, n=2.4, w={"Hips": 1}),
                   dict(c=(0, 0.030, 0.117), rx=0.240, ry=0.174, ryn=0.156, n=2.4, w={"Hips": 1}),
                   dict(c=(0, 0.030, 0.129), rx=0.239, ry=0.173, ryn=0.155, n=2.4, w={"Hips": 1}),
                   dict(c=(0, 0.030, 0.150), rx=0.236, ry=0.170, ryn=0.153, n=2.4, w={"Hips": 1}),
                   dict(c=(0, 0.030, 0.200), rx=0.230, ry=0.164, ryn=0.148, n=2.4, w={"Hips": 1})])
    v0 = len(mb.verts)
    mb.add_loft(fustan, None, segs=24, cap0=True, cap1=False, capmat=("Dark", None),
                matfn=lambda u, th, p: "Turq" if 1.0 < u < 2.0 else "Lace")
    for j in range(24):                    # ondas del encaje en el borde inferior
        mb.verts[v0 + j].z += 0.010 if j % 2 else -0.008
    return dress


def build_shawl(mb):
    """Rebozo: una esclavina sobre los hombros, abierta en V por delante, con una franja
    cerca del borde, y dos puntas con flecos que cuelgan por delante."""
    cape = cape_loft()
    tau = 2 * pi

    def cape_w(u, th, p):
        base = body_weights(p.z)
        lat = min(1.0, max(0.0, (abs(p.x) - 0.15) / 0.10)) * min(1.0, max(0.0, (0.745 - p.z) / 0.07))
        k = 0.6 * lat
        out = {b: v * (1.0 - k) for b, v in base.items()}
        out["UpperArm_L" if p.x > 0 else "UpperArm_R"] = k
        return {b: v for b, v in out.items() if v > 1e-4}

    def cape_mat(u, th, p):
        a = (th - rad(-90) + pi) % tau - pi
        if abs(a) < CAPE_OPEN:
            return None
        if u < 1.0:
            return "ShawlDeep"
        return "ShawlLine" if u < 2.0 else "Shawl"

    shawl, deep = PAL["Shawl"][1], PAL["ShawlDeep"][1]
    v0 = len(mb.verts)
    mb.add_loft(cape, None, segs=24, cap0=False, cap1=False, matfn=cape_mat, wfn=cape_w)
    lip = Loft([dict(c=(0, yo(0.605) + 0.004, 0.605), rx=0.279, ry=0.201, ryn=0.179, n=2.15, w={"Chest": 1}),
                dict(c=(0, yo(0.612) + 0.004, 0.612), rx=0.256, ry=0.180, ryn=0.158, n=2.15, w={"Chest": 1})])
    mb.add_loft(lip, None, segs=24, cap0=False, cap1=False, flip=True, wfn=cape_w,
                matfn=lambda u, th, p: None if abs((th - rad(-90) + pi) % tau - pi) < CAPE_OPEN else "ShawlLine")
    for i in range(v0, len(mb.verts)):
        cape_drape(mb.verts[i])

    for s, sfx in ((1, "_L"), (-1, "_R")):
        path = END_PATH[sfx[1]]
        z_end = path[-1][3]
        bone = "ShawlEnd" + sfx
        rings = []
        for i, (p, n, t, z) in enumerate(path):
            f = min(1.0, max(0.0, (0.575 - z) / 0.07))
            w = kc.mix_weights(body_weights(z), {bone: 1}, f)
            hw = 0.024 + 0.021 * min(1.0, i / 3.0)
            rings.append(dict(c=p, rx=hw, ry=0.006, n=2.6, w=w, side=tuple(t)))

        def end_mat(u, th, p, z_end=z_end):
            if p.z < z_end + 0.014:
                return "ShawlLine"
            if p.z < z_end + 0.034:
                return "Magenta"
            if p.z < z_end + 0.048:
                return "ShawlLine"
            return "Shawl"

        mb.add_loft(Loft(rings), None, segs=8, sub=1, cap0=True, cap1=True, matfn=end_mat,
                    col=lambda p, u, th: mixc(shawl, deep, 0.25 * max(0.0, sin(th))))
        end, t_end = path[-1][0], path[-1][2]
        for j in range(5):                 # flecos
            o = (j - 2) * 0.019
            fr = Loft([dict(c=end + t_end * o + Vector((0, 0, 0.004)), rx=0.0065, ry=0.005, w={bone: 1}),
                       dict(c=end + t_end * (o * 1.12) + Vector((0, -0.002, -0.050 + 0.008 * (j % 2))),
                            rx=0.004, ry=0.004, w={bone: 1})], side=tuple(t_end))
            mb.add_loft(fr, "Shawl" if j % 2 else "ShawlDeep", segs=4, cap0=False)


def build_necklace(mb, dress):
    """Collar de cuentas de jade sobre el canesú, con una gota central (hueso Amulet)."""
    n = 9
    for i in range(n):
        a = i / (n - 1.0) * 2.0 - 1.0
        x = 0.088 * a
        z = 0.744 - 0.066 * (1.0 - abs(a) ** 1.8)
        u, th = front_at_x(dress, z, x)
        p, nr, _t = surf_frame(dress, u, th)
        if i == n // 2:
            continue
        mb.add_sphere(p + nr * 0.009, 0.0125 - 0.002 * abs(a), "Jade", {"Chest": 1}, segs=6, rings=4)
    u, th = front_at_x(dress, 0.668, 0.0)
    p, nr, _t = surf_frame(dress, u, th)
    AM = {"Amulet": 1}
    mb.add_sphere(p + nr * 0.012, (0.020, 0.014, 0.025), "Jade", AM, segs=8, rings=5)
    mb.add_sphere(p + nr * 0.010 + Vector((0, 0, 0.026)), 0.009, "Gold", AM, segs=5, rings=3)


def build_body():
    mb = MeshBuilder(PAL)
    build_head(mb)
    build_left_arm(mb)
    build_right_arm(mb)
    build_legs(mb)
    dress = build_dress(mb)
    build_shawl(mb)
    build_necklace(mb, dress)
    return mb


# ───────────────────────────────── Bastón ─────────────────────────────────

def build_staff():
    mb = MeshBuilder(PAL)
    W, SP, FF = {"StaffBone": 1}, {"Sprout": 1}, {"Fireflies": 1}
    wood, deep, light = (PAL[k][1] for k in ("Wood", "WoodDeep", "WoodLight"))

    def wood_col(p, u, th):
        g = 0.5 + 0.5 * sin(3.0 * th + 5.0 * p.z)
        c = mixc(wood, light, 0.55 * g * g)
        c = mixc(c, deep, 0.5 * max(0.0, sin(2.0 * th + 17.0 * p.z)) ** 3)
        return mixc(c, deep, 0.8 * max(0.0, 1.0 - p.z / 0.10))             # contera oscura

    prof = [(0.0, 0.013), (0.035, 0.0195), (0.20, 0.0215), (0.38, 0.0205), (GRIP.z - 0.07, ROD_R),
            (GRIP.z + 0.07, ROD_R), (0.76, 0.0215), (0.90, 0.0235), (1.03, 0.0225), (1.15, 0.0245),
            (1.25, 0.0265), (1.31, 0.0300)]
    rings = [dict(c=staff_c(z), rx=r, ry=r, w=W) for z, r in prof]
    # arriba, el palo se dobla hacia delante en un cayado corto y nudoso
    for off, r in (((0.0, -0.004, 0.030), 0.0315), ((0.0, -0.026, 0.060), 0.0290), ((0.0, -0.060, 0.076), 0.0240),
                   ((0.0, -0.092, 0.070), 0.0190), ((0.0, -0.112, 0.054), 0.0125)):
        rings.append(dict(c=staff_c(1.31) + Vector(off), rx=r, ry=r, w=W))
    mb.add_loft(Loft(rings), "Wood", segs=8, col=wood_col)
    # espinas cónicas de ceiba
    for z, a, ln in ((0.80, 0.4, 0.026), (0.93, 2.6, 0.030), (1.04, 4.4, 0.028), (1.13, 1.3, 0.032),
                     (1.21, 3.4, 0.030), (1.27, 5.5, 0.026)):
        d = Vector((cos(a), sin(a), 0.25)).normalized()
        c = staff_c(z)
        side = d.cross(Vector((0, 0, 1))).normalized()
        th = Loft([dict(c=c + d * 0.016, rx=0.0125, ry=0.0125, w=W, side=tuple(side)),
                   dict(c=c + d * (0.020 + ln), rx=0.0012, ry=0.0012, w=W, side=tuple(side))], side=tuple(side))
        mb.add_loft(th, "Thorn", segs=5, cap0=False, col=lambda p, u, th_: mixc(wood, PAL["Thorn"][1], u))
    # hilos de colores enrollados sobre la empuñadura
    for k, key in enumerate(("Magenta", "Yellow", "Turq", "Magenta")):
        z0 = GRIP.z + 0.085 + 0.018 * k
        wrap = Loft([dict(c=staff_c(z0 + dz), rx=ROD_R + dr, ry=ROD_R + dr, w=W)
                     for dz, dr in ((0.0, 0.0), (0.003, 0.0055), (0.014, 0.0055), (0.017, 0.0))])
        mb.add_loft(wrap, key, segs=8, cap0=False, cap1=False)
    # retoño vivo: tallo, dos hojas, tres sépalos y el botón de jade
    tw = [(Vector((0.0, 0.010, -0.022)), 0.0100, W), (Vector((0.0, 0.0, 0.0)), 0.0085, SP),
          (Vector((0.010, 0.004, 0.045)), 0.0070, SP), (Vector((0.008, -0.004, 0.090)), 0.0060, SP),
          (BUD_C - SPROUT_BASE + Vector((0, 0, -0.030)), 0.0075, SP)]
    mb.add_loft(Loft([dict(c=SPROUT_BASE + o, rx=r, ry=r, w=w) for o, r, w in tw]), "Sprout", segs=5,
                cap0=False, cap1=False,
                col=lambda p, u, th: mixc(PAL["SproutDeep"][1], PAL["Sprout"][1], min(1.0, u / 2.0)))
    for o, d, ln in ((Vector((0.010, 0.004, 0.040)), Vector((0.9, 0.25, 0.42)), 0.074),
                     (Vector((0.008, -0.002, 0.070)), Vector((-0.85, -0.35, 0.45)), 0.062)):
        d.normalize()
        t = d.cross(Vector((0, 0, 1))).normalized()
        m = Matrix((t, d, t.cross(d))).transposed()
        mb.add_sphere(SPROUT_BASE + o + d * ln * 0.56, (0.024, ln * 0.56, 0.006), "Sprout", SP, segs=6, rings=4,
                      rot=m, col=lambda p, q: mixc(PAL["Sprout"][1], PAL["SproutDeep"][1], abs(q.x) * 0.3 +
                                                   0.5 * max(0.0, -q.y)))
    for i in range(3):
        a = 2 * pi * i / 3 + 0.5
        d = Vector((cos(a), sin(a), 0.0))
        m = Matrix((d.cross(Vector((0, 0, 1))), Vector((0, 0, 1)), d)).transposed()
        mb.add_sphere(BUD_C + d * 0.027 + Vector((0, 0, -0.018)), (0.017, 0.028, 0.007), "SproutDeep", SP,
                      segs=5, rings=3, rot=m)
    mb.add_sphere(BUD_C, (0.034, 0.034, 0.043), "Jade", SP, segs=10, rings=7,
                  deform=lambda d: 1.0 + 0.22 * max(0.0, d.z) ** 3 - 0.10 * max(0.0, d.z) * (1 - d.z))
    # luciérnagas de jade que rondan el botón
    for o, r in (((0.088, 0.012, 0.024), 0.0130), ((-0.062, 0.058, 0.066), 0.0105), ((-0.022, -0.080, -0.030), 0.0120)):
        mb.add_sphere(BUD_C + Vector(o), r, "Jade", FF, segs=6, rings=4)
    return mb


# ──────────────────────────────── Animaciones ────────────────────────────────
# Poses: {hueso: (rx, ry, rz)} en grados y ejes del modelo, sobre la pose de reposo (que
# ya es la de la abuela apoyada en su bastón). Pseudo-canales que resuelve `finish`:
#   "IK_L"/"IK_R"  desplazamiento del apoyo de cada pie (pies plantados);
#   "STAFF"        desplazamiento (x, y, z) de la contera del bastón respecto a su apoyo en
#                  reposo. La mano derecha se orienta sola para que el bastón pase del puño
#                  a ese punto, y el bastón se desliza por el puño lo que haga falta, así
#                  que con (0, 0, 0) la contera no se mueve del suelo aunque el cuerpo se meza.

GROUND = {"IK_L": (0, 0, 0), "IK_R": (0, 0, 0)}
STAFF_LEN = (GRIP - STAFF_BASE).length


def finish(p):
    p = dict(p)
    for s in ("L", "R"):
        ik = p.pop("IK_" + s, None)
        if ik is not None:
            RIG.ik(p, "Thigh_" + s, "Shin_" + s, [("Foot_" + s, (0, 0, 0))], BALL[s], BALL[s] + Vector(ik), bend=-1.0)
    target = STAFF_BASE + Vector(p.pop("STAFF", (0, 0, 0)))
    for _ in range(5):
        v = RIG.point(p, "Hand_R", GRIP) - target
        rw = STAFF_AXIS.rotation_difference(v.normalized()).to_matrix()
        rp = RIG.deform(p, "Forearm_R").to_3x3().normalized()
        e = (rp.inverted() @ rw).to_euler("XYZ")
        p["Hand_R"] = tuple(math.degrees(a) for a in e)
    v = RIG.point(p, "Hand_R", GRIP) - target
    p["StaffBone.loc"] = tuple(-STAFF_AXIS * (v.length - STAFF_LEN))
    return p


def mouth(wide, open_):
    return {"Mouth.scale": (wide, 1.0, open_)}


def lids(close, low=0.0, brow=0.0, brow_up=0.0):
    """close 0..1 cierra los párpados; brow > 0 ceño de enfado, < 0 cejas de pena."""
    return {"Lid_L": (BLINK * close, 0, 0), "Lid_R": (BLINK * close, 0, 0),
            "LidLow_L": (-12 * close + low, 0, 0), "LidLow_R": (-12 * close + low, 0, 0),
            "Brow_L": (0, -brow, 0), "Brow_R": (0, brow, 0),
            "Brow_L.loc": (0, 0, brow_up - 0.006 * close), "Brow_R.loc": (0, 0, brow_up - 0.006 * close)}


def ears(l, r, tip_l=None, tip_r=None):
    """Ángulo de caída de cada oreja (+ = baja) y de su punta."""
    return {"Ear_L": (0, l, 0), "Ear_R": (0, -r, 0),
            "EarTip_L": (0, l if tip_l is None else tip_l, 0), "EarTip_R": (0, -(r if tip_r is None else tip_r), 0)}


def idle(t):
    T = 3.0
    ph = 2 * pi * t / T
    sway = sin(ph)
    br = sin(2 * ph - 0.6)                        # dos respiraciones por ciclo
    p = dict(GROUND)
    p["STAFF"] = (0, 0, 0)
    p["Hips.loc"] = (-0.004 - 0.011 * sway, 0.003 * sin(ph + 1.0), -0.004 - 0.003 * cos(2 * ph))
    p["Hips"] = (0, 1.4 * sway, 1.2 * sin(ph + 0.5))
    p["Spine"] = (1.0 + 1.0 * br, -1.6 * sway, -1.0 * sin(ph + 0.5))
    p["Chest"] = (-0.6 - 1.6 * br, -0.8 * sway, 0)
    p["Head"] = (1.6 * sin(2 * ph + 1.0), 1.8 * sway, 3.0 * sin(ph + 0.4))
    p["UpperArm_L"] = (4 + 2.0 * br + 2.0 * sway, -4 - 1.8 * br, 0)
    p["Forearm_L"] = (-20 - 3 * br, 0, 0)
    p["Fingers_L"] = (0, 26 + 5 * br, 0)
    p["Index_L"] = (0, 20 + 4 * br, 0)
    p["UpperArm_R"] = (1.2 * br, 1.0 * br, 0)
    p["Forearm_R"] = (-1.5 * br, 0, 0)
    tw = bump(t, 2.05, 2.20) + bump(t, 2.22, 2.37)           # doble sacudida de la oreja derecha
    tw2 = bump(t, 2.09, 2.24) + bump(t, 2.26, 2.41)
    p["Ear_L"] = (0, 2.2 * sin(2 * ph + 0.4), 0)
    p["EarTip_L"] = (0, 3.2 * sin(2 * ph - 0.3), 0)
    p["Ear_R"] = (0, -2.2 * sin(2 * ph + 0.4) + 11 * tw, -15 * tw)
    p["EarTip_R"] = (0, -3.2 * sin(2 * ph - 0.3) + 10 * tw2, -13 * tw2)
    p.update(lids(bump(t, 0.50, 0.70) + bump(t, 1.62, 1.80)))
    p["ShawlEnd_L"] = (1.5 + 2.0 * sin(2 * ph + 0.7), 0, 2.0 * sin(ph - 0.6))
    p["ShawlEnd_R"] = (1.5 + 2.0 * sin(2 * ph + 1.5), 0, 2.0 * sin(ph - 1.1))
    p["Amulet"] = (1.5 * br, 2.5 * sin(ph - 0.7), 0)
    p["Sprout"] = (2.5 * sin(2 * ph + 0.3), 3.0 * sin(ph + 1.2), 0)
    p["Fireflies"] = (4 * sin(2 * ph), 0, 38 * sin(ph - 0.4))
    p["Fireflies.loc"] = (0, 0, 0.012 * sin(2 * ph + 0.9))
    p.update(mouth(1.0 + 0.04 * br, 1.0))
    return finish(p)


def _syll(t, times, w=0.085):
    """Aperturas de boca: una campana por sílaba."""
    return min(1.0, sum(bump(t, a - w, a + w) * k for a, k in times))


TALK_SYLL = [(0.20, 0.9), (0.40, 0.6), (0.58, 1.0), (0.80, 0.5), (1.02, 0.9), (1.46, 0.7), (1.64, 1.0),
             (1.84, 0.6), (2.06, 0.8)]


def talk(t):
    T = 2.4
    ph = 2 * pi * t / T
    g1 = A.window(t, 0.10, 1.25, 0.22)             # la mano izquierda explica…
    g2 = A.window(t, 1.35, 2.30, 0.22)             # …y remata con otro gesto, más abierto
    beat = sin(2 * pi * t / 0.4)
    tap = bump(t, 1.02, 1.34)                      # levanta el bastón y da un golpecito (≈1.33 s)
    op = _syll(t, TALK_SYLL)
    nod = bump(t, 0.50, 0.86) + bump(t, 1.26, 1.60) + 0.6 * bump(t, 1.96, 2.26)
    p = dict(GROUND)
    p["STAFF"] = (0.0, -0.012 * tap, 0.050 * tap)
    p["Hips.loc"] = (-0.004 - 0.006 * sin(ph), 0.002 * sin(2 * ph), -0.004 - 0.004 * nod)
    p["Hips"] = (0, 1.0 * sin(ph), 2.0 * sin(ph + 0.4))
    p["Spine"] = (1.0 + 2.0 * nod, -1.0 * sin(ph), 2.0 * g1 - 2.5 * g2)
    p["Chest"] = (-0.6 + 1.5 * nod, 0, 3.0 * g1 - 3.0 * g2)
    p["Head"] = (7.0 * nod - 2.0 * (g1 + g2), 3.0 * sin(ph + 0.5), 7.0 * g1 - 8.0 * g2)
    p["UpperArm_L"] = (4 - 34 * g1 - 26 * g2, -4 - 8 * g1 - 30 * g2, 0)
    p["Forearm_L"] = (-20 - 68 * g1 - 52 * g2 + 9 * beat * (g1 + g2), 0, 0)
    p["Hand_L"] = (-10 * g1 + 6 * beat * g1, 0, 30 * g1 + 70 * g2)
    p["Fingers_L"] = (0, 26 - 12 * g1 - 20 * g2 + 6 * beat * g1, 0)
    p["Index_L"] = (0, 20 - 16 * g1 - 16 * g2, 0)
    p["UpperArm_R"] = (-7 * tap, 2 * tap, 0)
    p["Forearm_R"] = (-9 * tap, 0, 0)
    p.update(ears(-3 * g1 - 4 * g2 + 2 * sin(2 * ph), -3 * g1 - 4 * g2 + 2 * sin(2 * ph + 0.8)))
    p.update(lids(bump(t, 0.86, 1.04) + bump(t, 2.12, 2.30), brow_up=0.006 * (g1 + g2) * (0.6 + 0.4 * op)))
    p["ShawlEnd_L"] = (2 + 3 * sin(2 * ph + 0.7) + 4 * g1, 0, 3 * sin(ph - 0.6))
    p["ShawlEnd_R"] = (2 + 3 * sin(2 * ph + 1.5), 0, 3 * sin(ph - 1.1))
    p["Amulet"] = (3 * sin(2 * ph), 3 * sin(ph - 0.7), 0)
    p["Sprout"] = (4 * sin(2 * ph + 0.3) + 12 * bump(t, 1.28, 1.56), 3 * sin(ph + 1.2), 0)
    p["Fireflies"] = (5 * sin(2 * ph), 0, 42 * sin(ph - 0.4))
    p["Fireflies.loc"] = (0, 0, 0.014 * sin(2 * ph + 0.9))
    p.update(mouth(1.0 - 0.10 * op + 0.04 * sin(2 * ph), 1.0 + 2.1 * op))
    return finish(p)


def scold(t):
    """Regaño: planta el bastón dos veces, levanta el índice y lo menea con el ceño fruncido."""
    k = K(t, [(0.0, 0.0), (0.16, 1.0), (0.94, 1.0), (1.2, 0.0)])
    wag = sin(2 * pi * (t - 0.16) / 0.26) * A.window(t, 0.16, 1.0, 0.10)
    th1, th2 = bump(t, 0.06, 0.34), bump(t, 0.52, 0.80)
    thump = th1 + th2
    shake = sin(2 * pi * t / 0.13) * A.window(t, 0.30, 1.0, 0.12)
    op = _syll(t, [(0.22, 1.0), (0.42, 0.7), (0.62, 1.0), (0.84, 0.8)], 0.09)
    p = dict(GROUND)
    p["STAFF"] = (0.004 * shake, -0.02 * thump, 0.075 * thump)
    p["Hips.loc"] = (-0.004 * (1 - k) + 0.006 * k, -0.012 * k, -0.004 - 0.006 * k + 0.010 * thump)
    p["Hips"] = (1.5 * k, 0, -3 * k)
    p["Spine"] = (1.0 + 2.5 * k, 0, -4 * k + 2.0 * wag)
    p["Chest"] = (-0.6 + 2.5 * k, 0, -4 * k + 2.0 * wag)
    p["Head"] = (-7 * k + 4 * thump, 4 * wag * k, 9 * k - 6 * wag)
    p["UpperArm_L"] = (4 - 92 * k, -4 + 18 * k, 0)
    p["Forearm_L"] = (-20 - 66 * k, 22 * k + 17 * wag, 0)
    p["Hand_L"] = (0, 9 * wag, -75 * k)
    p["Fingers_L"] = (0, 26 + 62 * k, 0)
    p["Index_L"] = (0, 20 - 26 * k, 0)
    p["UpperArm_R"] = (-9 * thump, 3 * thump, 0)
    p["Forearm_R"] = (-11 * thump, 0, 0)
    p.update(ears(-16 * k + 5 * wag, -16 * k - 5 * wag, -24 * k + 9 * wag, -24 * k - 9 * wag))
    p.update(lids(0.10 * k, low=-10 * k, brow=17 * k, brow_up=-0.007 * k))
    p["ShawlEnd_L"] = (8 * k + 5 * wag, 0, 6 * wag)
    p["ShawlEnd_R"] = (8 * k - 5 * wag, 0, 6 * wag)
    p["Amulet"] = (-6 * k + 5 * wag, 5 * wag, 0)
    p["Sprout"] = (14 * shake * k + 10 * thump, 8 * shake * k, 0)
    p["Fireflies"] = (0, 0, 60 * k * sin(2 * pi * t / 0.6))
    p["Fireflies.loc"] = (0, 0, 0.020 * thump)
    p.update(mouth(1.0 - 0.22 * k, 1.0 + 0.5 * k + 2.2 * op))
    return finish(p)


def bless(t):
    """Bendición: alza el bastón, lo sostiene en alto con los ojos entornados (el botón de
    jade brilla entre 0.55 y 1.05 s; el brillo lo pone el juego) y lo vuelve a apoyar."""
    k = K(t, [(0.0, 0.0), (0.14, -0.10), (0.52, 1.0), (1.06, 1.0), (1.42, 0.0), (1.6, 0.0)])
    kk = max(0.0, k)
    hold = A.window(t, 0.50, 1.10, 0.14)
    settle = bump(t, 1.34, 1.58)
    p = dict(GROUND)
    p["STAFF"] = (-0.030 * kk, 0.020 * kk, 0.33 * kk + 0.006 * hold * sin(2 * pi * t / 0.3))
    p["Hips.loc"] = (-0.004 * (1 - kk), 0.005 * kk, -0.004 - 0.012 * max(0.0, -k) - 0.008 * settle)
    p["Spine"] = (1.0 - 5.0 * kk - 5 * min(0.0, k), 0, 3 * kk)
    p["Chest"] = (-0.6 - 5.0 * kk, 0, 3 * kk)
    p["Head"] = (-13 * kk + 4 * settle, 0, -6 * kk)
    p["UpperArm_R"] = (-96 * k, -16 * kk, 0)
    p["Forearm_R"] = (-10 * k, 0, 0)
    p["UpperArm_L"] = (4 - 16 * kk, -4 - 40 * kk, 0)
    p["Forearm_L"] = (-20 - 42 * kk, 0, 0)
    p["Hand_L"] = (0, 0, 74 * kk)
    p["Fingers_L"] = (0, 26 - 22 * kk, 0)
    p["Index_L"] = (0, 20 - 18 * kk, 0)
    p.update(ears(-14 * kk + 6 * settle, -14 * kk + 6 * settle, -20 * kk + 10 * settle, -20 * kk + 10 * settle))
    p.update(lids(0.62 * hold, brow_up=0.008 * kk, brow=-5 * kk))
    p["ShawlEnd_L"] = (-7 * kk + 6 * settle, 0, 0)
    p["ShawlEnd_R"] = (-9 * kk + 8 * settle, 0, 0)
    p["Amulet"] = (-8 * kk + 6 * settle, 0, 0)
    p["Sprout"] = (-10 * kk + 5 * hold * sin(2 * pi * t / 0.3) + 12 * settle, 0, 0)
    p["Fireflies"] = (0, 0, 150 * K(t, [(0.0, 0.0), (0.5, 0.25), (1.06, 1.0), (1.6, 0.0)]))
    p["Fireflies.loc"] = (0, 0, 0.030 * hold)
    p["Fireflies.scale"] = tuple(1.0 + 0.5 * hold for _ in range(3))
    p.update(mouth(1.0 + 0.10 * kk, 1.0 + 0.5 * hold))
    return finish(p)


def loop(fn, length):
    """Ciclo exacto: el último cuadro es, bit a bit, el primero."""
    return lambda t: fn(0.0 if abs(t - length) < 1e-6 else t)


# «Run» y «Fall» son copias de «Idle»: el código del avatar puede pedirlas y así no falla.
ANIMS = [
    ("Idle", 3.0, loop(idle, 3.0)),
    ("Talk", 2.4, loop(talk, 2.4)),
    ("Scold", 1.2, scold),
    ("Bless", 1.6, bless),
    ("Run", 3.0, loop(idle, 3.0)),
    ("Fall", 3.0, loop(idle, 3.0)),
]


# ─────────────────────────────────── Main ───────────────────────────────────

def build():
    kc.reset_scene()
    mats = make_materials()
    arm = kc.build_armature("Armature", make_bones())
    body, staff = build_body(), build_staff()
    kc.bake_ao([body])
    kc.bake_ao([staff], [staff, body])
    objs = {"Yaxche": body.build("Yaxche", mats, arm), "Staff": staff.build("Staff", mats, arm)}
    kc.bake_actions(arm, ANIMS)
    return arm, objs


def main():
    arm, objs = build()
    kc.export_glb(OUT)
    rep = kc.glb_report(OUT)
    print("== yaxche.glb ==")
    for k, v in rep.items():
        print(" ", k, ":", v)
    for name, ob in objs.items():
        print("  tris", name, sum(len(p.vertices) - 2 for p in ob.data.polygons))


if __name__ == "__main__":
    main()
