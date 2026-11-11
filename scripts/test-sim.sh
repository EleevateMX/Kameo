#!/usr/bin/env bash
# Prueba de invariantes de la simulación de movimiento (colisiones, velocidad, determinismo).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-$ROOT/.tools/godot}"
[ -x "$GODOT" ] || { echo "No encuentro Godot. Ejecuta: npm run setup:godot"; exit 1; }
"$GODOT" --headless --path "$ROOT/game" --script res://tests/sim_fuzz.gd
