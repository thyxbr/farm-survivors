# Mapa editável no editor — plano de execução

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development (recomendado) ou
> superpowers:executing-plans para executar este plano tarefa por tarefa. Os passos usam caixas (`- [ ]`).

**Objetivo:** os 4 mapas do jogo (vale, Bosque, Mina, Pico) viram cenas `.tscn` editáveis no Godot, com
prévia igual ao jogo, pontos de monstro e nós de coleta configuráveis no Inspector.

**Arquitetura:** scripts `@tool` puros em `scripts/map/` descrevem cada peça (prop, chão pintado, morro, luz,
enfeite, entidade de jogo, ponto de monstro, landmark). O `world.gd` instancia a cena de cada mapa e o
`MapLoader` (lado do jogo, pode citar autoload) percorre os nós e monta o que hoje é montado por código. Uma
ferramenta de conversão grava as cenas a partir do mundo atual montado (sorteios congelados), e um resumo de
conteúdo prova que o jogo ficou igual.

**Tecnologia:** Godot 4.7.2, GDScript, testes próprios do projeto (`tests/unit/run.gd`, smoke, vila, net).

**Spec:** `docs/superpowers/specs/2026-11-15-mapa-editavel-design.md` (ler junto).

## Restrições globais

- Godot: `C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe` (abaixo, `$G`). Depois de criar `class_name`
  novo, rodar `"$G" --headless --path . --import` antes dos testes.
- Todo script anexado a nó das cenas de mapa é **puro**: não cita `Game`, `Network`, `Econ`, `Hub`, `Lobby`,
  `ItemDB`, `Balance`, `Sfx`, `FX`, `Loading`, `Weather`. Scripts do jogo só por `load("res://...")`.
- Scripts das peças são `@tool`; a prévia só é montada com `Engine.is_editor_hint()` e nunca é salva (nós sem
  `owner`). Cada peça expõe um método público de prévia (`build_preview()`) para as ferramentas de foto.
- Cenas de mapa em coordenadas locais; o mundo põe cada uma em `Regions.origin(id)`.
- Servidor dedicado (headless): nada visual (capim, clima, áudio, prévia).
- `ground.gd`: no máximo `MAX_SHAPES = 40` formas pintadas por chão.
- Igualdade após a conversão = mesmo conteúdo (posições com tolerância de 0,01 m, contagens, modelos, luzes);
  capim, fase da piscada das luzes e presentes do poço podem variar.
- `follow_ground` ligado por padrão: a altura salva é a distância até `ground.height_at(x, z)`.
- Nós de coleta: `node_id` inteiro fixo, igual ao índice atual para os 20 existentes.
- Commits pequenos por tarefa; mensagens em português; sem `--no-verify`. Subir `config/version` na última tarefa.
- Memórias do projeto: rodar o smoke de novo antes de culpar uma mudança por falha de projétil (flaky ~1 em 4);
  no teste de rede matar o servidor pelo PID.

## Foco de revisão

1. Mapa editado com peça sem chão por baixo (fora do relevo, `follow_ground` ligado): deve ficar em y = offset,
   não `NaN`/abismo. Teste em `test_map_data` (Tarefa 2) com `height_at` fora do mapa.
2. `EnemySpawn` com `count = 0` ou `radius = 0`: 0 monstros / todos no centro, sem erro. Teste na Tarefa 1.
3. Dois `resource_node` com o mesmo `node_id` ou `kind` inexistente: o teste de validação falha com o nome do
   nó. Teste na Tarefa 10.
4. Cena com mais de 40 `MapGroundPaint`: o teste de validação falha antes do jogo cortar formas em silêncio.
   Teste na Tarefa 10.
5. Cliente online com a cena: não pode criar monstros (só o servidor). Conferido pelo `net_test` na Tarefa 6 e
   por asserção nova no smoke (Tarefa 6): no modo cliente `spawns` fica vazio.

---

### Tarefa 0: base do trabalho

- [ ] **Passo 1:** pedir ao usuário para commitar a vila (`vila-cena`) e abrir o PR dela; criar o branch
  `mapa-editavel` a partir de `vila-cena` num worktree irmão (`../godot-3d-mapa`), rodar `--import` lá.
  Sem aprovação do usuário, não commitar nem dar push.

### Tarefa 1: dados puros dos mapas (`MapData`) e espalhamento dos monstros

