extends SceneTree
## Mede o clipe "Sword And Shield Casting" do Mixamo (assets/animations/mixamo/sword_shield_casting.fbx): só a parte
## em que o herói ergue a espada (0..1,3 s; depois ele se ajoelha e crava a espada, que não entra). Mão e cotovelo
## menos ombro, no espaço do esqueleto (+Z à frente, +X à esquerda), e a direção da lâmina (eixo do punho).
## Os números viraram KnightMoves.HAMMER_RAISE.
##   godot --headless --path . --script res://tools/hammer_probe.gd
func _init() -> void:
	var sc: PackedScene = load("res://assets/animations/mixamo/sword_shield_casting.fbx")
	var root := sc.instantiate()
	var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
	var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	var an := ap.get_animation(ap.get_animation_list()[0])
	var rot := {}
	var pos := {}
	for i in an.get_track_count():
		var b := String(an.track_get_path(i)).get_slice(":", 1)
		if an.track_get_type(i) == Animation.TYPE_ROTATION_3D: rot[b] = i
		elif an.track_get_type(i) == Animation.TYPE_POSITION_3D: pos[b] = i
	var t := 0.0
	while t <= 1.401:
		var g := {}
		for i in sk.get_bone_count():
			var n := sk.get_bone_name(i)
			var l := sk.get_bone_rest(i)
			if rot.has(n): l.basis = Basis(an.rotation_track_interpolate(rot[n], t)).scaled(l.basis.get_scale())
			if pos.has(n): l.origin = an.position_track_interpolate(pos[n], t)
			var par := sk.get_bone_parent(i)
			g[i] = (g[par] * l) if par >= 0 else l
		var P := func(n: String) -> Vector3: return g[sk.find_bone(n)].origin
		var line := "t=%.2f" % t
		for s in ["Left", "Right"]:
			var sh: Vector3 = P.call(s + "UpperArm")
			line += " %s hand%s elbow%s" % [s[0], _v(P.call(s + "Hand") - sh), _v(P.call(s + "LowerArm") - sh)]
		var hb: Basis = g[sk.find_bone("RightHand")].basis.orthonormalized()
		line += " Rhand.y%s Rhand.z%s Rhand.x%s" % [_v(hb.y), _v(hb.z), _v(hb.x)]
		var cb: Basis = g[sk.find_bone("UpperChest")].basis.orthonormalized()
		var hipb: Basis = g[sk.find_bone("Hips")].basis.orthonormalized()
		line += " hipY=%.3f chestZ%s hipsZ%s" % [P.call("Hips").y, _v(cb.z), _v(hipb.z)]
		for s in ["Left", "Right"]:
			line += " %sknee%s foot%s" % [s[0], _v(P.call(s + "LowerLeg") - P.call(s + "UpperLeg")), _v(P.call(s + "Foot") - P.call(s + "UpperLeg"))]
		print(line)
		t += 0.1
	quit()

func _v(v: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]
