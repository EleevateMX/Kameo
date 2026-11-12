"""Imágenes de Nojoch Tuunich (art/propuestas/nojoch/ y art/referencias/), con Blender local.

Uso (desde la raíz del repo):
    .tools/blender-venv/bin/python art/blender/render_nojoch.py [qué] [carpeta] [muestras] [reducción]
    .tools/blender-venv/bin/python art/blender/render_nojoch.py toma Anim segundos giro elevación salida.png [lado] [estado|caras]

`qué` es todo (por omisión), referencias, sentado, escala, poses, estados o medidas:
    referencias          la hoja definitiva para Kling, en art/referencias/ (o en [carpeta]):
                         nojoch_frente / _tres_cuartos / _lado / _espalda.png (1024×1024) y
                         nojoch_hoja.png (1920×1080), de pie («Idle», cuadro 0) en estado
                         «olvido», como aparece al despertar; y nojoch_liberado_hoja.png, la
                         misma hoja en estado «liberado». Fondo #d2d2d2, sin textos. La hoja
                         de olvido se copia también a art/propuestas/nojoch/nojoch_hoja.png.
    nojoch_sentado.png   dormido («Sleep»): ojos apagados y vetas tenues
    nojoch_escala.png    de pie junto a un alux y a Balam, a escala real (sus modelos se
                         construyen con build_alux.py y build_balam.py, sin tocarlos)
    nojoch_poses.png     cuadros clave de «Slam», «Sweep», «Kneel» y «Remember»
    nojoch_estados.png   la cara triste, dolorida y serena, y el cuerpo entero en los cinco
                         estados (dormido, olvido, furia, recuerdo, liberado); con rótulos
    medidas              no renderiza: imprime alturas, apoyos, contactos con el suelo, el
                         arco del barrido y si algo patina o da saltos
    godot <carpeta>      no renderiza: junta en nojoch_godot.png las capturas hechas con el
                         renderer de Godot (art/godot/render_nojoch.gd)
`toma` saca un cuadro suelto de cualquier animación (para ajustar poses); con `caras`
pinta de rojo las caras vistas por detrás (en el juego serían agujeros).

Con [reducción] (p. ej. 0.4) todo sale más pequeño, para una prueba rápida.

Los estados (ESTADOS) son los mismos que aplica el juego cambiando materiales por nombre
y mezclando las poses «Face_*»; aquí se ponen en los materiales de Blender. Fondo gris
neutro, sin suelo (solo la sombra de contacto). Cycles en CPU, 2 hilos. Necesita Pillow.
"""
import math
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import alux_common as kc  # noqa: E402  (importa bpy antes que mathutils)
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402
import render_referencias as rr  # noqa: E402
import build_nojoch as nj  # noqa: E402

OUTDIR = os.path.join(nj.REPO, "art", "propuestas", "nojoch")
REFDIR = os.path.join(nj.REPO, "art", "referencias")
MARGEN = 0.06
RED = 1.0                        # reducción de todas las imágenes (pruebas rápidas)
GAMMA_VISTA = float(os.environ.get("NOJOCH_GAMMA", "1.2"))   # ver como_en_godot()
TINTE_SOL = (1.0, 1.0, 0.82)
BASE_EXPORTADA = {}              # color base de cada material tal como se exporta (con el tinte)

MAGENTA, JADE = nj.HEX["Silencio"], nj.HEX["JadeVivo"]
OJO_APAGADO = "#2e302c"
# ojos: (color | None = apagados, fuerza); vetas / vetas2: fuerza de la emisión (0 = apagadas);
# glifos: cuántos encendidos; corazon: fuerza; cara: expresión (o mezcla A, B, peso)
ESTADOS = {
    "dormido": dict(ojos=(None, 0.0), vetas=0.25, vetas2=0.0, glifos=0, corazon=0.5, cara=None),
    "olvido": dict(ojos=(MAGENTA, 1.6), vetas=1.7, vetas2=0.0, glifos=2, corazon=1.4, cara=("Face_Sad", None, 0.0)),
    "olvido0": dict(ojos=(MAGENTA, 1.6), vetas=1.7, vetas2=0.0, glifos=0, corazon=1.4, cara=("Face_Sad", None, 0.0)),
    "furia": dict(ojos=(MAGENTA, 2.6), vetas=2.6, vetas2=2.4, glifos=4, corazon=1.4, cara=("Face_Pain", None, 0.0)),
    "recuerdo": dict(ojos=(JADE, 1.6), vetas=0.7, vetas2=0.0, glifos=4, corazon=2.0, cara=("Face_Sad", "Face_Serene", 0.5)),
    "liberado": dict(ojos=(JADE, 1.6), vetas=0.0, vetas2=0.0, glifos=4, corazon=2.4, cara=("Face_Serene", None, 0.0)),
}


