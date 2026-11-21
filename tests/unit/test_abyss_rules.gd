extends RefCounted
## AbyssRules: as habilidades do Arauto do Abismo (fases, escolha do golpe, Rajada, Garra, Zonas de Vazio,
## Miragem e Colapso).


func test_phases_by_health() -> void:
	T.eq(AbyssRules.phase(1.0), 1, "vida cheia: fase 1")
	T.eq(AbyssRules.phase(0.66), 1, "acima de 65%: fase 1")
	T.eq(AbyssRules.phase(0.64), 2, "abaixo de 65%: fase 2")
	T.eq(AbyssRules.phase(0.31), 2, "acima de 30%: fase 2")
	T.eq(AbyssRules.phase(0.29), 3, "abaixo de 30%: fase 3")


func test_phase1_basic_and_voids() -> void:
	T.eq(AbyssRules.attack(0, 1, 3.0, 4.5, 0), "swing", "perto: garra")
	T.eq(AbyssRules.attack(1, 1, 12.0, 4.5, 0), "volley", "longe: rajada")
	T.eq(AbyssRules.attack(3, 1, 3.0, 4.5, 0), "voids", "4º golpe: zonas de vazio")
	for n in 12:
		var k := AbyssRules.attack(n, 1, 12.0, 4.5, 0)
		T.ok(k != "mirage" and k != "collapse", "fase 1 não tem miragem nem colapso (%d: %s)" % [n, k])


func test_phase2_opens_with_mirage() -> void:
	T.eq(AbyssRules.attack(0, 2, 12.0, 4.5, 0), "mirage", "a fase 2 abre com a miragem")
	T.eq(AbyssRules.attack(6, 2, 12.0, 4.5, 0), "mirage", "e repete a cada 6 golpes")
	T.eq(AbyssRules.attack(6, 2, 12.0, 4.5, 1), "volley", "com cópias vivas não faz outra")
	T.eq(AbyssRules.attack(3, 2, 12.0, 4.5, 0), "voids", "as zonas continuam")
	for n in 12:
		T.ok(AbyssRules.attack(n, 2, 12.0, 4.5, 0) != "collapse", "fase 2 não tem colapso (%d)" % n)


func test_phase3_opens_with_collapse() -> void:
	T.eq(AbyssRules.attack(0, 3, 12.0, 4.5, 0), "collapse", "a fase 3 abre com o colapso")
	T.eq(AbyssRules.attack(6, 3, 3.0, 4.5, 2), "collapse", "e repete a cada 6 golpes, com ou sem cópias")
	T.eq(AbyssRules.attack(2, 3, 12.0, 4.5, 0), "mirage", "a miragem fica no meio do ciclo")
	T.eq(AbyssRules.attack(4, 3, 12.0, 4.5, 0), "voids", "e as zonas também")


func test_echoes_only_use_basic_attacks() -> void:
	T.eq(AbyssRules.echo_attack(3.0, 4.5), "swing", "cópia perto: garra")
	T.eq(AbyssRules.echo_attack(12.0, 4.5), "volley", "cópia longe: rajada")


func test_timings() -> void:
	for k in ["swing", "volley", "voids", "mirage", "collapse"]:
		T.ok(AbyssRules.hit_time(k) > 0.5, "%s: há tempo para ver o aviso" % k)
		T.ok(AbyssRules.duration(k) > AbyssRules.hit_time(k), "%s: o golpe acaba depois de acertar" % k)
	T.ok(AbyssRules.hit_time("collapse") > AbyssRules.PULL_T + 1.0, "colapso: sobra mais de 1 s depois do puxão para sair")


func test_volley_fan() -> void:
	T.eq(AbyssRules.volley_shots(1), AbyssRules.VOLLEY_SHOTS, "fase 1: leque menor")
	T.eq(AbyssRules.volley_shots(3), AbyssRules.VOLLEY_SHOTS_FURY, "fases 2 e 3: leque maior")
	var dirs := AbyssRules.volley_dirs(Vector3(0, 5, 3), 5)
	T.eq(dirs.size(), 5, "cinco projéteis")
	T.ok((dirs[2] as Vector3).distance_to(Vector3(0, 0, 1)) < 0.001, "o do meio vai reto no alvo, no plano")
	var side := rad_to_deg((dirs[0] as Vector3).angle_to(dirs[4]))
	_near(side, AbyssRules.VOLLEY_FAN * 4.0, 0.01, "o leque abre o ângulo todo")
	for d in dirs:
		_near((d as Vector3).length(), 1.0, 0.001, "direção normalizada")


func test_claw_arc() -> void:
	var o := Vector3(2, 0, 2)
	var f := Vector3(0, 0, 1)
	T.ok(AbyssRules.in_claw(o, f, o + Vector3(0, 0, 4)), "na frente: pega")
	T.ok(AbyssRules.in_claw(o, f, o + Vector3(3, 0, 2.5)), "na diagonal da frente: pega")
	T.ok(not AbyssRules.in_claw(o, f, o + Vector3(0, 0, -3)), "atrás: escapa")
	T.ok(not AbyssRules.in_claw(o, f, o + Vector3(4, 0, -0.5)), "de lado, um pouco atrás: escapa")
	T.ok(not AbyssRules.in_claw(o, f, o + Vector3(0, 0, AbyssRules.CLAW_R + 0.5)), "além do alcance: escapa")
	T.ok(AbyssRules.in_claw(o, f, o + Vector3(0, 0, -0.4)), "colado nele: pega")


