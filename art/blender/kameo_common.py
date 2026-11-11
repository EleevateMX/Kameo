"""Utilidades compartidas para generar los personajes de ALUX con Blender (bpy).

Todo es procedimental y determinista: mallas hechas de "lofts" (tubos con
secciones interpoladas), esferas deformadas y calcomanías geométricas; un
esqueleto; animaciones horneadas cuadro a cuadro a partir de funciones de
tiempo; exportación a glTF binario (.glb) y renders de vista previa.

Convenciones: 1 unidad = 1 metro, Z arriba, el personaje mira hacia -Y
(queda mirando a +Z en Godot), su izquierda es +X, pies en z = 0.
"""
import math
import os

import bpy
from mathutils import Euler, Matrix, Vector

FPS = 30


# ───────────────────────────── Escena y materiales ─────────────────────────────

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.unit_settings.system = "METRIC"
    return scene


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def make_material(name, color, rough=0.8, emission=0.0, metallic=0.0, emission_color=None):
    """Material PBR de color plano. `color` es "#rrggbb" (sRGB)."""
    m = bpy.data.materials.new(name)
    if m.node_tree is None or "Principled BSDF" not in m.node_tree.nodes:
        m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    lin = tuple(srgb_to_linear(c) for c in hex_rgb(color))
    bsdf.inputs["Base Color"].default_value = (*lin, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metallic
    if emission > 0.0:
        elin = tuple(srgb_to_linear(c) for c in hex_rgb(emission_color or color))
        bsdf.inputs["Emission Color"].default_value = (*elin, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission
    m.diffuse_color = (*lin, 1.0)
    return m


# ───────────────────────────────── Geometría ─────────────────────────────────

def _catmull(p0, p1, p2, p3, f):
    f2, f3 = f * f, f * f * f
    return 0.5 * ((2.0 * p1) + (-p0 + p2) * f + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f2
                  + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * f3)


def _catmull_d(p0, p1, p2, p3, f):
    f2 = f * f
    return 0.5 * ((-p0 + p2) + 2.0 * (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f
                  + 3.0 * (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * f2)


def _spow(v, e):
    return math.copysign(abs(v) ** e, v)


def mix_weights(a, b, f):
    out = {}
    for k, v in a.items():
        out[k] = out.get(k, 0.0) + v * (1.0 - f)
    for k, v in b.items():
        out[k] = out.get(k, 0.0) + v * f
    return {k: v for k, v in out.items() if v > 1e-4}


class Loft:
    """Tubo paramétrico S(u, θ) definido por anillos.

    Cada anillo: dict(c=(x,y,z), rx=, ry=, [ryn=], [n=], [w={hueso: peso}], [side=(x,y,z)])
      rx: radio sobre el eje lateral `a`; ry: radio sobre `b = t × a` (lado positivo);
      ryn: radio del lado negativo de `b` (por defecto = ry); n: exponente de
      superelipse (2 = elipse, 4 = casi cuadrado).
    u recorre los anillos (0 .. N-1) con interpolación Catmull-Rom.
    """

    def __init__(self, rings, side=(1.0, 0.0, 0.0)):
        self.rings = []
        for r in rings:
            q = dict(r)
            q["c"] = Vector(q["c"])
            q.setdefault("ryn", q["ry"])
            q.setdefault("n", 2.0)
            q.setdefault("w", None)
            q["side"] = Vector(q.get("side", side))
            self.rings.append(q)
        self.n = len(self.rings)

    def umax(self):
        return float(self.n - 1)

    def _idx(self, u):
        u = min(max(u, 0.0), self.n - 1.0)
        i = min(int(math.floor(u)), self.n - 2)
        return i, u - i

    def frame(self, u):
        i, f = self._idx(u)
        r = self.rings
        k0, k1, k2, k3 = max(i - 1, 0), i, i + 1, min(i + 2, self.n - 1)

        def cm(key):
            return _catmull(r[k0][key], r[k1][key], r[k2][key], r[k3][key], f)

        c = cm("c")
        t = _catmull_d(r[k0]["c"], r[k1]["c"], r[k2]["c"], r[k3]["c"], f)
        if t.length < 1e-6:
            t = r[k2]["c"] - r[k1]["c"]
        if t.length < 1e-6:
            t = r[min(k2 + 1, self.n - 1)]["c"] - r[max(k1 - 1, 0)]["c"]
        t.normalize()
        side = r[k1]["side"].lerp(r[k2]["side"], f)
        a = side - t * side.dot(t)
        a.normalize()
        b = t.cross(a)
        return c, a, b, t, max(cm("rx"), 0.0), max(cm("ry"), 0.0), max(cm("ryn"), 0.0), max(cm("n"), 1.0)

    def point(self, u, th):
        c, a, b, _t, rx, ry, ryn, n = self.frame(u)
        e = 2.0 / n
        cx = _spow(math.cos(th), e)
        cy = _spow(math.sin(th), e)
        return c + a * (rx * cx) + b * ((ry if cy >= 0.0 else ryn) * cy)

    def weights(self, u):
        i, f = self._idx(u)
        return mix_weights(self.rings[i]["w"] or {}, self.rings[i + 1]["w"] or {}, f)


class MeshBuilder:
    """Acumula vértices, caras, materiales y pesos; luego crea el objeto."""

    def __init__(self):
        self.verts = []
        self.weights = []
        self.faces = []
        self.fmat = []

    def vert(self, p, w):
        self.verts.append(Vector(p))
        self.weights.append(w)
        return len(self.verts) - 1

    def face(self, idx, mat):
        self.faces.append(tuple(idx))
        self.fmat.append(mat)

    def tri_count(self):
        return sum(len(f) - 2 for f in self.faces)

    def transform(self, matrix, start=0):
        """Aplica una matriz 4x4 a los vértices desde el índice `start`."""
        for i in range(start, len(self.verts)):
            self.verts[i] = matrix @ self.verts[i]

    # -- lofts --------------------------------------------------------------
    def add_loft(self, loft, mat, segs=12, sub=1, cap0=True, cap1=True, w=None,
                 matfn=None, wfn=None, th0=0.0, u0=None, u1=None, capmat=(None, None), flip=False):
        """Malla el loft. `mat` nombre de material o `matfn(u, th, p) -> nombre`.
        `w` pesos fijos para todo, o `wfn(u, th, p) -> dict`; si no, los de los anillos.
        `flip=True` invierte las caras (superficies interiores: bajo el ala del sombrero…)."""
        u0 = 0.0 if u0 is None else u0
        u1 = loft.umax() if u1 is None else u1
        rows = max(1, int(round((u1 - u0) * sub)))
        us = [u0 + (u1 - u0) * k / rows for k in range(rows + 1)]
        grid = []
        for u in us:
            row = []
            for j in range(segs):
                th = th0 + 2.0 * math.pi * j / segs
                p = loft.point(u, th)
                ww = wfn(u, th, p) if wfn else (w if w is not None else loft.weights(u))
                row.append(self.vert(p, ww))
            grid.append(row)
        for k in range(rows):
            um = 0.5 * (us[k] + us[k + 1])
            for j in range(segs):
                j2 = (j + 1) % segs
                thm = th0 + 2.0 * math.pi * (j + 0.5) / segs
                m = matfn(um, thm, loft.point(um, thm)) if matfn else mat
                if m is None:
                    continue
                q = (grid[k][j], grid[k][j2], grid[k + 1][j2], grid[k + 1][j])
                self.face(q[::-1] if flip else q, m)
        for cap, row, u, flip_cap, cm in ((cap0, grid[0], us[0], True, capmat[0]),
                                      (cap1, grid[-1], us[-1], False, capmat[1])):
            if not cap:
                continue
            c = loft.frame(u)[0]
            ww = wfn(u, 0.0, c) if wfn else (w if w is not None else loft.weights(u))
            ci = self.vert(c, ww)
            m = cm or (matfn(u, 0.0, c) if matfn else mat)
            if m is None:
                continue
            for j in range(segs):
                j2 = (j + 1) % segs
                self.face((ci, row[j2], row[j]) if flip_cap != flip else (ci, row[j], row[j2]), m)

    # -- esferas / elipsoides -------------------------------------------------
    def add_sphere(self, center, radii, mat, w, segs=12, rings=8, rot=None, deform=None,
                   keep=None, matfn=None, wfn=None):
        """Esfera UV (polos sobre Z local). `deform(p_local_unit) -> escala radial`,
        `keep(d) -> bool` filtra caras por la dirección unitaria local de su centro."""
        center = Vector(center)
        if isinstance(radii, (int, float)):
            radii = (radii, radii, radii)
        rot = rot or Matrix.Identity(3)

        def P(d):
            s = deform(d) if deform else 1.0
            return center + rot @ Vector((d.x * radii[0] * s, d.y * radii[1] * s, d.z * radii[2] * s))

        def D(i, j):
            ph = math.pi * i / rings
            th = 2.0 * math.pi * j / segs
            return Vector((math.sin(ph) * math.cos(th), math.sin(ph) * math.sin(th), math.cos(ph)))

        idx = {}

        def V(i, j):
            key = (i, 0 if i in (0, rings) else j % segs)
            if key not in idx:
                d = D(*key)
                p = P(d)
                idx[key] = self.vert(p, wfn(d, p) if wfn else w)
            return idx[key]

        for i in range(rings):
            for j in range(segs):
                dm = D(i, j) + D(i + 1, j) + D(i, j + 1) + D(i + 1, j + 1)
                dm.normalize()
                if keep and not keep(dm):
                    continue
                m = matfn(dm) if matfn else mat
                if m is None:
                    continue
                if i == 0:
                    self.face((V(0, 0), V(1, j), V(1, j + 1)), m)
                elif i == rings - 1:
                    self.face((V(i, j), V(rings, 0), V(i, j + 1)), m)
                else:
                    self.face((V(i, j), V(i + 1, j), V(i + 1, j + 1), V(i, j + 1)), m)

    # -- calcomanías sobre una superficie paramétrica ---------------------------
    def add_decal(self, P, a0, b0, radius, mat, w, nseg=6, inner=0.0, offset=0.004,
                  aspect=1.0, rot=0.0, outward=None, star=1.0, arc=(0.0, 1.0), wfn=None):
        """Disco/anillo/estrella pegado a la superficie P(a, b) alrededor de (a0, b0).
        radius en metros. inner>0 → anillo. star<1 → radios alternos (flor).
        `outward`: punto de referencia interior para orientar la normal (p.ej. el centro).
        `wfn(a, b, p) -> pesos` da pesos por vértice (para que la calcomanía se deforme
        igual que la superficie de abajo); si no, todos usan `w`."""
        e = 1e-3
        p0 = P(a0, b0)
        pa = (P(a0 + e, b0) - P(a0 - e, b0)) / (2 * e)
        pb = (P(a0, b0 + e) - P(a0, b0 - e)) / (2 * e)
        nrm = pa.cross(pb)
        nrm.normalize()
        if outward is not None and nrm.dot(p0 - Vector(outward)) < 0.0:
            nrm = -nrm
        e1 = pa.normalized()
        e2 = nrm.cross(e1)
        # resolver d = da*pa + db*pb en el plano tangente
        g11, g12, g22 = pa.dot(pa), pa.dot(pb), pb.dot(pb)
        det = g11 * g22 - g12 * g12

        def at(r, ang):
            lx, ly = r * math.cos(ang) * aspect, r * math.sin(ang)
            c0, s0 = math.cos(rot), math.sin(rot)
            d = e1 * (lx * c0 - ly * s0) + e2 * (lx * s0 + ly * c0)
            r1, r2 = d.dot(pa), d.dot(pb)
            da = (r1 * g22 - r2 * g12) / det
            db = (r2 * g11 - r1 * g12) / det
            pt = P(a0 + da, b0 + db)
            return pt + nrm * offset, (wfn(a0 + da, b0 + db, pt) if wfn else w)

        full = arc[1] - arc[0] >= 0.999
        n_pts = nseg if full else nseg + 1
        angs = [2.0 * math.pi * (arc[0] + (arc[1] - arc[0]) * k / nseg) for k in range(n_pts)]
        outer = [self.vert(*at(radius * (star if (k % 2 and star != 1.0) else 1.0), a))
                 for k, a in enumerate(angs)]
        if inner > 0.0:
            inn = [self.vert(*at(radius * inner, a)) for a in angs]
            rng = range(nseg) if full else range(nseg)
            for k in rng:
                k2 = (k + 1) % n_pts
                self.face((outer[k], outer[k2], inn[k2], inn[k]), mat)
        else:
            ci = self.vert(p0 + nrm * offset, wfn(a0, b0, p0) if wfn else w)
            for k in range(nseg if full else nseg):
                k2 = (k + 1) % n_pts
                self.face((ci, outer[k], outer[k2]), mat)

    # -- construir objeto -----------------------------------------------------
    def build(self, name, materials, armature=None, collection=None):
        used = sorted({v for f in self.faces for v in f})
        remap = {old: new for new, old in enumerate(used)}
        verts = [tuple(self.verts[i]) for i in used]
        faces = [tuple(remap[v] for v in f) for f in self.faces]
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(verts, [], faces)
        mat_names = []
        for m in self.fmat:
            if m not in mat_names:
                mat_names.append(m)
        for mn in mat_names:
            mesh.materials.append(materials[mn])
        mi = {mn: i for i, mn in enumerate(mat_names)}
        mesh.polygons.foreach_set("material_index", [mi[m] for m in self.fmat])
        mesh.polygons.foreach_set("use_smooth", [True] * len(faces))
        mesh.update()
        mesh.validate()
        obj = bpy.data.objects.new(name, mesh)
        (collection or bpy.context.scene.collection).objects.link(obj)
        groups = {}
        for old in used:
            w = self.weights[old] or {}
            tot = sum(w.values())
            for bone, val in w.items():
                if bone not in groups:
                    groups[bone] = obj.vertex_groups.new(name=bone)
                groups[bone].add([remap[old]], val / tot, "REPLACE")
        if armature is not None:
            for bone in groups:
                if bone not in armature.data.bones:
                    raise KeyError("hueso inexistente en pesos: " + bone)
            obj.parent = armature
            mod = obj.modifiers.new("Armature", "ARMATURE")
            mod.object = armature
        return obj


# ───────────────────────────────── Esqueleto ─────────────────────────────────

def build_armature(name, bones):
    """bones: lista de (nombre, cabeza, cola, padre|None). Devuelve el objeto."""
    data = bpy.data.armatures.new(name)
    arm = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for bname, head, tail, parent in bones:
        eb = data.edit_bones.new(bname)
        eb.head = Vector(head)
        eb.tail = Vector(tail)
        eb.roll = 0.0
        if parent:
            eb.parent = data.edit_bones[parent]
            eb.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return arm


# ──────────────────────────────── Animaciones ────────────────────────────────

def _interp_keys(t, keys, loop_len=None):
    """Interpola una lista [(t, valor)] con Catmull-Rom (valor: número o tupla)."""
    n = len(keys)
    if n == 1:
        return keys[0][1]
    if loop_len:
        t = t % loop_len
    if t <= keys[0][0] and not loop_len:
        return keys[0][1]
    if t >= keys[-1][0] and not loop_len:
        return keys[-1][1]
    i = 0
    while i < n - 2 and t >= keys[i + 1][0]:
        i += 1

    def key(k):
        if loop_len:
            # la última clave es igual a la primera (t = loop_len)
            if k < 0:
                kk = n - 1 + k
                return keys[kk][0] - loop_len, keys[kk][1]
            if k > n - 1:
                kk = k - (n - 1)
                return keys[kk][0] + loop_len, keys[kk][1]
            return keys[k]
        return keys[min(max(k, 0), n - 1)]

    (t0, v0), (t1, v1), (t2, v2), (t3, v3) = key(i - 1), key(i), key(i + 1), key(i + 2)
    f = (t - t1) / (t2 - t1)

    def one(a, b, c, d):
        # tangentes Catmull-Rom no uniformes (limitadas para evitar rebasar)
        m1 = (c - a) / (t2 - t0) if t2 > t0 else 0.0
        m2 = (d - b) / (t3 - t1) if t3 > t1 else 0.0
        if not loop_len:
            if i == 0:
                m1 = 0.0
            if i == n - 2:
                m2 = 0.0
        h = t2 - t1
        f2, f3 = f * f, f * f * f
        return ((2 * f3 - 3 * f2 + 1) * b + (f3 - 2 * f2 + f) * h * m1
                + (-2 * f3 + 3 * f2) * c + (f3 - f2) * h * m2)

    if isinstance(v1, (int, float)):
        return one(v0, v1, v2, v3)
    return tuple(one(a, b, c, d) for a, b, c, d in zip(v0, v1, v2, v3))


def K(t, keys, loop=None):
    """Curva escalar/tupla por claves [(t, v), ...]. loop = duración del ciclo."""
    return _interp_keys(t, keys, loop)


def pose_keys(t, keys, loop=None):
    """Interpola poses completas: keys = [(t, {canal: tupla}), ...].
    Los canales que falten en una clave valen cero (o uno para .scale)."""
    chans = set()
    for _, p in keys:
        chans.update(p.keys())
    out = {}
    for ch in chans:
        default = (1.0, 1.0, 1.0) if ch.endswith(".scale") else (0.0, 0.0, 0.0)
        out[ch] = _interp_keys(t, [(kt, tuple(p.get(ch, default))) for kt, p in keys], loop)
    return out


def add_pose(a, b, wb=1.0):
    """Suma (aditiva) la pose b sobre a. Las escalas se multiplican."""
    out = dict(a)
    for ch, v in b.items():
        if ch.endswith(".scale"):
            base = out.get(ch, (1.0, 1.0, 1.0))
            out[ch] = tuple(x * (1.0 + (y - 1.0) * wb) for x, y in zip(base, v))
        else:
            base = out.get(ch, (0.0, 0.0, 0.0))
            out[ch] = tuple(x + y * wb for x, y in zip(base, v))
    return out


def mirror_pose(p):
    """Refleja una pose izquierda↔derecha (huesos *_L / *_R)."""
    out = {}
    for ch, v in p.items():
        bone, _, suffix = ch.partition(".")
        if bone.endswith("_L"):
            bone = bone[:-2] + "_R"
        elif bone.endswith("_R"):
            bone = bone[:-2] + "_L"
        name = bone + ("." + suffix if suffix else "")
        if suffix == "loc":
            out[name] = (-v[0], v[1], v[2])
        elif suffix == "scale":
            out[name] = v
        else:
            out[name] = (v[0], -v[1], -v[2])
    return out


def bake_actions(arm, anims, extra_channels=()):
    """anims: lista de (nombre, duración_s, fn(t) -> pose).
    pose: {"Hueso": (rx, ry, rz) grados en ejes del modelo (X izq., Y atrás, Z arriba),
           "Hueso.loc": (x, y, z) metros en ejes del modelo, "Hueso.scale": (sx, sy, sz)}.
    Cada acción lleva claves en todos los huesos para que ninguna animación deje
    restos de la anterior. Crea una pista NLA por acción (para el exportador)."""
    rest = {b.name: b.matrix_local.to_3x3() for b in arm.data.bones}
    rest_q = {k: m.to_quaternion() for k, m in rest.items()}
    rest_inv = {k: m.inverted() for k, m in rest.items()}
    loc_bones, scale_bones = set(extra_channels), set()
    samples = {}
    for name, length, fn in anims:
        # la duración se redondea a cuadros enteros; el tiempo se reparte para que el
        # último cuadro caiga exactamente en `length` (los ciclos cierran sin salto)
        frames = max(1, int(round(length * FPS)))
        poses = [fn(length * f / frames) for f in range(frames + 1)]
        samples[name] = poses
        for p in poses:
            for ch in p:
                if ch.endswith(".loc"):
                    loc_bones.add(ch[:-4])
                elif ch.endswith(".scale"):
                    scale_bones.add(ch[:-6])
                elif ch not in rest:
                    raise KeyError("canal desconocido: " + ch)
    # Godot descarta al importar las pistas que coinciden con la pose de reposo y su
    # AnimationPlayer no toca los huesos sin pista: un párpado cerrado en "Hit" se
    # quedaría cerrado en "Run". Para que todas las animaciones conserven las mismas
    # pistas, los huesos animados llevan un sesgo imperceptible (0.03° / 0.2 mm).
    rot_bones = set()
    for poses in samples.values():
        for p in poses:
            for ch, v in p.items():
                if "." not in ch and any(abs(x) > 1e-6 for x in v):
                    rot_bones.add(ch)
    arm.animation_data_create()
    actions = []
    for name, length, fn in anims:
        act = bpy.data.actions.new(name)
        arm.animation_data.action = act
        prev = {}
        for f, pose in enumerate(samples[name]):
            for pb in arm.pose.bones:
                b = pb.name
                r = pose.get(b, (0.0, 0.0, 0.0))
                if b in rot_bones:
                    r = (r[0] + 0.03, r[1], r[2])
                qm = Euler([math.radians(a) for a in r], "XYZ").to_quaternion()
                q = rest_q[b].inverted() @ qm @ rest_q[b]
                if b in prev and prev[b].dot(q) < 0.0:
                    q.negate()
                prev[b] = q.copy()
                pb.rotation_quaternion = q
                pb.keyframe_insert("rotation_quaternion", frame=f)
                if b in loc_bones:
                    lv = Vector(pose.get(b + ".loc", (0.0, 0.0, 0.0))) + Vector((0.0, 0.0, 2e-4))
                    pb.location = rest_inv[b] @ lv
                    pb.keyframe_insert("location", frame=f)
                if b in scale_bones:
                    s = tuple(x + 3e-4 for x in pose.get(b + ".scale", (1.0, 1.0, 1.0)))
                    # escala en ejes del hueso: Y local = eje del hueso
                    pb.scale = Vector(s)
                    pb.keyframe_insert("scale", frame=f)
        _linearize(act)
        act.use_fake_user = True
        actions.append(act)
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
        pb.scale = (1, 1, 1)
    for act in actions:
        track = arm.animation_data.nla_tracks.new()
        track.name = act.name
        strip = track.strips.new(act.name, 0, act)
        strip.name = act.name
        track.mute = True
    return actions


def _all_fcurves(act):
    try:
        return list(act.fcurves)
    except AttributeError:
        out = []
        for layer in act.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    out.extend(bag.fcurves)
        return out


def _linearize(act):
    for fc in _all_fcurves(act):
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"


def set_action(arm, act_name, frame):
    """Pone al esqueleto en un cuadro de una acción (para renders)."""
    act = bpy.data.actions[act_name]
    for tr in arm.animation_data.nla_tracks:
        tr.mute = True
    arm.animation_data.action = act
    try:
        if arm.animation_data.action_slot is None and act.slots:
            arm.animation_data.action_slot = act.slots[0]
    except AttributeError:
        pass
    bpy.context.scene.frame_set(int(frame))


def clear_action(arm):
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
        pb.scale = (1, 1, 1)
    bpy.context.scene.frame_set(0)


# ──────────────────────────────── Exportación ────────────────────────────────

def export_glb(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_yup=True,
        export_apply=False,
        export_texcoords=False,
        export_normals=True,
        export_tangents=False,
        export_materials="EXPORT",
        export_image_format="NONE",
        export_vertex_color="NONE",
        export_cameras=False,
        export_lights=False,
        export_extras=False,
        export_skins=True,
        export_all_influences=False,
        export_morph=False,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        export_frame_range=False,
        export_anim_slide_to_zero=True,
        export_optimize_animation_size=True,
        export_optimize_animation_keep_anim_armature=False,   # sin canales T/S sin claves: JSON más chico
        export_reset_pose_bones=True,
        export_rest_position_armature=True,
        export_def_bones=False,
    )
    return os.path.getsize(path)


def glb_report(path):
    """Lee el JSON del .glb y devuelve triángulos, nombres, etc. (sin Blender)."""
    import json
    import struct
    with open(path, "rb") as fh:
        data = fh.read()
    jlen = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20 + jlen])
    tris = 0
    for mesh in doc.get("meshes", []):
        for prim in mesh["primitives"]:
            tris += doc["accessors"][prim["indices"]]["count"] // 3
    return {
        "bytes": len(data),
        "triangles": tris,
        "animations": [(a["name"], round(max(doc["accessors"][s["input"]]["max"][0] for s in a["samplers"]), 3))
                       for a in doc.get("animations", [])],
        "materials": [m["name"] for m in doc.get("materials", [])],
        "nodes": [n.get("name") for n in doc.get("nodes", []) if "mesh" in n],
        "joints": len(doc["skins"][0]["joints"]) if doc.get("skins") else 0,
    }


# ─────────────────────────────── Vista previa ───────────────────────────────

def setup_preview(ground_color="#5d7a4a", sky="#b9d3e6"):
    """Luces, cielo y suelo para renders con Cycles en CPU."""
    import addon_utils
    addon_utils.enable("cycles", default_set=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 3
    scene.view_settings.view_transform = "Standard"
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.image_settings.compression = 100
    world = bpy.data.worlds.new("PreviewWorld")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (*[srgb_to_linear(c) for c in hex_rgb(sky)], 1.0)
    bg.inputs[1].default_value = 0.9
    scene.world = world
    preview = bpy.data.collections.new("Preview")
    scene.collection.children.link(preview)

    def sun(name, energy, rot, color=(1, 1, 1)):
        ld = bpy.data.lights.new(name, "SUN")
        ld.energy = energy
        ld.color = color
        ld.angle = math.radians(8)
        ob = bpy.data.objects.new(name, ld)
        ob.rotation_euler = [math.radians(a) for a in rot]
        preview.objects.link(ob)

    sun("Key", 3.2, (50, 0, 35), (1.0, 0.95, 0.85))
    sun("Fill", 0.8, (60, 0, -140), (0.8, 0.9, 1.0))
    gm = bpy.data.meshes.new("PreviewGround")
    s = 30.0
    gm.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
    gmat = make_material("PreviewGroundMat", ground_color, 1.0)
    gm.materials.append(gmat)
    ground = bpy.data.objects.new("PreviewGround", gm)
    preview.objects.link(ground)
    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_data.lens = 60
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    preview.objects.link(cam)
    scene.camera = cam
    return cam


def render(path, cam, target, yaw_deg, pitch_deg, dist, res=480, samples=24):
    """yaw 0 = cámara delante del personaje (lo ve de frente); 90 = a su izquierda."""
    scene = bpy.context.scene
    target = Vector(target)
    yaw, pitch = math.radians(yaw_deg), math.radians(pitch_deg)
    off = Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), math.sin(pitch))) * dist
    cam.location = target + off
    cam.rotation_euler = (-off).to_track_quat("-Z", "Y").to_euler()
    scene.render.resolution_x = res
    scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.cycles.samples = samples
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
