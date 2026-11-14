extends SceneTree
## Confere os modelos com esqueleto dos NPCs da vila (assets/models/elder.glb e merchant.glb) depois do import.
## Rode com:
##   godot --headless --path . --script res://tests/npc_asset_test.gd
## Imprime PASS/FAIL para cada verificação e encerra com código 0 (ok) ou 1 (falhas).

# Medidas do Bram de antes do esqueleto (peças rígidas, braços caídos), em metros, coordenadas do Godot.
const ELDER_TOP := 1.753              # topo da cabeça (cabelo), sem o cajado
const ELDER_SHOULDERS := 0.552        # largura entre as ombreiras da túnica
const ELDER_STAFF_TOP := 2.011        # topo do cajado (gancho)
const ELDER_STAFF_AT := Vector2(0.25, 0.07)   # (x, z) do eixo do cajado, ao lado da mão esquerda
# Medidas da Mira de antes do esqueleto (peças rígidas, braços caídos).
const MERCHANT_TOP := 1.865           # topo da cabeça (turbante)
const MERCHANT_WRIST := Vector3(0.24, 0.93, 0.0)   # punho esquerdo (fim do antebraço); o direito é o espelho em x

const HUMANOID := ["Hips", "Spine", "Chest", "Neck", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand",
		"RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
		"RightUpperLeg", "RightLowerLeg", "RightFoot"]

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("PASS  ", what)
	else:
		fails += 1
		print("FAIL  ", what)


