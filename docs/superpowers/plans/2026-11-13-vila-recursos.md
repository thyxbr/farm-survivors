# Aldeões, recursos e mapa vivo — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transformar a Defesa da Cidade numa economia estilo AoE (aldeões, madeira/pedra/ferro/cristal, eras,
pesquisas, munição) com um mapa que recompense explorar (nós de recurso em anéis, covis, eventos, fauna nova) e
duas tropas novas (mago, canhoneiro).

**Architecture:**
- **Tabelas em `ColonyData`.** Fórmulas de produção e de consumo viram funções estáticas de `ColonyData`, para que
  o jogo e a simulação de economia usem a mesma conta.
- **Estado no servidor.** O estoque e o estado novo ficam em `Colony` (autoridade no servidor ou no solo). Os
  sistemas novos ganham arquivos próprios, que pertencem à `Colony`: natureza (nós de recurso), covis, eventos do dia
  e aldeões visuais.
- **Rede.** O mapa é gerado da semente em todos os jogadores. Pela rede só vão o estado leve (`net_state`) e os
  eventos pontuais (`Lobby.city_*`).

**Tech Stack:** Godot 4.7.2, GDScript. Testes headless (`tests/colony_test.gd`, `tests/net_test.gd`, novo `tests/economy_sim.gd`).

**Spec:** `docs/superpowers/specs/2026-11-13-vila-recursos-design.md` (leia junto; as tabelas de números estão lá).

## Global Constraints

- Trabalhar no worktree `C:\Games\godot-3d-vila`, branch `vila-recursos`. Nunca `git stash` no checkout compartilhado.
- Godot: `C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe` (abaixo, `$GODOT`). Rode `$GODOT --headless --path . --import` uma vez antes do primeiro teste.
- Textos de jogo, comentários e mensagens de commit em português, no estilo do código existente.
- Toda tabela de balanceamento fica em `scripts/colony/colony_data.gd`.
- `role` ∈ solo | server | client. Cliente nunca muda estado; ele pede ao servidor via `Lobby.city_request(action, args)`, que cai em `Colony.net_request`.
- Nada roda no headless que seja só visual (`DisplayServer.get_name() == "headless"` → pular).
- O save sobe para `"version": 2`. Save versão 1 precisa carregar (semente 7731, madeira 150, pedra 60, era = nível da prefeitura).
- Testes de rede locais: servidor com `S=$!` e `kill $S`, nunca `taskkill` geral. Use uma `--port` própria por execução.
- No fim, aumentar `config/version` no `project.godot` (0.7.9 → 0.8.0). Se o main avançou de versão, use a próxima livre.

## Review Focus

1. **Cliente pede uma ação sem recurso suficiente** (corrida entre dois jogadores gastando o mesmo cofre): o servidor recusa com o motivo e nada fica negativo. Teste em Task 1.
2. **Construção em cima do lugar de um nó que vai voltar:** o nó não reaparece dentro da construção e tenta de novo no próximo amanhecer. Teste em Task 3.
3. **Fome ou deserção deixam aldeões ocupados > aldeões totais:** a produção cai proporcionalmente, sem número negativo nem divisão por zero, e o "livres" nunca fica negativo. Teste em Task 2.
4. **Estoque de munição zera no meio da noite:** as torres continuam atirando a 50% de cadência, sem estoque negativo, e o aviso aparece uma vez só. Teste em Task 5.
5. **Save antigo (versão 1) carregado depois da atualização:** carrega sem erro, com a semente 7731, estoque inicial de madeira e pedra, e os covis novos. Teste em Task 3.

---

### Task 1: Estoque de recursos e custos com vários recursos

**Files:**
- Modify: `scripts/colony/colony_data.gd` (RESOURCES, custos em dicionário, START_RES)
- Modify: `scripts/colony/colony.gd` (estoque, `cost_of`, `can_place`, `place`, `demolish`, `upgrade`, `repair`, `net_state`/`apply_state`, `to_dict`/`from_dict`)
- Modify: `scripts/ui/colony_hud.gd` (linha de recursos, custo na barra de construção), `scripts/ui/colony_ui.gd` (custos de melhoria e reparo)
- Test: `tests/colony_test.gd`

**Interfaces:**
- Produces:
  - `ColonyData.RESOURCES := ["gold","food","wood","stone","iron","crystal"]`.
  - `ColonyData.RES_NAMES` (Ouro, Comida, Madeira, Pedra, Ferro, Cristal).
  - `ColonyData.START_RES := {"wood":150,"stone":60}`.
  - `ColonyData.COOP_WOOD_PER_PLAYER := 50`.
  - `BUILDINGS[k].cost` passa a ser `Dictionary` (valores da tabela da seção 3 do spec; a prefeitura é `{}`).
  - `ColonyData.scale_cost(c: Dictionary, k: float) -> Dictionary`, que arredonda cada recurso.
  - `ColonyData.coop_cost(kind, owned) -> Dictionary`.
  - `ColonyData.upgrade_cost(kind, level) -> Dictionary`: 80% × nível × custo-base. A melhoria para o nível 3 soma `{"iron": 5}`. A prefeitura é tratada na Task 6.
  - `Colony.res: Dictionary` guarda wood, stone, iron e crystal. Ouro continua em `get_gold()` e comida em `food`.
  - `Colony.amount(r: String) -> int`.
  - `Colony.missing(c: Dictionary) -> String`: devolve `""` quando há o bastante, senão por exemplo `"Faltam 20 de Pedra."`.
  - `Colony.pay(c: Dictionary) -> bool`: confere e paga de forma atômica.
  - `Colony.gain(c: Dictionary, at := Vector3.INF) -> void`: soma ao estoque. Com `at`, mostra o número flutuante.
  - `cost_of(kind) -> Dictionary`, `upgrade_cost(b) -> Dictionary`, `repair_cost(b) -> Dictionary`.
  - `ColonyBuilding.invested` vira `Dictionary`.

- [ ] **Step 1: Escrever os testes que falham** (em `colony_test.gd`, substituindo as checagens de "casa custa 60" e "sem ouro, não constrói")

