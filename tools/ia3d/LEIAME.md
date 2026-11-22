# Equipamento a partir de imagem, com IA local

Do conceito (três vistas desenhadas) até a peça vestida no herói, só com ferramentas abertas rodando na máquina.
Primeiro uso: Elmo Cabeça de Dragão (`h_dragonhead`).

## O que precisa estar instalado

Os scripts ficam aqui em `tools/ia3d` (`gerar.py`, `reduzir.py`, `pintar.py`, `cr_amd/`, `recortar_folha.py`,
`lote.sh`, `rodada.sh`); o ambiente, os pesos e o clone do Hunyuan3D-2 ficam fora do repositório, em `D:\ia3d`
(cerca de 25 GB; outro lugar: variável `IA3D`). Processo e erros a evitar: `docs/EQUIPAMENTO_POR_IA.md`;
comando: `/equipamento-ia`.

- Python 3.12 com ambiente próprio (`D:\ia3d\.venv`).
- PyTorch para placa AMD: pacotes ROCm 7.2.1 da AMD (`repo.radeon.com/rocm/windows/rocm-rel-7.2.1`).
- Hunyuan3D-2 (`D:\ia3d\repo`, clone de `github.com/Tencent/Hunyuan3D-2`). Os pesos da malha
  (`tencent/Hunyuan3D-2mv`) baixam sozinhos; os da pintura (12,6 GB) ficam em `D:\ia3d\models\tencent\Hunyuan3D-2`.
- Versões que precisam ficar fixas: `transformers<5`, `diffusers<0.36`, `huggingface_hub<1`; mais `xatlas`.

## Passo a passo

1. **Vistas.** Uma pasta com `frente.png`, `lado.png` e `costas.png`, fundo liso, um objeto só. No `lado.png` o
   objeto olha para a esquerda da imagem.
2. **Malha.** `python tools/ia3d/gerar.py <pasta_vistas> <saida>/bruto.glb` (uns 95 s). Sai uma malha fechada de
   cerca de 800 mil faces e, em `<saida>/recortes`, as vistas sem fundo.
3. **Pintura.** Reduzir a malha para ~40 mil faces (`FaceReducer` do Hunyuan3D) e rodar
   `python tools/ia3d/pintar.py <malha40k.glb> <saida>/recortes <saida>/pintado.glb`. Uns 25 min, pico de 11,6 GB de
   VRAM; quase tudo na geração das seis vistas, que ficam guardadas em `<saida>/pintado_vistas`.
4. **Base da peça.** `blender --background --factory-startup --python tools/blender/dragon_ia_tex_prep.py -- <saida>/pintado.glb [pasta_previa]`
   reduz para 16 mil faces mantendo o UV, baixa a textura para 1024 px, põe na altura da cabeça do herói e salva
   `tools/blender/base/dragon_ia_tex_base.blend`.
5. **Jogo.** `ASSETS=h_dragonhead` + `build_assets.py` exporta `assets/models/gear/h_dragonhead.glb` (textura em
   JPEG, sem AO nem `cel_paint`: a luz e a sombra já vêm pintadas); depois `--import` e `tools/look_shot.tscn`.

Hoje `tools/ia3d/lote.sh` faz os passos 2 a 3 de várias peças e `tools/ia3d/rodada.sh` os passos 4 e 5 com as fotos.

## O que foi preciso para a pintura rodar em AMD

- O único trecho CUDA da pintura é o `custom_rasterizer`; `tools/ia3d/cr_amd/custom_rasterizer` é um substituto em
  PyTorch puro com a mesma interface (`pintar.py` o põe na frente no caminho de importação).
- O fechamento de buracos por vértice do Hunyuan3D, sem a extensão C++ compilada, cai numa versão em Python puro
  que leva mais de meia hora; `pintar.py` troca por uma em numpy (menos de 1 s).
- Os pesos vão para a pasta com `snapshot_download(local_dir=...)`: o cache normal do Hugging Face tenta criar
  atalhos simbólicos e falha no Windows sem modo de desenvolvedor.
- Recorte de fundo (onnxruntime) e PyTorch ROCm no mesmo processo derrubam o Python: o recorte roda em processo
  à parte (`gerar.py` já faz isso).
- `tools/blender/base` e `tools/blender/refs/<peca>` levam `.gdignore`: sem ele o Godot tenta importar o `.blend`
  e para a importação inteira.

## Caminho antigo: pintura por regras (removido)

