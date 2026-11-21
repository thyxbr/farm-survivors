extends RefCounted
## EarthquakeRules: contas puras do Terremoto Devastador (expansão da onda, quando ela chega em cada ponto, quem é
## atingido uma vez só e dentro do raio, rachaduras radiais com ramificações, placas e explosões secundárias, a grade
## polar do chão e a fase da pose). O kit (Terremoto no slot 2 com escudo) fica no teste de fumaça (precisa do ItemDB).


func _cfg() -> EarthquakeConfig:
	return load("res://assets/vfx/earthquake/earthquake_config.tres")


func test_wave_grows_then_stops_at_radius() -> void:
	var R := 9.0
	var v := 16.0
	var T_ := EarthquakeRules.expansion_time(R, v)
	T.ok(T_ > 0.3 and T_ < 2.0, "a onda leva pouco mais de meio segundo até a borda (%.2f s)" % T_)
	T.eq(EarthquakeRules.wave_radius(0.0, R, v), 0.0, "começa no centro")
	var prev := 0.0
	var grows := true
	for i in range(1, 21):
		var r := EarthquakeRules.wave_radius(T_ * i / 20.0, R, v)
		grows = grows and r > prev
		prev = r
	T.ok(grows, "cresce progressivamente em todo o trajeto")
	T.ok(is_equal_approx(EarthquakeRules.wave_radius(T_, R, v), R) and is_equal_approx(EarthquakeRules.wave_radius(T_ * 3.0, R, v), R),
		"para no raio máximo e não passa dele")
	var early := EarthquakeRules.wave_radius(0.02, R, v) / 0.02
	T.ok(absf(early - v) < 1.0, "sai na velocidade configurada (%.1f m/s)" % early)
	var late := (EarthquakeRules.wave_radius(T_, R, v) - EarthquakeRules.wave_radius(T_ - 0.05, R, v)) / 0.05
	T.ok(late < v * 0.5, "e freia perto da borda (%.1f m/s)" % late)


func test_time_to_reach_matches_wave() -> void:
	var R := 9.0
	var v := 16.0
	for d in [0.5, 3.0, 6.0, 8.9]:
		var t := EarthquakeRules.time_to_reach(d, R, v)
		T.ok(absf(EarthquakeRules.wave_radius(t, R, v) - d) < 0.01, "a onda chega a %.1f m no tempo previsto" % d)
	T.eq(EarthquakeRules.time_to_reach(9.5, R, v), INF, "fora do raio a onda nunca chega")


func test_targets_hit_once_when_wave_arrives() -> void:
	var c := Vector3(10, 0, 10)
	var R := 9.0
	var list := [
		{"id": 1, "pos": c + Vector3(2, 0, 0), "radius": 0.5},
		{"id": 2, "pos": c + Vector3(0, 1.5, -6), "radius": 0.5},   # mais alto: só a distância no chão conta
		{"id": 3, "pos": c + Vector3(9.3, 0, 0), "radius": 0.5},    # o corpo encosta na borda: vale
		{"id": 4, "pos": c + Vector3(-11, 0, 0), "radius": 0.5},    # fora do raio
	]
	var hit := {}
	var a := EarthquakeRules.pick_reached(list, c, 1.0, R, hit)
	T.eq(a.size(), 0, "a onda ainda não chegou em ninguém (raio 1 m)")
	a = EarthquakeRules.pick_reached(list, c, 2.0, R, hit)
	T.eq(a.map(func(x): return x.id), [1], "a 2 m a onda pega só o mais perto")
	a = EarthquakeRules.pick_reached(list, c, 6.0, R, hit)
	T.eq(a.map(func(x): return x.id), [2], "a 6 m pega o próximo, e o primeiro não leva de novo")
	a = EarthquakeRules.pick_reached(list, c, R, R, hit)
	T.eq(a.map(func(x): return x.id), [3], "na borda pega quem encosta nela")
	a = EarthquakeRules.pick_reached(list, c, 50.0, R, hit)
	T.eq(a.size(), 0, "fora do raio máximo ninguém é atingido, nem com a onda grande")
	T.eq(hit.size(), 3, "cada um atingido uma vez só")


