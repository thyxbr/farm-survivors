extends SceneTree
## Mede o clipe "Great Sword Casting" do Mixamo: a cada 0,1 s a altura do quadril, o centro das mãos (relativo ao
## meio dos ombros) e a direção da lâmina estimada pela mão. Serviu para achar as fases (erguer, segurar, cortar)
## de tools/retarget_great_casting.gd.
##   godot --headless --path . --script res://tools/great_casting_probe.gd -- <great_sword_casting.fbx>
const MixamoClip := preload("res://tools/mixamo_clip.gd")

func _init() -> void:
	var root := Node.new()
	get_root().add_child.call_deferred(root)
	await process_frame
	var clip := MixamoClip.new()
	if not clip.load_fbx(OS.get_cmdline_user_args()[0], root):
		quit(1)
		return
	print("duração %.2f s" % clip.anim.length)
	var t := 0.0
	while t <= clip.anim.length + 0.001:
		var g := clip.globals(t)
		var mid := (clip.pt(g, "RightArm") + clip.pt(g, "LeftArm")) * 0.5
		var hands := (clip.pt(g, "RightHand") + clip.pt(g, "LeftHand")) * 0.5 - mid
		var ax := Vector3.ZERO
		for s in ["Right", "Left"]:
			ax += (clip.pt(g, s + "HandIndex1") - clip.pt(g, s + "HandPinky1")).normalized()
		print("t=%.2f hips(%.2f,%.2f,%.2f) mãos%s lâmina%s" % [t, clip.pt(g, "Hips").x, clip.pt(g, "Hips").y,
			clip.pt(g, "Hips").z, _v(hands), _v(ax.normalized())])
		t += 0.1
	quit()

func _v(v: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]
