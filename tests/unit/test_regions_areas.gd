extends RefCounted
## Regiões nomeadas dos mapas: forma e posição nos nós MapRegion das cenas (MapData.areas), números no
## data/balance/regions.json (Regions.area_info). Consultas puras em Regions.

const REGIONS_JSON := "res://data/balance/regions.json"


func _area(id: String, center: Vector3, shape: int, size := Vector2.ZERO, radius := 0.0, rot := 0.0) -> Dictionary:
	return {"id": id, "map": "vila", "center": center, "shape": shape, "size": size, "radius": radius, "rot": rot}


func _table() -> Dictionary:
	return BalanceTables.decode(JSON.parse_string(FileAccess.get_file_as_string(REGIONS_JSON)))


func test_rect_and_disc_contain() -> void:
	var r := _area("r", Vector3.ZERO, MapRegion.RECT, Vector2(10, 4))
	T.ok(Regions.area_has(r, Vector3(4.9, 7, 1.9)), "ponto dentro do retângulo (altura não conta)")
	T.ok(not Regions.area_has(r, Vector3(5.1, 0, 0)), "fora pela largura")
	T.ok(not Regions.area_has(r, Vector3(0, 0, 2.1)), "fora pela profundidade")
	var d := _area("d", Vector3(10, 0, 10), MapRegion.DISC, Vector2.ZERO, 5.0)
	T.ok(Regions.area_has(d, Vector3(13, 0, 13.9)), "dentro do disco (4,95 m)")
	T.ok(not Regions.area_has(d, Vector3(14, 0, 14)), "fora do disco (5,66 m)")


func test_rotated_rect() -> void:
	var r := _area("r", Vector3.ZERO, MapRegion.RECT, Vector2(10, 2), 0.0, PI / 2.0)
	T.ok(Regions.area_has(r, Vector3(0, 0, 4)), "girado 90°: o comprimento fica em Z")
	T.ok(not Regions.area_has(r, Vector3(4, 0, 0)), "girado 90°: a largura em X é 2")


func test_smallest_wins() -> void:
	var big := _area("ameias", Vector3(0, 0, -32), MapRegion.RECT, Vector2(100, 24))
	var small := _area("cume", Vector3(0, 0, -45), MapRegion.DISC, Vector2.ZERO, 12.0)
	T.eq(Regions.pick([big, small], Vector3(0, 0, -40)), "cume", "nas duas: a menor ganha")
	T.eq(Regions.pick([small, big], Vector3(0, 0, -40)), "cume", "a ordem não importa")
	T.eq(Regions.pick([big, small], Vector3(30, 0, -30)), "ameias", "só na grande")
	T.eq(Regions.pick([big, small], Vector3(0, 0, 40)), "", "fora de todas")


func test_info_defaults() -> void:
	var i := Regions.area_info({}, "sem_dado")
	T.eq(i.name, "sem_dado", "nome padrão = id")
	T.eq(i.density, 1.0, "densidade padrão 1")
	T.eq(i.level_min, 0, "sem faixa")
	T.ok(i.show_on_map, "aparece no mapa por padrão")
	var j := Regions.area_info({"t": {"name": "Toca", "level_min": 5}}, "t")
	T.eq(j.level_max, 5, "sem level_max: fica o level_min")


func test_label() -> void:
	T.eq(Regions.area_label({"t": {"name": "Toca", "level_min": 5, "level_max": 9}}, "t"), "Toca · Nv 5–9", "faixa")
	T.eq(Regions.area_label({"t": {"name": "Ninho", "level_min": 20, "level_max": 20}}, "t"), "Ninho · Nv 20", "nível único")
	T.eq(Regions.area_label({}, "x"), "x", "sem dado: só o nome")


func test_spawn_range() -> void:
	var t := {"toca_goblins": {"name": "Toca", "level_min": 5, "level_max": 9}}
	T.eq(Regions.spawn_range(t, "toca_goblins", 5, 8), Vector2i(5, 8), "nível do ponto manda")
	T.eq(Regions.spawn_range(t, "toca_goblins", 0, 0), Vector2i(5, 9), "nível 0: faixa da região")
	T.eq(Regions.spawn_range(t, "", 0, 0), Vector2i(0, 0), "fora de região: sem nível (ref_level)")
	T.eq(Regions.spawn_range(t, "sem_dado", 0, 0), Vector2i(0, 0), "região sem faixa: sem nível")


