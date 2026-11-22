extends RefCounted
## Ritmo da progressão com as tabelas reais (data/balance): golpes no monstro comum do mesmo nível,
## horas por faixa de nível, itens por morte e a fórmula do ataque básico.
## Se algum destes falhar depois de mexer em números, rode o simulador para ver onde:
##   godot --headless --path . -s tools/progression_sim.gd

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
			T.ok(h >= 5 and h <= 8, "%s nível %d: %d golpes (meta 5-8)" % [cls, level, h])
		var hh := ProgressionRules.sim_hits(bt, "healer", level)
		T.ok(hh >= 1 and hh <= 10, "healer nível %d: %d golpes (meta até 10)" % [level, hh])


func test_hours_per_band() -> void:
	var bt := _tables()
	var hours := ProgressionRules.sim_hours(bt)
	var targets: Dictionary = bt.get_table("progression").sim.target_hours
	T.eq(targets.size(), 5, "sim.target_hours tem as 5 faixas do design")
	# o alvo é o do design: mexer nele não pode fazer o teste passar
	# (35 h até o 50 desde o ajuste de dificuldade: comum com vida × 2 e XP igual, cada abate demora mais)
	var design := {"1-10": 2.5, "10-20": 5.5, "20-35": 11.5, "35-45": 8.0, "45-50": 7.0}
	for band in design:
		T.ok(targets.has(band) and is_equal_approx(float(targets[band]), design[band]),
			"alvo da faixa %s = %.1f h (design)" % [band, design[band]])
	for band in targets:
		T.ok(hours.has(band), "faixa %s no resultado" % band)
		var h := float(hours.get(band, 0.0))
		var t := float(targets[band])
		T.ok(h >= t * 0.8 and h <= t * 1.2, "faixa %s: %.2f h (alvo %.1f h ±20%%)" % [band, h, t])


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


## Chefe: 1 material raro garantido + chance pequena de item nomeado. Equipamento por abate ~1-2
## (o sorteio da janela de nível com gear_drop.boss_chance + os itens da lista), e o item nomeado da
## lista usável perto do nível do chefe (até +2).
func test_boss_drops() -> void:
	var bt := _tables()
	var enemies: Dictionary = bt.get_table("enemies")
	var boss_chance := float(bt.get_table("progression").gear_drop.get("boss_chance", 0.0))
	# Rei Goblin nasce no ref_level; o Lich no nível do ponto dele (scenes/maps/pico.tscn)
	var spawn := {"goblin_king": ProgressionRules.enemy_level(bt, "goblin_king", 0), "lich": 42}
	for kind in spawn:
		T.ok(enemies[kind].get("boss", false), "%s é chefe" % kind)
		var gear := 0.0
		for row in enemies[kind].loot:
			if CharRules.slot_of(bt, str(row[0])) == "":
				continue
			gear += float(row[1])
			var lvl := CharRules.item_level(bt, str(row[0]))
			T.ok(lvl <= spawn[kind] + 2, "%s: %s nível %d (chefe nível %d, até +2)" % [kind, row[0], lvl, spawn[kind]])
		T.ok(gear >= 0.2 and gear <= 0.35, "%s: %.2f item nomeado por abate (chance pequena)" % [kind, gear])
		var total := gear + boss_chance
		T.ok(total >= 1.0 and total <= 2.0, "%s: %.2f equipamentos por abate (meta 1-2)" % [kind, total])
