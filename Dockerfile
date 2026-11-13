# Servidor dedicado do Ecos de Valdoria (Godot headless).
#   docker build -t valdoria-server .
#   docker run -p 7777:7777/udp valdoria-server
# No Easypanel: App com build por Dockerfile + Advanced → Ports: 7777 → 7777 (UDP).
FROM debian:bookworm-slim

ARG GODOT_VERSION=4.7.2
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates wget unzip libfontconfig1 \
 && rm -rf /var/lib/apt/lists/* \
 && wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" -O /tmp/godot.zip \
 && unzip -q /tmp/godot.zip -d /tmp \
 && mv "/tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
 && chmod +x /usr/local/bin/godot \
 && rm /tmp/godot.zip

RUN useradd --create-home valdoria \
 && mkdir /game \
 && chown valdoria:valdoria /game
WORKDIR /game
COPY --chown=valdoria:valdoria . .
# o Godot grava o cache de import em /game/.godot: a pasta precisa ser do usuário
USER valdoria

# importa os assets (.glb etc.) uma vez, na build da imagem
RUN godot --headless --path /game --import \
 && test -d /game/.godot/imported

# /data guarda o banco de contas: monte um volume do Easypanel nele para não perder as contas ao atualizar
ENV GAME_PORT=7777 HTTP_PORT=8080 DB_PATH=/data/valdoria.db
EXPOSE 7777/udp
EXPOSE 8080
# "exec" deixa o Godot receber o SIGTERM direto (o container para na hora)
CMD ["sh", "-c", "exec godot --headless --path /game -- --server --port=${GAME_PORT} --http-port=${HTTP_PORT} --db=${DB_PATH}"]
