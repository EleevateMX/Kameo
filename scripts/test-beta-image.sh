#!/usr/bin/env bash
# Prueba local de la imagen única de la beta (infra/render/Dockerfile), montada como en Render:
# un solo puerto HTTP, el HTTPS puesto por delante por otro proxy y PostgreSQL aparte.
#
#   scripts/test-beta-image.sh             construye, levanta, comprueba, reinicia y vuelve a comprobar
#   SKIP_BUILD=1 scripts/test-beta-image.sh  usa la imagen alux-beta ya construida
#   KEEP=1 …                                deja todo arriba al terminar (https://localhost:8443)
#
# Comprueba: migraciones al arrancar, acceso sólo con invitación, HTTPS/WSS a través de dos
# proxies, partida por WebSocket, métricas y persistencia tras reiniciar los contenedores.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
NET=alux-beta-test
PORT_PUBLIC="${PORT_PUBLIC:-8443}"
rand() { head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'; }

cleanup() {
  if [ "${KEEP:-0}" != "1" ]; then
    docker rm -f alux-beta-front alux-beta-app alux-beta-db >/dev/null 2>&1 || true
    docker network rm "$NET" >/dev/null 2>&1 || true
    docker volume rm alux-beta-test-db >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
docker rm -f alux-beta-front alux-beta-app alux-beta-db >/dev/null 2>&1 || true
docker volume rm alux-beta-test-db >/dev/null 2>&1 || true

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  echo "== Construyendo la imagen =="
  docker build -t alux-beta -f infra/render/Dockerfile .
fi

echo "== Invitaciones de prueba =="
OUT="$(npm run --silent beta:invites -- --testers "Uno,Dos,Tres,Cuatro,Cinco" --days 2)"
mapfile -t CODES < <(printf '%s\n' "$OUT" | grep -oE 'ALUX(-[A-Z0-9]{5}){4}')
INVITES="$(printf '%s\n' "$OUT" | grep -E '^[a-z0-9-]+:[0-9a-f]{64}:' | head -1)"
[ "${#CODES[@]}" = 5 ] && [ -n "$INVITES" ] || { echo "No se pudieron generar las invitaciones"; exit 1; }
DB_PASS="$(rand)"; TICKET_SECRET="$(rand)"; SESSION="$(rand)"; SERVICE="$(rand)"

echo "== Levantando PostgreSQL, ALUX y el proxy HTTPS de delante =="
docker network create "$NET" >/dev/null 2>&1 || true
docker run -d --name alux-beta-db --network "$NET" -v alux-beta-test-db:/var/lib/postgresql/data \
  -e POSTGRES_USER=alux -e POSTGRES_PASSWORD="$DB_PASS" -e POSTGRES_DB=alux postgres:16-alpine >/dev/null
for _ in $(seq 1 30); do docker exec alux-beta-db pg_isready -U alux -q && break; sleep 1; done
run_app() {
  docker run -d --name alux-beta-app --network "$NET" --memory 512m \
    -e PORT=10000 -e BASE_URL="https://localhost:${PORT_PUBLIC}" \
    -e DATABASE_URL="postgres://alux:${DB_PASS}@alux-beta-db:5432/alux" \
    -e SESSION_SECRET="$SESSION" -e GAME_TICKET_SECRET="$TICKET_SECRET" -e SERVICE_KEY="$SERVICE" \
    -e BETA_ACCESS=invite -e BETA_INVITES="$INVITES" alux-beta >/dev/null
}
run_app
# El proxy de delante hace de balanceador de la plataforma: termina el HTTPS y reenvía en HTTP
docker run -d --name alux-beta-front --network "$NET" -p "${PORT_PUBLIC}:${PORT_PUBLIC}" caddy:2 \
  caddy reverse-proxy --from "https://localhost:${PORT_PUBLIC}" --to alux-beta-app:10000 --internal-certs >/dev/null

wait_up() {
  for i in $(seq 1 90); do
    curl -ksf -o /dev/null --noproxy localhost "https://localhost:${PORT_PUBLIC}/healthz" && return 0
    sleep 2
  done
  docker logs --tail 60 alux-beta-app; echo "ALUX no respondió"; exit 1
}
wait_up
docker cp alux-beta-front:/data/caddy/pki/authorities/local/root.crt /tmp/alux-beta-root.crt
check() { NODE_EXTRA_CA_CERTS=/tmp/alux-beta-root.crt NO_PROXY=localhost no_proxy=localhost npm run --silent beta:check -- "https://localhost:${PORT_PUBLIC}" "$@"; }

echo "== Estado de las migraciones =="
docker logs alux-beta-app 2>&1 | grep -E "migraciones|inicio" | head -12
echo "== Comprobación completa con una invitación =="
check --code "${CODES[0]}" --mark "Persiste"
echo "== Memoria en uso (límite del contenedor: 512 MB) =="
docker stats --no-stream --format '{{.Name}}  {{.MemUsage}}  CPU {{.CPUPerc}}' alux-beta-app alux-beta-db

if [ -n "${AFTER_UP:-}" ]; then
  echo "== Pruebas adicionales =="
  E2E_BASE_URL="https://localhost:${PORT_PUBLIC}" E2E_WS_URL="wss://localhost:${PORT_PUBLIC}/ws" E2E_INSECURE_TLS=1 \
    GAME_TICKET_SECRET="$TICKET_SECRET" E2E_INVITES="$(IFS=,; echo "${CODES[*]}")" \
    NODE_EXTRA_CA_CERTS=/tmp/alux-beta-root.crt NO_PROXY=localhost no_proxy=localhost bash -c "$AFTER_UP"
  # Las pruebas adicionales pueden haber renombrado al alux: se vuelve a dejar la marca
  check --code "${CODES[0]}" --mark "Persiste" >/dev/null
fi

echo "== Reinicio de los contenedores (aplicación y base de datos) =="
docker rm -f alux-beta-app >/dev/null
docker restart alux-beta-db >/dev/null
for _ in $(seq 1 30); do docker exec alux-beta-db pg_isready -U alux -q && break; sleep 1; done
run_app
wait_up
docker logs alux-beta-app 2>&1 | grep -E "migraciones" | tail -3
check --code "${CODES[0]}" --expect "Persiste"
echo "== Imagen de la beta verificada =="
