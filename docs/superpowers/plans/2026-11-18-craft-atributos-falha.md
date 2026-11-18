# Craft: atributo aleatório, falha, tela nova e animação — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Equipamento fabricado ganha bônus sorteado e chance de falha por raridade; a tela de craft mostra ícones e anima o desfecho.

**Architecture:** O bônus vai no id do item (`base[@qualidade][~afixo]`), com as variantes geradas em `ItemQuality.expand`, como a qualidade. `CraftRules.craft` (regra pura, roda no servidor) sorteia falha, qualidade e afixo e descreve o desfecho em eventos. A `CraftingUI` é refeita com `ItemSlot` e um overlay `CraftAnim` que espera a resposta do servidor.

**Tech Stack:** Godot 4 / GDScript; testes em `tests/unit` (runner `tests/unit/run.gd`) e `tests/smoke_test.gd`.

**Spec:** `docs/superpowers/specs/2026-11-17-craft-atributos-falha-design.md`

## Global Constraints
- Regras puras (`scripts/character/*`) não citam autoloads (`Game`, `ItemDB`…): o runner unitário não compila.
- Sem `rng`: nunca falha, nunca sorteia afixo.
- Números em `data/balance/progression.json` (`craft_affix`, `craft_fail`), nunca no código.
- `config/version` em `project.godot` sobe antes do merge.

## Review Focus
- Save antigo com `iron_sword@fina` continua carregando e equipando (teste em Task 1).
- Encanto de arma com afixo usa o id base (`ItemQuality.base("x@fina~urso") == "x"`) (Task 1).
- Item com afixo não cai de monstro (Task 1: `LootRules` usa `base(id) == id`).
- "Fabricar tudo" em que todas falham: materiais devolvidos pela metade, resultado `ok` com `n == 0` e `fail == times` (Task 2).
- Resposta do servidor chega antes ou depois da animação terminar; recusa (`ok == false`) fecha a animação sem desfecho (Task 4).

---

### Task 1: Id com afixo e variantes na tabela
**Files:** Modify `scripts/character/item_quality.gd`, `scripts/character/loot_rules.gd:54`, `scripts/autoload/item_db.gd` (linha do bônus em `item_summary`), `data/balance/progression.json`; Test `tests/unit/test_craft_rules.gd`.

**Produces:**
- `ItemQuality.AFFIX_SEP := "~"`; `base(id)`, `quality(id)`, `affix(id) -> String`, `make(base_id, q, affix_id) -> String`; `variant(id, q)` preserva o afixo.
- `ItemQuality.affix_ids(prog) -> Array`, `affix_allowed(item, prog) -> bool` (raridade em `craft_affix.rarities`), `affix_value(def, level)` (int para atributo inteiro, float 3 casas para fração).
- Itens gerados levam `"affix"`, `"affix_stat"`, `"affix_value"` e `"art"` = arte do base.
- `progression.json`: `craft_affix {rarities, price_mult, affixes{id:{name, stat, base, per_level}}}` e `craft_fail {chance{raridade}, per_level, floor, refund, xp_mult}` com os valores do spec.

- [ ] Testes: partes do id; `iron_sword@fina` existe e tem `art`; saída rara tem 8 afixos × 3 qualidades; valor do afixo somado e multiplicado pela qualidade; comum não tem afixo; `LootRules` não deixa cair variante.
- [ ] Implementar, rodar unitários, commit.

### Task 2: Falha, metade de volta e sorteio do afixo
**Files:** Modify `scripts/character/craft_rules.gd`; Test `tests/unit/test_craft_rules.gd`.

**Produces:**
- `CraftRules.fail_chance(bt, rid, prof_level) -> float` (0 fora de equipamento e na cozinha).
- `CraftRules.craft(...)` resultado ganha `"fail": int`; eventos `{"t": "craft_fail", "n": int, "back": {id: qty}}`.

- [ ] Testes com rng semeado: receita lendária de teste falha às vezes em 60 tentativas; `n + fail == 60`; material devolvido entre 0 e o gasto; ouro gasto inteiro; XP menor que 60 sucessos; receita comum nunca falha; raro bem-sucedido sai com afixo; sem rng nada muda.
- [ ] Implementar, rodar unitários, commit.

### Task 3: Tela de craft nova
**Files:** Rewrite `scripts/ui/crafting_ui.gd` (mantém `station`, `closed`, `list.item_count` usado pelo smoke test → trocar o smoke para `recipe_count()`).

- [ ] Lista de receitas em linhas com `ItemSlot`, nível, nome na cor da raridade e "xN"; painel direito com `ItemSlot` grande, resumo, chances (sucesso/Fina/Obra/bônus), materiais com ícone e tenho/preciso, ouro, XP.
- [ ] Smoke test passa; commit.

### Task 4: Animação de craft
**Files:** Create `scripts/ui/craft_anim.gd`; Modify `scripts/ui/crafting_ui.gd`.

**Produces:** `CraftAnim.start(item_id, station)`, `CraftAnim.resolve(ok_items: Array, fails: int, back: Dictionary)`, `CraftAnim.cancel()`, sinal `finished`.

- [ ] Fase de trabalho (≥ 1,1 s e até o servidor responder), desfecho de sucesso/falha, fecha com clique/tecla ou sozinho.
- [ ] Conferir na tela (screenshots), commit.

### Task 5: Versão e verificação
- [ ] `config/version` → próxima; unitários + smoke; `docs/BALANCEAMENTO.md` com a tabela de falha e afixos.