**Arquivos:**
- Criar: `scripts/map/map_data.gd`, `scripts/map/enemy_spawn.gd` (só a parte pura nesta tarefa)
- Teste: `tests/unit/test_map_data.gd`, fixture `tests/unit/fixtures/map_fixture.tscn`

**Interfaces (produz):**
- `class_name EnemySpawn extends Node3D` com `@export var kind := "slime"`, `count := 1`, `radius := 0.0`,
  `respawn := 30.0`, `boss := false`, `follow_ground := true`;
  `static func spread(center: Vector3, count: int, radius: float) -> Array[Vector3]`.
- `class_name MapData extends RefCounted`:
  - `const SCENES := {"vila": "res://scenes/maps/vale.tscn", "bosque": ..., "mina": ..., "pico": ...}`
  - `static func load_root(map_id: String) -> Node` (instancia, sem pôr na árvore; quem chama libera)
  - `static func local_xform(root: Node, n: Node3D) -> Transform3D` (soma os transforms até a raiz)
  - `static func landmark(map_id: String, id: String) -> Vector3` (global, com a origem da região; cache)
  - `static func resource_nodes() -> Dictionary` (`node_id -> {"kind": String, "pos": Vector3}` global; cache)
  - `static func enemy_kinds() -> PackedStringArray` (chaves de `data/balance/enemies.json` via `FileAccess`)
  - `static func clear_cache() -> void`
  - Todas aceitam um caminho de cena alternativo para teste: `static var scene_override := {}` (map_id → caminho).

- [ ] **Passo 1: teste que falha** — `test_spread`: `spread(Vector3(1,0,2), 1, 5)` == `[Vector3(1,0,2)]`;
  `spread(c, 0, 5).size() == 0`; `spread(c, 6, 4)`: 6 pontos, todos a distância ≤ 4 de `c`, nenhum par a
  menos de 1 m, e duas chamadas iguais devolvem o mesmo array; `radius = 0` → todos em `c`.
  `test_landmark_and_nodes`: com `scene_override = {"vila": "res://tests/unit/fixtures/map_fixture.tscn"}`,
  `landmark("vila", "camp") == Vector3(62, 0, 0)` e `resource_nodes()[3] == {"kind": "iron", "pos": Vector3(5, 0, 7)}`.
  `test_enemy_kinds`: contém `"slime"`, `"goblin"`, `"lich"`.
- [ ] **Passo 2:** rodar `"$G" --headless --path . -s tests/unit/run.gd` — FALHA (classe inexistente).
- [ ] **Passo 3:** implementar. `spread`: ponto 0 no centro, demais em espiral de ângulo áureo com raio
  `radius * sqrt(i / (count - 1))`. A fixture usa nós `MapLandmark`/`MapEntity` mínimos — criar aqui só os
  campos de dados de `MapLandmark` (`@export var id := ""`) e `MapEntity` (`kind`, `npc_id`, `index`,
  `node_id := -1`, `params: Dictionary`, `follow_ground`) em `scripts/map/map_landmark.gd` e
  `scripts/map/map_entity.gd`; a prévia vem na Tarefa 2.
- [ ] **Passo 4:** `--import` e rodar os unitários — PASSA, "0 falharam".
- [ ] **Passo 5:** commit `Mapa: MapData, EnemySpawn.spread e landmarks puros`.

### Tarefa 2: peças da cena com prévia no editor

**Arquivos:**
- Criar em `scripts/map/`: `map_prop.gd`, `map_ground_paint.gd`, `map_mountain.gd`, `map_grass_area.gd`,
  `map_light.gd`, `map_decor.gd`, `map_preview.gd` (funções estáticas comuns de prévia: boneco com nome,
  contorno de área, toon via `load()`); completar `map_entity.gd`, `map_landmark.gd`, `enemy_spawn.gd`.
- Teste: `tests/unit/test_map_pieces.gd`

**Interfaces (produz):**
- `MapProp extends Node3D`: `@export var model := "rock"` (lista `MapProp.MODELS` = chaves do `M` atual do
  `world.gd`), `shape := 0` (0 nenhuma, 1 caixa, 2 cilindro), `shape_size := Vector3.ZERO` (caixa: x,y,z;
  cilindro: x = raio, y = altura — mesmo formato do `prop()` atual), `no_grass := true`, `follow_ground := true`.
  Escala do nó = escala do modelo. `const DEFAULT_SHAPE := {model: [shape, size]}` preenche ao trocar modelo
  quando `shape_size == Vector3.ZERO`.