func test_void_points_by_seed_inside_room() -> void:
	var room := Rect2(-11, -9, 22, 18)
	var c := Vector3(0, 1, 0)
	var a := AbyssRules.void_points(77, c, room)
	var b := AbyssRules.void_points(77, c, room)
	T.eq(a.size(), AbyssRules.VOIDS, "quantidade")
	for i in a.size():
		T.ok((a[i] as Vector3).distance_to(b[i]) < 0.0001, "mesma semente, mesmos pontos")
		T.ok(room.has_point(Vector2(a[i].x, a[i].z)), "dentro da sala")
		_near(a[i].y, 1.0, 0.0001, "na altura do centro")
	var other := AbyssRules.void_points(78, c, room)
	T.ok((a[0] as Vector3).distance_to(other[0]) > 0.01, "outra semente, outros pontos")
	var far := AbyssRules.void_points(5, Vector3(10, 0, 8), room)
	for p in far:
		T.ok(room.has_point(Vector2(p.x, p.z)), "perto do canto continua dentro da sala")


func test_void_zone_grows() -> void:
	_near(AbyssRules.void_radius(0.0), AbyssRules.VOID_R0, 0.001, "nasce pequena")
	T.ok(AbyssRules.void_radius(5.0) > AbyssRules.void_radius(1.0), "cresce com o tempo")
	_near(AbyssRules.void_radius(AbyssRules.VOID_GROW + 5.0), AbyssRules.VOID_R1, 0.001, "para no raio máximo")
	T.ok(AbyssRules.VOID_LIFE > AbyssRules.VOID_GROW, "fica um tempo no tamanho máximo")


func test_mirage_points() -> void:
	var room := Rect2(-11, -9, 22, 18)
	T.eq(AbyssRules.echo_count(2), 2, "fase 2: duas cópias")
	T.eq(AbyssRules.echo_count(3), 3, "fase 3: três cópias")
	var pts := AbyssRules.mirage_points(9, Vector3.ZERO, room, 3)
	T.eq(pts.size(), 4, "um ponto para ele e um para cada cópia")
	for i in pts.size():
		T.ok(room.has_point(Vector2(pts[i].x, pts[i].z)), "dentro da sala")
		for j in range(i + 1, pts.size()):
			T.ok((pts[i] as Vector3).distance_to(pts[j]) > 4.0, "longe um do outro")
	var again := AbyssRules.mirage_points(9, Vector3.ZERO, room, 3)
	T.ok((pts[0] as Vector3).distance_to(again[0]) < 0.0001, "mesma semente, mesma roda")
	var spun := AbyssRules.mirage_points(10, Vector3.ZERO, room, 3)
	T.ok((pts[0] as Vector3).distance_to(spun[0]) > 0.01, "outra semente gira a roda")


func test_clamp_to_room() -> void:
	var room := Rect2(0, 0, 10, 10)
	T.ok(AbyssRules.clamp_to_room(Vector3(-5, 2, 30), room, 1.0).distance_to(Vector3(1, 2, 9)) < 0.0001, "traz para dentro")
	T.ok(AbyssRules.clamp_to_room(Vector3(-5, 2, 30), Rect2(), 1.0).distance_to(Vector3(-5, 2, 30)) < 0.0001,
		"sem sala não muda")


func test_collapse_opens_from_inside_with_safe_gaps() -> void:
	var prev_r := -1.0
	var prev_t := -1.0
	for i in AbyssRules.COLLAPSE_RINGS:
		var q := AbyssRules.collapse_ring(i)
		T.ok(float(q.r0) > prev_r, "faixa %d começa depois da anterior" % i)
		T.ok(float(q.t) > prev_t, "e estoura mais tarde")
		if i > 0:
			_near(float(q.r0) - prev_r, AbyssRules.COLLAPSE_GAP, 0.001, "vão seguro antes da faixa %d" % i)
		prev_r = float(q.r1)
		prev_t = float(q.t)
	T.ok(AbyssRules.in_collapse_ring(1.0, 0), "o miolo pega quem ficou no centro")
	T.ok(not AbyssRules.collapse_safe(AbyssRules.PULL_STOP), "onde o puxão deixa o jogador não é seguro")
	T.ok(AbyssRules.collapse_safe(AbyssRules.COLLAPSE_DISC + AbyssRules.COLLAPSE_GAP * 0.5), "o primeiro vão é seguro")
	var r1 := AbyssRules.collapse_ring(1)
	T.ok(not AbyssRules.collapse_safe((float(r1.r0) + float(r1.r1)) / 2.0), "no meio de um anel não é")


func test_pull_drags_to_center_and_stops() -> void:
	var c := Vector3(0, 0, 0)
	var p := Vector3(10, 1, 0)
	var q := AbyssRules.pull_step(p, c, 0.5)
	_near(q.x, 10.0 - AbyssRules.PULL_SPEED * 0.5, 0.001, "anda para o centro")
	_near(q.y, 1.0, 0.0001, "sem mexer na altura")
	for i in 100:
		q = AbyssRules.pull_step(q, c, 0.1)
	_near(Vector2(q.x, q.z).length(), AbyssRules.PULL_STOP, 0.001, "para a PULL_STOP m dele")
	var near := Vector3(1, 0, 0)
	T.ok(AbyssRules.pull_step(near, c, 0.5).distance_to(near) < 0.0001, "quem já está colado não é puxado")


func _near(a: float, b: float, tol: float, msg: String) -> void:
	T.ok(absf(a - b) <= tol, "%s (%s ~ %s)" % [msg, a, b])
