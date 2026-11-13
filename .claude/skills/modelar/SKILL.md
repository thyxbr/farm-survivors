---
name: modelar
description: "Workflow completo para criar ou refazer um modelo 3D do Ecos de Valdoria no Blender com as melhores práticas do projeto: worktree própria, brief curto, build filtrado, renders small, comparação com o guia de estilo, smoke test e PR. Inclui o modo arma (arma/prop traçado de uma folha de conceito, com a pintura da folha como textura, conferido no Godot). Só roda quando o usuário chama /modelar."
argument-hint: "<asset> [fase 1|2|3|4 | ajuste | arma] [o que mudar]"
disable-model-invocation: true
license: MIT
metadata:
  version: "1.1.0"
---

# /modelar

Pedido: `$ARGUMENTS`

Siga os passos em ordem, sem pedir confirmação entre eles. Só pare para perguntar quando o
pedido for ambíguo (asset desconhecido, fase impossível) ou exigir quebrar algo que o código usa.

## 0. Interpretar o pedido

- **asset**: primeira palavra (`knight`, `goblin`, `elder`, `merchant`, `slime`, `house`, `chest`…
  ou um nome novo, que vira um `build_<nome>()` novo).
- **modo**:
  - `fase 1` — corpo-base contínuo (loft de anéis), proporção, silhueta, pivôs `KneeL/KneeR/ElbowL/ElbowR`.
  - `fase 2` — armadura/roupa em camadas, cinto, frisos, capa.
  - `fase 3` — cabeça, elmo, rosto, cabelo/barba, mãos.
  - `fase 4` — visual no jogo (luz, ambiente, tonemap no Godot); não usa Blender, pule 4–5 e
    compare com prints do jogo.
  - `ajuste` — mudança pontual descrita no resto do pedido (cor, tamanho, uma peça).
  - `arma` — arma ou prop que tem de bater com uma **folha de conceito** (ex.: `/modelar w_azure_edge arma`,
    `/modelar w_<id_novo> arma`). Siga a seção **Modo arma** no lugar dos passos 2–6; os passos 1 e 7 valem.
  - Sem modo: asset `w_<id>` (arma) → `arma`; personagem que ainda é pilha de primitivas → `fase 1`;
    o resto → `ajuste`.
- **o que mudar**: o texto restante. Junte com os problemas que você mesmo vê no baseline.

**Modelo**: fases 1–3, `arma` e assets novos dependem de julgamento visual. Se estiver rodando em
Sonnet ou Haiku, diga em uma linha que Opus é o recomendado para isso e continue. `ajuste` vai bem em Sonnet.

## 1. Preparar a worktree (outras sessões usam o mesmo checkout)

```bash
cd C:/Games/godot-3d && git fetch -q origin
git worktree add -b modelo-<asset>-<modo> ../godot-3d-<asset> origin/main   # se já existir, reutilize
```

Trabalhe **só dentro de `../godot-3d-<asset>`**: os scripts de build e preview leem e gravam
relativo à própria pasta. Rode `--import` do Godot na worktree antes do smoke test (passo 6).

## 2. Contexto mínimo

1. `.claude/skills/references/godot-3d-pipeline.md` (comandos, convenções, orçamentos).
2. Personagens: `tools/blender/STYLE.md`, só as seções da fase. **Não abra as imagens de
   `refs/` agora.**
3. Ache a função do asset com `grep -n "^def build_<asset>\|^def " tools/blender/*.py` e leia só
   esse trecho e os helpers que ela usa. Nunca leia `characters.py` inteiro.
4. `grep -rn` dos nomes de peças e pivôs do asset em `scripts/` (são API).
5. Carregue no máximo 2–3 skills do roteamento (ex.: fase 1 → `character-artist` + `stylized-style`;
   fase 2 → `character-archetypes` + `materials`; prop → `prop-artist` + `lowpoly-style`).
   Não carregue `blender-director` no modo `ajuste`.

