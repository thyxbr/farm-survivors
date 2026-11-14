# Encantamento de armas — Parte 3 (efeitos dos elementos e fontes de +4 e +5) — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cada elemento ganha o seu efeito ao acertar, e Sagrado, Sombra e a Insígnia do Campeão passam a ter fonte em Valdoria, liberando +4 e +5.

**Architecture:** Os números dos efeitos ficam em `enchant.json` e são lidos por `EnchantRules` (puro). A aplicação acontece no cliente, nos dois lugares em que a arma acerta (golpe corpo a corpo e projétil da arma), por um ajudante único `EnchantHit`. Só a marca de Veneno precisa do servidor, porque vale para o dano de todos: ela vira estado do inimigo, com um pedido novo e valores limitados pelo servidor.

**Tech Stack:** Godot 4.7.2 (GDScript), `data/balance/*.json`, `tests/unit/`, `tests/smoke_test.gd`, `tests/net_test.gd`.

**Spec:** `docs/superpowers/specs/2026-11-14-encantamento-design.md` (seções 5.2, 5.3 e 6, passos 5 e 6)

## Global Constraints

- As mesmas das Partes 1 e 2. `config/version` sobe para `0.11.2` (RPC novo).
- Os efeitos valem só para acertos da **arma** (golpe e projétil da arma), não para magias nem para as armas automáticas da Horda.
- Um efeito nunca dispara outro efeito (o dano da corrente e da queimadura não gera corrente, queimadura nem cura).

## Diferenças em relação ao spec

- **Sombra vem do Goblin Bruto (Ruínas), não de lobos.** Os lobos são `ColonyAnimal`, presos à Defesa da Cidade e fora da replicação de inimigos de Valdoria. Trazer fauna para Valdoria fica como trabalho próprio.
- **Gelo escala pela duração, não pela força.** A lentidão do jogo é fixa (55% mais lento); o nível aumenta quanto tempo dura.

## Efeitos (em `enchant.json`, chave `effects`)

| Elemento | Efeito | +1 | +2 | +3 | +4 | +5 | Fixos |
|---|---|---|---|---|---|---|---|
| fogo | queimadura: fração do dano do golpe, em 3 pulsos | 0.15 | 0.22 | 0.30 | 0.38 | 0.45 | `secs` 3 |
| gelo | lentidão: segundos | 0.6 | 0.9 | 1.2 | 1.6 | 2.0 | — |
| raio | corrente: chance | 0.10 | 0.15 | 0.20 | 0.25 | 0.30 | `mult` 0.5, `radius` 6 |
| veneno | marca: dano extra recebido de todos | 0.04 | 0.06 | 0.08 | 0.10 | 0.12 | `secs` 4 |
| sagrado | dano extra em chefes e elites | 0.08 | 0.12 | 0.16 | 0.20 | 0.25 | — |
| sombra | cura: fração do dano causado | 0.01 | 0.015 | 0.02 | 0.025 | 0.03 | — |

## Review Focus

1. **Cliente adulterado mandando marca de Veneno enorme:** o servidor limita ao maior valor da tabela e a `secs`.
2. **Queimadura em inimigo que morre ou some antes dos pulsos:** nada quebra.
3. **Corrente sem outro inimigo por perto:** não acontece nada.
4. **Acerto em alvo que não é `Enemy`** (animal da cidade, nó de recurso): os efeitos são ignorados.
5. **Arma sem encanto ou tabela sem `effects`:** nenhum efeito, nenhum erro.

---

### Task 1: Fontes de Sagrado, Sombra e da Insígnia

**Files:** `data/balance/enemies.json`, `data/balance/enchant.json` (`sources`), `data/balance/items.json` (descrição de `shadow_fang`), `scripts/world/world.gd`; testes em `tests/unit/test_balance.gd` e `tests/smoke_test.gd`; snapshots de `enemies` e `items`.

| Monstro | Item | Chance | Onde | Quantos | Volta em |
|---|---|---|---|---|---|
| `goblin_bruto` | `shadow_fang` | 0.8 | `RUINS + (-11, 0, 4)` e `RUINS + (11, 0, 4)` | 2 | 150 s |
| `goblin_dourado` | `golden_dust` | 1.0 | `(30, 0, 44)` e `(-30, 0, -72)` | 2 | 240 s |
| `goblin_campeao` | `champion_badge` | 1.0 | `CAMP + (2, 0, -5)` | 1 | 300 s |

