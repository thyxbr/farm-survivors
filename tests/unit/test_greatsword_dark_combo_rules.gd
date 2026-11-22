extends RefCounted
## GreatswordDarkComboRules: contas puras da Dança do Abismo (o relógio dos quatro golpes emendados, os acertos, o quanto
## o herói anda, o arco de cada golpe) e a coerência da configuração com a animação gerada (KnightMovesGreatDark).


func _cfg() -> GreatswordDarkComboConfig:
	return load("res://assets/vfx/greatsword_dark/greatsword_dark_combo_config.tres")


func test_segments_chain_before_the_previous_ends() -> void:
	var lens := GreatswordDarkComboRules.segment_lengths([2.0, 1.0, 1.0], 2.0)
	T.eq(lens, [1.0, 0.5, 0.5] as Array[float], "a velocidade encurta cada clipe")
	var starts := GreatswordDarkComboRules.segment_starts(lens, [0.8, 0.5, 1.0])
	T.eq(starts, [0.0, 0.8, 1.05] as Array[float], "o seguinte entra na fração `chain` do anterior")
	T.ok(is_equal_approx(GreatswordDarkComboRules.total_time(lens, starts), 1.55), "o último toca até o fim")
	T.eq(GreatswordDarkComboRules.segment_at(0.0, lens, starts), Vector2(0, 0), "começa no primeiro golpe (sempre o deslize)")
	T.eq(GreatswordDarkComboRules.segment_at(0.5, lens, starts), Vector2(0, 0.5), "meio do primeiro")
	var s := GreatswordDarkComboRules.segment_at(0.9, lens, starts)
	T.ok(int(s.x) == 1 and is_equal_approx(s.y, 0.2), "depois da emenda, o segundo (%s)" % s)
	T.eq(GreatswordDarkComboRules.segment_at(99.0, lens, starts), Vector2(2, 1), "depois do fim: o fim do último")
	T.ok(GreatswordDarkComboRules.segment_lengths([1.0], 0.0)[0] > 0.0, "velocidade zero não divide por zero")


func test_hits_fire_once_in_their_window() -> void:
	var lens: Array[float] = [1.0, 1.0]
	var starts: Array[float] = [0.0, 0.9]
	T.ok(is_equal_approx(GreatswordDarkComboRules.hit_time(1, 0.5, lens, starts), 1.4), "acerto no meio do segundo golpe")
	var segs := [0, 1, 1]
	var ats := [0.5, 0.2, 0.8]
	var fired := []
	var t := 0.0
	while t < 2.0:
		fired.append_array(GreatswordDarkComboRules.hits_between(t, t + 1.0 / 60.0, segs, ats, lens, starts))
		t += 1.0 / 60.0
	T.eq(fired, [0, 1, 2], "cada acerto uma vez, na ordem")
	T.eq(GreatswordDarkComboRules.hits_between(0.6, 0.6, segs, ats, lens, starts).size(), 0, "intervalo vazio não acerta")


func test_root_motion_interpolates() -> void:
	var root := [Vector3.ZERO, Vector3(0, 0, 1), Vector3(0, 0, 3)]
	T.eq(GreatswordDarkComboRules.root_at(root, 0.0), Vector3.ZERO, "começo")
	T.eq(GreatswordDarkComboRules.root_at(root, 0.75), Vector3(0, 0, 2), "entre dois quadros")
	T.eq(GreatswordDarkComboRules.root_at(root, 2.0), Vector3(0, 0, 3), "depois do fim fica no último")
	T.eq(GreatswordDarkComboRules.root_at([], 0.5), Vector3.ZERO, "sem trilha não anda")


