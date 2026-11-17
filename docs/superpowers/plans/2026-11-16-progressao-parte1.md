# Progressão parte 1 — nível dos monstros, itens, XP e loot: plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Monstros ganham nível (status por curva), itens pedem nível, a curva de XP vai ao nível 50 em ~30 h com penalidade no fim, a XP cai contra monstros mais fracos e o loot deixa de soltar equipamento pronto à toa.

**Architecture:** Toda a matemática nova fica numa classe pura `ProgressionRules` que lê `data/balance/progression.json`. `Enemy` só recebe um `level` e aplica os multiplicadores que já existem (`hp_mult`, `dmg_mult`); `CharRules`, `LootRules` e `CharacterService` passam a receber o nível do monstro. Um simulador headless usa as mesmas funções puras para conferir ritmo e golpes, e um teste unitário trava as metas.

**Tech Stack:** Godot 4.7 / GDScript; tabelas JSON em `data/balance`; testes em `tests/unit` (runner `tests/unit/run.gd`), `smoke_test`, `net_test` (skill `smoke-check`); Python só para os scripts de migração de dados de uma vez só (`tools/balance/`).

**Spec:** `docs/superpowers/specs/2026-11-16-progressao-design.md` (seções "0. Onde ficam os parâmetros" e "1. Nível dos monstros, itens, XP e loot", mais "Decisões do usuário" e "Decisões da revisão").

Comandos (PowerShell ou bash, na raiz do worktree `C:\Games\godot-3d-progressao`):
- Godot: `C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe` (abaixo `$GODOT`).
- Unitários: `$GODOT --headless --path . -s tests/unit/run.gd` (depois de criar `class_name` novo, rodar antes `$GODOT --headless --path . --import`).
- O runner roda todos os arquivos `test_*.gd`; procurar o nome do teste na saída.

## Global Constraints

- Nível máximo **50**; ritmo alvo por faixa: 1–10 ~2 h, 10–20 ~5 h, 20–35 ~10 h, 35–45 ~7 h, 45–50 ~6 h (total ~30 h). Tolerância do teste: ±20% por faixa.
- Monstro comum do mesmo nível morre em **3 a 5 golpes** (guerreiro, arqueiro, mago com ataque básico; healer até 7), com atributos todos no atributo da classe e a melhor arma de nível ≤ L.
- Ajuste de XP por diferença (monstro − jogador): ≤ −8 → 0,05; −7..−5 → 0,25; −4..−3 → 0,70; −2..+2 → 1,00; +3..+4 → 1,15; ≥ +5 → 1,25. Em grupo, o "jogador" é o maior nível entre quem recebe.
- Bandas de nível por raridade na migração dos itens: comum 1–8, incomum 8–15, raro 14–24, épico 22–35, lendário 35–45.
- Horda e Defesa da Cidade **não mudam**: monstro sem nível (`level = 0`) usa os números de hoje.
- Nenhum número de balanceamento novo fixo em `.gd`: tudo em `data/balance/progression.json` ou no Inspector.
- Classes puras (`*_rules.gd`, `BalanceTables`) não usam nomes de autoload (`Game`, `ItemDB`, `Balance`...).
- Personagem antigo não perde nível, item nem ouro; a migração roda uma vez (`flags.prog_v`).
- Textos de jogo em português, no tom dos existentes. Comentários em português.
- PR sobe `config/version` em `project.godot` (0.29.0 → 0.30.0).

## Review Focus

1. **Save antigo com item equipado acima do nível novo** — continua equipado e o personagem carrega; só não dá para re-equipar. (Teste na Task 6.)
2. **Migração rodando duas vezes** (servidor recarrega o cache, solo recarrega o save) — segunda chamada não mexe em nada. (Teste na Task 6.)
3. **Monstro da Horda/cidade ou de tipo sem `ref_level`** — mesmos status de hoje, sem erro. (Teste na Task 1 e 2.)
4. **Personagem no nível 50** — XP extra não sobe nível nem estoura; barra de XP cheia. (Teste na Task 3.)
5. **Material de missão de coleta** (`goblin_ear`, `bone_shard`, `slime_gel`...) continua caindo com a mesma chance depois do corte do loot. (Teste na Task 5.)

---

### Task 1: `progression.json` e `ProgressionRules` (curvas puras)

