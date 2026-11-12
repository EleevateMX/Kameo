#!/usr/bin/env bash
# Capturas rápidas del escenario, personajes y HUD sin levantar el servidor.
#   scripts/preview.sh carpeta/de/salida [tomas…]     (tomas: plaza cerca piramide santuario cenote mirador panoramica combate)
#   PREVIEW_SIZE=1920x1080 scripts/preview.sh carpeta kf_sello_1a …   cuadros clave para vídeo, a otra resolución
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-$ROOT/.tools/godot}"
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"; shift
SIZE="${PREVIEW_SIZE:-1280x720}"
"$GODOT" --headless --path "$ROOT/game" --import >/dev/null 2>&1 || true
RUN=("$GODOT" --rendering-driver opengl3 --path "$ROOT/game" --resolution "$SIZE" --script res://tools/preview.gd -- "$OUT" "$@")
if [ -n "${DISPLAY:-}" ]; then "${RUN[@]}"; else xvfb-run -a -s "-screen 0 ${SIZE}x24" "${RUN[@]}"; fi
