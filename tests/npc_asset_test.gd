extends SceneTree
## Confere os modelos com esqueleto dos NPCs da vila (assets/models/elder.glb e merchant.glb) depois do import.
## Rode com:
##   godot --headless --path . --script res://tests/npc_asset_test.gd
## Imprime PASS/FAIL para cada verificação e encerra com código 0 (ok) ou 1 (falhas).

# Medidas do Bram de antes do esqueleto (peças rígidas, braços caídos), em metros, coordenadas do Godot.
const ELDER_TOP := 1.753              # topo da cabeça (cabelo), sem o cajado
const ELDER_SHOULDERS := 0.552        # largura entre as ombreiras da túnica
const ELDER_STAFF_TOP := 2.011        # topo do cajado (gancho)
# staff_hold segura o cajado como cajado de caminhada: cotovelo dobrado, punho em volta do cajado a ~1 m (antes
# o braço caía esticado e a mão ficava a 0,88 m, sem folga para o braço alcançar o cajado fincado nos clipes).
# O cajado é o mesmo, na mesma altura; fica à frente e para fora, longe da túnica.
const ELDER_STAFF_AT := Vector2(0.429, 0.27)   # (x, z) do centro do cajado no staff_hold (antes 0.25, 0.07)
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
				"Bram: staff_hold, cajado na mão esquerda, à frente e para fora (%.3f, %.3f)" % [c.x, c.z])
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
const STAFF_SAMPLES := 12       # instantes conferidos por clipe
const STAFF_TILT := 5.0         # inclinação máxima do cajado (graus)
const STAFF_FOOT := 0.02        # pé do cajado: altura máxima acima/abaixo do chão (m)
const ELBOW_AXIS := 0.999       # cotovelo como dobradiça: eixo da rotação de LeftLowerArm ~ X local
const WRIST_TWIST := 25.0       # torção máxima da mão em torno do antebraço (graus)
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
		_check_staff_planted(npc, lib)
	if key == "merchant" and lib.has_animation("call"):
		_check_seamless(npc, lib.get_animation("call"))


## A Mira toca o call várias vezes seguidas: o último quadro tem de casar com o primeiro (sem salto na emenda).
func _check_seamless(npc: String, a: Animation) -> void:
	var seam := 0.0
	var where := ""
	for t in a.get_track_count():
		var d := 0.0
		match a.track_get_type(t):
			Animation.TYPE_ROTATION_3D:
				d = rad_to_deg((a.rotation_track_interpolate(t, 0.0) as Quaternion).angle_to(a.rotation_track_interpolate(t, a.length)))
			Animation.TYPE_POSITION_3D:   # 1 cm conta como 1°
				d = 100.0 * (a.position_track_interpolate(t, 0.0) as Vector3).distance_to(a.position_track_interpolate(t, a.length))
		if d > seam:
			seam = d
			where = str(a.track_get_path(t)).get_slice(":", 1)
	check(seam <= 1.0, "%s: call emenda sem salto (maior diferença fim/início %.2f em %s)" % [npc, seam, where])