**Files:**
- Create: `data/balance/progression.json`
- Create: `scripts/character/progression_rules.gd`
- Modify: `scripts/balance/balance_tables.gd` (`NAMES` += `"progression"`)
- Modify: `data/balance/enemies.json` (campo `ref_level` em cada tipo)
- Test: `tests/unit/test_progression_rules.gd`

**Interfaces:**
- Produces (`class_name ProgressionRules`, tudo `static`):
  - `max_level(bt: BalanceTables) -> int`
  - `xp_to_next(bt: BalanceTables, level: int) -> int` — `base × level^exp × late_mult(level)`; no `max_level` devolve 0.
  - `enemy_level(bt, kind: String, level: int) -> int` — `level` se > 0, senão `ref_level` do tipo (padrão 1).
  - `enemy_mults(bt, kind: String, level: int) -> Dictionary` — `{"hp": float, "dmg": float, "xp": float, "gold": float}` = `curva(L)/curva(ref_level)`; com `level <= 0` todos 1.0.
  - `xp_diff_mult(bt, enemy_level: int, player_level: int) -> float`
  - `tier_of(bt, level: int) -> int` — camada 1..5 (a cada 10 níveis), usada pelo loot e pela tinta.

`progression.json` (valores iniciais; a Task 8 calibra):

```json
{
  "max_level": 50,
  "xp_curve": {"base": 60, "exp": 1.55, "late": {"45": 1.6, "46": 1.9, "47": 2.2, "48": 2.6, "49": 3.0}},
  "xp_diff": [[-99, -8, 0.05], [-7, -5, 0.25], [-4, -3, 0.7], [-2, 2, 1.0], [3, 4, 1.15], [5, 99, 1.25]],
  "enemy_curves": {
    "hp":   {"rate": 0.22, "exp": 1.15},
    "dmg":  {"rate": 0.12, "exp": 1.0},
    "xp":   {"rate": 0.20, "exp": 1.1},
    "gold": {"rate": 0.10, "exp": 1.0}
  },
  "tier_size": 10,
  "tiers": [
    {"tint": {"$c": [1, 1, 1, 1]}, "scale": 1.0},
    {"tint": {"$c": [0.85, 0.95, 1.1, 1]}, "scale": 1.05},
    {"tint": {"$c": [0.8, 0.8, 1.0, 1]}, "scale": 1.1},
    {"tint": {"$c": [1.1, 0.8, 0.7, 1]}, "scale": 1.15},
    {"tint": {"$c": [0.7, 0.6, 0.9, 1]}, "scale": 1.2}
  ],
  "elite": {"level_bonus": 2, "hp": 2.0, "scale": 1.25, "gear_chance": 0.05},
  "gear_drop": {"chance": 0.02, "boss_chance": 1.0, "window": [-3, 1],
                "rarity_weight": {"common": 60, "uncommon": 28, "rare": 10, "epic": 2, "legendary": 0}},
  "quest_xp_share": 0.3,
  "sim": {"attack_interval": 0.9, "downtime_per_kill": 12.0, "talent_damage": 0.0}
}
```

Curva de cada status: `c(L) = (1 + rate × (L − 1))^exp`. `ref_level` inicial por tipo (editar no `enemies.json`): slimes comuns 2, slime_gelo/veloz 12, goblin/arqueiro/bombardeiro 6, xamã 14, bruto 9, campeão/dourado 10, esqueletos 22 (cavaleiro 25), feras do Vale (raptor, tecelã, flor, bocarrão, asa) 7, rei goblin 12, slime rainha 20, lich 40.

- [ ] **Step 1: Write the failing test** `tests/unit/test_progression_rules.gd` (padrão de `test_char_rules.gd`: `_tables()` carrega `res://data/balance`):
  - `test_xp_to_next_matches_curve`: `xp_to_next(bt, 10) == int(60 * pow(10, 1.55))`; `xp_to_next(bt, 46) > 1.8 * int(60 * pow(46, 1.55))`; `xp_to_next(bt, 50) == 0`.
  - `test_enemy_mults_identity_without_level`: `enemy_mults(bt, "goblin", 0)` == `{"hp":1.0,"dmg":1.0,"xp":1.0,"gold":1.0}`; idem para tipo desconhecido `"nao_existe"`.
  - `test_enemy_mults_at_ref_level_is_one`: para `goblin` em `ref_level` (6), `hp` ≈ 1.0.
  - `test_enemy_mults_grow_with_level`: `enemy_mults(bt,"goblin",20).hp > enemy_mults(bt,"goblin",10).hp > 1.0`.
  - `test_xp_diff_table`: `xp_diff_mult(bt, 2, 12) == 0.05`; `(5,11) == 0.25`; `(10,13) == 0.7`; `(10,10) == 1.0`; `(14,10) == 1.15`; `(20,10) == 1.25`.
  - `test_tier_of`: `tier_of(bt,1)==1`, `tier_of(bt,10)==1`, `tier_of(bt,11)==2`, `tier_of(bt,50)==5`.
