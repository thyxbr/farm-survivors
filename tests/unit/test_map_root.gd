extends RefCounted
## MapRoot: o que a raiz de um mapa lê das peças para montar o chão (formas pintadas, morros) e o capim (áreas
## sem capim e de capim ralo, pegadas dos objetos). Igual no editor e no jogo, sem autoload.

const FIXTURE := "res://tests/unit/fixtures/map_root_fixture.tscn"


func _root() -> MapRoot:
	return (load(FIXTURE) as PackedScene).instantiate() as MapRoot


func test_paints_and_mountains() -> void:
	var r := _root()
	var paints := r.paint_data()
	T.eq(paints.size(), 2, "duas formas pintadas")
	T.eq(paints[0], {"center": Vector3(3, 0, 4), "disc": false, "size": Vector2(6, 2), "radius": 4.0,
		"color": Color(0.5, 0.4, 0.3), "soft": 0.5, "grass": 0.0}, "retângulo dentro de um grupo deslocado")
	T.eq(paints[1].disc, true, "disco")
	T.eq(r.mountain_data(), [Vector4(-20, 30, 12, 9)], "morro: x, z, raio, altura")
	r.free()


func test_grass_lists() -> void:
	var r := _root()
	var g := r.grass_lists()
	var oak: Array = g.keep_out.filter(func(e: Array) -> bool: return e[0] == Vector2(10, 0))
	T.eq(oak.size(), 1, "pegada do carvalho")
	T.ok(oak.size() == 1 and is_equal_approx(oak[0][1], 0.55), "raio do tronco (0,4) + folga (0,15)")
	T.ok([Vector2(0, -8), 5.0] in g.keep_out, "área sem capim")
	T.eq(g.sparse, [[Vector2(7, 7), 3.0]], "área de capim ralo")
	T.eq(g.keep_out.size(), 2, "cerca com no_grass desligado não entra")
	r.free()
