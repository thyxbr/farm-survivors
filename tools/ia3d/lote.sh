#!/usr/bin/env bash
# Gera, reduz e pinta várias peças, uma depois da outra (a pintura usa quase toda a GPU: nunca duas juntas).
#
#   bash tools/ia3d/lote.sh <peça> [<peça> ...]
#
# Cada <peça> é uma pasta $IA3D/vistas/<peça> com frente.png, lado.png e costas.png (tools/ia3d/recortar_folha.py
# monta essas pastas a partir da folha de conceito). Sai em $IA3D/saida/<peça>/: bruto.glb (~1 M faces),
# malha40k.glb (só a peça maior, 40 mil faces) e pintura/pintado.glb (textura de 2048 px).
# Tempo: ~1,5 min a malha e 1 a 2 min a pintura por peça; pico de 9 GB de VRAM.
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"
IA3D="${IA3D:-D:/ia3d}"
PY="$IA3D/.venv/Scripts/python.exe"
cd "$IA3D"
for p in "$@"; do
  mkdir -p "saida/$p/pintura"
  "$PY" -u "$AQUI/gerar.py" "vistas/$p" "saida/$p/bruto.glb" > "saida/$p/gerar.log" 2>&1 || { echo "ERRO gerar $p (saida/$p/gerar.log)"; continue; }
  "$PY" -u "$AQUI/reduzir.py" "saida/$p/bruto.glb" "saida/$p/malha40k.glb" 2>&1 | grep -E "^(pedacos|saida)" | sed "s/^/$p /"
  "$PY" -u "$AQUI/pintar.py" "saida/$p/malha40k.glb" "saida/$p/recortes" "saida/$p/pintura/pintado.glb" \
    > "saida/$p/pintura/log.txt" 2>&1 || { echo "ERRO pintar $p (saida/$p/pintura/log.txt)"; continue; }
  echo "OK $p $(grep -E 'pintura em' "saida/$p/pintura/log.txt")"
done
echo FIM
