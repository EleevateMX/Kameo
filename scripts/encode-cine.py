#!/usr/bin/env python3
"""Convierte una toma original de una cinemática al formato que carga el juego y la anota en el manifiesto.

    scripts/encode-cine.py <original.mp4> <id del plano> <segundos>

Escribe game/web/static/video/<id>.mp4 (H.264 main, 720p) y <id>.webm (VP9), sin audio (el sonido
de cada plano lo pone el juego), y actualiza manifest.json con su duración y su huella.
"""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "game/web/static/video"
VF = "scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720,fps=24,format=yuv420p"


def main() -> None:
    src, clip, dur = Path(sys.argv[1]), sys.argv[2], float(sys.argv[3])
    base = ["ffmpeg", "-v", "error", "-y", "-i", str(src), "-t", f"{dur:.3f}", "-an", "-vf", VF]
    mp4, webm = OUT / f"{clip}.mp4", OUT / f"{clip}.webm"
    subprocess.run(base + ["-c:v", "libx264", "-profile:v", "main", "-level", "3.1", "-preset", "slow", "-crf", "23",
                           "-maxrate", "2600k", "-bufsize", "5200k", "-movflags", "+faststart", str(mp4)], check=True)
    subprocess.run(base + ["-c:v", "libvpx-vp9", "-crf", "34", "-b:v", "0", "-deadline", "good", "-cpu-used", "2",
                           "-row-mt", "1", str(webm)], check=True)
    manifest_path = OUT / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    digest = hashlib.sha256(mp4.read_bytes() + webm.read_bytes()).hexdigest()[:10]
    manifest["clips"][clip] = {"src": {"mp4": mp4.name, "webm": webm.name}, "dur": dur, "audio": False, "v": digest}
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False))
    print(f"{clip}: {mp4.stat().st_size / 1e6:.2f} MB mp4 · {webm.stat().st_size / 1e6:.2f} MB webm · v={digest}")


if __name__ == "__main__":
    main()
