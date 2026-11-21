extends RefCounted
## BlizzardRules: as habilidades da Sentinela da Nevasca (escolha do golpe, o Sopro em cone que gira, as Estacas,
## os braseiros e a exposição à nevasca).


func test_specials_alternate_on_odd_attacks() -> void:
	T.eq(BlizzardRules.attack(0, 3.0, 4.0, false), "swing", "perto: patada")
	T.eq(BlizzardRules.attack(1, 3.0, 4.0, false), "breath", "2º golpe: sopro")
	T.eq(BlizzardRules.attack(2, 3.0, 4.0, false), "swing", "3º: patada de novo")
	T.eq(BlizzardRules.attack(3, 3.0, 4.0, false), "icicles", "4º: estacas")
	T.eq(BlizzardRules.attack(5, 3.0, 4.0, false), "breath", "o ciclo recomeça")


func test_far_target_gets_the_other_special() -> void:
	T.eq(BlizzardRules.attack(0, 12.0, 4.0, false), "icicles", "longe, antes do sopro: estacas")
	T.eq(BlizzardRules.attack(2, 12.0, 4.0, false), "breath", "longe, antes das estacas: sopro")


func test_roar_comes_first() -> void:
	T.eq(BlizzardRules.attack(0, 3.0, 4.0, true), "blizzard", "a fúria começa chamando a nevasca")
	T.eq(BlizzardRules.attack(3, 12.0, 4.0, true), "blizzard", "em qualquer ponto do ciclo")


func test_breath_sweeps_through_the_target() -> void:
	for sign in [1.0, -1.0]:
		var aim := 0.7
		var start := BlizzardRules.breath_start(aim, sign, false)
		var a0 := BlizzardRules.breath_angle(start, sign, 0.0, false)
		var a_end := BlizzardRules.breath_angle(start, sign, BlizzardRules.BREATH_T0 + BlizzardRules.BREATH_TIME, false)
		_near(a0, start, 0.0001, "parado no preparo")
		_near(absf(a_end - a0), deg_to_rad(BlizzardRules.BREATH_SWEEP), 0.0001, "gira o arco inteiro")
		T.ok((aim - a0) * sign > 0.0 and (a_end - aim) * sign > 0.0, "o alvo fica dentro do arco varrido")
	T.ok(BlizzardRules.sweep(true) > BlizzardRules.sweep(false), "na fúria o arco é maior")
	T.ok(BlizzardRules.sweep_sign(0) != BlizzardRules.sweep_sign(1), "o sentido alterna")


func test_breath_active_window() -> void:
	T.ok(not BlizzardRules.breath_active(BlizzardRules.BREATH_T0 - 0.1), "no preparo não sopra")
	T.ok(BlizzardRules.breath_active(BlizzardRules.BREATH_T0 + 1.0), "soprando")
	T.ok(not BlizzardRules.breath_active(BlizzardRules.BREATH_T0 + BlizzardRules.BREATH_TIME + 0.1), "acabou")


func test_cone_hits_inside_and_misses_outside() -> void:
	var o := Vector3(3, 0, -2)
	var a := deg_to_rad(90.0)   # para +X
	T.ok(BlizzardRules.in_cone(o, a, o + Vector3(8, 0, 0)), "na frente")
	T.ok(BlizzardRules.in_cone(o, a, o + Vector3(8, 3, 2)), "dentro do ângulo, a altura não conta")
	T.ok(not BlizzardRules.in_cone(o, a, o + Vector3(8, 0, 5)), "de lado: escapa")
	T.ok(not BlizzardRules.in_cone(o, a, o + Vector3(-6, 0, 0)), "atrás: escapa")
	T.ok(not BlizzardRules.in_cone(o, a, o + Vector3(BlizzardRules.BREATH_RANGE + 1.0, 0, 0)), "além do alcance: escapa")
	T.ok(BlizzardRules.in_cone(o, a, o + Vector3(-0.3, 0, 0.2)), "debaixo do focinho pega")


func test_breath_survives_the_snapshot() -> void:
	for sign in [1.0, -1.0]:
		var start := -2.1
		var flags := ThrowRules.pack_flags(3, BlizzardRules.breath_offset(start, sign))
		var got := BlizzardRules.breath_unpack(ThrowRules.unpack_offset(flags))
		_near(wrapf(float(got[0]) - start, -PI, PI), 0.0, TAU / 256.0, "direção inicial (256 passos)")
		T.eq(float(got[1]), sign, "sentido do giro")
		T.eq(flags & 3, 3, "lento e enfurecido ficam")


func test_braziers_inside_room() -> void:
	var room := Rect2(Vector2(-11, -42), Vector2(22, 18))
	var pts := BlizzardRules.brazier_points(room, 0.0)
	T.eq(pts.size(), BlizzardRules.BRAZIERS, "quatro braseiros")
	for p in pts:
		T.ok(room.grow(-2.0).has_point(Vector2(p.x, p.z)), "longe das paredes")
	T.ok((pts[0] as Vector3).distance_to(pts[1]) > BlizzardRules.BRAZIER_R * 2.0, "os abrigos não se tocam")
	var d := BlizzardRules.default_room(Vector3(5, 0, 5))
	T.ok(d.has_point(Vector2(5, 5)) and d.size == BlizzardRules.ROOM, "sala padrão em volta do ponto")


