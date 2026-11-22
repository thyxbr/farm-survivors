extends RefCounted
## DragSlashRules: contas puras do Corte do Abismo (corrida, parada no inimigo, arco do corte, garras, trajetória da
## lâmina sem entrar no chão) e a coerência da configuração.


func _cfg() -> DragSlashConfig:
	return load("res://assets/vfx/longsword_drag/drag_slash_config.tres")


func test_dash_speed_ramps_and_brakes() -> void:
	var top := 14.0
	var start := DragSlashRules.dash_speed(0.0, 7.0, top)
	var full := DragSlashRules.dash_speed(0.3, 7.0, top)
	var near := DragSlashRules.dash_speed(0.3, 0.1, top)
	T.ok(start > 0.0 and start < full, "arranca devagar e acelera (%.1f -> %.1f)" % [start, full])
	T.ok(is_equal_approx(full, top), "no meio da corrida, a velocidade toda")
	T.ok(near < full * 0.6 and near > 0.0, "freia perto do fim sem parar de uma vez (%.1f)" % near)


func test_nearest_enemy_in_the_lane() -> void:
	var o := Vector3.ZERO
	var f := Vector3(0, 0, 1)
	var mobs := [{"pos": Vector3(0.3, 0, 3.0), "radius": 0.5}, {"pos": Vector3(4.0, 0, 1.0), "radius": 0.5},
		{"pos": Vector3(0, 0, -2.0), "radius": 0.5}]
	T.eq(DragSlashRules.nearest_ahead(o, f, mobs, 6.0, 1.0), 2.5, "o da frente, descontado o corpo")
	T.eq(DragSlashRules.nearest_ahead(o, f, [mobs[1], mobs[2]], 6.0, 1.0), INF, "dos lados e atrás não contam")
	T.eq(DragSlashRules.nearest_ahead(o, f, [{"pos": Vector3(0, 0, 9.0), "radius": 0.5}], 6.0, 1.0), INF, "longe demais")
	T.ok(DragSlashRules.dash_should_stop(1.0, 7.0, 1.2, 1.6, false), "para perto do inimigo")
	T.ok(DragSlashRules.dash_should_stop(7.0, 7.0, INF, 1.6, false), "para ao completar a distância")
	T.ok(DragSlashRules.dash_should_stop(2.0, 7.0, INF, 1.6, true), "para na parede")
	T.ok(not DragSlashRules.dash_should_stop(2.0, 7.0, 4.0, 1.6, false), "senão continua")


func test_slash_arc_in_front() -> void:
	var o := Vector3.ZERO
	var f := Vector3(0, 0, 1)
	T.ok(DragSlashRules.in_slash(o, f, Vector3(0, 0, 2.0), 2.8, 70.0), "à frente")
	T.ok(DragSlashRules.in_slash(o, f, Vector3(1.8, 1.0, 1.0), 2.8, 70.0), "na diagonal (a altura não conta)")
	T.ok(not DragSlashRules.in_slash(o, f, Vector3(0, 0, -2.0), 2.8, 70.0), "atrás não")
	T.ok(not DragSlashRules.in_slash(o, f, Vector3(0, 0, 3.5), 2.8, 70.0), "fora do alcance")
	T.ok(DragSlashRules.in_slash(o, f, Vector3(0, 0, 3.5), 2.8, 70.0, 0.8), "o corpo encosta na borda")
	T.ok(DragSlashRules.in_slash(o, f, Vector3(-0.2, 0, -0.5), 2.8, 70.0, 0.5), "colado no herói sempre conta")


func test_claws_in_a_row_ahead() -> void:
	var c := DragSlashRules.claw_centers(Vector3(1, 0, 1), Vector3(0, 0, 2), 3, 2.0, 1.5, 0.4)
	T.eq(c.size(), 3, "três garras")
	T.ok(c[0].is_equal_approx(Vector3(1, 0, 3)), "a primeira no eixo, a 2 m (%s)" % c[0])
	T.ok(is_equal_approx(c[1].z, 4.5) and is_equal_approx(c[2].z, 6.0), "as outras a cada 1,5 m")
	T.ok((c[1].x - 1.0) * (c[2].x - 1.0) < 0.0, "alternando para os lados")
	T.ok(DragSlashRules.in_claw(c[0], c[0] + Vector3(1.0, 3.0, 0), 1.35), "em cima da garra")
	T.ok(not DragSlashRules.in_claw(c[0], c[0] + Vector3(2.0, 0, 0), 1.35), "longe da garra")


func test_each_enemy_hit_once() -> void:
	var hit := {}
	var mobs := [{"id": 1, "pos": Vector3(0, 0, 1)}, {"id": 2, "pos": Vector3(0, 0, 9)}]
	var near := func(e: Dictionary) -> bool: return (e.pos as Vector3).length() < 3.0
	T.eq(DragSlashRules.pick(mobs, near, hit).size(), 1, "só o perto")
	T.eq(DragSlashRules.pick(mobs, near, hit).size(), 0, "a segunda vez não fere de novo")


func test_blade_never_enters_the_ground() -> void:
	var length := 1.3
	for hand_y in [0.6, 0.9, 1.2, 2.0]:
		var el := DragSlashRules.min_elevation(hand_y, 0.03, length)
		var tip_y: float = hand_y + DragSlashRules.blade_dir(-2.0, el).y * length
		T.ok(tip_y >= 0.03 - 0.001, "mão a %.1f m: a ponta fica no chão ou acima (%.3f)" % [hand_y, tip_y])
	T.ok(is_equal_approx(DragSlashRules.min_elevation(2.0, 0.0, 1.3), 0.0), "mão bem alta: pode apontar para baixo")
	var d := DragSlashRules.blade_dir(0.0, PI * 0.5)
	T.ok(d.is_equal_approx(Vector3(0, 0, 1)), "azimute 0 na horizontal = para a frente")
	T.ok(DragSlashRules.blade_dir(-PI * 0.5, PI * 0.5).is_equal_approx(Vector3(-1, 0, 0)), "-90° = para a direita (-X)")
	T.ok(DragSlashRules.blade_dir(0.0, PI).is_equal_approx(Vector3(0, 1, 0)), "elevação PI = para cima")


func test_spline_passes_the_keys() -> void:
	var keys := [[0.0, 1.0], [1.0, 3.0], [2.0, 2.0]]
	T.ok(is_equal_approx(DragSlashRules.spline(keys, 1.0), 3.0), "passa na chave")
	T.ok(is_equal_approx(DragSlashRules.spline(keys, -1.0), 1.0) and is_equal_approx(DragSlashRules.spline(keys, 5.0), 2.0), "segura nas pontas")
	var v: Vector3 = DragSlashRules.spline([[0.0, Vector3.ZERO], [1.0, Vector3.ONE]], 0.5)
	T.ok(v.is_equal_approx(Vector3(0.5, 0.5, 0.5)), "Vector3 também")


func test_config_is_coherent() -> void:
	var c := _cfg()
	T.ok(c.hit_time() > c.plant_time and c.hit_time() < c.plant_time + c.rise_time, "o acerto é no meio da subida")
	T.ok(c.slash_total() > c.hit_time(), "o corte termina depois do acerto")
	T.ok(c.stop_distance < c.claw_first + c.claw_radius, "o inimigo que parou a corrida fica no arco ou na primeira garra")
	T.ok(c.stop_distance + 0.5 < c.slash_radius, "e o corte alcança quem parou a corrida")
	T.ok(c.dash_speed > 8.6, "a corrida é mais rápida que correr")