def px(n):
    return max(16, int(round(n * RED)))


# ───────────────────────────────── Escena ─────────────────────────────────

def poner_estado(objs, nombre):
    """Materiales de un estado, como los pone el juego (ver «Estados» en el README)."""
    e = ESTADOS[nombre]
    mats = {m.name: m for m in objs["Nojoch"].data.materials}

    def poner(mat, base=None, emision=None, fuerza=0.0, vcol=True):
        nt = mats[mat].node_tree
        bsdf = nt.nodes["Principled BSDF"]
        mezcla = next((n for n in nt.nodes if n.type == "MIX"), None)       # color base × color de vértice
        if base is not None:
            if mezcla is not None:
                mezcla.inputs["A"].default_value = (*kc.C(base), 1.0)
            else:
                bsdf.inputs["Base Color"].default_value = (*kc.C(base), 1.0)
        if mezcla is not None:
            mezcla.inputs["Factor"].default_value = 1.0 if vcol else 0.0
        if emision is not None:
            bsdf.inputs["Emission Color"].default_value = (*kc.C(emision), 1.0)
        bsdf.inputs["Emission Strength"].default_value = fuerza

    if e["vetas"] > 0.0:
        poner("Silence", "#ffffff", MAGENTA, e["vetas"])
    else:
        poner("Silence", nj.HEX["SilencioApagado"], MAGENTA, 0.0, vcol=False)
    if e["vetas2"] > 0.0:
        poner("Silence2", MAGENTA, MAGENTA, e["vetas2"], vcol=False)
    else:
        poner("Silence2", None, MAGENTA, 0.0)
        mezcla2 = next(n for n in mats["Silence2"].node_tree.nodes if n.type == "MIX")
        mezcla2.inputs["A"].default_value = BASE_EXPORTADA["Silence2"]      # vuelve a ser piedra
    for i in range(1, 5):
        if i <= e["glifos"]:
            poner("Glyph%d" % i, "#ffffff", JADE, 2.4)
        else:
            poner("Glyph%d" % i, nj.HEX["GlifoApagado"], JADE, 0.0)
    color, fuerza = e["ojos"]
    poner("Eye", color or OJO_APAGADO, color or JADE, fuerza, vcol=False)
    poner("Heart", None, JADE, e["corazon"])


def construir(con_escala=False):
    """Construye el coloso (y, para la imagen de escala, el alux y Balam en la misma escena)."""
    arm, objs = nj.build()
    todo = {"nojoch": (arm, objs, dict((a[0], a[1]) for a in nj.ANIMS))}
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
    como_en_godot(objs["Nojoch"])
    return todo, cam, eje


def como_en_godot(ob):
    """El renderer del juego usa el color de vértice tal cual, sin descodificar sRGB, y por
    eso allí la piedra se ve bastante más clara que su código hex. La paleta del coloso
    está ajustada mirando Godot; para que estas imágenes enseñen la caliza del color que
    tiene en el juego, sus materiales descodifican el color de vértice con GAMMA_VISTA en
    vez de 2.2 y la piedra lleva el tinte del sol del juego, TINTE_SOL (aquí la luz es
    blanca). Los demás personajes no se tocan."""
    for m in ob.data.materials:
        for n in m.node_tree.nodes:
            if n.type == "GAMMA":
                n.inputs["Gamma"].default_value = GAMMA_VISTA
            if n.type == "MIX" and m.name in ("Body", "Silence2"):
                a = n.inputs["A"].default_value
                n.inputs["A"].default_value = (a[0] * TINTE_SOL[0], a[1] * TINTE_SOL[1], a[2] * TINTE_SOL[2], 1.0)
            if n.type == "MIX":
                BASE_EXPORTADA[m.name] = tuple(n.inputs["A"].default_value)


