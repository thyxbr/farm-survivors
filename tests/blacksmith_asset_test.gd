extends SceneTree
## Confere o modelo do ferreiro (assets/models/blacksmith.glb) depois do import. Rode com:
##   godot --headless --path . --script res://tests/blacksmith_asset_test.gd
## Imprime PASS/FAIL para cada verificação e encerra com código 0 (ok) ou 1 (falhas).

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("PASS  ", what)
	else:
		fails += 1
		print("FAIL  ", what)


# transformação de n relativa a top (o modelo não entra na árvore)
func _xform_to(n: Node3D, top: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	while n != top:
		xf = n.transform * xf
		n = n.get_parent() as Node3D
	return xf


func _initialize() -> void:
	var scene: PackedScene = load("res://assets/models/blacksmith.glb")
	check(scene != null, "blacksmith.glb carrega")
	if scene == null:
		quit(1)
		return
	var m: Node3D = scene.instantiate()
	var sks := m.find_children("*", "Skeleton3D")
	check(sks.size() == 1, "ferreiro tem um Skeleton3D")
	if sks.size() == 1:
		var sk := sks[0] as Skeleton3D
		for b in ["Hips", "Spine", "Chest", "Neck", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand",
				"RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
				"RightUpperLeg", "RightLowerLeg", "RightFoot"]:
			check(sk.find_bone(b) >= 0, "osso do perfil humanoide: " + b)
	var aps := m.find_children("*", "AnimationPlayer")
	check(aps.size() == 1, "ferreiro tem um AnimationPlayer")
	if aps.size() == 1:
		var ap := aps[0] as AnimationPlayer
		for c in ["work_hammer", "work_pause", "idle", "talk"]:
			check(ap.has_animation(c), "clipe provisório: " + c)
		if ap.has_animation("work_hammer"):
			check(ap.get_animation("work_hammer").loop_mode == Animation.LOOP_LINEAR, "martelar está em loop")
	var hammer := m.find_child("Hammer", true, false) as MeshInstance3D
	check(hammer != null and hammer.skin == null, "martelo é malha separada e sem pesos")
	var mi := m.find_children("*", "MeshInstance3D")
	check(mi.any(func(x): return x.skin != null), "malha do corpo é skinned")
	# altura: topo da cabeça entre 1.6 e 1.95 m, como Bram/Mira (pés no chão)
	var box := AABB()
	var first := true
	for x in mi:
		if x == hammer:
			continue
		var b: AABB = _xform_to(x, m) * x.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var top := box.end.y
	check(not first and top > 1.6 and top < 1.95, "altura do ferreiro %.2f m" % top)
	check(not first and absf(box.position.y) < 0.05, "pés no chão (%.3f m)" % box.position.y)
	m.free()
	_check_props()
	print("FALHAS: ", fails)
	quit(1 if fails > 0 else 0)


# bigorna (alvo do golpe) e forja (brasas) do ferreiro
func _check_props() -> void:
	var a_scene: PackedScene = load("res://assets/models/anvil.glb")
	check(a_scene != null, "anvil.glb carrega")
	if a_scene != null:
		var a: Node3D = a_scene.instantiate()
		var sp := a.find_child("StrikePoint", true, false) as Node3D
		check(sp != null, "bigorna tem StrikePoint")
		if sp != null:
			var y := _xform_to(sp, a).origin.y
			check(y > 0.7 and y < 0.9, "StrikePoint a %.2f m do chão" % y)
		a.free()
	var f_scene: PackedScene = load("res://assets/models/forge.glb")
	check(f_scene != null, "forge.glb carrega")
	if f_scene != null:
		var f: Node3D = f_scene.instantiate()
		check(f.find_child("Embers", true, false) != null, "forja tem Embers")
		f.free()
