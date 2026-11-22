extends RefCounted
## GreatswordSpinRules: contas puras do Ciclone de Aço (fases, aceleração e desaceleração suaves, o giro fechando as
## voltas pedidas, o alcance e o intervalo de corte por inimigo) e a coerência da configuração.


func _cfg() -> GreatswordSpinConfig:
	return load("res://assets/vfx/greatsword_spin/greatsword_spin_config.tres")


func _d() -> Array[float]:
	return GreatswordSpinRules.durations(0.3, 0.4, 1.2, 0.8, 0.3)


func test_phases_follow_the_timeline() -> void:
	var d := _d()
	T.eq(GreatswordSpinRules.phase_at(0.0, d), Vector2(0, 0), "começa na postura")
	T.eq(int(GreatswordSpinRules.phase_at(0.35, d).x), GreatswordSpinRules.Phase.ACCEL, "depois da postura: acelera")
	T.eq(int(GreatswordSpinRules.phase_at(1.0, d).x), GreatswordSpinRules.Phase.SPIN, "gira na velocidade máxima")
	T.eq(int(GreatswordSpinRules.phase_at(2.0, d).x), GreatswordSpinRules.Phase.DECEL, "desacelera")
	T.eq(int(GreatswordSpinRules.phase_at(2.8, d).x), GreatswordSpinRules.Phase.RECOVER, "volta à guarda")
	T.eq(GreatswordSpinRules.phase_at(99.0, d), Vector2(4, 1), "depois do fim: o fim da última fase")
	var z := GreatswordSpinRules.durations(0.0, -1.0, 0.1, 0.1, 0.1)
	T.ok(z[0] > 0.0 and z[1] > 0.0, "fase sem duração não divide por zero")


func test_speed_ramps_up_and_down_smoothly() -> void:
	var d := _d()
	T.eq(GreatswordSpinRules.speed_frac(0.1, d), 0.0, "parado na postura")
	_near(GreatswordSpinRules.speed_frac(0.3 + 0.2, d), 0.5, 0.001, "meio da aceleração: metade da velocidade")
	T.eq(GreatswordSpinRules.speed_frac(1.2, d), 1.0, "velocidade máxima no giro")
	_near(GreatswordSpinRules.speed_frac(1.9 + 0.4, d), 0.5, 0.001, "meio da desaceleração: metade")
	T.eq(GreatswordSpinRules.speed_frac(2.8, d), 0.0, "parado no fim")
	# sem trancos: a velocidade muda pouco de um passo de física para o outro em toda a linha do tempo
	var prev := 0.0
	var worst := 0.0
	var t := 0.0
	while t < 3.0:
		var s := GreatswordSpinRules.speed_frac(t, d)
		worst = maxf(worst, absf(s - prev))
		prev = s
		t += 1.0 / 60.0
	T.ok(worst < 0.07, "aceleração e desaceleração suaves (maior salto %.3f)" % worst)


func test_angle_integrates_speed_and_closes_the_turns() -> void:
	var d := _d()
	var turns := 5
	var w := GreatswordSpinRules.max_speed(d, turns)
	T.eq(GreatswordSpinRules.angle(0.2, d, turns), 0.0, "não gira na postura")
	_near(GreatswordSpinRules.angle(99.0, d, turns), turns * TAU, 0.0001, "termina com as voltas completas")
	_near(GreatswordSpinRules.angle(2.7 - 0.0001, d, turns), turns * TAU, 0.001, "o fim da desaceleração fecha as voltas")
	# o ângulo é a integral da velocidade: a derivada numérica bate com speed_frac * w
	for t: float in [0.45, 0.6, 1.0, 1.6, 2.1, 2.5]:
		var h := 0.0005
		var deriv := (GreatswordSpinRules.angle(t + h, d, turns) - GreatswordSpinRules.angle(t - h, d, turns)) / (2.0 * h)
		_near(deriv, GreatswordSpinRules.speed_frac(t, d) * w, 0.05, "velocidade angular contínua em %.2f s" % t)
	# nunca gira para trás
	var prev := -1.0
	var mono := true
	var t := 0.0
	while t < 3.0:
		var a := GreatswordSpinRules.angle(t, d, turns)
		mono = mono and a >= prev - 0.000001
		prev = a
		t += 0.01
	T.ok(mono, "o ângulo só aumenta")