func test_arc_front_and_around() -> void:
	var o := Vector3.ZERO
	var f := Vector3(0, 0, 1)
	T.ok(GreatswordDarkComboRules.in_arc(o, f, Vector3(0.5, 0, 2.5), 3.0, 160.0), "à frente, no alcance")
	T.ok(not GreatswordDarkComboRules.in_arc(o, f, Vector3(0, 0, -2.0), 3.0, 160.0), "atrás de um golpe à frente não")
	T.ok(GreatswordDarkComboRules.in_arc(o, f, Vector3(0, 0, -2.0), 3.0, 360.0), "um golpe girando acerta atrás")
	T.ok(not GreatswordDarkComboRules.in_arc(o, f, Vector3(0, 0, 3.5), 3.0, 360.0), "fora do alcance")
	T.ok(GreatswordDarkComboRules.in_arc(o, f, Vector3(0, 0, 3.5), 3.0, 160.0, 0.6), "o corpo do inimigo encosta no alcance")
	T.ok(GreatswordDarkComboRules.in_arc(o, f, Vector3(0.3, 0, -0.4), 3.0, 90.0), "encostado no herói conta sempre")
	var ts := [{"pos": Vector3(0, 0, 2)}, {"pos": Vector3(0, 4.0, 2)}, {"pos": Vector3(0, 0, -2)}]
	T.eq(GreatswordDarkComboRules.pick_targets(ts, o, f, 3.0, 160.0).size(), 1, "só o da frente e na altura do herói")


func test_config_and_generated_animation() -> void:
	var c := _cfg()
	T.ok(c != null, "a configuração carrega")
	T.eq(KnightMovesGreatDark.TRACKS.size(), 4, "quatro golpes")
	T.eq(KnightMovesGreatDark.ROOT.size(), 4, "uma trilha de deslocamento por golpe")
	T.eq(KnightMovesGreatDark.CLIP_TIME.size(), 4, "uma duração por golpe")
	for k in KnightMovesGreatDark.TRACKS.size():
		var tr: Dictionary = KnightMovesGreatDark.TRACKS[k]
		for j in ["end", "dir", "edge", "twist", "spin", "leg_l", "knee_r"]:
			T.eq((tr[j] as Array).size(), KnightMovesGreatDark.N, "golpe %d: trilha %s com N quadros" % [k, j])
		T.eq((KnightMovesGreatDark.ROOT[k] as Array).size(), KnightMovesGreatDark.N, "golpe %d: deslocamento com N quadros" % k)
	# o deslize (sempre o primeiro) vai bem para a frente; o modelo olha para +Z
	var slide: Vector3 = (KnightMovesGreatDark.ROOT[KnightMovesGreatDark.SLIDE] as Array).back()
	T.ok(slide.z > 2.0 and absf(slide.x) < slide.z * 0.3, "o deslize avança para a frente (%s)" % slide)
	var n := c.hit_count()
	T.ok(n >= 4, "pelo menos um acerto por golpe (%d)" % n)
	var segs := {}
	for i in n:
		T.ok(c.hit_segment[i] >= 0 and c.hit_segment[i] < 4 and c.hit_at[i] > 0.0 and c.hit_at[i] < 1.0,
			"acerto %d dentro de um golpe" % i)
		T.ok(c.hit_mult[i] > 0.0 and c.hit_reach[i] > 1.0 and c.hit_arc[i] > 0.0, "acerto %d com dano, alcance e arco" % i)
		segs[c.hit_segment[i]] = true
		if i > 0:
			var lens := c.lengths()
			var starts := c.starts()
			T.ok(GreatswordDarkComboRules.hit_time(c.hit_segment[i], c.hit_at[i], lens, starts)
				> GreatswordDarkComboRules.hit_time(c.hit_segment[i - 1], c.hit_at[i - 1], lens, starts), "acertos em ordem (%d)" % i)
	T.eq(segs.size(), 4, "os quatro golpes acertam")
	var total := 0.0
	for m in c.hit_mult:
		total += m
	T.ok(total > 2.0 and total < 6.0, "dano do combo inteiro razoável para a recarga (%.2fx)" % total)
	T.ok(c.total_time() > 3.0 and c.total_time() < 7.0, "combo de %.1f s" % c.total_time())
	T.eq(c.chain.size(), 4, "uma emenda por golpe")
	# a emenda não pula o acerto: cada acerto acontece antes do golpe seguinte começar
	for i in n:
		var seg := c.hit_segment[i]
		if seg < 3:
			T.ok(c.hit_at[i] < c.chain[seg], "acerto %d antes da emenda do golpe %d" % [i, seg])