- `MapGroundPaint extends Node3D`: `disc := false`, `size := Vector2(4, 4)`, `radius := 4.0`,
  `color := Color(0.45, 0.35, 0.22)`, `soft := 0.8`, `grass := 0.0`.
- `MapMountain extends Node3D`: `radius := 20.0`, `height := 10.0`.
- `MapGrassArea extends Node3D`: `sparse := false` (false = sem capim), `radius := 5.0`.
- `MapLight extends OmniLight3D`: `mode := 0` (0 normal, 1 noite, 2 piscando), `night_energy := 1.0`.
- `MapDecor extends Node3D`: `kind := "xmas_tree"` (lista: `xmas_tree`, `snowman`, `sleigh`, `candy_cane`,
  `gifts`, `light_string`, `lamp_garland`, `wreath`, `wagon`, `scarecrow`, `crops`, `label`, `forge_fire`),
  `params := {}` (ex.: `scale`, `seed`, `end` (Vector3 local), `sag`, `pattern`, `text`, `font_size`, `size`).
  `func build_into(parent: Node3D) -> void` usa os mesmos construtores do jogo (`ChristmasDecor`,
  `RegionBuilder.wagon`...) via `load()`; usado pela prévia e pelo `MapLoader`.
- Todas: `func build_preview(ground_height: Callable = Callable()) -> void` (monta a filha `Preview`; altura
  pelo `Callable(x, z) -> float` quando `follow_ground`).
- `static func ground_y(follow: bool, local_y: float, height: Callable, x: float, z: float) -> float` em
  `map_preview.gd` (Foco 1: `height` inválido ou valor não finito → `local_y`).

- [ ] **Passo 1: teste que falha** — `test_map_pieces.gd`: cada script carrega sem autoload (o próprio
  executor já falha se não compilar); `MapPreview.ground_y(true, 0.5, func(x, z): return 3.0, 0, 0) == 3.5`;
  `ground_y(true, 0.5, func(x, z): return NAN, 0, 0) == 0.5`; `ground_y(false, 2.0, ..) == 2.0`;
  `MapProp.DEFAULT_SHAPE["fence"] == [1, Vector3(2.1, 1.0, 0.25)]` e `["tree_oak"] == [2, Vector3(0.4, 3, 0)]`.
- [ ] **Passo 2:** rodar unitários — FALHA.
- [ ] **Passo 3:** implementar as peças. Prévia de `EnemySpawn`: disco translúcido do raio + `count` bonecos em
  `spread()` + rótulo "kind ×count". `MapEntity`: modelo quando o tipo tem um (signpost, notice_board, portal
  como disco), senão boneco com `npc_id`/`kind`. `MapLandmark`: haste + bandeira + `id`.
- [ ] **Passo 4:** unitários PASSAM. Conferir modo editor com cena de teste:
  `"$G" -e --headless --path . res://tests/unit/fixtures/map_fixture.tscn --quit-after 300` sem `SCRIPT ERROR`.
- [ ] **Passo 5:** commit `Mapa: peças @tool com prévia no editor`.

### Tarefa 3: raiz do mapa (`MapRoot`) com chão, luz e toon na prévia; ferramenta de foto

**Arquivos:**
- Criar: `scripts/map/map_root.gd`, `tools/map_shot.gd`
- Modificar: `scripts/world/ground.gd` (só se precisar de `@tool` ou de um modo sem colisão para a prévia;
  não mudar o resultado no jogo)

**Interfaces (produz):**
- `class_name MapRoot extends Node3D`: `@export var map_id := "vila"`, `half := 125.0`, `border_height := 58.0`,
  `grass_density := 0.6`, `grass_plants := 1.0`, `grass_seed := 0`, `show_preview := true`,
  `preview_grass := false`. `func build_preview() -> void` monta o chão (`ground.gd`: formas dos
  `MapGroundPaint`, morros dos `MapMountain`, `border_mountains`, `build_terrain`), a luz
  (`WorldLighting.build`), chama `build_preview(height)` de cada peça e aplica o toon. `func ground_node() -> Node3D`.
- `tools/map_shot.gd`: `godot --path . --resolution 1200x700 --script res://tools/map_shot.gd -- <saida> <map_id> [vistas]`
  fotografa a prévia (sem editor) nas vistas do `village_shot.gd` (e `camp`, `ruins`, `arena`, `fields`,
  `nest` novas; para regiões, `wide` e `center`).

