#!/usr/bin/env bash
# Exporta el cliente del juego a Web dentro del portal (apps/portal/public/game).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-$ROOT/.tools/godot}"
OUT="$ROOT/apps/portal/public/game"
[ -x "$GODOT" ] || { echo "No encuentro Godot. Ejecuta: npm run setup:godot"; exit 1; }
mkdir -p "$OUT"
"$GODOT" --headless --path "$ROOT/game" --import >/dev/null 2>&1 || true
"$GODOT" --headless --path "$ROOT/game" --export-release "Web" "$OUT/index.html"
[ -f "$OUT/index.wasm" ] || { echo "La exportación no generó index.wasm"; exit 1; }
echo "Juego exportado en $OUT"
ls -lh "$OUT" | tail -n +2
