extends RefCounted
## FlameChannelRules: contas puras da Canalização de Fogo (o cone da labareda, o intervalo de tique por inimigo, o fim
## da canalização, a velocidade do jato e os quadros do círculo mágico) e a coerência da configuração.


func _cfg() -> FlameChannelConfig:
	return load("res://assets/vfx/flame_channel/flame_channel_config.tres")


func _in(pos: Vector3, er := 0.0) -> bool:
	# palma em (0, 1.3, 0), jato para +X, 4,5 m, raio 0,45 -> 1,6, pés em y = 0
	return FlameChannelRules.in_cone(Vector3(0, 1.3, 0), Vector3(1, 0, 0), pos, 4.5, 0.45, 1.6, 0.0, 2.5, 3.0, er)


func test_cone_reach_and_width() -> void:
	T.ok(_in(Vector3(1.0, 0.0, 0.0)), "logo à frente, no chão: dentro (a altura da palma não importa)")
	T.ok(_in(Vector3(4.4, 0.0, 0.0)), "perto da ponta (4,4 m): dentro")
	T.ok(not _in(Vector3(4.8, 0.0, 0.0)), "depois dos 4,5 m: fora")
	T.ok(_in(Vector3(4.8, 0.0, 0.0), 0.4), "o corpo do inimigo (raio) alcança a ponta")
	T.ok(not _in(Vector3(-0.8, 0.0, 0.0)), "atrás do mago: fora")
	T.ok(not _in(Vector3(0.5, 0.0, 1.0)), "do lado, perto da palma (o cone ainda é estreito): fora")
	T.ok(_in(Vector3(4.0, 0.0, 1.3)), "do lado, perto da ponta (o cone abriu): dentro")
	T.ok(not _in(Vector3(4.0, 0.0, 2.0)), "longe demais do eixo: fora")
	T.ok(not _in(Vector3(2.0, -3.0, 0.0)), "bem abaixo dos pés: fora")
	T.ok(not _in(Vector3(2.0, 3.5, 0.0)), "bem acima: fora")
	T.ok(not FlameChannelRules.in_cone(Vector3.ZERO, Vector3.UP, Vector3(1, 0, 0), 4.5, 0.4, 1.6, 0.0, 2.0, 2.0),
		"direção sem componente no chão: nada")


func test_ticks_respect_interval_per_target() -> void:
	var cone := {"origin": Vector3(0, 1.3, 0), "dir": Vector3(0, 0, -1), "length": 4.5, "r0": 0.45, "r1": 1.6,
		"feet_y": 0.0, "below": 2.5, "above": 3.0}
	var a := {"id": 1, "pos": Vector3(0, 0, -2), "radius": 0.4}
	var b := {"id": 2, "pos": Vector3(0, 0, -9), "radius": 0.4}
	var last := {}
	T.eq(FlameChannelRules.pick_targets([a, b], cone, 1.0, 0.2, last).size(), 1, "só quem está na labareda leva o tique")
	T.eq(FlameChannelRules.pick_targets([a, b], cone, 1.1, 0.2, last).size(), 0, "antes do intervalo: sem tique novo")
	T.eq(FlameChannelRules.pick_targets([a, b], cone, 1.2, 0.2, last).size(), 1, "no intervalo: tique de novo")
	# 1 s a 60 quadros: 5 tiques (0,2 s cada) no mesmo inimigo
	last = {}
	var n := 0
	for i in 60:
		n += FlameChannelRules.pick_targets([a], cone, i / 60.0, 0.2, last).size()
	T.eq(n, 5, "5 tiques por segundo")


func test_channel_end() -> void:
	T.ok(not FlameChannelRules.should_end(0.3, true, 0.7, 8.0, 50.0), "soltou antes do mínimo: continua")
	T.ok(FlameChannelRules.should_end(0.7, true, 0.7, 8.0, 50.0), "soltou e passou do mínimo: termina")
	T.ok(not FlameChannelRules.should_end(5.0, false, 0.7, 8.0, 50.0), "segurando: continua")
	T.ok(FlameChannelRules.should_end(8.0, false, 0.7, 8.0, 50.0), "tempo máximo: termina")
	T.ok(FlameChannelRules.should_end(1.0, false, 0.7, 8.0, 0.0), "sem mana: termina")


func test_jet_speed_reaches_length() -> void:
	for damping in [0.0, 1.5, 4.0]:
		var v := FlameChannelRules.jet_speed(4.5, 0.5, float(damping))
		var d: float = v * 0.5 - float(damping) * 0.5 * 0.5 * 0.5
		T.ok(absf(d - 4.5) < 0.001, "o jato chega a 4,5 m com amortecimento %.1f (%.3f)" % [damping, d])


func test_circle_frames() -> void:
	var form := Vector2i(1, 18)
	var loop := Vector2i(27, 50)
	var f := FlameChannelRules.circle_frame(0.0, form, 0.32, loop, 26.0)
	T.eq(f.x, 1.0, "começa no primeiro quadro da formação")
	f = FlameChannelRules.circle_frame(0.319, form, 0.32, loop, 26.0)
	T.ok(f.x >= 17.0 and f.y <= 18.0, "a formação termina no último quadro dela (%s)" % f)
	f = FlameChannelRules.circle_frame(0.32, form, 0.32, loop, 26.0)
	T.eq(f.x, 27.0, "depois da formação: o laço")
	# o laço emenda o último quadro no primeiro, sem sair da faixa
	var n := loop.y - loop.x + 1
	f = FlameChannelRules.circle_frame(0.32 + (n - 1 + 0.5) / 26.0, form, 0.32, loop, 26.0)
	T.eq(Vector2(f.x, f.y), Vector2(50, 27), "o último quadro do laço mistura com o primeiro")
	for i in 400:
		var g := FlameChannelRules.circle_frame(i * 0.037, form, 0.32, loop, 26.0)
		T.ok(g.x >= 1.0 and g.x <= 50.0 and g.y <= 50.0 and g.z >= 0.0 and g.z < 1.0, "quadro sempre válido")
	var e := FlameChannelRules.end_frame(1.0, Vector2i(56, 63))
	T.eq(e.x, 63.0, "o fim termina no anel apagado")


func test_config_is_coherent() -> void:
	var c := _cfg()
	T.ok(c != null, "a configuração carrega")
	T.ok(is_equal_approx(c.length, 6.5), "a labareda alcança 6,5 m")
	T.ok(c.radius_end > c.radius_start, "o cone abre à frente")
	T.ok(c.min_time >= c.windup_time, "um toque ainda solta fogo depois do preparo")
	T.ok(c.max_time > c.min_time, "o máximo passa do mínimo")
	T.ok(c.form_frames.y < c.loop_frames.x and c.loop_frames.y < c.end_frames.y and c.end_frames.y <= 63,
		"os trechos do círculo cabem na sheet 8 x 8")
	T.ok(c.damage_for(10.0) > c.damage_for(0.0), "o dano cresce com a INT")
