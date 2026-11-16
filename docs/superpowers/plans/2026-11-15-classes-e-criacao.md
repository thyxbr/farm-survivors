# Classes e criação de personagem (Parte 1) — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Classe fixa por personagem (Guerreiro/Arqueiro/Mago/Healer) escolhida numa tela de criação com sexo, que trava a arma e o kit; healer com linha nova de cetros e Cura em área nos aliados.

**Architecture:** A classe e o sexo vivem em `CharState` e são validados por `CharRules` (mesmo código no solo e no servidor via `CharacterService`). O kit de habilidades passa a derivar da classe. A cura em aliados é calculada e distribuída pelo servidor (o cliente só pede). A tela de criação é uma cena nova que fica entre o menu/login e o mundo.

**Tech Stack:** Godot 4 / GDScript, JSON em `data/balance`, Blender CLI (`tools/blender/armory.py`) para os modelos de cetro.

**Spec:** `docs/superpowers/specs/2026-11-15-classes-e-criacao-design.md`

## Global Constraints

- Trabalhar no worktree `C:\Games\godot-3d-classes` (branch `classes-criacao`), nunca no checkout principal.
- Ids de classe: `warrior`, `archer`, `mage`, `healer`. Classe de arma: `sword`, `bow`, `staff`, `scepter`. Sexo: `m`, `f`. `""` = não escolhido.
- Classe não muda depois de escolhida (sem respec).
- Raio da Cura em aliados: **8 m**; atinge o próprio healer e qualquer jogador da mesma zona no raio, com ou sem grupo.
- Loja mostra todas as armas; as de outra classe aparecem marcadas e não podem ser equipadas.
- Drops com nome (`"named": true`) não são trocados de classe.
- Textos para o jogador em português.
- Versão: `config/version` em `project.godot` de `0.21.0` para `0.22.0`.
- Comandos de teste (rodar a partir do worktree; `GODOT` = executável do Godot, ver memória `blender-export-crash`):
  - unitários: `"$GODOT" --headless --path . -s tests/unit/run.gd`
  - smoke: `"$GODOT" --headless --path . res://scenes/world.tscn -- --smoketest`
  - vila: `"$GODOT" --headless --path . res://scenes/world.tscn -- --vilatest`
  - net: ver `.github/workflows` (servidor + Ana/Beto); matar o servidor pelo PID, nunca todos os Godot.

## Review Focus

1. Save solo antigo / personagem online antigo sem `char_class` → abre "Escolha sua classe", não quebra nem entra no mundo sem arma (teste em Task 2 e Task 6).
2. Pedido `choose_class` repetido ou com classe/sexo inválido vindo da rede → recusado sem mudar o estado (Task 2).
3. Cliente que não é healer (ou healer pedindo cura rápido demais) manda `request_heal` → servidor ignora (Task 5).
4. Healer sozinho, sem ninguém perto → ainda se cura (Task 5).
5. Testes automáticos (smoke/vila/net) criam personagens novos → precisam escolher classe sem tela (`--class=`) senão travam (Task 6).

---

### Task 1: Dados de classe, campos no personagem e itens de cetro

**Files:**
- Create: `data/balance/classes.json`
- Modify: `scripts/character/char_state.gd` (campos, `to_dict`, `from_dict`)
- Modify: `scripts/character/char_rules.gd:15` (`CLASS_NAMES`)
- Modify: `data/balance/items.json` (5 cetros)
- Modify: `scripts/autoload/game.gd` (espelho `char_class`, `body` em `apply_state`)
- Test: `tests/unit/test_char_rules.gd`

**Interfaces:**
- Produces: `CharState.char_class: String`, `CharState.body: String`; tabela `classes` com `{id: {"name", "weapon_class", "starter_weapon", "attr", "desc", "color"}}`; `CharRules.CLASS_IDS := ["warrior", "archer", "mage", "healer"]`; `CharRules.class_weapon(bt, cls: String) -> String` (`""` para classe desconhecida); `Game.char_class`, `Game.body`.

- [ ] **Step 1: Testes que falham**

