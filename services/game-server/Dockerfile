# Servidor dedicado de ALUX (Godot sin ventana).
# Construir desde la raíz del repositorio:
#   docker build -f services/game-server/Dockerfile -t alux-game .
FROM debian:bookworm-slim
ARG GODOT_VERSION=4.5.1
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 \
 && curl -fL -o /tmp/godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
 && unzip -q /tmp/godot.zip -d /opt \
 && mv "/opt/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
 && rm /tmp/godot.zip \
 && apt-get purge -y curl unzip && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*
RUN useradd --create-home alux
COPY --chown=alux:alux game /game
USER alux
# Genera la caché de importación para que el arranque sea inmediato
RUN godot --headless --path /game --import || true
ENV ALUX_PORT=9080
EXPOSE 9080
CMD ["godot", "--headless", "--path", "/game", "--", "--server"]
