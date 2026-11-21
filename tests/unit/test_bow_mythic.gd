extends RefCounted
## BowMythicRules (regras dos arcos míticos de endgame) e BowAura.kind_of, com as tabelas reais de data/balance.

const R := preload("res://scripts/player/bow_mythic_rules.gd")


func test_every_mythic_bow_has_a_mythic_fx() -> void:
	var bt := BalanceTables.load_dir("res://data/balance")
	var items := bt.get_table("items")
	var fxs := {}
	for id in ["abyss_bow", "dawn_bow", "dragon_bow", "wind_bow", "crescent_bow", "root_bow"]:
		T.ok(items.has(id), "%s existe" % id)
		var it: Dictionary = items[id]
		T.eq(str(it.rarity), "mythic", "%s é Mítico" % id)
		T.eq(str(it["class"]), "bow", "%s é arco" % id)
		T.ok(R.is_mythic_fx(str(it.fx)), "%s tem efeito mítico (%s)" % [id, it.fx])
		T.ok(bool(it.get("named", false)), "%s é nomeado (não cai pela janela de nível)" % id)
		T.ok(int(it.level) >= 48, "%s é de endgame" % id)
		fxs[str(it.fx)] = true
	T.eq(fxs.size(), R.FX.size(), "cada arco mítico tem um efeito diferente")
	T.eq(int(bt.get_table("rarity")["mythic"].rank), 5, "Mítico fica acima de Lendário")


func test_mythic_bows_outhit_legendary_bows() -> void:
	var items := BalanceTables.load_dir("res://data/balance").get_table("items")
	var best_legendary := 0
	for id: String in items:
		var it: Dictionary = items[id]
		if it.get("class", "") == "bow" and it.get("rarity", "") == "legendary" and ItemQuality.base(id) == id:
			best_legendary = maxi(best_legendary, int(it.get("damage", 0)))
	T.ok(best_legendary > 0, "há arco lendário para comparar (%d)" % best_legendary)
	for id in ["abyss_bow", "dawn_bow", "dragon_bow", "wind_bow", "crescent_bow", "root_bow"]:
		var dmg := int(items[id].get("damage", 0))
		T.ok(dmg > best_legendary, "%s (%d) bate mais que o melhor arco lendário (%d)" % [id, dmg, best_legendary])


func test_perfect_release_window() -> void:
	T.ok(R.perfect_release(10.0, 10.0), "soltar no instante da tensão máxima")
	T.ok(R.perfect_release(10.0, 10.0 + float(R.CRESCENT.window)), "soltar no fim da janela")
	T.ok(not R.perfect_release(10.0, 10.0 + float(R.CRESCENT.window) + 0.05), "depois da janela não é perfeita")
	T.ok(not R.perfect_release(-1.0, 3.0), "sem tensão máxima não é perfeita")
	T.ok(not R.perfect_release(10.0, 9.9), "antes da tensão máxima não é perfeita")


func test_solar_marks_fire_on_third() -> void:
	var a := R.add_mark([], 1.0)
	T.ok(not a.fire, "1ª marca não dispara")
	var b := R.add_mark(a.marks, 2.0)
	T.ok(not b.fire, "2ª marca não dispara")
	var c := R.add_mark(b.marks, 3.0)
	T.ok(c.fire, "3ª marca derruba a coluna de sol")
	T.eq(c.marks.size(), 0, "a coluna zera as marcas")


func test_solar_marks_expire() -> void:
	var a := R.add_mark([], 0.0)
	var b := R.add_mark(a.marks, 1.0)
	var c := R.add_mark(b.marks, 1.0 + float(R.SOLAR.window) + 0.5)
	T.ok(not c.fire, "marcas velhas expiram")
	T.eq(c.marks.size(), 1, "só a marca nova fica")


func test_rain_points_inside_radius() -> void:
	var pts := R.rain_points(Vector3(5, 2, -3), int(R.RAIN.arrows), float(R.RAIN.radius))
	T.eq(pts.size(), int(R.RAIN.arrows), "uma posição por flecha")
	T.ok((pts[0] as Vector3).is_equal_approx(Vector3(5, 2, -3)), "a primeira cai no centro")
	var far := 0.0
	for p: Vector3 in pts:
		T.ok(is_equal_approx(p.y, 2.0), "no plano do centro")
		far = maxf(far, Vector2(p.x - 5, p.z + 3).length())
	T.ok(far <= float(R.RAIN.radius) + 0.001 and far > float(R.RAIN.radius) * 0.8, "espalha até o raio")


func test_bounce_target_picks_nearest_unhit() -> void:
	var cands := [{"id": 1, "pos": Vector3(2, 0, 0)}, {"id": 2, "pos": Vector3(4, 0, 0)}, {"id": 3, "pos": Vector3(30, 0, 0)}]
	T.eq(R.bounce_target(Vector3.ZERO, cands, {}, 9.0), 0, "o mais perto")
	T.eq(R.bounce_target(Vector3.ZERO, cands, {1: true}, 9.0), 1, "pula quem já foi atingido")
	T.eq(R.bounce_target(Vector3.ZERO, cands, {1: true, 2: true}, 9.0), -1, "longe demais: nenhum")


func test_vortex_pull_shape() -> void:
	T.eq(R.vortex_pull(float(R.VORTEX.radius) + 0.1), 0.0, "fora da fenda não puxa")
	T.ok(R.vortex_pull(float(R.VORTEX.radius)) > R.vortex_pull(0.5), "puxa mais forte na borda")
	T.ok(R.vortex_pull(0.0) > 0.0, "no centro ainda segura")


func test_full_shot_survives_the_event() -> void:
	var d := Vector3(0.3, 0.1, -0.9).normalized()
	T.ok(R.decode_full(R.encode_dir(d, true)), "tiro tensionado chega como tensionado")
	T.ok(not R.decode_full(R.encode_dir(d, false)), "tiro comum chega como comum")
	T.ok(R.encode_dir(d, true).normalized().is_equal_approx(d), "a direção não muda")


func test_aura_kind_from_empty_name() -> void:
	T.eq(BowAura.kind_of("Aura_fire_3"), "fire", "tipo pelo nome do empty")
	T.eq(BowAura.kind_of("Aura_void"), "void", "sem número também")
	T.eq(BowAura.kind_of("Tip"), "", "outro empty não é aura")
	for k in BowAura.KINDS:
		T.ok(BowAura.KINDS[k].has("color"), "aura %s tem cor" % k)