```gdscript
func test_state_class_roundtrip() -> void:
	var s := _blank()
	s.char_class = "healer"; s.body = "f"
	var s2 := CharState.from_dict(s.to_dict(), _tables())
	A.eq(s2.char_class, "healer"); A.eq(s2.body, "f")

func test_state_old_save_has_no_class() -> void:
	var d := _blank().to_dict(); d.erase("char_class"); d.erase("body")
	var s := CharState.from_dict(d, _tables())
	A.eq(s.char_class, ""); A.eq(s.body, "")

func test_state_rejects_unknown_class() -> void:
	var d := _blank().to_dict(); d["char_class"] = "ninja"; d["body"] = "x"
	var s := CharState.from_dict(d, _tables())
	A.eq(s.char_class, ""); A.eq(s.body, "")

func test_class_table_complete() -> void:
	for c in CharRules.CLASS_IDS:
		var w := CharRules.class_weapon(_tables(), c)
		A.true_(w in ["sword", "bow", "staff", "scepter"], c)
		var st: String = _tables().get_table("classes")[c]["starter_weapon"]
		A.eq(CharRules.weapon_class(_tables(), st), w, c)
	A.eq(CharRules.class_weapon(_tables(), "healer"), "scepter")

func test_scepters_one_per_rarity() -> void:
	var seen := {}
	for id in _tables().get_table("items"):
		var it: Dictionary = _tables().get_table("items")[id]
		if it.get("class", "") == "scepter":
			seen[it.rarity] = true
	A.eq(seen.size(), 5)
```

(Use os helpers de asserção que já existem em `tests/unit/assert.gd`; os nomes acima são ilustrativos.)

- [ ] **Step 2: Rodar unitários — esperado FALHAR** (campos inexistentes).

- [ ] **Step 3: Implementar**
  - `classes.json`: warrior→sword/`azure_edge`/attr `str`; archer→bow/`short_bow`/`agi`; mage→staff/`apprentice_staff`/`int`; healer→scepter/`sc_novice_scepter`/`int`. Nomes "Guerreiro", "Arqueiro", "Mago", "Healer"; `desc` de uma linha cada.
  - Garantir que `Balance`/`BalanceTables.load_dir` carregam o arquivo novo (conferir se a lista de tabelas é fixa).
  - 5 itens `class: "scepter"`, ids com prefixo `sc_` (já existe `frost_scepter` como cajado — não reaproveitar): `sc_novice_scepter` common, e um por uncommon/rare/epic/legendary. Dano e preço na escala dos cajados da mesma raridade; `stats` com `spell` e `mp`; campo `"heal"` (bônus % de cura, ex. 0/0.05/0.1/0.15/0.25); `model: "sc_<nome>"`.
  - `CLASS_NAMES` ganha `"scepter": "Cetro"`.
  - `from_dict` aceita só valores de `CLASS_IDS` / `["m","f"]`, senão `""`.

- [ ] **Step 4: Rodar unitários — esperado PASSAR** (e `test_balance` continua passando).

- [ ] **Step 5: Commit** `feat: classes e cetros nos dados do personagem`

---

### Task 2: Escolher classe, travar equipamento e bloquear personagem sem classe

**Files:**
- Modify: `scripts/character/char_rules.gd` (`choose_class`, `equip`, `best_weapon_of`)
- Modify: `scripts/character/char_state.gd:35` (`new_character` sem arma e sem kit "três classes")
- Modify: `scripts/character/character_service.gd` (`ARGS`, `CLIENT_OPS`, `_dispatch`, bloqueio em `apply`)
- Test: `tests/unit/test_char_rules.gd`, `tests/unit/test_character_service.gd`

**Interfaces:**
- Consumes: Task 1.
- Produces: `CharRules.choose_class(s: CharState, bt: BalanceTables, cls: String, body: String) -> Dictionary` (padrão `_ok/_fail`; evento `{"t": "class", "class": cls, "body": body}`); op de rede `"choose_class"` com args `[String, String]`; erro `"sem_classe"` para qualquer outra op com `char_class == ""`.

- [ ] **Step 1: Testes que falham**