# transformação de n relativa a top
func _xform_to(n: Node3D, top: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	while n != top:
		xf = n.transform * xf
		n = n.get_parent() as Node3D
	return xf


func _initialize() -> void:
	_check_elder()
	_check_merchant()
	print("FALHAS: ", fails)
	quit(1 if fails > 0 else 0)


func _check_elder() -> void:
	var scene: PackedScene = load("res://assets/models/elder.glb")
	check(scene != null, "elder.glb carrega")
	if scene == null:
		return
	var m: Node3D = scene.instantiate()
	root.add_child(m)
	var sk: Skeleton3D = null
	var sks := m.find_children("*", "Skeleton3D")
	check(sks.size() == 1, "Bram tem um Skeleton3D")
	if sks.size() == 1:
		sk = sks[0] as Skeleton3D
		for b: String in HUMANOID:
			check(sk.find_bone(b) >= 0, "Bram: osso do perfil humanoide " + b)
	var mi := m.find_children("*", "MeshInstance3D")
	check(mi.any(func(x): return x.skin != null), "Bram: malha do corpo é skinned")
	var staff := m.find_child("Staff", true, false) as MeshInstance3D
	check(staff != null and staff.skin == null, "Bram: cajado (Staff) é malha separada e sem pesos")
	var ap: AnimationPlayer = null
	var aps := m.find_children("*", "AnimationPlayer")
	check(aps.size() == 1, "Bram tem um AnimationPlayer")
	if aps.size() == 1:
		ap = aps[0] as AnimationPlayer
		for c in ["staff_hold", "excited"]:
			check(ap.has_animation(c), "Bram: clipe " + c)
		if ap.has_animation("excited"):
			var dur := ap.get_animation("excited").length
			check(dur > 1.2 and dur < 1.8, "Bram: excited dura ~1,5 s (%.2f s)" % dur)
	# altura e pés no chão (corpo em pose T, sem o cajado)
	var box := AABB()
	var first := true
	for x: MeshInstance3D in mi:
		if x == staff:
			continue
		var b: AABB = _xform_to(x, m) * x.get_aabb()
		box = b if first else box.merge(b)
		first = false
	check(not first and absf(box.end.y - ELDER_TOP) <= 0.03,
			"Bram: altura %.3f m (antes %.3f m)" % [box.end.y, ELDER_TOP])
	check(not first and box.position.y > -0.02 and box.position.y < 0.03,
			"Bram: pés no chão (%.3f m)" % box.position.y)
	# staff_hold: o cajado preso à mão esquerda volta ao lugar de antes, de pé ao lado do corpo
	if sk != null and staff != null and ap != null and ap.has_animation("staff_hold"):
		ap.play("staff_hold")
		ap.seek(0.0, true)
		var hand := sk.find_bone("LeftHand")
		var s := _xform_to(sk, m)
		var follow := s * sk.get_bone_global_pose(hand) * sk.get_bone_global_rest(hand).affine_inverse() * s.affine_inverse()
		var st := follow * _xform_to(staff, m)
		var sb: AABB = st * staff.get_aabb()
		check(absf(sb.end.y - ELDER_STAFF_TOP) <= 0.03,
				"Bram: staff_hold, topo do cajado %.3f m (antes %.3f m)" % [sb.end.y, ELDER_STAFF_TOP])
		check(sb.position.y > -0.01 and sb.position.y < 0.06, "Bram: staff_hold, pé do cajado no chão (%.3f m)" % sb.position.y)
		var c := sb.get_center()
		check(Vector2(c.x, c.z).distance_to(ELDER_STAFF_AT) <= 0.03,
				"Bram: staff_hold, cajado ao lado da mão esquerda (%.3f, %.3f)" % [c.x, c.z])
	m.free()


func _check_merchant() -> void:
	var scene: PackedScene = load("res://assets/models/merchant.glb")
	check(scene != null, "merchant.glb carrega")
	if scene == null:
		return
	var m: Node3D = scene.instantiate()
	root.add_child(m)
	var sk: Skeleton3D = null
	var sks := m.find_children("*", "Skeleton3D")
	check(sks.size() == 1, "Mira tem um Skeleton3D")
	if sks.size() == 1:
		sk = sks[0] as Skeleton3D
		for b: String in HUMANOID:
			check(sk.find_bone(b) >= 0, "Mira: osso do perfil humanoide " + b)
	var mi := m.find_children("*", "MeshInstance3D")
	check(mi.any(func(x): return x.skin != null), "Mira: malha do corpo é skinned")
	var ap: AnimationPlayer = null
	var aps := m.find_children("*", "AnimationPlayer")
	check(aps.size() == 1, "Mira tem um AnimationPlayer")
	if aps.size() == 1:
		ap = aps[0] as AnimationPlayer
		for c in ["arms_down", "call"]:
			check(ap.has_animation(c), "Mira: clipe " + c)
		if ap.has_animation("call"):
			var dur := ap.get_animation("call").length
			check(dur > 1.2 and dur < 1.8, "Mira: call dura ~1,5 s (%.2f s)" % dur)
	# altura e pés no chão (corpo em pose T)
	var box := AABB()
	var first := true
	for x: MeshInstance3D in mi:
		var b: AABB = _xform_to(x, m) * x.get_aabb()
		box = b if first else box.merge(b)
		first = false
	check(not first and absf(box.end.y - MERCHANT_TOP) <= 0.03,
			"Mira: altura %.3f m (antes %.3f m)" % [box.end.y, MERCHANT_TOP])
	check(not first and box.position.y > -0.02 and box.position.y < 0.03,
			"Mira: pés no chão (%.3f m)" % box.position.y)
	# arms_down: os punhos voltam para onde as mãos ficavam no modelo antigo, braços caídos
	if sk != null and ap != null and ap.has_animation("arms_down"):
		ap.play("arms_down")
		ap.seek(0.0, true)
		var s := _xform_to(sk, m)
		for sd: String in ["Left", "Right"]:
			var w := MERCHANT_WRIST * Vector3(1.0 if sd == "Left" else -1.0, 1.0, 1.0)
			var at := s * sk.get_bone_global_pose(sk.find_bone(sd + "Hand")).origin
			check(at.distance_to(w) <= 0.03, "Mira: arms_down, punho %s em %s (antes %s)" % [sd, at, w])
	m.free()
