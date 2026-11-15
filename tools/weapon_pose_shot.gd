extends Node3D
## Folha de contato das poses com cajado e arco: parado, andando (dois instantes do passo), golpes do cajado,
## mira do arco, tensão cheia e soltura. Três fileiras: frente em 3/4, de lado e de trás (visão da câmera do
## jogo, por cima do ombro). Precisa de janela (sem --headless) e do --import feito antes:
##   godot --path . --resolution 1900x1350 res://tools/weapon_pose_shot.tscn -- <saida.png> [cajado|arco] [roupa] [c=<coluna>]

const KNIGHT := preload("res://assets/models/knight.glb")
const STAFF_POSES := ["parado", "cajado 1 preparo", "cajado 1 meio", "cajado 1 mira", "cajado 1 coice", "cajado 2 preparo", "cajado 3 alto", "cajado 3 mira"]
const BOW_POSES := ["parado", "andando A", "andando B", "mirando", "puxando", "tenso", "andando tenso", "soltou"]
const GAP := 1.35
const ROW_H := 450
const VIEWS := [35.0, 90.0, 180.0]

var _frames := 0
var _out := ""
var _names: Array = []
var _bow := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://weapon_pose_shot.png"
	_bow = "arco" in args
	_names = BOW_POSES if _bow else STAFF_POSES
	var plate := not ("roupa" in args)
	WorldLighting.build(self)
	for row in VIEWS.size():
		for i in _names.size():
			var m := KNIGHT.instantiate() as Node3D
			add_child(m)
			m.position = Vector3(i * GAP + row * 100.0, 0, 0)
			m.rotation.y = deg_to_rad(VIEWS[row])
			var look := {"weapon": "hunter_bow" if _bow else "apprentice_staff"}
			if plate:
				look.merge({"armor": "royal_plate", "head": "knight_helm", "hands": "iron_gauntlets", "feet": "iron_greaves"})
			var lk := KnightLook.apply(m, look)
			var r := KnightAnim.rig(m)
			_pose(r, lk, _names[i])
	var g := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(_names.size() * GAP + 302.0, 0.02, 40.0)
	g.mesh = bm
	g.position = Vector3(100.0, -0.01, 0.0)
	add_child(g)
	for row in VIEWS.size():
		var vp := SubViewport.new()
		vp.size = Vector2i(1900, ROW_H)
		vp.world_3d = get_viewport().world_3d
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.set_meta("row", row)
		add_child(vp)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 2.6
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.position = Vector3((_names.size() - 1) * GAP / 2.0 + row * 100.0, 1.1, 8.0)
		for a in args:   # c=<coluna>: aproxima a câmera dessa coluna (e das vizinhas)
			if a.begins_with("c="):
				cam.size = 1.1
				cam.position = Vector3(float(a.substr(2)) * GAP + row * 100.0, 1.35, 8.0)
		vp.add_child(cam)
		cam.current = true


func _pose(r: Dictionary, lk: Dictionary, kind: String) -> void:
	var cls := "bow" if _bow else "staff"
	var p := KnightAnim.idle_pose(0.0)
	var move := 0.0
	match kind:
		"andando A", "andando B", "andando tenso", "correndo":
			move = 1.0
			var ph := 0.0 if kind != "andando B" else PI * 0.5
			p = KnightAnim.locomotion_pose(r, ph, move, 1.0 if kind == "correndo" else 0.0)
	KnightAnim.weapon_carry(p, cls, move, 1.0 if kind == "correndo" else 0.0)
	var atk := true
	match kind:
		"cajado 1 preparo":
			KnightAnim.staff_pose(p, 1, 0.16, 0.0)
		"cajado 1 meio":
			KnightAnim.staff_pose(p, 1, 0.25, 0.0)
		"cajado 2 preparo":
			KnightAnim.staff_pose(p, 2, 0.16, 0.0)
		"cajado 3 mira":
			KnightAnim.staff_pose(p, 3, 0.36, 0.0)
		"cajado 1 mira":
			KnightAnim.staff_pose(p, 1, 0.34, 0.0)
		"cajado 1 coice":
			KnightAnim.staff_pose(p, 1, 0.48, 0.0)
		"cajado 3 alto":
			KnightAnim.staff_pose(p, 3, 0.22, 0.0)
		"magia":
			KnightAnim.cast_pose(p, "fireball", 0.3, 0.0, true)
		"mirando":
			KnightAnim.bow_draw_pose(p, 0.0)
		"puxando":
			KnightAnim.bow_draw_pose(p, 0.45)
		"tenso", "andando tenso":
			KnightAnim.bow_draw_pose(p, 1.0, move)
		"soltou":
			KnightAnim.bow_release_pose(p, 0.2, 0.0)
		_:
			atk = false
	if atk:
		KnightAnim.hips_follow(p)
	for _i in 2:   # a segunda vez: a altura do modelo usa as rotações já aplicadas
		KnightAnim.apply(r, p, 1.0)
	KnightAnim.hold_weapon_upright(lk, r)
	if lk.get("arrow"):
		lk.arrow.visible = kind in ["mirando", "puxando", "tenso", "andando tenso"]
	KnightAnim.bow_string(lk, r)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 14:
		return
	var img := Image.create(1900, ROW_H * VIEWS.size(), false, Image.FORMAT_RGBA8)
	for vp: SubViewport in find_children("*", "SubViewport", false, false):
		var part := vp.get_texture().get_image()
		part.convert(Image.FORMAT_RGBA8)
		img.blit_rect(part, Rect2i(Vector2i.ZERO, part.get_size()), Vector2i(0, ROW_H * int(vp.get_meta("row"))))
	img.save_png(_out)
	print("SHOT ", _out)
	get_tree().quit()