- [ ] **Step 1:** Testes que falham: `test_essence_sources` passa a cobrir os seis elementos e a `champion_badge`; o smoke test confere 2 brutos, 2 dourados e 1 campeão no mundo.
- [ ] **Step 2:** Ver falhar. **Step 3:** Implementar e regravar snapshots. **Step 4:** Passam. **Step 5:** Commit `Encantamento: fontes de Sagrado, Sombra e da Insígnia`.

### Task 2: Números e regras dos efeitos

**Files:** `data/balance/enchant.json`, `scripts/character/enchant_rules.gd`, `scripts/ui/enchant_ui.gd`; testes em `tests/unit/test_enchant_rules.gd`, `tests/unit/test_balance.gd`.

**Produces:**
- `EnchantRules.effect(bt: BalanceTables, element: String, level: int) -> Dictionary` — `{"el", "value": float}` mais os campos fixos do elemento (`secs`, `mult`, `radius`); sem efeito (nível 0, elemento ou tabela ausente): `{}`.
- `EnchantRules.effect_text(bt, element, level) -> String` — `"Queimadura: 30% do dano em 3 s"`, `"Lentidão por 1,2 s"`, `"Corrente: 20% de chance de saltar a outro inimigo"`, `"Marca tóxica: alvo recebe +8% de dano por 4 s"`, `"+16% de dano em chefes e elites"`, `"Cura 2% do dano causado"`; sem efeito: `""`.
- `EnchantRules.max_effect(bt, element) -> float` — maior valor da tabela para o elemento (o servidor usa para limitar).
- O painel mostra `effect_text` do nível resultante no lugar do nome do efeito.

- [ ] Testes que falham (valores da tabela acima nos níveis 1, 3 e 5 de cada elemento; textos; `{}` e `""` nos casos sem efeito; `max_effect("veneno") == 0.12`) → ver falhar → implementar → passam → commit `Encantamento: números e regras dos efeitos`.

### Task 3: Efeitos ao acertar

**Files:** Create `scripts/player/enchant_hit.gd`; Modify `scripts/enemies/enemy.gd`, `scripts/player/player.gd` (golpe), `scripts/player/projectile.gd` (`_damage`), `scripts/autoload/network.gd`, `scripts/autoload/game.gd` (`weapon_effect()`), `project.godot`; testes em `tests/smoke_test.gd`, `tests/net_test.gd`.

**Produces:**
- `Game.weapon_effect() -> Dictionary` — `EnchantRules.effect` da arma equipada.
- `class_name EnchantHit`:
  - `static func scale(target: Node, dmg: float) -> float` — Sagrado: multiplica se o alvo é `Enemy` chefe ou elite (`is_boss`, `elite`, `data.elite`, ou com afixo); senão devolve `dmg`.
  - `static func on_hit(target: Node, dmg: float) -> void` — aplica o efeito da arma equipada depois do dano; ignora alvo que não é `Enemy`.
  - `static func chain(target: Enemy, dmg: float, fx: Dictionary) -> Enemy` — dá `dmg * mult` no inimigo vivo mais próximo dentro de `radius` e o devolve (`null` se não houver).
- `Enemy.venom_amp: float`, `Enemy.venom_timer: float`, `Enemy.apply_venom(amp: float, secs: float) -> void` (réplica: pede ao servidor), `Enemy.incoming(amount: float) -> float` (dano já com a marca).
- `Network.client_mark_enemy(net_id: int, amp: float, secs: float)` e o RPC `_mark_enemy`, que confere zona e alcance (`HitGuard.accepts` com dano 0) e limita `amp` a `EnchantRules.max_effect(bt, "veneno")` e `secs` ao `secs` da tabela.

- [ ] **Step 1:** Testes que falham. Smoke (`_test_enchant_effects`, depois de `_test_enchant`): com um goblin criado para o teste, troca a arma de elemento pelo serviço e confere cada efeito — queimadura tira vida ao longo de 3 s e não quebra se o alvo é liberado antes; lentidão liga `slow_timer`; `chain` acerta um segundo goblin a menos de 6 m com metade do dano e devolve `null` sem vizinho; marca de veneno faz 100 de dano virar 106 no +2; `scale` dá 112 em elite e 100 em alvo comum e em nó de recurso; sombra cura 1,5 por 100 de dano. Net test: marca de veneno adulterada (`amp` 5.0) num inimigo vivo, depois 10 de dano → a vida cai entre 11 e 11,5 (limitado a 12%).
- [ ] **Step 2:** Ver falhar. **Step 3:** Implementar. **Step 4:** Smoke e multiplayer da Horda passam.
- [ ] **Step 5:** Rodada final (import, unitários, smoke, Defesa da Cidade, Horda, cidade em grupo) e captura de um efeito na tela.
- [ ] **Step 6:** Commit `Encantamento: efeitos dos elementos ao acertar`.
