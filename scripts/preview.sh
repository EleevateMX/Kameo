#!/usr/bin/env bash
# Capturas rápidas del escenario, personajes y HUD sin levantar el servidor.
#   scripts/preview.sh carpeta/de/salida [tomas…]     (tomas: plaza cerca piramide santuario cenote mirador panoramica combate)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-$ROOT/.tools/godot}"
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"; shift
"$GODOT" --headless --path "$ROOT/game" --import >/dev/null 2>&1 || true
RUN=("$GODOT" --rendering-driver opengl3 --path "$ROOT/game" --resolution 1280x720 --script res://tools/preview.gd -- "$OUT" "$@")
if [ -n "${DISPLAY:-}" ]; then "${RUN[@]}"; else xvfb-run -a -s "-screen 0 1280x720x24" "${RUN[@]}"; fi
