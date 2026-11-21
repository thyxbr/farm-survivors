extends Node3D
## Folha dos efeitos dos arcos míticos (BowMythic) em ação, na luz do jogo: fenda do Abismo, coluna de sol da
## Alvorada, chuva de fogo da Presa do Dragão, rajada do Rei dos Ventos, lua do Crescente e espinheiro com flor da
## Raiz-Mãe. Cada efeito nasce na frente da câmera e é fotografado em dois instantes. Precisa de janela:
##   godot --path . --resolution 1280x720 res://tools/mythic_bow_shot.tscn -- <saida.png>

const SHOTS := [
	["Suspiro do Abismo", "vortex", [0.5, 1.15]],
	["Alvorada", "solar", [0.15, 0.45]],
	["Presa do Dragão", "dragonfire", [0.55, 1.1]],
	["Rei dos Ventos", "gale", [0.08, 0.25]],
	["Crescente Gêmeo", "crescent", [0.1, 0.3]],
	["Raiz-Mãe", "bramble", [0.6, 1.6]],
]
var _out := "user://mythic_bow_shot.png"
var _cam: Camera3D
var _frames: Array = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	WorldLighting.build(self)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.5, 0.28)
	pm.material = gm
	ground.mesh = pm
	add_child(ground)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 0.2, 60)
	cs.shape = box
	cs.position.y = -0.1
	body.add_child(cs)
	add_child(body)
	_cam = Camera3D.new()
	_cam.position = Vector3(0, 4.2, 9.0)
	add_child(_cam)
	_cam.look_at(Vector3(0, 1.2, 0))
	_run.call_deferred()


func _dummy(at: Vector3) -> Node3D:
	var d := MeshInstance3D.new()
	var c := CapsuleMesh.new()
	c.radius = 0.35
	c.height = 1.2
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.75, 0.55)
	c.material = m
	d.mesh = c
	d.position = at + Vector3.UP * 0.6
	add_child(d)
	return d


func _run() -> void:
	for s in SHOTS:
		var kids := get_children()
		var t0 := Time.get_ticks_msec()
		_trigger(str(s[1]))
		var shots: Array = []
		for t in s[2]:
			while (Time.get_ticks_msec() - t0) / 1000.0 < float(t):
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			shots.append(get_viewport().get_texture().get_image())
		_frames.append([s[0], shots])
		await get_tree().create_timer(1.8).timeout
		for c in get_children():
			if not (c in kids):
				c.queue_free()
		await get_tree().create_timer(0.3).timeout
	_save()
	get_tree().quit()


func _trigger(fx: String) -> void:
	var at := Vector3.ZERO
	match fx:
		"vortex":
			for x in [-2.5, 2.5]:
				_dummy(Vector3(x, 0, 0))
			var r := BowMythic.Rift.new()
			r.visual_only = true
			r.position = at
			add_child(r)
		"solar":
			_dummy(at)
			HolyFX.seal(at, BowMythic.SUN, float(BowMythicRules.SOLAR.radius), 0.9)
			HolyFX.pillar(at, BowMythic.SUN, 1.1, 7.0, 0.9)
			HolyFX.sparkles(at + Vector3.UP, BowMythic.SUN, 24, 1.6, 4.0, 1.5, 0.35)
			FXToon.ring_wave(at, float(BowMythicRules.SOLAR.radius), 0.35, BowMythic.SUN)
			for k in 3:
				HolyFX.star(at + Vector3.UP * (1.6 + 0.25 * k), BowMythic.SUN, 0.45)
		"dragonfire":
			var r := BowMythic.Rain.new()
			r.visual_only = true
			r.position = at
			add_child(r)
		"gale":
			_dummy(at)
			for k in 4:
				var a := PROJECTILE_ARROW("gale", Vector3(-6 + k * 0.4, 1.2, 2 - k), Vector3(1, 0, -0.15).normalized())
				a.full = true
			FXToon.ground_gust(at, 2.2, FXToon.WIND, 0.5)
		"crescent":
			HolyFX.star(Vector3(0, 1.6, 0), BowMythic.MOON, 0.9)
			HolyFX.sparkles(Vector3(0, 1.6, 0), BowMythic.MOON, 16, 0.5, 2.5, 0.3, 0.25)
			for k in 2:
				var a := PROJECTILE_ARROW("crescent", Vector3(-5, 1.4 + k * 0.3, 0.5), Vector3(1, 0, -0.05).normalized())
				a.trail = BowMythic.MOON if k == 1 else {}
				a.full = true
		"bramble":
			var r := BowMythic.Bramble.new()
			r.visual_only = true
			r.position = at
			add_child(r)
			var f := BowMythic.Flower.new()
			f.position = Vector3(1.6, 0, 1.2)
			add_child(f)


func PROJECTILE_ARROW(fx: String, from: Vector3, dir: Vector3) -> Node3D:
	var a = load("res://scripts/player/projectile.gd").new()
	a.kind = "arrow"
	a.fx = fx
	a.visual_only = true
	a.no_drop = true
	a.direction = dir
	a.speed = 14.0
	a.life = 1.2
	a.color = BowMythic.particle_color(fx)
	a.position = from
	add_child(a)
	return a


func _save() -> void:
	var w := 480
	var h := 270
	var sheet := Image.create(w * 2 + 30, (h + 26) * _frames.size() + 10, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.12, 0.12, 0.14))
	for i in _frames.size():
		var row: Array = _frames[i][1]
		for j in row.size():
			var img: Image = row[j]
			img.resize(w, h, Image.INTERPOLATE_LANCZOS)
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(10 + j * (w + 10), 10 + i * (h + 26) + 20))
	sheet.save_png(_out)
	var names := []
	for f in _frames:
		names.append(f[0])
	print("SHOT ", _out, " ", names)
