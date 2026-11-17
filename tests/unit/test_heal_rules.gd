extends RefCounted
## HealRules: quem a Cura do healer atinge (raio, zona, posição conhecida) e o intervalo mínimo por jogador.


func test_targets_within_radius_including_caster() -> void:
	var pos := {1: Vector3.ZERO, 2: Vector3(5, 0, 0), 3: Vector3(8, 0, 0), 4: Vector3(8.1, 0, 0)}
	var t := HealRules.targets(1, [1, 2, 3, 4], pos)
	T.ok(1 in t and 2 in t and 3 in t, "o próprio, a 5 m e a 8 m são curados")
	T.ok(not (4 in t), "a 8,1 m fica de fora")


func test_targets_skip_unknown_position_but_heal_caster() -> void:
	var t := HealRules.targets(1, [1, 2], {2: Vector3.ZERO})
	T.ok(1 in t, "o conjurador é curado mesmo sem posição")
	T.ok(not (2 in t), "alvo sem posição conhecida é pulado")
	t = HealRules.targets(1, [1, 2], {1: Vector3.ZERO})
	T.ok(not (2 in t), "alvo sem posição fora")


func test_targets_only_zone_peers() -> void:
	var pos := {1: Vector3.ZERO, 2: Vector3(1, 0, 0), 3: Vector3(1, 0, 0)}
	var t := HealRules.targets(1, [1, 2], pos)
	T.ok(not (3 in t), "quem não está na zona não é curado")


func test_interval() -> void:
	T.ok(HealRules.interval_ok(-INF, 100.0), "primeira cura vale")
	T.ok(not HealRules.interval_ok(100.0, 101.3), "a 1,3 s recusa")
	T.ok(HealRules.interval_ok(100.0, 101.4), "a 1,4 s vale")
	T.ok(HealRules.interval_ok(100.0, 101.6), "a 1,6 s (menor recarga legítima) vale")


func test_interval_per_ability() -> void:
	T.ok(is_equal_approx(HealRules.min_interval("heal"), 1.4), "Cura: 1,4 s")
	T.ok(is_equal_approx(HealRules.min_interval("scepter_ward"), 16.0 * 0.4 - 0.2), "Escudo de Luz: recarga x 0,4 - 0,2")
	T.ok(HealRules.min_interval("scepter_ult") == 14.5, "ultimate: piso de 14,5 s no servidor")
	T.ok(not HealRules.interval_ok(100.0, 105.0, "scepter_ward"), "Escudo a 5 s recusa")
	T.ok(HealRules.interval_ok(100.0, 106.2, "scepter_ward"), "Escudo a 6,2 s vale")
	T.ok(not HealRules.interval_ok(100.0, 114.0, "scepter_ult"), "ultimate: recusa a 14 s")
	T.ok(HealRules.interval_ok(100.0, 114.5, "scepter_ult"), "ultimate: vale a 14,5 s")
	T.ok(HealRules.interval_ok(100.0, 116.0, "scepter_ult"), "ultimate: vale a 16 s (recarga minima do cliente)")
	T.ok(HealRules.ALLY_BUFFS.get("scepter_ult") == "scepter_feast" and not HealRules.ALLY_BUFFS.has("heal"), "mapa habilidade -> buff")


func test_targets_radius_bonus() -> void:
	var pos := {1: Vector3.ZERO, 2: Vector3(9, 0, 0)}
	T.ok(not (2 in HealRules.targets(1, [1, 2], pos)), "a 9 m fora do raio base")
	T.ok(2 in HealRules.targets(1, [1, 2], pos, 2.0), "a 9 m dentro com bônus de 2 m")


func test_level_ok() -> void:
	T.ok(not HealRules.level_ok(4, 5), "nível 4 não usa o Escudo de Luz (nível 5)")
	T.ok(HealRules.level_ok(3, 3) and HealRules.level_ok(8, 8), "nível exato vale")
	T.ok(not HealRules.level_ok(7, 8), "nível 7 não usa o Banquete (nível 8)")


func test_targets_talent_radius_bonus() -> void:
	var pos := {1: Vector3.ZERO, 2: Vector3(9.0, 0, 0)}
	T.ok(not (2 in HealRules.targets(1, [1, 2], pos)), "9 m fora do raio base")
	T.ok(2 in HealRules.targets(1, [1, 2], pos, 2.0), "9 m dentro com +2 m")


func test_heal_target_aimed_ally() -> void:
	var pos := {1: Vector3.ZERO, 2: Vector3(20, 0, 0), 3: Vector3(29, 0, 0), 4: Vector3(1, 0, 0)}
	T.eq(HealRules.heal_target(1, 2, [1, 2, 3, 4], pos), 2, "aliado mirado a 20 m recebe")
	T.eq(HealRules.heal_target(1, 0, [1, 2], pos), 1, "sem alvo: o próprio healer")
	T.eq(HealRules.heal_target(1, 1, [1, 2], pos), 1, "alvo = ele mesmo")
	T.eq(HealRules.heal_target(1, 3, [1, 2, 3], pos), 1, "a 29 m (fora do alcance): o próprio healer")
	T.eq(HealRules.heal_target(1, 3, [1, 2, 3], pos, 2.0), 3, "a 29 m com +2 m de talento: recebe")
	T.eq(HealRules.heal_target(1, 4, [1, 2], pos), 1, "alvo de outra zona: o próprio healer")
	T.eq(HealRules.heal_target(1, 2, [1, 2], {1: Vector3.ZERO}), 1, "alvo sem posição: o próprio healer")


func test_ally_buff_seconds() -> void:
	T.eq(HealRules.ally_buff_seconds(12.0, 4.0), 16.0, "tempo base + bonus")
	T.eq(HealRules.ally_buff_seconds(12.0, -5.0), 12.0, "bonus negativo ignorado")
