"""Hojas de personaje (turnaround) para las cinemáticas: referencias visuales con las
que mantener la continuidad de los personajes al generar vídeo (Kling u otra herramienta).

Uso (desde la raíz del repo):
    .tools/blender-venv/bin/python art/blender/render_referencias.py [personaje] [carpeta] [res] [muestras]

`personaje` es alux, balam, yaxche o todos (por omisión, todos). Deja en art/referencias/:
    <personaje>_frente.png, _tres_cuartos.png, _lado.png, _espalda.png
        cuerpo entero en el primer cuadro de «Idle», 1024×1024, con el mismo encuadre
        en las cuatro vistas (la cámara gira alrededor del personaje, a la altura del
        pecho y horizontal; las luces giran con ella, así que todas se iluminan igual);
    <personaje>_hoja.png
        hoja apaisada 1920×1080 con las cuatro vistas en fila, a la misma escala;
    balam_accion.png
        Balam en el vuelo del galope («Run»), con el encuadre de sus otras vistas.

Fondo gris claro uniforme, sin suelo (solo una sombra de contacto suave) y sin ningún
texto dentro de la imagen: los generadores de vídeo copian los rótulos que ven.

Los modelos, los materiales, las luces y la cámara son los de `render_previews.py`
(Cycles en CPU, 2 hilos, con la luz de los retratos); aquí cambian el encuadre y el
fondo, y se retocan en memoria dos defectos de los modelos que de cerca se notarían
(ver «Retoques»). Necesita Pillow. La ficha de cada personaje está en
art/referencias/README.md.
"""
import math
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import alux_common as kc  # noqa: E402  (importa bpy antes que mathutils)
import bpy  # noqa: E402
from render_previews import REPO, show_hats  # noqa: E402

FONDO = "#d2d2d2"                # gris claro neutro
MARGEN = 0.07                    # aire alrededor del personaje, en fracción del cuadro
SOMBRA_RADIO = 0.45              # alcance de la sombra de contacto (m)
SOMBRA_FUERZA = 0.55             # opacidad de la sombra donde el suelo queda tapado del todo
HOJA = (1920, 1080)

# (nombre, giro de la cámara): 0 = de frente, 90 = a la izquierda del personaje, 180 = por detrás
VISTAS = [("frente", 0), ("tres_cuartos", 40), ("lado", 90), ("espalda", 180)]

# tocado: mallas del alux que se dejan visibles (las que usa el juego con el sombrero 0);
# pecho: altura de la cámara (m); accion: (animación, segundos, giro) de la vista en movimiento
PERSONAJES = {
    "alux": dict(tocado="Hair+Hat_Palma", pecho=0.75, accion=None),
    "balam": dict(tocado=None, pecho=0.62, accion=("Run", 0.1333, 60)),
    "yaxche": dict(tocado=None, pecho=0.68, accion=None),
}


# ──────────────────────── Retoques solo para estas imágenes ────────────────────────
# Dos defectos de los modelos se notan con la cámara baja y de cerca de estas hojas, y
# un generador de vídeo los copiaría como si fueran parte del diseño. Se corrigen aquí,
# en memoria: ni los scripts de construcción ni los .glb cambian. (Las caras se pintan
# por los dos lados, como en `render_previews.py`; en el juego son de una sola cara.)

