extends RefCounted
## SeismicSpikesRules: contas puras das Estacas Sísmicas (fases da pose, rachaduras se espalhando, frente do tremor,
## quem é atingido uma vez só e dentro do raio, a mão sobre a ponta cravada e o sacolejo do herói no terremoto).
## O kit (Estacas na tecla 3 e Fúria na 5 com a montante) fica no teste de fumaça (precisa do ItemDB).


func _cfg() -> SeismicSpikesConfig:
	return load("res://assets/vfx/seismic_spikes/seismic_spikes_config.tres")


func test_config_timeline_in_order() -> void:
	var c := _cfg()
	T.ok(is_equal_approx(c.radius, 4.5), "raio de 4,5 m")
	T.ok(c.impact_time() < c.quake_time() and c.quake_time() < c.pull_start() and c.pull_start() < c.pull_end()
		and c.pull_end() < c.total_time(), "cravar -> rachaduras -> tremor -> arrancar -> voltar, nessa ordem")
	T.ok(is_equal_approx(c.cracks_done_time() - c.impact_time(), c.crack_time), "as rachaduras chegam na borda no fim da fase 1")
	T.ok(c.quake_delay > 0.0 and is_equal_approx(c.quake_time() - c.cracks_done_time(), c.quake_delay),
		"a terra começa a tremer um intervalo (%.2f s) depois das rachaduras chegarem na borda" % c.quake_delay)
	T.ok(is_equal_approx(c.pull_end() - c.quake_time(), c.quake_hold + c.pull_time),
		"treme com a espada cravada e para quando ela sai do chão")
	var sum := 0.0
	for d in c.pose_durations():
		sum += d
	T.ok(absf(sum - c.total_time()) < 0.001, "as fases da pose somam o tempo do herói (%.2f x %.2f)" % [sum, c.total_time()])


func test_phase_at_walks_the_phases() -> void:
	var d := SeismicSpikesRules.durations(0.5, 0.1, 1.0, 0.5, 0.4)
	T.eq(SeismicSpikesRules.phase_at(-1.0, d), Vector2(0, 0.0), "antes do começo: erguer em 0")
	T.eq(SeismicSpikesRules.phase_at(0.25, d), Vector2(SeismicSpikesRules.WINDUP, 0.5), "metade do erguer")
	T.eq(int(SeismicSpikesRules.phase_at(0.55, d).x), SeismicSpikesRules.PLUNGE, "cravando")
	T.eq(int(SeismicSpikesRules.phase_at(1.2, d).x), SeismicSpikesRules.HOLD, "segurando cravada")
	T.eq(int(SeismicSpikesRules.phase_at(1.8, d).x), SeismicSpikesRules.PULL, "arrancando")
	T.eq(SeismicSpikesRules.phase_at(99.0, d), Vector2(SeismicSpikesRules.RECOVER, 1.0), "depois do fim: voltar em 1")
	var z := SeismicSpikesRules.durations(0.0, 0.0, 0.0, 0.0, 0.0)
	T.ok(z.all(func(x: float) -> bool: return x > 0.0), "nenhuma fase com duração zero")


func test_cracks_spread_from_center_to_edge() -> void:
	T.eq(SeismicSpikesRules.crack_reveal(0.0, 0.5), 0.0, "no impacto ainda não há rachadura")
	var prev := 0.0
	var grows := true
	for i in range(1, 11):
		var r := SeismicSpikesRules.crack_reveal(0.05 * i, 0.5)
		grows = grows and r > prev
		prev = r
	T.ok(grows, "as rachaduras crescem o tempo todo até a borda")
	T.ok(is_equal_approx(SeismicSpikesRules.crack_reveal(0.5, 0.5), 1.0) and is_equal_approx(SeismicSpikesRules.crack_reveal(2.0, 0.5), 1.0),
		"chegam na borda no tempo da fase 1 e param lá")
	T.ok(SeismicSpikesRules.crack_reveal(0.1, 0.5) > 0.2 * 1.5, "rápido no começo (o golpe)")