## 3. Brief no chat (até 6 linhas)

```markdown
**Asset:** <nome> — <modo>   **Orçamento:** <tris> tris, <n> materiais
**Hoje:** <2–3 problemas principais>
**Vou mudar:** <lista curta>   **Nomes mantidos:** <peças usadas por scripts/>
**Skills:** <2–3>
```

Siga em frente sem esperar resposta.

## 4. Baseline (uma vez)

Se o GLB já existe: render `small` normal → `<scratchpad>/<asset>_antes.png`, leia uma vez e
anote os problemas. Guarde o arquivo para o antes/depois; não leia de novo.

## 5. Loop de iteração (máx. 3 rodadas; 4 nas fases 1–3)

Cada rodada:
1. Edite a função do asset (e helpers novos, ex.: gerador de corpo-base reutilizável na fase 1).
2. Build filtrado:
   ```bash
   B="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
   ASSETS=<asset> "$B" --background --factory-startup --python tools/blender/build_assets.py > <scratchpad>/build.log 2>&1
   grep -E "^EXPORT|Error|Traceback" <scratchpad>/build.log   # sem EXPORT? tail -n 40 no log
   ```
3. Render `small` (+ `silhouette small` quando a fase é de forma) e leia **uma** imagem por vez.
4. Lista de falhas contra o checklist do STYLE.md / da fase; corrija **todas** na próxima rodada.

Pare antes do limite quando o checklist da fase passar. Se no limite ainda não convergiu, pare,
mostre a última imagem ao usuário e pergunte o que priorizar.

## 6. Conferência final

1. Render em tamanho cheio (sem `small`), normal e `silhouette`; `preview_closeup.py` nas fases 2–3.
2. Agora, e só agora, abra **uma** imagem de referência relevante em
   `C:/Games/godot-3d/tools/blender/refs/` e compare com o checklist do STYLE.md (seção 8).
   Corrija o que for grave (no máximo uma rodada extra).
3. `TRIS` e nº de materiais dentro do orçamento; nomes de `scripts/` ainda batem.
4. Mostre ao usuário o antes e o depois (envie as imagens se houver ferramenta para isso).
5. Rode a skill `smoke-check` no modo `rapido` dentro da worktree.

## 7. Entregar

1. Suba o patch de `config/version` em `project.godot` (o jogo tem auto update; PRs de modelo sobem a versão).
   No modo `arma`, versione também `tools/blender/traced/` (JSON e `tex/*.png` com os `.import`); `refs/` nunca.
   Se outra branch aberta já subiu o mesmo número, suba de novo ao atualizar com o `main`.
2. Commit com o que mudou e tris antes → depois; push; PR para `main`. **Sem merge** até o usuário pedir.
3. Resposta final curta: o que mudou, tris/materiais antes → depois, veredito do smoke-check,
   link do PR e a sugestão do próximo passo (ex.: `/modelar knight fase 2`).
4. Depois do merge (quando pedido): apagar a branch local e remota e a worktree.

## Modo arma (arma/prop de uma folha de conceito)

A meta é **a folha**, não uma reinterpretação: o contorno sai traçado da folha, as peças planas viram
placas infladas, cabo e pomo viram sólidos de revolução, e a pintura da folha entra como textura projetada
de frente (degradês, sombras e frisos chegam ao jogo como desenhados). Modelar à mão com cor chapada,
losango low-poly e conferir em Workbench deixou as 15 espadas longe da folha; não volte a isso.
Substitui os passos 2–6. Aqui as regras de referência dos personagens **não** valem: a referência
(o recorte da arma) é aberta em toda rodada, uma arma por vez.

Arquivos: `tools/blender/trace_swords.py` (traçado, config `SWORDS`), `tools/blender/weapons.py`
(`build_traced`, `slab`, `lathe`, `tex_mat`; Chama Rosada à mão em `build_w_rose_flame`),
`tools/blender/traced/` (saída do traçado, versionada), `tools/weapon_shot.gd` (foto no Godot),
`tools/blender/preview_weapon_eevee.py` (render no Blender), `scripts/player/weapon_model.gd`.

