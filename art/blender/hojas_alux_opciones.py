"""Hojas de opciones del personalizador del alux, dibujadas con el renderer de Godot.

Uso (desde la raíz del repo; no usa Blender, solo Pillow, Godot y xvfb):
    .tools/blender-venv/bin/python art/blender/hojas_alux_opciones.py [opciones]

Deja en art/propuestas/alux_personalizacion/:
    opciones.png        todo junto: el alux de fábrica y cada opción de cada familia
    tocados.png, vestimenta.png, accesorios.png, amuletos.png   cada familia, más grande
    combinaciones.png   cuatro conjuntos completos con otros colores y tonos de piel
    cruces.png          cada vestimenta con cada accesorio (y un amuleto), de cerca
    movimiento.png      carrera, salto y otras poses con capa, morral, farol, faja…

Cada vista la dibuja art/godot/render_alux_opciones.gd, que enciende las mallas por
nombre y tiñe los materiales igual que el juego, con su misma luz.

Opciones:
    --glb RUTA        otro .glb (por omisión, game/assets/characters/alux.glb)
    --salida CARPETA  otra carpeta de salida
    --solo A,B        solo esas hojas (tocados, vestimenta, accesorios, amuletos,
                      combinaciones, cruces, movimiento, defecto); no rehace opciones.png
    --res N           lado de cada captura en píxeles (por omisión 480)
    --sueltas CARPETA guarda además las capturas sueltas, sin reducir
    --de CARPETA      no captura: monta las hojas con las capturas sueltas de esa carpeta
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
GODOT = os.path.join(REPO, ".tools", "godot")
GUION = os.path.join(REPO, "art", "godot", "render_alux_opciones.gd")

TOCADOS = ["Hat_Palma", "Hat_Penacho", "Hat_Flor", "sin tocado", "Hat_Plumas", "Hat_Panuelo", "Hat_Hojas"]
VESTIMENTA = ["túnica", "Outfit_Capa", "Outfit_Faja", "Outfit_Bordado"]
ACCESORIOS = ["ninguno", "Acc_Morral", "Acc_Sonaja", "Acc_Caracol", "Acc_Farol"]
AMULETOS = ["ninguno", "Amu_Jade", "Amu_Concha", "Amu_Obsidiana", "Amu_Semillas"]

CUERPO = dict(dist=2.75, target=[0, 0.74, 0], pitch=6)
CABEZA = dict(dist=1.85, target=[0, 1.13, 0], pitch=5)
PECHO = dict(dist=1.35, target=[0, 0.80, 0], pitch=2)
CINTO = dict(dist=2.1, target=[0, 0.60, 0], pitch=10)

# conjuntos completos: tocado, vestimenta, accesorio, amuleto, principal, secundario, piel
CONJUNTOS = [
    ("plumas · capa · morral · concha", dict(hat=4, outfit=1, acc=1, amu=2, color="#e4007c", accent="#ffd23f", skin="#8c563a")),
    ("pañuelo · faja · farol · semillas", dict(hat=5, outfit=2, acc=4, amu=4, color="#31466b", accent="#ff7a1a", skin="#c08a62")),
    ("hojas · bordado · caracol · obsidiana", dict(hat=6, outfit=3, acc=3, amu=3, color="#fff7ec", accent="#19b4d6", skin="#6f4530")),
    ("penacho · capa · sonaja · jade", dict(hat=1, outfit=1, acc=2, amu=1, color="#7ccf4e", accent="#b3372e", skin="#d6a57e")),
]


def tomas():
    """{hoja: (columnas, [(rótulo, toma)])}; cada toma es un diccionario para el guion de Godot."""
    h = {}
    viejo = dict(acc=1, amu=1)
    h["defecto"] = (6, [
        ("de fábrica · frente", dict(yaw=0, **CUERPO)), ("de fábrica · tres cuartos", dict(yaw=40, **CUERPO)),
        ("de fábrica · espalda", dict(yaw=180, **CUERPO)),
        ("morral + jade (como hasta ahora)", dict(yaw=0, **viejo, **CUERPO)),
        ("morral + jade · tres cuartos", dict(yaw=40, **viejo, **CUERPO)),
        ("morral + jade · espalda", dict(yaw=215, **viejo, **CUERPO))])
    filas = []
    for i, nombre in enumerate(TOCADOS):
        for vista, yaw in (("frente", 0), ("tres cuartos", 40), ("por detrás", 155)):
            filas.append(("%d %s · %s" % (i, nombre, vista), dict(hat=i, yaw=yaw, **CABEZA)))
    h["tocados"] = (6, filas)
    filas = []
    for i, nombre in enumerate(VESTIMENTA):
        for vista, yaw, extra in (("frente", 0, {}), ("tres cuartos", 40, {}), ("espalda", 180, {}),
                                  ("secundario magenta", 320, dict(accent="#e4007c"))):
            filas.append(("%d %s · %s" % (i, nombre, vista), dict(outfit=i, yaw=yaw, **extra, **CUERPO)))
    h["vestimenta"] = (4, filas)
    filas = []
    for i, nombre in enumerate(ACCESORIOS):
        for vista, yaw in (("frente", 0), ("lado derecho", 270), ("atrás a la derecha", 222), ("espalda", 180)):
            filas.append(("%d %s · %s" % (i, nombre, vista), dict(acc=i, yaw=yaw, **CINTO)))
    h["accesorios"] = (4, filas)
    filas = []
    for i, nombre in enumerate(AMULETOS):
        for vista, yaw in (("frente", 0), ("tres cuartos", 38)):
            filas.append(("%d %s · %s" % (i, nombre, vista), dict(amu=i, hat=3, yaw=yaw, **PECHO)))
    h["amuletos"] = (4, filas)
    filas = []
    for nombre, look in CONJUNTOS:
        for vista, yaw in (("frente", 0), ("tres cuartos", 40), ("atrás a la derecha", 215)):
            filas.append(("%s · %s" % (nombre, vista), dict(yaw=yaw, **look, **CUERPO)))
    h["combinaciones"] = (3, filas)
    # cada vestimenta con cada accesorio, de cerca, para buscar piezas que se crucen
    filas = []
    for o in (1, 2, 3):
        for ac in (1, 2, 3, 4):
            look = dict(outfit=o, acc=ac, amu=(o + ac) % 4 + 1, hat=3, accent="#ffd23f" if o != 3 else "#19b4d6")
            rot = "%s + %s" % (VESTIMENTA[o].split("_")[1].lower(), ACCESORIOS[ac].split("_")[1].lower())
            filas.append((rot + " · delante", dict(yaw=325, dist=2.0, target=[0, 0.64, 0], pitch=8, **look)))
            filas.append((rot + " · atrás a la derecha", dict(yaw=215, dist=2.0, target=[0, 0.64, 0], pitch=12, **look)))
    h["cruces"] = (4, filas)
    capa_morral = dict(hat=0, outfit=1, acc=1, amu=1, accent="#ffd23f")
    capa_farol = dict(hat=4, outfit=1, acc=4, amu=2, color="#e4007c", accent="#fff7ec")
    faja_sonaja = dict(hat=5, outfit=2, acc=2, amu=4, color="#31466b", accent="#ff7a1a")
    bordado_caracol = dict(hat=6, outfit=3, acc=3, amu=3, color="#fff7ec", accent="#19b4d6")
    mov = dict(dist=3.0, target=[0, 0.74, 0], pitch=8)
    alto = dict(dist=3.2, target=[0, 0.86, 0], pitch=8)
    h["movimiento"] = (4, [
        ("Run 0.07 s · capa + morral · lado", dict(anim="Run", t=0.0667, yaw=90, **capa_morral, **mov)),
        ("Run 0.07 s · capa + morral · atrás", dict(anim="Run", t=0.0667, yaw=215, **capa_morral, **mov)),
        ("Run 0.23 s · capa + morral · frente", dict(anim="Run", t=0.2333, yaw=25, **capa_morral, **mov)),
        ("Run 0.23 s · capa + morral · lado der.", dict(anim="Run", t=0.2333, yaw=270, **capa_morral, **mov)),
        ("Run 0.07 s · capa + farol · lado der.", dict(anim="Run", t=0.0667, yaw=270, **capa_farol, **mov)),
        ("Run 0.07 s · capa + farol · atrás", dict(anim="Run", t=0.0667, yaw=205, **capa_farol, **mov)),
        ("Run 0.23 s · capa + farol · frente", dict(anim="Run", t=0.2333, yaw=335, **capa_farol, **mov)),
        ("Run 0.23 s · capa + farol · espalda", dict(anim="Run", t=0.2333, yaw=180, **capa_farol, **mov)),
        ("Jump 0.25 s · capa + morral · frente", dict(anim="Jump", t=0.25, yaw=25, **capa_morral, **alto)),
        ("Jump 0.25 s · capa + morral · atrás", dict(anim="Jump", t=0.25, yaw=215, **capa_morral, **alto)),
        ("Jump 0.40 s · capa + farol · lado der.", dict(anim="Jump", t=0.40, yaw=270, **capa_farol, **alto)),
        ("Jump 0.40 s · capa + farol · espalda", dict(anim="Jump", t=0.40, yaw=180, **capa_farol, **alto)),
        ("Run 0.07 s · faja + sonaja · atrás", dict(anim="Run", t=0.0667, yaw=215, **faja_sonaja, **mov)),
        ("Run 0.23 s · faja + sonaja · frente", dict(anim="Run", t=0.2333, yaw=20, **faja_sonaja, **mov)),
        ("Run 0.07 s · bordado + caracol · atrás", dict(anim="Run", t=0.0667, yaw=200, **bordado_caracol, **mov)),
        ("Run 0.23 s · bordado + caracol · frente", dict(anim="Run", t=0.2333, yaw=340, **bordado_caracol, **mov)),
        ("Fall 0.3 s · capa + morral", dict(anim="Fall", t=0.3, yaw=30, **capa_morral, **alto)),
        ("Cast 0.10 s · capa + farol", dict(anim="Cast", t=0.10, yaw=50, **capa_farol, **mov)),
        ("Land 0.07 s · faja + sonaja", dict(anim="Land", t=0.067, yaw=215, **faja_sonaja, **mov)),
        ("Idle 1.5 s · bordado + caracol", dict(anim="Idle", t=1.5, yaw=150, **bordado_caracol, **mov)),
    ])
    return h


def capturar(glb, lista, carpeta, res):
    """Dibuja todas las tomas con Godot (2 hilos) en `carpeta`."""
    tmp = tempfile.mkdtemp(prefix="alux_opciones_")
    try:
        proyecto = os.path.join(tmp, "proyecto")
        os.makedirs(proyecto)
        open(os.path.join(proyecto, "project.godot"), "w").close()
        guion = os.path.join(tmp, "tomas.json")
        with open(guion, "w") as fh:
            json.dump(lista, fh)
        cmd = ["xvfb-run", "-a", GODOT, "--path", proyecto, "--rendering-driver", "opengl3",
               "--resolution", "%dx%d" % (res, res), "--script", GUION, "--", carpeta, glb, guion]
        r = subprocess.run(cmd, env=dict(os.environ, LP_NUM_THREADS="2"), stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, text=True)
        for linea in r.stdout.splitlines():
            if ("ERROR" in linea or "WARNING" in linea) and "alsa" not in linea.lower() and "audio" not in linea \
                    and "status < 0" not in linea and "V-Sync" not in linea:
                print(" ", linea)
        if r.returncode != 0:
            sys.exit("Godot falló:\n" + r.stdout[-2000:])
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def fuente(tam):
    from PIL import ImageFont
    for ruta in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
                 "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"):
        if os.path.exists(ruta):
            return ImageFont.truetype(ruta, tam)
    return ImageFont.load_default()      # sin tildes, pero no falla


def montar(carpeta, nombre, cols, filas, destino, celda, titulo=""):
    from PIL import Image, ImageDraw
    pie = 22 if celda >= 300 else 16
    cab = 34 if titulo else 0
    celdas = []                          # None en `filas` = la siguiente empieza fila nueva
    for f in filas:
        if f is None:
            celdas += [None] * (-len(celdas) % cols)
        else:
            celdas.append(f)
    alto = (len(celdas) + cols - 1) // cols
    hoja = Image.new("RGB", (cols * celda, cab + alto * (celda + pie)), "#1d2420")
    d = ImageDraw.Draw(hoja)
    if titulo:
        d.text((10, 7), titulo, fill="#ffe9a8", font=fuente(18))
    f = fuente(13 if celda >= 300 else 10)
    for i, celda_ in enumerate(celdas):
        if celda_ is None:
            continue
        rotulo, toma = celda_
        im = Image.open(os.path.join(carpeta, toma["n"] + ".png")).convert("RGB")
        if im.width != celda:
            im = im.resize((celda, celda), Image.LANCZOS)
        x, y = (i % cols) * celda, cab + (i // cols) * (celda + pie)
        hoja.paste(im, (x, y))
        d.text((x + 6, y + celda + 3), rotulo, fill="#f1efe6", font=f)
    path = os.path.join(destino, nombre + ".png")
    # PNG de paleta (255 colores, con tramado): un tercio del peso, sin diferencia a la vista
    hoja.quantize(colors=255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG).save(path, optimize=True)
    return path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", default=os.path.join(REPO, "game", "assets", "characters", "alux.glb"))
    ap.add_argument("--salida", default=os.path.join(REPO, "art", "propuestas", "alux_personalizacion"))
    ap.add_argument("--solo", default="")
    ap.add_argument("--res", type=int, default=480)
    ap.add_argument("--sueltas", default="")
    ap.add_argument("--de", default="")
    a = ap.parse_args()
    hojas = tomas()
    solo = [s for s in a.solo.split(",") if s]
    if solo:
        hojas = {k: v for k, v in hojas.items() if k in solo}
    lista = []
    for hoja, (_cols, filas) in hojas.items():
        for i, (_rotulo, toma) in enumerate(filas):
            toma["n"] = "%s_%02d" % (hoja, i + 1)
            lista.append(toma)
    os.makedirs(a.salida, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix="alux_capturas_")
    try:
        if a.de:
            carpeta = os.path.abspath(a.de)
        else:
            carpeta = os.path.abspath(a.sueltas) if a.sueltas else tmp
            capturar(os.path.abspath(a.glb), lista, carpeta, a.res)
        for hoja, (cols, filas) in hojas.items():
            if hoja == "defecto":
                continue
            print("hoja", montar(carpeta, hoja, cols, filas, a.salida, 400 if hoja != "movimiento" else 360))
        if not solo:
            # la hoja general: de fábrica y una fila por familia, con las vistas que más enseñan
            orden = ["defecto", "tocados", "vestimenta", "accesorios", "amuletos"]
            quitar = {"tocados": "por detrás", "vestimenta": "secundario magenta", "accesorios": "lado derecho"}
            todo = []
            for hoja in orden:
                todo += [f for f in hojas[hoja][1] if quitar.get(hoja, "\0") not in f[0]] + [None]
            print("hoja", montar(carpeta, "opciones", 6, todo, a.salida, 256,
                                 "ALUX · piezas del personalizador (capturas de Godot, luz del juego)"))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