```gdscript
var w0 := colony.amount("wood")
colony.place("house", Vector3(-12, 0, -6), PI / 2)
check(Game.gold == g0 - 30 and colony.amount("wood") == w0 - 40, "casa custa 30 ouro e 40 madeira")
colony.res["stone"] = 0
check(colony.can_place("market", Vector3(12, 0, 8), 0.0) == "Faltam 20 de Pedra.", "sem pedra, não constrói")
check(not colony.pay({"stone": 5}) and colony.amount("stone") == 0, "pagar sem ter não deixa negativo")
colony.res["stone"] = 2000; colony.res["wood"] = 2000
# demolição: devolve 50% de cada recurso investido
check(Game.gold == g0 + int(wall.invested.gold * 0.5) and colony.amount("stone") == s0 + int(wall.invested.stone * 0.5), "demolir devolve metade de cada recurso")
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `$GODOT --headless --path . res://scenes/colony.tscn -- --colonytest`
Expected: `FAIL  casa custa 30 ouro e 40 madeira` (e as demais novas)

- [ ] **Step 3: Implementar o estoque e os custos**
  - Cada lugar que hoje compara `get_gold() < cost` passa a usar `missing(...)`. Cada `_pay(int)` de construção, melhoria ou reparo passa a usar `pay(dict)`.
  - `net_request` no servidor reconfere com `missing` antes de executar (Review Focus 1).
  - O HUD mostra `Madeira N · Pedra N`. Ferro e cristal só aparecem se `amount > 0`.
  - O custo na barra de construção mostra cada recurso, com vermelho no que falta.
  - O `START_GOLD` fica como está até a Task 12 (balanceamento).

- [ ] **Step 4: Rede e save**
  - Em `net_state()`, adicione a chave `"res": res`.
  - Em `apply_state`, leia essa chave.
  - Em `to_dict()`, adicione `"version": 2` e `"res"`.
  - Em `from_dict`, sem `"res"`, use `START_RES`. Um `invested` inteiro (save antigo) vira `{"gold": n}`.

- [ ] **Step 5: Rodar o teste**

Run: `$GODOT --headless --path . res://scenes/colony.tscn -- --colonytest`
Expected: `OK — 0 falha(s)`

- [ ] **Step 6: Commit** — `git commit -am "Cidade: estoque de madeira, pedra, ferro e cristal; custos com vários recursos"`

---

### Task 2: Aldeões livres e ocupados, treino na prefeitura

**Files:**
- Modify: `scripts/colony/colony_data.gd`:
  - `crew` em BUILDINGS: farm 2, market 2, lumber_camp 3, quarry 3, barracks 1, as três torres 1.
  - remover `workers` e `GROWTH`;
  - `VILLAGER_COST := {"food": 40}`, `VILLAGER_TIME := 8.0`.
- Modify: `scripts/colony/colony.gd` (`busy()`, `free_villagers()`, `crew_eff(b)`, fila de treino, `dawn`, `forecast`, `can_place`)
- Modify: `scripts/colony/building.gd` (`tower_rate` usa `colony.crew_eff(self)`)
- Modify: `scripts/ui/colony_ui.gd` (botão "Treinar aldeão" na janela da prefeitura, com fila e barra de progresso)
- Test: `tests/colony_test.gd`

**Interfaces:**
- Produces:
  - `Colony.busy() -> int`: soma de `crew` das construções vivas.
  - `Colony.free_villagers() -> int`: `maxi(0, citizens - busy())`.
  - `Colony.staffing() -> float`: `clampf(citizens / busy, 0, 1)`; vale 1 quando `busy == 0`.
  - `Colony.crew_eff(b) -> float`: igual a `staffing()`, aplicado à construção.
  - `Colony.train_villager() -> String`: `""` = entrou na fila.
  - `Colony.train_queue: int` e `Colony.train_t: float` (no `net_state` como `"tq"` e `"tt"`).
  - `ColonyData.tower_rate_mult(eff: float) -> float`: devolve `1.0` se `eff >= 1`, senão `1.5`. É multiplicado no intervalo entre disparos.
  - `net_request` ganha a ação `"train"`.

- [ ] **Step 1: Testes que falham**

```gdscript
var free0 := colony.free_villagers()
colony.place("farm", Vector3(-14, 0, 8), 0.0)
check(colony.free_villagers() == free0 - 2, "fazenda ocupa 2 aldeões")
colony.citizens = colony.busy() + 1
check(colony.can_place("market", Vector3(12, 0, 8), 0.0) == "Faltam 1 aldeão livre.", "sem aldeões livres, não constrói")
var c0 := colony.citizens; var food0 := colony.food
check(colony.train_villager() == "" and colony.food == food0 - ColonyData.VILLAGER_COST.food, "treinar aldeão custa comida")
await wait(ColonyData.VILLAGER_TIME + 0.5)
check(colony.citizens == c0 + 1, "aldeão treinado em 8 s")
colony.citizens = colony.pop_cap()
check(colony.train_villager() != "", "sem moradia, não treina")
# Review Focus 3: fome deixa ocupados > aldeões
colony.citizens = 1
check(colony.free_villagers() == 0 and colony.staffing() > 0.0 and colony.staffing() < 1.0, "falta de aldeões reduz produção sem ficar negativo")
check(colony.forecast().food_in >= 0, "previsão nunca negativa")
# dawn: sem crescimento automático
var cz := colony.citizens; colony.dawn()
check(colony.citizens == cz, "aldeões não nascem sozinhos no amanhecer")
```

- [ ] **Step 2: Rodar e ver falhar** — mesmo comando; esperado FAIL em "fazenda ocupa 2 aldeões".

- [ ] **Step 3: Implementar**
  - `forecast` troca `eff` por `staffing()`.
  - `dawn` remove o bloco `growth` e o relatório perde `growth`. Os refugiados do co-op continuam somando `citizens`.
  - A fila avança em `_physics_process` só no servidor ou no solo, e só de dia. Quando a era sobe (Task 6), a fila pausa.
  - `recruit` passa a exigir `free_villagers() >= 1`, além de `citizens >= 1`.
  - A mensagem de falta é `"Faltam %d aldeão livre."` ou `"Faltam %d aldeões livres."`.

- [ ] **Step 4: Rodar o teste** — `OK — 0 falha(s)`.
- [ ] **Step 5: Commit** — `"Cidade: aldeões ocupados pelas construções e treino na prefeitura"`

