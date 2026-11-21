extends SceneTree
## Mede o clipe "Sword And Shield Impact" do Mixamo (assets/animations/mixamo/sword_shield_impact.fbx): posição de
## cada osso no espaço do esqueleto (+Z à frente, +X à esquerda) em alguns instantes, compondo as trilhas de
## rotação com o repouso. Os números viraram KnightMoves.AEGIS_GUARD (mão/cotovelo menos ombro, giro do peito).
##   godot --headless --path . --script res://tools/aegis_probe.gd
func _init() -> void:
	var sc: PackedScene = load("res://assets/animations/mixamo/sword_shield_impact.fbx")
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
	var show := ["Hips", "UpperChest", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"]
	for t in [0.0, 0.1, 0.17, 0.23, 0.3, 0.4, 0.5, 0.6, 0.76]:
		var g := {}
		var line := "t=%.2f" % t
		for i in sk.get_bone_count():
			var n := sk.get_bone_name(i)
			var l := sk.get_bone_rest(i)
			if rot.has(n): l.basis = Basis(an.rotation_track_interpolate(rot[n], t)).scaled(l.basis.get_scale())
			if pos.has(n): l.origin = an.position_track_interpolate(pos[n], t)
			var par := sk.get_bone_parent(i)
			g[i] = (g[par] * l) if par >= 0 else l
		for n in show:
			var p: Vector3 = g[sk.find_bone(n)].origin
			line += " %s(%.2f,%.2f,%.2f)" % [n.replace("Upper", "U").replace("Lower", "L"), p.x, p.y, p.z]
		var hb: Basis = g[sk.find_bone("Hips")].basis
		var cb: Basis = g[sk.find_bone("UpperChest")].basis
		line += " hipsFwd=%s chestFwd=%s" % [hb.z.normalized(), cb.z.normalized()]
		print(line)
	quit()
