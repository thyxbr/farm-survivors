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


func test_elite_adds_levels() -> void:
	var bt := _tables()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var bonus := int(bt.get_table("progression").elite.level_bonus)
	for i in 20:
		var l := ProgressionRules.spawn_level(bt, 5, 8, true, rng)
		T.ok(l >= 5 + bonus and l <= 8 + bonus, "elite 5..8 sobe %d níveis (%d)" % [bonus, l])
	T.eq(ProgressionRules.spawn_level(bt, 5, 0, false, rng), 5, "level_max 0 = nível fixo")
	T.eq(ProgressionRules.spawn_level(bt, 0, 0, false, rng), 0, "sem nível continua sem nível")
	T.eq(ProgressionRules.spawn_level(bt, 0, 0, true, rng), 0, "elite sem nível não ganha nível")


## Vida e dano de um tipo no nível `level` como o Enemy calcula (curva de nível × categoria).
func _at(bt: BalanceTables, kind: String, level: int, chief := false) -> Dictionary:
	var t: Dictionary = bt.get_table("enemies")[kind]
	var m := ProgressionRules.enemy_mults(bt, kind, level)
	var r := ProgressionRules.rank_mults(bt, kind, chief)
	return {"hp": float(t.hp) * float(m.hp) * float(r.hp), "dmg": float(t.damage) * float(m.dmg) * float(r.dmg)}


## No mesmo nível: todo campeão (elite) tem mais vida e bate mais que qualquer comum, e todo chefe mais que
## qualquer campeão. Ficam de fora o Goblin Dourado (foge, dano 0) e os que explodem (dano de um golpe só).
func test_rank_order_at_same_level() -> void:
	var bt := _tables()
	var en: Dictionary = bt.get_table("enemies")
	var groups := {"normal": [], "elite": [], "boss": []}
	for k in en:
		if int(en[k].damage) <= 0 or en[k].get("ai", "") == "bomber" or en[k].has("blast"):
			continue
		groups["boss" if en[k].get("boss", false) else ("elite" if en[k].get("elite", false) else "normal")].append(k)
	T.ok(groups.elite.size() > 0 and groups.boss.size() > 0, "há campeões e chefes")
	for level in [8, 21, 40]:
		for pair in [["normal", "elite"], ["elite", "boss"]]:
			for weak in groups[pair[0]]:
				for strong in groups[pair[1]]:
					var a := _at(bt, weak, level)
					# chefe com "rank" próprio (Rei Goblin da missão) é comparado no posto de chefe de dungeon
					var b := _at(bt, strong, level, en[strong].has("rank"))
					T.ok(b.hp > a.hp, "Nv %d: vida de %s > %s" % [level, strong, weak])
					T.ok(b.dmg > a.dmg, "Nv %d: dano de %s > %s" % [level, strong, weak])
	var common: Dictionary = bt.get_table("progression").rank.common
	T.eq(ProgressionRules.rank_mults(bt, "goblin", false), {"hp": float(common.hp), "dmg": float(common.dmg)},
		"comum usa o bloco rank.common")


## O Rei Goblin da missão (no mundo, no ref_level) é o primeiro chefe: mais forte que um comum, mas abaixo
## do bloco dos chefes, que ele só usa como chefe de dungeon.
func test_story_king_is_softer() -> void:
	var bt := _tables()
	var own := ProgressionRules.rank_mults(bt, "goblin_king")
	var full := ProgressionRules.rank_mults(bt, "goblin_king", true)
	T.ok(own.hp > 1.0 and own.hp < full.hp, "vida: entre o comum e o chefe de dungeon")
	T.ok(own.dmg > 1.0 and own.dmg < full.dmg, "dano: entre o comum e o chefe de dungeon")


func test_chief_uses_boss_rank() -> void:
	var bt := _tables()
	var chief := _at(bt, "slime_rainha", 21, true)
	var queen := _at(bt, "slime_rainha", 21)
	T.ok(chief.hp > queen.hp and chief.dmg > queen.dmg, "chefe de dungeon mais forte que a mesma elite no mundo")
	T.eq(ProgressionRules.rank_mults(bt, "slime_rainha", true), ProgressionRules.rank_mults(bt, "goblin_king", true),
		"chefe de dungeon usa o bloco do chefe")


func test_danger_bonus() -> void:
	var bt := _tables()
	var diff := ProgressionRules.danger_diff(bt)
	var none := {"dmg": 1.0, "taken": 1.0}
	T.eq(ProgressionRules.danger_mults(bt, 10 + diff - 1, 10), none, "abaixo do vermelho: sem bônus")
	var red: Dictionary = ProgressionRules.danger_mults(bt, 10 + diff, 10)
	T.ok(float(red.dmg) > 1.0 and float(red.taken) < 1.0, "no vermelho: bate mais e leva menos")
	var far: Dictionary = ProgressionRules.danger_mults(bt, 10 + diff + 5, 10)
	T.ok(float(far.dmg) > float(red.dmg) and float(far.taken) < float(red.taken), "cresce com a diferença")
	var huge: Dictionary = ProgressionRules.danger_mults(bt, 50, 1)
	var d: Dictionary = bt.get_table("progression").danger
	T.ok(absf(float(huge.dmg) - float(d.dmg_max)) < 0.0001 and absf(float(huge.taken) - float(d.taken_min)) < 0.0001, "tem teto")
	T.eq(ProgressionRules.danger_mults(bt, 0, 1), none, "monstro sem nível (Horda) sem bônus")
	T.eq(ProgressionRules.danger_mults(bt, 30, 0), none, "jogador desconhecido sem bônus")


func test_quests_have_level_and_xp() -> void:
	var bt := _tables()
	var qt: Dictionary = bt.get_table("quests")
	var maxl := ProgressionRules.max_level(bt)
	var early := 0
	for id in qt:
		var l := int(qt[id].get("level", 0))
		T.ok(l >= 1 and l <= maxl, "%s: nível %d dentro de 1..máx" % [id, l])
		T.ok(int(qt[id].get("reward_xp", 0)) > 0, "%s: reward_xp > 0" % id)
		if l <= 10 and not qt[id].has("event"):   # sazonal (Natal) fica fora do ritmo
			early += int(qt[id].reward_xp)
	var band := 0
	for l in range(1, 10):
		band += ProgressionRules.xp_to_next(bt, l)
	T.ok(early >= band * 0.20 and early <= band * 0.45,
		"missões até o nível 10 dão 20%%-45%% do XP dos níveis 1-9 (%d de %d)" % [early, band])
