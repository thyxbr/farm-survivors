---
name: equipamento-ia
description: "Gera o modelo 3D de um equipamento do Ecos de Valdoria (armadura, elmo, arma, escudo) a partir de uma imagem de referência do usuário, com IA local (Hunyuan3D-2 na GPU AMD): recorte das vistas, malha, pintura, preparo no Blender, estilo no gear.py ou na armaria, fotos no jogo e folha conceito x jogo. Só roda quando o usuário chama /equipamento-ia."
argument-hint: "<imagem> <tipo: armadura|elmo|arma|escudo> <nome> [peças da folha, de cima para baixo]"
disable-model-invocation: true
license: MIT
metadata:
  version: "1.0.0"
---

# /equipamento-ia

Pedido: `$ARGUMENTS`

Leia antes de tudo `docs/EQUIPAMENTO_POR_IA.md` (regras e erros já cometidos) e `tools/ia3d/LEIAME.md` (scripts).
Siga os passos em ordem. Pare só para o que é do usuário: aprovar a folha conceito x jogo de cada rodada.

## 0. Entender o pedido

- `<imagem>`: caminho da folha (ou a imagem que o usuário colou: ela fica no scratchpad, em `images/`). Abra e
  olhe: quantas peças (linhas) e quantas vistas (colunas). Sem as três vistas (frente, lado, costas), peça ao
  usuário a imagem que falta com um prompt completo por imagem (um bloco inteiro por imagem, sem "troque X").
- `<tipo>` e `<nome>`: armadura → estilos `a_<nome>` (+ `g_`, `f_`, `h_` se a folha tiver), itens `<nome>_plate`
  etc.; arma → asset da classe (`w_`, `st_`, `sc_`, `bw_`), item de arma; escudo → `sh_`.
- Peça por peça, decida **rígida no pivô** ou **com pele** (tabela em `docs/EQUIPAMENTO_POR_IA.md`). Arma e escudo
  são sempre rígidos.

## 1. Worktree e estado

```bash
cd C:/Games/godot-3d && git fetch -q origin
git worktree add -b equip-<nome> ../godot-3d-<nome> origin/main
```

Trabalhe só na worktree. Depois de criada: `godot --headless --path . --import` (senão o build e as fotos falham).
Não reinstale nada em `D:\ia3d` (ambiente, pesos e clone do Hunyuan3D-2 já estão lá).

## 2. Vistas

```bash
$IA3D/.venv/Scripts/python.exe -I tools/ia3d/recortar_folha.py <imagem> <peça1>,<peça2>,...
```

Abra `D:\ia3d\vistas\recortes_folha.png` e confira, peça por peça:
- nenhuma célula cortada no meio;
- o lado com a frente da peça para a esquerda da imagem;
- detalhes assimétricos (chifre, gancho, gema de um lado só) do mesmo lado da peça na frente e nas costas. Se
  as costas vierem trocadas, espelhe `costas.png`; se o lado contradiz as outras vistas, gere uma variante sem ele
  (pasta `<peça>_c` só com frente e costas) e escolha a melhor malha.

## 3. Malha e pintura (em segundo plano)

```bash
bash tools/ia3d/lote.sh <peça1> <peça2> ...
```

Rode com `run_in_background` (uma peça leva ~3 min; a pintura usa 9 GB de VRAM, nunca rode duas ao mesmo tempo).
Enquanto roda, escreva o estilo (passo 4). Quando cada malha sair, renderize a `malha40k.glb` em quatro vistas
cinza e olhe: chifre a mais, placa solta, lado faltando. `reduzir.py` imprime os pedaços: confira que a peça
maior é a certa.

## 4. Preparo e estilo

- Acrescente a peça em `PECAS` de `tools/blender/dragon_ia_peca_prep.py`: base, objeto, giro (face de fora para
  +X em peças de um lado do corpo; arma: lâmina para +Z), espelho, corte embaixo (luva), triângulos, chifre extra.
  Manchas da pintura vão em `LIMPA` (caixas na peça normalizada).
- Builder em `tools/blender/gear.py` com os helpers `_dgia_*`: `_dgia_pair` + `_dgia_place` (rígidas, espelho
  automático), `_dgia_limb` + `_dgia_cavity` + `_dgia_enclose` (peças em tubo), `_dgia_chest` + `g_skin_finish`
  (com pele), `_dgia_export` (rígidas) ou `g_export_skinned(estilo, export_image_format='JPEG', ...)` (com pele).
  Registre o estilo na lista `GEAR` e crie o item em `data/balance/items.json` (`"style"`).
- Arma: siga "Armas" em `docs/EQUIPAMENTO_POR_IA.md` (convenções de `tools/blender/armory.py`, empty `Tip`).

## 5. Rodada (fotos)

```bash
bash tools/ia3d/rodada.sh D:/ia3d/saida/<nome>/rodadaN <estilos> <itens> <peça>=D:/ia3d/saida/<peça>/pintura/pintado.glb ...
```

Olhe `folha.png` e as fotos de perto (`look_shot` com `legs`, `feet`, `torso back`, `bust`, `hands`; `fem` para
o corpo feminino). Corrija o que a lista "Conferência" do documento aponta **antes** de mostrar. Depois monte a
folha conceito x jogo (conceito à esquerda, jogo frente/lado/costas à direita), mande com `SendUserFile` e pare
para validação. Liste os defeitos que ainda se veem.

## 6. Versões e teste no jogo

- Feminina: `ASSETS=<estilo>_f` (as peças exportadas por `_dgia_export`/`g_export_skinned` já deformam).
- Anão: **em pausa** até o usuário decidir. Não gere `_d`.
- Jogo de verdade: `godot --path <worktree> res://scenes/world.tscn -- --level=60 --weapon=<arma> --equip=<ids>`
  (a cena principal é o menu; `--level` antes de `--weapon` e `--equip`).

## 7. Fechar

Quando o usuário aprovar: acrescente ao `docs/EQUIPAMENTO_POR_IA.md` os erros novos que custaram rodadas, rode o
teste rápido (`tests/unit` com `run.gd`), commit, PR. Não suba `config/version` (o CI numera). Merge só com ok do
usuário, depois apague o branch (local e remoto).
