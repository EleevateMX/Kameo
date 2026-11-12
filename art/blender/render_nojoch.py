"""Imágenes de la propuesta de Nojoch Tuunich (art/propuestas/nojoch/), con Blender local.

Uso (desde la raíz del repo):
    .tools/blender-venv/bin/python art/blender/render_nojoch.py [qué] [carpeta] [muestras] [reducción]
    .tools/blender-venv/bin/python art/blender/render_nojoch.py toma Anim segundos giro elevación salida.png [lado] [recuerda|caras]

`qué` es todo (por omisión), hoja, sentado, escala, poses, recuerda o medidas:
    nojoch_hoja.png      1920×1080: frente, tres cuartos, lado y espalda, de pie («Idle», cuadro 0)
    nojoch_sentado.png   dormido («Sleep»), tres cuartos
    nojoch_escala.png    de pie junto a un alux y a Balam, a escala real (sus modelos se
                         construyen con build_alux.py y build_balam.py, sin tocarlos)
    nojoch_poses.png     cuadros clave de «Slam», «Sweep», «Kneel» y «Remember» (cada uno a su encuadre)
    nojoch_recuerda.png  «Remember» por delante y por detrás con las vetas apagadas y los
                         glifos, los ojos y el corazón encendidos
    medidas              no renderiza: imprime alturas, apoyos y contactos con el suelo
    godot <carpeta>      no renderiza: junta en nojoch_godot.png las capturas hechas con el
                         renderer de Godot (art/godot/render_nojoch.gd)
`toma` saca un cuadro suelto de cualquier animación (para ajustar poses); con `caras`
pinta de rojo las caras vistas por detrás (en el juego serían agujeros).

Con [reducción] (p. ej. 0.4) todo sale más pequeño, para una prueba rápida.

Fondo gris neutro, sin suelo (solo la sombra de contacto) y sin textos, como las hojas
de art/referencias. Cycles en CPU, 2 hilos. Necesita Pillow.
"""
import math
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import alux_common as kc  # noqa: E402  (importa bpy antes que mathutils)
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402
import render_referencias as rr  # noqa: E402
import build_nojoch as nj  # noqa: E402

OUTDIR = os.path.join(nj.REPO, "art", "propuestas", "nojoch")
MARGEN = 0.06
RED = 1.0                        # reducción de todas las imágenes (pruebas rápidas)


def px(n):
    return max(16, int(round(n * RED)))


# ───────────────────────────────── Escena ─────────────────────────────────

def recordar(mats):
    """Estado «el guardián recuerda»: vetas apagadas (cicatrices grises) y jade encendido.
    Es lo que hará el juego con los materiales; el .glb se exporta en el estado olvidado."""
    def poner(nombre, fuerza, base=None):
        bsdf = mats[nombre].node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Emission Color"].default_value = (*kc.C(nj.HEX["JadeLuz" if nombre == "Eye" else "JadeVivo"]), 1.0)
        bsdf.inputs["Emission Strength"].default_value = fuerza
        if base:
            bsdf.inputs["Base Color"].default_value = (*kc.C(base), 1.0)

    poner("Silence", nj.EMISION_RECUERDA["Silence"], nj.HEX["SilencioApagado"])
    poner("Heart", nj.EMISION_RECUERDA["Heart"])
    poner("Eye", nj.EMISION_RECUERDA["Eye"])
    for i in range(1, 5):
        poner("Glyph%d" % i, nj.EMISION_RECUERDA["Glyph"])


def construir(recuerda=False, con_escala=False):
    """Construye el coloso (y, para la imagen de escala, el alux y Balam en la misma escena)."""
    arm, objs = nj.build()
    todo = {"nojoch": (arm, objs, dict((a[0], a[1]) for a in nj.ANIMS))}
    if recuerda:
        recordar({m.name: m for m in objs["Nojoch"].data.materials})
    if con_escala:
        vaciar = kc.reset_scene
        kc.reset_scene = lambda: bpy.context.scene        # los otros build() no deben vaciar la escena
        try:
            for quien in ("alux", "balam"):
                mod = __import__("build_" + quien)
                a, o = mod.build()
                todo[quien] = (a, o, dict((x[0], x[1]) for x in mod.ANIMS))
        finally:
            kc.reset_scene = vaciar
    rr.SOMBRA_RADIO, rr.SOMBRA_FUERZA = 1.1, 0.5         # sombra de contacto a la medida de un coloso
    cam, eje = rr.preparar_escena()
    return todo, cam, eje


