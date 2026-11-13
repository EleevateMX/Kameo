#!/usr/bin/env bash
# Arranca el servidor de zonas sociales (la plaza), un proceso aparte del servidor de mazmorras.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$ROOT/.env" ] && set -a && . "$ROOT/.env" && set +a
GODOT="${GODOT_BIN:-$ROOT/.tools/godot}"
[ -x "$GODOT" ] || { echo "No encuentro Godot. Ejecuta: npm run setup:godot"; exit 1; }
export ALUX_TICKET_SECRET="${GAME_TICKET_SECRET:-${ALUX_TICKET_SECRET:-}}"
export ALUX_SERVICE_KEY="${SERVICE_KEY:-${ALUX_SERVICE_KEY:-}}"
export ALUX_API_URL="${ALUX_API_URL:-http://127.0.0.1:${API_PORT:-4000}}"
export ALUX_ZONE_PORT="${ZONE_PORT:-${ALUX_ZONE_PORT:-9081}}"
exec "$GODOT" --headless --path "$ROOT/game" -- --zone
