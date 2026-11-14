# Encantamento de armas — Parte 1 (protótipo no main, regras, servidor e painel do Doran) — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** O jogador encanta a arma equipada falando com o Doran; o servidor valida, cobra e grava; a arma ganha dano e brilha para todos os jogadores.

**Architecture:** Segue o caminho que as passivas permanentes já usam: regra pura (`EnchantRules`, sem autoload) → `CharacterService.apply("enchant")` → `CharStore` (SQLite no servidor, JSON no solo) → espelho no `Game` → interface. O visual é o do protótipo (`EnchantFX`, `BuffAura`), mas o elemento e o nível mostrados aos outros passam a vir do que o servidor gravou.

**Tech Stack:** Godot 4.7.2 (GDScript), SQLite pelo `Db` do projeto, tabelas JSON em `data/balance/`, testes em `tests/unit/` (`run.gd`), `tests/smoke_test.gd` e `tests/net_test.gd`.

**Spec:** `docs/superpowers/specs/2026-11-14-encantamento-design.md`

**Escopo:** este plano cobre os passos 1 a 3 da ordem de entrega do spec (seção 6). Os passos 4 a 6 (materiais e monstros em Valdoria, efeitos dos elementos, conteúdo de nível alto) ficam para a **Parte 2** e a **Parte 3**, cada uma com seu plano. Ao fim da Parte 1 o encantamento funciona de ponta a ponta, mas os materiais ainda não têm fonte no mapa: só chegam por concessão de teste.

## Global Constraints

- Godot `C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe` (abaixo, `$G`). Trabalhar só no worktree `C:\Games\godot-3d-vfx-encanto`, nunca em `C:\Games\godot-3d`.
- Depois de criar qualquer `class_name` novo, rodar `$G --headless --path . --import` antes dos testes.
- Nunca encerrar todos os processos Godot. Guardar o PID do servidor de teste e encerrar só ele (`kill $S`). Porta diferente de 7777 a cada execução.
- Textos para o jogador e comentários de código em português, no estilo do projeto.
- Regras puras: `scripts/character/*.gd` não usam autoload; recebem `CharState` e `BalanceTables`.
- Toda operação de regra devolve `{"ok", "err", "events"}` e **só muda o estado se `ok`**.
- Elementos (ids, nesta ordem): `fogo`, `gelo`, `raio`, `veneno`, `sagrado`, `sombra`. Nível máximo: `5`.
- Bônus de dano por nível: `0.05, 0.10, 0.16, 0.23, 0.30`.
- Custos e essências: valores exatos da Task 2.
- `config/version` em `project.godot` precisa ficar acima da versão do `main` (hoje `0.10.1`).
- Commits terminam com `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>`. Sem `git push` e sem PR: isso é decisão do usuário.

## Diferenças em relação ao spec (decididas ao ler o código)

- **Sem conferência de distância até o Doran.** Nenhuma operação do serviço confere posição (comprar na Mira também não). Manter igual; o painel só abre pelo diálogo.
- **Sem mudança no `hit_guard`.** Ele não tem teto de dano, só mínimo e alcance.
- **O pedido leva só o elemento** (`["fogo"]`), não o id da arma: vale sempre a arma equipada.

## Review Focus

1. **Servidor antigo sem a tabela `enchant`:** o cliente recebe tabelas sem ela. O painel deve dizer "Encantamento indisponível neste servidor" e nada pode quebrar. (Task 7)
2. **Save ou banco com encanto inválido** (arma desconhecida, elemento desconhecido, nível 0, 9 ou texto): entra sanitizado, sem erro de script. (Task 3)
3. **Arma trocada com o painel aberto:** o painel passa a mostrar a arma nova e o custo dela. (Task 7)
4. **Clique duplo em "Encantar":** só um pedido sai; o botão fica desligado até a resposta. (Task 7)
5. **Arma encantada desequipada:** o brilho some no jogador e na réplica dos outros. (Task 6)

---

### Task 1: Trazer o protótipo para o `main` atual

**Files:**
- Modify (conflitos esperados): `scripts/player/player.gd`, `scripts/autoload/network.gd`, `tests/net_test.gd`, `project.godot`
- Move: `scenes/vfx_lab.tscn` → `tools/vfx_lab.tscn`; `scripts/vfx/vfx_lab.gd` → `tools/vfx_lab.gd`
- Delete: pasta `shots/`
- Mantidos como estão: `scripts/vfx/enchant_fx.gd`, `scripts/vfx/buff_aura.gd`, `shaders/enchant_overlay.gdshader`, `shaders/aura_*.gdshader`

**Interfaces:**
- Produces (já existem no protótipo, precisam sobreviver ao merge):
  - `EnchantFX.apply(look: Dictionary, element: String, level: int) -> void`, `EnchantFX.ELEMENTS`, `EnchantFX.MAX_LEVEL`
  - `BuffAura.set_styles(styles: Array) -> void`, `BuffAura.styles() -> Array`, `BuffAura.refresh() -> void`, `BuffAura.STYLES`, `BuffAura.style_for(food_id: String) -> String`
  - `Player.set_ability_aura(style: String, on: bool) -> void`, `Player.vfx_aura`, `Player._vfx_state() -> Dictionary`, `Player._vfx_apply(fx: Dictionary, rebuilt: bool) -> void`
  - `look["fx"] = {"auras": Array, "en": String, "lv": int}`; `Network._clean_fx(fx) -> Dictionary`