- [ ] **Step 2:** `$GODOT --headless --path . --import` e rodar os unitários. Expected: FAIL (`ProgressionRules` não existe).
- [ ] **Step 3:** Criar `progression.json`, adicionar `"progression"` em `BalanceTables.NAMES`, `ref_level` no `enemies.json`, e implementar `ProgressionRules`. `late` é dicionário nível→multiplicador (chave string); nível sem chave = 1.0.
- [ ] **Step 4:** Rodar os unitários. Expected: `test_progression_rules` todo PASS e o resto como antes (inclui `test_balance.gd`, que confere as tabelas).
- [ ] **Step 5: Commit** — `git add data/balance scripts/character/progression_rules.gd scripts/balance/balance_tables.gd tests/unit/test_progression_rules.gd` · `git commit -m "Progressão: tabela progression.json e curvas puras"`

### Task 2: Monstro com nível (mundo, rede, placa) e nível nos pontos de nascimento

**Files:**
- Modify: `scripts/enemies/enemy.gd` (var `level`, `_ready`, `_die`, placa de nome)
- Modify: `scripts/map/enemy_spawn.gd` (`@export level`, `@export level_max`, `@export elite`)
- Modify: `scripts/world/map_loader.gd:45-62` (entrada leva `level`, `level_max`, `elite`)
- Modify: `scripts/world/world.gd:524-531` (`_spawn` sorteia o nível na faixa e marca elite)
- Modify: `scripts/autoload/network.gd` (`_enemy_spawned` e as duas chamadas `.rpc_id` levam `level`)
- Modify: `scenes/maps/vale.tscn`, `bosque.tscn`, `mina.tscn`, `pico.tscn` (nível de cada `EnemySpawn`)
- Create: `tools/balance/set_spawn_levels.py` (script de uma vez: escreve `level`/`level_max` nos nós)
- Test: `tests/unit/test_progression_rules.gd` (+1 teste), smoke test

**Interfaces:**
- Consumes: `ProgressionRules.enemy_level`, `enemy_mults`, `tier_of` (Task 1).
- Produces: `Enemy.level: int` (0 = sem nível); `Enemy.xp_reward() -> int` = `round(data.xp × mults.xp)`; `Enemy.gold_mult() -> float`; entrada de spawn `{"kind","pos","level","level_max","elite",...}`; RPC `_enemy_spawned(net_id, kind, pos, yaw, max_hp, hp, flags, level: int)`.

- [ ] **Step 1: Write the failing test** `test_elite_adds_levels`: `ProgressionRules.spawn_level(bt, 5, 8, true, rng)` está entre 7 e 10; `spawn_level(bt, 5, 0, false, rng) == 5` (`level_max` 0 = fixo); `spawn_level(bt, 0, 0, false, rng) == 0`. (Acrescentar `spawn_level(bt, level: int, level_max: int, elite: bool, rng: RandomNumberGenerator) -> int` a `ProgressionRules`.)
- [ ] **Step 2:** Rodar unitários. Expected: FAIL (`spawn_level` não existe).
- [ ] **Step 3:** Implementar:
  - `spawn_level` em `ProgressionRules` (sorteio uniforme em `[level, max(level, level_max)]` + `elite.level_bonus` se elite e nível > 0).
  - `EnemySpawn`: `@export_range(0, 60) var level := 0`, `@export_range(0, 60) var level_max := 0`, `@export var elite := false`, com doc-comentário ("0 = número de hoje, para Horda/cidade").
  - `MapLoader` copia os três para a entrada; `world._spawn` chama `spawn_level` e põe `e.level` e `e.elite` antes do `add_child`.
  - `Enemy._ready`: `var m := ProgressionRules.enemy_mults(Balance.tables, kind, level)`; `hp_mult *= m.hp`, `dmg_mult *= m.dmg` antes de `max_hp`; elite de mundo (não horda) com `level > 0` multiplica `hp_mult` por `elite.hp`; escala do modelo × `tiers[tier-1].scale` e tinta pela camada (só com `level > 0`).
  - `_die` solo usa `xp_reward()` no lugar de `data.xp`.
  - Placa: `display_name` vira `"Nv %d %s"` quando `level > 0`; cor da placa pela diferença para `Game.level` (≤ −5 cinza, −4..+2 branco, +3..+4 amarelo, ≥ +5 vermelho), recalculada quando o jogador sobe de nível (sinal `level_up` já emitido como evento; basta recalcular a cada ~1 s no `_process` que já atualiza a barra).
  - Rede: `server_register_enemy` e a ressincronização em `network.gd:553` mandam `e.level`; `_enemy_spawned` põe `e.level = level` antes do `add_child`.
