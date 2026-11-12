"""Renders de vista previa (Cycles en CPU, 2 hilos) y retratos para el HUD.

Uso (desde la raíz del repo):
    .tools/blender-venv/bin/python art/blender/render_previews.py alux      [carpeta] [res] [filtro]
    .tools/blender-venv/bin/python art/blender/render_previews.py balam     [carpeta] [res] [filtro]
    .tools/blender-venv/bin/python art/blender/render_previews.py yaxche    [carpeta] [res] [filtro]
    .tools/blender-venv/bin/python art/blender/render_previews.py portraits [personaje]

Las vistas van a art/previews/ (más una hoja de contacto <personaje>_hoja.png) y los
retratos a game/assets/ui/portrait_alux.png, portrait_balam.png y portrait_yaxche.png
(256×256, fondo transparente; con [personaje] solo se hace el suyo). Giro de cámara 0 = de frente, 90 = a la izquierda del personaje,
180 = por detrás.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import alux_common as kc  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

# (nombre, animación, segundos, giro, elevación, tocados[, objetivo, distancia])
ALUX_SHOTS = [
    ("alux_01_frente34_palma", None, 0, 30, 10, "Hat_Palma"),
    ("alux_02_lado_flor", None, 0, 90, 5, "Hair+Hat_Flor"),
    ("alux_03_espalda34_penacho", None, 0, 150, 14, "Hair+Hat_Penacho"),
    ("alux_04_cara_cabello", None, 0, 12, 3, "Hair", (0, 0, 1.04), 1.7),
    ("alux_05_detalle_cuerpo", None, 0, 22, 8, "Hair", (0, 0, 0.5), 1.7),
    ("alux_10_idle_mirada", "Idle", 1.5, 25, 8, "Hair+Hat_Flor"),
    ("alux_11_run_apoyo", "Run", 0.0333, 80, 6, "Hat_Palma"),
    ("alux_12_run_vuelo", "Run", 0.1333, 80, 6, "Hat_Palma"),
    ("alux_13_jump", "Jump", 0.26, 35, 5, "Hair+Hat_Penacho"),
    ("alux_14_land", "Land", 0.0667, 50, 8, "Hat_Palma"),
    ("alux_15_cast_preparacion", "Cast", 0.0333, 55, 8, "Hat_Palma"),
    ("alux_16_cast_lanzamiento", "Cast", 0.10, 55, 8, "Hat_Palma"),
    ("alux_17_dodge", "Dodge", 0.133, 90, 5, "Hair", (0, 0, 0.6), 3.1),
    ("alux_18_hit", "Hit", 0.0667, 40, 8, "Hair+Hat_Penacho"),
    ("alux_19_transform", "Transform", 0.10, 25, 6, "Hair+Hat_Flor", (0, 0, 0.85), 3.4),
    ("alux_20_death", "Death", 0.90, 55, 30, "Hair+Hat_Flor", (0, 0.4, 0.3), 3.3),
]

BALAM_SHOTS = [
    ("balam_01_frente34", None, 0, 35, 12, None),
    ("balam_02_lado", None, 0, 90, 4, None),
    ("balam_03_espalda34", None, 0, 148, 18, None),
    ("balam_04_cara", None, 0, 28, 6, None, (0, -0.66, 0.86), 1.6),
    ("balam_10_idle", "Idle", 1.5, 45, 10, None),
    ("balam_11_run_empuje", "Run", 0.0333, 90, 4, None),
    ("balam_12_run_vuelo", "Run", 0.1333, 90, 4, None),
    ("balam_13_run_recepcion", "Run", 0.2333, 90, 4, None),
    ("balam_14_claw", "Claw", 0.10, 330, 8, None, (0, -0.1, 0.6), 3.6),
    ("balam_15_charge", "Charge", 0.20, 55, 8, None),
    ("balam_16_chargerelease_arriba", "ChargeRelease", 0.0667, 80, 5, None, (0, -0.1, 0.7), 4.3),
    ("balam_17_chargerelease_golpe", "ChargeRelease", 0.1667, 80, 5, None, (0, -0.1, 0.7), 4.3),
    ("balam_18_pounce", "Pounce", 0.30, 80, 5, None, (0, 0, 0.65), 4.2),
    ("balam_19_pounceland", "PounceLand", 0.0667, 80, 5, None, (0, 0, 0.6), 4.2),
    ("balam_20_transform", "Transform", 0.1667, 60, 5, None, (0, 0, 0.75), 4.5),
    ("balam_21_death", "Death", 1.0, 60, 28, None, (0, 0.1, 0.3), 3.9),
]

YAXCHE_SHOTS = [
    ("yaxche_01_frente34", None, 0, 30, 10, None),
    ("yaxche_02_lado", None, 0, 90, 5, None),
    ("yaxche_03_espalda", None, 0, 180, 12, None),
    ("yaxche_04_cara", None, 0, 14, 4, None, (0, -0.06, 0.97), 1.7),
    ("yaxche_10_idle", "Idle", 2.3, 48, 8, None),
    ("yaxche_11_talk", "Talk", 0.6, 20, 8, None),
    ("yaxche_12_scold", "Scold", 0.62, 10, 8, None, (0, -0.05, 0.85), 2.9),
    ("yaxche_13_bless", "Bless", 0.8, 20, 6, None, (0, -0.05, 1.0), 4.6),
]


def shrink_png(path, colors=200):
    """Reduce el PNG a una paleta para no engordar el repo (necesita Pillow)."""
    try:
        from PIL import Image
    except ImportError:
        return
    im = Image.open(path)
    if im.mode == "RGBA":
        im.quantize(colors=colors, method=Image.Quantize.FASTOCTREE).save(path, optimize=True)
    else:
        im.convert("RGB").quantize(colors=colors, method=Image.Quantize.MEDIANCUT,
                                   dither=Image.Dither.FLOYDSTEINBERG).save(path, optimize=True)


def contact_sheet(outdir, prefix, cols=4, cell=256):
    """Hoja de contacto con todas las tomas (necesita Pillow; si no está, se omite)."""
    try:
        from PIL import Image
    except ImportError:
        return
    import glob
    files = sorted(f for f in glob.glob(os.path.join(outdir, prefix + "_[0-9]*.png")))
    if not files:
        return
    rows = (len(files) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell, rows * cell), "white")
    for i, f in enumerate(files):
        im = Image.open(f).convert("RGB").resize((cell, cell), Image.LANCZOS)
        sheet.paste(im, ((i % cols) * cell, (i // cols) * cell))
    sheet.save(os.path.join(outdir, prefix + "_hoja.png"))
    shrink_png(os.path.join(outdir, prefix + "_hoja.png"))


def show_hats(objs, hat):
    for name in objs:
        if name.startswith("Hat_") or name == "Hair":
            objs[name].hide_render = name not in (hat or "").split("+")


def previews(who, outdir, res, flt):
    os.makedirs(outdir, exist_ok=True)
    if who == "alux":
        import build_alux as mod
        shots, target, dist = ALUX_SHOTS, (0, 0, 0.78), 3.2
    elif who == "yaxche":
        import build_yaxche as mod
        shots, target, dist = YAXCHE_SHOTS, (0, -0.05, 0.78), 3.6
    else:
        import build_balam as mod
        shots, target, dist = BALAM_SHOTS, (0, 0.15, 0.55), 3.9
    arm, objs = mod.build()
    cam = kc.setup_preview()
    lengths = dict((a[0], a[1]) for a in mod.ANIMS)
    for shot in shots:
        name, anim, t, yaw, pitch, hat = shot[:6]
        if flt and flt not in name:
            continue
        show_hats(objs, hat)
        if anim:
            frames = max(1, round(lengths[anim] * kc.FPS))
            kc.set_action(arm, anim, round(t / lengths[anim] * frames))
        else:
            kc.clear_action(arm)
        path = os.path.join(outdir, name + ".png")
        kc.render(path, cam, shot[6] if len(shot) > 6 else target, yaw, pitch,
                  shot[7] if len(shot) > 7 else dist, res=res, samples=20)
        shrink_png(path)
        print("render", name)
    contact_sheet(outdir, who)


def portraits(only=""):
    """Retratos de cabeza y hombros para el HUD y los diálogos: luz plana y amable, fondo
    transparente. `only` limita a un personaje (los demás retratos no se tocan)."""
    outdir = os.environ.get("KAMEO_UI_DIR") or os.path.join(REPO, "game", "assets", "ui")
    os.makedirs(outdir, exist_ok=True)
    for who, hat, target, yaw, pitch, dist in (("alux", "Hat_Palma", (0.04, 0, 1.10), 24, 4, 2.0),
                                               ("balam", None, (0.03, -0.66, 0.885), 32, 6, 1.28),
                                               ("yaxche", None, (-0.02, -0.085, 1.03), 24, 4, 2.2)):
        if only and who != only:
            continue
        mod = __import__("build_" + who)
        arm, objs = mod.build()
        cam = kc.setup_preview(ground=False, sky="#ffffff", ambient=1.0, key=1.4)
        show_hats(objs, hat)
        kc.clear_action(arm)
        path = os.path.join(outdir, "portrait_%s.png" % who)
        kc.render(path, cam, target, yaw, pitch, dist, res=256, samples=48, transparent=True)
        shrink_png(path, colors=255)
        print("retrato", path, os.path.getsize(path), "bytes")


def main():
    who = sys.argv[1] if len(sys.argv) > 1 else "alux"
    if who == "portraits":
        portraits(sys.argv[2] if len(sys.argv) > 2 else "")
        return
    outdir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(REPO, "art", "previews")
    res = int(sys.argv[3]) if len(sys.argv) > 3 else 384
    previews(who, outdir, res, sys.argv[4] if len(sys.argv) > 4 else "")


if __name__ == "__main__":
    main()