def cenefas_enteras():
    """Los hilos finos que dan la vuelta entera a una prenda (ruedo y jubón del alux,
    canesú y ruedo de la abuela, anillos de la cola de Balam) se pintan con un polígono
    de cuatro vértices, los cuatro sobre la costura. Si sus bordes no coinciden con una
    fila de la malla, la triangulación los deja sin área y en el .glb queda una ranura
    por la que se ve el interior de la prenda. Con vértices intermedios en los bordes
    largos, el hilo sale como está descrito en el script de construcción."""
    original = kc.MeshBuilder.add_loft_painted
    if getattr(original, "cenefas_enteras", False):
        return
    tau = 2.0 * math.pi

    def add_loft_painted(self, loft, mat, shapes, segs=12, **kw):
        nuevas = []
        for poly, key in shapes:
            us, ts = sorted(set(u for u, _t in poly)), [t for _u, t in poly]
            t0, t1 = min(ts), max(ts)
            if len(poly) == 4 and len(us) == 2 and abs(t1 - t0 - tau) < 1e-6:
                vuelta = [t0 + (t1 - t0) * j / segs for j in range(segs)] + [t1]
                poly = [(us[0], t) for t in vuelta] + [(us[1], t) for t in reversed(vuelta)]
            nuevas.append((poly, key))
        return original(self, loft, mat, nuevas, segs=segs, **kw)

    add_loft_painted.cenefas_enteras = True
    kc.MeshBuilder.add_loft_painted = add_loft_painted


def cabello_bajo_el_tocado(objs, centro, holgura=0.012):
    """El cabello del alux asoma por la cinta del sombrero de palma (el sombrero va
    ladeado). Los vértices del cabello que quedarían fuera del tocado, o rozándolo, se
    meten debajo, sin hundirlos en la cabeza mientras haya sitio."""
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree

    def arbol(ob):
        me = ob.data
        return BVHTree.FromPolygons([v.co.copy() for v in me.vertices], [tuple(p.vertices) for p in me.polygons])

    pelo = objs.get("Hair")
    if pelo is None or pelo.hide_render:
        return
    c = Vector(centro)
    cabeza = arbol(next(iter(objs.values())))            # la primera malla es el cuerpo
    for nombre, ob in objs.items():
        if not nombre.startswith("Hat_") or ob.hide_render:
            continue
        tocado = arbol(ob)
        for v in pelo.data.vertices:
            d = v.co - c
            largo = d.length
            choque = tocado.ray_cast(c, d / largo)
            if choque[0] is None:
                continue
            tope = choque[3] - holgura
            piel = cabeza.ray_cast(c, d / largo)
            if piel[0] is not None:
                tope = max(tope, piel[3] + 0.004)
            if largo > tope:
                v.co = c + d * (tope / largo)


# ───────────────────────────────── Escena ─────────────────────────────────

def preparar_escena():
    """Luz plana y neutra (como la de los retratos) y, en vez de suelo, un plano invisible que
    solo pinta la sombra de contacto. Devuelve la cámara y el eje con el que giran las luces."""
    cam = kc.setup_preview(ground=False, sky="#ffffff", ambient=0.85, key=1.5)
    preview = bpy.data.collections["Preview"]
    eje = bpy.data.objects.new("EjeLuces", None)
    preview.objects.link(eje)
    for nombre in ("Key", "Fill"):
        bpy.data.objects[nombre].parent = eje
    # Sombra de contacto: el plano es transparente salvo donde el personaje le tapa el
    # cielo (oclusión ambiental), y ahí es negro con esa opacidad. No depende de las
    # luces, así que es la misma mancha suave bajo los pies en todas las vistas.
    mat = bpy.data.materials.new("PreviewSombra")
    if mat.node_tree is None:
        mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.samples = 16
    ao.inputs["Distance"].default_value = SOMBRA_RADIO
    tapado = nt.nodes.new("ShaderNodeMath")
    tapado.operation = "SUBTRACT"
    tapado.inputs[0].default_value = 1.0
    opacidad = nt.nodes.new("ShaderNodeMath")
    opacidad.operation = "MULTIPLY"
    opacidad.use_clamp = True
    opacidad.inputs[1].default_value = SOMBRA_FUERZA
    claro = nt.nodes.new("ShaderNodeBsdfTransparent")
    negro = nt.nodes.new("ShaderNodeEmission")
    negro.inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)
    negro.inputs["Strength"].default_value = 0.0
    mezcla = nt.nodes.new("ShaderNodeMixShader")
    salida = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(ao.outputs["AO"], tapado.inputs[1])
    nt.links.new(tapado.outputs[0], opacidad.inputs[0])
    nt.links.new(opacidad.outputs[0], mezcla.inputs[0])
    nt.links.new(claro.outputs[0], mezcla.inputs[1])
    nt.links.new(negro.outputs[0], mezcla.inputs[2])
    nt.links.new(mezcla.outputs[0], salida.inputs["Surface"])
    gm = bpy.data.meshes.new("PreviewSombra")
    s = 30.0
    gm.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
    gm.materials.append(mat)
    suelo = bpy.data.objects.new("PreviewSombra", gm)
    suelo.visible_diffuse = suelo.visible_glossy = suelo.visible_shadow = False   # solo lo ve la cámara
    preview.objects.link(suelo)
    return cam, eje


