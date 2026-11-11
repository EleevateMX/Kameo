"""Renders de vista previa (Cycles en CPU) de los personajes.

Uso (desde la raíz del repo):
    .tools/blender-venv/bin/python art/blender/render_previews.py alux  [carpeta] [res] [filtro]
    .tools/blender-venv/bin/python art/blender/render_previews.py balam [carpeta] [res] [filtro]

Por defecto escribe en art/previews/ a 512 px, más una hoja de contacto
(<personaje>_hoja.png). Giro de cámara 0 = de frente, 90 = a la izquierda del
personaje, 180 = por detrás.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import kameo_common as kc  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

# (nombre, animación, segundos, giro, elevación, tocado[, objetivo, distancia])
ALUX_SHOTS = [
    ("alux_01_frente34_palma", None, 0, 30, 10, "Hat_Palma"),
    ("alux_02_lado_flor", None, 0, 90, 5, "Hat_Flor"),
    ("alux_03_espalda34_penacho", None, 0, 150, 14, "Hat_Penacho"),
    ("alux_04_frente_penacho", None, 0, 10, 6, "Hat_Penacho"),
    ("alux_05_frente34_flor", None, 0, 35, 8, "Hat_Flor"),
    ("alux_06_cara_cabello", None, 0, 12, 3, "Hair", (0, 0, 1.04), 1.7),
    ("alux_07_cara_palma", None, 0, 38, 0, "Hat_Palma", (0, 0, 1.1), 1.9),
    ("alux_08_arriba_palma", None, 0, 200, 40, "Hat_Palma"),
    ("alux_10_idle_parpadeo", "Idle", 0.62, 25, 8, "Hat_Flor"),
    ("alux_11_run_a", "Run", 0.15, 70, 8, "Hat_Palma"),
    ("alux_12_run_b", "Run", 0.40, 110, 8, "Hair"),
    ("alux_13_jump", "Jump", 0.30, 35, 5, "Hat_Penacho"),
    ("alux_14_fall", "Fall", 0.20, 30, 0, "Hat_Palma"),
    ("alux_15_swim", "Swim", 0.40, 70, 18, "Hat_Flor", (0, 0, 0.6), 3.1),
    ("alux_16_cast_prep", "Cast", 0.10, 50, 8, "Hat_Palma"),
    ("alux_17_cast", "Cast", 0.20, 50, 8, "Hat_Palma"),
    ("alux_18_dodge", "Dodge", 0.133, 90, 5, "Hair", (0, 0, 0.6), 3.1),
    ("alux_19_interact", "Interact", 0.34, 65, 8, "Hat_Flor"),
    ("alux_20_hit", "Hit", 0.07, 40, 8, "Hat_Penacho"),
    ("alux_21_death", "Death", 0.90, 55, 30, "Hat_Flor", (0, 0.4, 0.3), 3.3),
]

BALAM_SHOTS = [
    ("balam_01_frente34", None, 0, 35, 12, None),
    ("balam_02_lado", None, 0, 90, 4, None),
    ("balam_03_espalda34", None, 0, 145, 18, None),
    ("balam_04_frente", None, 0, 0, 5, None, (0, 0, 0.6), 3.2),
    ("balam_05_cara", None, 0, 30, 8, None, (0, -0.6, 0.85), 1.6),
    ("balam_06_arriba", None, 0, 100, 50, None),
    ("balam_10_idle", "Idle", 0.8, 50, 10, None),
    ("balam_11_run_a", "Run", 0.0, 90, 4, None),
    ("balam_12_run_b", "Run", 0.12, 90, 4, None),
    ("balam_13_run_c", "Run", 0.30, 90, 4, None),
    ("balam_14_jump", "Jump", 0.30, 80, 5, None),
    ("balam_15_fall", "Fall", 0.20, 75, 5, None),
    ("balam_16_swim", "Swim", 0.30, 70, 18, None),
    ("balam_17_claw_prep", "Claw", 0.09, 330, 8, None, (0, -0.1, 0.6), 3.4),
    ("balam_18_claw", "Claw", 0.17, 330, 8, None, (0, -0.1, 0.6), 3.4),
    ("balam_19_charge", "Charge", 0.20, 55, 8, None),
    ("balam_20_chargerelease_a", "ChargeRelease", 0.10, 80, 5, None, (0, 0, 0.7), 4.2),
    ("balam_21_chargerelease_b", "ChargeRelease", 0.20, 80, 5, None, (0, 0, 0.7), 4.2),
    ("balam_22_pounce", "Pounce", 0.25, 80, 5, None, (0, 0, 0.65), 4.0),
    ("balam_23_hit", "Hit", 0.07, 50, 8, None),
    ("balam_24_death", "Death", 1.0, 60, 28, None, (0, 0.1, 0.3), 3.7),
]


def shrink_png(path):
    """Reduce el PNG a paleta de 200 colores para no engordar el repo (necesita Pillow)."""
    try:
        from PIL import Image
    except ImportError:
        return
    im = Image.open(path).convert("RGB")
    im.quantize(colors=200, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG).save(
        path, optimize=True)


def contact_sheet(outdir, prefix, cols=5, cell=256):
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


def main():
    who = sys.argv[1] if len(sys.argv) > 1 else "alux"
    outdir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(REPO, "art", "previews")
    res = int(sys.argv[3]) if len(sys.argv) > 3 else 512
    flt = sys.argv[4] if len(sys.argv) > 4 else ""
    os.makedirs(outdir, exist_ok=True)
    if who == "alux":
        import build_alux as mod
        shots, target, dist = ALUX_SHOTS, (0, 0, 0.78), 3.2
    else:
        import build_balam as mod
        shots, target, dist = BALAM_SHOTS, (0, 0.15, 0.55), 3.8
    arm, objs = mod.build()
    cam = kc.setup_preview()
    hats = [n for n in objs if n.startswith("Hat_") or n == "Hair"]
    for shot in shots:
        name, anim, t, yaw, pitch, hat = shot[:6]
        tgt = shot[6] if len(shot) > 6 else target
        dst = shot[7] if len(shot) > 7 else dist
        if flt and flt not in name:
            continue
        for h in hats:
            show = (h == hat) or (h == "Hair" and hat in ("Hat_Flor", "Hat_Penacho"))
            objs[h].hide_render = not show
        if anim:
            act_len = dict((a[0], a[1]) for a in mod.ANIMS)[anim]
            frames = max(1, round(act_len * kc.FPS))
            kc.set_action(arm, anim, round(t / act_len * frames))
        else:
            kc.clear_action(arm)
        kc.render(os.path.join(outdir, name + ".png"), cam, tgt, yaw, pitch, dst, res=res, samples=32)
        shrink_png(os.path.join(outdir, name + ".png"))
        print("render", name)
    contact_sheet(outdir, who)


if __name__ == "__main__":
    main()
