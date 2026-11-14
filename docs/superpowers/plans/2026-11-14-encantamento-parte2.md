# Encantamento de armas — Parte 2 (materiais em Valdoria) — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Os materiais do encantamento passam a existir no mapa de Valdoria, fechando o ciclo até o +3 para Fogo, Gelo, Raio e Veneno.

**Architecture:** As essências entram nas tabelas de saque dos monstros (`enemies.json`), que só valem em Valdoria. Os monstros novos entram como pontos de nascimento em `world.gd`. A coleta de ferro e cristal segue o molde dos itens pegos no chão: o cliente pede, o servidor confere zona, distância e tempo de recuperação e concede. Cada jogador tem os seus próprios veios (como o saque pessoal), então não há estado de veio para replicar.

**Tech Stack:** Godot 4.7.2 (GDScript), tabelas JSON em `data/balance/`, testes em `tests/unit/`, `tests/smoke_test.gd`, `tests/net_test.gd`.

**Spec:** `docs/superpowers/specs/2026-11-14-encantamento-design.md` (seções 5.3 e 6, passo 4)

**Escopo:** Sagrado (Goblin Dourado), Sombra (lobos) e a Insígnia do Campeão ficam para a Parte 3, junto com os efeitos dos elementos. Nesta parte, +4 e +5 continuam sem fonte.

## Global Constraints

- As mesmas da Parte 1 (worktree `C:\Games\godot-3d-vfx-encanto`, `--import` depois de `class_name` novo, nunca matar todos os Godot, textos em português, commits com `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>`).
- `config/version` sobe para `0.11.1` (RPC novo).
- A operação nova se chama `gather` (o serviço já tem `harvest`, que é a colheita da horta).
- Não mexer na ordem dos sorteios que montam o mapa (`rng` de `world.gd`): nada de áreas novas em `_avoid`, senão todas as árvores mudam de lugar.
- O smoke test tem falha intermitente conhecida nas verificações de projétil; se só elas falharem, rodar de novo.

## Review Focus

1. **Bater no veio longe dele** (cliente adulterado): o servidor recusa pela distância.
2. **Pedir o mesmo veio duas vezes seguidas:** só a primeira concede; a segunda é recusada até o veio se recuperar.
3. **Pedir um veio que não existe** ou com id de tipo errado: recusa sem erro de script.
4. **Jogador fora de Valdoria** (na praça ou na cidade) pedindo coleta: recusa.
5. **Tabela `world_nodes` ausente** (servidor antigo): o mundo carrega sem veios, sem erro.

---

### Task 1: Essências no saque e monstros novos em Valdoria

**Files:** Modify `data/balance/enemies.json`, `scripts/world/world.gd` (`_setup_enemies`, constante `NEST`); Test `tests/unit/test_balance.gd`, `tests/smoke_test.gd`; regravar o snapshot de `enemies`.

**Interfaces — Produces:** `World.NEST := Vector3(-36, 0, 36)`.

Saque novo (entrada `[item, chance]` acrescentada ao `loot` de cada um):

| Monstro | Item | Chance |
|---|---|---|
| `slime_veloz` | `frost_drop` | 0.5 |
| `slime_explosivo` | `ember_core` | 0.6 |
| `slime_mae` | `toxic_gland` | 0.9 |
| `goblin_xama` | `thunder_totem` | 0.7 |

Pontos de nascimento novos:

| Lugar | Monstro | Quantos | Volta em |
|---|---|---|---|
| Ninho de Slimes (`NEST`) | `slime_veloz` | 4 | 45 s |
| Ninho de Slimes | `slime_explosivo` | 3 | 60 s |
| Ninho de Slimes | `slime_mae` | 1 | 120 s |
| Acampamento Goblin (`CAMP`) | `goblin_arqueiro` | 2 | 75 s |
| Acampamento Goblin | `goblin_xama` | 1 | 120 s |

- [ ] **Step 1: Testes que falham.** Em `test_balance.gd`, `test_essence_sources`: para cada elemento de `fogo, gelo, raio, veneno`, existe em `enemies` um monstro cujo `loot` contém a essência do elemento com chance > 0. No smoke test, logo no início (onde confere "inimigos spawnados"): existem em `enemies` 4 `slime_veloz`, 3 `slime_explosivo`, 1 `slime_mae`, 2 `goblin_arqueiro` e 1 `goblin_xama`; todos os de slime a menos de 12 m de `world.NEST`.
- [ ] **Step 2:** Rodar e ver falhar.
- [ ] **Step 3:** Implementar; regravar o snapshot (`tools/balance_snapshot.gd -- enemies`); ajustar a contagem "inimigos spawnados" se o teste a fixar.
- [ ] **Step 4:** Unitários e smoke passam.
- [ ] **Step 5:** Commit `Encantamento: essências no saque e monstros novos em Valdoria`.

### Task 2: Tabela `world_nodes` e regras de coleta

**Files:** Create `data/balance/world_nodes.json`, `scripts/world/world_harvest.gd`; Modify `scripts/balance/balance_tables.gd` (`NAMES`); Test `tests/unit/test_world_harvest.gd`.