---

### Task 3: Semente aleatória no solo, nós de recurso e coleta pelo jogador

**Files:**
- Create: `scripts/colony/nature.gd`: `class_name ColonyNature extends Node3D`. Gera os nós, guarda o que está esgotado, cuida da volta, do save e da rede.
- Create: `scripts/colony/resource_node.gd`: `class_name ColonyResourceNode extends Node3D`. Visual, colisão e `hit()`.
- Modify: `scripts/colony/colony_world.gd`:
  - `_scatter_nature` passa a delegar para `ColonyNature.generate`;
  - a semente: um solo novo sorteia `randi()`; um solo carregado lê `"seed"` do save, com padrão 7731; `--colonytest` e `--colonydemo` usam 7731.
- Modify: `scripts/colony/colony_data.gd`: `NODES`, `RINGS`, `REGROW_DAYS`.
- Modify: `scripts/player/player.gd` (o laço de golpe também acerta o grupo `harvest`)
- Modify: `scripts/autoload/lobby.gd`: `city_hit_node(id)` do cliente para o servidor; `city_node_state(id, alive)` do servidor para os clientes.
- Modify: `scripts/colony/colony.gd` (`nature` como referência, `to_dict`/`from_dict` com `"seed"` e `"nodes"`, `dawn` chama `nature.regrow(day)`, `net_full` inclui os esgotados)
- Test: `tests/colony_test.gd`

**Interfaces:**
- Produces:
  - `ColonyData.NODES`, uma entrada por tipo de nó:

    | Tipo | Recurso | Golpes | Total |
    |---|---|---|---|
    | `tree` | wood | 4 | 24 |
    | `rock` | stone | 5 | 25 |
    | `iron` | iron | 6 | 12 |
    | `gold` | gold | 6 | 60 |
    | `crystal` | crystal | 6 | 8 |
    | `berry` | food | 1 | 12 |

  - `ColonyData.RINGS := [52.0, 80.0, 105.0]`.
  - `ColonyData.REGROW_DAYS := {"tree":2,"berry":2,"rock":4,"iron":4,"gold":4,"crystal":4}`.
  - `ColonyNature.generate(rng: RandomNumberGenerator, colony: Colony) -> void`:
    - mantém a ordem atual de bosques e soltos, dando ids `0..N`;
    - depois põe veios de ferro (7), de ouro (4) e arbustos (10) no anel 2, e cristais (6) no anel 3, sempre longe dos obstáculos;
    - chama `colony.obstacles.append` para cada nó.
  - `ColonyNature.node(id) -> ColonyResourceNode`.
  - `ColonyNature.deplete(id, day: int)`.
  - `ColonyNature.regrow(day: int)`: só restaura se `colony.can_place`-style não sobrepuser uma construção. Para isso usa o novo `Colony.building_at(p: Vector2, r: float) -> bool`.
  - `ColonyNature.alive_near(kind: String, p: Vector3, r: float) -> Array[int]`.
  - `ColonyNature.nearest(kind: String, p: Vector3) -> ColonyResourceNode`: o nó vivo mais próximo.
  - `ColonyNature.count(kind: String) -> int`: quantos nós desse tipo existem, vivos ou não.
  - `ColonyNature.add_rich(kind: String, pos: Vector3, total: int) -> int`: cria um nó rico e devolve o id (usado nas Tasks 8 e 9).
  - `ColonyNature.to_dict() -> Dictionary` (`{id: dia_que_volta}`) e `from_dict(d)`.
  - `ColonyResourceNode`: `id: int`, `kind: String`, `hits_left: int`, `alive: bool`, `hit(from: Vector3) -> void`, `set_alive(on: bool, fx := true)`.
    - Fica no grupo `harvest`. **Não** entra em `enemies`.
    - Quando esgota: some, perde a colisão e é retirado de `colony.obstacles`. A posição do obstáculo fica guardada no nó, para ele voltar a ser obstáculo quando reaparecer.
  - `Colony.harvest(id: int, at: Vector3) -> void`:
    - roda no servidor ou no solo;
    - entrega `total / golpes`, multiplicado pelos bônus de pesquisa da Task 6 (por ora 1.0), através de `gain`;
    - no último golpe chama `deplete`.

- [ ] **Step 1: Testes que falham**

```gdscript
check(world.map_seed == 7731, "teste usa semente fixa")
var tree := colony.nature.nearest("tree", player.global_position)
var w0 := colony.amount("wood")
for i in 4: colony.harvest(tree.id, player.global_position)
check(colony.amount("wood") == w0 + 24 and not tree.alive, "árvore dá 24 madeira em 4 golpes e cai")
check(not _obstacle_at(tree.global_position), "árvore caída sai dos obstáculos")
colony.day += 2; colony.nature.regrow(colony.day)
check(tree.alive and _obstacle_at(tree.global_position), "árvore volta em 2 dias")
# Review Focus 2: construção em cima do lugar
for i in 4: colony.harvest(tree.id, player.global_position)
colony.place("wall", tree.global_position, 0.0, true)   # free; testa só sobreposição
colony.day += 2; colony.nature.regrow(colony.day)
check(not tree.alive, "nó não volta dentro de uma construção")
check(colony.nature.count("crystal") == 6 and colony.nature.count("iron") == 7, "anéis externos têm cristal e ferro")
var cr := colony.nature.nearest("crystal", Vector3.ZERO)
check(Vector2(cr.global_position.x, cr.global_position.z).length() >= 105.0, "cristal só no anel 3")
# Review Focus 5: save versão 1
var old := colony.to_dict(); old.erase("seed"); old.erase("res"); old.erase("nodes"); old["version"] = 1
_write_save(old); Game.start_colony(true); await wait(1.0); _bind()
check(world.map_seed == 7731 and colony.amount("wood") == 150, "save antigo carrega com semente 7731 e madeira inicial")
```

  Helpers do teste: `_obstacle_at(p)` procura em `colony.obstacles` a menos de 0,1 m; `_write_save(d)` grava o JSON em `Game.colony_save_path`.

- [ ] **Step 2: Rodar e ver falhar.**

