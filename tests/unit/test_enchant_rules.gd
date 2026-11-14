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