- [ ] **Step 4:** Escrever `tools/balance/set_spawn_levels.py`: para cada bloco `[node ...]` com script `enemy_spawn.gd` nos 4 mapas, insere/atualiza `level = A` e `level_max = B` pela tabela abaixo (por `kind`, e pelo mapa), sem tocar no resto. Rodar e conferir com `git diff --stat` que só os 4 `.tscn` mudaram.

  | Mapa | Faixa por tipo |
  |---|---|
  | vale | slime*, slime_veloz, slime_explosivo, slime_mae 1–4 · goblin, goblin_arqueiro, goblin_bombardeiro 5–8 · raptor, tecela, flor_faminta, bocarrao, asa_couro 4–9 · goblin_xama, goblin_bruto, goblin_dourado, goblin_campeao 8–11 · esqueleto* 10–13 · slime_gelo 6–9 |
  | bosque | tudo 12–20 · slime_rainha 20 |
  | mina | tudo 20–30 · esqueleto_cavaleiro 30 |
  | pico | tudo 30–40 · lich 42 |

  Chefes por missão (`goblin_king` em `world.gd`) ficam com `level` = `ref_level` (12) fixado no código que os cria (`boss.level = ProgressionRules.enemy_level(Balance.tables, "goblin_king", 0)`).
- [ ] **Step 5:** Rodar unitários e o smoke test: `$GODOT --headless --path . res://scenes/world.tscn -- --smoketest`. Expected: unitários PASS; smoke "PASS" (se só fireball/spark/arrow falhar, rodar de novo — flake conhecido).
- [ ] **Step 6:** Rodar `net_test` como a skill `smoke-check` faz (confere que o RPC novo bate entre servidor e cliente). Expected: PASS.
- [ ] **Step 7: Commit** — `git commit -am "Progressão: monstros com nível no mundo, na rede e na placa"` (incluir o script novo com `git add tools/balance/set_spawn_levels.py`).

### Task 3: Nova curva de XP, nível máximo e ajuste por diferença de nível

**Files:**
- Modify: `scripts/character/char_rules.gd:178-200` (`xp_to_next` delega a `ProgressionRules`; `_add_xp` para no máximo), `:224` (`kill`)
- Modify: `scripts/character/character_service.gd:251` (`kill`)
- Modify: `scripts/autoload/econ.gd:224`, `:573` (`kill`, `server_kill`)
- Modify: `scripts/autoload/network.gd:648-671` (`server_enemy_killed`)
- Modify: `scripts/autoload/game.gd:771` (`on_enemy_killed`) e `scripts/enemies/enemy.gd` `_die`
- Modify: `data/balance/rules.json` (remove `xp_curve`, que foi para `progression.json`)
- Test: `tests/unit/test_char_rules.gd`, `tests/unit/test_character_service.gd`

**Interfaces:**
- Consumes: `ProgressionRules.xp_to_next`, `max_level`, `xp_diff_mult` (Task 1); `Enemy.xp_reward()`, `Enemy.level` (Task 2).
- Produces:
  - `CharRules.kill(s, bt, kind: String, xp: int, enemy_level := 0, group_level := 0) -> Dictionary` — com `enemy_level > 0`, `xp = round(xp × xp_diff_mult(enemy_level, max(s.level, group_level)))`.
  - `CharacterService.kill(char_id, kind, xp, enemy_level := 0, group_level := 0)`
  - `Econ.kill(kind, xp, enemy_level := 0)`; `Econ.server_kill(peer, kind, xp, enemy_level := 0, group_level := 0)`
  - `Game.on_enemy_killed(kind, xp_reward, enemy_level := 0)`