- [ ] **Step 3: Implementar a natureza e o golpe**
  - Visual dos nós: árvore e pedra reaproveitam `tree_pine`, `tree_oak` e `rock` (como o `_prop` de hoje).
  - Veio de ferro: `rock` com material ferrugem (`Color(0.55,0.3,0.2)`) e pontos escuros.
  - Veio de ouro: `rock` com cristais amarelos emissivos pequenos.
  - Cristal: 3 a 5 prismas (`CylinderMesh` de 6 lados) azul-violeta emissivos, mais uma `OmniLight3D` fraca (só fora do headless).
  - Arbusto: `bush_berry.glb`.
  - Golpe do jogador: depois do laço de `enemies` em `player.gd` (~linha 479), percorra `harvest` com o mesmo alcance e cone. No solo chame `colony.harvest`; no cliente, `Lobby.city_hit_node(id)`.
  - Com `ColonyNature.HIT_COOLDOWN := 0.25` por nó, um golpe só tira 1 pedaço mesmo acertando duas vezes.

- [ ] **Step 4: Semente e save**
  - `colony_world._ready` decide `map_seed` **antes** de `rng.seed`.
  - Com `Game.loading_colony` (ou a flag que já existe para carregar), use `_read_colony_save().get("seed", 7731)`.

- [ ] **Step 5: Rodar o teste** — `OK — 0 falha(s)`.
- [ ] **Step 6: Commit** — `"Cidade: mapa aleatório no solo e nós de recurso coletáveis em anéis"`

---

### Task 4: Serraria e pedreira com produção contínua

**Files:**
- Modify: `scripts/colony/colony_data.gd`:
  - BUILDINGS `lumber_camp` (Serraria) e `quarry` (Pedreira), com `size` de `Vector2(5.0, 4.0)`, hp 300, `crew` 3, `gather: "tree"`/`"rock"`, `reach: 14.0`, `max_dist: 80.0`, `min_nodes: 4`;
  - entrar no `ORDER` depois de `farm`;
  - `GATHER_RATE := 1.0 / 6.0`: unidades por aldeão por segundo, com o bosque cheio;
  - `GATHER_FULL := 8`: com 8 ou mais nós vivos no raio, a produção é 100%; abaixo disso, é proporcional;
  - `ColonyData.gather_rate(crew_eff: float, live: int, tech_mult: float) -> float`.
- Modify: `scripts/colony/colony.gd`:
  - `can_place` permite esses dois tipos fora de `CITY_RADIUS`, até `max_dist`, desde que haja `min_nodes` nós no raio;
  - tique de produção a cada 3 s, de dia, no servidor ou no solo, usando um acumulador fracionário por construção;
  - a cada `NODE_YIELD_CAMP := 24` unidades produzidas, esgota o nó vivo mais próximo do raio.
- Modify: `scripts/colony/building_visuals.gd`:
  - `_lumber_camp(r, level)`: galpão de `_box` e `_cyl`, pilha de toras e `crate`;
  - `_quarry(r, level)`: blocos de pedra, carrinho e `barrel`;
  - sem `.glb` novo.
- Modify: `scripts/ui/colony_hud.gd` (a previsão mostra madeira e pedra por minuto)
- Test: `tests/colony_test.gd`

**Interfaces:**
- Consumes: `ColonyNature.alive_near`, `ColonyNature.deplete`, `Colony.crew_eff`.
- Produces:
  - `Colony.gather_per_min() -> Dictionary` (`{"wood": x, "stone": y}`), usado pelo HUD e pelo `forecast`.
  - `ColonyData.gather_rate` é usado pelo `economy_sim` (Task 12).

- [ ] **Step 1: Testes que falham**

```gdscript
var spot := _grove_spot()   # ponto a ~60 m com >= 4 árvores a 14 m
check(colony.can_place("lumber_camp", spot, 0.0) == "", "serraria pode ficar fora da cidade perto do bosque")
check(colony.can_place("lumber_camp", Vector3(0, 0, 20), 0.0) != "", "serraria longe de árvores é recusada")
check(colony.can_place("lumber_camp", spot * 1.6, 0.0) != "", "serraria além de 80 m é recusada")
var camp := colony.place("lumber_camp", spot, 0.0)
var w0 := colony.amount("wood"); var live0 := colony.nature.alive_near("tree", spot, 14.0).size()
await wait(30.0)
check(colony.amount("wood") > w0 + 10, "serraria produz madeira de dia (%d)" % (colony.amount("wood") - w0))
check(colony.nature.alive_near("tree", spot, 14.0).size() <= live0, "serraria consome o bosque")
check(ColonyData.gather_rate(1.0, 2, 1.0) < ColonyData.gather_rate(1.0, 8, 1.0), "bosque ralo produz menos")
```

  Para não esperar 30 s, use o `Engine.time_scale = 4.0` em volta da espera, como o teste já faz em outros pontos (ou chame `colony._gather_tick(30.0)` se o tique estiver separado).

- [ ] **Step 2–4:** rodar e ver falhar, implementar, rodar e ver passar.
- [ ] **Step 5: Commit** — `"Cidade: serraria e pedreira produzem do bosque e das pedras em volta"`

---

### Task 5: Munição das torres e das tropas à distância

**Files:**
- Modify: `scripts/colony/colony_data.gd`:
  - `AMMO := {"archer_tower": ["wood", 5], "cannon_tower": ["stone", 2], "mage_tower": ["crystal", 15], "archer": ["wood", 8], "mage": ["crystal", 20], "cannoneer": ["stone", 3]}`: o recurso e quantos disparos rende 1 unidade;
  - `NO_AMMO_RATE := 2.0`: multiplicador do intervalo, ou seja, metade da cadência.
- Modify: `scripts/colony/colony.gd`:
  - `use_ammo(who: String) -> bool`: devolve `false` quando falta;
  - um acumulador fracionário por recurso, `_ammo_acc`;
  - `night_ammo: Dictionary`, gasto da noite, que vai para o `last_report`;
  - `_ammo_warned: Dictionary` e um aviso por recurso por noite.
