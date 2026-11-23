extends Node3D
## Laboratório dos três efeitos sombrios pintados, cada um no enquadramento da referência dele:
##   godot --path . res://tools/shadow_lab.tscn -- --fx=hole     Buraco Negro (BlackHoleFX)
##   godot --path . res://tools/shadow_lab.tscn -- --fx=orb      Esfera Sombria (ShadowOrbFX)
##   godot --path . res://tools/shadow_lab.tscn -- --fx=blades   Lâminas Rúnicas (RuneBladesFX)
##   godot --path . res://tools/shadow_lab.tscn -- --fx=boom     Explosão de fogo (ExplosionFX via FXToon.fire_burst)
##   godot --path . res://tools/shadow_lab.tscn -- --fx=boomdark Explosão sombria dos monstros (FXToon.blast)
##   Espaço  repete (lâminas, explosão)   N  dia / noite   L  câmera lenta
## Com `--seq=<pasta>` grava os quadros e fecha (rode com `--fixed-fps 30`); `--noon` grava de dia.

const KNIGHT := preload("res://assets/models/knight.glb")
const FRAMES := {"hole": 60, "orb": 34, "blades": 110, "boom": 44, "boomdark": 44}
const BLADE_SPEED := 17.0
const TARGET := Vector3(0.0, 0.0, -15.0)

var _fx := "hole"
var _env: Environment
var _sun: DirectionalLight3D
var _noon := false
var _slow := false
var _flying: Array = []     # [{"node", "dir", "left"}]


func _ready() -> void:
	var seq := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fx="):
			_fx = a.substr(5)
		elif a.begins_with("--seq="):
			seq = a.substr(6)
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
	pm.size = Vector2(80, 80)
	var gm := StandardMaterial3D.new()
	var img := Image.create(2, 2, false, Image.FORMAT_RGB8)
	var a := Color(0.3, 0.3, 0.32) if _fx == "hole" else Color(0.45, 0.55, 0.7) if _fx == "orb" else Color(0.16, 0.2, 0.3)
	var b := a * 0.78
	img.set_pixel(0, 0, a)
	img.set_pixel(1, 1, a)
	img.set_pixel(1, 0, b)
	img.set_pixel(0, 1, b)
	gm.albedo_texture = ImageTexture.create_from_image(img)
	gm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	gm.uv1_scale = Vector3(40, 40, 1)
	gm.roughness = 0.9
	pm.material = gm
	ground.mesh = pm
	add_child(ground)

	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	match _fx:
		"hole":
			var h := BlackHoleFX.new()
			h.radius = 3.0
			add_child(h)
			cam.position = Vector3(0.0, 3.4, 8.6)
			cam.look_at(Vector3(0.0, -0.4, 0.0))
		"boom", "boomdark":
			cam.position = Vector3(0.0, 2.6, 8.0)
			cam.look_at(Vector3(0.0, 1.3, 0.0))
		"orb":
			var o := ShadowOrbFX.new()
			o.radius = 1.0
			add_child(o)
			o.position = Vector3(0.0, 1.7, 0.0)
			cam.position = Vector3(0.0, 1.9, 6.6)
			cam.look_at(Vector3(0.0, 1.5, 0.0))
		_:
			var m := KNIGHT.instantiate() as Node3D
			add_child(m)
			m.position = TARGET
			cam.position = Vector3(-0.6, 5.2, 7.5)
			cam.look_at(Vector3(0.6, 0.6, -6.0))
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


## A explosão pelas funções do jogo: a de fogo (bola de fogo do jogador) ou a sombria dos monstros.
func _boom() -> void:
	if _fx == "boomdark":
		FXToon.blast(Vector3.ZERO, 3.6)
	else:
		FXToon.fire_burst(Vector3(0.0, 1.3, 0.0), 1.2)


## Seis lâminas em leque perto da câmera; nascem, miram e disparam uma a uma no cavaleiro lá longe.
func _blades() -> void:
	var pts: Array = []
	var dirs: Array = []
	for i in 6:
		var p := Vector3(-0.2 + i * 0.55, 1.0 + 0.12 * (i % 2), 0.9 - absf(i - 2.5) * 0.25)
		pts.append(p)
		dirs.append((TARGET + Vector3.UP * 1.0 - p).normalized())
	var time := 1.5
	RuneBladesFX.charge(self, pts, dirs, time)
	await get_tree().create_timer(time).timeout
	for i in 6:
		var b := RuneBladesFX.make_blade()
		add_child(b)
		b.global_position = pts[i]
		b.global_basis = RuneBladesFX.basis_along(dirs[i])
		_flying.append({"node": b, "dir": dirs[i], "left": (TARGET + Vector3.UP - pts[i]).length(), "wait": i * 0.16})


func _process(delta: float) -> void:
	for f in _flying.duplicate():
		if f.wait > 0.0:
			f.wait -= delta
			continue
		var n: Node3D = f.node
		n.global_position += f.dir * BLADE_SPEED * delta
		f.left -= BLADE_SPEED * delta
		if f.left <= 0.0:
			RuneBladesFX.impact(self, n.global_position)
			n.queue_free()
			_flying.erase(f)


func _record(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for i in 30:      # espera os shaders compilarem
		await get_tree().process_frame
	if _fx == "blades":   # aquece: uma lâmina e um acerto fora da gravação
		RuneBladesFX.impact(self, Vector3(0, -50, 0))
		for i in 10:
			await get_tree().process_frame
	seed(7)
	for i in int(FRAMES.get(_fx, 60)):
		if i == 4 and _fx == "blades":
			_blades()
		if i == 4 and _fx.begins_with("boom"):
			_boom()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%03d.png" % [dir, i])
	get_tree().quit()


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_SPACE:
				if _fx == "blades":
					_blades()
				elif _fx.begins_with("boom"):
					_boom()
			KEY_L:
				_slow = not _slow
				Engine.time_scale = 0.2 if _slow else 1.0
			KEY_N:
				_noon = not _noon
				_light()
