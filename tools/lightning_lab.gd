extends Node3D
## Laboratório do Raio e Onda de Choque (LightningShockwaveFX): palco escuro com grade, como o da referência, um
## cavaleiro no meio e a câmera na mesma altura e distância.
##   godot --path . res://tools/lightning_lab.tscn
##   Espaço  solta o efeito   L  câmera lenta   N  dia / noite
## Com `-- --lseq=<pasta>` grava 46 quadros (o efeito sai no quadro 8, como na referência) e fecha; rode com
## `--fixed-fps 30` para os quadros baterem com os da referência. `--noon` grava de dia.

const KNIGHT := preload("res://assets/models/knight.glb")

var _model: Node3D
var _env: Environment
var _sun: DirectionalLight3D
var _noon := false
var _slow := false


func _ready() -> void:
	var seq := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lseq="):
			seq = a.substr(7)
		elif a == "--noon":
			_noon = true
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.glow_enabled = true
	_env.glow_intensity = 0.7
	_env.glow_bloom = 0.08
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation = Vector3(-0.9, 0.5, 0.0)
	add_child(_sun)
	_light()

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	var gm := StandardMaterial3D.new()
	var img := Image.create(2, 2, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, Color(0.16, 0.2, 0.3))
	img.set_pixel(1, 1, Color(0.16, 0.2, 0.3))
	img.set_pixel(1, 0, Color(0.11, 0.14, 0.22))
	img.set_pixel(0, 1, Color(0.11, 0.14, 0.22))
	gm.albedo_texture = ImageTexture.create_from_image(img)
	gm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	gm.uv1_scale = Vector3(30, 30, 1)
	gm.roughness = 0.9
	pm.material = gm
	ground.mesh = pm
	add_child(ground)

	_model = KNIGHT.instantiate() as Node3D
	add_child(_model)

	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.position = Vector3(0.0, 5.4, 8.6)
	cam.look_at(Vector3(0.0, 0.5, 0.0))
	cam.current = true

	if seq != "":
		_record(seq)


func _light() -> void:
	if _noon:
		_env.background_color = Color(0.5, 0.62, 0.78)
		_env.ambient_light_color = Color(0.75, 0.8, 0.9)
		_env.ambient_light_energy = 0.9
		_sun.light_energy = 1.3
	else:
		_env.background_color = Color(0.0, 0.005, 0.015)
		_env.ambient_light_color = Color(0.25, 0.32, 0.5)
		_env.ambient_light_energy = 0.35
		_sun.light_energy = 0.25


func _cast() -> void:
	LightningShockwaveFX.cast(self, Transform3D.IDENTITY, 3.8, _model)


func _record(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for i in 20:      # espera os shaders compilarem
		await get_tree().process_frame
	# aquece: um efeito fora da gravação (compila os materiais), e espera acabar
	_cast()
	for i in 50:
		await get_tree().process_frame
	seed(7)
	for i in 46:
		if i == 8:
			_cast()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%03d.png" % [dir, i])
	get_tree().quit()


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_SPACE:
				_cast()
			KEY_L:
				_slow = not _slow
				Engine.time_scale = 0.2 if _slow else 1.0
			KEY_N:
				_noon = not _noon
				_light()