func test_spikes_same_seed_same_points_inside_room() -> void:
	var room := Rect2(Vector2(-11, -42), Vector2(22, 18))
	var c := Vector3(0, 0, -36)
	var a := BlizzardRules.spike_points(77, c, room)
	var b := BlizzardRules.spike_points(77, c, room)
	T.eq(a.size(), BlizzardRules.SPIKES, "quantas estacas")
	for i in a.size():
		T.ok((a[i] as Vector3).is_equal_approx(b[i]), "mesma semente, mesmo ponto")
		T.ok(room.has_point(Vector2(a[i].x, a[i].z)), "dentro da sala")
	T.ok(not (a[0] as Vector3).is_equal_approx(BlizzardRules.spike_points(78, c, room)[0]), "outra semente, outro ponto")
	var free := BlizzardRules.clamp_to_room(Vector3(99, 0, 99), Rect2())
	T.ok(free.is_equal_approx(Vector3(99, 0, 99)), "sem sala, não mexe no ponto")


func test_relight_and_mask() -> void:
	var timers := [0.0, BlizzardRules.RELIGHT, 0.0, 3.0]
	T.eq(BlizzardRules.lit_mask(timers), 0b0101, "acesos: 0 e 2")
	timers = BlizzardRules.relight_step(timers, 3.5)
	T.eq(BlizzardRules.lit_mask(timers), 0b1101, "o 3 reacendeu")
	timers = BlizzardRules.relight_step(timers, BlizzardRules.RELIGHT)
	T.eq(BlizzardRules.lit_mask(timers), BlizzardRules.MASK_ALL, "todos de volta")


func test_cone_puts_out_braziers_in_its_way() -> void:
	var o := Vector3.ZERO
	var pts := [Vector3(0, 0, 6), Vector3(6, 0, 0), Vector3(0, 0, -6), Vector3(0, 0, 30)]
	T.eq(BlizzardRules.cone_braziers(o, 0.0, pts), 0b0001, "só o que está na frente e no alcance")
	T.eq(BlizzardRules.cone_braziers(o, deg_to_rad(90.0), pts), 0b0010, "girou: pega o do lado")


func test_shelter_needs_a_lit_brazier() -> void:
	var pts := [Vector3(0, 0, 0), Vector3(20, 0, 0)]
	T.ok(BlizzardRules.sheltered(Vector3(2, 0, 1), pts, 0b01), "perto do aceso")
	T.ok(not BlizzardRules.sheltered(Vector3(2, 0, 1), pts, 0b10), "perto do apagado não vale")
	T.ok(not BlizzardRules.sheltered(Vector3(10, 0, 0), pts, 0b11), "longe dos dois")
	T.ok(BlizzardRules.sheltered(Vector3(20, 5, BlizzardRules.BRAZIER_R - 0.1), pts, 0b11), "na beira do abrigo")


func test_exposure_grows_outside_and_thaws_inside() -> void:
	var e := 0.0
	e = BlizzardRules.exposure_step(e, BlizzardRules.EXPOSE_RAMP / 2.0, false)
	_near(e, 0.5, 0.0001, "metade do tempo, metade da exposição")
	e = BlizzardRules.exposure_step(e, 100.0, false)
	T.eq(e, 1.0, "para em 1")
	e = BlizzardRules.exposure_step(e, BlizzardRules.THAW / 2.0, true)
	_near(e, 0.5, 0.0001, "no abrigo descongela")
	e = BlizzardRules.exposure_step(e, 100.0, true)
	T.eq(e, 0.0, "para em 0")


func test_blizzard_hurts_more_with_exposure() -> void:
	T.ok(BlizzardRules.blizzard_damage(10.0, 1.0) > BlizzardRules.blizzard_damage(10.0, 0.3), "dano cresce")
	_near(BlizzardRules.blizzard_damage(10.0, 1.0), 10.0, 0.0001, "exposição cheia: o tique cheio")
	T.eq(BlizzardRules.blizzard_chill(0.05), 0.0, "no começo ainda não congela")
	T.ok(BlizzardRules.blizzard_chill(1.0) > BlizzardRules.blizzard_chill(0.4), "lentidão cresce")


func test_mask_survives_the_snapshot_with_the_attack() -> void:
	var flags := BossRules.pack_seed(3, 0xBEEF)
	flags = BlizzardRules.pack_mask(flags, 0b1010)
	T.eq(BlizzardRules.unpack_mask(flags), 0b1010, "braseiros")
	T.eq(BossRules.unpack_seed(flags), 0xBEEF, "a semente das estacas fica")
	T.eq(flags & 3, 3, "lento e enfurecido ficam")
	T.ok(flags < (1 << 24), "cabe no float32 do snapshot")
	T.eq(int(float(flags)), flags, "ida e volta pelo float")


func _near(a: float, b: float, eps: float, msg: String) -> void:
	T.ok(absf(a - b) <= eps, "%s (%f ~ %f)" % [msg, a, b])
