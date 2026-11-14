# Monstros: goblin refeito, esqueletos e novas variantes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Goblin remodelado com equipamento por variante, família de esqueletos e duas variantes novas, presentes nos três modos.

**Architecture:** Um GLB por família, gerado por `tools/blender/monsters.py`; peças de equipamento são nós `Opt_<Nome>` e `enemies.json` escolhe quais ficam (`"gear"`). `enemy.gd` continua animando os seis pivôs; os tipos novos reutilizam as IAs existentes.

**Tech Stack:** Godot 4.7.2 (GDScript), Blender 5.2 em modo background, JSON em `data/balance`.

**Spec:** `docs/superpowers/specs/2026-11-14-monstros-esqueleto-design.md`

## Global Constraints

- Modelo da slime intocado.
- Pivôs obrigatórios em todo monstro humanoide: `LegL`, `LegR`, `Body`, `Head`, `ArmL`, `ArmR`. Frente = -Y no Blender, pés em Z=0.
- Peça opcional = nó `Opt_<Nome>`; `"gear"` usa o nome sem prefixo.
- Blender só por CLI: `blender.exe --background --factory-startup --python tools/blender/build_assets.py` com `ASSETS=goblin,skeleton`.
- Scripts puros rodados pelo runner de unitários não citam autoloads.
- `tests/unit/fixtures/balance_snapshot.bin` é regravado para `enemies` e `items` com `tools/balance_snapshot.gd`.
- Versão `0.14.0` em `project.godot`.

## Review Focus

1. Tipo sem `"gear"` (slimes) → nada é removido nem dá erro.
2. `"gear"` com nome que não existe no modelo → aviso no log, sem travar.
3. Arqueiro/mago fora da Horda → o projétil causa dano (grupo `players`).
4. Cliente em rede atingido pela Slime de Gelo → lentidão chega ao dono do personagem.
5. Menu principal e ferramentas que instanciam `goblin.glb` direto → não mostram todas as peças de uma vez.

---

### Task 1: Modelos (Blender)

**Files:** Create `tools/blender/monsters.py`; Modify `tools/blender/characters.py` (remove `build_goblin`), `tools/blender/build_assets.py` (exec do arquivo novo, `skeleton` em `BUILDERS`); gera `assets/models/goblin.glb`, `assets/models/skeleton.glb`.

**Produces:** nós `Opt_*` das tabelas do spec; pivôs padrão; nomes de raiz `Goblin` e `Skeleton`.

- [ ] `build_goblin()` em loft (`sec`/`loft` de `body.py`), cabeça atual mantida, peças `Opt_*`.
- [ ] `build_skeleton()`: crânio, costelas, coluna, bacia, ossos longos com juntas, peças `Opt_*`.
- [ ] Gerar os GLB e importar no Godot.
- [ ] Commit.

### Task 2: Peças opcionais e modelo novo no jogo

**Files:** Modify `scripts/enemies/enemy.gd`, `scripts/ui/main_menu.gd`, `tools/toon_shot.gd`, `tools/toon_cost.gd`; Test `tests/unit/test_enemy_gear.gd`.

**Produces:** `static func Enemy.apply_gear(model: Node3D, gear: Array) -> Array` (devolve os nomes pedidos que não existem); `MODELS["skeleton"]`.

- [ ] Teste: monta um `Node3D` com filhos `Opt_A`, `Opt_B`, `Fixo`; `apply_gear(m, ["A"])` deixa `Opt_A` e `Fixo`, remove `Opt_B`, devolve `[]`; `apply_gear(m, ["X"])` devolve `["X"]`; `apply_gear(m, [])` remove todos os `Opt_`. Como `enemy.gd` cita autoloads, a função mora em `scripts/enemies/enemy_gear.gd` (`class_name EnemyGear`, pura) e `Enemy.apply_gear` só repassa.
- [ ] Teste de dados: todo tipo de `enemies.json` com modelo `goblin`/`skeleton` tem `"gear"`, e cada nome existe como `Opt_<nome>` no GLB correspondente.
- [ ] Implementar; `_ready` chama antes de coletar `meshes`; remover o caso especial da coroa.
- [ ] `toon_shot.gd` aceita `gear=A,B`.
- [ ] Rodar unitários; commit.

### Task 3: Tipos novos, projétil mágico, lentidão

**Files:** Modify `data/balance/enemies.json`, `data/balance/items.json`, `scripts/enemies/enemy.gd`, `scripts/enemies/enemy_arrow.gd`, `scripts/player/player.gd`, `scripts/autoload/network.gd`, `scripts/ui/icon_painter.gd`, fixture do snapshot.

**Produces:** tipos `esqueleto`, `esqueleto_arqueiro`, `esqueleto_mago`, `esqueleto_cavaleiro`, `goblin_bombardeiro`, `slime_gelo`; item `bone_shard`; `Player.apply_chill(secs: float)`; `Network.server_chill_player(peer_id: int, secs: float)`; `enemy_arrow.magic: bool`.

- [ ] `"gear"` em todos os goblins; tipos novos com os valores do spec.
- [ ] Flecha: sem `targets()` no pai usa o grupo `players`; `magic` troca o visual por um orbe roxo.
- [ ] `chill`: no acerto corpo a corpo chama `apply_chill` se o alvo tiver; jogador anda a × 0,6 enquanto durar.
- [ ] Regravar snapshot (`-- enemies items`); unitários; commit.

### Task 4: Aparições nos modos

**Files:** Modify `scripts/world/world.gd`, `scripts/survival/survival_mode.gd`, `scripts/colony/colony.gd`, `scripts/colony/colony_data.gd`, `tests/smoke_test.gd` (contagens), `project.godot`, `README.md`.

- [ ] Mundo, Horda e Cidade conforme "Onde aparecem" do spec; recompensas da Horda tratam os tipos novos (cavaleiro = campeão).
- [ ] Smoke test confere as contagens novas das Ruínas e do Acampamento.
- [ ] Versão 0.14.0; commit.

### Task 5: Verificação

- [ ] Fotos com `tools/toon_shot.gd` de cada variante; comparar com a foto de antes.
- [ ] Skill `smoke-check` (import, unitários, economia, smoke, cidade, praça, rede).
- [ ] PR.
