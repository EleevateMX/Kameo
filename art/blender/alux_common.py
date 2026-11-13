"""Utilidades compartidas para generar los personajes de ALUX con Blender (bpy).

Todo es procedimental y determinista:
  · mallas hechas de "lofts" (tubos con secciones interpoladas), esferas deformadas
    y dibujos recortados en la propia superficie (triangulación de Delaunay con
    restricciones), con el color en los vértices y oclusión ambiental horneada;
  · un esqueleto, con cinemática directa e inversa (pies plantados) en Python;
  · animaciones horneadas cuadro a cuadro a partir de funciones de tiempo;
  · exportación a glTF binario (.glb) y renders de vista previa.

Convenciones: 1 unidad = 1 metro, Z arriba, el personaje mira hacia -Y
(queda mirando a +Z en Godot), su izquierda es +X, pies en z = 0.
"""
import math
import os

import bpy
from mathutils import Euler, Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import delaunay_2d_cdt

FPS = 30
COLOR_ATTR = "Col"
# El renderer Compatibility de Godot usa los colores de vértice tal cual, como si ya
# estuvieran en sRGB (comprobado con capturas), así que se guardan codificados en sRGB
# aunque glTF los defina lineales. Los cálculos (mezclas, oclusión) se hacen en lineal.
VERTEX_COLORS_SRGB = True


# ───────────────────────────── Escena, color y materiales ─────────────────────────────

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


def linear_to_srgb(c):
    c = min(1.0, max(0.0, c))
    return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1.0 / 2.4) - 0.055


def C(h):
    """"#rrggbb" (sRGB) → tupla RGB lineal, que es como se guardan los colores de vértice."""
    return tuple(srgb_to_linear(c) for c in hex_rgb(h))


def mixc(a, b, f):
    f = min(1.0, max(0.0, f))
    return tuple(x + (y - x) * f for x, y in zip(a, b))


def mulc(a, k):
    return tuple(x * k for x in a)


WHITE = (1.0, 1.0, 1.0)