def puntos(objs):
    """Vértices, ya deformados por el esqueleto, de las mallas que se van a ver."""
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for ob in objs.values():
        if ob.hide_render:
            continue
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        pts += [tuple(ev.matrix_world @ v.co) for v in me.vertices]
        ev.to_mesh_clear()
    return pts


def encuadre(tomas, cam, pecho):
    """Un solo encuadre para todas las tomas: [(puntos, giro), ...] → (objetivo, distancia).
    La cámara queda a la altura del pecho, horizontal; el cuadro se centra en el cuerpo
    desplazando la lente (shift), no inclinando la cámara, así no hay fuga de verticales."""
    base = tomas[0][0]
    ys = [p[1] for p in base]
    cy = 0.5 * (min(ys) + max(ys))              # eje de giro: plano de simetría, centro del largo
    t = 0.5 * cam.data.sensor_width / cam.data.lens

    def medir(dist):
        lat, lo, hi = 0.0, 1e9, -1e9
        for pts, giro in tomas:
            a = math.radians(giro)
            sa, ca = math.sin(a), math.cos(a)
            for x, y, z in pts:
                y -= cy
                d = dist - (x * sa - y * ca)     # profundidad desde la cámara
                if d <= 0.05:
                    return None
                lat = max(lat, abs(x * ca + y * sa) / d)
                v = (z - pecho) / d
                lo, hi = min(lo, v), max(hi, v)
        return lat, lo, hi

    def cabe(dist):
        m = medir(dist)
        return m is not None and max(m[0], 0.5 * (m[2] - m[1])) <= t * (1.0 - 2.0 * MARGEN)

    a, b = 0.5, 40.0
    for _ in range(40):
        c = 0.5 * (a + b)
        a, b = (a, c) if cabe(c) else (c, b)
    _lat, lo, hi = medir(b)
    cam.data.shift_x = 0.0
    cam.data.shift_y = 0.5 * (lo + hi) / (2.0 * t)
    return (0.0, cy, pecho), b


# ───────────────────────────────── Imágenes ─────────────────────────────────