- [ ] **Step 1: Write the failing tests** em `test_char_rules.gd`:
  - `test_kill_xp_scaled_by_level_diff`: personagem nível 12, `CharRules.kill(s, bt, "slime", 100, 2)` dá +5 XP; `kill(..., 100, 12)` dá +100; `kill(..., 100, 0)` dá +100 (sem nível = sem ajuste).
  - `test_kill_xp_uses_group_level`: personagem nível 5, `kill(s, bt, "goblin", 100, 7, 14)` dá +25 (diferença 7 − 14 = −7 → 0,25).
  - `test_level_cap_50`: `s.level = 49`, `grant(s, bt, 0, 10_000_000, {})` → `s.level == 50` e `s.xp == 0`; segundo `grant` mantém `level == 50` e `xp == 0`.
  - `test_xp_to_next_delegates`: `CharRules.xp_to_next(10, bt) == ProgressionRules.xp_to_next(bt, 10)`.
- [ ] **Step 2:** Rodar unitários. Expected: FAIL nos quatro.
- [ ] **Step 3:** Implementar. No nível máximo `_add_xp` zera o excesso e não emite "+XP". `Network.server_enemy_killed` calcula `group_level` = maior `Party._level(pid)` entre as chaves de `rewards` e passa `e.level` e `group_level` para `Econ.server_kill`; `Party.server_kill_rewards` recebe `e.xp_reward()` no lugar de `e.data.xp`. Solo: `Enemy._die` → `Game.on_enemy_killed(kind, xp_reward(), level)`.
- [ ] **Step 4:** Rodar unitários (inclui `test_character_service.gd`, que já cobre `kill`). Expected: PASS.
- [ ] **Step 5: Commit** — `git commit -am "Progressão: curva de XP até 50 e XP pela diferença de nível"`

### Task 4: Nível dos itens (migração, equipar, tooltip)

**Files:**
- Create: `tools/balance/assign_item_levels.py`
- Modify: `data/balance/items.json` (campo `level` em todo item equipável, gerado pelo script)
- Modify: `scripts/character/char_rules.gd:364` (`equip`) e helper `item_level`
- Modify: `scripts/ui/item_tooltip.gd` (linha "Nível N", vermelha se faltar)
- Test: `tests/unit/test_char_rules.gd`

**Interfaces:**
- Produces: `CharRules.item_level(bt, id: String) -> int` (sem campo = 1); erro de `equip` `"exige_nivel"` com notify `"Requer nível %d."`.

- [ ] **Step 1:** Escrever `assign_item_levels.py`: para itens com `type` em `weapon`, `armor`, `gear` (todo item com `slot_of` ≠ ""), ordena dentro da raridade pela força (`damage` da arma; senão `defense`; senão `price`) e interpola linearmente na banda da raridade (Global Constraints), arredondando. Itens `named` (de chefe) recebem o topo da banda. Itens que já têm `level` não mudam (o script pode rodar de novo). Grava com a mesma indentação (tab) e `ensure_ascii=False`.
- [ ] **Step 2:** Rodar o script; conferir `git diff data/balance/items.json` (só linhas `"level"` novas).
- [ ] **Step 3: Write the failing tests:**
  - `test_equip_refuses_below_level`: personagem nível 3 com `dragonfang` na mochila (classe guerreiro): `equip` falha com `err == "exige_nivel"` e o item continua na mochila.
  - `test_equip_ok_at_level`: mesmo personagem com `s.level = CharRules.item_level(bt, "dragonfang")` equipa.
  - `test_all_equipables_have_level`: todo item com `slot_of != ""` tem `level` entre 1 e 50.
- [ ] **Step 4:** Rodar unitários. Expected: FAIL em `test_equip_refuses_below_level`.
- [ ] **Step 5:** Implementar a checagem em `equip` (antes de mexer no inventário) e a linha do tooltip (lê `Game.level` no cliente).
- [ ] **Step 6:** Rodar unitários. Expected: PASS.
- [ ] **Step 7: Commit** — `git add tools/balance/assign_item_levels.py` + `git commit -am "Progressão: itens pedem nível para equipar"`

### Task 5: Loot enxuto por nível