- [ ] **Step 1: Commitar o protótipo como está** (hoje está sem commit), sem a pasta `shots/`.

```bash
git add scripts/vfx shaders scenes/vfx_lab.tscn scripts/player/player.gd scripts/autoload/network.gd tests/net_test.gd docs/superpowers
git commit -m "VFX: protótipo de aura de buff e brilho de encantamento"
```

- [ ] **Step 2: `git merge main`** e resolver os conflitos. Em `player.gd` e `network.gd` vale a versão do `main`; por cima dela reaplicar somente: o bloco "VFX (protótipo)" no fim de `player.gd`, as chamadas `_vfx_setup()`, `_vfx_sync()` e a nova `apply_look`/`_update_equipment_visual`, e em `network.gd` a linha `out["fx"] = _clean_fx(look.get("fx"))` com a função `_clean_fx`. Em `net_test.gd` manter o bloco "efeitos visuais" depois da troca para o cajado.

- [ ] **Step 3: Mover o laboratório para `tools/`** (como `tools/blacksmith_shot.*`), ajustar o caminho do script na cena, apagar `shots/`.

- [ ] **Step 4: Subir `config/version`** para `0.11.0`.

- [ ] **Step 5: Importar e rodar tudo**

```bash
$G --headless --path . --import 2>&1 | grep -A2 "SCRIPT ERROR"      # esperado: nada
$G --headless --path . -s tests/unit/run.gd                          # esperado: sai com 0
$G --headless --path . res://scenes/world.tscn -- --smoketest        # esperado: "OK (0 falhas)"
```

Mais o teste de multiplayer da Horda (comandos na skill `smoke-check`, item 3). Esperado: `NETTEST OK (0 falhas)` nos dois clientes, incluindo "vê as auras e o encanto dos outros jogadores".

- [ ] **Step 6: Commit** `git commit -m "VFX: merge do main (0.10.1) e laboratório em tools/"`

---

### Task 2: Tabela `enchant` e materiais

**Files:**
- Create: `data/balance/enchant.json`
- Modify: `scripts/balance/balance_tables.gd` (lista `NAMES`), `data/balance/items.json`
- Test: `tests/unit/test_balance.gd`

**Interfaces:**
- Produces: `bt.get_table("enchant")` com o formato abaixo; nove itens novos do tipo `material`.

- [ ] **Step 1: Escrever o teste que falha** em `tests/unit/test_balance.gd`

```gdscript
func test_enchant_table() -> void:
	var bt := BalanceTables.load_dir("res://data/balance")
	var e: Dictionary = bt.get_table("enchant")
	var items: Dictionary = bt.get_table("items")
	T.eq(e.get("max_level"), 5, "nível máximo")
	T.eq(e.get("damage"), [0.05, 0.10, 0.16, 0.23, 0.30], "bônus de dano por nível")
	T.eq(e.get("elements", {}).keys(), ["fogo", "gelo", "raio", "veneno", "sagrado", "sombra"], "seis elementos, em ordem")
	T.eq(e.get("levels", []).size(), 5, "um custo por nível")
	for el in e.elements:
		T.ok(items.has(e.elements[el].essence), "essência de %s existe em items" % el)
	for id in ["iron_ore", "arcane_crystal", "champion_badge"]:
		T.ok(items.get(id, {}).get("type") == "material" and items[id].get("stack", false), "%s é material empilhável" % id)
	for lv in e.levels:
		for id in lv.get("items", {}):
			T.ok(items.has(id), "item de custo %s existe" % id)
```

- [ ] **Step 2: Rodar e ver falhar** — `$G --headless --path . -s tests/unit/run.gd` → FALHA em `test_enchant_table`.

- [ ] **Step 3: Criar `data/balance/enchant.json`** com exatamente:

```json
{
	"max_level": 5,
	"damage": [0.05, 0.10, 0.16, 0.23, 0.30],
	"elements": {
		"fogo":    {"name": "Fogo",    "essence": "ember_core",    "effect": "Queimadura"},
		"gelo":    {"name": "Gelo",    "essence": "frost_drop",    "effect": "Lentidão"},
		"raio":    {"name": "Raio",    "essence": "thunder_totem", "effect": "Corrente"},
		"veneno":  {"name": "Veneno",  "essence": "toxic_gland",   "effect": "Marca tóxica"},
		"sagrado": {"name": "Sagrado", "essence": "golden_dust",   "effect": "Ruína de chefes"},
		"sombra":  {"name": "Sombra",  "essence": "shadow_fang",   "effect": "Roubo de vida"}
	},
	"levels": [
		{"gold": 50,   "ecos": 0,  "essence": 2,  "items": {"iron_ore": 4}},
		{"gold": 120,  "ecos": 0,  "essence": 4,  "items": {"iron_ore": 8}},
		{"gold": 250,  "ecos": 0,  "essence": 6,  "items": {"iron_ore": 12, "arcane_crystal": 4}},
		{"gold": 500,  "ecos": 0,  "essence": 8,  "items": {"iron_ore": 16, "arcane_crystal": 8, "champion_badge": 1}},
		{"gold": 1000, "ecos": 40, "essence": 10, "items": {"iron_ore": 20, "arcane_crystal": 12}}
	],
	"swap": {"gold": 100, "essence": 3},
	"sources": {
		"iron_ore": "veios de ferro perto do Acampamento Goblin",
		"arcane_crystal": "cristais arcanos nas Ruínas",
		"ember_core": "Slimes Explosivos, no Ninho de Slimes",
		"frost_drop": "Slimes Velozes, no Ninho de Slimes",
		"thunder_totem": "Goblins Xamãs, no Acampamento Goblin",
		"toxic_gland": "Slimes Mães, no Ninho de Slimes",
		"golden_dust": "Goblins Dourados, que aparecem pelo mapa",
		"shadow_fang": "lobos, na floresta entre a vila e as Ruínas",
		"champion_badge": "o Campeão Goblin, no Acampamento Goblin"
	}
}
```

