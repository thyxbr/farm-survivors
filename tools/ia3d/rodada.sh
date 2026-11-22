#!/usr/bin/env bash
# Uma rodada: prepara as bases das peças, exporta os estilos, importa no Godot e fotografa o conjunto.
#
#   bash tools/ia3d/rodada.sh <pasta_fotos> <estilos> <itens> [<peça>=<pintado.glb> ...]
#
#   <estilos>  ASSETS do build, separados por vírgula (ex.: a_dragonia,a_dragonia_f)
#   <itens>    ids vestidos nas fotos, separados por vírgula (ex.: dragonia_plate,dragonhead_helm)
#   <peça>=…   peças a preparar de novo com tools/blender/dragon_ia_peca_prep.py (chaves de PECAS)
#
# Sai <pasta_fotos>/folha.png: frente, 3/4, lado, costas, braços abertos e corrida.
set -eu
RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
B="${BLENDER:-C:/Program Files/Blender Foundation/Blender 5.2/blender.exe}"
G="${GODOT:-C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe}"
PY="${IA3D:-D:/ia3d}/.venv/Scripts/python.exe"
O=$1; A=$2; SET=$3; shift 3
cd "$RAIZ"
mkdir -p "$O"
for pp in "$@"; do pc=${pp%%=*}; gl=${pp#*=}
  "$B" --background --factory-startup --python tools/blender/dragon_ia_peca_prep.py -- "$gl" "$pc" "$O/previa_$pc" 2>&1 \
    | grep -E "^(MALHA|TEXTURA|UNID|OK|CHIFRES|TAMPO|CORTE|LIMPA)|Error|line [0-9]" | sed "s/^/$pc: /" || true
done
ASSETS=$A "$B" --background --factory-startup --python tools/blender/build_assets.py 2>&1 \
  | grep -E "^EXPORT|LOOSE|CONNECTED|ENVOLVE|Error|Traceback|line [0-9]" || true
"$G" --headless --path . --import 2>&1 | grep -E "^ERROR" | head -5 || true
for v in "frente:" "3q:3q" "lado:side" "costas:back" "arms:arms" "run:run 3q"; do
  n=${v%%:*}; x=${v#*:}
  "$G" --path . --resolution 700x700 res://tools/look_shot.tscn -- "$O/$n.png" "$SET" $x 2>&1 | grep -E "^ERROR" || true
done
"$PY" -I -c "
from PIL import Image
ims=[Image.open('$O/%s.png'%n).convert('RGB').resize((450,450)) for n in ('frente','3q','lado','costas','arms','run')]
W=Image.new('RGB',(1350,900),'white')
for i,im in enumerate(ims): W.paste(im,(450*(i%3),450*(i//3)))
W.save('$O/folha.png')"
echo "FOLHA $O/folha.png"