def posar(ficha, anim, t):
    """Pone un esqueleto en el segundo `t` de una animación. Busca la acción en sus
    pistas NLA (y no por nombre global) para que convivan varios personajes."""
    arm, _objs, dur = ficha
    cuadros = max(1, round(dur[anim] * kc.FPS))
    ad = arm.animation_data
    # al convivir varios personajes, Blender renombra las acciones repetidas («Idle.001»)
    pista = next(tr for tr in ad.nla_tracks if tr.name == anim or tr.name.rsplit(".", 1)[0] == anim)
    ad.action = pista.strips[0].action
    try:
        if ad.action_slot is None and ad.action.slots:
            ad.action_slot = ad.action.slots[0]
    except AttributeError:
        pass
    bpy.context.scene.frame_set(int(round(t / dur[anim] * cuadros)))


def nube(fichas):
    pts = []
    for _arm, objs, _dur in fichas:
        pts += rr.puntos(objs)
    return pts


def ejes(giro, elev):
    """Ejes de la cámara (hacia ella, derecha, arriba) para un giro y una elevación."""
    a, e = math.radians(giro), math.radians(elev)
    o = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
    r = Vector((0, 0, 1)).cross(o).normalized()
    return o, r, o.cross(r)


def encuadrar(pts, cam, giro, elev, w, h, margen=MARGEN):
    """Objetivo y distancia para que la nube de puntos quepa entera y centrada."""
    import numpy as np
    o, r, u = (np.array(v) for v in ejes(giro, elev))
    t = 0.5 * cam.data.sensor_width / cam.data.lens
    tx, ty = (t, t * h / w) if w >= h else (t * w / h, t)
    tx, ty = tx * (1 - 2 * margen), ty * (1 - 2 * margen)
    vs = np.array(pts, dtype=float)
    obj = 0.5 * (vs.min(axis=0) + vs.max(axis=0))
    dist = 10.0
    for _ in range(8):
        q = vs - obj
        po, pr, pu = q @ o, q @ r, q @ u
        # la distancia mínima a la que cada punto entra en el cuadro
        dist = float(np.max(po + np.maximum(np.abs(pr) / tx, np.abs(pu) / ty)))
        xs, ys = pr / (dist - po), pu / (dist - po)
        obj = obj + r * (0.5 * (xs.min() + xs.max()) * dist) + u * (0.5 * (ys.min() + ys.max()) * dist)
    return Vector(obj), dist


def desvanecer(im, borde=0.05):
    """La sombra de contacto no debe cortarse en seco en el borde del cuadro: la opacidad
    cae a cero en una franja junto a los cuatro bordes (el personaje nunca llega hasta ahí)."""
    import numpy as np
    from PIL import Image
    a = np.asarray(im.convert("RGBA")).astype(np.float32)
    h, w = a.shape[:2]

    def rampa(n):
        k = np.arange(n, dtype=np.float32)
        f = np.clip(np.minimum(k, n - 1 - k) / max(2.0, borde * n), 0.0, 1.0)
        return f * f * (3.0 - 2.0 * f)

    a[..., 3] *= np.outer(rampa(h), rampa(w))
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def toma(path, cam, eje, objetivo, giro, elev, dist, w, h, muestras):
    """Render w×h con fondo transparente; las luces giran con la cámara."""
    scene = bpy.context.scene
    o, _r, _u = ejes(giro, elev)
    cam.data.shift_x = cam.data.shift_y = 0.0
    cam.location = Vector(objetivo) + o * dist
    cam.rotation_euler = (-o).to_track_quat("-Z", "Y").to_euler()
    eje.rotation_euler = (0.0, 0.0, math.radians(giro))
    scene.render.resolution_x, scene.render.resolution_y = w, h
    scene.render.resolution_percentage = 100
    scene.cycles.samples = muestras
    scene.render.film_transparent = True
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    from PIL import Image
    return desvanecer(Image.open(path))


