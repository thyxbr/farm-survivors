extends Node3D
## Galeria das espadas modeladas (assets/models/w_*.glb) com a luz do jogo, na ordem da folha de conceito.
## godot --path . res://tools/godot/weapon_gallery.tscn -- --gallery=<saida.png>   (sem argumento fica aberta)

const ORDER := [
	["w_rose_flame", "w_thorn_root", "w_crystal_frost", "w_azure_edge", "w_moon_crescent", "w_royal_wings", "w_venom_leaf"],
	["w_neon_edge", "w_titan_cleaver", "w_amber_fang", "w_coral_spine", "w_ivory_wing", "w_scarlet_talon", "w_crimson_reed",
		"w_pale_crescent"],
]


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.96, 0.96, 0.97)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.85)
	e.ambient_light_energy = 0.35
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-35), deg_to_rad(-30), 0)
	sun.light_energy = 1.0
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-10), deg_to_rad(150), 0)
	fill.light_energy = 0.35
	add_child(fill)
	for r in ORDER.size():
		var row: Array = ORDER[r]
		for i in row.size():
			var path := "res://assets/models/%s.glb" % row[i]
			if not ResourceLoader.exists(path):
				continue
			var w := (load(path) as PackedScene).instantiate() as Node3D
			KnightLook.setup_model_materials(w)
			w.position = Vector3((i - (row.size() - 1) / 2.0) * 0.48, 0.3 - r * 1.75, 0)
			add_child(w)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 3.9
	cam.position = Vector3(0, -0.35, 5)
	add_child(cam)
	cam.current = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--gallery="):
			for k in 8:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(a.get_slice("=", 1))
			get_tree().quit()
