extends RefCounted
## GreatswordSupremeRules: contas puras da Lâmina Suprema (fases da animação, área do golpe e o golpe único por
## inimigo) e a coerência da configuração com a animação gerada (KnightMovesGreatCast).


func _cfg() -> GreatswordSupremeConfig:
	return load("res://assets/vfx/greatsword_supreme/greatsword_supreme_config.tres")


func test_phases_follow_the_timeline() -> void:
	var d := GreatswordSupremeRules.durations(0.5, 1.5, 0.6, 0.5, 0.8)
	T.eq(GreatswordSupremeRules.phase_at(0.0, d), Vector2(0, 0), "começa erguendo")
	T.eq(GreatswordSupremeRules.phase_at(0.25, d), Vector2(0, 0.5), "meio do erguer")
	T.eq(int(GreatswordSupremeRules.phase_at(0.5, d).x), 1, "depois de erguer: a carga")
	T.eq(int(GreatswordSupremeRules.phase_at(2.0, d).x), 2, "no fim da carga começa o corte")
	var k := GreatswordSupremeRules.phase_at(2.6, d)
	T.eq(int(k.x), 3, "depois do corte, ajoelhado")
	T.eq(GreatswordSupremeRules.phase_at(99.0, d), Vector2(4, 1), "depois do fim: o fim da última fase")
	var z := GreatswordSupremeRules.durations(0.0, -1.0, 0.1, 0.1, 0.1)
	T.ok(z[0] > 0.0 and z[1] > 0.0, "fase sem duração não divide por zero")


func test_area_covers_hit_point_and_cut_path() -> void:
	var o := Vector3.ZERO
	var c := Vector3(0, 0, 3.4)
	T.ok(GreatswordSupremeRules.in_area(o, c, Vector3(3.5, 2.0, 3.4), 4.0, 1.0), "no ponto do golpe (a altura não conta)")
	T.ok(not GreatswordSupremeRules.in_area(o, c, Vector3(4.5, 0, 3.4), 4.0, 1.0), "fora do raio")
	T.ok(GreatswordSupremeRules.in_area(o, c, Vector3(4.5, 0, 3.4), 4.0, 1.0, 0.6), "o corpo do inimigo encosta na borda")
	T.ok(GreatswordSupremeRules.in_area(o, Vector3(0, 0, 8), Vector3(0.8, 0, 1.5), 2.0, 1.0), "no caminho do corte")
	T.ok(not GreatswordSupremeRules.in_area(o, Vector3(0, 0, 8), Vector3(0, 0, -1.5), 2.0, 1.0), "atrás do herói não")
	T.ok(not GreatswordSupremeRules.in_area(o, Vector3(0, 0, 8), Vector3(0.8, 0, 1.5), 2.0, 0.0), "sem corte, só o ponto do golpe")


func test_crater_area_is_a_straight_band() -> void:
	var a := Vector3.ZERO
	var b := Vector3(0, 0, 10)
	var c := Vector3(0, 0, 6)
	T.ok(GreatswordSupremeRules.in_crater(a, b, c, Vector3(1.4, 0, 9.0), 2.0, 1.5), "dentro da cratera, além do ponto do golpe")
	T.ok(not GreatswordSupremeRules.in_crater(a, b, c, Vector3(1.7, 0, 9.0), 2.0, 1.5), "fora dos 3 m de largura")
	T.ok(GreatswordSupremeRules.in_crater(a, b, c, Vector3(1.9, 0, 6.5), 2.0, 1.5), "no raio do ponto do golpe")
	T.ok(not GreatswordSupremeRules.in_crater(a, b, c, Vector3(0, 0, 11.6), 2.0, 1.5), "além da ponta da cratera não")
	T.ok(GreatswordSupremeRules.in_crater(a, b, c, Vector3(1.7, 0, 9.0), 2.0, 1.5, 0.3), "o corpo do inimigo encosta na borda")


func test_each_enemy_hit_once() -> void:
	var hit := {}
	var ts := [{"id": 1, "pos": Vector3(0, 0, 3)}, {"id": 2, "pos": Vector3(20, 0, 0)}, {"id": 3, "pos": Vector3(1, 0, 8), "radius": 0.5}]
	var a := GreatswordSupremeRules.pick_targets(ts, Vector3.ZERO, Vector3(0, 0, 9), Vector3(0, 0, 5), 2.5, 1.5, hit)
	T.eq(a.map(func(x: Dictionary) -> int: return x.id), [1, 3], "só quem está na cratera")
	T.eq(GreatswordSupremeRules.pick_targets(ts, Vector3.ZERO, Vector3(0, 0, 9), Vector3(0, 0, 5), 2.5, 1.5, hit).size(), 0,
		"ninguém leva duas vezes")