- Modify: `scripts/colony/building.gd` (~linha 340, ao disparar: `_cd = tower_rate() * (1.0 if colony.use_ammo(kind) else ColonyData.NO_AMMO_RATE) * ColonyData.tower_rate_mult(colony.crew_eff(self))`)
- Modify: `scripts/colony/soldier.gd` (o disparo à distância chama `colony.use_ammo(unit)` e o intervalo dobra sem munição)
- Modify: `scripts/ui/colony_ui.gd` (o relatório do amanhecer mostra a munição gasta), `colony_hud.gd` (o recurso em falta pisca)
- Test: `tests/colony_test.gd`

**Interfaces:**
- Consumes: `Colony.res`, `Colony.crew_eff`.
- Produces:
  - `Colony.use_ammo(who: String) -> bool`;
  - `ColonyData.ammo_per_night(kind: String, shots: float, tech_mult: float) -> float`, usado pela simulação.

- [ ] **Step 1: Testes que falham**

```gdscript
colony.res["wood"] = 10
for i in 10: colony.use_ammo("archer_tower")
check(colony.amount("wood") == 8, "10 flechas gastam 2 madeira")
colony.res["wood"] = 0
check(not colony.use_ammo("archer_tower") and colony.amount("wood") == 0, "sem madeira não fica negativo")
var t := colony.place("archer_tower", Vector3(8, 0, 14), 0.0, true)
var e := colony.spawn_enemy("slime", Vector3(8, 0, 30)); var hp0 := e.hp
await wait(3.0)
check(not is_instance_valid(e) or e.hp < hp0, "torre sem munição continua atirando (mais devagar)")
check(colony.say_count("Acabaram as flechas") == 1, "aviso de munição aparece uma vez")
```

  `say_count(prefix)` é um contador só de teste. Adicione `var _said: Array[String]` em `say()` quando `OS.has_feature("debug")`, ou intercepte `Game.notify` no teste.

- [ ] **Step 2–4:** rodar e ver falhar, implementar, rodar e ver passar.
- [ ] **Step 5: Commit** — `"Cidade: torres e atiradores gastam munição do estoque"`

---

### Task 6: Eras da prefeitura e pesquisas

**Decisão:** **a era é o nível da prefeitura** (1 = Aldeia, 2 = Vila, 3 = Cidade).
- "Avançar de era" é a melhoria da prefeitura, com o custo e os requisitos da tabela da seção 16 do spec, e leva 30 s.
- A regra que já existe ("nível da construção ≤ nível da prefeitura + 1") passa a ser "nível ≤ era".
- `needs_level` vira `needs_era`.
- Torre de Canhão e Torre Arcana exigem a era 2.

**Files:**
- Modify: `scripts/colony/colony_data.gd`:
  - `ERAS` (nome, custo, `requires` como `{"lumber_camp":1,"quarry":1}` ou `{"barracks_level":2}`);
  - `ERA_TIME := 30.0`, `TECH_TIME := 20.0`;
  - `TECHS` (as 11 da seção 17 do spec, com `era`, `at`, `cost`, `fx: {"mult_key": valor}`);
  - `ColonyData.era_cost(era: int, players: int) -> Dictionary`: multiplica por `1 + 0.35 * (players - 1)`.
- Modify: `scripts/colony/colony.gd`:
  - `era() -> int`;
  - `advance_era() -> String`;
  - `research(tech: String) -> String`;
  - `techs: Dictionary` (as compradas);
  - `busy_t: Dictionary`, que guarda a ação em andamento por construção (`net_id -> [ação, t]`);
  - `mult(key: String) -> float`: o produto dos `fx` das pesquisas compradas.
- Modify, nos pontos onde o número já é calculado:
  - `building.gd`: dano, vida máxima, explosão, saltos;
  - `soldier.gd`: dano e vida;
  - `colony.gd`: `harvest`, `gather_rate`, `forecast` (comida), `use_ammo`.
- Modify: `scripts/ui/colony_ui.gd`:
  - janela da prefeitura: "Avançar para a era II/III", com os requisitos que faltam em vermelho;
  - janela de cada construção: a lista de pesquisas daquela construção (comprada, bloqueada pela era, ou com preço).
- Modify: `scripts/autoload/lobby.gd`: as ações `"era"` e `"tech"` em `net_request`. `techs` e `busy_t` entram no `net_state`.
- Test: `tests/colony_test.gd`

**Interfaces:**
- Chaves de `fx` (o `mult(key)` lê estas):
  - `wood`, `stone`, `food`: produção;
  - `arrow_dmg`;
  - `bld_hp`, `wall_hp`;
  - `ammo_wood`, `ammo_stone`, `ammo_crystal`: multiplicador de consumo;
  - `splash`;
  - `chain_add`: aditivo, lido por `bonus("chain_add") -> int`;
  - `unit_hp`, `unit_dmg`.
- Produces: `Colony.era()`, `Colony.mult(key)`, `Colony.bonus(key)`, `Colony.has_tech(t)`, `ColonyData.TECHS`, `ColonyData.ERAS`.

- [ ] **Step 1: Testes que falham**

```gdscript
check(colony.era() == 1 and colony.advance_era().begins_with("Exige"), "era II exige serraria e pedreira")
check(colony.can_place("cannon_tower", Vector3(14, 0, 14), 0.0).contains("era"), "torre de canhão exige era II")
# com serraria (Task 4) e pedreira colocadas e recursos de sobra:
check(colony.advance_era() == "", "avança para a era II")
await wait(ColonyData.ERA_TIME + 0.5)
check(colony.era() == 2 and colony.hall.level == 2, "era II = prefeitura nível 2")
var r0 := ColonyData.gather_rate(1.0, 8, colony.mult("wood"))
check(colony.research("sharp_axe") == "", "pesquisa Machado Afiado")
await wait(ColonyData.TECH_TIME + 0.5)
check(is_equal_approx(ColonyData.gather_rate(1.0, 8, colony.mult("wood")), r0 * 1.2), "Machado Afiado dá +20% madeira")
check(colony.research("sharp_axe") != "", "pesquisa não se compra duas vezes")
check(colony.research("arcane_focus").contains("era"), "pesquisa da era III bloqueada na era II")
```

- [ ] **Step 2–4:** rodar e ver falhar, implementar, rodar e ver passar. Atualize também o check antigo `colony.recruit("knight") != ""`, que agora vale por exigir a era 2.
- [ ] **Step 5: Commit** — `"Cidade: eras da prefeitura e pesquisas"`

