extends RefCounted
## MapRules: conversão mundo ↔ mapa de cada região e o filtro de quem aparece no mapa (só o grupo).


func test_village_corners_and_center() -> void:
	T.eq(MapRules.to_uv("vila", Vector3(0, 0, 0)), Vector2(0.5, 0.5), "centro do vale")
	T.eq(MapRules.to_uv("vila", Vector3(-125, 0, -125)), Vector2(0, 0), "canto noroeste")
	T.eq(MapRules.to_uv("vila", Vector3(125, 9, 125)), Vector2(1, 1), "canto sudeste (altura não conta)")
	T.ok(MapRules.to_uv("vila", Vector3(0, 0, -100)).y < 0.5, "as ruínas (norte) ficam em cima")


func test_round_trip_in_far_region() -> void:
	var p := Regions.at("mina", Vector3(12, 0, -30))
	var uv := MapRules.to_uv("mina", p)
	T.ok(uv.x > 0.0 and uv.x < 1.0 and uv.y > 0.0 and uv.y < 1.0, "dentro do mapa da mina")
	T.ok(MapRules.from_uv("mina", uv).distance_to(p) < 0.01, "ida e volta")


func test_places_include_coach_for_every_region() -> void:
	for id in Regions.ORDER:
		var names: Array = MapRules.places(id).map(func(p: Array) -> String: return p[0])
		T.ok("Carruagem da Guilda" in names, "carruagem no mapa %s" % id)
		for p in MapRules.places(id):
			T.eq(Regions.region_at(p[1]), id, "%s fica dentro de %s" % [p[0], id])


func test_only_party_members_are_shown() -> void:
	T.eq(MapRules.shown_players([1, 2, 3, 4], [1, 3], 1), [3], "só o grupo, sem eu")
	T.eq(MapRules.shown_players([1, 2], [], 1), [], "sem grupo ninguém aparece")


func test_heading_north_is_zero() -> void:
	T.ok(absf(MapRules.heading(Vector3(0, 0, -1))) < 0.001, "norte = 0")
	T.ok(absf(MapRules.heading(Vector3(1, 0, 0)) - PI / 2) < 0.001, "leste = 90°")


## Os lugares do mapa e a carruagem vêm dos landmarks da cena do mapa (MapLandmark): mover o nó no editor muda o
## minimapa e a viagem. Os valores abaixo são os de antes da conversão para cenas.
func test_places_come_from_landmarks() -> void:
	var at := {}
	for p in MapRules.places("vila"):
		at[p[0]] = p[1]
	T.eq(at.get("Acampamento Goblin"), MapData.landmark("vila", "camp"), "acampamento pelo landmark camp")
	T.eq(at.get("Acampamento Goblin"), Vector3(62, 0, 0), "acampamento no lugar de sempre")
	T.eq(at.get("Ruínas"), Vector3(0, 0, -100), "ruínas")
	T.eq(at.get("Horta"), Vector3(0, 0, 33), "Horta")
	T.eq(at.get("Pomar"), Vector3(20, 0, 33), "pomar")
	T.eq(at.get("Ninho de Slimes"), Vector3(-36, 0, 36), "ninho")
	T.eq(at.get("Portal da Horda"), MapData.landmark("vila", "portal"), "o portal da Horda pelo landmark portal")
	T.eq(at.get("Portal da Horda"), Vector3(-8, 0, -9.5), "portal da Horda na frente da vila")


func test_coach_and_arrive_from_landmarks() -> void:
	T.eq(Regions.coach_point("vila"), MapData.landmark("vila", "coach"), "carruagem do vale pelo landmark")
	T.eq(Regions.coach_point("vila"), Vector3(-7.5, 0, -18.0), "carruagem do vale no lugar de sempre")
	T.eq(Regions.arrive_point("mina"), Vector3(800, 0.3, 52.0), "chegada na Mina no lugar de sempre")
	T.ok(not Regions.DATA.vila.has("coach") and not Regions.DATA.mina.has("arrive"),
		"carruagem e chegada saíram do Regions.DATA (só a cena manda)")


## Atlas do mapa-mundi: o vale no meio, as outras regiões a leste/sul, sem sobrepor, e cada ponto do mundo
## cai dentro do retângulo da região dele.
func test_atlas_layout() -> void:
	T.eq(MapRules.atlas_center("vila"), Vector2.ZERO, "vale no centro do atlas")
	T.ok(MapRules.atlas_center("bosque").y > 0.0 and absf(MapRules.atlas_center("bosque").x) < 0.01, "bosque ao sul")
	T.ok(MapRules.atlas_center("mina").x > 0.0 and absf(MapRules.atlas_center("mina").y) < 0.01, "mina a leste")
	for a in Regions.ORDER:
		T.ok(MapRules.atlas_bounds().encloses(MapRules.atlas_rect(a)), "%s dentro do atlas" % a)
		for b in Regions.ORDER:
			if a < b:
				T.ok(MapRules.atlas_center(a).distance_to(MapRules.atlas_center(b)) > MapRules.radius(a) + MapRules.radius(b),
					"%s e %s não se sobrepõem" % [a, b])
		T.eq(MapRules.atlas_region_at(MapRules.to_atlas(Regions.coach_point(a))), a, "carruagem de %s no círculo dela" % a)
		var h: float = Regions.DATA[a].half
		T.eq(MapRules.atlas_region_at(MapRules.to_atlas(Regions.at(a, Vector3(h, 0, -h)))), a, "canto de %s dentro do círculo" % a)
		T.ok(MapRules.capture_rect(a).encloses(MapRules.rect(a).grow(MapRules.MINI_RADIUS)), "a foto de %s cobre o minimapa na borda" % a)
	T.eq(MapRules.to_atlas(Regions.at("mina", Vector3(5, 3, -7))), MapRules.atlas_center("mina") + Vector2(5, -7), "ponto da mina")


func test_coach_exits_follow_rank() -> void:
	var ex := MapRules.exits("vila", "C")
	T.eq(ex.map(func(e: Array) -> String: return e[0]), ["bosque", "mina", "pico"], "saídas do vale")
	T.eq(ex.map(func(e: Array) -> bool: return e[1]), [true, false, false], "rank C só libera o bosque")
	T.ok(not ("mina" in MapRules.exits("mina", "S").map(func(e: Array) -> String: return e[0])), "sem saída para si mesma")


func test_zoom_keeps_point_under_mouse() -> void:
	var anchor := Vector2(30, -12)
	var off := Vector2(200, -50)
	var c := MapRules.zoom_center(anchor, off, 4.0)
	T.ok((c + off / 4.0).distance_to(anchor) < 0.001, "o ponto fica embaixo do mouse")


## Arrastar o atlas não leva para o mar: o ponto volta para o mapa mais perto.
func test_clamp_to_land() -> void:
	T.eq(MapRules.clamp_to_land(Vector2(10, -20)), Vector2(10, -20), "dentro do vale fica")
	var far := MapRules.clamp_to_land(Vector2(-900, 0))
	T.eq(MapRules.atlas_region_at(far), "vila", "a oeste de tudo volta para o vale")
	T.ok(absf(far.length() - MapRules.radius("vila")) < 0.1, "na borda do círculo")
	T.eq(MapRules.atlas_region_at(Vector2(2000, 2000).lerp(Vector2.ZERO, 0.0)), "", "longe é mar")
	T.eq(MapRules.atlas_region_at(MapRules.clamp_to_land(Vector2(2000, 2000))), "pico", "a sudeste volta para o Pico")
