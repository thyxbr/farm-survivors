extends SceneTree
## Foto de uma arma (assets/models/<id>.glb) com o mesmo céu, sol e tonemap do world.gd — o que o
## jogador vê, sem passar pelo menu. Também imprime se a superfície usa a cor por vértice como albedo.
## Precisa de janela (não use --headless) e do --import feito antes:
##   godot --path . --resolution 420x900 --script res://tools/weapon_shot.gd -- w_rose_flame <saida.png> [3q]

var _frames := 0
var _out := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var id: String = args[0]
	_out = args[1]
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.28, 0.48, 0.82)
	sm.sky_horizon_color = Color(0.72, 0.8, 0.9)
	sm.ground_horizon_color = Color(0.72, 0.8, 0.9)
	sm.ground_bottom_color = Color(0.25, 0.3, 0.25)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.95, 0.86)
	root.add_child(sun)

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