**Interfaces — Produces:**
- Tabela `world_nodes`: `{"kinds": {kind: {"item", "amount", "hits", "respawn", "model"}}, "nodes": [[kind, x, z], ...]}`. O id de um nó é o índice dele em `nodes`.
- `class_name WorldHarvest extends RefCounted`:
  - `static func node_def(bt: BalanceTables, id) -> Dictionary` — `{"id", "kind", "pos": Vector3, "item", "amount", "hits", "respawn", "model"}`; id inválido (fora da lista, negativo, não inteiro): `{}`.
  - `static func count(bt: BalanceTables) -> int`
  - `func gather(bt: BalanceTables, account: int, id, from: Vector3, now: float) -> Dictionary` — `{"ok", "err", "items": {item: amount}}`. Erros: `no_invalido`, `longe` (usa `HitGuard.accepts_harvest`), `esgotado` (antes de `respawn` segundos desde a última coleta daquela conta naquele nó).
  - `func undo(account: int, id: int) -> void` — desfaz a marca de coletado (a concessão falhou).
  - `func ready_in(account: int, id: int, now: float) -> float` — segundos até poder coletar de novo (0 = pronto).

Valores:

| kind | item | amount | hits | respawn | model |
|---|---|---|---|---|---|
| `iron` | `iron_ore` | 3 | 5 | 180 | `iron` |
| `crystal` | `arcane_crystal` | 1 | 6 | 300 | `crystal` |

Nós: 6 de ferro num círculo de raio 12,5 em volta de `CAMP (62, 0)` nos ângulos 40°, 90°, 140°, 220°, 270°, 320°; 4 de cristal num círculo de raio 17 em volta de `RUINS (0, -100)` nos ângulos 30°, 150°, 210°, 330° (x = cx + r·cos, z = cz + r·sin, arredondados a uma casa).

- [ ] **Step 1: Testes que falham** (`test_world_harvest.gd`): a tabela tem 10 nós, 6 `iron` e 4 `crystal`, e todo `item` existe em `items`; `gather` perto concede `{"iron_ore": 3}`; de novo na hora dá `esgotado`; depois de 180 s concede de novo; outra conta no mesmo nó concede (veios são pessoais); a 30 m dá `longe`; posição `Vector3.INF` dá `longe`; ids `-1`, `999`, `"x"`, `1.5` dão `no_invalido`; `undo` permite coletar de novo; com tabela ausente, `count` é 0 e `gather` dá `no_invalido`.
- [ ] **Step 2:** Rodar e ver falhar. **Step 3:** Implementar. **Step 4:** Unitários passam.
- [ ] **Step 5:** Commit `Encantamento: tabela world_nodes e regras de coleta`.

### Task 3: Coleta no jogo (solo e servidor) e os veios no mapa

**Files:** Create `scripts/world/world_resource_node.gd`; Modify `scripts/autoload/econ.gd`, `scripts/world/world.gd`, `project.godot` (versão); Test `tests/smoke_test.gd`, `tests/net_test.gd`.

**Interfaces — Consumes:** `WorldHarvest` (Task 2), `ColonyResourceNode` (visual, tremida, queda e volta).

**Produces:**
- `Econ.gather_node(id: int, from: Vector3) -> void` — solo: confere e concede na hora (origem `"gather"`); online: manda `_gather_node(seq, id)` ao servidor, que usa a última posição conhecida do jogador e exige zona `"world"`. Resposta como op `"gather"` em `Econ.result`/`Econ.done`. Recusa `esgotado` avisa "Este veio ainda não se recuperou."
- `class_name WorldResourceNode extends ColonyResourceNode` — campos `node_id: int`, `respawn: float`; `hit(from)` conta os golpes localmente, treme, e no último some, chama `Econ.gather_node` e volta sozinho depois de `respawn` segundos.
- `world.resource_nodes: Array` — os nós criados (vazio no servidor dedicado, que só precisa da tabela).

- [ ] **Step 1: Testes que falham.** Smoke (função `_test_gather`, antes de `_test_enchant`): há 10 nós em `world.resource_nodes`; o jogador ao lado de um veio de ferro dá 5 golpes (`node.hit(pos)`) e ganha 3 `iron_ore`; o nó fica `alive == false`; `Econ.gather_node` de novo no mesmo nó não concede nada; `Econ.gather_node` de um veio a mais de 30 m não concede. Net test (depois do bloco do encanto): `Econ.gather_node(0, ...)` longe do Acampamento não muda `iron_ore`; depois de mover o jogador para junto do veio 0 e esperar a posição chegar ao servidor, concede 3; um segundo pedido não concede.
- [ ] **Step 2:** Rodar e ver falhar. **Step 3:** Implementar. **Step 4:** Smoke e multiplayer da Horda passam.
- [ ] **Step 5:** Conferir na tela (captura dos veios no Acampamento e dos cristais nas Ruínas, e do Ninho).
- [ ] **Step 6:** Rodada final: import, unitários, smoke, Defesa da Cidade, multiplayer da Horda, cidade em grupo.
- [ ] **Step 7:** Commit `Encantamento: coleta de ferro e cristal em Valdoria`.