```gdscript
func test_choose_class_new_char_gets_starter() -> void:
	var s := _blank()
	var r := CharRules.choose_class(s, _tables(), "healer", "f")
	A.true_(r.ok); A.eq(s.char_class, "healer"); A.eq(s.equipment.weapon, "sc_novice_scepter")

func test_choose_class_only_once() -> void:
	var s := _blank(); CharRules.choose_class(s, _tables(), "mage", "m")
	A.false_(CharRules.choose_class(s, _tables(), "warrior", "m").ok); A.eq(s.char_class, "mage")

func test_choose_class_invalid() -> void:
	var s := _blank()
	A.false_(CharRules.choose_class(s, _tables(), "ninja", "m").ok)
	A.false_(CharRules.choose_class(s, _tables(), "mage", "x").ok)
	A.eq(s.char_class, "")

func test_choose_class_keeps_matching_weapon() -> void:
	var s := _blank(); s.equipment.weapon = "oak_staff"
	CharRules.choose_class(s, _tables(), "mage", "m")
	A.eq(s.equipment.weapon, "oak_staff")

func test_choose_class_equips_best_owned() -> void:
	var s := _blank(); s.equipment.weapon = "azure_edge"
	CharRules.add_item(s, _tables(), "apprentice_staff", 1)
	CharRules.add_item(s, _tables(), "archmage_staff", 1)
	CharRules.choose_class(s, _tables(), "mage", "m")
	A.eq(s.equipment.weapon, "archmage_staff")
	A.eq(_count(s, "azure_edge"), 1)          # antiga volta para a mochila
	A.eq(_count(s, "apprentice_staff"), 1)

func test_equip_other_class_refused() -> void:
	var s := _blank(); CharRules.choose_class(s, _tables(), "warrior", "m")
	CharRules.add_item(s, _tables(), "short_bow", 1)
	var r := CharRules.equip(s, _tables(), "short_bow")
	A.false_(r.ok); A.eq(r.err, "exige_classe")

func test_new_character_has_no_weapon() -> void:
	var s := CharState.new_character(_tables())
	A.eq(s.equipment.weapon, ""); A.eq(_count(s, "short_bow"), 0); A.eq(_count(s, "apprentice_staff"), 0)
```

Em `test_character_service.gd`: personagem sem classe → `apply(acc, "buy", [...])` devolve `err == "sem_classe"`; `apply(acc, "choose_class", ["archer", "m"])` ok e depois `buy` funciona.

- [ ] **Step 2: Rodar unitários — esperado FALHAR.**

- [ ] **Step 3: Implementar**
  - `choose_class`: falha `"ja_tem_classe"` / `"classe_invalida"`; grava; se a arma equipada não é da classe, volta para a mochila e equipa `best_weapon_of(s, bt, weapon_class)` (maior índice de raridade em `rarity.json`, desempate por `damage`), senão cria e equipa a `starter_weapon`; mão secundária com `needs` incompatível volta para a mochila. Aviso "Você agora é <Nome da classe>!".
  - `equip`: arma (`slot == "weapon"`) com `weapon_class != class_weapon(s.char_class)` → `_fail("exige_classe", [_notify("%s é arma de %s." ...)])`. Com `char_class == ""` também falha.
  - `new_character`: remove `azure_edge` equipada e o kit `apprentice_staff`/`short_bow`; mantém o resto.
  - Service: `"choose_class": {"types": [TYPE_STRING, TYPE_STRING], "optional": 0}`; em `apply`, se `s.char_class == ""` e `op != "choose_class"` → `{"ok": false, "err": "sem_classe"}`. `grant`/`kill` não são bloqueados (o mundo não abre sem classe).
  - Atualizar testes existentes que assumem o kit antigo (`_blank` já zera o inventário; procurar `azure_edge` equipada em `new_character` nos testes) dando `choose_class` antes.

- [ ] **Step 4: Rodar unitários — esperado PASSAR.**

- [ ] **Step 5: Commit** `feat: escolha de classe trava a arma do personagem`

---

### Task 3: Drops de arma seguem a classe

**Files:**
- Modify: `scripts/character/loot_rules.gd` (`roll` ganha `char_class`)
- Modify: `scripts/autoload/econ.gd:573` (`server_drop_loot` passa a classe do personagem do peer)
- Modify: `scripts/enemies/enemy.gd:767` (solo passa `Game.char_class`)
- Modify: `data/balance/items.json` (`"named": true`)
- Test: `tests/unit/test_char_rules.gd`

**Interfaces:**
- Produces: `LootRules.roll(bt, kind, rng, char_class := "") -> Dictionary`; `LootRules.adapt_weapon(bt, id: String, char_class: String, rng) -> String`.

- [ ] **Step 1: Testes que falham**

```gdscript
func test_adapt_weapon_to_class_same_rarity() -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var out := LootRules.adapt_weapon(_tables(), "oak_staff", "warrior", rng)
	A.eq(CharRules.weapon_class(_tables(), out), "sword")
	A.eq(_tables().get_table("items")[out].rarity, "uncommon")

func test_adapt_keeps_named_and_own_class_and_non_weapons() -> void:
	var rng := RandomNumberGenerator.new()
	A.eq(LootRules.adapt_weapon(_tables(), "archmage_staff", "warrior", rng), "archmage_staff")
	A.eq(LootRules.adapt_weapon(_tables(), "oak_staff", "mage", rng), "oak_staff")
	A.eq(LootRules.adapt_weapon(_tables(), "health_potion", "mage", rng), "health_potion")
	A.eq(LootRules.adapt_weapon(_tables(), "oak_staff", "", rng), "oak_staff")
```

