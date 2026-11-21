extends Node3D
## Laboratório de animação dos monstros: monta um Enemy de verdade (mesmo modelo e mesmo _animate do jogo), desliga
## a IA e roda a animação de um modo, salvando uma folha de quadros vista de lado e de 3/4.
##   godot --path . res://tools/monster_lab.tscn -- --kind=lobo_geada --mode=walk --out=lab.png [--frames=8] [--span=1.0]
## Modos: idle, walk (anda na velocidade do tipo), run (1,5x), attack (o ataque comum do tipo: lunge, swing, slam,
## shoot ou howl com --attack=<tipo>); span = segundos cobertos pela folha (para o ataque, a duração dele).

const W := 420
const H := 420

var kind := "lobo_geada"
var mode := "walk"
var out := "lab.png"
var frames := 8
var span := 1.0
var attack := ""
var e: Enemy
var cams: Array[Camera3D] = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--kind="):
			kind = a.substr(7)
		elif a.begins_with("--mode="):
			mode = a.substr(7)
		elif a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--frames="):
			frames = int(a.substr(9))
		elif a.begins_with("--span="):
			span = float(a.substr(7))
		elif a.begins_with("--attack="):
			attack = a.substr(9)
	get_window().size = Vector2i(W, H)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.24, 0.26, 0.3)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.72, 0.78)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.85, 0.88, 0.92)
	floor_mi.material_override = fm
	add_child(floor_mi)
	e = Enemy.new()
	e.kind = kind
	add_child(e)
	e.set_physics_process(false)
	e.set_process(false)
	e.model.rotation.y = 0.0          # frente do modelo = +Z
	for n in ["Bar", "NameTag"]:
		var c := e.find_child(n, true, false)
		if c:
			c.visible = false
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in e.model.find_children("*", "MeshInstance3D", true, false):
		var bb := mi.global_transform * mi.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	var hgt := box.get_center().y * 2.0
	var size := maxf(box.size.length() * 1.05, 2.6)
	# câmeras: de lado (olhando para -X, frente à direita), de 3/4 por cima (como a do jogo) e de frente
	for spec in [[Vector3(10, hgt * 0.5, 0), Vector3(0, hgt * 0.5, 0)], [Vector3(6, 7, 6), Vector3(0, hgt * 0.4, 0)],
			[Vector3(0, hgt * 0.5, 10), Vector3(0, hgt * 0.5, 0)]]:
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = size
		add_child(cam)
		cam.look_at_from_position(spec[0], spec[1], Vector3.UP)
		cams.append(cam)
	_run.call_deferred()


func _step(dt: float, hspeed: float) -> void:
	e._animate(dt, hspeed)


func _run() -> void:
	var dt := 1.0 / 60.0
	var hspeed := 0.0
	if mode == "walk":
		hspeed = float(e.data.speed)
	elif mode == "run":
		hspeed = float(e.data.speed) * 1.5
	e.state = "chase" if hspeed > 0.0 else "idle"
	# aquece o ciclo (o _animate suaviza com lerp)
	for i in 90:
		_step(dt, hspeed)
	var total := span
	if mode == "attack":
		e.state = "attack"
		e.attack_kind = attack if attack != "" else "lunge"
		e.attack_timer = 0.0
		e.hit_done = false
		total = e._attack_duration()
	var sheet := Image.create(W * frames, H * cams.size(), false, Image.FORMAT_RGBA8)
	var t := 0.0
	for f in frames:
		var target := total * float(f) / float(maxi(1, frames - 1))
		while t < target - 0.0001:
			if mode == "attack":
				e.attack_timer = t
			_step(dt, hspeed)
			t += dt
		for ci in cams.size():
			cams[ci].make_current()
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			img.resize(W, H)
			sheet.blit_rect(img, Rect2i(0, 0, W, H), Vector2i(f * W, ci * H))
	sheet.save_png(out)
	print("LAB salvo: ", out, " (", mode, ", ", total, " s)")
	get_tree().quit()