`levels[i]` é o custo para chegar ao nível `i + 1`. `effect` é só o nome mostrado no painel; o efeito em si é da Parte 3.

- [ ] **Step 4: Registrar** `"enchant"` em `BalanceTables.NAMES` e criar em `items.json` os nove materiais (`"type": "material"`, `"stack": true`, `"rarity"`, `"price"`, `"color"`, `"desc"` no mesmo formato de `slime_gel`):

| id | name | price | rarity |
|---|---|---|---|
| `iron_ore` | Minério de Ferro | 6 | common |
| `arcane_crystal` | Cristal Arcano | 14 | uncommon |
| `ember_core` | Núcleo em Brasa | 10 | uncommon |
| `frost_drop` | Gota Gélida | 10 | uncommon |
| `thunder_totem` | Totem Trovejante | 12 | uncommon |
| `toxic_gland` | Glândula Tóxica | 12 | uncommon |
| `golden_dust` | Pó Dourado | 25 | rare |
| `shadow_fang` | Presa Sombria | 12 | uncommon |
| `champion_badge` | Insígnia do Campeão | 60 | epic |

- [ ] **Step 5: Rodar e ver passar** — `$G --headless --path . -s tests/unit/run.gd` → sai com 0.

- [ ] **Step 6: Commit** `git commit -m "Encantamento: tabela enchant e materiais"`

---

### Task 3: `CharState.enchants` e `EnchantRules`

**Files:**
- Create: `scripts/character/enchant_rules.gd`
- Modify: `scripts/character/char_state.gd` (campo, `to_dict`, `from_dict`)
- Test: `tests/unit/test_enchant_rules.gd` (novo)

**Interfaces:**
- Consumes: `bt.get_table("enchant")` (Task 2); `CharRules.count_item`, `CharRules.remove_item`, `CharRules._ok`, `CharRules._fail`, `CharRules._notify`.
- Produces:
  - `CharState.enchants: Dictionary` — `{weapon_id: {"el": String, "lv": int}}`
  - `EnchantRules.of(s: CharState, weapon_id: String) -> Dictionary` — `{"el", "lv"}`; sem encanto: `{"el": "", "lv": 0}`
  - `EnchantRules.cost(s: CharState, bt: BalanceTables, element: String) -> Dictionary` — `{"ok": bool, "err": String, "kind": "up"|"swap", "to": int, "gold": int, "ecos": int, "items": {id: qty}}` para a arma equipada, com a essência já somada em `items`
  - `EnchantRules.enchant(s: CharState, bt: BalanceTables, element: String) -> Dictionary` — `{"ok", "err", "events"}`
  - `EnchantRules.mods(s: CharState, bt: BalanceTables) -> Dictionary` — `{"damage": float}` da arma equipada; `{}` sem encanto
  - Erros: `sem_tabela`, `sem_arma`, `elemento_invalido`, `nivel_maximo`, `sem_ouro`, `sem_ecos`, `sem_material`
  - Evento de sucesso: `{"t": "enchant", "id": weapon_id, "el": element, "lv": int}` mais um `notify`

Regra de `cost`/`enchant`, sobre o encanto atual `{el, lv}` da arma equipada:
- `lv == 0`, ou `element == el` e `lv < max` → **subir**: vai a `lv + 1` com `element`, custo `levels[lv]` (ouro, Ecos, itens e `essence` unidades da essência de `element`).
- `element != el` e `lv > 0` → **trocar**: mantém `lv`, custo `swap` (ouro e `essence` unidades da essência de `element`).
- `element == el` e `lv == max` → `nivel_maximo`.
- Ordem das recusas: `sem_tabela`, `sem_arma`, `elemento_invalido`, `nivel_maximo`, `sem_ouro`, `sem_ecos`, `sem_material`.

- [ ] **Step 1: Escrever os testes que falham** em `tests/unit/test_enchant_rules.gd`