- [ ] **Passo 1:** fixture `map_fixture.tscn` ganha `MapRoot` na raiz, 1 morro, 2 formas pintadas, 1 prop.
- [ ] **Passo 2:** implementar; rodar o editor headless na fixture com um `print` temporário do número de
  malhas da prévia — > 0 e sem erro; tirar o `print`.
- [ ] **Passo 3:** `map_shot` na fixture gera as PNGs; olhar a imagem (chão com relevo, prop no chão, toon).
- [ ] **Passo 4:** unitários PASSAM. Commit `Mapa: MapRoot com prévia do chão e ferramenta de foto`.

### Tarefa 4: carregador no jogo (`MapLoader`) e resumo de conteúdo

**Arquivos:**
- Criar: `scripts/world/map_loader.gd` (lado do jogo; pode citar autoload)
- Modificar: `scripts/world/world.gd` (fábrica `make_entity`, `content_summary`, `landmarks`)

**Interfaces:**
- Consome: Tarefas 1–3.
- Produz:
  - `class_name MapLoader extends RefCounted`; `static func build(w: Node3D, map_id: String) -> Node3D`
    instancia a cena, põe em `Regions.origin(map_id)` como filha do mundo (nome `Map_<id>`), cria o chão
    (`w.ground` no vale, `w.region_grounds[id]` nas regiões), aplica alturas, e para cada peça: `MapProp` →
    modelo + `StaticBody3D` (`collision_mask = 0`) + pegada sem capim (`w._no_grass`); `MapLight` →
    `DayNightFX.night_light` ou `w.flicker_lights`; `MapDecor.build_into`; `MapEntity` → `w.make_entity(e)`;
    `EnemySpawn` → entradas `{kind, pos, node, timer, respawn}` em `w.spawns`/`w.region_spawns` só quando
    `w.has_server_enemies()` (boss: guarda em `w.boss_spawns[kind]`); `MapGrassArea` → listas do capim;
    `MapLandmark` → `w.landmarks[id]`; `VillageBuilding` → o `_build_buildings` atual. Devolve a raiz.
  - `world.gd`: `var landmarks := {}`; `func make_entity(e: MapEntity) -> Node` (todos os tipos que hoje são
    criados por código: `elder`, `merchant`, `alchemist`, `blacksmith`, `rival`, `npc` (RegionBuilder.npc),
    `story_point`, `hub_point`, `farm_plot`, `kitchen`, `portal`, `signpost`, `santa`, `xmas_gift`,
    `xmas_door`, `resource_node`; guarda em `points`, `santa`, `resource_nodes` como hoje);
    `func content_summary() -> Array` (lista ordenada de `"categoria|modelo_ou_tipo|x|y|z"` com 2 casas, para
    props com cena de origem, luzes por modo, entidades por tipo/id/index, monstros por tipo, formas e morros
    do chão, enfeites por tipo).
- [ ] **Passo 1:** `content_summary()` primeiro, sobre o mundo atual (ainda montado pelo código); rodar o jogo
  com `-- --mapsummary=<arquivo>` (nova flag: monta o mundo, grava o resumo e sai) e guardar como
  `tests/fixtures/map_baseline.txt` (o retrato do jogo antes da conversão; commit dele).
- [ ] **Passo 2:** implementar `MapLoader` e `make_entity` (ainda sem uso; o código antigo segue montando).
- [ ] **Passo 3:** unitários e smoke PASSAM (nada mudou). Commit `Mapa: carregador e retrato do mundo atual`.

### Tarefa 5: ferramenta de conversão e cena do vale

**Arquivos:**
- Criar: `tools/bake_maps.gd`, `scenes/maps/vale.tscn` (gerada)
- Modificar: `scripts/world/christmas_decor.gd`, `scripts/world/region_builder.gd`, `scripts/world/world.gd`
  (ganchos de gravação)

**Interfaces:**
- `static var recorder: Array = []` + `static var recording := false` em `ChristmasDecor`; cada construtor
  público, quando `recording`, anexa `{"kind", "pos", "yaw", "params"}` (mesmos nomes de `MapDecor.kind`).
  Idem para `RegionBuilder.wagon`, o espantalho, a plantação, os `Label3D` soltos e o fogo da forja no `world.gd`.
- Nós criados por `VillageBuilding` (casas, lojas, flores, donos) ganham `set_meta("from_building", true)`
  para a conversão pular.
