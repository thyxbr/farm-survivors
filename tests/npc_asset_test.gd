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
	_check_libraries()
	_check_substitutes()
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


# ---------------------------------------------------------------- bibliotecas "mixamo" (tools/build_npc_mixamo.gd)
const LIBS := {
	"elder": ["res://assets/animations/elder_mixamo.res", {"idle": true, "excited": false, "talk": true}],
	"merchant": ["res://assets/animations/merchant_mixamo.res", {"idle": true, "call": false, "talk": true}],
}
## Ossos do braço esquerdo do Bram presos na pose staff_hold (o cajado não balança).
const ELDER_LOCKED := ["LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand"]
const SK := "%GeneralSkeleton:"


func _check_libraries() -> void:
	for npc: String in LIBS:
		var lib := load(LIBS[npc][0]) as AnimationLibrary
		check(lib != null, "%s carrega como AnimationLibrary" % LIBS[npc][0])
		if lib != null:
			_check_library(npc, lib)


## Com nenhum FBX novo presente (pasta inexistente), a ferramenta monta tudo de substitutos e diz a origem.
func _check_substitutes() -> void:
	var tool: Script = load("res://tools/build_npc_mixamo.gd")
	check(tool != null, "tools/build_npc_mixamo.gd carrega")
	if tool == null:
		return
	var subs := {"elder": {"idle": "blacksmith_mixamo.res", "excited": "elder.glb", "talk": "blacksmith_mixamo.res"},
			"merchant": {"idle": "blacksmith_mixamo.res", "call": "merchant.glb", "talk": "blacksmith_mixamo.res"}}
	for npc: String in subs:
		var origins := {}
		var lib: AnimationLibrary = tool.build(npc, "res://tests/sem_fbx/", origins)
		check(lib != null, "%s sem FBX: a ferramenta monta a biblioteca" % npc)
		if lib == null:
			continue
		for c: String in subs[npc]:
			var o: String = origins.get(c, "")
			check(o.begins_with("SUBSTITUTO") and o.contains(subs[npc][c]),
					"%s sem FBX: %s vem de substituto (%s)" % [npc, c, o])
		_check_library(npc + " sem FBX", lib)


func _check_library(npc: String, lib: AnimationLibrary) -> void:
	var key := npc.get_slice(" ", 0)
	var loops: Dictionary = LIBS[key][1]
	var names: Array = lib.get_animation_list().map(func(n): return str(n))
	names.sort()
	var want: Array = loops.keys()
	want.sort()
	check(names == want, "%s: clipes %s (esperado %s)" % [npc, names, want])
	var bones := {}   # NodePath:tipo animados por algum clipe
	for c: String in loops:
		if not lib.has_animation(c):
			continue
		var a := lib.get_animation(c)
		print("      %s/%s: %s, %.2f s, %d tracks" % [npc, c, a.get_meta("origem", "?"), a.length, a.get_track_count()])
		check((a.loop_mode == Animation.LOOP_LINEAR) == loops[c],
				"%s: %s %s" % [npc, c, "em loop" if loops[c] else "toca uma vez"])
		var stray := 0
		for t in a.get_track_count():
			var p := str(a.track_get_path(t))
			bones["%s:%d" % [p, a.track_get_type(t)]] = true
			if not p.begins_with(SK) or p.contains("mixamorig"):
				stray += 1
		check(a.get_track_count() > 0 and stray == 0, "%s: %s anima só ossos do perfil (%d fora)" % [npc, c, stray])
	# um osso sem track no clipe atual ficaria preso na pose do clipe anterior
	for c: String in loops:
		if lib.has_animation(c):
			var a := lib.get_animation(c)
			var missing := bones.keys().filter(func(k: String):
				return a.find_track(NodePath(k.get_slice(":", 0) + ":" + k.get_slice(":", 1)), int(k.get_slice(":", 2))) < 0)
			check(missing.is_empty(), "%s: %s anima todos os ossos da biblioteca (faltam %s)" % [npc, c, missing])
	if key == "elder":
		_check_staff_lock(npc, lib)


## Bram: em todos os clipes o braço esquerdo fica parado na pose staff_hold do elder.glb.
func _check_staff_lock(npc: String, lib: AnimationLibrary) -> void:
	var m: Node3D = (load("res://assets/models/elder.glb") as PackedScene).instantiate()
	var ap := m.find_children("*", "AnimationPlayer")[0] as AnimationPlayer
	var hold := ap.get_animation("staff_hold")
	var t_hold := hold.find_track(SK + "LeftLowerArm", Animation.TYPE_ROTATION_3D)
	var want: Quaternion = hold.rotation_track_interpolate(t_hold, 0.0)
	m.free()
	for c in lib.get_animation_list():
		var a := lib.get_animation(c)
		for b: String in ELDER_LOCKED:
			var t := a.find_track(SK + b, Animation.TYPE_ROTATION_3D)
			var other := a.find_track(SK + b, Animation.TYPE_POSITION_3D) >= 0 or a.find_track(SK + b, Animation.TYPE_SCALE_3D) >= 0
			var r0: Quaternion = a.rotation_track_interpolate(t, 0.0) if t >= 0 else Quaternion()
			var r1: Quaternion = a.rotation_track_interpolate(t, a.length * 0.5) if t >= 0 else Quaternion()
			check(t >= 0 and not other and r0.is_equal_approx(r1),
					"%s: %s, %s constante (t=0 e meio iguais)" % [npc, c, b])
		var tl := a.find_track(SK + "LeftLowerArm", Animation.TYPE_ROTATION_3D)
		check(tl >= 0 and (a.rotation_track_interpolate(tl, a.length * 0.5) as Quaternion).is_equal_approx(want),
				"%s: %s, LeftLowerArm na pose staff_hold" % [npc, c])
