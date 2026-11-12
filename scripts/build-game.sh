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
# Archivos que acompañan al juego sin pasar por el motor: el puente de vídeo de las cinemáticas
# con sus vídeos (game/web/static/video) y el mezclador de audio con la música, los ambientes y
# las bandas sonoras de las cinemáticas (game/web/static/audio).
rm -rf "$OUT/video" "$OUT/audio"
cp -R "$ROOT/game/web/static/." "$OUT/"
rm -f "$OUT/.gdignore"
echo "Juego exportado en $OUT"
ls -lh "$OUT" | tail -n +2