- `tools/bake_maps.gd` (`--script`, com janela não é preciso): monta o mundo antigo com gravação ligada e escreve
  cada mapa: props a partir de `scene_file_path` + `StaticBody3D` irmão na mesma posição (forma e tamanho),
  luzes pelo grupo de noite / `flicker_lights`, formas e morros lidos do chão (`_shapes`, `_cols`, `_mix`,
  `_peaks` — ler as variáveis, sem mudar o `ground.gd`), entidades pelo script do nó, monstros de `spawns`
  (um `EnemySpawn` com `count = 1` por entrada nesta tarefa), landmarks das constantes atuais, `VillageBuilding`
  copiados de `village.tscn`, paredes invisíveis como `StaticBody3D`. Alturas viram distância ao chão.
  Nós agrupados em Node3D por área (Vila, Horta, Campos, Acampamento, Ruínas, Arena, Floresta Leste, Esparsas,
  Morros, Borda, Natal, Monstros, Coleta). Saída: `scenes/maps/<id>.tscn`.
- [ ] **Passo 1:** ganchos de gravação (sem efeito com `recording = false`; smoke PASSA).
- [ ] **Passo 2:** `bake_maps.gd -- vila` gera `vale.tscn`; abrir no editor headless sem erro.
- [ ] **Passo 3:** `map_shot` do `vale.tscn` × `village_shot` do jogo atual, mesmas vistas, lado a lado em
  `docs/screenshots/mapa_vale_editor_x_jogo.png`; olhar.
- [ ] **Passo 4:** commit `Mapa: conversão do vale para scenes/maps/vale.tscn`.

### Tarefa 6: o jogo passa a carregar o vale da cena

**Arquivos:**
- Modificar: `scripts/world/world.gd` (etapas do `_ready`), `tests/vila_test.gd`, `tests/net_test.gd`,
  `tests/smoke_test.gd`, `tests/unit/test_village_layout.gd`, `scripts/world/village_layout.gd`
- Apagar: `scenes/village.tscn`, `scripts/world/village_plan.gd` (a prévia agora é do `MapRoot`)

- [ ] **Passo 1:** etapas do vale viram `MapLoader.build(self, "vila")`; as funções antigas do vale ficam sem
  chamada (apagadas na Tarefa 11). `VillageLayout.buildings()` lê os `VillageBuilding` do `vale.tscn`.
- [ ] **Passo 2:** teste novo no smoke: `--mapsummary` do mundo novo comparado com
  `tests/fixtures/map_baseline.txt` (só as linhas do vale; tolerância 0,01 m) — 0 diferenças. No modo cliente
  (`net_test`), `spawns` vazio (Foco 5).
- [ ] **Passo 3:** ajustar testes que procuram filhos diretos do mundo para procurar na árvore (mesmas
  contagens e conferências).
- [ ] **Passo 4:** rodar unitários, smoke, vila, net (comando do CI; matar o servidor pelo PID), economia —
  todos PASSAM. Medir o tempo do `_ready` antes/depois (anotar no commit).
- [ ] **Passo 5:** commit `Mapa: o vale vem de scenes/maps/vale.tscn`.

### Tarefa 7: Bosque, Mina e Pico

- [ ] **Passo 1:** `bake_maps.gd -- bosque mina pico`; fotos lado a lado; `MapLoader.build` para cada região no
  lugar de `RegionBuilder.build` (wagon e cocheiro viram `MapDecor`/`MapEntity`; paredes `StaticBody3D`).
- [ ] **Passo 2:** comparação do resumo com a linha de base (todas as linhas) — 0 diferenças.
- [ ] **Passo 3:** unitários, smoke (viagem ao bosque acha `sylvi`, `coach_bosque`, `slime_rainha`), vila, net
  PASSAM. Commit `Mapa: Bosque, Mina e Pico em cena`.

### Tarefa 8: landmarks no lugar das constantes

**Arquivos:** `scripts/world/world.gd`, `scripts/world/regions.gd`, `scripts/world/map_rules.gd`,
`scripts/survival/survival_mode.gd`, testes que leem `w.ARENA`, `w.VILLAGE_SPAWN`, `w.NEST`, `w.MOUNTAINS`.

- [ ] **Passo 1: teste que falha** — em `test_map_rules`: `MapRules.PLACES` vem de `MapData.landmark` (mesmos
  valores de hoje); em `test_guild`: `Regions.coach_point(id)`/`arrive_point(id)` iguais aos atuais e vindos
  de `MapData.landmark(id, "coach"/"arrive")`.