---

### Task 7: Fauna nova (lobo e urso) por anel

**Files:**
- Modify: `scripts/colony/colony_data.gd`:
  - `ANIMALS.wolf`: Lobo, hp 45, speed 7.6, food 4, gold 6, radius 0.45, damage 8, aggressive, `pack: [3,4]`, ring 2.
  - `ANIMALS.bear`: Urso, hp 260, speed 5.2, food 30, gold 28, radius 0.9, damage 22, aggressive, ring 3.
  - `ring` nos animais existentes: coelho, cervo e javali = 1, javali também no 2.
- Modify: `scripts/colony/animal.gd`: `_build_wolf()` e `_build_bear()` com as mesmas peças procedurais de `_build_boar`. O lobo é cinza e mais baixo; o urso é marrom, grande, com ombros altos.
- Modify: `scripts/colony/colony.gd`: `_spawn_wildlife` escolhe o anel e depois a espécie daquele anel; `_wild_point(min, max)` ganha um raio máximo.
- Test: `tests/colony_test.gd`

- [ ] **Step 1: Testes que falham**

```gdscript
colony._spawn_wildlife(true)
var kinds := {}
for a in get_tree().get_nodes_in_group("animals"): kinds[a.kind] = Vector2(a.global_position.x, a.global_position.z).length()
check(kinds.has("wolf") or kinds.has("bear"), "fauna nova aparece")
for a in get_tree().get_nodes_in_group("animals"):
    if a.kind == "bear": check(Vector2(a.global_position.x, a.global_position.z).length() >= 105.0, "urso só no anel 3")
```

  Para esse teste ficar determinístico, `_spawn_wildlife` aceita `want_override := -1`. O teste pede 40 animais.

- [ ] **Step 2–4:** rodar e ver falhar, implementar, rodar e ver passar.
- [ ] **Step 5: Commit** — `"Cidade: lobos e ursos nos anéis distantes"`

---

### Task 8: Covis (pontos de interesse)

**Files:**
- Create: `scripts/colony/den.gd`: `class_name ColonyDen extends Node3D`.
- Modify: `scripts/colony/colony_data.gd`:
  - `POIS`: `goblin_camp`, `slime_nest`, `haunted_ruins`, cada um com `name`, `ring`, `props` (lista de `[modelo, offset, yaw]`), `guards` (`[[tipo, n_base]]`), `boss`, `boss_affix`, `reward: {"wood","stone","iron","crystal","gold"}` e `deposit` (tipo de nó rico + quantidade);
  - `DEN_WAKE := 45.0`, `DEN_LEASH := 25.0`, `DEN_GROW_DAYS := 3`, `DEN_WAVE_BONUS := 0.15`.
- Modify: `scripts/colony/nature.gd`: depois dos nós, `generate` posiciona de 4 a 6 covis (`rng`), cada um numa direção diferente de `DIR_NAMES`. O anel vem da tabela. Os acampamentos e ninhos ficam no anel 2, as ruínas no 3.
- Modify: `scripts/colony/colony.gd`:
  - `dens: Array[ColonyDen]`;
  - `start_night` força as direções dos covis vivos em `wave_dirs` e soma `DEN_WAVE_BONUS * den.level` ao orçamento daquela direção (veja `_build_wave`/`_fill_wave`; o orçamento extra passa pelo `WAVE_CAP` como o resto);
  - no entardecer, `den.sleep()`;
  - no amanhecer, `den.dawn(day)` (cresce a cada 3 dias e repõe os guardas).
- Modify: `scripts/enemies/enemy.gd`: `var den_id := -1`. Com `den_id >= 0`, o inimigo volta ao covil quando se afasta mais de `DEN_LEASH` do centro.
- Modify: `scripts/autoload/lobby.gd`: `city_den_state(id, level, cleared)`. Os guardas usam o fluxo de inimigos que já existe.
- Test: `tests/colony_test.gd`

**Interfaces:**
- Produces:
  - `ColonyDen`: `id`, `kind`, `level`, `cleared`, `awake`, `dir_index`, `wake()`, `sleep()`, `dawn(day)`, `on_boss_killed()`, `to_dict()`, `from_dict()`.
  - `Colony.den_dirs() -> Dictionary` (`{dir_index: level}` dos covis vivos).
  - Quando o covil é limpo:
    - cada jogador ganha `night_reward(day)` pelo mesmo caminho de `Lobby.city_night_survived` (no solo, `Game.add_gold`/XP);
    - a cidade ganha `gain(reward)`;
    - aparece um nó rico: `ColonyNature.add_rich(kind, pos, total)`, com um id acima dos gerados, que vai no save.

- [ ] **Step 1: Testes que falham**

```gdscript
check(colony.dens.size() >= 4, "o mapa tem covis (%d)" % colony.dens.size())
var den: ColonyDen = colony.dens[0]
player.global_position = den.global_position + Vector3(30, 0.5, 0)
await wait(1.0)
check(den.awake and den.guards_alive() > 0, "covil acorda com jogador perto")
player.global_position = Vector3(0, 0.5, 14); await wait(1.0)
check(not den.awake and den.guards_alive() == 0, "covil dorme sem ninguém perto")
check(colony.den_dirs().has(den.dir_index), "covil de pé entra na onda")
colony.start_night()
check(den.dir_index in colony.wave_dirs, "direção do covil é forçada na onda")
# fim da noite como no teste existente...
den.dawn(colony.day + 3)
check(den.level == 2, "covil cresce a cada 3 dias")
var s0 := colony.amount("stone"); den.on_boss_killed()
check(den.cleared and colony.amount("stone") > s0 and not colony.den_dirs().has(den.dir_index), "limpar o covil dá recursos e fecha a direção")
colony.phase = "night"
player.global_position = colony.dens[1].global_position + Vector3(20, 0.5, 0)
await wait(1.0)
check(not colony.dens[1].awake, "covis dormem à noite")
```

- [ ] **Step 2–4:** rodar e ver falhar, implementar, rodar e ver passar.
- [ ] **Step 5: Commit** — `"Cidade: covis de monstros que crescem e reforçam as ondas"`

---

### Task 9: Eventos aleatórios do dia e marcador de direção