def posar(ficha, anim, t, estado=None):
    """Pone un esqueleto en el segundo `t` de una animación. Busca la acción en sus
    pistas NLA (y no por nombre global) para que convivan varios personajes. Con `estado`
    (solo el coloso) pone además sus materiales y su cara: la pose se congela (se quita la
    acción) y la expresión se escribe encima, como hará el juego."""
    arm, objs, dur = ficha
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
    if estado is None:
        return
    poner_estado(objs, estado)
    ev = arm.evaluated_get(bpy.context.evaluated_depsgraph_get())
    base = {pb.name: pb.matrix_basis.copy() for pb in ev.pose.bones}
    ad.action = None
    for pb in arm.pose.bones:
        pb.matrix_basis = base[pb.name]
    cara = ESTADOS[estado]["cara"]
    if cara:
        nj.apply_face(arm, *cara)
    bpy.context.view_layer.update()


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


def rotulo(im, texto, xy, alto=30):
    from PIL import ImageDraw, ImageFont
    try:
        fuente = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", px(alto))
    except OSError:
        fuente = ImageFont.load_default()
    ImageDraw.Draw(im).text(xy, texto, fill="#3a3a3a", font=fuente, anchor="ma")


# ───────────────────────────────── Imágenes ─────────────────────────────────

def referencias(outdir, muestras, tmp):
    """La hoja para Kling: cuatro vistas con el mismo encuadre, en «olvido» y en «liberado»."""
    from PIL import Image
    todo, cam, eje = construir()
    ficha = todo["nojoch"]
    refdir = REFDIR if outdir == OUTDIR else outdir
    os.makedirs(refdir, exist_ok=True)
    res = px(1024)
    rr.HOJA = (px(1920), px(1080))
    for estado, prefijo in (("olvido0", "nojoch"), ("liberado", "nojoch_liberado")):
        posar(ficha, "Idle", 0.0, estado)
        pts = rr.puntos(ficha[1])
        objetivo, dist = rr.encuadre([(pts, giro) for _n, giro in rr.VISTAS], cam, 2.5)
        print("%s: altura %.3f m, cámara a 2.50 m de altura y %.2f m de distancia" % (prefijo, max(p[2] for p in pts), dist))
        capas = []
        for nombre, giro in rr.VISTAS:
            eje.rotation_euler = (0.0, 0.0, math.radians(giro))
            crudo = os.path.join(tmp, "%s_%s.png" % (prefijo, nombre))
            kc.render(crudo, cam, objetivo, giro, 0.0, dist, res=res, samples=muestras, transparent=True)
            capas.append(desvanecer(Image.open(crudo)))
            if estado == "olvido0":
                guardar(rr.sobre_fondo(capas[-1]), os.path.join(refdir, "%s_%s.png" % (prefijo, nombre)))
        path = os.path.join(refdir, prefijo + "_hoja.png")
        rr.hoja(capas, path)
        print("imagen", path, os.path.getsize(path), "bytes")
        if estado == "olvido0" and os.path.abspath(refdir) != os.path.abspath(outdir):
            shutil.copyfile(path, os.path.join(outdir, "nojoch_hoja.png"))
            print("imagen", os.path.join(outdir, "nojoch_hoja.png"), "(copia)")


def sentado(outdir, muestras, tmp):
    todo, cam, eje = construir()
    posar(todo["nojoch"], "Sleep", 0.0, "dormido")
    w, h = px(1440), px(1080)
    objetivo, dist = encuadrar(nube([todo["nojoch"]]), cam, 35, 8, w, h)
    im = toma(os.path.join(tmp, "sentado.png"), cam, eje, objetivo, 35, 8, dist, w, h, muestras)
    guardar(rr.sobre_fondo(im), os.path.join(outdir, "nojoch_sentado.png"))


def escala(outdir, muestras, tmp):
    todo, cam, eje = construir(con_escala=True)
    posar(todo["nojoch"], "Idle", 0.0, "olvido")
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