- [ ] **Step 2: Rodar — FALHAR.**
- [ ] **Step 3: Implementar.** Sorteio uniforme entre armas da classe com a mesma raridade e sem `named`; se não houver nenhuma, devolve o id original. Marcar `"named": true` em toda arma que aparece em recompensa de `quests.json` ou no loot de inimigo com chefe/assinatura em `enemies.json` (gerar a lista com um script único e conferir à mão; inclui `archmage_staff`, `elven_bow`, `guardian_greatsword`). `roll` aplica `adapt_weapon` em cada item sorteado, consumindo o RNG **depois** do sorteio original (não muda a sequência dos outros testes). No servidor, a classe vem de `Network.characters` pela conta do peer.
- [ ] **Step 4: Rodar — PASSAR.**
- [ ] **Step 5: Commit** `feat: drop de arma vira arma da classe do jogador`

---

### Task 4: Kit pela classe, Cura no cetro e ataque básico do cetro

**Files:**
- Modify: `scripts/autoload/item_db.gd:21-41` (`heal` → `class: "scepter"`, `slot: 1`, `level: 1`; `scepter_ward` slot 2 e `scepter_ult` slot 4 com `ready: false`)
- Modify: `scripts/autoload/game.gd:541` (`ability_kit` usa `CharRules.class_weapon(Balance.tables, char_class)`)
- Create: `scripts/player/abilities/scepter_abilities.gd` (padrão de `staff_abilities.gd`; `use`/`tick`/`play_remote`)
- Modify: `scripts/player/player.gd` (`_ab_module` reconhece `scepter`/`sc_`; ataque básico do cetro = esfera de luz curta via `_spawn_projectile` com `kind` novo `"light_orb"`; Cura continua no `match` antigo em `cast`)
- Modify: `scripts/character/char_rules.gd` (`spell_power(s, bt) -> float`, `heal_amount(s, bt) -> float`)
- Test: `tests/unit/test_char_rules.gd`, `tests/smoke_test.gd`

**Interfaces:**
- Produces: `CharRules.heal_amount(s, bt) -> float` = `(30 + 4 * spell_power) * (1 + heal da arma)`; `spell_power` = atributo `int` + soma de `stats.spell` do equipamento (mesma conta de `Game.spell_power()`). Player usa esse valor para a cura local.

- [ ] **Step 1: Testes que falham** — `heal_amount` de um healer com `sc_novice_scepter` e INT 5 é `30 + 4*(5+spell do cetro)`; `ItemDB.kit("staff")` não contém `heal`; `ItemDB.kit("scepter")[0] == "heal"`. Smoke: personagem healer conjura `heal` e a vida sobe.
- [ ] **Step 2: Rodar — FALHAR.**
- [ ] **Step 3: Implementar.** Ataque básico do cetro: alcance ~12 m, mesma cadência do cajado, cor dourada/branca, escala com INT; em `player.gd` o ramo de ataque do cajado passa a tratar `staff` e `scepter` com cor/kind diferentes. Ícone do cetro em `skill_icon.gd`/`IconPainter` se a classe precisar de ícone próprio.
- [ ] **Step 4: Rodar unitários + smoke — PASSAR** (lembrar do flake de projétil: rodar de novo antes de culpar a mudança).
- [ ] **Step 5: Commit** `feat: kit de habilidades pela classe e ataque do cetro`

---

### Task 5: Cura do healer em aliados (rede)

**Files:**
- Modify: `scripts/autoload/network.gd` (`request_heal()` cliente→servidor; `_you_were_healed(amount, from_peer)` servidor→cliente)
- Modify: `scripts/player/player.gd:888` (ramo `"heal"`: online chama `Network.request_heal()`; solo cura local)
- Test: `tests/net_test.gd`

**Interfaces:**
- Consumes: `CharRules.heal_amount` (Task 4), `last_pos`, `zone_peers`, `Network.characters`.
- Produces: `Network.request_heal() -> void`; RPC `_you_were_healed(amount: float, from_peer: int)`.