**Files:**
- Create: `scripts/colony/day_events.gd`: `class_name ColonyEvents extends Node`.
- Create: `scripts/colony/caravan.gd`: o NPC da caravana (`merchant.glb`), no grupo `interactable`; ao interagir abre a janela de troca.
- Modify: `scripts/colony/colony_data.gd`:
  - `DAY_EVENTS`: `caravan`, `lost_villagers`, `meteor`, `alpha`, `camp_raid`, `lost_chest`, cada um com `name`, `weight`, `min_day` e `needs` (por exemplo `camp_raid` precisa de uma serraria ou pedreira a mais de `CITY_RADIUS`);
  - `EVENT_CHANCE := 0.6`, `EVENT_MIN_DAY := 2`;
  - `TRADES`: a caravana troca `[[{"wood":50},{"gold":30}], [{"gold":40},{"iron":5}], [{"gold":80},{"crystal":3}], [{"stone":60},{"gold":35}]]`.
- Modify: `scripts/colony/colony.gd`:
  - `events: ColonyEvents`;
  - `dawn` chama `events.roll(day)`;
  - o entardecer chama `events.end()`;
  - a ação `"trade"` no `net_request`.
- Modify: `scripts/ui/colony_hud.gd`: um indicador na borda da tela aponta para o evento ativo, com o nome e a distância. Antes, procure se o HUD já tem bússola ou minimapa (`grep -n "compass\|minimap" scripts/ui/*.gd`); se tiver, use. No co-op o indicador também aponta os covis que um jogador já viu.
- Modify: `scripts/ui/colony_ui.gd`: a janela de troca, que reusa o estilo das janelas de construção.
- Modify: `scripts/autoload/lobby.gd`: `city_event(kind, x, z, active)`.
- Test: `tests/colony_test.gd`

**Interfaces:**
- Produces:
  - `ColonyEvents.roll(day: int, force := "") -> String`: devolve o evento sorteado ou `""`.
  - `ColonyEvents.active: String` e `ColonyEvents.pos: Vector3`.
  - `ColonyEvents.end()`.
  - `ColonyEvents.complete(kind)`, chamado ao resgatar os aldeões, ao abrir o baú e assim por diante.
  - `Colony.trade(i: int) -> String`.
- Comportamento de cada evento (`spawn` no servidor):
  - **caravan**: põe a caravana num ponto do anel 1–2.
  - **lost_villagers**: põe 3 aldeões (modelo `elder`) e uma matilha de lobos. Quando os lobos morrem e um jogador interage, soma `mini(room, 2 + day / 4)` aos aldeões; o que sobrar vira comida (10 por aldeão).
  - **meteor**: faz o efeito (`FX.burst` + `FX.ring` grandes e um som), cria 3 nós ricos de cristal (`add_rich`) e põe 4 slimes.
  - **alpha**: cria um `boar` ou `bear` com escala 1.5, vida ×3 e recompensa ×3.
  - **camp_raid**: põe `3 + day / 3` monstros a 20 m da serraria ou pedreira mais distante, com `_siege_target` = ela.
  - **lost_chest**: põe um baú (`chest.glb`, `interactable`) e 3 errantes. Ao abrir, dá `gain({"gold": 40 + 10*day, "wood": 60, "stone": 40})`.

- [ ] **Step 1: Testes que falham**

```gdscript
check(colony.events.roll(1) == "", "nenhum evento no dia 1")
check(colony.events.roll(3, "caravan") == "caravan" and colony.events.active == "caravan", "caravana chega")
colony.res["wood"] = 100; var g0 := colony.get_gold()
check(colony.trade(0) == "" and colony.amount("wood") == 50 and colony.get_gold() == g0 + 30, "troca 50 madeira por 30 ouro")
colony.res["wood"] = 10
check(colony.trade(0) != "", "troca sem recurso é recusada")
colony.events.end()
check(colony.events.active == "" and get_tree().get_nodes_in_group("caravan").is_empty(), "evento acaba ao anoitecer")
check(colony.events.roll(3, "camp_raid") == "", "ataque à serraria só com serraria fora da cidade")
colony.events.roll(3, "meteor")
check(colony.nature.count("crystal") >= 9, "meteoro deixa cristais")
```

- [ ] **Step 2–4:** rodar e ver falhar, implementar, rodar e ver passar.
- [ ] **Step 5: Commit** — `"Cidade: eventos aleatórios durante o dia"`

---

### Task 10: Mago e canhoneiro

**Files:**
- Modify: `scripts/colony/colony_data.gd`. Os custos de `UNITS` viram dicionário:

  | Unidade | Custo | Salário | Notas |
  |---|---|---|---|
  | militia | gold 30, food 20 | | |
  | soldier | gold 50, food 30, wood 10 | | |
  | archer | gold 50, wood 40 | | |
  | knight | gold 150, food 40, iron 10 | | `needs_era: 2` |
  | mage | gold 120, crystal 6 | 10 | `needs_era: 2`, hp 75, damage 14, reach 14, cooldown 1.6, `ranged`, `chain: 1`, `slow: 1.5`, `shot: "bolt"` |
  | cannoneer | gold 140, iron 8, stone 20 | 11 | `needs_era: 2`, hp 110, damage 34, reach 17, cooldown 3.0, `ranged`, `splash: 2.6`, `shot: "ball"` |

  - A aparência usa itens que existem no `item_db`. Rode `grep -n "staff\|robe\|cajado\|manto" scripts/autoload/item_db.gd`; sem cajado, use a arma mágica mais próxima.
  - `UNIT_ORDER` ganha os dois.
- Modify: `scripts/colony/soldier.gd`: o disparo à distância usa `data.get("shot","arrow")` e chama o mesmo caminho de projétil das torres (`tower_shot.gd`/`Lobby.city_shot`), passando `splash`, `chain` e `slow`.
- Modify: `scripts/colony/colony.gd`: `recruit` usa `missing`/`pay` e `needs_era`.
- Test: `tests/colony_test.gd`

- [ ] **Step 1: Testes que falham**

