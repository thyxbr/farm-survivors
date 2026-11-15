extends RefCounted
## EnemyModel: peças irmãs do modelo do inimigo juntadas numa malha só, sem mudar o desenho.


func _piece(at: Vector3, mat: Material = null, scale := Vector3.ONE) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = Vector3(0.2, 0.2, 0.2)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.get_mesh_arrays())
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	mi.scale = scale
	return mi


func _tris(root: Node) -> int:
	var n := 0
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.is_in_group(ToonLook.OUTLINE_GROUP) or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			n += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		for s in root.mesh.get_surface_count():
			n += (root.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n


func test_merge_one_surface_per_material() -> void:
	var red := StandardMaterial3D.new()
	var blue := StandardMaterial3D.new()
	var a := _piece(Vector3.ZERO, red)
	var b := _piece(Vector3(1, 0, 0), red)
	var c := _piece(Vector3(2, 0, 0), blue)
	var one: PackedVector3Array = a.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var pieces: Array[MeshInstance3D] = [a, b, c]
	var m := EnemyModel.merge(pieces)
	T.eq(m.get_surface_count(), 2, "uma superfície por material")
	T.ok(m.surface_get_material(0) == red and m.surface_get_material(1) == blue, "cada superfície com o material das peças")
	var v: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	T.eq(v.size(), one.size() * 2, "as duas peças vermelhas na mesma superfície")
	var max_x := -INF
	for p in v:
		max_x = maxf(max_x, p.x)
	T.ok(absf(max_x - 1.1) < 0.001, "a segunda peça entra na posição dela")
	var idx: PackedInt32Array = m.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var top := 0
	for i in idx:
		top = maxi(top, i)
	T.eq(top, v.size() - 1, "índices da segunda peça deslocados")
	for n in pieces:
		n.free()


## Peça espelhada (escala negativa, como a perna direita feita a partir da esquerda): os triângulos
## continuam de frente para fora.
func test_merge_mirrored_piece_keeps_facing() -> void:
	var a := _piece(Vector3.ZERO, null, Vector3(-1, 1, 1))
	var pieces: Array[MeshInstance3D] = [a]
	var m := EnemyModel.merge(pieces)
	var arr := m.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var same := 0
	var src_arr := a.mesh.surface_get_arrays(0)
	var sv: PackedVector3Array = src_arr[Mesh.ARRAY_VERTEX]
	var si: PackedInt32Array = src_arr[Mesh.ARRAY_INDEX]
	for t in range(0, idx.size(), 3):
		# a normal geométrica do triângulo, antes e depois: espelhada em x, igual em y e z
		var n0 := (sv[si[t + 1]] - sv[si[t]]).cross(sv[si[t + 2]] - sv[si[t]])
		var n1 := (v[idx[t + 1]] - v[idx[t]]).cross(v[idx[t + 2]] - v[idx[t]])
		if n1.is_equal_approx(Vector3(-n0.x, n0.y, n0.z)):
			same += 1
	T.eq(same, idx.size() / 3, "todo triângulo da peça espelhada aponta para o lado certo")
	a.free()


func test_merged_copy_keeps_groups_and_special_pieces() -> void:
	var root := Node3D.new()
	root.name = "Root"
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	body.add_child(_piece(Vector3.ZERO))
	body.add_child(_piece(Vector3(0, 1, 0)))
	var goo := _piece(Vector3(0, 2, 0))
	goo.name = "Goo"
	goo.material_override = StandardMaterial3D.new()      # material por cima: fica de fora
	body.add_child(goo)
	var arm := Node3D.new()
	arm.name = "ArmL"
	arm.position = Vector3(1, 0, 0)
	body.add_child(arm)
	var lone := _piece(Vector3.ZERO)
	lone.name = "Hand"
	arm.add_child(lone)                                    # peça sozinha: segue como está
	var out := EnemyModel.merged_copy(root)
	var b2 := out.get_node("Body") as Node3D
	T.ok(b2 != null and b2.get_node_or_null("ArmL") != null, "os grupos continuam com o mesmo nome")
	T.ok((b2.get_node("ArmL") as Node3D).position.is_equal_approx(Vector3(1, 0, 0)), "e na mesma posição")
	T.ok(b2.get_node_or_null(EnemyModel.MERGED) is MeshInstance3D, "as duas peças simples viraram uma malha")
	T.ok(b2.get_node_or_null("Goo") != null and (b2.get_node("Goo") as MeshInstance3D).material_override != null, "peça com material por cima não entra")
	T.ok(b2.get_node("ArmL").get_node_or_null("Hand") != null, "peça sozinha não muda")
	T.eq(out.find_children("*", "MeshInstance3D", true, false).size(), 3, "três malhas no total")
	T.eq(_tris(out), _tris(root), "nenhum triângulo a mais ou a menos")
	out.free()
	root.free()


## O goblin de verdade: 102 peças no GLB, 7 malhas no modelo pronto (uma por grupo que o código anima).
func test_goblin_instance_has_one_mesh_per_group() -> void:
	var data := {"model": "goblin", "scale": 1.0}
	var src: Node3D = EnemyModel.MODELS.goblin.instantiate()
	var m := EnemyModel.instance("goblin", data)
	for n in ["Body", "Head", "ArmL", "ArmR", "LegL", "LegR", "Crown"]:
		var g := m.find_child(n, true, false) as Node3D
		var g0 := src.find_child(n, true, false) as Node3D
		T.ok(g != null and g.get_node_or_null(EnemyModel.MERGED) is MeshInstance3D, "%s tem a malha juntada" % n)
		T.ok(g != null and g.transform.is_equal_approx(g0.transform), "%s na posição do GLB" % n)
	if not ToonLook.enabled():
		T.eq(m.find_children("*", "MeshInstance3D", true, false).size(), 7, "sete malhas")
	T.eq(_tris(m), _tris(src), "os mesmos triângulos do GLB")
	T.ok(EnemyModel.instance("goblin", data) != m, "cada chamada devolve uma cópia nova")
	src.free()
	m.free()


func test_tint_shares_one_copy_per_material() -> void:
	var data := {"model": "goblin", "scale": 1.0, "tint": [Color(1, 0, 0), 0.5]}
	var plain := EnemyModel.instance("goblin", {"model": "goblin", "scale": 1.0})
	var red := EnemyModel.instance("goblin_teste_tinto", data)
	var a := (plain.find_child("Body", true, false).get_node(EnemyModel.MERGED) as MeshInstance3D).mesh
	var b := (red.find_child("Body", true, false).get_node(EnemyModel.MERGED) as MeshInstance3D).mesh
	T.eq(b.get_surface_count(), a.get_surface_count(), "a tintura não cria superfícies a mais")
	if not ToonLook.enabled():
		var ca: Color = (a.surface_get_material(0) as StandardMaterial3D).albedo_color
		var cb: Color = (b.surface_get_material(0) as StandardMaterial3D).albedo_color
		T.ok(cb.is_equal_approx(ca.lerp(Color(1, 0, 0), 0.5)), "cor puxada para a tintura")
	plain.free()
	red.free()
