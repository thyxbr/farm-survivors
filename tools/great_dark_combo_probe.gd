extends SceneTree
## Mede os clipes do combo sombrio da montante (Mixamo "Great Sword Slide Attack", "Great Sword Slash", "Great Sword
## Slash (1)", "Great Sword High Spin Attack"): a cada 0,05 s o quadril (deslocamento e giro), o centro das mãos
## relativo ao quadril e a velocidade das mãos (o pico marca o golpe). Serviu para achar [início, acerto, fim] de
## tools/retarget_great_dark_combo.gd.
##   godot --headless --path . --script res://tools/great_dark_combo_probe.gd -- <clipe.fbx>
const MixamoClip := preload("res://tools/mixamo_clip.gd")

func _init() -> void:
	var root := Node.new()
	get_root().add_child.call_deferred(root)
	await process_frame
	for path in OS.get_cmdline_user_args():
		var clip := MixamoClip.new()
		if not clip.load_fbx(path, root):
			quit(1)
			return
		print("== %s duração %.2f s" % [path.get_file(), clip.anim.length])
		var t := 0.0
		var prev := Vector3.ZERO
		while t <= clip.anim.length + 0.001:
			var g := clip.globals(t)
			var hips := clip.pt(g, "Hips")
			var hands := (clip.pt(g, "RightHand") + clip.pt(g, "LeftHand")) * 0.5
			var yaw := clip.q(g, "Hips").get_euler(EULER_ORDER_YXZ).y
			var spd := (hands - prev).length() / 0.05 if t > 0.0 else 0.0
			prev = hands
			print("t=%.2f hips(%.1f,%.1f,%.1f) yaw=%4.0f mãos-quadril%s vel=%.0f" % [t, hips.x, hips.y, hips.z,
				rad_to_deg(yaw), _v(hands - hips), spd])
			t += 0.05
	quit()

func _v(v: Vector3) -> String:
	return "(%.0f,%.0f,%.0f)" % [v.x, v.y, v.z]