# (animación, segundos, giro, elevación, estado)
POSES = [("Slam", nj.SLAM_HIT + 0.05, -68, 8, "olvido"), ("Sweep", 0.5 * (nj.SWEEP_START + nj.SWEEP_END), 8, 34, "olvido"),
         ("Kneel", nj.KNEEL_T, 40, 6, "furia"), ("Remember", nj.REMEMBER_T, 52, 6, "liberado")]


def poses(outdir, muestras, tmp):
    from PIL import Image
    todo, cam, eje = construir()
    ficha = todo["nojoch"]
    w, h = px(960), px(540)
    lienzo = Image.new("RGBA", (2 * w, 2 * h), rr.FONDO)
    for i, (anim, t, giro, elev, estado) in enumerate(POSES):
        posar(ficha, anim, t, estado)
        objetivo, dist = encuadrar(nube([ficha]), cam, giro, elev, w, h)   # cada cuadro, a su encuadre
        im = toma(os.path.join(tmp, "pose_%d.png" % i), cam, eje, objetivo, giro, elev, dist, w, h, muestras)
        lienzo.alpha_composite(im, ((i % 2) * w, (i // 2) * h))
    guardar(lienzo.convert("RGB"), os.path.join(outdir, "nojoch_poses.png"))


# (rótulo, animación, segundos, giro, elevación, estado)
CUERPOS = [("Dormido", "Sleep", 0.0, 32, 8, "dormido"), ("Olvido", "Idle", 0.0, 24, 4, "olvido"),
           ("Furia", "Charge", 0.1, 46, 6, "furia"), ("Recuerdo", "Kneel", nj.KNEEL_T, 28, 6, "recuerdo"),
           ("Liberado", "Remember", nj.REMEMBER_T, 24, 6, "liberado")]
CARAS = [("Triste y confusa  ·  Face_Sad", "olvido"), ("Dolor contenido  ·  Face_Pain", "furia"),
         ("Serena  ·  Face_Serene", "liberado")]


def estados(outdir, muestras, tmp):
    """Hoja de expresiones y estados: arriba la cara en primer plano; abajo, el cuerpo entero."""
    from PIL import Image
    todo, cam, eje = construir()
    ficha = todo["nojoch"]
    ob = ficha[1]["Nojoch"]
    W, H = px(1920), px(1080)
    lienzo = Image.new("RGBA", (W, H), rr.FONDO)
    # caras: solo los vértices de la cabeza, sin la crestería, para el encuadre
    grupos = {g.index: g.name for g in ob.vertex_groups}
    de_cabeza = [i for i, v in enumerate(ob.data.vertices)
                 if grupos[max(v.groups, key=lambda g: g.weight).group] in ("Head", "Jaw", "Lids", "Brow_L", "Brow_R", "Mouth_L", "Mouth_R")
                 and v.co.z < nj.HZ + 1.02]
    w, h = W // 3, px(400)
    for i, (texto, estado) in enumerate(CARAS):
        posar(ficha, "Idle", 0.0, estado)
        dg = bpy.context.evaluated_depsgraph_get()
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        pts = [tuple(ev.matrix_world @ me.vertices[k].co) for k in de_cabeza]
        ev.to_mesh_clear()
        objetivo, dist = encuadrar(pts, cam, 8, 2, w, h, margen=0.04)
        im = toma(os.path.join(tmp, "cara_%d.png" % i), cam, eje, objetivo, 8, 2, dist, w, h, muestras)
        lienzo.alpha_composite(im, (i * w, px(46)))
        rotulo(lienzo, texto, (i * w + w // 2, px(10)))
    w2, h2 = W // 5, px(560)
    y2 = px(46) + h + px(52)
    for i, (texto, anim, t, giro, elev, estado) in enumerate(CUERPOS):
        posar(ficha, anim, t, estado)
        objetivo, dist = encuadrar(nube([ficha]), cam, giro, elev, w2, h2, margen=0.03)
        im = toma(os.path.join(tmp, "cuerpo_%d.png" % i), cam, eje, objetivo, giro, elev, dist, w2, h2, muestras)
        lienzo.alpha_composite(im, (i * w2, y2))
        rotulo(lienzo, texto, (i * w2 + w2 // 2, y2 - px(42)))
    guardar(lienzo.convert("RGB"), os.path.join(outdir, "nojoch_estados.png"))


def medidas():
    """Alturas y contactos, medidos sobre la malla deformada, y comprobaciones de las
    animaciones (para el README y para ajustar poses)."""
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
    print("Triángulos por material:", {m: sum(len(p.vertices) - 2 for p in ob.data.polygons if mats[p.material_index] == m) for m in mats})

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
                          ("Summon", nj.SUMMON_HIT + 0.05, ("Hand_L", "Fingers_L", "FingerTips_L"))):
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
    comprobar_animaciones()


def comprobar_animaciones():
    """Con la cinemática de build_nojoch (sin malla): pies que patinan, saltos de un
    cuadro al siguiente y el arco del barrido."""
    R = nj.RIG

    def puntos(p):
        out = {}
        for s, sx in (("L", 1), ("R", -1)):
            out["mano_" + s] = R.point(p, "Hand_" + s, nj.mx(nj.PALM_C, sx))
            out["pie_" + s] = R.point(p, "Foot_" + s, nj.CONTACT[s])
        out["cabeza"] = R.point(p, "Head", Vector((0, 0, 5.0)))
        return out

    print("Saltos (mayor cambio de velocidad de un cuadro al siguiente, en m/s; un golpe seco es normal en Slam y Summon):")
    for name, dur, fn in nj.ANIMS:
        n = round(dur * kc.FPS)
        fr = [puntos(fn(dur * f / n)) for f in range(n + 1)]
        peor = (0.0, "", 0.0)
        for k in fr[0]:
            for i in range(1, n):
                a = (fr[i + 1][k] - 2 * fr[i][k] + fr[i - 1][k]).length * kc.FPS
                if a > peor[0]:
                    peor = (a, k, i / kc.FPS)
        print("  %-9s %5.1f m/s (%s a %.2f s)" % (name, *peor))
    n = round(nj.WALK_T * kc.FPS)
    for s in ("L", "R"):
        ys = []
        for f in range(n):
            t = nj.WALK_T * f / n
            c = R.point(nj.walk(t), "Foot_" + s, nj.CONTACT[s])
            if c.z < 0.002:                         # apoyado: en el mundo no debe moverse
                u = (t / nj.WALK_T + (0.0 if s == "L" else 0.5)) % 1.0
                ys.append(c.y - nj.WALK_SPEED * u * nj.WALK_T)
        print("Walk a %.1f m/s, pie %s: apoyado %d de %d cuadros; se desliza %.1f mm" % (
            nj.WALK_SPEED, s, len(ys), n, 1000 * (max(ys) - min(ys))))
    az = []
    for t in (nj.SWEEP_START, nj.SWEEP_END):
        p = nj.sweep(t)
        c = R.point(p, "FingerTips_R", Vector((-nj.AX, 0, nj.TIP_Z[0])))
        az.append(math.degrees(math.atan2(c.x, -c.y)))
        print("Sweep a %.2f s: la punta de la mano a %.0f° (0 = al frente, + = a su izquierda), a %.2f m del eje y %.2f m de alto" % (
            t, az[-1], math.hypot(c.x, c.y), c.z))
    print("Sweep: barre %.0f° en %.2f s" % (az[1] - az[0], nj.SWEEP_END - nj.SWEEP_START))


def hoja_godot(capturas, outdir, celda=480, columnas=4):
    """Hoja de contacto con las capturas de art/godot/render_nojoch.gd (n01…)."""
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
    todo, cam, eje = construir()
    if extra == "caras":
        pintar_caras_traseras()
    posar(todo["nojoch"], anim, t, extra if extra in ESTADOS else None)
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
    pasos = {"referencias": referencias, "sentado": sentado, "escala": escala, "poses": poses, "estados": estados}
    if que != "todo" and que not in pasos:
        sys.exit("no sé hacer «%s» (todo, %s, medidas, godot o toma)" % (que, ", ".join(pasos)))
    os.makedirs(outdir, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="nojoch_") as tmp:
        for nombre, paso in pasos.items():
            if que in ("todo", nombre):
                paso(outdir, muestras, tmp)


if __name__ == "__main__":
    main()