- [ ] **Passo 2:** implementar; `CAMP`, `RUINS`, `ARENA`, `FARM`, `NEST`, `ORCHARD`, `VILLAGE_SPAWN`,
  `PORTAL_POS` saem do `world.gd` (leitores usam `w.landmarks[...]` ou `MapData.landmark`); `coach`/`arrive`
  saem de `Regions.DATA`.
- [ ] **Passo 3:** todos os testes PASSAM. Commit `Mapa: landmarks da cena no lugar das constantes`.

### Tarefa 9: nós de coleta editáveis

**Arquivos:** `scripts/world/world_harvest.gd`, `data/balance/world_nodes.json`, `scripts/balance/balance_tables.gd`,
fixture do snapshot do balanceamento, `tests/unit/test_world_harvest.gd`, cenas (`resource_node` com `node_id`).

- [ ] **Passo 1: teste que falha** — `test_world_harvest`: `node_def(bt, 0).pos == Vector3(71.6, 0, 8.0)` e
  `node_def(bt, 6).pos == Vector3(14.7, 0, -91.5)` vindos da cena; `count(bt) == 20`; id que não existe na
  cena → `{}`; ids não precisam ser contíguos (fixture com ids `[0, 2]`: `node_def(bt, 1) == {}`).
- [ ] **Passo 2:** `node_def` junta `kinds` do JSON com `MapData.resource_nodes()`; `count` = número de nós;
  `nodes` sai do JSON; atualizar o snapshot do balanceamento sem afrouxar o teste dele.
- [ ] **Passo 3:** smoke (20 nós, `[0]` é ferro com `node_id` 0) e net PASSAM. Commit
  `Mapa: nós de coleta editáveis com node_id fixo`.

### Tarefa 10: monstros configuráveis e validação dos mapas

**Arquivos:** cenas dos mapas, `tests/unit/test_map_validation.gd`

- [ ] **Passo 1: teste que falha** — `test_map_validation`: em cada cena, todo `EnemySpawn.kind` está em
  `MapData.enemy_kinds()` (mensagem com o caminho do nó); `count >= 0`, `radius >= 0`, `respawn > 0`; no
  máximo 40 `MapGroundPaint` por mapa (Foco 4); landmarks obrigatórios (`camp`, `ruins`, `arena`, `farm`,
  `nest`, `orchard`, `village_spawn`, `portal`, `coach`, `arrive` no vale; `coach`, `arrive` nas regiões) uma
  vez cada; `node_id` únicos em todos os mapas e `kind` em `kinds` (Foco 3); índices de `farm_plot` 0..11,
  `xmas_gift` 0..7 e `xmas_door` 0..5 completos e únicos; tudo dentro de `half`. Mais um teste com uma fixture
  quebrada (id repetido, 41 formas) que confere que a validação acusa.
- [ ] **Passo 2:** agrupar entradas de monstro: só junta num `EnemySpawn` com `count > 1` quando
  `spread(centro, n, raio)` reproduz as posições atuais (tolerância 0,01 m); no resto fica `count = 1`.
  O resumo continua igual à linha de base.
- [ ] **Passo 3:** todos os testes PASSAM. Commit `Mapa: pontos de monstro no Inspector e validação`.

### Tarefa 11: limpeza, guia e versão

- [ ] **Passo 1:** apagar do `world.gd` e do `region_builder.gd` as funções e listas que viraram cena
  (`_build_village`… `_mountain_nature`, `_setup_enemies` (listas), `_bosque/_mina/_pico`, `MOUNTAINS`, `TREE_R`
  se sem uso); tirar os ganchos de gravação e o `tools/bake_maps.gd` (a conversão foi feita); `VillageLayout`
  fica só com regras (paletas, `tint`, tamanhos).
- [ ] **Passo 2:** `docs/EDITOR_MAPA.md`: abrir um mapa, mover/duplicar peças, adicionar casa/árvore/monstro/nó
  de coleta, o que cada campo do Inspector faz, rodar a validação antes do jogo, e que o online usa o mesmo
  arquivo (precisa sair numa versão nova).
- [ ] **Passo 3:** `config/version` +1 patch; rodar tudo do CI (unitários, economia, smoke, ferreiro, NPCs,
  colônia, vila, net, cidade em grupo) — PASSAM; tempo de carregamento ≤ ao de antes.
- [ ] **Passo 4:** commit `Mapa completo editável no editor; versão X`.