### A1. Preparar

1. `refs/` é local (está no `.gitignore`) e a worktree nova nasce sem ele. O traçado lê a folha relativo à
   própria worktree: `mkdir -p tools/blender/refs && cp C:/Games/godot-3d/tools/blender/refs/espadas.webp tools/blender/refs/`.
   `traced/` é versionado: o build só precisa dele, não da folha.
2. Leia o cabeçalho e `SWORDS` de `trace_swords.py` e, com `grep -n "^def "`, só `build_traced` e a
   assinatura de `slab`/`lathe` em `weapons.py`. Skills: no máximo `prop-artist` + `materials`.
3. Folha diferente de `refs/espadas.webp`: `SHEET`, `BG` (cor do fundo) e a escala `TRACE_S`
   (1,2 m por 426 px, a da Chama Rosada) são fixos hoje; ajuste antes, mantendo uma escala única por folha.
4. Brief do passo 3 com orçamento de arma (abaixo). Baseline: se o GLB existe, foto no Godot (A4).

### A2. Recortar e decidir os cortes

1. Arma nova: `python tools/blender/trace_swords.py comps` lista as manchas da folha `(x0, y0, x1, y1, px)`;
   a da arma vira o `box`. Crie a entrada em `SWORDS` com `box`, `grip` (y0, y1 do cabo; a origem fica
   no meio dele) e um palpite de `parts`.
2. `python tools/blender/trace_swords.py grid <id> <scratchpad>/<id>_grid.png`: recorte 3× com grade de
   10 px (linhas azuis e número a cada 50 px). Leia a grade e decida as peças
   `(tipo, nome, y0, y1, x0, x1, extras)` em pixels da folha:
   - lâmina, guarda, asas, ganchos, adornos planos → `slab` (placa inflada do contorno da máscara dentro
     da caixa; `extras` = `_b(th, bevel)` em metros, ou os presets `BLADE`, `GUARD`, `THIN`, `HILT`);
   - cabo e pomo redondos → `lathe` (raio = meia largura da máscara em cada linha; `{"seg": 6–8}`);
   - deixe as faixas se sobreporem alguns px (guarda sobre a lâmina) para não abrir fresta; se a caixa
     pega pedaço de outra peça, estreite `x0/x1`. Contorno com mais de um pedaço vira `Nome0`, `Nome1`…
   - `eps` (simplificação, padrão 1.2 px) e `min_area` nos extras se o contorno sair serrilhado ou com sujeira.

### A3. Traçar e buildar

```bash
python tools/blender/trace_swords.py > <scratchpad>/trace.log 2>&1     # regrava traced/espadas_trace.json e traced/tex/<id>.png
grep "<id>" <scratchpad>/trace.log                                      # peças e nº de pontos de cada uma
B="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
ASSETS=w_<id> "$B" --background --factory-startup --python tools/blender/build_assets.py > <scratchpad>/build.log 2>&1
grep -E "^EXPORT|Error|Traceback" <scratchpad>/build.log
```

O traçado regrava todas as armas: `git status tools/blender/traced/` deve mostrar só a `<id>` mudando.
Arma nova: inclua o id no laço de `build_traced` no fim de `weapons.py` e o item em
`scripts/autoload/item_db.gd` com `"model": "w_<id>"` (`knight_look.gd` instancia o GLB pelo `model`).
`ASSETS=weapons` gera todas.

### A4. Conferir no Godot (loop, até 4 rodadas)

O Godot é a verdade (luz, tonemap e o importador mudam a cor); o Blender só ajuda a achar a causa.

```bash
G="C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe"
"$G" --headless --path . --import > <scratchpad>/import.log 2>&1          # obrigatório depois de cada build
"$G" --path . --resolution 420x900 --script res://tools/weapon_shot.gd -- w_<id> <scratchpad>/<id>_godot.png > <scratchpad>/shot.log 2>&1
grep -E "^SHOT|^SURF|ERROR" <scratchpad>/shot.log
```

