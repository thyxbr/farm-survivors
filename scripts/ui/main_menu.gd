extends Control
## Menu principal com uma pequena cena 3D girando ao fundo.

const OPTIONS := preload("res://scripts/ui/options_panel.gd")

var pivot: Node3D
var menu_box: VBoxContainer


func _ready() -> void:
	theme = UITheme.get_theme()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	_build_backdrop()

	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.85))
	g.set_color(1, Color(0, 0, 0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(1, 0)
	var fade := TextureRect.new()
	fade.texture = gt
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.anchor_right = 0.6
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)

	menu_box = VBoxContainer.new()
	menu_box.anchor_top = 0.5
	menu_box.anchor_bottom = 0.5
	menu_box.offset_left = 90
	menu_box.offset_top = -230
	menu_box.offset_right = 560
	menu_box.offset_bottom = 230
	menu_box.add_theme_constant_override("separation", 12)
	add_child(menu_box)
	var title := UITheme.label("Ecos de Valdoria", 64, UITheme.GOLD)
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0))
	menu_box.add_child(title)
	menu_box.add_child(UITheme.label("Um RPG de ação — protótipo", 20, UITheme.DIM))
	var sp := Control.new()
	sp.custom_minimum_size.y = 24
	menu_box.add_child(sp)
	var new_btn := UITheme.button("Novo jogo", _new_game, 320)
	menu_box.add_child(new_btn)
	var cont := UITheme.button("Continuar", func() -> void: Game.load_game(), 320)
	cont.disabled = not Game.has_save()
	menu_box.add_child(cont)
	if Game.has_save():
		menu_box.add_child(UITheme.label("   " + Game.save_info(), 15, UITheme.DIM))
	menu_box.add_child(UITheme.button("Opções", _options, 320))
	menu_box.add_child(UITheme.button("Sair", func() -> void: get_tree().quit(), 320))
	(cont if not cont.disabled else new_btn).grab_focus.call_deferred()

	var credit := UITheme.label("Feito com Godot 4 · modelos low-poly criados no Blender", 14, UITheme.DIM)
	credit.anchor_top = 1.0
	credit.anchor_bottom = 1.0
	credit.offset_left = 24
	credit.offset_top = -36
	add_child(credit)


func _new_game() -> void:
	Sfx.play("click", 0.0)
	Game.start_new_game()


func _options() -> void:
	menu_box.visible = false
	var o := OPTIONS.new()
	add_child(o)
	o.closed.connect(func() -> void: menu_box.visible = true)


func _process(delta: float) -> void:
	if pivot:
		pivot.rotation.y += delta * 0.12


func _build_backdrop() -> void:
	var svc := SubViewportContainer.new()
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X
	svc.add_child(vp)
	var root := Node3D.new()
	vp.add_child(root)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.12, 0.15, 0.35)
	sm.sky_horizon_color = Color(0.85, 0.5, 0.35)
	sm.ground_horizon_color = Color(0.85, 0.5, 0.35)
	sm.ground_bottom_color = Color(0.1, 0.1, 0.1)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.8, 0.5, 0.4)
	env.fog_density = 0.02
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-20, 60, 0)
	sun.light_color = Color(1, 0.7, 0.5)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	root.add_child(sun)

	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 30
	disc.bottom_radius = 30
	disc.height = 0.1
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.25, 0.4, 0.15)
	disc.material = gm
	ground.mesh = disc
	ground.position.y = -0.05
	root.add_child(ground)

	pivot = Node3D.new()
	root.add_child(pivot)
	var knight: Node3D = load("res://assets/models/knight.glb").instantiate()
	knight.rotation.y = 0.5
	pivot.add_child(knight)
	var arm := knight.find_child("ArmR", true, false) as Node3D
	if arm:
		arm.rotation.x = -1.2
	var gob: Node3D = load("res://assets/models/goblin.glb").instantiate()
	gob.position = Vector3(2.5, 0, 2.0)
	gob.rotation.y = -2.4
	gob.scale = Vector3.ONE * 1.6
	pivot.add_child(gob)
	var slime: Node3D = load("res://assets/models/slime.glb").instantiate()
	slime.position = Vector3(-1.2, 0, -2.2)
	slime.rotation.y = 2.5
	pivot.add_child(slime)
	var fire: Node3D = load("res://assets/models/campfire.glb").instantiate()
	fire.position = Vector3(0.8, 0, -1.5)
	pivot.add_child(fire)
	var fl := OmniLight3D.new()
	fl.position = Vector3(0.8, 1.0, -1.5)
	fl.light_color = Color(1, 0.55, 0.2)
	fl.light_energy = 2.5
	fl.omni_range = 8
	pivot.add_child(fl)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 26:
		var a := rng.randf() * TAU
		var d := rng.randf_range(8, 22)
		var t: Node3D = load("res://assets/models/tree_pine.glb" if rng.randf() < 0.6 else "res://assets/models/tree_oak.glb").instantiate()
		t.position = Vector3(cos(a) * d, 0, sin(a) * d)
		t.scale = Vector3.ONE * rng.randf_range(0.9, 1.6)
		pivot.add_child(t)
	var cam := Camera3D.new()
	cam.position = Vector3(-3.2, 1.9, 6.0)
	cam.fov = 50
	root.add_child(cam)
	cam.look_at(Vector3(1.0, 1.1, 0), Vector3.UP)