## Bram: em todos os clipes o cajado (preso à mão esquerda como o jogo prende) fica de pé, com o pé no chão, e
## o braço esquerdo é dobradiça (cotovelo só no eixo X local, mão sem torção em torno do antebraço).
func _check_staff_planted(npc: String, lib: AnimationLibrary) -> void:
	var m: Node3D = (load("res://assets/models/elder.glb") as PackedScene).instantiate()
	root.add_child(m)
	var ap := m.find_children("*", "AnimationPlayer")[0] as AnimationPlayer
	var sk := m.find_children("*", "Skeleton3D")[0] as Skeleton3D
	var staff := m.find_child("Staff", true, false) as MeshInstance3D
	var s := _xform_to(sk, m)
	var hd := sk.find_bone("LeftHand")
	var la := sk.find_bone("LeftLowerArm")
	var cl := sk.find_bone("LeftShoulder")
	ap.play("staff_hold")
	ap.seek(0.0, true)
	var cl_hold := sk.get_bone_pose_rotation(cl)
	var la_rest := sk.get_bone_rest(la).basis.get_rotation_quaternion()
	var hd_rest := sk.get_bone_rest(hd).basis.get_rotation_quaternion()
	# como SkinnedNPC._attach: o cajado segue a mão mantendo onde estava em relação a ela na pose T
	var grip := (s * sk.get_bone_global_rest(hd)).affine_inverse() * _xform_to(staff, m)
	var box := staff.get_aabb()
	var long := box.get_longest_axis_index()
	var axis := Vector3.ZERO
	axis[long] = 1.0
	ap.add_animation_library("teste", lib)
	for c in lib.get_animation_list():
		var a := lib.get_animation(c)
		ap.play("teste/" + c)
		var tilt := 0.0
		var foot_lo := INF
		var foot_hi := -INF
		var spot_min := Vector2(INF, INF)
		var spot_max := Vector2(-INF, -INF)
		var hinge := 1.0
		var twist := 0.0
		var clav := 0.0   # quanto a clavícula sai da pose staff_hold (graus)
		for i in STAFF_SAMPLES:
			var t := a.length * i / float(STAFF_SAMPLES - 1)
			ap.seek(t, true)
			var st := s * _pose_global(sk, hd) * grip
			var v := (st.basis * axis).normalized()
			tilt = maxf(tilt, rad_to_deg(acos(absf(v.y))))
			var low := INF
			for k in 8:
				low = minf(low, (st * box.get_endpoint(k)).y)
			foot_lo = minf(foot_lo, low)
			foot_hi = maxf(foot_hi, low)
			var o := st * box.get_center()
			spot_min = spot_min.min(Vector2(o.x, o.z))
			spot_max = spot_max.max(Vector2(o.x, o.z))
			var dq := la_rest.inverse() * sk.get_bone_pose_rotation(la)
			if dq.get_angle() > deg_to_rad(3.0):
				hinge = minf(hinge, dq.get_axis().dot(Vector3.RIGHT))
			clav = maxf(clav, rad_to_deg(sk.get_bone_pose_rotation(cl).angle_to(cl_hold)))
			var dh := hd_rest.inverse() * sk.get_bone_pose_rotation(hd)
			twist = maxf(twist, absf(rad_to_deg(wrapf(2.0 * atan2(dh.y, dh.w), -PI, PI))))
		check(tilt <= STAFF_TILT, "%s: %s, cajado de pé (inclinação até %.1f°)" % [npc, c, tilt])
		check(foot_lo >= -STAFF_FOOT and foot_hi <= STAFF_FOOT,
				"%s: %s, pé do cajado no chão (%.3f a %.3f m)" % [npc, c, foot_lo, foot_hi])
		check(spot_min.distance_to(spot_max) <= 0.02,
				"%s: %s, cajado parado no mesmo ponto (varia %.3f m)" % [npc, c, spot_min.distance_to(spot_max)])
		check(hinge >= ELBOW_AXIS, "%s: %s, cotovelo como dobradiça (eixo·X %.4f)" % [npc, c, hinge])
		check(twist <= WRIST_TWIST, "%s: %s, mão sem torção (até %.1f°)" % [npc, c, twist])
		check(clav <= 0.5, "%s: %s, alcança o cajado sem baixar a clavícula (até %.1f°)" % [npc, c, clav])
	ap.stop()
	ap.remove_animation_library("teste")
	m.free()


## Pose global (espaço do esqueleto) do osso b a partir das poses locais atuais: o cache global do Skeleton3D
## só se atualiza no quadro seguinte, então depois de vários seek() no mesmo quadro ele estaria velho.
func _pose_global(sk: Skeleton3D, b: int) -> Transform3D:
	var x := Transform3D.IDENTITY
	while b >= 0:
		x = sk.get_bone_pose(b) * x
		b = sk.get_bone_parent(b)
	return x