```gdscript
extends RefCounted
## Encantamento de armas: regras puras com as tabelas reais.

var _bt: BalanceTables


func _tables() -> BalanceTables:
	if _bt == null:
		_bt = BalanceTables.load_dir("res://data/balance")
	return _bt


## Personagem com a arma inicial (azure_edge) e os recursos dados.
func _rich(gold := 0, ecos := 0, items := {}) -> CharState:
	var s := CharState.new_character(_tables())
	s.gold = gold
	s.ecos = ecos
	for id in items:
		CharRules.add_item(s, _tables(), id, items[id])
	return s


func test_first_level_cost_and_result() -> void:
	var bt := _tables()
	var s := _rich(60, 0, {"iron_ore": 5, "ember_core": 3})
	var c := EnchantRules.cost(s, bt, "fogo")
	T.ok(c.ok and c.kind == "up" and c.to == 1, "sobe para +1")
	T.eq(c.gold, 50, "50 de ouro")
	T.eq(c.items, {"iron_ore": 4, "ember_core": 2}, "4 ferro e 2 essências")
	var r := EnchantRules.enchant(s, bt, "fogo")
	T.ok(r.ok, "encantou")
	T.eq(EnchantRules.of(s, "azure_edge"), {"el": "fogo", "lv": 1}, "arma +1 de fogo")
	T.eq(s.gold, 10, "ouro debitado")
	T.eq(CharRules.count_item(s, "iron_ore"), 1, "ferro debitado")
	T.eq(CharRules.count_item(s, "ember_core"), 1, "essência debitada")
	T.eq(EnchantRules.mods(s, bt), {"damage": 0.05}, "+5% de dano")


func test_refusals_keep_state() -> void:
	var bt := _tables()
	var s := _rich(49, 0, {"iron_ore": 4, "ember_core": 2})
	var before := s.to_dict()
	T.eq(EnchantRules.enchant(s, bt, "fogo").err, "sem_ouro", "falta ouro")
	T.eq(EnchantRules.enchant(s, bt, "luz").err, "elemento_invalido", "elemento desconhecido")
	s.gold = 50
	CharRules.remove_item(s, "ember_core", 1)
	before = s.to_dict()
	T.eq(EnchantRules.enchant(s, bt, "fogo").err, "sem_material", "falta essência")
	T.eq(s.to_dict(), before, "estado intacto")
	s.equipment.weapon = ""
	T.eq(EnchantRules.enchant(s, bt, "fogo").err, "sem_arma", "sem arma equipada")


func test_swap_keeps_level() -> void:
	var bt := _tables()
	var s := _rich(100, 0, {"frost_drop": 3})
	s.enchants["azure_edge"] = {"el": "fogo", "lv": 3}
	var c := EnchantRules.cost(s, bt, "gelo")
	T.ok(c.ok and c.kind == "swap" and c.to == 3, "troca mantém +3")
	T.eq(c.gold, 100, "taxa de troca")
	T.eq(c.items, {"frost_drop": 3}, "3 essências do elemento novo")
	T.ok(EnchantRules.enchant(s, bt, "gelo").ok, "trocou")
	T.eq(EnchantRules.of(s, "azure_edge"), {"el": "gelo", "lv": 3}, "gelo +3")
	T.eq(s.gold, 0, "ouro debitado")


func test_level_five_needs_ecos_and_max() -> void:
	var bt := _tables()
	var s := _rich(1000, 39, {"iron_ore": 20, "arcane_crystal": 12, "shadow_fang": 10})
	s.enchants["azure_edge"] = {"el": "sombra", "lv": 4}
	T.eq(EnchantRules.enchant(s, bt, "sombra").err, "sem_ecos", "faltam Ecos")
	s.ecos = 40
	T.ok(EnchantRules.enchant(s, bt, "sombra").ok, "+5")
	T.eq(s.ecos, 0, "40 Ecos debitados")
	T.eq(EnchantRules.mods(s, bt), {"damage": 0.30}, "+30% de dano")
	T.eq(EnchantRules.enchant(s, bt, "sombra").err, "nivel_maximo", "não passa de +5")


func test_enchant_follows_weapon_type() -> void:
	var bt := _tables()
	var s := _rich()
	s.enchants["azure_edge"] = {"el": "raio", "lv": 2}
	T.eq(EnchantRules.mods(s, bt), {"damage": 0.10}, "arma equipada encantada")
	T.ok(CharRules.equip(s, bt, "short_bow").ok, "troca para o arco")
	T.eq(EnchantRules.mods(s, bt), {}, "arco sem encanto: sem bônus")
	T.ok(CharRules.sell(s, bt, "azure_edge").ok, "vende a espada")
	T.eq(EnchantRules.of(s, "azure_edge"), {"el": "raio", "lv": 2}, "o encanto fica guardado")


func test_state_roundtrip_sanitizes() -> void:
	var bt := _tables()
	var s := _rich()
	s.enchants["azure_edge"] = {"el": "fogo", "lv": 2}
	T.eq(CharState.from_dict(s.to_dict(), bt).enchants, {"azure_edge": {"el": "fogo", "lv": 2}}, "ida e volta")
	var d := s.to_dict()
	d["enchants"] = {"azure_edge": {"el": "fogo", "lv": 9.0}, "espada_fantasma": {"el": "fogo", "lv": 1},
		"short_bow": {"el": "luz", "lv": 2}, "iron_sword": {"el": "gelo", "lv": 0}, "bread": {"el": "gelo", "lv": 1},
		"apprentice_staff": "texto", 7: {"el": "gelo", "lv": 1}}
	T.eq(CharState.from_dict(d, bt).enchants, {"azure_edge": {"el": "fogo", "lv": 5}},
		"nível limitado a 5; arma, elemento, nível e formato inválidos descartados")
	d["enchants"] = "lixo"
	T.eq(CharState.from_dict(d, bt).enchants, {}, "campo de tipo errado vira vazio")


func test_missing_table() -> void:
	var bt := BalanceTables.from_dict({"items": _tables().get_table("items"), "rules": _tables().get_table("rules")})
	var s := CharState.new()
	s.equipment = CharRules.empty_equipment()
	s.equipment.weapon = "azure_edge"
	T.eq(EnchantRules.enchant(s, bt, "fogo").err, "sem_tabela", "sem tabela enchant não quebra")
	T.eq(EnchantRules.mods(s, bt), {}, "sem tabela: sem bônus")
```

