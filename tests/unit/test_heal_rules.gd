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
	T.ok(not HealRules.interval_ok(100.0, 101.9), "a 1,9 s recusa")
	T.ok(HealRules.interval_ok(100.0, 102.0), "a 2,0 s vale")