func test_souls_spawn_in_the_crater_and_flee_outwards() -> void:
	var a := Vector3.ZERO
	var b := Vector3(0, 0, 10)
	for k in 9:
		var along := float(k) / 8.0
		var p := GreatswordSupremeRules.soul_spawn(a, b, 1.5, along, float(k % 3) * 0.5)
		T.ok(absf(p.x) <= 1.5 and p.z >= -0.01 and p.z <= 10.01, "a alma nasce dentro da cratera (%s)" % p)
		var f := GreatswordSupremeRules.soul_flee_dir(a, b, p, float(k) / 8.0)
		T.ok(is_equal_approx(f.length(), 1.0) and is_zero_approx(f.y), "foge pelo chão (normalizado)")
		if absf(p.x) > 0.05:
			T.ok(f.x * p.x > 0.0, "foge para o lado em que nasceu (%s de %s)" % [f, p])


func test_back_weight() -> void:
	T.eq(GreatswordSupremeRules.back_weight(0.3, 0.6), 0.0, "antes de começar a voltar")
	T.ok(is_equal_approx(GreatswordSupremeRules.back_weight(0.8, 0.6), 0.5), "metade da volta")
	T.eq(GreatswordSupremeRules.back_weight(1.0, 0.6), 1.0, "no fim, na guarda")


func test_config_and_generated_animation() -> void:
	var c := _cfg()
	T.ok(is_equal_approx(c.impact_time(), c.raise_time + c.charge_time + c.slash_time), "impacto = erguer + carga + corte")
	T.ok(c.total_time() > c.impact_time(), "depois do impacto ainda ajoelha e levanta")
	T.ok(c.sword_length >= 5.0, "espada de energia ~3x a altura do herói (%.2f m)" % c.sword_length)
	T.ok(absf(c.impact_distance - c.sword_length) < 1.0, "a ponta alcança o ponto do golpe sem encolher (%.2f m)" % c.impact_distance)
	T.ok(c.crack_length() > c.impact_distance and absf(c.crack_center_offset()) < c.crack_length() * 0.5,
		"a cratera passa pelo ponto do golpe, do herói até além da ponta (%.1f m)" % c.crack_length())
	T.ok(is_equal_approx(c.crack_width, 3.0) and is_equal_approx(c.cut_half_width * 2.0, c.crack_width),
		"cratera de 3 m de largura, e o dano pega a largura toda")
	T.ok(c.soul_count > 0 and c.soul_life > 0.5, "almas saem da cratera")
	T.ok(c.crack_hold + c.fade_time >= c.soul_life, "a cratera dura enquanto as almas voam")
	T.ok(c.impact_radius > 0.0 and c.impact_distance > 0.0, "o impacto é à frente e tem área")
	T.eq(KnightMovesGreatCast.TRACKS.size(), GreatswordSupremeRules.PHASE_COUNT, "uma trilha por fase")
	for tr in KnightMovesGreatCast.TRACKS:
		for j in ["end", "dir", "edge", "twist", "spin"]:
			T.eq((tr[j] as Array).size(), KnightMovesGreatCast.N, "trilha %s com N quadros" % j)
	# a lâmina termina o corte no chão, à frente
	T.ok(KnightMovesGreatCast.IMPACT_TIP.z > 1.0 and KnightMovesGreatCast.IMPACT_TIP.y < 0.8,
		"a ponta da lâmina crava à frente, perto do chão (%s)" % KnightMovesGreatCast.IMPACT_TIP)
	# fases emendadas: o fim de uma é o começo da seguinte
	for k in range(1, KnightMovesGreatCast.TRACKS.size()):
		var a: Dictionary = KnightMovesGreatCast.TRACKS[k - 1]
		var b: Dictionary = KnightMovesGreatCast.TRACKS[k]
		T.ok(((a.end as Array).back() as Vector3).distance_to(b.end[0]) < 0.03, "a arma emenda na fase %d" % k)
		T.ok(((a.edge as Array).back() as Vector3).dot(b.edge[0]) > 0.9, "o gume não vira na fase %d" % k)
		T.ok(absf(float((a.twist as Array).back()) - float(b.twist[0])) < 0.05, "o tronco emenda na fase %d" % k)