- [ ] **Step 2: Rodar e ver falhar** — `$G --headless --path . --import` e depois `$G --headless --path . -s tests/unit/run.gd` → FALHA (classe `EnchantRules` não existe).

- [ ] **Step 3: Adicionar `enchants` ao `CharState`**: campo `var enchants := {}`, incluído em `to_dict()` (cópia profunda) e em `from_dict()`. Em `from_dict`: aceita só `Dictionary`; cada chave precisa ser `String` cujo item (com `bt`) tenha `type == "weapon"`; o valor precisa ser `Dictionary` com `el` `String` presente em `enchant.elements` (com `bt`) e `lv` numérico ≥ 1, limitado a `max_level`. O resto é descartado em silêncio.

- [ ] **Step 4: Implementar `scripts/character/enchant_rules.gd`** (`class_name EnchantRules`, `extends RefCounted`) com as quatro funções da seção Interfaces. Mensagem de sucesso: `"<nome da arma>: <nome do elemento> +<nível>"` com a cor `C_GOLD`.

- [ ] **Step 5: Importar, rodar e ver passar** — `$G --headless --path . --import`; `$G --headless --path . -s tests/unit/run.gd` → sai com 0.

- [ ] **Step 6: Commit** `git commit -m "Encantamento: regras puras e campo enchants no personagem"`

---

### Task 4: Operação `enchant` no serviço e gravação

**Files:**
- Modify: `scripts/character/character_service.gd` (`CLIENT_OPS`, `ARGS`, `_dispatch`, `apply`), `scripts/server/migrations.gd`, `scripts/server/sqlite_char_store.gd` (ler e gravar a coluna), `scripts/autoload/econ.gd` (concessão de itens de teste)
- Test: `tests/unit/test_character_service.gd`, `tests/unit/test_db.gd`, `tests/unit/test_file_char_store.gd`

**Interfaces:**
- Consumes: `EnchantRules.enchant` (Task 3).
- Produces:
  - `CharacterService.apply(account_id, "enchant", [element: String])` → `{"ok", "err", "events", "state"}`; `state` traz `enchants`.
  - Coluna `characters.enchants TEXT NOT NULL DEFAULT '{}'` (JSON), em uma migração nova no fim de `MIGRATIONS`.
  - `economy_log`: linhas com `kind = "enchant"`, `source = "enchant"`, uma por ouro e por item debitado; os Ecos entram com `kind = "ecos"` e `item_id = "enchant"`.
  - `Econ.request_test_items(items: Dictionary) -> void`: como `request_test_gold`, só em servidor `--test`; concede até 99 de cada item conhecido.

- [ ] **Step 1: Escrever os testes que falham**

Em `test_character_service.gd` (usar o mesmo armazenamento em memória e os auxiliares que o arquivo já tem para `buy_passive`):

```gdscript
func test_enchant_persists_and_logs() -> void:
	var svc := _service()                       # auxiliar existente do arquivo
	svc.grant(1, 50, 0, {"iron_ore": 4, "ember_core": 2}, "test")
	var r := svc.apply(1, "enchant", ["fogo"])
	T.ok(r.ok, "encantou pelo serviço")
	T.eq(r.state.enchants, {"azure_edge": {"el": "fogo", "lv": 1}}, "estado devolvido traz o encanto")
	var rows := _log_rows("enchant")            # linhas de economy_log com source "enchant"
	T.eq(rows.size(), 3, "ouro, ferro e essência registrados")
	T.ok(_reload(svc, 1).enchants.has("azure_edge"), "gravado: sobrevive a recarregar")


func test_enchant_bad_args() -> void:
	var svc := _service()
	T.eq(svc.apply(1, "enchant", []).err, "args", "sem argumento")
	T.eq(svc.apply(1, "enchant", [3]).err, "args", "tipo errado")
	T.eq(svc.apply(1, "enchant", ["luz"]).err, "elemento_invalido", "elemento desconhecido")
```

Se o arquivo não tiver auxiliares com esses nomes, usar os equivalentes que ele já usa nos testes de `buy_passive`.

Em `test_db.gd`: abrir um banco novo, aplicar as migrações, gravar pelo `SqliteCharStore` um personagem com `enchants = {"azure_edge": {"el": "gelo", "lv": 3}}`, ler de volta e conferir igualdade; conferir que `Migrations.latest()` subiu em 1.

