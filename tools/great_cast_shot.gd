extends "res://tools/shield_combo_shot.gd"
## Folha de contato da Lâmina Suprema (KnightMovesGreatCast): uma fileira por fase (erguer, segurar, cortar, ajoelhado,
## levantar), oito instantes cada, cada fase emendada na anterior como no jogo. Com o .fbx do Mixamo ("Great Sword
## Casting"), desenha por cima de cada cavaleiro o esqueleto de referência. Precisa de janela (sem --headless):
##   godot --path . --resolution 2400x2000 res://tools/great_cast_shot.tscn -- <saida.png> [vista=<graus>] [casting.fbx]

const CAST_RETARGET := preload("res://tools/retarget_great_casting.gd")


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://great_cast_shot.png"
	var view := 35.0
	var clip: MixamoClip = null
	for a in args.slice(1):
		if a.begins_with("vista="):
			view = float(a.substr(6))
		elif a.ends_with(".fbx"):
			clip = MixamoClip.new()
			if not clip.load_fbx(a, self):
				clip = null
	WorldLighting.build(self)
	var rows: int = KnightMovesGreatCast.TRACKS.size()
	for row in rows:
		for i in TIMES.size():
			var holder := Node3D.new()
			holder.position = Vector3(i * GAP + row * 100.0, 0, 0)
			holder.rotation.y = deg_to_rad(view)
			add_child(holder)
			var m := KNIGHT.instantiate() as Node3D
			holder.add_child(m)
			var lk := KnightLook.apply(m, {"weapon": "eclipse_greatsword", "armor": "royal_plate", "head": "knight_helm",
				"hands": "iron_gauntlets", "feet": "iron_greaves"})
			var r := KnightAnim.rig(m)
			var p := KnightAnim.idle_pose(0.0)
			KnightAnim.great_carry(p, 0.0, 0.0)
			KnightAnim.great_cast_pose(p, row, TIMES[i], {}, 0.0)
			KnightAnim.hips_follow(p)
			for _k in 3:
				KnightAnim.apply(r, p, 1.0)
			KnightAnim.hold_weapon_upright(lk, r)
			if clip:
				var ph: Array = CAST_RETARGET.PHASES[row]
				holder.add_child(_stick(clip, lerpf(ph[0], ph[1], TIMES[i]), (r.LegL as Node3D).global_position.y))
	var gm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(TIMES.size() * GAP + rows * 100.0, 0.02, 40.0)
	gm.mesh = bm
	gm.position = Vector3(rows * 50.0, -0.01, 0.0)
	add_child(gm)
	for row in rows:
		var vp := SubViewport.new()
		vp.size = Vector2i(W, ROW_H)
		vp.world_3d = get_viewport().world_3d
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.set_meta("row", row)
		add_child(vp)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 3.6
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.position = Vector3((TIMES.size() - 1) * GAP / 2.0 + row * 100.0, 1.5, 8.0)
		vp.add_child(cam)
		cam.current = true


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 14:
		return
	var rows: int = KnightMovesGreatCast.TRACKS.size()
	var img := Image.create(W, ROW_H * rows, false, Image.FORMAT_RGBA8)
	for vp: SubViewport in find_children("*", "SubViewport", false, false):
		var part := vp.get_texture().get_image()
		part.convert(Image.FORMAT_RGBA8)
		img.blit_rect(part, Rect2i(Vector2i.ZERO, part.get_size()), Vector2i(0, ROW_H * int(vp.get_meta("row"))))
	img.save_png(_out)
	print("SHOT ", _out)
	get_tree().quit()
