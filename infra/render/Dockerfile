# ALUX completo en UNA sola imagen: proxy interno (Caddy) + portal + API + servidor de juego
# (mazmorras) + servidor de zonas (la plaza).
# Pensada para plataformas que exponen un único puerto HTTP y ponen el HTTPS por delante
# (Render, Fly, Railway…). El proxy escucha en $PORT y reparte:
#     /ws        → servidor de juego (WebSocket)        /api/v1/*  → API pública
#     /zone      → servidor de zonas (WebSocket)
#     /game/*    → juego exportado (archivos estáticos)  lo demás   → portal
# Construir desde la raíz:  docker build -f infra/render/Dockerfile -t alux-beta .

# ── 1) Godot: binario para exportar el juego y para ejecutar el servidor ──
FROM debian:bookworm-slim AS godot
ARG GODOT_VERSION=4.5.1
# Certificados raíz extra (sólo si hay un proxy que inspecciona HTTPS; ver infra/docker/certs)
COPY infra/docker/certs/ /usr/local/share/ca-certificates/extra/
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 brotli \
 && update-ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY scripts/setup-godot.sh scripts/build-game.sh scripts/
COPY game game
RUN scripts/setup-godot.sh && scripts/build-game.sh
# Los archivos grandes del juego se comprimen una vez aquí (el .wasm pasa de ~37 MB a ~9 MB)
RUN cd apps/portal/public/game && for f in index.wasm index.pck index.js index.html; do \
      brotli -q 11 -k "$f" && gzip -9 -k "$f"; done && ls -l

# ── 2) Portal compilado y dependencias de la API ──
FROM node:22-bookworm-slim AS build
WORKDIR /app
COPY infra/docker/certs/ /usr/local/share/ca-certificates/extra/
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
 && update-ca-certificates && rm -rf /var/lib/apt/lists/*
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
COPY package.json package-lock.json ./
COPY apps/api/package.json apps/api/
COPY apps/portal/package.json apps/portal/
COPY packages/shared-contracts/package.json packages/shared-contracts/
COPY tests/package.json tests/
RUN npm ci -w @alux/portal -w @alux/api -w @alux/shared-contracts
COPY packages packages
COPY apps/portal apps/portal
COPY apps/api apps/api
COPY supabase/migrations supabase/migrations
COPY --from=godot /src/apps/portal/public/game apps/portal/public/game
RUN npm run build -w @alux/portal

# ── 3) Imagen final ──
FROM node:22-bookworm-slim AS run
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libfontconfig1 tini curl \
 && rm -rf /var/lib/apt/lists/*
COPY --from=caddy:2 /usr/bin/caddy /usr/local/bin/caddy
COPY --from=godot /src/.tools/godot /usr/local/bin/godot
WORKDIR /app
COPY --from=build --chown=node:node /app /app
COPY --chown=node:node game /app/game
COPY --chown=node:node infra/render/Caddyfile infra/render/start.sh /app/infra/render/
RUN chmod +x /app/infra/render/start.sh
USER node
# Caché de importación del proyecto de juego: el servidor arranca al instante
RUN godot --headless --path /app/game --import || true
ENV NODE_ENV=production PORT=10000
EXPOSE 10000
ENTRYPOINT ["tini", "--"]
CMD ["/app/infra/render/start.sh"]