Em `test_file_char_store.gd`: mesma ida e volta pelo `FileCharStore`.

- [ ] **Step 2: Rodar e ver falhar** — `$G --headless --path . -s tests/unit/run.gd`.

- [ ] **Step 3: Implementar.** `"enchant"` entra em `CLIENT_OPS`; `ARGS["enchant"] = {"types": [TYPE_STRING], "optional": 0}`; `_dispatch` chama `EnchantRules.enchant(s, _bt, a[0])`; em `apply`, o `_persist` do `enchant` usa `source = "enchant"` e `ecos_item = "enchant"`. Migração nova: `ALTER TABLE characters ADD COLUMN enchants TEXT NOT NULL DEFAULT '{}'`. `SqliteCharStore` lê e grava a coluna como JSON, junto de `equipment`. `Econ.request_test_items` segue o molde de `request_test_gold` / `_grant_test_gold`.

- [ ] **Step 4: Rodar e ver passar** — `$G --headless --path . -s tests/unit/run.gd` → sai com 0.

- [ ] **Step 5: Commit** `git commit -m "Encantamento: operação enchant no serviço, migração e registro da economia"`

---

### Task 5: Espelho no cliente e bônus de dano

**Files:**
- Modify: `scripts/autoload/game.gd` (campo, `apply_state`, `mod()`), `scripts/ui/item_tooltip.gd` ou `ItemDB.item_summary` (linha do encanto)
- Test: `tests/smoke_test.gd`

**Interfaces:**
- Consumes: `EnchantRules.mods`, `EnchantRules.of`; `Econ.request("enchant", [element])`; `Econ.grant(gold, xp, items, source)`.
- Produces:
  - `Game.enchants: Dictionary` (espelho de `CharState.enchants`)
  - `Game.enchant_mods: Dictionary`, recalculado em `apply_state` e somado em `Game.mod(k)`
  - `Game.weapon_enchant() -> Dictionary` — `{"el", "lv"}` da arma equipada
  - sinal `Game.enchant_changed` emitido quando `weapon_enchant()` muda (troca de arma ou encanto novo)

- [ ] **Step 1: Escrever o teste que falha** em `tests/smoke_test.gd`, num bloco novo depois dos testes de loja:

```gdscript
	# ---- encantamento (solo: o serviço local decide)
	var dmg_plain := Game.melee_damage()
	Econ.grant(50, 0, {"iron_ore": 4, "ember_core": 2}, "test", true)
	Econ.request("enchant", ["fogo"])
	await wait(0.2)
	check(Game.weapon_enchant() == {"el": "fogo", "lv": 1}, "arma equipada encantada: fogo +1")
	check(abs(Game.melee_damage() - dmg_plain * 1.05) < 0.01, "encanto +1 dá +5% de dano")
	check(Game.count_item("iron_ore") == 0 and Game.count_item("ember_core") == 0, "materiais gastos")
	Econ.request("enchant", ["fogo"])
	await wait(0.2)
	check(Game.weapon_enchant().lv == 1, "sem recursos não sobe")
```

Usar os nomes de `wait`/`check` e de contagem de item que o arquivo já usa.

- [ ] **Step 2: Rodar e ver falhar** — `$G --headless --path . res://scenes/world.tscn -- --smoketest`.

- [ ] **Step 3: Implementar** o espelho e o bônus. `mod("damage")` já multiplica o dano em `melee_damage()`; o encanto entra como mais uma parcela da soma em `mod()`.

- [ ] **Step 4: Mostrar o encanto na dica do item:** para arma com encanto, uma linha `"<Elemento> +<nível> · +<N>% de dano"` na cor do elemento (`EnchantFX.ELEMENTS[el].color`).

- [ ] **Step 5: Rodar e ver passar** — smoke test → `OK (0 falhas)`.

- [ ] **Step 6: Commit** `git commit -m "Encantamento: espelho no cliente, bônus de dano e dica do item"`

---

### Task 6: Brilho definido pelo servidor

**Files:**
- Modify: `scripts/player/player.gd` (bloco VFX), `scripts/autoload/network.gd` (`_clean_look`, reenvio), `scripts/autoload/econ.gd`
- Test: `tests/net_test.gd`

**Interfaces:**
- Consumes: `Game.weapon_enchant()`, `Game.enchant_changed` (Task 5); `Econ.request_test_items` (Task 4); `CharacterService.load_or_create`.
- Produces:
  - `Econ.server_weapon_enchant(peer: int) -> Dictionary` — `{"el", "lv"}` da arma equipada da conta daquele peer, lido do serviço
  - `Network.server_refresh_look(peer: int) -> void` — recalcula `players[peer].look["fx"]` e reenvia a todos
  - `Player._vfx_state()` passa a tirar `en`/`lv` de `Game.weapon_enchant()`

- [ ] **Step 1: Trocar o bloco de teste do protótipo em `net_test.gd`** (o que mexe em `vfx_enchant_el`/`vfx_enchant_lv`) por:

