extends RefCounted
## HammerRules: contas puras do Martelo de Energia (queda com aceleração, crateras em volta do impacto, quem está
## no raio e o golpe único por inimigo). O kit (Martelo no slot 2 com escudo) fica no teste de fumaça (precisa do ItemDB).


func _cfg() -> HammerConfig:
	return load("res://assets/vfx/hammer/hammer_config.tres")


func test_fall_time_matches_distance() -> void:
	var t := HammerRules.fall_time(2.0, 1.5, 42.0)
	T.ok(t > 0.0 and t < 0.5, "queda de 2 m é rápida (%.3f s)" % t)
	T.ok(absf(HammerRules.fall_distance(t, 1.5, 42.0) - 2.0) < 0.001, "no tempo da queda percorre a altura toda")
	T.ok(HammerRules.fall_distance(t * 0.5, 1.5, 42.0) < 1.0, "acelera: na metade do tempo caiu menos da metade")
	T.eq(HammerRules.fall_time(0.0, 1.0, 10.0), 0.0, "sem altura, sem queda")
	T.ok(absf(HammerRules.fall_time(3.0, 2.0, 0.0) - 1.5) < 0.001, "sem aceleração: velocidade constante")


func test_config_timeline_and_size() -> void:
	var c := _cfg()
	T.ok(absf(c.hammer_size / c.circle_radius - 3.6 / 1.7) < 0.2, "martelo proporcional ao círculo (%.1f m, raio %.2f)" % [c.hammer_size, c.circle_radius])
	var aegis: AegisConfig = load("res://assets/vfx/aegis/aegis_config.tres")
	T.ok(is_equal_approx(c.circle_radius, aegis.circle_radius), "círculo do mesmo tamanho que o da Égide (%.2f m)" % c.circle_radius)
	T.ok(c.circle_height - c.hammer_size > 2.0, "o martelo pronto fica bem acima do chão (%.2f m)" % (c.circle_height - c.hammer_size))
	T.ok(c.fall_height() > 0.5, "o martelo cai de verdade (%.2f m)" % c.fall_height())
	var sum := c.circle_form_time + c.formation_time + c.circle_close_time + c.fall_time()
	T.ok(is_equal_approx(c.impact_time(), sum), "impacto = materializar + formar + fechar + cair")
	T.ok(c.crater_max_distance <= c.radius, "crateras dentro do raio de dano")


func test_crater_layout_covers_area_naturally() -> void:
	var c := _cfg()
	var pts := HammerRules.crater_layout(c.crater_count, c.crater_min_distance, c.crater_max_distance, 1234)
	T.eq(pts.size(), c.crater_count, "uma posição por cratera")
	var dists := {}
	var quad := [0, 0, 0, 0]
	for p in pts:
		var d := p.length()
		T.ok(d >= c.crater_min_distance - 0.001 and d <= c.crater_max_distance + 0.001, "cratera entre o mínimo e o máximo (%.2f)" % d)
		dists[snappedf(d, 0.01)] = true
		quad[(1 if p.x >= 0.0 else 0) + (2 if p.y >= 0.0 else 0)] += 1
	T.ok(dists.size() >= pts.size() - 1, "distâncias variadas (não todas iguais)")
	T.ok(quad.min() >= 1, "circular: crateras em todos os quadrantes %s" % [quad])
	for i in range(1, pts.size()):
		T.ok(pts[i].length() >= pts[i - 1].length(), "em ordem de distância (a onda se espalha)")
	var again := HammerRules.crater_layout(c.crater_count, c.crater_min_distance, c.crater_max_distance, 1234)
	T.ok(again == pts, "mesma semente, mesmas crateras (dono e réplicas)")
	T.ok(HammerRules.crater_layout(0, 1.0, 3.0, 1).is_empty(), "zero crateras: nenhuma")


func test_targets_in_radius_once() -> void:
	var center := Vector3(10, 0, 5)
	var hit := {}
	var cands := [
		{"id": 1, "pos": center + Vector3(1, 0, 1), "radius": 0.5},       # perto
		{"id": 2, "pos": center + Vector3(4.6, 0, 0), "radius": 0.5},     # encosta na borda pelo corpo
		{"id": 3, "pos": center + Vector3(6.0, 0, 0), "radius": 0.5},     # fora
		{"id": 4, "pos": center + Vector3(0, 2.5, 1.0), "radius": 0.4},   # mais alto, dentro no chão
	]
	var got := HammerRules.pick_targets(cands, center, 4.5, hit)
	var ids := got.map(func(t: Dictionary) -> int: return t.id)
	T.ok(1 in ids and 2 in ids and 4 in ids, "dentro do raio levam o golpe %s" % [ids])
	T.ok(not (3 in ids), "fora do raio não leva")
	var again := HammerRules.pick_targets(cands, center, 4.5, hit)
	T.ok(again.is_empty(), "cada inimigo uma vez por ativação")

