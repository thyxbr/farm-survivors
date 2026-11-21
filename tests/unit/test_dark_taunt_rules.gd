extends RefCounted
## DarkTauntRules: contas puras do Círculo da Provocação Sombria (quem está no círculo, uma vez por ativação; onde
## as mãos saem do chão; o tempo do clipe do herói; imobilização e provocação; quando a provocação deixa de valer).
## O kit (slot 3 com escudo), a IA provocada e o visual ficam no teste de fumaça (precisam dos autoloads).


func _cfg() -> DarkTauntConfig:
	return load("res://assets/vfx/dark_taunt/dark_taunt_config.tres")


func test_pick_targets_inside_once() -> void:
	var c := Vector3(10, 0, 10)
	var taken := {}
	var list := [
		{"id": 1, "pos": c + Vector3(2, 0, 0), "radius": 0.5},
		{"id": 2, "pos": c + Vector3(0, 3.0, -4.5), "radius": 0.5},   # alto, mas dentro no chão
		{"id": 3, "pos": c + Vector3(6.3, 0, 0), "radius": 0.5},      # encosta na borda (raio 6)
		{"id": 4, "pos": c + Vector3(8, 0, 0), "radius": 0.5},        # fora
		{"id": 5, "pos": c + Vector3(-1, 0, 0.5), "radius": 0.4},
	]
	var got := DarkTauntRules.pick_targets(list, c, 6.0, taken)
	var ids := got.map(func(x): return x.id)
	T.eq(ids, [5, 1, 2, 3], "dentro do raio (a altura não conta), do mais perto para o mais longe")
	T.ok(not 4 in ids, "fora do círculo não é agarrado")
	T.eq(DarkTauntRules.pick_targets(list, c, 6.0, taken).size(), 0, "mesma ativação: ninguém é agarrado duas vezes")


func test_hand_spots_spread_inside_circle() -> void:
	var targets := [Vector2(3, 0), Vector2(-2, 2), Vector2(0, -4.5)]
	var spots := DarkTauntRules.hand_spots(targets, 8, 6.0, 1.0, 77)
	T.eq(spots.size(), 8, "uma posição por mão")
	var per_target := {}
	for s in spots:
		var p: Vector2 = s.pos
		T.ok(p.length() <= 6.0, "mão dentro do círculo (%.2f m)" % p.length())
		if int(s.target) >= 0:
			per_target[int(s.target)] = true
			var o: Vector2 = targets[int(s.target)]
			T.ok(p.distance_to(o) <= DarkTauntRules.HAND_GAP + 0.01, "a mão do alvo sai perto dele (%.2f m)" % p.distance_to(o))
	T.eq(per_target.size(), targets.size(), "cada alvo tem a sua mão")
	# não saem todas do mesmo lugar: as sem alvo ficam afastadas umas das outras
	var free := spots.filter(func(s): return int(s.target) < 0)
	var min_gap := INF
	for i in free.size():
		for j in range(i + 1, free.size()):
			min_gap = minf(min_gap, (free[i].pos as Vector2).distance_to(free[j].pos))
	T.ok(min_gap >= DarkTauntRules.HAND_MIN_GAP - 0.01, "mãos sem alvo espalhadas (menor distância %.2f m)" % min_gap)
	var quad := {}
	for s in spots:
		var p: Vector2 = s.pos
		quad[int(floor((p.angle() + PI) / (TAU / 4.0))) % 4] = true
	T.ok(quad.size() >= 3, "mãos em vários lados do círculo (%d quadrantes)" % quad.size())
	var again := DarkTauntRules.hand_spots(targets, 8, 6.0, 1.0, 77)
	T.ok(again.size() == spots.size() and (again[5].pos as Vector2).is_equal_approx(spots[5].pos), "mesma semente = mesmas mãos (rede)")
	T.eq(DarkTauntRules.hand_spots([], 0, 6.0, 1.0, 1).size(), 0, "sem mãos configuradas e sem alvo: nenhuma")
	T.eq(DarkTauntRules.hand_spots(targets, 1, 6.0, 1.0, 1).size(), targets.size(), "mais alvos que mãos: cada alvo ainda ganha a sua")


func test_clip_time_holds_then_returns() -> void:
	var hold_end := 2.0
	T.eq(DarkTauntRules.clip_time(0.3, hold_end, 0.5), 0.3, "começo em tempo real (recolhe e explode)")
	var a := DarkTauntRules.clip_time(1.0, hold_end, 0.5)
	var b := DarkTauntRules.clip_time(1.9, hold_end, 0.5)
	T.ok(a >= DarkTauntRules.CLIP_HOLD_FROM and b <= DarkTauntRules.CLIP_RETURN_FROM and b > a, "segura no trecho parado do clipe (%.2f -> %.2f)" % [a, b])
	T.eq(DarkTauntRules.clip_time(2.5, hold_end, 0.5), DarkTauntRules.CLIP_END, "volta à guarda até o fim do clipe")
	T.ok(DarkTauntRules.clip_time(2.25, hold_end, 0.5) > DarkTauntRules.CLIP_RETURN_FROM, "depois das mãos agarrarem, volta")


func test_taunt_times() -> void:
	T.eq(DarkTauntRules.taunt_times(1.5, 6.0, false), Vector2(1.5, 7.5), "preso 1,5 s; provocado do agarrão até 6 s depois de soltar")
	T.eq(DarkTauntRules.taunt_times(1.5, 6.0, true), Vector2(0.0, 7.5), "chefe não fica preso, mas é provocado")
	T.eq(DarkTauntRules.taunt_times(-3.0, NAN, false), Vector2(0.0, 0.0), "valores inválidos viram zero")


func test_taunter_ok() -> void:
	T.ok(DarkTauntRules.taunter_ok(true, true, false, true), "herói vivo, no mesmo mundo, fora da vila: vale")
	T.ok(not DarkTauntRules.taunter_ok(false, true, false, true), "herói morto: a provocação acaba")
	T.ok(not DarkTauntRules.taunter_ok(true, false, false, true), "herói em outro mundo (saiu): acaba")
	T.ok(not DarkTauntRules.taunter_ok(true, true, true, true), "herói entrou na vila: a guarda protege, acaba")
	T.ok(not DarkTauntRules.taunter_ok(true, true, false, false), "fora da sala do chefe: acaba")


func test_config_timeline() -> void:
	var c := _cfg()
	T.ok(c.radius >= 3.0 and c.hold_time > 0.0 and c.taunt_time > c.hold_time, "raio, imobilização e provocação com sentido")
	var grab := DarkTauntConfig.CAST_LEAD + c.circle_form_time + c.rise_time() + DarkTauntRules.REACH_TIME
	T.ok(is_equal_approx(c.grab_at(), grab), "as mãos agarram depois de o círculo se formar e elas subirem (%.2f s)" % c.grab_at())
	T.ok(is_equal_approx(c.release_at(), c.grab_at() + c.hold_time), "soltam depois da imobilização")
	T.ok(c.grab_at() < 3.5, "o herói não fica preso tempo demais (%.2f s)" % c.grab_at())
	var fast := c.duplicate() as DarkTauntConfig
	fast.hand_rise_speed = 2.0
	T.ok(fast.rise_time() < c.rise_time(), "velocidade de emergência maior = mãos sobem mais rápido")
