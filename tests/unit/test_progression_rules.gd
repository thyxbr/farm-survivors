extends RefCounted
## ProgressionRules: curvas puras de XP, atributos de monstro e camadas, com as tabelas reais de data/balance.
## Os parâmetros das curvas vêm da tabela carregada (a calibração não quebra os testes).

var _bt: BalanceTables


func _tables() -> BalanceTables:
	if _bt == null:
		_bt = BalanceTables.load_dir("res://data/balance")
	return _bt


func _curve_xp(bt: BalanceTables, level: int) -> int:
	var c: Dictionary = bt.get_table("progression").xp_curve
	return int(float(c.base) * pow(float(level), float(c.exp)))


func test_xp_to_next_matches_curve() -> void:
	var bt := _tables()
	T.eq(ProgressionRules.xp_to_next(bt, 10), _curve_xp(bt, 10), "nível 10 segue a curva")
	var late: Dictionary = bt.get_table("progression").xp_curve.late
	T.ok(late.has("46"), "tabela tem multiplicador tardio no 46")
	T.ok(ProgressionRules.xp_to_next(bt, 46) > int(float(late["46"]) * 0.95 * _curve_xp(bt, 46)), "nível 46 leva o multiplicador tardio")
	T.eq(ProgressionRules.xp_to_next(bt, ProgressionRules.max_level(bt)), 0, "no nível máximo não há próximo")


func test_enemy_mults_identity_without_level() -> void:
	var bt := _tables()
	var one := {"hp": 1.0, "dmg": 1.0, "xp": 1.0, "gold": 1.0}
	T.eq(ProgressionRules.enemy_mults(bt, "goblin", 0), one, "sem nível = números de hoje")
	T.eq(ProgressionRules.enemy_mults(bt, "nao_existe", 0), one, "tipo desconhecido sem nível")


func test_enemy_mults_at_ref_level_is_one() -> void:
	var bt := _tables()
	var ref := ProgressionRules.enemy_level(bt, "goblin", 0)
	T.eq(ref, int(bt.get_table("enemies")["goblin"]["ref_level"]), "nível padrão = ref_level")
	T.ok(absf(float(ProgressionRules.enemy_mults(bt, "goblin", ref).hp) - 1.0) < 0.0001, "hp no ref_level = 1")
	T.eq(ProgressionRules.enemy_level(bt, "goblin", 17), 17, "nível dado vence o ref_level")
	T.eq(ProgressionRules.enemy_level(bt, "nao_existe", 0), 1, "tipo desconhecido = nível 1")


func test_enemy_mults_grow_with_level() -> void:
	var bt := _tables()
	var m20: Dictionary = ProgressionRules.enemy_mults(bt, "goblin", 20)
	var m10: Dictionary = ProgressionRules.enemy_mults(bt, "goblin", 10)
	T.ok(float(m20.hp) > float(m10.hp) and float(m10.hp) > 1.0, "hp cresce com o nível")
	for k in ["dmg", "xp", "gold"]:
		T.ok(float(m20[k]) > float(m10[k]), "%s cresce com o nível" % k)


func test_xp_diff_table() -> void:
	var bt := _tables()
	T.eq(ProgressionRules.xp_diff_mult(bt, 2, 12), 0.05, "-10")
	T.eq(ProgressionRules.xp_diff_mult(bt, 5, 11), 0.25, "-6")
	T.eq(ProgressionRules.xp_diff_mult(bt, 10, 13), 0.7, "-3")
	T.eq(ProgressionRules.xp_diff_mult(bt, 10, 10), 1.0, "0")
	T.eq(ProgressionRules.xp_diff_mult(bt, 14, 10), 1.15, "+4")
	T.eq(ProgressionRules.xp_diff_mult(bt, 20, 10), 1.25, "+10")


func test_tier_of() -> void:
	var bt := _tables()
	T.eq(ProgressionRules.tier_of(bt, 1), 1, "nível 1")
	T.eq(ProgressionRules.tier_of(bt, 10), 1, "nível 10")
	T.eq(ProgressionRules.tier_of(bt, 11), 2, "nível 11")
	T.eq(ProgressionRules.tier_of(bt, 50), 5, "nível 50")