func test_crack_paths_radial_with_branches() -> void:
	var c := _cfg()
	var reach := c.radius * c.crack_length
	var paths := EarthquakeRules.crack_paths(c.crack_count, reach, c.crack_branching, c.crack_width, 77)
	var mains := paths.filter(func(p): return p.main)
	T.eq(mains.size(), c.crack_count, "uma rachadura principal por configuração")
	T.ok(paths.size() > mains.size(), "rachaduras com ramificações (%d no total)" % paths.size())
	var quads := {}
	var lengths := []
	var straight := true
	for p in mains:
		var pts: PackedVector2Array = p.points
		var tip := pts[pts.size() - 1]
		lengths.append(tip.length())
		quads[int(floor((tip.angle() + PI) / (TAU / 4.0))) % 4] = true
		T.ok(tip.length() <= reach + 0.8, "rachadura não passa muito do comprimento (%.2f m)" % tip.length())
		T.ok(tip.length() > pts[0].length(), "sai do centro para fora")
		# zigue-zague: o ângulo dos pontos varia
		var a0 := pts[1].angle()
		for q in pts:
			if q.length() > 0.5 and absf(angle_difference(q.angle(), a0)) > 0.02:
				straight = false
		var ws: PackedFloat32Array = p.widths
		T.ok(ws[ws.size() - 1] < ws[0], "afina até a ponta")
	T.ok(not straight, "as rachaduras não são retas")
	T.eq(quads.size(), 4, "espalhadas em todas as direções")
	lengths.sort()
	T.ok(lengths[lengths.size() - 1] - lengths[0] > reach * 0.2, "umas maiores e outras menores (%.1f..%.1f m)" % [lengths[0], lengths[lengths.size() - 1]])
	var again := EarthquakeRules.crack_paths(c.crack_count, reach, c.crack_branching, c.crack_width, 77)
	T.ok(again.size() == paths.size() and (again[3].points as PackedVector2Array) == (paths[3].points as PackedVector2Array),
		"mesma semente, mesmo desenho (o dono e as réplicas veem o mesmo chão)")
	T.eq(EarthquakeRules.crack_paths(0, reach, 0.5, 0.3, 1).size(), 0, "sem rachaduras configuradas: nenhuma")
	var plain := EarthquakeRules.crack_paths(6, reach, 0.0, 0.3, 5)
	T.eq(plain.size(), 6, "sem ramificação: só as principais")


func test_plates_and_secondary_spots() -> void:
	var c := _cfg()
	var paths := EarthquakeRules.crack_paths(c.crack_count, c.radius * c.crack_length, c.crack_branching, c.crack_width, 9)
	var plates := EarthquakeRules.plate_spots(paths, c.plate_count, c.plate_size, 9)
	T.eq(plates.size(), c.plate_count, "uma placa por configuração")
	var ordered := true
	for i in range(1, plates.size()):
		ordered = ordered and float(plates[i].dist) >= float(plates[i - 1].dist)
	T.ok(ordered, "placas em ordem de distância (a onda as levanta em sequência)")
	var sizes := plates.map(func(p): return float(p.size))
	sizes.sort()
	T.ok(sizes[sizes.size() - 1] > sizes[0] * 1.3, "placas de tamanhos diferentes")
	var sec := EarthquakeRules.secondary_spots(paths, c.secondary_count)
	T.eq(sec.size(), c.secondary_count, "uma explosão secundária por configuração")
	for p: Vector2 in sec:
		T.ok(p.length() > c.radius * 0.4, "explosão secundária nas pontas das rachaduras (%.1f m)" % p.length())


func test_ground_grid_follows_slope_and_ignores_outliers() -> void:
	var R := 10.0
	var rings := EarthquakeRules.GRID_RINGS
	var slices := EarthquakeRules.GRID_SLICES
	var h := PackedFloat32Array()
	h.resize((rings + 1) * slices)
	for r in rings + 1:
		for s in slices:
			var p := EarthquakeRules.grid_point(r, s, R)
			h[r * slices + s] = p.x * 0.2   # rampa: sobe para +X
	h[5 * slices + 3] = 4.0          # um raio caiu num telhado
	h[7 * slices + 10] = NAN         # um raio sem chão
	var g := EarthquakeRules.clean_grid(h, 0.0)
	var at := EarthquakeRules.grid_height(g, Vector2(6.0, 0.0), R)
	T.ok(absf(at - 1.2) < 0.15, "segue a rampa (%.2f m a 6 m)" % at)
	T.ok(absf(EarthquakeRules.grid_height(g, Vector2(-4.0, 1.0), R) + 0.8) < 0.15, "e do outro lado desce")
	var roof := EarthquakeRules.grid_point(5, 3, R)
	T.ok(absf(EarthquakeRules.grid_height(g, roof, R) - roof.x * 0.2) < 0.5, "o ponto no telhado é ignorado")
	T.ok(not is_nan(g[7 * slices + 10]), "ponto sem chão vira a altura do vizinho")


func test_pose_phase_timeline() -> void:
	var c := _cfg()
	var w := c.windup_time
	var s := c.slam_time
	T.eq(EarthquakeRules.pose_phase(0.0, w, s, c.hold_time, c.recover_time), 0.0, "começa na fase 0")
	T.ok(is_equal_approx(EarthquakeRules.pose_phase(w, w, s, c.hold_time, c.recover_time), 1.0), "escudo no alto no fim da subida")
	T.ok(is_equal_approx(EarthquakeRules.pose_phase(c.impact_time(), w, s, c.hold_time, c.recover_time), 2.0), "contato no instante do impacto")
	var mid := EarthquakeRules.pose_phase(w + s * 0.5, w, s, c.hold_time, c.recover_time)
	T.ok(mid < 1.5, "a descida acelera: na metade do tempo ainda falta mais da metade (%.2f)" % mid)
	T.eq(EarthquakeRules.pose_phase(c.total_time() + 1.0, w, s, c.hold_time, c.recover_time), 4.0, "de volta no fim")
	T.ok(c.forward_offset > 0.2 and c.forward_offset < 1.5, "o escudo bate logo à frente dos pés (%.2f m)" % c.forward_offset)