```gdscript
check(colony.recruit("mage").contains("era"), "mago exige era II")
# após era II (Task 6):
colony.res["crystal"] = 0
check(colony.recruit("mage") == "Faltam 6 de Cristal.", "mago custa cristal")
colony.res["crystal"] = 20; colony.res["iron"] = 20
check(colony.recruit("mage") == "" and colony.recruit("cannoneer") == "", "recruta mago e canhoneiro")
var e := colony.spawn_enemy("slime", colony.rally + Vector3(0, 0, 10)); var hp0 := e.hp
await wait(4.0)
check(not is_instance_valid(e) or e.hp < hp0, "tropas à distância novas acertam monstros")
```

- [ ] **Step 2–4:** rodar e ver falhar, implementar, rodar e ver passar.
- [ ] **Step 5: Commit** — `"Cidade: mago e canhoneiro no quartel"`

---

### Task 11: Aldeões visuais

**Files:**
- Create: `scripts/colony/villager_visual.gd`: `class_name ColonyVillager extends Node3D`, só no cliente. É um boneco simples feito com as peças procedurais (corpo `_box`, cabeça `_sphere`, ferramenta), que anda entre a porta e um alvo, faz um gesto de trabalho por 3 s e volta.
- Modify: `scripts/colony/building.gd`:
  - fora do headless, cria `mini(crew efetivo, crew)` aldeões filhos;
  - recria quando `colony.staffing()` muda de faixa;
  - à noite, eles ficam ocultos (`visible = false`).
- O alvo depende da construção:
  - serraria e pedreira: o nó vivo mais próximo (`alive_near`);
  - fazenda: um ponto aleatório dentro da pegada;
  - mercado: as bancas;
  - torre: fica parado ao pé dela.
- Test: manual (visual). O headless garante que nada é criado: no `colony_test` (headless), `check(get_tree().get_nodes_in_group("villager_visual").is_empty(), "aldeões visuais não existem no headless")`.

- [ ] **Step 1:** escrever o check e rodar (ele passa trivialmente; serve de guarda).
- [ ] **Step 2:** implementar.
- [ ] **Step 3:** abrir o jogo (`$GODOT --path . res://scenes/colony.tscn -- --colonydemo`), tirar um screenshot e conferir os bonecos andando até as árvores. Rodar `colony_test`: `OK`.
- [ ] **Step 4: Commit** — `"Cidade: aldeões visuais trabalhando nas construções"`

---

### Task 12: Simulação de economia, balanceamento, rede e smoke-check

**Files:**
- Create: `tests/economy_sim.gd` (`extends SceneTree`, roda com `--script`), que usa só funções estáticas de `ColonyData`.
- Modify: `scripts/colony/colony_data.gd`: os números que a simulação mandar mudar (custos, `START_GOLD`, `GATHER_RATE`, `AMMO`, `ERAS`, `TECHS`).
- Modify: `tests/net_test.gd`, na parte da cidade: o cliente coleta uma árvore, o servidor confirma e os dois clientes veem a madeira subir e o nó esgotado.
- Modify: `.github/workflows/*.yml`: um passo `timeout 120 godot --headless --path . --script res://tests/economy_sim.gd`.
- Modify: `project.godot`: `config/version="0.8.0"`.
- Modify: `.claude/skills/smoke-check` (se existir no repo), para incluir `economy_sim`.

**Interfaces:**
- Consumes: `ColonyData.gather_rate`, `ColonyData.ammo_per_night`, `ColonyData.era_cost`, `ColonyData.coop_cost`, `ColonyData.TECHS`, `NODES`, `BUILDINGS`, `UNITS`, `TAX`, `night_reward`.
- `economy_sim.gd`:
  - simula `players ∈ [1, 2, 4]`, 15 dias cada;
  - a cada dia aplica: imposto, mercado, comida, salários, upkeep, produção das serrarias e pedreiras (8 nós vivos, `crew` cheio), coleta manual (`MANUAL_PER_DAY` = 1,5 × uma serraria cheia, a meta da seção 18), munição da noite (tiros por torre = `60 / rate`) e treino de aldeões até o `pop_cap`;
  - o jogador segue uma lista de construção fixa e gasta quando pode, nesta ordem: casa, fazenda, serraria, torre de arqueiros, pedreira, quartel, mercado, e então "1 serraria a cada 6 torres", era quando possível e pesquisas em ordem de era.

**Asserts da simulação** (as metas da seção 18 do spec; a simulação imprime `PASS`/`FAIL` e sai com 1 se houver falha):

```gdscript
check(day1_affordable(["town_hall","house","house","farm","lumber_camp","archer_tower"]), "começo: dia 1 compra o kit inicial")
check(era2_day >= 4 and era2_day <= 6, "era II entre os dias 4 e 6 (dia %d)" % era2_day)
check(era3_day >= 9 and era3_day <= 12, "era III entre os dias 9 e 12 (dia %d)" % era3_day)
check(min_wood_at_night > 0, "madeira nunca zera à noite até o dia 15")
check(max_wood_before_12 <= 1500, "madeira não acumula demais antes do dia 12")
check(era1_techs_done_by <= era2_day, "pesquisas da era I compráveis até a era II")
check(era3_techs_left_at_15 > 0, "pesquisas da era III não acabam antes do dia 15")
```

- [ ] **Step 1:** escrever `economy_sim.gd` com os asserts e rodar. Run: `$GODOT --headless --path . --script res://tests/economy_sim.gd`. Esperado: alguns FAIL, que são o ponto de partida do balanceamento.
- [ ] **Step 2:** ajustar os números em `colony_data.gd` até `OK — 0 falha(s)` nos três tamanhos de grupo. Anotar no commit o que mudou em relação ao spec.
- [ ] **Step 3:** atualizar `net_test` e rodar o teste de rede local. Servidor: `$GODOT --headless --path . -- --server --port=7795 --city-day=12 & S=$!`. Clientes: `--nettest=127.0.0.1:7795 --peers=2 --city=lead` e `--city=join`. No fim, `kill $S`. Esperado: os dois clientes com `OK`.
- [ ] **Step 4:** rodar a skill `smoke-check`, que deve dar PASSOU em todos.
- [ ] **Step 5:** rodar a skill `balance-check` e corrigir os outliers que ela apontar.
- [ ] **Step 6:** subir `config/version` e fazer o commit — `"Cidade: simulação de economia e balanceamento (0.8.0)"`.
