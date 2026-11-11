#!/usr/bin/env bash
# Descarga Godot (editor/headless) y la plantilla de exportación Web en .tools/
# Uso: scripts/setup-godot.sh
set -euo pipefail
VERSION="${GODOT_VERSION:-4.5.1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/.tools"
BIN="$TOOLS/godot"
TEMPLATES="${HOME}/.local/share/godot/export_templates/${VERSION}.stable"
BASE="https://github.com/godotengine/godot/releases/download/${VERSION}-stable"
mkdir -p "$TOOLS"

if [ ! -x "$BIN" ]; then
  echo "Descargando Godot ${VERSION}..."
  curl -fL --retry 4 -o "$TOOLS/godot.zip" "$BASE/Godot_v${VERSION}-stable_linux.x86_64.zip"
  unzip -oq "$TOOLS/godot.zip" -d "$TOOLS"
  mv "$TOOLS/Godot_v${VERSION}-stable_linux.x86_64" "$BIN"
  chmod +x "$BIN"
  rm "$TOOLS/godot.zip"
fi

if [ ! -f "$TEMPLATES/web_nothreads_release.zip" ]; then
  echo "Descargando plantillas de exportación (≈1 GB, sólo se conserva la Web)..."
  curl -fL --retry 4 -o "$TOOLS/templates.tpz" "$BASE/Godot_v${VERSION}-stable_export_templates.tpz"
  mkdir -p "$TEMPLATES"
  unzip -oqj "$TOOLS/templates.tpz" \
    "templates/web_nothreads_release.zip" "templates/web_nothreads_debug.zip" "templates/version.txt" \
    -d "$TEMPLATES"
  rm "$TOOLS/templates.tpz"
fi

"$BIN" --version
echo "Godot listo en $BIN"
