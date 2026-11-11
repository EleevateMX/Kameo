#!/usr/bin/env bash
# Arranque de la imagen única de ALUX: valida la configuración, aplica las migraciones y
# levanta API, servidor de juego, portal y proxy. Si cualquiera de ellos cae, el contenedor
# termina para que la plataforma lo reinicie entero.
set -euo pipefail
log() { echo "[inicio] $*"; }
die() { echo "[inicio] ERROR: $*" >&2; exit 1; }

export NODE_ENV=production
export PORT="${PORT:-10000}"

# ── URL pública (en Render llega sola en RENDER_EXTERNAL_URL) ──
BASE_URL="${BASE_URL:-${RENDER_EXTERNAL_URL:-}}"
[ -n "$BASE_URL" ] || die "Define BASE_URL con la URL pública (https://…)."
export BASE_URL="${BASE_URL%/}"
host="${BASE_URL#*://}"
case "$BASE_URL" in https://*) ws="wss" ;; *) ws="ws" ;; esac
export GAME_SERVERS="${GAME_SERVERS:-gs-1=${ws}://${host}/ws}"

# ── Secretos obligatorios ──
for name in SESSION_SECRET GAME_TICKET_SECRET SERVICE_KEY; do
  value="${!name:-}"
  [ "${#value}" -ge 16 ] || die "Falta $name (mínimo 16 caracteres). Va en los secretos del proveedor, nunca en Git."
done
if [ -z "${DATABASE_URL:-}" ] && [ "${ALUX_ALLOW_FILE_STORE:-0}" != "1" ]; then
  die "Falta DATABASE_URL (PostgreSQL). Sin base de datos el progreso se perdería en cada reinicio."
fi

# ── Todo lo interno escucha sólo dentro del contenedor ──
export API_PORT=4000 API_HOST=127.0.0.1 API_URL=http://127.0.0.1:4000
export ALUX_PORT=9080 ALUX_BIND=127.0.0.1 ALUX_SERVER_ID="${ALUX_SERVER_ID:-gs-1}" ALUX_API_URL=http://127.0.0.1:4000
export ALUX_TICKET_SECRET="$GAME_TICKET_SECRET" ALUX_SERVICE_KEY="$SERVICE_KEY"
# En esta imagen nunca hay "entrada de prueba" abierta: se entra con Discord o con invitación
export ALLOW_DEV_LOGIN=false
unset ALUX_ALLOW_DEV_SECRETS

discord="no"; [ -n "${DISCORD_CLIENT_ID:-}" ] && [ -n "${DISCORD_CLIENT_SECRET:-}" ] && discord="sí"
invites=$(printf '%s' "${BETA_INVITES:-}" | tr ',;' '\n\n' | grep -c ':' || true)
log "URL pública: $BASE_URL · juego: ${GAME_SERVERS#*=}"
log "Discord configurado: $discord · acceso de testers: ${BETA_ACCESS:-off} (${invites} invitación/es)"
if [ "$discord" = "no" ] && { [ "${BETA_ACCESS:-}" != "invite" ] || [ "$invites" = "0" ]; }; then
  log "AVISO: sin Discord y sin invitaciones nadie podrá iniciar sesión."
fi

cd /app
# ── Migraciones (se detiene si alguna falla o si borraría datos) ──
if [ -n "${DATABASE_URL:-}" ]; then
  npm run --silent migrate -w @alux/api || die "Las migraciones fallaron: no se arranca con un esquema a medias."
fi

pids=()
prefix() { sed -u "s/^/[$1] /"; }
start() { # nombre, orden…
  local name="$1"; shift
  ( "$@" 2>&1 | prefix "$name" ) &
  pids+=("$!")
}
stop_all() {
  trap - TERM INT EXIT
  log "Deteniendo servicios…"
  pkill -TERM -f 'next start|tsx src/index.ts|godot --headless|caddy run' 2>/dev/null || true
  pkill -TERM -P $$ 2>/dev/null || true
  for p in "${pids[@]}"; do kill -TERM "$p" 2>/dev/null || true; done
  wait 2>/dev/null || true
}
trap 'stop_all; exit 0' TERM INT

wait_http() { # url, nombre
  for _ in $(seq 1 90); do
    curl -fsS -o /dev/null --max-time 2 "$1" && return 0
    sleep 1
  done
  die "$2 no respondió a tiempo."
}

start api npm run --silent start -w @alux/api
wait_http http://127.0.0.1:4000/health "La API"
start juego godot --headless --path /app/game -- --server
start portal npx --no-install next start apps/portal -H 127.0.0.1 -p 3000
wait_http http://127.0.0.1:3000/ "El portal"
# El proxy va el último: el puerto público sólo se abre cuando todo lo demás responde
start proxy caddy run --config /app/infra/render/Caddyfile --adapter caddyfile
log "ALUX en marcha en el puerto $PORT"

# Si cualquier servicio termina, se apaga todo: la plataforma reinicia el contenedor
wait -n || true
log "Un servicio terminó de forma inesperada."
stop_all
exit 1
