extends Node3D
## Morte em cacos (FXShatter) quadro a quadro: três monstros morrem juntos e a tela é fotografada em
## alguns instantes depois da morte, lado a lado num PNG. Precisa de janela (sem --headless):
##   godot --path . --resolution 960x540 res://tools/death_shot.tscn -- <saida.png>

const ENEMY := preload("res://scripts/enemies/enemy.gd")
const KINDS := ["goblin", "slime", "esqueleto"]
const SHOTS := [0.0, 0.15, 0.3, 0.4, 0.6, 0.9]   # segundos depois da morte

var _out := ""
var _enemies: Array = []


func _ready() -> void:
	_out = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://death.png"
	WorldLighting.build(self)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(shape)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.45, 0.25)
	plane.material = gm
	floor_body.add_child(ground)
	add_child(floor_body)
	for i in KINDS.size():
		var e := ENEMY.new()
		e.kind = KINDS[i]
		e.position = Vector3((i - 1) * 2.2, 0.1, 0)
		add_child(e)
		_enemies.append(e)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 1.8, 4.2)
	cam.look_at(Vector3(0, 0.8, 0))
	cam.current = true
	await get_tree().create_timer(0.8).timeout
	for e in _enemies:
		e.die_visual()
	var t0 := Time.get_ticks_msec() / 1000.0
	var imgs: Array[Image] = []
	for s in SHOTS:
		while Time.get_ticks_msec() / 1000.0 - t0 < s:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		imgs.append(get_viewport().get_texture().get_image())
	var w := imgs[0].get_width() / 2
	var h := imgs[0].get_height() / 2
	var sheet := Image.create(w * 3, h * 2, false, imgs[0].get_format())
	for i in imgs.size():
		imgs[i].resize(w, h)
		sheet.blit_rect(imgs[i], Rect2i(0, 0, w, h), Vector2i((i % 3) * w, (i / 3) * h))
	sheet.save_png(_out)
	print("salvo ", _out)
	get_tree().quit()
