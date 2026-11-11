#!/usr/bin/env bash
# Prueba el despliegue con Docker en esta máquina: construye las imágenes, levanta
# proxy HTTPS/WSS + portal + API + servidor de juego + PostgreSQL y comprueba que un
# jugador puede iniciar sesión, pedir ticket y entrar al juego por wss://.
#
#   scripts/test-deploy.sh           construye, levanta, prueba y apaga
#   KEEP=1 scripts/test-deploy.sh    deja todo arriba al terminar (https://localhost)
#   SKIP_BUILD=1 ...                 usa las imágenes alux-portal, alux-api y alux-game ya construidas
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
COMPOSE=(docker compose -f infra/docker/docker-compose.yml -f infra/docker/docker-compose.test.yml --env-file "$ROOT/.env.deploy-test")
[ -n "${EXTRA_COMPOSE:-}" ] && COMPOSE+=(-f "$EXTRA_COMPOSE")

cat > .env.deploy-test <<ENV
DOMAIN=localhost
DISCORD_CLIENT_ID=prueba
DISCORD_CLIENT_SECRET=prueba
SESSION_SECRET=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
GAME_TICKET_SECRET=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
SERVICE_KEY=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
DATABASE_URL=postgres://alux:alux-prueba-local@db:5432/alux
ENV

cleanup() {
  if [ "${KEEP:-0}" != "1" ]; then
    "${COMPOSE[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
    rm -f .env.deploy-test
  fi
}
trap cleanup EXIT

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  echo "== Construyendo imágenes =="
  "${COMPOSE[@]}" build
fi
echo "== Levantando servicios =="
"${COMPOSE[@]}" up -d
echo "== Esperando a que el portal responda por HTTPS =="
for i in $(seq 1 60); do
  if curl -ksf -o /dev/null --noproxy localhost https://localhost/; then break; fi
  sleep 2
  [ "$i" = 60 ] && { "${COMPOSE[@]}" logs --tail 40; echo "El portal no respondió"; exit 1; }
done
# Certificado raíz interno de Caddy, para verificar TLS de verdad en la prueba
docker cp "$("${COMPOSE[@]}" ps -q proxy)":/data/caddy/pki/authorities/local/root.crt /tmp/alux-caddy-root.crt
echo "== Prueba de extremo a extremo por https:// y wss:// =="
NODE_EXTRA_CA_CERTS=/tmp/alux-caddy-root.crt NO_PROXY=localhost no_proxy=localhost \
  npx tsx tests/deploy-check.ts https://localhost
echo "== Estado de los contenedores =="
"${COMPOSE[@]}" ps --format 'table {{.Service}}\t{{.Status}}'
