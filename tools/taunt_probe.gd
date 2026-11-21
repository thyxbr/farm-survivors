extends SceneTree
## Mede o clipe "Sword And Shield Power Up" do Mixamo (assets/animations/mixamo/sword_shield_power_up.fbx, 2,37 s)
## e imprime as chaves no formato de KnightMoves.TAUNT_CAST: [t, mão esq., cotovelo esq., mão dir., cotovelo dir.,
## inclinação, giro, subida]. O clipe começa virado de lado: tudo é rodado para o referencial do quadril em t = 0
## (+Z à frente, +X à esquerda). Inclinação = tronco para a frente (rad, relativa a t = 0, x0,45 como no Martelo),
## giro = ombros contra o quadril (pela metade) e subida = quadril (m, relativa a t = 0).
## Fases do clipe: 0..0,4 s recolhe os braços junto ao peito (agacha um pouco); 0,45..0,6 s explode, os braços
## lançados para baixo e para fora, o peito aberto para cima; segura até 1,7 s; 1,7..2,37 s volta à guarda.
##   godot --headless --path . --script res://tools/taunt_probe.gd
const TIMES := [0.0, 0.2, 0.35, 0.45, 0.55, 0.65, 0.8, 1.6, 1.8, 2.0, 2.2, 2.36]


func _init() -> void:
	var sc: PackedScene = load("res://assets/animations/mixamo/sword_shield_power_up.fbx")
	var root := sc.instantiate()
	var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
	var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	var an := ap.get_animation(ap.get_animation_list()[0])
	print("len=", an.length)
	var rot := {}
	var pos := {}
	for i in an.get_track_count():
		var b := String(an.track_get_path(i)).get_slice(":", 1)
		if an.track_get_type(i) == Animation.TYPE_ROTATION_3D: rot[b] = i
		elif an.track_get_type(i) == Animation.TYPE_POSITION_3D: pos[b] = i
	var frame := Basis()
	var pitch0 := 0.0
	var hip0 := 0.0
	var twist0 := 0.0
	for k in TIMES.size():
		var t: float = TIMES[k]
		var g := {}
		for i in sk.get_bone_count():
			var n := sk.get_bone_name(i)
			var l := sk.get_bone_rest(i)
			if rot.has(n): l.basis = Basis(an.rotation_track_interpolate(rot[n], t)).scaled(l.basis.get_scale())
			if pos.has(n): l.origin = an.position_track_interpolate(pos[n], t)
			var par := sk.get_bone_parent(i)
			g[i] = (g[par] * l) if par >= 0 else l
		var P := func(n: String) -> Vector3: return g[sk.find_bone(n)].origin
		var hz: Vector3 = g[sk.find_bone("Hips")].basis.orthonormalized().z
		var cz: Vector3 = g[sk.find_bone("UpperChest")].basis.orthonormalized().z
		if k == 0:
			var f := Vector3(hz.x, 0.0, hz.z).normalized()
			# do esqueleto para o referencial do herói: f vira +Z, a esquerda (up x f) vira +X
			frame = Basis(Vector3.UP.cross(f), Vector3.UP, f).inverse()
			pitch0 = asin(clampf(cz.y, -1.0, 1.0))
			hip0 = P.call("Hips").y
			twist0 = _yaw(cz) - _yaw(hz)
		var vals := []
		for s in ["Left", "Right"]:
			var sh: Vector3 = P.call(s + "UpperArm")
			vals.append(frame * (P.call(s + "Hand") - sh))
			vals.append(frame * (P.call(s + "LowerArm") - sh))
		var incline := -(asin(clampf(cz.y, -1.0, 1.0)) - pitch0) * 0.45
		var twist := wrapf(_yaw(cz) - _yaw(hz) - twist0, -PI, PI) * 0.5
		var lift: float = (P.call("Hips").y - hip0) * 0.8
		print("\t[%.2f, %s, %s, %s, %s, %.2f, %.2f, %.3f]," % [t, _v(vals[0]), _v(vals[1]), _v(vals[2]), _v(vals[3]), incline, twist, lift])
	quit()


func _yaw(v: Vector3) -> float:
	return atan2(v.x, v.z)


func _v(v: Vector3) -> String:
	return "Vector3(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
