extends RefCounted
## ThrowRules: o arremesso de dinamite do Kobold (ponto de queda, arco e o ponto no snapshot de rede).


func test_target_inside_range() -> void:
	T.eq(ThrowRules.target(Vector3.ZERO, Vector3(0, 1, -5), 9.0), Vector3(0, 0, -5), "alvo perto: o próprio ponto, no chão de quem joga")


func test_clamps_to_range() -> void:
	T.eq(ThrowRules.target(Vector3.ZERO, Vector3(20, 0, 0), 9.0), Vector3(9, 0, 0), "longe: corta no alcance")


func test_flags_roundtrip_keeps_low_bits() -> void:
	var off := Vector3(-4.0, 0.0, 5.0)
	var f := ThrowRules.pack_flags(3, off)
	T.eq(f & 3, 3, "bits de lento/enfurecido ficam")
	T.ok(ThrowRules.unpack_offset(f).distance_to(off) < 0.2, "o ponto volta com erro < 20 cm")


func test_flags_offset_any_direction() -> void:
	for off in [Vector3(9, 0, 0), Vector3(0, 0, -9), Vector3(-6, 0, -6), Vector3(0.5, 0, 0.2)]:
		T.ok(ThrowRules.unpack_offset(ThrowRules.pack_flags(0, off)).distance_to(off) < 0.2, "direção %s" % str(off))


func test_flags_dist_caps() -> void:
	T.ok(absf(ThrowRules.unpack_offset(ThrowRules.pack_flags(0, Vector3(999, 0, 0))).length() - 63.75) < 0.01, "teto de 8 bits")


func test_flags_fit_float() -> void:
	T.ok(ThrowRules.pack_flags(3, Vector3(-63, 0, -1)) < (1 << 24), "cabe exato num float32 do snapshot")


func test_flags_without_throw_is_zero_dist() -> void:
	T.eq(ThrowRules.unpack_offset(3), Vector3.ZERO, "sem arremesso: deslocamento zero")


func test_arc_ends_and_peaks() -> void:
	var a := Vector3.ZERO
	var b := Vector3(0, 0, -8)
	T.eq(ThrowRules.arc(a, b, 0.0, 3.0), a, "sai da mão")
	T.eq(ThrowRules.arc(a, b, 1.0, 3.0), b, "cai no alvo")
	T.ok(absf(ThrowRules.arc(a, b, 0.5, 3.0).y - 3.0) < 0.001, "pico no meio")