func test_spawn_count() -> void:
	var t := {"a": {"name": "A", "density": 1.5}, "b": {"name": "B", "density": 0.0}}
	T.eq(Regions.spawn_count(t, "a", 2), 3, "densidade 1,5")
	T.eq(Regions.spawn_count(t, "b", 4), 0, "densidade 0 esvazia")
	T.eq(Regions.spawn_count(t, "", 4), 4, "fora de região: igual")


func test_json_and_scenes_agree() -> void:
	var t := _table()
	T.eq(t.size(), 33, "21 regiões dos mapas + 12 salas das 4 dungeons no regions.json")
	var seen := {}
	for a in MapData.all_areas():
		seen[a.id] = true
		T.ok(t.has(a.id), "região %s da cena %s existe no regions.json" % [a.id, a.map])
	for id in t:
		T.ok(seen.has(id), "região %s do regions.json tem nó MapRegion" % id)
		T.ok(int(t[id].level_min) > 0 and int(t[id].level_max) >= int(t[id].level_min), "%s com faixa válida" % id)


func test_area_at_on_real_maps() -> void:
	T.eq(Regions.area_at(Vector3(86, 0, 0)), "toca_goblins", "o acampamento goblin")
	T.eq(Regions.area_at(Vector3(0, 0, -6)), "campos_norte", "campos ao norte da vila")
	T.eq(Regions.area_at(Vector3(0, 0, 72)), "", "a vila não é região de monstro")
	T.eq(Regions.area_at(Vector3(-28, 0, -52)), "forte_brutos", "o forte perto do cemitério")
	T.eq(Regions.area_at(Regions.at("pico", Vector3(0, 0, -45))), "cume_maldito", "o cume dentro das ameias")
	T.eq(Regions.area_at(Regions.at("bosque", Vector3(-26, 0, -36))), "ninho_rainha", "a Slime Rainha no ninho")
	T.ok(Regions.area_center("toca_goblins").distance_to(Vector3(86, 0, 0)) < 1.0, "centro da toca")
	T.eq(Regions.area_center("nao_existe"), Vector3.INF, "região sem nó")


## Missão que cita região: o objetivo leva o nome dela e o rastreador aponta para o centro da região.
func test_quest_objective_and_destination() -> void:
	var t := _table()
	var q := {"objective": "Batedores goblins derrotados", "region": "toca_goblins", "where": [0, 0]}
	T.eq(StoryRules.objective(q, t), "Batedores goblins derrotados · Toca dos Goblins", "nome da região no objetivo")
	T.eq(StoryRules.objective({"objective": "Ache o Kael"}, t), "Ache o Kael", "sem região: igual")
	var qt := {"m": {"type": "kill", "target": "goblin", "count": 2, "giver_id": "elder", "region": "toca_goblins", "where": [0, 0]}}
	var st := {"m": {"state": "active", "progress": 0}}
	var d := StoryRules.destination(qt, st, "m", {})
	T.ok(d.has("pos") and (d.pos as Vector2).distance_to(Vector2(86, 0)) < 1.0, "rastreador no centro da toca")
	qt.m.region = "nao_existe"
	T.eq(StoryRules.destination(qt, st, "m", {}).pos, Vector2(0, 0), "região sem nó: cai no where")


## Regiões não se sobrepõem (um monstro na borda ficaria com a região "errada" e a missão dela não contaria),
## a não ser os encaixes de propósito: o Cume Maldito dentro das Ameias do Lich.
func test_regions_do_not_overlap() -> void:
	const NESTED := [["ameias_lich", "cume_maldito"]]
	for map_id in Regions.ALL:
		var areas := MapData.areas(map_id)
		var o: Vector3 = Regions.origin(map_id)
		var h := float(Regions.DATA[map_id].half)
		var bad := {}
		for x in range(int(-h), int(h) + 1, 2):
			for z in range(int(-h), int(h) + 1, 2):
				var p := o + Vector3(x + 0.5, 0, z + 0.5)   # fora das bordas exatas (retângulos vizinhos dividem a borda)
				var ids: Array = []
				for a in areas:
					if Regions.area_has(a, p) and not a.id in ids:
						ids.append(a.id)
				ids.sort()
				if ids.size() > 1 and not ids in NESTED:
					bad[str(ids)] = true
		T.ok(bad.is_empty(), "%s: regiões que se sobrepõem %s" % [map_id, str(bad.keys())])