**Files:**
- Create: `tools/balance/trim_enemy_loot.py`
- Modify: `data/balance/enemies.json` (`loot` sem equipamento nos monstros comuns; chefes com lista curta)
- Modify: `scripts/character/loot_rules.gd` (`roll` com nível)
- Modify: `scripts/autoload/econ.gd:604` (`server_drop_loot` com nível e elite), `scripts/enemies/enemy.gd` (`drop_loot`), `scripts/autoload/network.gd:670`
- Test: `tests/unit/test_char_rules.gd` (seção LootRules)

**Interfaces:**
- Consumes: `ProgressionRules.enemy_mults`, `CharRules.item_level`.
- Produces: `LootRules.roll(bt, kind, rng, char_class := "", level := 0, elite := false) -> Dictionary` (mesma saída `{"gold", "items"}`); `LootRules.gear_pool(bt, level: int) -> Array` (ids equipáveis não `named` com `item_level` em `[level + window[0], level + window[1]]`, ordenados). `Econ.server_drop_loot(peer, kind, pos, zone := "world", level := 0, elite := false)`; `Enemy.drop_loot(parent, enemy_kind, pos, with_gold := true, level := 0, elite := false)`.

- [ ] **Step 1:** `trim_enemy_loot.py`: em cada tipo **não** `boss`, tira do `loot` toda entrada cujo item é equipável; materiais, poções e sementes ficam com a mesma chance. Nos chefes (`goblin_king`, `slime_rainha`, `lich`): mantém materiais/poções/sementes e só as entradas de equipamento `named` ou as 3 de maior chance, com a soma das chances de equipamento ≤ 1,0. Rodar e revisar o diff.
- [ ] **Step 2: Write the failing tests:**
  - `test_loot_has_no_gear_for_common`: 2.000 sorteios de `goblin` com `level 6` e `progression.gear_drop.chance` zerado na tabela de teste (copiar com `from_dict` e mudar) → nenhum item equipável.
  - `test_quest_materials_keep_rate`: 4.000 sorteios de `goblin` (nível 6) → frequência de `goblin_ear` entre 0,66 e 0,74; `esqueleto` → `bone_shard` entre 0,66 e 0,74.
  - `test_gear_drop_respects_level`: com `gear_drop.chance = 1.0`, 500 sorteios de `goblin` nível 20 → todo equipável sorteado tem `item_level` entre 17 e 21.
  - `test_gold_scales_with_level`: média de ouro de 1.000 sorteios em nível 30 > 2 × média em nível 6.
  - `test_roll_without_level_unchanged`: `roll(bt, "slime", rng_seed42)` sem nível dá o mesmo resultado que `roll(..., level = 0)`.
- [ ] **Step 3:** Rodar unitários. Expected: FAIL nos novos.
- [ ] **Step 4:** Implementar: ouro × `mults.gold`; depois do loot da tabela, um sorteio de equipamento com `gear_drop.chance` (elite: `elite.gear_chance`; `boss`: `boss_chance`) — escolhe raridade pelo `rarity_weight` entre as que têm candidatos em `gear_pool`, depois item uniforme (pool ordenado: mesma semente, mesmo resultado); `adapt_weapon` continua por último. Passar `e.level`/`e.elite` em `Network.server_enemy_killed` e no `_die` solo.
- [ ] **Step 5:** Rodar unitários. Expected: PASS.
- [ ] **Step 6: Commit** — `git add tools/balance/trim_enemy_loot.py` + `git commit -am "Progressão: loot de material e equipamento raro pelo nível"`

### Task 6: Migração dos personagens existentes

**Files:**
- Modify: `scripts/character/char_rules.gd` (nova `migrate_progression`)
- Modify: `scripts/character/char_state.gd` (`new_character` grava `flags.prog_v = 1`)
- Modify: `scripts/character/character_service.gd:85-95` (`load_or_create` migra e salva)
- Test: `tests/unit/test_char_rules.gd`, `tests/unit/test_character_service.gd`

**Interfaces:**
- Produces: `CharRules.migrate_progression(s: CharState, bt: BalanceTables) -> bool` (true = mudou; marca `s.flags.prog_notice = true`) e `CharRules.PROG_VERSION := 1`.

Regras: se `flags.prog_v` ≥ 1, não faz nada. Senão: atributos voltam a 5 cada; `stat_points = (level − 1) × points_per_level + soma de stat_points dos ranks da guilda já alcançados` (`ranks(bt)` até `rank_of(s)`); `xp = min(xp, xp_to_next(level) − 1)` (no 50, 0); equipamento **não** é tocado; talentos não mudam; `flags.prog_v = 1`.

