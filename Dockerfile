# Servidor dedicado do Ecos de Valdoria (Godot headless): jogo em UDP 7777 + API HTTP de login/health em 8080,
# contas e personagens num banco SQLite em /data (addons/godot-sqlite, .so do Linux).
#   docker build -t valdoria-server .
#   docker run -v valdoria-data:/data -p 7777:7777/udp -p 8080:8080 valdoria-server
# (sem volume em /data o servidor não sobe — DB_REQUIRE_MOUNT=1; para um teste descartável use -e DB_REQUIRE_MOUNT=0)
#   curl http://127.0.0.1:8080/health
# No Easypanel: App com build por Dockerfile; Mounts → volume em /data (obrigatório); Domains → HTTPS com proxy para a
# porta 8080; Advanced → Ports: 7777 → 7777 (UDP). Envs opcionais: GAME_PORT, HTTP_PORT, DB_PATH, ADMIN_USERS
# (crie a conta antes de pôr o nome em ADMIN_USERS).
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
 && mkdir /game /data \
 && chown valdoria:valdoria /game /data
WORKDIR /game
COPY --chown=valdoria:valdoria . .
# o Godot grava o cache de import em /game/.godot: a pasta precisa ser do usuário
USER valdoria

# importa os assets (.glb etc.) uma vez, na build da imagem
RUN godot --headless --path /game --import \
 && test -d /game/.godot/imported

# /data guarda o banco de contas: monte um volume do Easypanel nele para não perder as contas ao atualizar.
# Sem VOLUME na imagem (um volume anônimo esconderia a falta do volume de verdade e sumiria no próximo deploy):
# com DB_REQUIRE_MOUNT=1 o servidor confere em /proc/mounts que a pasta do DB_PATH é um ponto de montagem e,
# se não for, sai com erro. Um volume nomeado novo herda o dono valdoria de /data (criado acima, antes do USER).
ENV GAME_PORT=7777 HTTP_PORT=8080 DB_PATH=/data/valdoria.db DB_REQUIRE_MOUNT=1
EXPOSE 7777/udp
EXPOSE 8080
# "exec" deixa o Godot receber o SIGTERM direto (o container para na hora)
CMD ["sh", "-c", "exec godot --headless --path /game -- --server --port=${GAME_PORT} --http-port=${HTTP_PORT} --db=${DB_PATH}"]
