extends RefCounted
## ToonLook: quem decide se o estilo e o contorno ficam ligados (linha de comando x opção do menu x teste)
## e a casca de contorno juntada por grupo de peças.


func _args(a: Array) -> PackedStringArray:
	return PackedStringArray(a)


func test_style_follows_menu_option() -> void:
	T.ok(ToonLook.decide_style(_args([]), false, true), "opção ligada, com janela: liga")
	T.ok(not ToonLook.decide_style(_args([]), false, false), "opção desligada: desliga")


func test_notoon_beats_menu_option() -> void:
	T.ok(not ToonLook.decide_style(_args(["--notoon"]), false, true), "--notoon vence a opção ligada")
	T.ok(not ToonLook.decide_style(_args(["--notoon", "--smoketest"]), true, true), "--notoon vence até nos testes")


func test_dedicated_server_never_converts() -> void:
	T.ok(not ToonLook.decide_style(_args(["--server"]), true, true), "sem janela e fora de teste: desligado")


func test_tests_ignore_menu_option() -> void:
	for flag in ["--smoketest", "--colonytest", "--vilatest"]:
		T.ok(ToonLook.decide_style(_args([flag]), true, false), "%s roda com o estilo, mesmo com a opção desligada" % flag)
		T.ok(ToonLook.decide_outline(_args([flag]), false), "%s roda com contorno" % flag)


func test_outline_option_and_flag() -> void:
	T.ok(ToonLook.decide_outline(_args([]), true), "opção ligada: contorno")
	T.ok(not ToonLook.decide_outline(_args([]), false), "opção desligada: sem contorno")
	T.ok(not ToonLook.decide_outline(_args(["--nooutline"]), true), "--nooutline vence a opção")


func _piece(at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.2, 0.2, 0.2)
	mi.mesh = box
	mi.position = at
	return mi


func test_merged_hull_joins_sibling_pieces() -> void:
	var a := _piece(Vector3.ZERO)
	var b := _piece(Vector3(1, 0, 0))
	var one := ToonLook._hull_of(a.mesh)
	var both := ToonLook._merged_hull([a, b])
	T.ok(both != null, "casca juntada existe")
	T.eq(both.get_surface_count(), 1, "uma superfície só")
	var v1: PackedVector3Array = one.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var v2: PackedVector3Array = both.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	T.eq(v2.size(), v1.size() * 2, "vértices das duas peças")
	var max_x := -INF
	for v in v2:
		max_x = maxf(max_x, v.x)
	T.ok(absf(max_x - 1.1) < 0.001, "a segunda peça entra deslocada pela posição dela")
	var idx: PackedInt32Array = both.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var top := 0
	for i in idx:
		top = maxi(top, i)
	T.eq(top, v2.size() - 1, "índices da segunda peça deslocados")
	T.ok(ToonLook._merged_hull([a, b]) == both, "mesmo grupo reaproveita a casca do cache")
	a.free()
	b.free()