- [ ] **Step 1: Write the failing tests:**
  - `test_migrate_refunds_points`: personagem nível 18, rank C, atributos `{"str": 56, "int": 5, "vit": 5, "agi": 5}`, `stat_points 0` → depois: atributos todos 5, `stat_points == 17*3 + 3`, retorno `true`.
  - `test_migrate_keeps_gear_above_level`: personagem nível 3 com `dragonfang` equipado → continua equipado depois de migrar e de `CharState.from_dict(s.to_dict(), bt)`.
  - `test_migrate_runs_once`: segunda chamada devolve `false` e não muda `stat_points` (depois de gastar 1 ponto entre as chamadas, continua gasto).
  - `test_new_character_needs_no_migration`: `migrate_progression(CharState.new_character(bt), bt) == false`.
  - Em `test_character_service.gd`: `test_load_migrates_and_saves` — grava personagem sem `prog_v` no store de teste, `load_or_create` devolve migrado e o store relido também está migrado.
- [ ] **Step 2:** Rodar unitários. Expected: FAIL.
- [ ] **Step 3:** Implementar e chamar em `load_or_create` logo depois de `_read` (salvar se `true`). O aviso ao jogador ("Seus pontos de atributo foram devolvidos: a progressão mudou. Distribua de novo na ficha (C).") vai em `s.flags.prog_notice = true`; o cliente mostra uma vez no HUD ao receber o estado e limpa com o fluxo de flags que já existe (procurar como `king_dead` é lido no cliente).
- [ ] **Step 4:** Rodar unitários. Expected: PASS.
- [ ] **Step 5: Commit** — `git commit -am "Progressão: personagens antigos recebem os pontos de volta"`

### Task 7: XP das missões pela fatia do nível

**Files:**
- Create: `tools/balance/set_quest_levels.py`
- Modify: `data/balance/quests.json` (campo `level` em cada missão; `reward_xp` recalculado)
- Test: `tests/unit/test_progression_rules.gd`

**Interfaces:**
- Consumes: curva de `progression.json` (o script Python lê o mesmo JSON e reproduz `xp_to_next`).
- Produces: `quests.json` com `level` por missão (editável) e `reward_xp = round(quest_xp_share × xp_to_next(level) × peso)`, `peso` = 1,5 para missão principal (`main_chain`), 1,0 secundária, 0,6 contrato do quadro.

- [ ] **Step 1:** `set_quest_levels.py`: nível de cada missão = nível médio do alvo dela (tipo `kill`: faixa do `target` no mapa de `where`/região pela tabela da Task 2; outras: nível da missão anterior da corrente, começando em 1). Imprime uma tabela `id, nível, xp antigo, xp novo` para revisão. Rodar com `--write`.
- [ ] **Step 2: Write the failing test** `test_quests_have_level_and_xp`: toda missão em `quests.json` tem `level` 1..50 e `reward_xp > 0`; a soma de `reward_xp` das missões com `level ≤ 10` está entre 20% e 45% de `sum(xp_to_next(1..9))`.
- [ ] **Step 3:** Rodar unitários. Expected: PASS depois do `--write` (se falhar, ajustar `quest_xp_share`/pesos e rodar o script de novo).
- [ ] **Step 4: Commit** — `git add tools/balance/set_quest_levels.py` + `git commit -am "Progressão: XP das missões pelo nível da missão"`

### Task 8: Simulador de ritmo, calibração, guia de balanceamento e versão

**Files:**
- Create: `tools/progression_sim.gd` (`extends SceneTree`, roda com `-s`)
- Create: `tests/unit/test_progression_pacing.gd`
- Modify: `scripts/character/char_rules.gd` (nova `basic_damage`), `scripts/autoload/game.gd:516-523` (`melee_damage` usa `basic_damage`)
- Modify: `data/balance/progression.json` (valores calibrados)
- Create: `docs/BALANCEAMENTO.md`
- Modify: `project.godot` (`config/version` → `0.30.0`)