Antes de a pintura da IA rodar aqui, a cor era decidida pela forma da malha, com regras medidas à mão. Dava um
resultado pior e pedia medidas novas a cada peça; os scripts foram apagados. Fica registrado o que se aprendeu,
para não repetir:

- Projetar os desenhos do conceito na malha não funciona: as vistas não batem entre si (olhos, largura dos
  chifres), então a cor cai fora do lugar e fica manchada.
- Decidir a cor pela forma (nervuras em relevo para os frisos, marcas medidas para olhos e dentes, corte mínimo
  em grafo para separar o chifre do casco) chega perto, mas cada parte vira um problema próprio, com limites
  que só valem para aquela malha.
- Com 14 mil faces a malha é grossa demais para desenhar olho e friso por face: a cor precisa ir em textura.

## Para outra peça

Trocar em `dragon_ia_tex_prep.py`: o arquivo `BASE`, o nome do objeto, a escala `S` e os centros `C_UNID`/`C_JOGO`
(o centro da peça na malha normalizada de altura 1 e o ponto do herói onde ele fica). A pintura não pede ajuste.

## Armadura inteira (estilos a_/g_/f_dragonia)

- Vistas: uma folha com as peças em linhas (frente, lado, costas) serve; recorte cada célula num quadrado de fundo
  liso (`tools/ia3d/recortar_folha.py` faz isso) (`D:\ia3d\vistas\<peça>`). Em peça assimétrica (ombreira, braçadeira) o detalhe tem de cair do mesmo lado
  da peça na frente e nas costas; se a vista de costas vier trocada, espelhe-a, senão a malha sai com dois chifres.
- `bash tools/ia3d/lote.sh <peça> ...` gera, reduz (`reduzir.py`: só a peça maior, 40 mil faces) e pinta cada uma
  em sequência. A pintura leva 1 a 2 min por peça (9 GB de VRAM).
- `tools/blender/dragon_ia_peca_prep.py -- <pintado.glb> <peça> [prévia]` prepara a base de cada peça (tabela
  `PECAS`: giro, espelho, corte da luva, triângulos, chifre extra; `LIMPA`: manchas que a pintura deixou, repintadas
  com o vermelho da placa em volta).
- Rígidas, presas a um pivô e espelhadas para o lado direito (`_dgia_place`): ombreiras (`Arm`), coxotes (`Leg`),
  braçadeiras (`Elbow`, mãos fechada e aberta feitas por código), greva cortada no tornozelo (canela no `Knee`, pé
  no `Ankle`). Com pele: o peitoral, que recebe os pesos de `_gb_skirt_w` (tronco em cima, coxas na saia) em
  `g_skin_finish`; as rígidas da mesma armadura ficam 100% no osso do pivô dentro do mesmo esqueleto.
- Encaixe das peças em tubo (greva, braçadeira): medir pela caixa da peça inteira deixa o membro do corpo de fora
  (a greva tem o pé na profundidade, e a placa da frente puxa o centro para a frente; a calça aparecia dos lados).
  `_dgia_cavity` mede o vão de dentro com raios e centra o membro nele; `_dgia_enclose` confere, na faixa em que o
  tubo é fechado, se a casca do membro ficou coberta (imprime `ENVOLVE ... descobertos`).
- `bash tools/ia3d/rodada.sh <fotos> <estilos> <itens> [peça=pintado.glb ...]` faz preparo, build, importação e fotos.

## Peças rígidas do corpo (ombreiras, rodada 1)

- Vistas de UMA ombreira (a esquerda): frente = face de fora, lado = perfil com a face de fora para a esquerda da
  imagem, costas = o lado de dentro. A vista de costas tem de estar espelhada em relação à frente (o chifre do
  mesmo lado da peça): a gerada pelo usuário veio com o chifre do lado oposto e a malha saiu com dois chifres.
  `D:\ia3d\vistas\ombreira_b` tem a versão espelhada.
- `python tools/ia3d/reduzir.py <bruto.glb> <malha40k.glb>` fica só com a peça maior (o fundo escuro da vista de
  costas virou um disco solto) e reduz para 40 mil faces.
- `tools/blender/dragon_ia_peca_prep.py` deixa a peça normalizada com a face de fora para +X; escala, lugar e
  espelho para o lado direito ficam em `build_a_dragonia` (`DGP_S`, `DGP_OFF`, `DGP_TILT`), presa a `ArmL`/`ArmR`.
- A pintura da ombreira levou 90 s (9 GB de VRAM), não 25 min como o elmo.