- [ ] **Step 1: Teste que falha** (net_test): Ana com classe `healer` (via `--class=healer`), Beto `warrior` perto e ferido; Ana conjura `heal`; espera a vida de Beto subir em até 3 s. Beto pedindo `request_heal` direto → nada acontece.
- [ ] **Step 2: Rodar net test — FALHAR.**
- [ ] **Step 3: Implementar.** Servidor em `_request_heal`: recusa se a classe da conta não é `healer` ou se a última cura aceita do peer foi há menos de **2,0 s**; calcula `CharRules.heal_amount` do personagem no servidor; para cada `pid` em `zone_peers(zone_of(id))` (inclui o próprio) com `last_pos[pid].distance_to(last_pos[id]) <= 8.0`, manda `_you_were_healed.rpc_id(pid, amount, id)`. Cliente: `Game.hp = min(max_hp, hp + amount)`, número verde e `_heal_fx`, `stats_changed`. Visual remoto continua pelo `send_event("heal")` existente. No solo nada muda (cura só a si).
- [ ] **Step 4: Rodar net test — PASSAR.**
- [ ] **Step 5: Commit** `feat: cura do healer atinge aliados a 8 m`

---

### Task 6: Tela de criação e fluxo de entrada

**Files:**
- Create: `scenes/char_create.tscn`, `scripts/ui/char_create.gd`
- Modify: `scripts/autoload/game.gd:295-310` (`start_new_game`, `continue_game` → `go_to_world()`)
- Modify: `scripts/autoload/network.gd:826` (cliente, depois de aceito → `Game.go_to_world()`)
- Modify: `scripts/ui/char_preview.gd` (`show_weapon(id: String)` para a prévia sem equipar)
- Modify: UI da loja (marcar arma de outra classe: "arma de <Classe>", cor apagada) e a tela de equipamento (botão Equipar desabilitado)
- Modify: `.github/workflows/*.yml` só se as linhas de comando de teste precisarem de `--class=`
- Test: `tests/smoke_test.gd`, `tests/vila_test.gd`, `tests/net_test.gd`

**Interfaces:**
- Consumes: op `choose_class` (Task 2), `CharPreview`.
- Produces: `Game.go_to_world() -> void` — se `char_class == ""` abre `res://scenes/char_create.tscn`, senão `Loading.go(WORLD_SCENE)`; argumentos `--class=<id>` e `--body=m|f` (com `--smoketest`/`--vilatest`/`--nettest` o padrão é `warrior`/`m`) que pedem `choose_class` sem mostrar a tela.

- [ ] **Step 1: Teste que falha** — smoke: novo jogo com `--class=archer` entra no mundo com `Game.char_class == "archer"` e arco equipado; equipar uma espada da mochila falha com aviso.
- [ ] **Step 2: Rodar — FALHAR.**
- [ ] **Step 3: Implementar a tela** conforme o esboço do spec: botões Masculino/Feminino; 4 cartões de classe (nome, arma, atributo, nomes das habilidades do kit vindos de `ItemDB.kit`); prévia 3D com a arma inicial; "Começar" manda `Econ.request("choose_class", [cls, body])` e, no `done` ok, `Loading.go(WORLD_SCENE)`. Feminino mostra o aviso "visual feminino chega em breve". Personagem antigo (`level > 1` ou inventário não vazio): título "Escolha sua classe" e aviso de que a arma fora da classe vai para a mochila. "Voltar" volta ao menu (online: desconecta). Incluir `body` no que o servidor já replica do visual de cada jogador (mesmo caminho da arma equipada), para a parte 4 usar.
- [ ] **Step 4: Rodar unitários, smoke, vila e net — PASSAR.** Abrir o jogo de verdade, criar um healer feminino e conferir a tela por captura.
- [ ] **Step 5: Commit** `feat: tela de criação com classe e sexo`

---

### Task 7: Modelos dos cetros

**Files:**
- Modify: `tools/blender/armory.py` (5 cetros `sc_*`, mesmo padrão de `finish_staff`)
- Create: `assets/models/sc_*.glb`
- Modify: `scripts/player/weapon_model.gd` se precisar de pegada/posição própria para `scepter`

- [ ] **Step 1:** Gerar pelo Blender CLI (não pelo MCP); cetro ~0,7× o comprimento de um cajado, cabeça com gema/emblema luminoso, paleta clara/dourada; estilo toon (`cel_paint` + `_flat`).
- [ ] **Step 2:** `grep LOOSE` na saída do build: nenhuma peça solta.
- [ ] **Step 3:** Captura com `--geardemo` segurando cada cetro; conferir pegada na mão.
- [ ] **Step 4: Commit** `feat: modelos dos cetros do healer`

---

### Task 8: Versão e verificação final

- [ ] **Step 1:** `project.godot` → `config/version="0.22.0"`.
- [ ] **Step 2:** Rodar a skill `smoke-check` (todos os testes do CI). Esperado: PASSOU em todos.
- [ ] **Step 3: Commit** `Classes e criação de personagem; versão 0.22.0`
