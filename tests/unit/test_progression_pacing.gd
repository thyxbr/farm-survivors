extends RefCounted
## Ritmo da progressão com as tabelas reais (data/balance): golpes no monstro comum do mesmo nível,
## horas por faixa de nível, itens por morte e a fórmula do ataque básico.
## Se algum destes falhar depois de mexer em números, rode o simulador para ver onde:
##   godot --headless --path . -s tools/progression_sim.gd

const HOURS_TARGET := {"1-10": 2.0, "10-20": 5.0, "20-35": 10.0, "35-45": 7.0, "45-50": 6.0}

var _bt: BalanceTables


func _tables() -> BalanceTables:
	if _bt == null:
		_bt = BalanceTables.load_dir("res://data/balance")
	return _bt


func test_hits_same_level() -> void:
	var bt := _tables()
	for level in [5, 10, 20, 30, 40, 50]:
		for cls in ["warrior", "archer", "mage"]:
			var h := ProgressionRules.sim_hits(bt, cls, level)
			T.ok(h >= 3 and h <= 5, "%s nível %d: %d golpes (meta 3-5)" % [cls, level, h])
		var hh := ProgressionRules.sim_hits(bt, "healer", level)
		T.ok(hh >= 1 and hh <= 7, "healer nível %d: %d golpes (meta até 7)" % [level, hh])


func test_hours_per_band() -> void:
	var hours := ProgressionRules.sim_hours(_tables())
	for band in HOURS_TARGET:
		T.ok(hours.has(band), "faixa %s no resultado" % band)
		var h := float(hours.get(band, 0.0))
		var t: float = HOURS_TARGET[band]
		T.ok(h >= t * 0.8 and h <= t * 1.2, "faixa %s: %.2f h (alvo %.0f h ±20%%)" % [band, h, t])


func test_basic_damage_matches_old_formula() -> void:
	var a := {"str": 20, "agi": 5, "int": 5, "vit": 5}
	T.ok(is_equal_approx(CharRules.basic_damage("sword", a, 12, 0), 12 + 20 * 1.6), "espada: arma + FOR x 1,6")
	var b := {"str": 5, "agi": 20, "int": 5, "vit": 5}
	T.ok(is_equal_approx(CharRules.basic_damage("bow", b, 15, 0), 15 + 30 + 1.5), "arco: arma + AGI x 1,5 + FOR x 0,3")
	var c := {"str": 5, "agi": 5, "int": 20, "vit": 5}
	T.ok(is_equal_approx(CharRules.basic_damage("staff", c, 10, 4), 10 + 28 + 2), "cajado: arma + INT x 1,4 + magia x 0,5")
	T.ok(is_equal_approx(CharRules.basic_damage("scepter", c, 10, 4), 10 + 28 + 2), "cetro usa a conta do cajado")


## Meta do design: ~0,5 a 0,8 item por monstro comum (sorteio no ref_level, com o equipamento por nível).
func test_items_per_kill() -> void:
	var bt := _tables()
	for kind in ["slime", "goblin", "esqueleto", "raptor_capim"]:
		var avg := ProgressionRules.sim_items_per_kill(bt, kind, 4000, 1234)
		T.ok(avg >= 0.5 and avg <= 0.8, "%s: %.2f itens por morte (meta 0,5-0,8)" % [kind, avg])
