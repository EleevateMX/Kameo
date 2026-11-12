"""Vídeos de las animaciones de Nojoch Tuunich, hechos con el renderer de Godot.

Uso (desde la raíz del repo; no usa Blender, solo Pillow, Godot, xvfb y ffmpeg):
    .tools/blender-venv/bin/python art/blender/videos_nojoch.py [opciones]

Deja en art/propuestas/nojoch/:
    animaciones/<Anim>.mp4      una por animación (640×360, 15 cuadros/s, H.264, sin audio)
    nojoch_animaciones.mp4      el carrete con todas seguidas, en el orden de ORDEN

Cada cuadro lo dibuja art/godot/render_nojoch.gd (modo=anim) con la luz del juego, el
nombre de la animación sobreimpreso, el estado en que el juego la usa (dormido, olvido,
furia o liberado, con su expresión) y un suelo de losas de 2 m. «Walk» y «Charge» se
desplazan a la velocidad real del juego (1.7 y 12 m/s) con la cámara siguiéndolas: si
los pies patinan, se ve contra las losas. Los ciclos cortos se repiten varias veces.

Opciones:
    --glb RUTA        otro .glb (por omisión, el de art/propuestas/nojoch/)
    --salida CARPETA  otra carpeta de salida
    --solo A,B        solo esas animaciones (no rehace el carrete)
    --hojas CARPETA   además, hojas de cuadros consecutivos (<Anim>_1.png …) para revisarlas
    --paso N          en las hojas, un cuadro de cada N (por omisión 1: todos)
    --giro G          fuerza el giro de la cámara (para mirar desde otro lado)
    --estado E        un mismo estado de materiales para todas (por omisión, cada animación
                      lleva el estado en que el juego la usa; ver CAMARAS en render_nojoch.gd)
    --sin-videos      solo cuadros y hojas
"""
import argparse
import glob
import os
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
GODOT = os.path.join(REPO, ".tools", "godot")
GUION = os.path.join(REPO, "art", "godot", "render_nojoch.gd")
ORDEN = ["Sleep", "Awaken", "Idle", "Walk", "Slam", "Sweep", "Summon", "Charge", "Stunned", "Kneel", "Remember"]
FPS = 15
RES = (640, 360)


def cuadros(glb, tmp, solo, giro, estado):
    """Dibuja todos los cuadros con Godot (2 hilos) y devuelve la carpeta."""
    proyecto = os.path.join(tmp, "proyecto")
    os.makedirs(proyecto, exist_ok=True)
    open(os.path.join(proyecto, "project.godot"), "w").close()
    salida = os.path.join(tmp, "cuadros")
    cmd = ["xvfb-run", "-a", GODOT, "--path", proyecto, "--rendering-driver", "opengl3",
           "--resolution", "%dx%d" % RES, "--script", GUION, "--", salida, glb, "modo=anim", "fps=%d" % FPS]
    if estado:
        cmd.append("estado=" + estado)
    if solo:
        cmd.append("anims=" + ",".join(solo))
    if giro is not None:
        cmd.append("giro=%s" % giro)
    env = dict(os.environ, LP_NUM_THREADS="2")
    r = subprocess.run(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    for linea in r.stdout.splitlines():
        if linea.startswith("anim ") or "ERROR" in linea and "alsa" not in linea.lower() and "status < 0" not in linea:
            print(" ", linea)
    if r.returncode != 0:
        sys.exit("Godot falló:\n" + r.stdout[-2000:])
    return salida


def hojas(carpeta, anim, destino, paso=1, cols=6, por_hoja=24, celda=(320, 240), recorte=(480, 360)):
    from PIL import Image, ImageDraw
    files = sorted(glob.glob(os.path.join(carpeta, anim, "f*.png")))[::paso]
    os.makedirs(destino, exist_ok=True)
    out = []
    for k in range(0, len(files), por_hoja):
        grupo = files[k:k + por_hoja]
        filas = (len(grupo) + cols - 1) // cols
        lienzo = Image.new("RGB", (cols * celda[0], filas * celda[1]), "#202020")
        for i, f in enumerate(grupo):
            im = Image.open(f).convert("RGB")
            x0, y0 = (im.width - recorte[0]) // 2, (im.height - recorte[1]) // 2
            im = im.crop((x0, y0, x0 + recorte[0], y0 + recorte[1])).resize(celda, Image.LANCZOS)
            n = int(os.path.basename(f)[1:5])
            ImageDraw.Draw(im).text((celda[0] - 78, celda[1] - 14), "%d · %.2f s" % (n, (n - 1) / FPS), fill="#ffff66")
            lienzo.paste(im, ((i % cols) * celda[0], (i // cols) * celda[1]))
        path = os.path.join(destino, "%s_%d.png" % (anim, k // por_hoja + 1))
        lienzo.save(path)
        out.append(path)
    return out


def video(carpeta, anim, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-threads", "2", "-framerate", str(FPS), "-i",
           os.path.join(carpeta, anim, "f%04d.png"), "-c:v", "libx264", "-preset", "medium", "-crf", "21",
           "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-an", path]
    subprocess.run(cmd, check=True)
    print("vídeo", path, os.path.getsize(path), "bytes")


def carrete(videos, path, tmp):
    lista = os.path.join(tmp, "lista.txt")
    with open(lista, "w") as fh:
        for v in videos:
            fh.write("file '%s'\n" % v)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lista, "-c", "copy",
                    "-movflags", "+faststart", "-an", path], check=True)
    print("carrete", path, os.path.getsize(path), "bytes")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", default=os.path.join(REPO, "art", "propuestas", "nojoch", "nojoch.glb"))
    ap.add_argument("--salida", default=os.path.join(REPO, "art", "propuestas", "nojoch"))
    ap.add_argument("--solo", default="")
    ap.add_argument("--hojas", default="")
    ap.add_argument("--paso", type=int, default=1)
    ap.add_argument("--giro", default=None)
    ap.add_argument("--estado", default="")
    ap.add_argument("--sin-videos", action="store_true")
    a = ap.parse_args()
    solo = [s for s in a.solo.split(",") if s]
    tmp = tempfile.mkdtemp(prefix="nojoch_videos_")
    try:
        carpeta = cuadros(os.path.abspath(a.glb), tmp, solo, a.giro, a.estado)
        anims = [n for n in ORDEN if os.path.isdir(os.path.join(carpeta, n))]
        if a.hojas:
            for n in anims:
                for h in hojas(carpeta, n, a.hojas, a.paso):
                    print("hoja", h)
        if not a.sin_videos:
            for n in anims:
                video(carpeta, n, os.path.join(a.salida, "animaciones", n + ".mp4"))
            if not solo:
                carrete([os.path.join(a.salida, "animaciones", n + ".mp4") for n in anims],
                        os.path.join(a.salida, "nojoch_animaciones.mp4"), tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