def guardar(im, path):
    im.save(path, optimize=True)
    print("imagen", path, os.path.getsize(path), "bytes")


def pintar_caras_traseras():
    """Depuración: las caras vistas por detrás salen rojas."""
    for m in bpy.data.materials:
        nt = m.node_tree
        if nt is None or "Principled BSDF" not in nt.nodes or m.name.startswith("Preview"):
            continue
        out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
        geo, mix, rojo = nt.nodes.new("ShaderNodeNewGeometry"), nt.nodes.new("ShaderNodeMixShader"), nt.nodes.new("ShaderNodeEmission")
        rojo.inputs["Color"].default_value = (1, 0, 0, 1)
        rojo.inputs["Strength"].default_value = 3.0
        nt.links.new(geo.outputs["Backfacing"], mix.inputs[0])
        nt.links.new(nt.nodes["Principled BSDF"].outputs[0], mix.inputs[1])
        nt.links.new(rojo.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs["Surface"])


# ───────────────────────────────── Imágenes ─────────────────────────────────

def hoja(outdir, muestras, tmp):
    todo, cam, eje = construir()
    ficha = todo["nojoch"]
    posar(ficha, "Idle", 0.0)
    pts = rr.puntos(ficha[1])
    objetivo, dist = rr.encuadre([(pts, giro) for _n, giro in rr.VISTAS], cam, 2.5)
    print("hoja: altura %.3f m, cámara a 2.50 m de altura y %.2f m de distancia" % (max(p[2] for p in pts), dist))
    from PIL import Image
    capas = []
    for nombre, giro in rr.VISTAS:
        eje.rotation_euler = (0.0, 0.0, math.radians(giro))
        crudo = os.path.join(tmp, "hoja_%s.png" % nombre)
        kc.render(crudo, cam, objetivo, giro, 0.0, dist, res=px(1100), samples=muestras, transparent=True)
        capas.append(desvanecer(Image.open(crudo)))
    path = os.path.join(outdir, "nojoch_hoja.png")
    rr.HOJA = (px(1920), px(1080))
    rr.hoja(capas, path)
    print("imagen", path, os.path.getsize(path), "bytes")


def sentado(outdir, muestras, tmp):
    todo, cam, eje = construir()
    posar(todo["nojoch"], "Sleep", 0.0)
    w, h = px(1440), px(1080)
    objetivo, dist = encuadrar(nube([todo["nojoch"]]), cam, 35, 8, w, h)
    im = toma(os.path.join(tmp, "sentado.png"), cam, eje, objetivo, 35, 8, dist, w, h, muestras)
    guardar(rr.sobre_fondo(im), os.path.join(outdir, "nojoch_sentado.png"))


def escala(outdir, muestras, tmp):
    todo, cam, eje = construir(con_escala=True)
    posar(todo["nojoch"], "Idle", 0.0)
    posar(todo["alux"], "Idle", 0.0)
    posar(todo["balam"], "Idle", 0.0)
    rr.show_hats(todo["alux"][1], "Hair+Hat_Palma")
    todo["alux"][0].location = (-3.0, -0.9, 0.0)
    todo["alux"][0].rotation_euler = (0.0, 0.0, math.radians(-12))
    todo["balam"][0].location = (3.1, -0.9, 0.0)
    todo["balam"][0].rotation_euler = (0.0, 0.0, math.radians(38))
    bpy.context.view_layer.update()
    w, h = px(1920), px(1080)
    objetivo, dist = encuadrar(nube(todo.values()), cam, 14, 3, w, h)
    im = toma(os.path.join(tmp, "escala.png"), cam, eje, objetivo, 14, 3, dist, w, h, muestras)
    guardar(rr.sobre_fondo(im), os.path.join(outdir, "nojoch_escala.png"))


# (animación, segundos, giro, elevación)
POSES = [("Slam", nj.SLAM_HIT + 0.05, 40, 10), ("Sweep", nj.SWEEP_START + 0.1, -30, 14),
         ("Kneel", nj.KNEEL_T, 40, 6), ("Remember", nj.REMEMBER_T, 28, 6)]


