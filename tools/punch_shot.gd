extends Node3D
## Folha de contato do soco sem arma (KnightMoves.PUNCH): guarda, jab, direto, carga e acerto do uppercut.
## Duas fileiras: de frente em 3/4 e de lado. Precisa de janela (sem --headless) e do --import feito antes:
##   godot --path . --resolution 1900x900 res://tools/punch_shot.tscn -- <saida.png> [roupa]
## roupa = camisa, calça e sapatos padrão em vez da armadura de placas.

const KNIGHT := preload("res://assets/models/knight.glb")
const NAMES := ["guarda", "jab", "direto", "uppercut (carga)", "uppercut"]
const GAP := 1.7
const ROW_H := 450

var _frames := 0
var _out := ""
var _report: Array = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://pose_shot.png"
	var plate := not ("roupa" in args)
	WorldLighting.build(self)
	for row in 2:
		for i in NAMES.size():
			var m := KNIGHT.instantiate() as Node3D
			add_child(m)
			m.position = Vector3(i * GAP + row * 100.0, 0, 0)
			m.rotation.y = deg_to_rad(35.0) if row == 0 else deg_to_rad(90.0)
			var look := {"weapon": ""}
			if plate:
				look.merge({"armor": "royal_plate", "head": "knight_helm", "hands": "iron_gauntlets", "feet": "iron_greaves"})
			var lk := KnightLook.apply(m, look)
			var r := KnightAnim.rig(m)
			_pose(r, lk, NAMES[i])
			if row == 0:
				_report.append([NAMES[i], r])
	var g := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(NAMES.size() * GAP + 202.0, 0.02, 40.0)
	g.mesh = bm
	g.position = Vector3(50.0, -0.01, 0.0)
	add_child(g)
	for row in 2:
		var vp := SubViewport.new()
		vp.size = Vector2i(1900, ROW_H)
		vp.world_3d = get_viewport().world_3d
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.set_meta("row", row)
		add_child(vp)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 2.4
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.position = Vector3((NAMES.size() - 1) * GAP / 2.0 + row * 100.0, 1.0, 8.0)
		vp.add_child(cam)
		cam.current = true


func _pose(r: Dictionary, _lk: Dictionary, kind: String) -> void:
	var p := KnightAnim.idle_pose(0.0)
	match kind:
		"guarda":
			KnightAnim.punch_pose(p, 1, 0.2, 0.0)
		"jab":
			KnightAnim.punch_pose(p, 1, 0.42, 0.0)
		"direto":
			KnightAnim.punch_pose(p, 2, 0.42, 0.0)
		"uppercut (carga)":
			KnightAnim.punch_pose(p, 3, 0.24, 0.0)
		"uppercut":
			KnightAnim.punch_pose(p, 3, 0.42, 0.0)
	KnightAnim.hips_follow(p)
	for _i in 2:
		KnightAnim.apply(r, p, 1.0)


func _lowest(ankle: Node3D) -> float:
	var best := 99.0
	for mi: MeshInstance3D in ankle.find_children("*", "MeshInstance3D", true, false):
		if not mi.visible or mi.mesh == null:
			continue
		for v: Vector3 in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			best = minf(best, (mi.global_transform * v).y)
	return best


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 2:
		for e in _report:
			var r: Dictionary = e[1]
			print("%-16s pé E %.3f  pé D %.3f  quadril %.3f" % [e[0], _lowest(r.AnkleL), _lowest(r.AnkleR),
				(r.LegL as Node3D).global_position.y])
	if _frames < 14:
		return
	var img := Image.create(1900, ROW_H * 2, false, Image.FORMAT_RGBA8)
	for vp: SubViewport in find_children("*", "SubViewport", false, false):
		var part := vp.get_texture().get_image()
		part.convert(Image.FORMAT_RGBA8)
		img.blit_rect(part, Rect2i(Vector2i.ZERO, part.get_size()), Vector2i(0, ROW_H * int(vp.get_meta("row"))))
	img.save_png(_out)
	print("SHOT ", _out)
	get_tree().quit()