**Interfaces:**
- Produces:
  - `CharRules.basic_damage(weapon_class: String, attrs: Dictionary, weapon_damage: float, spell_gear: float) -> float` — as três fórmulas de `melee_damage` (sem `mod("damage")`); `Game.melee_damage()` passa a ser `CharRules.basic_damage(...) * mod("damage")`.
  - `ProgressionRules.sim_hits(bt, char_class: String, level: int) -> int` — golpes para matar o monstro comum de referência (`goblin`) no mesmo nível: atributos `5 + (level−1)×pontos` no atributo da classe, melhor arma da classe com `item_level ≤ level` (não `named`), `talent_damage` do `sim`.
  - `ProgressionRules.sim_hours(bt) -> Dictionary` — `{"1-10": h, "10-20": h, "20-35": h, "35-45": h, "45-50": h}`: para cada nível, `xp_to_next × (1 − quest_xp_share)` ÷ XP do goblin no mesmo nível × (`sim_hits` do guerreiro × `attack_interval` + `downtime_per_kill`) ÷ 3600.

- [ ] **Step 1: Write the failing tests** em `test_progression_pacing.gd`:
  - `test_hits_same_level`: para `warrior`, `archer`, `mage` e níveis 5, 10, 20, 30, 40, 50: `3 <= sim_hits <= 5`; `healer`: `<= 7`.
  - `test_hours_per_band`: cada faixa de `sim_hours` dentro de ±20% de `{"1-10": 2, "10-20": 5, "20-35": 10, "35-45": 7, "45-50": 6}`.
  - `test_basic_damage_matches_old_formula`: `basic_damage("sword", {"str": 20, ...}, 12, 0) == 12 + 20*1.6`; `"bow"` com agi 20/str 5 e arma 15 == `15 + 30 + 1.5`; `"staff"` com int 20, arma 10, spell 4 == `10 + 28 + 2`.
- [ ] **Step 2:** Rodar unitários. Expected: FAIL.
- [ ] **Step 3:** Implementar `basic_damage`, `sim_hits`, `sim_hours` e `tools/progression_sim.gd`, que imprime uma tabela por nível (nível, XP p/ próximo, vida do goblin, dano por classe, golpes por classe, minutos no nível) e o total por faixa.
- [ ] **Step 4:** Calibrar: rodar `$GODOT --headless --path . -s tools/progression_sim.gd`, ajustar `enemy_curves`, `xp_curve.late`, `sim.downtime_per_kill` em `progression.json` até os testes passarem. Se os golpes não fecharem só com as curvas porque a arma mais forte por nível pula demais, ajustar `level` de itens no `items.json` (à mão), não o código.
- [ ] **Step 5:** Escrever `docs/BALANCEAMENTO.md`: cada botão de `progression.json` (o que faz, valor seguro, o que conferir no simulador), o `ref_level` do `enemies.json`, o `level` dos itens e das missões, os campos `level`/`level_max`/`elite` do Ponto de monstro no Inspector, e como rodar o simulador. Acrescentar uma linha sobre esses campos na seção "Ponto de monstro" de `docs/EDITOR_MAPA.md`.
- [ ] **Step 5b:** Conferir a capacidade das árvores de talento: somar `max` de todos os talentos de cada classe em `talents.json`; se for menor que 49, anotar no PR que os pontos acima disso ficam guardados (ampliar as árvores fica fora desta parte).
- [ ] **Step 6:** Subir `config/version` para `0.30.0`. Rodar a skill `smoke-check` (import, unitários, smoke, vila, net). Expected: todos PASSOU (flake de projétil: rodar de novo antes de culpar a mudança).
- [ ] **Step 7:** Jogar 10 minutos no solo com personagem novo (`$GODOT --path .`): conferir placa "Nv" nos monstros, slime morrendo em 2–3 golpes no nível 1, goblin do nível 5–8 em 3–5 no nível certo, nenhum equipamento caindo a cada poucos abates. Anotar o tempo até o nível 3 para comparar com o simulador.
- [ ] **Step 8: Commit** — `git add tools/progression_sim.gd tests/unit/test_progression_pacing.gd docs/BALANCEAMENTO.md` + `git commit -am "Progressão: simulador de ritmo, calibração e guia de balanceamento; versão 0.30.0"`

---

## Fora desta parte (vai para as partes 2–4)

- Regiões nomeadas, densidade e nomes no mapa (parte 2). Até lá o nível vem do `EnemySpawn`.
- Materiais por camada, receitas e profissões (parte 3). **A loja só com o básico entra na parte 3**, junto com o craft: se cortar a loja agora, sem craft, o jogador acima do nível ~15 fica sem fonte de equipamento. Por isso a chance de equipamento nesta parte começa em 2% (o design fala em ~0,5%) e cai quando o craft existir.
- Dungeons (parte 4).
