extends RefCounted
## Biomas dos mapas (BiomeRules): cada mapa de viagem com chão, serra e clima próprios; o Vale fica como era.


func _w(rain: float, snow: float, cover: float, wet: float, cloud: float) -> Dictionary:
	return {"rain": rain, "snow": snow, "cover": cover, "wet": wet, "cloud": cloud, "wind": 0.2}


func test_vale_keeps_the_default() -> void:
	var v := BiomeRules.of("vila")
	T.eq(v.grass, BiomeRules.VALE.grass, "o Vale continua com o capim de sempre")
	T.ok(not BiomeRules.has_sky("vila"), "o Vale não troca o céu")
	var s := _w(0.7, 0.0, 0.0, 0.5, 0.8)
	T.eq(BiomeRules.weather("vila", s), s, "o clima do Vale passa sem mudar")


func test_each_travel_map_has_its_own_look() -> void:
	var seen := {}
	for id in ["bosque", "mina", "pico"]:
		var b := BiomeRules.of(id)
		T.ok(BiomeRules.has_sky(id), "%s tem céu e névoa próprios" % id)
		T.ok(b.grass != BiomeRules.VALE.grass, "%s tem chão diferente do Vale" % id)
		T.ok(not seen.has(str(b.grass)), "%s tem chão diferente dos outros mapas" % id)
		seen[str(b.grass)] = true
		for m in (b.plants as Dictionary).values():
			T.ok(ResourceLoader.exists(MapProp.model_path(m)), "planta %s de %s existe" % [m, id])
		for m in (b.ring_trees as Dictionary).keys():
			T.ok(ResourceLoader.exists(MapProp.model_path(m)), "árvore da serra %s de %s existe" % [m, id])


func test_dungeons_use_the_outside_map() -> void:
	T.eq(BiomeRules.of("dg_mina").grass, BiomeRules.of("mina").grass, "a dungeon da geleira usa o bioma da geleira")


func test_weather_by_biome() -> void:
	var rainy := _w(0.8, 0.0, 0.0, 0.6, 0.9)
	var snowy := _w(0.0, 0.7, 0.9, 0.0, 0.8)
	var clear := _w(0.0, 0.0, 0.0, 0.0, 0.0)
	var g := BiomeRules.weather("mina", rainy)
	T.eq(g.rain, 0.0, "na geleira não chove")
	T.eq(g.cover, 1.0, "na geleira o chão fica coberto de neve")
	T.ok(BiomeRules.weather("mina", clear).snow >= 0.45, "na geleira sempre neva")
	var v := BiomeRules.weather("pico", snowy)
	T.eq(v.snow, 0.0, "no vulcão não neva")
	T.eq(v.cover, 0.0, "nem acumula neve")
	T.eq(BiomeRules.weather("pico", rainy).rain, 0.0, "nem chove")
	var p := BiomeRules.weather("bosque", snowy)
	T.eq(p.snow, 0.0, "no pântano não neva")
	T.ok(BiomeRules.weather("bosque", clear).wet >= 0.55, "o pântano está sempre molhado")
