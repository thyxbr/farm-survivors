extends RefCounted
## BossRules: as habilidades de chefe da Mãe-Verme (escolha do golpe, Onda de Cristais, Desmoronamento, Poças de
## Ácido e a Fúria).


func test_special_on_second_attack_alternates() -> void:
	T.eq(BossRules.worm_attack(1, 0, 3.0, 5.0), "quake", "2º golpe da subida: especial (onda primeiro)")
	T.eq(BossRules.worm_attack(1, 1, 3.0, 5.0), "rockfall", "na subida seguinte: desmoronamento")
	T.eq(BossRules.worm_attack(1, 2, 20.0, 5.0), "quake", "alterna, perto ou longe")


func test_plain_attacks_by_distance() -> void:
	T.eq(BossRules.worm_attack(0, 0, 3.0, 5.0), "slam", "perto: mordida em área")
	T.eq(BossRules.worm_attack(2, 0, 3.0, 5.0), "slam", "perto, fora do especial: mordida")
	T.eq(BossRules.worm_attack(0, 0, 12.0, 5.0), "shoot", "longe: cuspe")
	T.eq(BossRules.worm_attack(2, 0, 12.0, 5.0), "acid_rain", "longe, outra vez: poças de ácido")


func test_quake_rings_grow_in_time_and_size() -> void:
	T.eq(BossRules.QUAKE_RINGS, 4, "quatro anéis")
	for i in BossRules.QUAKE_RINGS - 1:
		var a := BossRules.quake_ring(i)
		var b := BossRules.quake_ring(i + 1)
		T.ok(b.r > a.r and b.t > a.t, "anel %d: mais longe e mais tarde que o %d" % [i + 1, i])
	T.ok(BossRules.quake_ring(0).t >= 0.9, "o primeiro anel dá tempo de ler o aviso")


func test_quake_gap_is_safe() -> void:
	# entre dois anéis sobra um vão onde nenhum acerta
	var a := BossRules.quake_ring(0)
	var b := BossRules.quake_ring(1)
	var gap: float = (a.r + b.r) / 2.0
	for i in BossRules.QUAKE_RINGS:
		T.ok(not BossRules.in_quake_ring(gap, i), "o vão (%.1f m) está fora do anel %d" % [gap, i])
	T.ok(BossRules.in_quake_ring(a.r, 0), "em cima do anel: acerta")


func test_rockfall_points_deterministic_and_near() -> void:
	var c := Vector3(10, 0, -5)
	var p1 := BossRules.rockfall_points(1234, c, 12.0, 6)
	var p2 := BossRules.rockfall_points(1234, c, 12.0, 6)
	T.eq(p1.size(), 6, "seis pedras sorteadas")
	T.eq(p1, p2, "mesma semente: mesmos pontos (servidor e cliente)")
	T.ok(p1 != BossRules.rockfall_points(99, c, 12.0, 6), "outra semente: outros pontos")
	for p in p1:
		T.ok(Vector2(p.x - c.x, p.z - c.z).length() <= 12.0 and p.y == c.y, "dentro do raio, na altura do chefe")


func test_acid_points_spread_around_target() -> void:
	var o := Vector3.ZERO
	var t := Vector3(0, 0, -10)
	var pts := BossRules.acid_points(o, t)
	T.eq(pts.size(), 3, "três bolhas")
	T.eq(pts[0], t, "a primeira cai no alvo")
	T.ok(pts[1].distance_to(t) > 2.0 and pts[2].distance_to(t) > 2.0, "as outras abrem para os lados")
	T.ok(pts[1].distance_to(pts[2]) > 3.0, "uma de cada lado")


func test_fury_dives() -> void:
	T.eq(BossRules.FURY_DIVES, 3, "três mergulhos seguidos na fúria")
	T.eq(BossRules.surface_attacks(3, 2), 0, "com mergulhos de fúria pendentes: mergulha logo")
	T.eq(BossRules.surface_attacks(3, 0), 3, "sem fúria pendente: o normal")


func test_seed_fits_flags() -> void:
	var f := BossRules.pack_seed(3, 65535)
	T.eq(f & 3, 3, "bits de lento/enfurecido ficam")
	T.eq(BossRules.unpack_seed(f), 65535, "semente volta inteira")
	T.ok(f < (1 << 24), "cabe no float32 do snapshot")


## Poças e Mergulho miram quem está mais longe dela (dentro do fosso): a linha de trás também é alvo.
func test_farthest_target() -> void:
	var o := Vector3.ZERO
	var pts := [Vector3(2, 0, 0), Vector3(0, 5, 14), Vector3(-9, 0, 0)]
	T.eq(BossRules.farthest_index(o, pts), 1, "o mais distante no plano (altura não conta)")
	T.eq(BossRules.farthest_index(o, [Vector3(3, 0, 0)]), 0, "sozinho: ele mesmo")
	T.eq(BossRules.farthest_index(o, []), -1, "ninguém: -1")