def make_material(name, color, rough=0.8, emission=0.0, metallic=0.0, emission_color=None, tint=False):
    """Material PBR de color plano. `color` es "#rrggbb" (sRGB). El color de vértice
    multiplica a este color al exportar (COLOR_0) y en Godot.
    `tint=True` marca un material que el juego tiñe y cuyos vértices llevan el matiz
    dividido por este color (ver `MeshBuilder.vdiv`): la vista previa lo multiplica como
    Godot, en sRGB, para que salga el color de siempre."""
    m = bpy.data.materials.new(name)
    if m.node_tree is None or "Principled BSDF" not in m.node_tree.nodes:
        m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    lin = C(color)
    bsdf.inputs["Base Color"].default_value = (*lin, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metallic
    if emission > 0.0:
        bsdf.inputs["Emission Color"].default_value = (*C(emission_color or color), 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission
    m.diffuse_color = (*lin, 1.0)
    m.use_backface_culling = True          # una sola cara: en glTF, doubleSided = false
    if tint:
        m["tinte_srgb"] = list(hex_rgb(color))
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
    u recorre los anillos (0 .. N-1) con interpolación Catmull-Rom. θ es el ángulo
    polar de la sección (parametrización regular, sin singularidades).
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
        return c, a, b, t, max(cm("rx"), 1e-5), max(cm("ry"), 1e-5), max(cm("ryn"), 1e-5), max(cm("n"), 1.0)

    def point(self, u, th):
        c, a, b, _t, rx, ry, ryn, n = self.frame(u)
        cs, sn = math.cos(th), math.sin(th)
        ryy = ry if sn >= 0.0 else ryn
        rad = (abs(cs / rx) ** n + abs(sn / ryy) ** n) ** (-1.0 / n)
        return c + (a * cs + b * sn) * rad

    def weights(self, u):
        i, f = self._idx(u)
        return mix_weights(self.rings[i]["w"] or {}, self.rings[i + 1]["w"] or {}, f)

    def poly(self, u0, th0, pts, rot=0.0):
        """Polígono dado en metros sobre el plano tangente en (u0, θ0) → lista de (u, θ).
        El eje x del plano va a lo largo de u; el eje y, a lo largo de θ."""
        e = 1e-3
        pa = (self.point(u0 + e, th0) - self.point(u0 - e, th0)) / (2 * e)
        pb = (self.point(u0, th0 + e) - self.point(u0, th0 - e)) / (2 * e)
        e1 = pa.normalized()
        e2 = (pb - e1 * pb.dot(e1)).normalized()
        g11, g12, g22 = pa.dot(pa), pa.dot(pb), pb.dot(pb)
        det = g11 * g22 - g12 * g12
        c0, s0 = math.cos(rot), math.sin(rot)
        out = []
        for x, y in pts:
            d = e1 * (x * c0 - y * s0) + e2 * (x * s0 + y * c0)
            r1, r2 = d.dot(pa), d.dot(pb)
            out.append((u0 + (r1 * g22 - r2 * g12) / det, th0 + (r2 * g11 - r1 * g12) / det))
        return out


def ngon(n, r, star=1.0, phase=0.0, sx=1.0, sy=1.0, radii=None):
    """Puntos (x, y) de un polígono regular o estrellado; `radii` da un radio por vértice."""
    pts = []
    for k in range(n):
        a = phase + 2.0 * math.pi * k / n
        rr = r * (radii[k % len(radii)] if radii else (star if k % 2 else 1.0))
        pts.append((rr * math.cos(a) * sx, rr * math.sin(a) * sy))
    return pts


class MeshBuilder:
    """Acumula vértices, caras, colores y pesos; luego crea el objeto.

    `palette`: {clave: (nombre_de_material, color_lineal)}. Cada cara se pinta con
    una clave; el color se guarda por esquina, así que una malla puede tener muchos
    colores con un solo material."""

    def __init__(self, palette):
        self.palette = palette
        self.verts = []
        self.weights = []
        self.faces = []
        self.fmat = []
        self.fcols = []
        self.focc = []
        self.ao = None
        # {material: (r, g, b) en sRGB}: el color guardado en los vértices de ese material
        # se divide por ese valor, que debe ser el albedo del material. Así el color vive
        # en el material (el juego lo cambia para teñir) y el vértice solo lleva el matiz
        # como factor: con el albedo de fábrica, material × vértice da el color de siempre.
        self.vdiv = {}

    def vert(self, p, w):
        self.verts.append(Vector(p))
        self.weights.append(w)
        return len(self.verts) - 1

    def color(self, key):
        return self.palette[key][1] if isinstance(key, str) else key

    def face(self, idx, key, cols=None, occ=True):
        mat, base = self.palette[key]
        self.faces.append(tuple(idx))
        self.fmat.append(mat)
        if cols is None:
            self.fcols.append([base] * len(idx))
        else:
            self.fcols.append([self.color(c) if c is not None else base for c in cols])
        self.focc.append(occ)

    def tri_count(self):
        return sum(len(f) - 2 for f in self.faces)

    def transform(self, matrix, start=0):
        """Aplica una matriz 4x4 a los vértices desde el índice `start`."""
        for i in range(start, len(self.verts)):
            self.verts[i] = matrix @ self.verts[i]

    # -- lofts --------------------------------------------------------------
    def add_loft(self, loft, mat, segs=12, sub=1, cap0=True, cap1=True, w=None,
                 matfn=None, wfn=None, th0=0.0, u0=None, u1=None, capmat=(None, None), flip=False,
                 col=None):
        """Malla el loft. `mat` clave de la paleta o `matfn(u, th, p) -> clave` (None = sin cara).
        `w` pesos fijos, o `wfn(u, th, p) -> dict`; si no, los de los anillos.
        `col(p, u, th) -> color` da un color por vértice (degradados); si no, el de la clave.
        `flip=True` invierte las caras (superficies interiores: bajo el ala del sombrero…)."""
        u0 = 0.0 if u0 is None else u0
        u1 = loft.umax() if u1 is None else u1
        rows = max(1, int(round((u1 - u0) * sub)))
        us = [u0 + (u1 - u0) * k / rows for k in range(rows + 1)]
        grid, cgrid = [], []
        for u in us:
            row, crow = [], []
            for j in range(segs):
                th = th0 + 2.0 * math.pi * j / segs
                p = loft.point(u, th)
                ww = wfn(u, th, p) if wfn else (w if w is not None else loft.weights(u))
                row.append(self.vert(p, ww))
                crow.append(col(p, u, th) if col else None)
            grid.append(row)
            cgrid.append(crow)
        for k in range(rows):
            um = 0.5 * (us[k] + us[k + 1])
            for j in range(segs):
                j2 = (j + 1) % segs
                thm = th0 + 2.0 * math.pi * (j + 0.5) / segs
                m = matfn(um, thm, loft.point(um, thm)) if matfn else mat
                if m is None:
                    continue
                q = (grid[k][j], grid[k][j2], grid[k + 1][j2], grid[k + 1][j])
                cc = (cgrid[k][j], cgrid[k][j2], cgrid[k + 1][j2], cgrid[k + 1][j]) if col else None
                if flip:
                    q, cc = q[::-1], (cc[::-1] if cc else None)
                self.face(q, m, cc)
        for cap, row, crow, u, flip_cap, cm in ((cap0, grid[0], cgrid[0], us[0], True, capmat[0]),
                                                (cap1, grid[-1], cgrid[-1], us[-1], False, capmat[1])):
            if not cap:
                continue
            c = loft.frame(u)[0]
            ww = wfn(u, 0.0, c) if wfn else (w if w is not None else loft.weights(u))
            ci = self.vert(c, ww)
            m = cm or (matfn(u, 0.0, c) if matfn else mat)
            if m is None:
                continue
            cc0 = col(c, u, 0.0) if (col and not cm) else None
            for j in range(segs):
                j2 = (j + 1) % segs
                a, b = (j2, j) if flip_cap != flip else (j, j2)
                cc = (cc0, crow[a], crow[b]) if (col and not cm) else None
                self.face((ci, row[a], row[b]), m, cc)

    # -- loft con dibujos recortados en la superficie ---------------------------
    def add_loft_painted(self, loft, mat, shapes, segs=12, sub=1, cap0=True, cap1=True, wfn=None,
                         th0=0.0, col=None, capmat=(None, None), u0=None, u1=None):
        """Como add_loft, pero con dibujos "pintados" en la propia malla: `shapes` es una
        lista de (polígono [(u, θ), ...], clave) que se recortan en la superficie con una
        triangulación de Delaunay con restricciones; el último de la lista queda encima.
        La costura está en θ = th0: los dibujos no deben cruzarla (se descartan con aviso)."""
        u0 = 0.0 if u0 is None else u0
        u1 = loft.umax() if u1 is None else u1
        rows = max(1, int(round((u1 - u0) * sub)))
        tau = 2.0 * math.pi
        # escalas para que los triángulos salgan bien proporcionados
        su = sum((loft.frame(u0 + (u1 - u0) * (k + 1) / rows)[0] - loft.frame(u0 + (u1 - u0) * k / rows)[0]).length
                 for k in range(rows)) / (u1 - u0)
        um = 0.5 * (u0 + u1)
        sth = sum((loft.point(um, tau * k / 8) - loft.frame(um)[0]).length for k in range(8)) / 8.0
        pts, faces = [], []
        for k in range(rows + 1):
            u = u0 + (u1 - u0) * k / rows
            for j in range(segs + 1):
                pts.append(Vector((u * su, (th0 + tau * j / segs) * sth)))
        keys = []
        for poly, key in shapes:
            mid = sum(t for _, t in poly) / len(poly)
            shift = math.floor((mid - th0) / tau) * tau
            pp = [(u, t - shift) for u, t in poly]
            if any(t < th0 + 1e-4 or t > th0 + tau - 1e-4 for _, t in pp) or \
               any(u < u0 - 1e-6 or u > u1 + 1e-6 for u, _ in pp):
                full = abs(max(t for _, t in poly) - min(t for _, t in poly) - tau) < 1e-6
                if not full:
                    print("  aviso: dibujo sobre la costura o fuera del loft, descartado:", key)
                    continue
            area = sum(pp[i][0] * pp[(i + 1) % len(pp)][1] - pp[(i + 1) % len(pp)][0] * pp[i][1]
                       for i in range(len(pp)))
            if area < 0:                      # la triangulación solo rellena polígonos antihorarios
                pp.reverse()
            # Ningún borde puede abarcar más de una columna de la malla: en 3D sería una
            # cuerda que atraviesa la prenda. El caso extremo es la franja que da la vuelta
            # entera (dos bordes de costura a costura): sin vértices intermedios, sus
            # triángulos tienen dos esquinas en el mismo punto de la costura y no existen.
            dense = []
            for i, (ua, ta) in enumerate(pp):
                ub, tb = pp[(i + 1) % len(pp)]
                dense.append((ua, ta))
                n = int(math.ceil(abs(tb - ta) * segs / tau - 1e-9))
                dense.extend((ua + (ub - ua) * k / n, ta + (tb - ta) * k / n) for k in range(1, n))
            pp = dense
            base = len(pts)
            pts.extend(Vector((min(max(u, u0), u1) * su, t * sth)) for u, t in pp)
            faces.append(list(range(base, base + len(pp))))
            keys.append(key)
        ov, _oe, of, _ovo, _oeo, off = delaunay_2d_cdt(pts, [], faces, 0, 1e-7, True)
        vid, seam = {}, {}
        params = [(v.x / su, v.y / sth) for v in ov]
        for i, (u, th) in enumerate(params):
            if abs(th - th0) < 1e-6:
                seam[round(u, 5)] = i
        index = [None] * len(ov)

        def V(i):
            if index[i] is None:
                u, th = params[i]
                if abs(th - th0 - tau) < 1e-6 and round(u, 5) in seam:
                    index[i] = V(seam[round(u, 5)])
                else:
                    p = loft.point(u, th)
                    index[i] = self.vert(p, wfn(u, th, p) if wfn else loft.weights(u))
                    vid[index[i]] = (col(p, u, th) if col else None)
            return index[i]

        lost = 0.0                  # superficie que se queda sin triángulos (debe ser nula)
        for tri, orig in zip(of, off):
            a, b, c = tri
            area = (ov[b].x - ov[a].x) * (ov[c].y - ov[a].y) - (ov[c].x - ov[a].x) * (ov[b].y - ov[a].y)
            if abs(area) < 1e-12:
                continue
            ids = [V(a), V(b), V(c)]
            if len(set(ids)) < 3:
                lost += 0.5 * abs(area)
                continue
            if area > 0:            # hacia fuera = sentido horario en el plano (u, θ)
                ids.reverse()
            if orig:
                self.face(ids, keys[max(orig)])
            else:
                self.face(ids, mat, [vid[i] for i in ids] if col else None)
        if lost > 1e-9:
            print("  aviso: %.1f cm² del loft «%s» sin malla (triángulos aplastados en la costura)"
                  % (lost * 1e4, mat))
        for cap, uu, flip_cap, cm in ((cap0, u0, True, capmat[0]), (cap1, u1, False, capmat[1])):
            if not cap:
                continue
            ring = sorted((th, i) for i, (u, th) in enumerate(params)
                          if abs(u - uu) < 1e-6 and th < th0 + tau - 1e-6)
            row = [V(i) for _, i in ring]
            c = loft.frame(uu)[0]
            ci = self.vert(c, wfn(uu, 0.0, c) if wfn else loft.weights(uu))
            cc0 = col(c, uu, 0.0) if (col and not cm) else None
            for j in range(len(row)):
                j2 = (j + 1) % len(row)
                a, b = (j2, j) if flip_cap else (j, j2)
                cc = (cc0, vid.get(row[a]), vid.get(row[b])) if (col and not cm) else None
                self.face((ci, row[a], row[b]), cm or mat, cc)

    # -- esferas / elipsoides -------------------------------------------------
    def add_sphere(self, center, radii, mat, w, segs=12, rings=8, rot=None, deform=None,
                   keep=None, matfn=None, wfn=None, col=None, occ=True):
        """Esfera UV (polos sobre Z local). `deform(d) -> escala radial`, `keep(d) -> bool`
        filtra caras por la dirección unitaria local de su centro, `col(p, d) -> color`."""
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

        idx, cols = {}, {}

        def V(i, j):
            key = (i, 0 if i in (0, rings) else j % segs)
            if key not in idx:
                d = D(*key)
                p = P(d)
                idx[key] = self.vert(p, wfn(d, p) if wfn else w)
                cols[idx[key]] = col(p, d) if col else None
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
                    q = (V(0, 0), V(1, j), V(1, j + 1))
                elif i == rings - 1:
                    q = (V(i, j), V(rings, 0), V(i, j + 1))
                else:
                    q = (V(i, j), V(i + 1, j), V(i + 1, j + 1), V(i, j + 1))
                self.face(q, m, [cols[v] for v in q] if col else None, occ)

    # -- calcomanías sobre una superficie paramétrica ---------------------------
    def add_decal(self, P, a0, b0, radius, mat, w, nseg=6, inner=0.0, offset=0.003,
                  aspect=1.0, rot=0.0, outward=None, star=1.0, arc=(0.0, 1.0), wfn=None):
        """Disco/anillo/estrella pegado a la superficie P(a, b) alrededor de (a0, b0).
        Solo para detalles pequeños (brillos de los ojos…): no proyecta oclusión."""
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
            for k in range(nseg):
                k2 = (k + 1) % n_pts
                self.face((outer[k], outer[k2], inn[k2], inn[k]), mat, occ=False)
        else:
            ci = self.vert(p0 + nrm * offset, wfn(a0, b0, p0) if wfn else w)
            for k in range(nseg):
                k2 = (k + 1) % n_pts
                self.face((ci, outer[k], outer[k2]), mat, occ=False)

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
        attr = mesh.color_attributes.new(COLOR_ATTR, "FLOAT_COLOR", "CORNER")
        flat = []
        for f, cols, mname in zip(self.faces, self.fcols, self.fmat):
            div = self.vdiv.get(mname)
            for v, c in zip(f, cols):
                k = self.ao[v] if self.ao else 1.0
                rgb = (c[0] * k, c[1] * k, c[2] * k)
                if VERTEX_COLORS_SRGB:
                    rgb = tuple(linear_to_srgb(x) for x in rgb)
                if div:
                    rgb = tuple(min(1.0, x / d) for x, d in zip(rgb, div))
                flat.extend((rgb[0], rgb[1], rgb[2], 1.0))
        attr.data.foreach_set("color", flat)
        mesh.color_attributes.active_color = attr
        mesh.color_attributes.render_color_index = 0
        mesh.update()
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


# ─────────────────────────── Oclusión ambiental por vértice ───────────────────────────

def _hemisphere(n):
    """Direcciones fijas, repartidas con peso coseno sobre la semiesfera +Z."""
    out = []
    g = math.pi * (3.0 - math.sqrt(5.0))
    for k in range(n):
        r = math.sqrt((k + 0.5) / n)
        a = g * k
        out.append(Vector((r * math.cos(a), r * math.sin(a), math.sqrt(max(0.0, 1.0 - r * r)))))
    return out


def bake_ao(targets, occluders=None, ground=True, samples=28, dist=0.22, strength=0.8, floor=0.32):
    """Hornea oclusión ambiental en los vértices de los MeshBuilder `targets` lanzando
    rayos contra `occluders` (por defecto los mismos) y, si `ground`, contra el suelo."""
    occluders = occluders or targets
    verts, polys = [], []
    for mb in occluders:
        base = len(verts)
        verts.extend(tuple(v) for v in mb.verts)
        for f, occ in zip(mb.faces, mb.focc):
            if occ:
                for k in range(1, len(f) - 1):
                    polys.append((base + f[0], base + f[k], base + f[k + 1]))
    if ground:
        base = len(verts)
        s = 5.0
        verts.extend([(-s, -s, 0.0), (s, -s, 0.0), (s, s, 0.0), (-s, s, 0.0)])
        polys.append((base, base + 1, base + 2))
        polys.append((base, base + 2, base + 3))
    bvh = BVHTree.FromPolygons(verts, polys)
    dirs = _hemisphere(samples)
    for mb in targets:
        nrm = [Vector((0, 0, 0)) for _ in mb.verts]
        for f in mb.faces:
            p = [mb.verts[i] for i in f]
            fn = Vector((0, 0, 0))
            for k in range(1, len(p) - 1):
                fn += (p[k] - p[0]).cross(p[k + 1] - p[0])
            for i in f:
                nrm[i] += fn
        ao = [1.0] * len(mb.verts)
        for i, n in enumerate(nrm):
            if n.length < 1e-12:
                continue
            n.normalize()
            t = n.cross(Vector((0, 0, 1)) if abs(n.z) < 0.9 else Vector((1, 0, 0)))
            t.normalize()
            b = n.cross(t)
            o = mb.verts[i] + n * 0.006
            occ = 0.0
            for d in dirs:
                hit = bvh.ray_cast(o, t * d.x + b * d.y + n * d.z, dist)
                if hit[0] is not None:
                    occ += 1.0 - hit[3] / dist
            ao[i] = max(floor, 1.0 - strength * occ / samples)
        mb.ao = ao


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


def _rot(deg):
    return Euler([math.radians(a) for a in deg], "XYZ").to_matrix()


class Rig:
    """Cinemática en Python con la misma convención que las poses: cada hueso gira,
    en ejes del modelo, alrededor de su cabeza; los hijos heredan la deformación."""

    def __init__(self, bones):
        self.head = {n: Vector(h) for n, h, _t, _p in bones}
        self.parent = {n: p for n, _h, _t, p in bones}

    def deform(self, pose, bone):
        """Matriz 4x4 que lleva puntos en reposo pegados a `bone` a su sitio en la pose."""
        chain = []
        b = bone
        while b:
            chain.append(b)
            b = self.parent[b]
        D = Matrix.Identity(4)
        for b in reversed(chain):
            h = self.head[b]
            M = Matrix.Translation(h) @ _rot(pose.get(b, (0, 0, 0))).to_4x4()
            s = pose.get(b + ".scale")
            if s:
                M = M @ Matrix.Diagonal((s[0], s[1], s[2], 1.0))
            M = Matrix.Translation(pose.get(b + ".loc", (0, 0, 0))) @ M @ Matrix.Translation(-h)
            D = D @ M
        return D

    def point(self, pose, bone, rest_point):
        return self.deform(pose, bone) @ Vector(rest_point)

    def ik(self, pose, upper, lower, ends, contact_rest, target, bend=-1.0, iters=3):
        """IK con corrección: tras resolver, mide con la cinemática directa dónde quedó el
        apoyo y compensa el error (giros laterales y escalas del padre) unas pocas veces."""
        goal = Vector(target)
        aim = Vector(target)
        for _ in range(iters):
            self._ik_once(pose, upper, lower, ends, contact_rest, aim, bend)
            err = goal - self.point(pose, ends[-1][0], contact_rest)
            if err.length < 1e-5:
                break
            aim = aim + err

    def _ik_once(self, pose, upper, lower, ends, contact_rest, target, bend):
        """IK de dos huesos (upper, lower) en el plano sagital, más una cola de huesos
        `ends` = [(hueso, giro_en_mundo_en_grados), ...] cuya orientación se fija en el
        mundo (pie plano, metatarso…). Coloca el punto `contact_rest` (pegado al último
        hueso) en `target`. bend = -1 dobla la rodilla hacia delante; +1, el codo atrás."""
        pos = Vector(target)
        ref = Vector(contact_rest)
        for bone, rot in reversed(ends):
            pos = pos - _rot(rot) @ (ref - self.head[bone])
            ref = self.head[bone]
        first = ends[0][0]
        Dp = self.deform(pose, self.parent[upper]) @ Matrix.Translation(pose.get(upper + ".loc", (0, 0, 0)))
        d = Dp.inverted() @ pos - self.head[upper]
        r1 = self.head[lower] - self.head[upper]
        r2 = self.head[first] - self.head[lower]
        rd = self.head[first] - self.head[upper]
        if d.z < -1e-3:
            ry = math.atan2(-d.x, -d.z) - math.atan2(-rd.x, -rd.z)
            zz = -math.hypot(d.x, d.z)
        else:
            ry, zz = 0.0, d.z
        L1, L2 = math.hypot(r1.y, r1.z), math.hypot(r2.y, r2.z)
        a1, a2 = math.atan2(r1.y, -r1.z), math.atan2(r2.y, -r2.z)
        dist = min(max(math.hypot(d.y, zz), abs(L1 - L2) + 1e-4), L1 + L2 - 1e-4)
        ad = math.atan2(d.y, -zz)
        beta = math.acos(min(1.0, max(-1.0, (L1 * L1 + dist * dist - L2 * L2) / (2 * L1 * dist))))
        al1 = ad + bend * beta
        ky, kz = L1 * math.sin(al1), -L1 * math.cos(al1)
        ty, tz = dist * math.sin(ad), -dist * math.cos(ad)
        al2 = math.atan2(ty - ky, -(tz - kz))
        pose[upper] = (math.degrees(al1 - a1), math.degrees(ry), 0.0)
        pose[lower] = (math.degrees((al2 - a2) - (al1 - a1)), 0.0, 0.0)
        for bone, rot in ends:
            Rp = self.deform(pose, self.parent[bone]).to_3x3().normalized()
            e = (Rp.inverted() @ _rot(rot)).to_euler("XYZ")
            pose[bone] = tuple(math.degrees(a) for a in e)


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


def L(t, keys):
    """Como K pero lineal entre claves (para contactos exactos)."""
    if t <= keys[0][0]:
        return keys[0][1]
    for (t0, v0), (t1, v1) in zip(keys, keys[1:]):
        if t <= t1:
            f = (t - t0) / (t1 - t0)
            if isinstance(v0, (int, float)):
                return v0 + (v1 - v0) * f
            return tuple(a + (b - a) * f for a, b in zip(v0, v1))
    return keys[-1][1]


def _default(ch):
    return (1.0, 1.0, 1.0) if ch.endswith(".scale") else (0.0, 0.0, 0.0)


def pose_keys(t, keys, loop=None):
    """Interpola poses completas: keys = [(t, {canal: tupla}), ...].
    Los canales que falten en una clave valen cero (o uno para .scale)."""
    chans = set()
    for _, p in keys:
        chans.update(p.keys())
    out = {}
    for ch in chans:
        d = _default(ch)
        out[ch] = _interp_keys(t, [(kt, tuple(p.get(ch, d))) for kt, p in keys], loop)
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


def scale_pose(p, k):
    out = {}
    for ch, v in p.items():
        if ch.endswith(".scale"):
            out[ch] = tuple(1 + (x - 1) * k for x in v)
        else:
            out[ch] = tuple(x * k for x in v)
    return out


def blend_pose(a, b, f):
    """Mezcla lineal de dos poses (f = 0 → a, f = 1 → b)."""
    out = {}
    for ch in set(a) | set(b):
        d = _default(ch)
        out[ch] = tuple(x + (y - x) * f for x, y in zip(a.get(ch, d), b.get(ch, d)))
    return out


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


def bump(t, t0, t1):
    if t <= t0 or t >= t1:
        return 0.0
    return math.sin(math.pi * (t - t0) / (t1 - t0)) ** 2


def squash(s):
    """Escala que conserva el volumen: s en vertical (Z), 1/√s en horizontal."""
    k = 1.0 / math.sqrt(s)
    return (k, k, s)


def bake_actions(arm, anims):
    """anims: lista de (nombre, duración_s, fn(t) -> pose).
    pose: {"Hueso": (rx, ry, rz) grados en ejes del modelo (X izq., Y atrás, Z arriba),
           "Hueso.loc": (x, y, z) metros en ejes del modelo,
           "Hueso.scale": (sx, sy, sz) en ejes del modelo}.
    Cada acción lleva claves en todos los huesos para que ninguna animación deje
    restos de la anterior. Crea una pista NLA por acción (para el exportador)."""
    rest = {b.name: b.matrix_local.to_3x3() for b in arm.data.bones}
    rest_q = {k: m.to_quaternion() for k, m in rest.items()}
    rest_inv = {k: m.inverted() for k, m in rest.items()}
    loc_bones, scale_bones = set(), set()
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
                    s = pose.get(b + ".scale", (1.0, 1.0, 1.0))
                    # escala dada en ejes del modelo → ejes del hueso (huesos alineados)
                    m = rest[b]
                    ls = [sum(m[j][i] * m[j][i] * s[j] for j in range(3)) + 3e-4 for i in range(3)]
                    pb.scale = Vector(ls)
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
        export_vertex_color="ACTIVE",          # COLOR_0 = color de vértice (multiplica al material)
        export_all_vertex_colors=False,
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
    surfaces = {}
    for mesh in doc.get("meshes", []):
        names = []
        for prim in mesh["primitives"]:
            tris += doc["accessors"][prim["indices"]]["count"] // 3
            names.append(doc["materials"][prim["material"]]["name"] + ("" if "COLOR_0" in prim["attributes"] else " (sin COLOR_0)"))
        surfaces[mesh["name"]] = names
    return {
        "bytes": len(data),
        "triangles": tris,
        "animations": [(a["name"], round(max(doc["accessors"][s["input"]]["max"][0] for s in a["samplers"]), 3))
                       for a in doc.get("animations", [])],
        "surfaces": surfaces,
        "joints": len(doc["skins"][0]["joints"]) if doc.get("skins") else 0,
    }


# ─────────────────────────────── Vista previa ───────────────────────────────

def link_vertex_colors():
    """Para Cycles: conecta el color de vértice (× color base) a cada material.
    Se hace solo al renderizar; el exportador usa los materiales sin nodos extra."""
    for m in bpy.data.materials:
        nt = m.node_tree
        if nt is None or "Principled BSDF" not in nt.nodes or m.name.startswith("Preview"):
            continue
        bsdf = nt.nodes["Principled BSDF"]
        if bsdf.inputs["Base Color"].is_linked:
            continue
        vc = nt.nodes.new("ShaderNodeVertexColor")
        vc.layer_name = COLOR_ATTR
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        mix.inputs["A"].default_value = bsdf.inputs["Base Color"].default_value
        if VERTEX_COLORS_SRGB and m.get("tinte_srgb"):
            # material teñible: Godot multiplica albedo y vértice tal como están guardados
            # (en sRGB); aquí se hace igual y se pasa a lineal el producto
            mix.inputs["A"].default_value = (*m["tinte_srgb"], 1.0)
            gam = nt.nodes.new("ShaderNodeGamma")
            gam.inputs["Gamma"].default_value = 2.2
            nt.links.new(vc.outputs["Color"], mix.inputs["B"])
            nt.links.new(mix.outputs["Result"], gam.inputs["Color"])
            nt.links.new(gam.outputs["Color"], bsdf.inputs["Base Color"])
            continue
        if VERTEX_COLORS_SRGB:              # Cycles sí trabaja en lineal: deshacer la codificación
            gam = nt.nodes.new("ShaderNodeGamma")
            gam.inputs["Gamma"].default_value = 2.2
            nt.links.new(vc.outputs["Color"], gam.inputs["Color"])
            nt.links.new(gam.outputs["Color"], mix.inputs["B"])
        else:
            nt.links.new(vc.outputs["Color"], mix.inputs["B"])
        nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])