def sobre_fondo(im, size=None):
    """Compone una imagen RGBA sobre el fondo neutro y la devuelve en RGB."""
    from PIL import Image
    lienzo = Image.new("RGBA", size or im.size, FONDO)
    lienzo.alpha_composite(im, ((lienzo.width - im.width) // 2, (lienzo.height - im.height) // 2))
    return lienzo.convert("RGB")


def hoja(vistas, path):
    """Las vistas (RGBA, mismo encuadre) en fila sobre el fondo neutro, todas a la misma
    escala y con el suelo a la misma altura. Sin textos."""
    from PIL import Image
    cajas = [im.getchannel("A").point(lambda v: 255 if v > 96 else 0).getbbox() for im in vistas]
    top, bot = min(c[1] for c in cajas), max(c[3] for c in cajas)
    anchos = [c[2] - c[0] for c in cajas]
    w, h = HOJA
    hueco = 0.035 * w
    k = min((w - hueco * (len(vistas) + 1)) / sum(anchos), 0.86 * h / (bot - top))
    hueco = (w - k * sum(anchos)) / (len(vistas) + 1)
    lienzo = Image.new("RGBA", HOJA, FONDO)
    x = hueco
    y0 = 0.5 * (h - k * (bot - top)) - k * top
    for im, caja, ancho in zip(vistas, cajas, anchos):
        esc = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
        capa = Image.new("RGBA", HOJA, (0, 0, 0, 0))
        capa.paste(esc, (round(x - k * caja[0]), round(y0)))
        lienzo.alpha_composite(capa)
        x += k * ancho + hueco
    lienzo.convert("RGB").save(path, optimize=True)


# ───────────────────────────────── Render ─────────────────────────────────

def referencias(quien, outdir, res, muestras):
    from PIL import Image
    cfg = PERSONAJES[quien]
    cenefas_enteras()
    mod = __import__("build_" + quien)
    arm, objs = mod.build()
    cam, eje = preparar_escena()
    show_hats(objs, cfg["tocado"])
    if hasattr(mod, "HC"):
        cabello_bajo_el_tocado(objs, mod.HC)
    duracion = dict((a[0], a[1]) for a in mod.ANIMS)

    def posar(anim, t):
        cuadros = max(1, round(duracion[anim] * kc.FPS))
        kc.set_action(arm, anim, round(t / duracion[anim] * cuadros))

    # (nombre, animación, segundos, giro): reposo = primer cuadro de «Idle»
    tomas = [(nombre, "Idle", 0.0, giro) for nombre, giro in VISTAS]
    if cfg["accion"] and cfg["accion"][0] in duracion:
        tomas.append(("accion",) + tuple(cfg["accion"]))
    nubes = {}
    for _nombre, anim, t, _giro in tomas:
        if (anim, t) not in nubes:
            posar(anim, t)
            nubes[(anim, t)] = puntos(objs)
    objetivo, dist = encuadre([(nubes[(anim, t)], giro) for _n, anim, t, giro in tomas], cam, cfg["pecho"])
    alto = max(p[2] for p in nubes[("Idle", 0.0)])
    print("%s: altura %.3f m, cámara a %.2f m de altura y %.2f m de distancia" % (quien, alto, cfg["pecho"], dist))

    tmp = tempfile.mkdtemp(prefix="referencias_")
    try:
        capas = {}
        for nombre, anim, t, giro in tomas:
            posar(anim, t)
            eje.rotation_euler = (0.0, 0.0, math.radians(giro))
            crudo = os.path.join(tmp, nombre + ".png")
            kc.render(crudo, cam, objetivo, giro, 0.0, dist, res=res, samples=muestras, transparent=True)
            capas[nombre] = Image.open(crudo).convert("RGBA")
            path = os.path.join(outdir, "%s_%s.png" % (quien, nombre))
            sobre_fondo(capas[nombre]).save(path, optimize=True)
            print("render", path, os.path.getsize(path), "bytes")
        path = os.path.join(outdir, quien + "_hoja.png")
        hoja([capas[nombre] for nombre, _giro in VISTAS], path)
        print("hoja", path, os.path.getsize(path), "bytes")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    quien = sys.argv[1] if len(sys.argv) > 1 else "todos"
    outdir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(REPO, "art", "referencias")
    res = int(sys.argv[3]) if len(sys.argv) > 3 else 1024
    muestras = int(sys.argv[4]) if len(sys.argv) > 4 else 32
    if quien != "todos" and quien not in PERSONAJES:
        sys.exit("personaje desconocido: %s (alux, balam, yaxche o todos)" % quien)
    os.makedirs(outdir, exist_ok=True)
    for nombre in PERSONAJES:
        if quien in ("todos", nombre):
            referencias(nombre, outdir, res, muestras)


if __name__ == "__main__":
    main()
