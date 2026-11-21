extends Node3D
## Folha de contato do combo de espada com escudo (KnightMovesShield): uma fileira por golpe, oito instantes
## cada. Com os .fbx do Mixamo, desenha por cima de cada cavaleiro o esqueleto de referência (linhas vermelhas,
## na escala do cavaleiro), para comparar o retarget. Precisa de janela (sem --headless) e do --import feito:
##   godot --path . --resolution 2400x1600 res://tools/shield_combo_shot.tscn -- <saida.png> [vista=<graus>] [combo.fbx giro.fbx]
## vista = de onde se olha (0 = de frente, 90 = do lado esquerdo dele, 180 = de trás); padrão 35.

const KNIGHT := preload("res://assets/models/knight.glb")
const MixamoClip := preload("res://tools/mixamo_clip.gd")
const RETARGET := preload("res://tools/retarget_shield_combo.gd")
const TIMES := [0.0, 0.15, 0.3, 0.42, 0.55, 0.7, 0.85, 1.0]
const GAP := 1.8
const W := 2400
const ROW_H := 400
const BONES := [["Hips", "Spine2"], ["Spine2", "Neck"], ["Neck", "Head"], ["Neck", "RightArm"], ["RightArm", "RightForeArm"],
	["RightForeArm", "RightHand"], ["Neck", "LeftArm"], ["LeftArm", "LeftForeArm"], ["LeftForeArm", "LeftHand"],
	["Hips", "RightUpLeg"], ["RightUpLeg", "RightLeg"], ["RightLeg", "RightFoot"], ["Hips", "LeftUpLeg"],
	["LeftUpLeg", "LeftLeg"], ["LeftLeg", "LeftFoot"], ["RightHandPinky1", "RightHandIndex1"]]

var _frames := 0
var _out := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://shield_combo_shot.png"
	var view := 35.0
	var fbx := []
	for a in args.slice(1):
		if a.begins_with("vista="):
			view = float(a.substr(6))
		elif a.ends_with(".fbx"):
			fbx.append(a)
	var clips := []
	for path in fbx:
		var c := MixamoClip.new()
		if c.load_fbx(path, self):
			clips.append(c)
	WorldLighting.build(self)
	var rows: int = KnightMovesShield.TRACKS.size()
	for row in rows:
		for i in TIMES.size():
			var holder := Node3D.new()
			holder.position = Vector3(i * GAP + row * 100.0, 0, 0)
			holder.rotation.y = deg_to_rad(view)
			add_child(holder)
			var m := KNIGHT.instantiate() as Node3D
			holder.add_child(m)
			var lk := KnightLook.apply(m, {"weapon": "knight_blade", "offhand": "knight_shield", "armor": "royal_plate",
				"head": "knight_helm", "hands": "iron_gauntlets", "feet": "iron_greaves"})
			var r := KnightAnim.rig(m)
			var p := KnightAnim.idle_pose(0.0)
			KnightAnim.shield_combo_pose(p, row + 1, TIMES[i], 0.0)
			KnightAnim.hips_follow(p)
			for _k in 3:
				KnightAnim.apply(r, p, 1.0)
			KnightAnim.hold_weapon_upright(lk, r)
			if clips.size() == 2:
				var seg: Array = RETARGET.SEGMENTS[row]
				var g := log((float(seg[2]) - float(seg[1])) / (float(seg[3]) - float(seg[1]))) / log(RETARGET.HIT_AT)
				var mt: float = seg[1] + (float(seg[3]) - float(seg[1])) * pow(TIMES[i], g)
				holder.add_child(_stick(clips[seg[0]], mt, (r.LegL as Node3D).global_position.y))
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
		cam.size = 2.5
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.position = Vector3((TIMES.size() - 1) * GAP / 2.0 + row * 100.0, 1.05, 8.0)
		vp.add_child(cam)
		cam.current = true


## Esqueleto do Mixamo no instante `t`, com o quadril sobre a origem e na altura `hip_y` do cavaleiro.
func _stick(c: MixamoClip, t: float, hip_y: float) -> MeshInstance3D:
	var gl := c.globals(t)
	var hips := c.pt(gl, "Hips")
	var hips_rest_y := 0.0
	for b in ["LeftUpLeg", "RightUpLeg"]:
		hips_rest_y += c.pt(c.globals(0.0), b).y * 0.5
	var s := hip_y / maxf(hips_rest_y, 0.01)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for pair in BONES:
		for n in pair:
			var v := c.pt(gl, n)
			im.surface_add_vertex(Vector3((v.x - hips.x) * s, v.y * s, (v.z - hips.z) * s))
	im.surface_end()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.15, 0.1)
	mat.no_depth_test = true
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = mat
	return mi


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 14:
		return
	var rows: int = KnightMovesShield.TRACKS.size()
	var img := Image.create(W, ROW_H * rows, false, Image.FORMAT_RGBA8)
	for vp: SubViewport in find_children("*", "SubViewport", false, false):
		var part := vp.get_texture().get_image()
		part.convert(Image.FORMAT_RGBA8)
		img.blit_rect(part, Rect2i(Vector2i.ZERO, part.get_size()), Vector2i(0, ROW_H * int(vp.get_meta("row"))))
	img.save_png(_out)
	print("SHOT ", _out)
	get_tree().quit()