def setup_preview(ground_color="#5d7a4a", sky="#b9d3e6", ground=True, ambient=0.9, key=3.2, threads=2):
    """Luces, cielo y suelo para renders con Cycles en CPU (pocos hilos: máquina compartida)."""
    import addon_utils
    addon_utils.enable("cycles", default_set=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.render.threads_mode = "FIXED"
    scene.render.threads = threads
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 3
    scene.view_settings.view_transform = "Standard"
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.image_settings.compression = 100
    link_vertex_colors()
    world = bpy.data.worlds.new("PreviewWorld")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (*C(sky), 1.0)
    bg.inputs[1].default_value = ambient
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

    sun("Key", key, (50, 0, 35), (1.0, 0.95, 0.85))
    sun("Fill", 0.8, (60, 0, -140), (0.8, 0.9, 1.0))
    if ground:
        gm = bpy.data.meshes.new("PreviewGround")
        s = 30.0
        gm.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
        gm.materials.append(make_material("PreviewGroundMat", ground_color, 1.0))
        preview.objects.link(bpy.data.objects.new("PreviewGround", gm))
    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_data.lens = 60
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    preview.objects.link(cam)
    scene.camera = cam
    return cam


def render(path, cam, target, yaw_deg, pitch_deg, dist, res=480, samples=24, transparent=False):
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
    scene.render.film_transparent = transparent
    scene.render.image_settings.color_mode = "RGBA" if transparent else "RGB"
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
