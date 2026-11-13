extends SceneTree
## Foto de um modelo (assets/models/<id>.glb: arma, personagem, prop) com a luz do jogo (WorldLighting,
## a mesma do world.gd) — o que o jogador vê, sem passar pelo menu. Também imprime se cada superfície usa
## a cor por vértice como albedo. Precisa de janela (não use --headless) e do --import feito antes:
##   godot --path . --resolution 420x900 --script res://tools/weapon_shot.gd -- w_rose_flame <saida.png> [3q]
##   godot --path . --resolution 900x900 --script res://tools/weapon_shot.gd -- knight <saida.png>

var _frames := 0
var _out := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var id: String = args[0]
	_out = args[1]
	WorldLighting.build(root)               # a mesma luz do world.gd (céu, ambiente, ACES, sol, contraluz)

	var w := (load("res://assets/models/%s.glb" % id) as PackedScene).instantiate() as Node3D
	WeaponModel.use_vertex_color(w)          # o mesmo ajuste que o jogo faz ao equipar
	root.add_child(w)
	if "3q" in args:
		w.rotation_degrees.y = -35.0
	_weapon = w


var _weapon: Node3D


func _frame_camera() -> void:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in _weapon.find_children("*", "MeshInstance3D", true, false):
		var m := mi.mesh
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s) as BaseMaterial3D
			var has_col: bool = (m.surface_get_format(s) & Mesh.ARRAY_FORMAT_COLOR) != 0
			print("SURF %s/%d vertex_color=%s albedo_from_vc=%s vc_srgb=%s albedo=%s" % [mi.name, s, has_col,
				mat.vertex_color_use_as_albedo if mat else "-", mat.vertex_color_is_srgb if mat else "-",
				mat.albedo_color if mat else "-"])
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var vp := root.get_visible_rect().size
	cam.size = maxf(box.size.y, box.size.x * vp.y / vp.x) * 1.04   # tamanho = altura visível
	cam.position = Vector3(box.get_center().x, box.get_center().y, box.end.z + 3.0)
	root.add_child(cam)
	cam.current = true


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_frame_camera()
	if _frames < 12:
		return false
	root.get_texture().get_image().save_png(_out)
	print("SHOT ", _out)
	return true