def poses(outdir, muestras, tmp):
    from PIL import Image
    todo, cam, eje = construir()
    ficha = todo["nojoch"]
    w, h = px(960), px(540)
    lienzo = Image.new("RGBA", (2 * w, 2 * h), rr.FONDO)
    for i, (anim, t, giro, elev) in enumerate(POSES):
        posar(ficha, anim, t)
        objetivo, dist = encuadrar(nube([ficha]), cam, giro, elev, w, h)   # cada cuadro, a su encuadre
        im = toma(os.path.join(tmp, "pose_%d.png" % i), cam, eje, objetivo, giro, elev, dist, w, h, muestras)
        lienzo.alpha_composite(im, ((i % 2) * w, (i // 2) * h))
    guardar(lienzo.convert("RGB"), os.path.join(outdir, "nojoch_poses.png"))


def recuerda(outdir, muestras, tmp):
    from PIL import Image
    todo, cam, eje = construir(recuerda=True)
    ficha = todo["nojoch"]
    posar(ficha, "Remember", nj.REMEMBER_T)
    w, h = px(960), px(1080)
    vistas = [(26, 6), (152, 10)]
    cuadros = [encuadrar(nube([ficha]), cam, giro, elev, w, h) for giro, elev in vistas]
    dist = max(d for _o, d in cuadros)
    lienzo = Image.new("RGBA", (2 * w, h), rr.FONDO)
    for i, ((giro, elev), (objetivo, _d)) in enumerate(zip(vistas, cuadros)):
        im = toma(os.path.join(tmp, "recuerda_%d.png" % i), cam, eje, objetivo, giro, elev, dist, w, h, muestras)
        lienzo.alpha_composite(im, (i * w, 0))
    guardar(lienzo.convert("RGB"), os.path.join(outdir, "nojoch_recuerda.png"))


def medidas():
    """Alturas y contactos, medidos sobre la malla deformada (para el README y para ajustar poses)."""
    arm, objs = nj.build()
    ficha = (arm, objs, dict((a[0], a[1]) for a in nj.ANIMS))
    ob = objs["Nojoch"]
    mats = [m.name for m in ob.data.materials]
    grupos = {g.index: g.name for g in ob.vertex_groups}
    hueso = [grupos[max(v.groups, key=lambda g: g.weight).group] for v in ob.data.vertices]
    de_mat = {}
    for p in ob.data.polygons:
        for vi in p.vertices:
            de_mat.setdefault(mats[p.material_index], set()).add(vi)

    def malla():
        dg = bpy.context.evaluated_depsgraph_get()
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        co = [ev.matrix_world @ v.co for v in me.vertices]
        ev.to_mesh_clear()
        return co

    def caja(co, idx=None):
        sel = [co[i] for i in idx] if idx is not None else co
        return [(min(p[k] for p in sel), max(p[k] for p in sel)) for k in range(3)]

    posar(ficha, "Idle", 0.0)
    co = malla()
    bb = caja(co)
    print("De pie (Idle 0): alto %.2f m, ancho %.2f m, fondo %.2f m" % (bb[2][1], bb[0][1] - bb[0][0], bb[1][1] - bb[1][0]))
    hb = caja(co, de_mat["Heart"])
    print("  corazón: centro a %.2f m (de %.2f a %.2f); glifos entre %.2f y %.2f m" % (
        0.5 * (hb[2][0] + hb[2][1]), hb[2][0], hb[2][1], *caja(co, de_mat["Glyph1"])[2]))
    posar(ficha, "Sleep", 0.0)
    bb = caja(malla())
    print("Sentado (Sleep 0): alto %.2f m, ancho %.2f m, de y=%.2f a y=%.2f" % (bb[2][1], bb[0][1] - bb[0][0], *bb[1]))
    for anim, t in (("Kneel", nj.KNEEL_T), ("Remember", nj.REMEMBER_T)):
        posar(ficha, anim, t)
        co = malla()
        hb = caja(co, de_mat["Heart"])
        print("%s (final): alto %.2f m; corazón a %.2f m (de %.2f a %.2f)" % (
            anim, caja(co)[2][1], 0.5 * (hb[2][0] + hb[2][1]), hb[2][0], hb[2][1]))
    for anim, t, mano in (("Slam", nj.SLAM_HIT + 0.05, ("Hand_R", "Fingers_R", "FingerTips_R")),
                          ("Summon", nj.SUMMON_HIT + 0.05, ("Hand_L", "Fingers_L", "FingerTips_L")),
                          ("Sweep", nj.SWEEP_START + 0.1, ("Hand_R", "Fingers_R", "FingerTips_R")),
                          ("Sweep", nj.SWEEP_END, ("Hand_R", "Fingers_R", "FingerTips_R"))):
        posar(ficha, anim, t)
        co = malla()
        idx = [i for i, h in enumerate(hueso) if h in mano]
        b = caja(co, idx)
        print("%s a %.2f s: la mano queda en x %.2f..%.2f, y %.2f..%.2f, z %.2f..%.2f" % (anim, t, *b[0], *b[1], *b[2]))
    print("Punto más bajo de la malla en cada animación (bajo cero = atraviesa el suelo):")
    for anim, dur, _fn in nj.ANIMS:
        peor, cuando, alto, quien = 1e9, 0.0, 0.0, ""
        n = max(1, round(dur * kc.FPS))
        for f in range(0, n + 1, 2):
            posar(ficha, anim, dur * f / n)
            co = malla()
            i = min(range(len(co)), key=lambda k: co[k][2])
            alto = max(alto, max(p[2] for p in co))
            if co[i][2] < peor:
                peor, cuando, quien = co[i][2], dur * f / n, hueso[i]
        print("  %-9s %.3f m (a %.2f s, %s); altura máxima %.2f m" % (anim, peor, cuando, quien, alto))


def hoja_godot(capturas, outdir, celda=480, columnas=4):
    """Hoja de contacto con las capturas de art/godot/render_nojoch.gd (n01…n08)."""
    import glob
    from PIL import Image
    files = sorted(glob.glob(os.path.join(capturas, "n[0-9][0-9]_*.png")))
    if not files:
        sys.exit("no hay capturas n??_*.png en " + capturas)
    filas = (len(files) + columnas - 1) // columnas
    lienzo = Image.new("RGB", (columnas * celda, filas * celda), rr.FONDO)
    for i, f in enumerate(files):
        im = Image.open(f).convert("RGB").resize((celda, celda), Image.LANCZOS)
        lienzo.paste(im, ((i % columnas) * celda, (i // columnas) * celda))
    os.makedirs(outdir, exist_ok=True)
    guardar(lienzo, os.path.join(outdir, "nojoch_godot.png"))


def suelta(args):
    anim, t, giro, elev, path = args[0], float(args[1]), float(args[2]), float(args[3]), args[4]
    lado = int(args[5]) if len(args) > 5 else 640
    extra = args[6] if len(args) > 6 else ""
    todo, cam, eje = construir(recuerda=(extra == "recuerda"))
    if extra == "caras":
        pintar_caras_traseras()
    posar(todo["nojoch"], anim, t)
    objetivo, dist = encuadrar(nube([todo["nojoch"]]), cam, giro, elev, lado, lado)
    im = toma(path, cam, eje, objetivo, giro, elev, dist, lado, lado, 12)
    rr.sobre_fondo(im).save(path)
    print("toma", path)


def main():
    que = sys.argv[1] if len(sys.argv) > 1 else "todo"
    if que == "toma":
        return suelta(sys.argv[2:])
    if que == "medidas":
        return medidas()
    if que == "godot":
        return hoja_godot(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else OUTDIR)
    outdir = sys.argv[2] if len(sys.argv) > 2 else OUTDIR
    muestras = int(sys.argv[3]) if len(sys.argv) > 3 else 24
    global RED
    RED = float(sys.argv[4]) if len(sys.argv) > 4 else 1.0
    pasos = {"hoja": hoja, "sentado": sentado, "escala": escala, "poses": poses, "recuerda": recuerda}
    if que != "todo" and que not in pasos:
        sys.exit("no sé hacer «%s» (todo, %s, medidas o toma)" % (que, ", ".join(pasos)))
    os.makedirs(outdir, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="nojoch_") as tmp:
        for nombre, paso in pasos.items():
            if que in ("todo", nombre):
                paso(outdir, muestras, tmp)


if __name__ == "__main__":
    main()