```gdscript
	# encanto de verdade: o servidor decide e todos veem
	Game.food_buffs["spicy_soup"] = 60.0
	w.player.set_ability_aura("escudo", true)
	Econ.request_test_gold(200)
	Econ.request_test_items({"iron_ore": 4, "frost_drop": 2})
	await wait(0.5)
	Econ.request("enchant", ["gelo"])
	check(await _wait_until(func() -> bool: return Game.weapon_enchant() == {"el": "gelo", "lv": 1}, 5.0),
		"servidor encantou a arma equipada")
	var my_fx: Dictionary = w.player._last_look.get("fx", {})
	check(my_fx.get("auras", []) == ["escudo", "furia"] and my_fx.get("en", "") == "gelo" and my_fx.get("lv", 0) == 1,
		"auras e encanto no visual local")
	if peers > 1:
		check(await _wait_until(func() -> bool:
			for rp in Network.remote_players.values():
				var fx: Dictionary = rp._last_look.get("fx", {})
				if fx.get("auras", []) != ["escudo", "furia"] or fx.get("en", "") != "gelo" or fx.get("lv", 0) != 1:
					return false
			return true, 6.0), "vê as auras e o encanto dos outros jogadores")
	# o cliente não consegue declarar um encanto que o servidor não gravou
	var fake: Dictionary = w.player._last_look.duplicate(true)
	fake["fx"]["en"] = "sombra"
	fake["fx"]["lv"] = 5
	Network.send_look(fake)
	await wait(1.0)
	if peers > 1:
		for rp in Network.remote_players.values():
			check(rp._last_look.get("fx", {}).get("lv", 0) == 1, "encanto falso de %s é ignorado" % rp.display_name)
	# desequipar a arma apaga o brilho para todos
	Econ.request("unequip", ["weapon"])
	check(await _wait_until(func() -> bool: return w.player._last_look.get("fx", {}).get("lv", -1) == 0, 5.0),
		"sem arma: sem brilho no jogador")
	if peers > 1:
		check(await _wait_until(func() -> bool:
			for rp in Network.remote_players.values():
				if rp._last_look.get("fx", {}).get("lv", -1) != 0:
					return false
			return true, 6.0), "sem arma: o brilho some na réplica dos outros")
	Game.food_buffs.erase("spicy_soup")
	w.player.set_ability_aura("escudo", false)
```

Como os dois clientes rodam o mesmo roteiro, cada um vê o outro com encanto `gelo +1`. Manter as duas verificações de réplica do protótipo ("aura montada na réplica", "encanto aplicado na arma da réplica") logo depois de "vê as auras e o encanto dos outros jogadores".

- [ ] **Step 2: Rodar e ver falhar** — teste de multiplayer da Horda (skill `smoke-check`, item 3) → FALHA em "encanto falso ... é ignorado".

- [ ] **Step 3: Implementar.** No servidor, `_clean_look` passa a ignorar `en`/`lv` vindos do cliente e a preenchê-los com `Econ.server_weapon_enchant(peer)`; as auras continuam vindo do cliente, filtradas. Depois de um `enchant`, `equip` ou `unequip` aceito, o servidor chama `Network.server_refresh_look(peer)`. No cliente, `_vfx_state()` lê `Game.weapon_enchant()` e `Game.enchant_changed` dispara `_update_equipment_visual()`.

- [ ] **Step 4: Remover os atalhos de teste do protótipo:** teclas F7/F8 (`_unhandled_key_input`), variáveis `vfx_enchant_el`/`vfx_enchant_lv` e o argumento `--enchant`. Ficam `--buffs`, `--auras` e `--vfxwalk`.

- [ ] **Step 5: Rodar e ver passar** — multiplayer da Horda → `NETTEST OK (0 falhas)` nos dois clientes; smoke test → `OK (0 falhas)`.

- [ ] **Step 6: Commit** `git commit -m "Encantamento: brilho definido pelo servidor e visto por todos"`

---

### Task 7: Painel do Doran

**Files:**
- Create: `scripts/ui/enchant_ui.gd`
- Modify: `scripts/world/npc.gd` (diálogo do ferreiro), `scripts/world/world.gd` (`open_enchant`), `scripts/world/blacksmith.gd` (golpe de encanto)
- Test: `tests/smoke_test.gd`

**Interfaces:**
- Consumes: `Game.weapon_enchant()`, `Game.enchant_changed`, `EnchantRules.cost`, `Econ.request("enchant", [el])`, `Econ.result`/`Econ.done`, `Balance.tables`, `UITheme`, `EnchantFX`, `KnightLook`.
- Produces:
  - `world.open_enchant() -> void` (abre o painel como modal, igual a `open_shop`)
  - `EnchantUI` com sinal `closed` e, para os testes: `selected: String` (elemento escolhido), `enchant_button: Button`, `status_text() -> String`, `select(element: String) -> void`, `cost_rows() -> Array` (cada linha `{"id", "need", "have", "ok"}`; ouro com id `""`, Ecos com id `"$ecos"`)
  - `Blacksmith.enchant_strike(color: Color) -> void` — um golpe na bigorna com faíscas na cor dada e o som da bigorna

