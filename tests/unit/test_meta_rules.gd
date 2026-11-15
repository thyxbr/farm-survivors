extends RefCounted
## Ecos, passivas permanentes e base compartilhada: regras puras com as tabelas reais.

var _bt: BalanceTables


func _tables() -> BalanceTables:
	if _bt == null:
		_bt = BalanceTables.load_dir("res://data/balance")
	return _bt


func _blank(ecos := 0) -> CharState:
	var s := CharState.new_character(_tables())
	s.ecos = ecos
	return s


func test_ecos_curve() -> void:
	var bt := _tables()
	T.eq(RewardRules.ecos(bt, "horde", 10), 50, "horde 10 rodadas")
	T.eq(RewardRules.ecos(bt, "city", 5), 45, "city 5 noites")
	T.eq(RewardRules.ecos(bt, "city", 0), 0, "nada alcançado")
	T.eq(RewardRules.ecos(bt, "xyz", 9), 0, "modo desconhecido")


func test_buy_passive_levels_and_cost() -> void:
	var bt := _tables()
	var s := _blank(100)
	var r := CharRules.buy_passive(s, bt, "poder")
	T.ok(r.ok, "compra nível 1")
	T.eq(s.ecos, 75, "custou 25")
	T.eq(s.passives["poder"], 1, "nível 1")
	T.ok(CharRules.buy_passive(s, bt, "poder").ok, "compra nível 2")
	T.eq(s.ecos, 30, "custou 45")
	T.eq(s.passives["poder"], 2, "nível 2")
	var before := s.to_dict()
	r = CharRules.buy_passive(s, bt, "poder")
	T.ok(not r.ok and r.err == "sem_ecos", "sem Ecos para o nível 3")
	T.eq(s.to_dict(), before, "estado intacto")


func test_buy_passive_max_and_invalid() -> void:
	var bt := _tables()
	var s := _blank(1000)
	s.passives["poder"] = 5
	var r := CharRules.buy_passive(s, bt, "poder")
	T.ok(not r.ok and r.err == "nivel_maximo", "nível máximo")
	r = CharRules.buy_passive(s, bt, "nada")
	T.ok(not r.ok and r.err == "passiva_invalida", "id inválido")
	T.eq(s.ecos, 1000, "nada cobrado")


func test_meta_mods_sum() -> void:
	var m := CharRules.meta_mods(_tables(), {"poder": 2, "armadura": 3})
	T.ok(absf(m.damage - 0.06) < 0.0001, "dano 2 níveis")
	T.eq(m.defense, 3, "defesa 3 níveis")


func test_state_roundtrip_ecos_passives() -> void:
	var bt := _tables()
	var s := _blank(77)
	s.passives = {"poder": 3, "vigor": 1}
	var s2 := CharState.from_dict(s.to_dict(), bt)
	T.eq(s2.ecos, 77, "ecos")
	T.eq(s2.passives, {"poder": 3, "vigor": 1}, "passivas")
	var d := s.to_dict()
	d.passives = {"poder": 9, "fantasma": 2, "vigor": 0}
	d.ecos = -4
	var s3 := CharState.from_dict(d, bt)
	T.eq(s3.passives, {"poder": 5}, "saneadas")
	T.eq(s3.ecos, 0, "ecos >= 0")