func test_quake_front_and_time_to_reach() -> void:
	var R := 4.5
	var P := 0.35
	T.eq(SeismicSpikesRules.quake_front(-0.1, R, P), 0.0, "antes do tremor nada")
	T.ok(is_equal_approx(SeismicSpikesRules.quake_front(P, R, P), R) and is_equal_approx(SeismicSpikesRules.quake_front(5.0, R, P), R),
		"chega na borda e para")
	T.ok(is_equal_approx(SeismicSpikesRules.quake_front(0.0, R, 0.0), R), "sem propagação: a área inteira de uma vez")
	for d in [0.5, 2.0, 4.4]:
		var t := SeismicSpikesRules.time_to_reach(d, R, P)
		T.ok(absf(SeismicSpikesRules.quake_front(t, R, P) - d) < 0.01, "o tremor chega a %.1f m no tempo previsto" % d)
	T.eq(SeismicSpikesRules.time_to_reach(5.0, R, P), INF, "fora do raio o tremor nunca chega")


func test_pick_reached_once_and_within_radius() -> void:
	var c := Vector3(10, 0, 10)
	var R := 4.5
	var targets := [
		{"id": 1, "pos": c + Vector3(1.0, 0, 0), "radius": 0.4},
		{"id": 2, "pos": c + Vector3(0, 3.0, 3.5), "radius": 0.4},   # a altura não importa
		{"id": 3, "pos": c + Vector3(4.7, 0, 0), "radius": 0.4},     # na borda, o corpo encosta
		{"id": 4, "pos": c + Vector3(6.0, 0, 0), "radius": 0.4},     # fora
	]
	var hit := {}
	var a := SeismicSpikesRules.pick_reached(targets, c, 1.5, R, hit)
	T.eq(a.map(func(x): return x.id), [1], "a frente em 1,5 m pega só o de perto")
	var b := SeismicSpikesRules.pick_reached(targets, c, R, R, hit)
	T.eq(b.map(func(x): return x.id), [2, 3], "na borda pega os outros de dentro, não o de perto de novo")
	var again := SeismicSpikesRules.pick_reached(targets, c, R, R, hit)
	T.eq(again.size(), 0, "cada um uma vez por ativação; o de fora nunca")


func test_hand_over_tip_keeps_blade_length() -> void:
	var tip := Vector3(0, -0.25, 0.8)
	var h := SeismicSpikesRules.hand_over_tip(tip, 1.3, 0.6)
	T.ok(absf(h.distance_to(tip) - 1.3) < 0.001, "a lâmina não estica nem encolhe (%.3f)" % h.distance_to(tip))
	T.ok(h.y > tip.y and is_equal_approx(h.z, 0.6), "a mão fica em cima da ponta cravada, um pouco atrás")


func test_quake_wobble_small_and_smooth() -> void:
	T.eq(SeismicSpikesRules.quake_wobble(1.0, 0.0), Vector2.ZERO, "sem tremor o herói fica parado")
	var big := 0.0
	var jump := 0.0
	var prev := SeismicSpikesRules.quake_wobble(0.0, 1.0)
	var moved := false
	for i in range(1, 300):
		var w := SeismicSpikesRules.quake_wobble(i / 120.0, 1.0)
		big = maxf(big, maxf(absf(w.x), absf(w.y)))
		jump = maxf(jump, (w - prev).length())
		moved = moved or (w - prev).length() > 0.001
		prev = w
	T.ok(moved and big <= 0.036, "sacode pouco (até %.3f rad)" % big)
	T.ok(jump < 0.02, "sem saltos de um quadro para o outro (%.4f)" % jump)
	T.eq(SeismicSpikesRules.quake_wobble(0.7, 1.0), SeismicSpikesRules.quake_wobble(0.7, 1.0), "igual no dono e nas réplicas")