func test_reach_counts_ground_distance_and_height() -> void:
	var c := Vector3.ZERO
	T.ok(GreatswordSpinRules.in_reach(c, Vector3(3.0, 0.5, 0.0), 3.1, 2.5), "dentro do alcance")
	T.ok(not GreatswordSpinRules.in_reach(c, Vector3(3.5, 0.0, 0.0), 3.1, 2.5), "fora do alcance")
	T.ok(GreatswordSpinRules.in_reach(c, Vector3(3.5, 0.0, 0.0), 3.1, 2.5, 0.5), "o corpo do inimigo encosta na borda")
	T.ok(not GreatswordSpinRules.in_reach(c, Vector3(1.0, 4.0, 0.0), 3.1, 2.5), "muito acima não")
	T.ok(GreatswordSpinRules.in_reach(c, Vector3(-2.0, 0.0, -2.0), 3.1, 2.5), "atrás também (o giro corta em volta)")


func test_each_target_waits_the_hit_interval() -> void:
	var last := {}
	var mobs := [{"id": 1, "pos": Vector3(1, 0, 0)}, {"id": 2, "pos": Vector3(0, 0, -2)}, {"id": 3, "pos": Vector3(9, 0, 0)}]
	var a := GreatswordSpinRules.pick_targets(mobs, Vector3.ZERO, 3.0, 2.5, 1.0, 0.3, last)
	T.eq(a.map(func(x): return x.id), [1, 2], "corta os dois no alcance; o longe não")
	T.eq(GreatswordSpinRules.pick_targets(mobs, Vector3.ZERO, 3.0, 2.5, 1.1, 0.3, last).size(), 0, "antes do intervalo: nada")
	T.eq(GreatswordSpinRules.pick_targets(mobs, Vector3.ZERO, 3.0, 2.5, 1.3, 0.3, last).size(), 2, "passado o intervalo: de novo")
	# um giro inteiro a 60 Hz: cortes por inimigo = tempo / intervalo (sem dano a cada quadro)
	last.clear()
	var hits := 0
	for i in 60:
		hits += GreatswordSpinRules.pick_targets([mobs[0]], Vector3.ZERO, 3.0, 2.5, i / 60.0, 0.3, last).size()
	T.eq(hits, 4, "1 s com intervalo de 0,3 s: 4 cortes")


func test_config_defaults_are_coherent() -> void:
	var c := _cfg()
	T.ok(c != null, "a configuração carrega")
	var d := c.durations()
	T.eq(d.size(), GreatswordSpinRules.PHASE_COUNT, "uma duração por fase")
	_near(c.total_time(), d[0] + d[1] + d[2] + d[3] + d[4], 0.0001, "tempo total = soma das fases")
	# a energia sombria segue o corte: o rastro dura uma parte do giro (não vira um anel fechado) e passa da ponta
	var arc := GreatswordSpinRules.max_speed(d, c.turns) * c.trail_time
	T.ok(arc > PI * 0.5 and arc < TAU * 0.9, "rastro sombrio cobre parte da volta na velocidade máxima (%.0f°)" % rad_to_deg(arc))
	T.ok(c.trail_reach > 0.0 and c.trail_reach < c.radius, "a energia passa da ponta sem passar do alcance")
	T.ok(c.hit_interval >= 0.1, "intervalo por alvo impede dano a cada quadro")
	var turns_s := GreatswordSpinRules.max_speed(d, c.turns) / TAU
	T.ok(turns_s > 1.0 and turns_s < 5.0, "velocidade máxima de giro legível (%.1f voltas/s)" % turns_s)


func _near(a: float, b: float, tol: float, msg: String) -> void:
	T.ok(absf(a - b) <= tol, "%s (%.4f ~ %.4f)" % [msg, a, b])


func test_lean_only_while_spinning() -> void:
	var d := _d()   # postura 0,3 / aceleração 0,4 / giro 1,2 / desaceleração 0,8 / volta 0,3
	T.eq(GreatswordSpinRules.lean_weight(0.2, d), 0.0, "na postura o tronco fica reto (braços erguidos à frente)")
	var mid_accel := GreatswordSpinRules.lean_weight(0.5, d)
	T.ok(mid_accel > 0.2 and mid_accel < 0.8, "inclina para trás junto com a aceleração (%.2f)" % mid_accel)
	T.eq(GreatswordSpinRules.lean_weight(1.2, d), 1.0, "inclinado no giro")
	T.eq(GreatswordSpinRules.lean_weight(2.1, d), 1.0, "ainda inclinado no começo da desaceleração")
	var late := GreatswordSpinRules.lean_weight(2.6, d)
	T.ok(late > 0.0 and late < 1.0, "volta ao normal no fim da animação (%.2f)" % late)
	T.eq(GreatswordSpinRules.lean_weight(2.86, d), 0.0, "reto antes de acabar")
	T.eq(GreatswordSpinRules.lean_weight(9.0, d), 0.0, "reto depois do fim")