- `weapon_shot.gd` precisa de janela: **sem `--headless`** (sem janela não há imagem). Usa o mesmo céu,
  sol e tonemap do `world.gd` e câmera ortográfica de frente; acrescente `3q` para a vista 3/4
  (espessura e bisel). As linhas `SURF` dizem se a superfície tem cor por vértice e se ela é o albedo.
- Blender, quando precisar separar modelo de importação:
  `"$B" -b --factory-startup --python tools/blender/preview_weapon_eevee.py -- w_<id> <scratchpad>/<id>_eevee.png [900] [3q] 2>&1 | grep -E "^TRIS|Error"`
  (imprime `TRIS <id> <tris> <materiais>`). Eevee, não Workbench: o Workbench achata a cor e o bisel.
- Compare **lado a lado** a foto do Godot com o recorte da grade (A2), lendo as duas imagens na rodada.
  Para revisar todas de uma vez: um laço de `weapon_shot.gd` por `assets/models/w_*.glb` e uma folha
  montada com PIL (recorte da folha | foto), lida em grupos de 5.
- Checklist da arma:
  1. silhueta = contorno da folha (pontas, ganchos, furos, curvas da guarda);
  2. cores e degradês da folha; gume sem franja branca e sem cinza lavado;
  3. no `3q`: espessura e bisel legíveis, sem fresta entre peças, cabo redondo;
  4. cabo na origem, lâmina em +Z, empty `Tip` na ponta (o jogo usa para rastro e alcance);
  5. orçamento: 1,8k–3,6k tris e **1 material** por arma.

### A5. Armadilhas já resolvidas (não redescubra)

- **Cor por vértice sai branca no jogo**: o importador glTF do Godot traz `COLOR_0`, mas não liga
  `vertex_color_use_as_albedo`. `WeaponModel.use_vertex_color()` (`scripts/player/weapon_model.gd`) liga ao
  instanciar; `knight_look.gd` e `weapon_shot.gd` já chamam. Todo código novo que instancie um GLB de arma
  tem de chamar também.
- **Gume cinza**: especular baixo. `tex_mat` usa `Specular IOR Level` ≈ 0.12 (`vc_mat` 0.2–0.25); acima
  disso o reflexo rasante (Fresnel) clareia o gume e apaga o contorno escuro pintado.
- **Franja branca no gume**: o fundo da textura é preenchido (`fill_bg`) a partir do **miolo com cor de
  verdade** (pixel longe do branco do fundo e 3 px para dentro, ou 7 px dentro da máscara). Partir da
  máscara inteira puxa a borda anti-serrilhada clara da folha, e o gume da malha, que fica sobre ela,
  sai com calombos brancos.
- `refs/` é local (fora do git); `traced/` é versionado. Nunca commite a folha.
- Pintura à mão por vértice (`vc_mat` + `paint`, como a Chama Rosada) só quando a textura projetada não
  serve; é bem mais trabalhosa e o resultado é o mesmo material único.

### A6. Conferência final

Foto do Godot de frente e `3q` ao lado do recorte; mostre ao usuário o antes/depois (envie as imagens se
houver ferramenta). `TRIS`/materiais no orçamento. `smoke-check` no modo `rapido` na worktree. Depois, passo 7.

## Regras de economia

- Saída do Blender e do Godot sempre em log + `grep`; nunca a saída inteira no contexto.
- Nunca leia a mesma imagem duas vezes nem releia arquivo já lido; localize com `grep -n`.
- Junte todas as correções de uma rodada; nada de rodada para um detalhe só.
- Imagens de referência dos personagens: no máximo uma leitura por sessão, na conferência final.
  No modo `arma` a referência (o recorte da arma, não a folha inteira) é lida a cada rodada, uma arma por vez.
