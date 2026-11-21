extends RefCounted
## AegisRules: integridade e absorção da Égide Cristalina (escudo de placas da espada com escudo), e a
## montagem das placas da barreira (AegisBarrier.layout / plate_size: a coroa de losangos, funções estáticas sem nó).


func _cfg() -> AegisConfig:
	return load("res://assets/vfx/aegis/aegis_config.tres")


func test_max_integrity_grows_with_level_and_defense() -> void:
	var c := _cfg()
	var base := AegisRules.max_integrity(c, 1, 0.0)
	T.eq(base, c.max_integrity, "nível 1 sem defesa: a base")
	T.ok(AegisRules.max_integrity(c, 10, 0.0) > base, "mais nível, mais integridade")
	T.ok(AegisRules.max_integrity(c, 1, 8.0) > base, "mais defesa, mais integridade")


func test_absorb_holds_damage_until_broken() -> void:
	var st := AegisRules.new_state(100.0)
	T.ok(AegisRules.active(st), "escudo novo protege")
	var r := AegisRules.absorb(st, 30.0)
	T.eq(r.absorbed, 30.0, "absorve o golpe inteiro")
	T.eq(r.overflow, 0.0, "nada passa para a vida")
	T.ok(not r.broke and is_equal_approx(AegisRules.fraction(st), 0.7), "integridade 70%")
	r = AegisRules.absorb(st, 90.0)
	T.eq(r.absorbed, 70.0, "segura só o que resta")
	T.eq(r.overflow, 20.0, "o excesso passa")
	T.ok(r.broke and st.broken and not AegisRules.active(st), "quebrou")
	r = AegisRules.absorb(st, 15.0)
	T.ok(r.absorbed == 0.0 and r.overflow == 15.0 and not r.broke, "quebrado não absorve nem quebra de novo")
	T.eq(st.absorbed, 100.0, "total absorvido = integridade máxima")


func test_absorb_ratio_lets_part_through() -> void:
	var st := AegisRules.new_state(100.0)
	var r := AegisRules.absorb(st, 40.0, 0.75)
	T.eq(r.absorbed, 30.0, "75% no escudo")
	T.eq(r.overflow, 10.0, "25% direto na vida")


func test_zero_or_negative_damage_is_ignored() -> void:
	var st := AegisRules.new_state(50.0)
	var r := AegisRules.absorb(st, 0.0)
	T.ok(r.absorbed == 0.0 and r.overflow == 0.0 and AegisRules.fraction(st) == 1.0, "golpe zero não muda nada")
	T.eq(AegisRules.fraction({}), 0.0, "sem estado: fração zero")
	T.ok(not AegisRules.active({}), "sem estado: não protege")


func test_cracks_grow_as_integrity_drops() -> void:
	T.eq(AegisRules.plate_crack(1.0, 0.9, 1.0), 0.0, "inteiro: nenhuma rachadura")
	T.eq(AegisRules.plate_crack(0.0, 0.0, 0.0), 1.0, "zerado: tudo rachado")
	var prev := 0.0
	for f in [0.9, 0.7, 0.5, 0.3, 0.1]:
		var c := AegisRules.plate_crack(f, 0.5, 0.0)
		T.ok(c > prev, "fração %.1f racha mais que a anterior (%.2f > %.2f)" % [f, c, prev])
		prev = c
	T.ok(AegisRules.plate_crack(0.6, 0.5, 1.0) > AegisRules.plate_crack(0.6, 0.5, 0.0), "perto do golpe racha mais")
	T.ok(AegisRules.plate_crack(0.6, 1.0, 0.0) > AegisRules.plate_crack(0.6, 0.0, 0.0), "o sorteio da placa muda a ordem")


func test_barrier_crown_layout() -> void:
	var c := _cfg()
	var pts := AegisBarrier.layout(c.plate_count, c.shield_width, c.shield_height, c.plate_rows)
	T.eq(pts.size(), c.plate_count, "uma posição por placa (fileiras completas)")
	var ok_order := true
	var ok_ring := true
	var top := 0.0
	for i in pts.size():
		var p: Dictionary = pts[i]
		if i > 0 and p.pos.y < pts[i - 1].pos.y:
			ok_order = false
		var horiz := Vector2(p.pos.x, p.pos.z).length()
		if horiz > c.shield_width + 0.01 or horiz < c.shield_width * 0.8:
			ok_ring = false
		top = maxf(top, p.pos.y + p.size.y * 0.5)
	T.ok(ok_order, "ordenadas de baixo para cima (ordem de formação)")
	T.ok(ok_ring, "todas na parede da coroa, no raio do escudo")
	T.ok(absf(top - c.shield_height) < 0.01 and pts[0].pos.y - pts[0].size.y * 0.5 < 0.01,
		"do chão (%.2f) ao topo (%.2f = altura do escudo)" % [pts[0].pos.y - pts[0].size.y * 0.5, top])


func test_crown_fits_a_party() -> void:
	# o herói e mais 4 (cápsulas de ~0,4 m de raio) lado a lado: um em volta do outro cabe num raio de ~1,3 m;
	# folga para ninguém encostar na parede
	var c := _cfg()
	T.ok(c.shield_width >= 2.5, "raio da coroa (%.1f m) cabe o herói e mais 4" % c.shield_width)
	T.ok(c.circle_radius >= c.shield_width, "o círculo do chão envolve a coroa")


func test_plate_size_tiles_the_ring() -> void:
	var c := _cfg()
	var s := AegisBarrier.plate_size(c.plate_count, c.shield_width, c.shield_height, c.plate_rows)
	var per := float(c.plate_count) / c.plate_rows
	T.ok(s.x * per >= TAU * c.shield_width and s.x * per < TAU * c.shield_width * 1.25, "as placas de uma fileira fecham a volta (com sobreposição)")
	T.ok(s.y > s.x, "losango mais alto que largo (%.2f x %.2f)" % [s.x, s.y])
	T.ok(AegisBarrier.plate_size(c.plate_count * 2, c.shield_width, c.shield_height, c.plate_rows).x < s.x, "mais placas, placas mais estreitas")