Comportamento do painel (seção 5.5 do spec):
- Título: `"Encantar: <arma>"`, com `"+<nível> (<Elemento>)"` quando já tem encanto.
- Seis botões de elemento; o do encanto atual vem marcado. Ao abrir, o selecionado é o elemento atual, ou `fogo` se não houver.
- Linha "Próximo nível" com o dano atual → novo; na troca de elemento, `"Trocar para <Elemento> (mantém +<nível>)"`.
- Tabela de custo com "Você tem" e ✓/✗ por linha. Para cada linha em falta, uma frase `"Falta: <n> <item> (<enchant.sources[id]>)"`.
- Botão "Encantar" desligado quando falta algo, no nível máximo (texto `"Nível máximo"`) ou enquanto um pedido está pendente.
- Prévia da arma com o brilho do nível resultante (`EnchantFX.apply` sobre um `KnightLook.apply`).
- Erros do serviço → texto: `sem_ouro` "Ouro insuficiente.", `sem_ecos` "Ecos insuficientes.", `sem_material` "Faltam materiais.", `nivel_maximo` "Esta arma já está no nível máximo.", `sem_arma` "Equipe uma arma primeiro.", `sem_tabela` "Encantamento indisponível neste servidor."
- Sem arma equipada: só a mensagem "Equipe uma arma primeiro." e o botão Fechar.
- Tabela `enchant` vazia: só "Encantamento indisponível neste servidor." e o botão Fechar.
- Fecha com `E`/Esc como os outros painéis.

Diálogo do Doran: a última página ganha as opções `"Encantar arma"` (abre o painel) e `"Até logo"`.

- [ ] **Step 1: Escrever os testes que falham** em `tests/smoke_test.gd`, depois do bloco da Task 5 (a arma está em fogo +1, sem materiais):

```gdscript
	# ---- painel do Doran
	w.open_enchant()
	var eui = w.modal
	check(eui != null and eui.selected == "fogo", "painel abre no elemento atual da arma")
	check(eui.enchant_button.disabled, "sem materiais: botão desligado")
	check("veios de ferro" in eui.status_text(), "painel diz onde achar o que falta")
	Econ.grant(120, 0, {"iron_ore": 8, "ember_core": 4}, "test", true)
	await wait(0.2)
	check(not eui.enchant_button.disabled, "com materiais: botão ligado")
	eui.enchant_button.pressed.emit()
	check(eui.enchant_button.disabled, "pedido pendente: botão desligado (sem clique duplo)")
	eui.enchant_button.pressed.emit()
	await wait(0.3)
	check(Game.weapon_enchant() == {"el": "fogo", "lv": 2}, "um clique duplo sobe um nível só")
	eui.select("gelo")
	var gold_row: Dictionary = eui.cost_rows()[0]
	check(gold_row.id == "" and gold_row.need == 100, "trocar de elemento mostra a taxa de troca")
	# arma trocada com o painel aberto
	Econ.request("equip", ["short_bow"])
	await wait(0.3)
	check("Arco Curto" in eui.status_text(), "painel acompanha a troca de arma")
	check(eui.cost_rows()[0].need == 50, "arma nova: custo do +1")
	Econ.request("equip", ["azure_edge"])
	await wait(0.3)
	# servidor antigo, sem a tabela
	var keep: Dictionary = Balance.tables.to_dict()
	var no_table := keep.duplicate(true)
	no_table.erase("enchant")
	Balance.apply(no_table)
	await wait(0.1)
	check("indisponível" in eui.status_text() and eui.enchant_button.disabled, "sem tabela enchant: painel avisa e não quebra")
	Balance.apply(keep)
	eui.closed.emit()
	await wait(0.1)
```

`status_text()` devolve o título, a linha de próximo nível, as frases de "Falta" e o aviso, juntos, para os testes.

O roteiro acima supõe que, nesse ponto do smoke test, a arma equipada é `azure_edge` e há um `short_bow` na mochila (kit inicial). Se o smoke test tiver trocado de arma antes, usar as armas que ele tiver nesse ponto e ajustar os nomes esperados.

- [ ] **Step 2: Rodar e ver falhar** — smoke test → falha em `w.open_enchant`.

- [ ] **Step 3: Implementar `enchant_ui.gd`** no molde de `scripts/ui/passive_master_ui.gd` (mesma moldura `UITheme.centered_panel`, mesmo ciclo `Econ.result`/`Econ.done` → redesenhar). O painel redesenha em `Game.enchant_changed`, `Game.inventory_changed` e `Balance.changed`.

- [ ] **Step 4: Ligar ao Doran:** opção no diálogo, `world.open_enchant()`, e `Blacksmith.enchant_strike(color)` chamado quando o `enchant` volta `ok`, com a cor de `EnchantFX.ELEMENTS[el].color`. No servidor dedicado (`_animate == false`) o golpe não faz nada.

- [ ] **Step 5: Rodar e ver passar** — smoke test → `OK (0 falhas)`.

- [ ] **Step 6: Conferir na tela.** Rodar o jogo com janela, falar com o Doran, abrir o painel e encantar. Guardar uma captura do painel e uma do golpe com faíscas (`--shot=` salva um PNG; ver `Game._debug_screenshot`).

- [ ] **Step 7: Rodada final de testes** — import, unitários, smoke, Defesa da Cidade (`--colonytest`), multiplayer da Horda e cidade em grupo, pela skill `smoke-check`. Todos precisam passar.

- [ ] **Step 8: Commit** `git commit -m "Encantamento: painel do Doran"`
