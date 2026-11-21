extends RefCounted
## ThornRules: as habilidades da Espinheira (escolha do golpe, Raízes em linha, Brotos que curam e Esporos).


func test_plain_attacks_by_distance() -> void:
	T.eq(ThornRules.attack(0, false, 3.0, 4.5, 0), "swing", "perto: garra")
	T.eq(ThornRules.attack(1, false, 12.0, 4.5, 0), "roots", "longe: raízes")


func test_special_every_fourth() -> void:
	T.eq(ThornRules.attack(3, false, 3.0, 4.5, 0), "sprouts", "4º golpe: brotos")
	T.eq(ThornRules.attack(7, false, 12.0, 4.5, 0), "sprouts", "fora da fúria é sempre broto")
	T.eq(ThornRules.attack(3, true, 3.0, 4.5, 0), "sprouts", "fúria, ciclo par: brotos")
	T.eq(ThornRules.attack(7, true, 3.0, 4.5, 0), "spores", "fúria, ciclo ímpar: esporos")


func test_no_more_sprouts_while_many_alive() -> void:
	T.eq(ThornRules.attack(3, false, 3.0, 4.5, 2), "roots", "brotos vivos demais: raízes em vez de invocar")
	T.eq(ThornRules.attack(3, true, 3.0, 4.5, 3), "spores", "na fúria vira esporos")


func test_root_line_hits_along_and_misses_beside() -> void:
	var o := Vector3(5, 0, 5)
	var d := Vector3(1, 0, 0)
	T.eq(ThornRules.root_segment(o, d, ThornRules.root_point(o, d, 0)), 0, "no primeiro trecho")
	T.eq(ThornRules.root_segment(o, d, ThornRules.root_point(o, d, ThornRules.ROOT_SEGS - 1)),
		ThornRules.ROOT_SEGS - 1, "no último trecho")
	T.eq(ThornRules.root_segment(o, d, o + Vector3(8, 0, ThornRules.ROOT_HALF + 0.3)), -1, "de lado: escapa")
	T.eq(ThornRules.root_segment(o, d, o + Vector3(-3, 0, 0)), -1, "atrás dela: escapa")
	T.eq(ThornRules.root_segment(o, d, o + Vector3(ThornRules.ROOT_LEN + 3.0, 0, 0)), -1, "além da ponta: escapa")


func test_root_segments_erupt_in_order() -> void:
	for i in ThornRules.ROOT_SEGS - 1:
		T.ok(ThornRules.root_time(i + 1) > ThornRules.root_time(i), "trecho %d depois do %d" % [i + 1, i])
	T.ok(ThornRules.root_time(0) >= 1.0, "o aviso dá tempo de sair da linha")


func test_fan_only_when_enraged() -> void:
	T.eq(ThornRules.root_dirs(Vector3(0, 0, 3), false).size(), 1, "uma linha")
	var fan := ThornRules.root_dirs(Vector3(0, 0, 3), true)
	T.eq(fan.size(), 3, "três na fúria")
	for v in fan:
		T.ok(absf((v as Vector3).length() - (1.0)) <= 0.001, "direções normalizadas")


func test_sprout_points_around_her() -> void:
	var c := Vector3(-800, 0, 762)
	var pts := ThornRules.sprout_points(c, Vector3(0, 0, 1))
	T.eq(pts.size(), ThornRules.SPROUTS, "três brotos")
	for p in pts:
		T.ok(absf((p as Vector3).distance_to(c) - (ThornRules.SPROUT_RING)) <= 0.01, "na roda")
	T.ok((pts[0] as Vector3).z < c.z, "o primeiro nasce atrás dela")


func test_sprout_heal_scales_with_alive() -> void:
	T.ok(absf(ThornRules.sprout_heal(1000.0, 0, 1.0) - (0.0)) <= 0.0001, "sem brotos, sem cura")
	T.ok(absf(ThornRules.sprout_heal(1000.0, 3, 2.0) - (1000.0 * ThornRules.SPROUT_HEAL * 6.0)) <= 0.0001, "3 brotos por 2 s")


func test_spore_points_deterministic_and_inside() -> void:
	var c := Vector3(3, 1, 4)
	var a := ThornRules.spore_points(42, c)
	var b := ThornRules.spore_points(42, c)
	T.eq(a, b, "mesma semente, mesmos pontos (servidor e cliente)")
	for p in a:
		var d := Vector2((p as Vector3).x - c.x, (p as Vector3).z - c.z).length()
		T.ok(d <= ThornRules.SPORE_SPREAD + 0.001 and d >= ThornRules.SPORE_SPREAD * 0.35 - 0.001, "dentro do espalhamento")
		T.ok(absf((p as Vector3).y - (c.y)) <= 0.0001, "na altura dela")


func test_spores_grow() -> void:
	T.ok(absf(ThornRules.spore_radius(0.0) - (ThornRules.SPORE_R0)) <= 0.0001, "nasce pequena")
	T.ok(absf(ThornRules.spore_radius(ThornRules.SPORE_LIFE) - (ThornRules.SPORE_R1)) <= 0.0001, "acaba grande")
	T.ok(ThornRules.spore_radius(5.0) > ThornRules.SPORE_R0, "cresce com o tempo")
