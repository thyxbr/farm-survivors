extends Node3D
## Efeitos do healer quadro a quadro: borda de alvo da Cura num aliado, cura em arco, Lança de Luz,
## explosão radiante e Banquete. Cada quadro é uma foto; saem lado a lado num PNG. Precisa de janela:
##   godot --path . --resolution 960x540 res://tools/healer_shot.tscn -- <saida.png>

const PLAYER := preload("res://scripts/player/player.gd")
const PROJECTILE := preload("res://scripts/player/projectile.gd")

var _out := ""
var _imgs: Array[Image] = []


func _ready() -> void:
	_out = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://healer.png"
	WorldLighting.build(self)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(shape)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.45, 0.25)
	plane.material = gm
	floor_body.add_child(ground)
	add_child(floor_body)
	var healer := _replica(Vector3(-2.2, 0, 0), 1)
	var a := _replica(Vector3(1.2, 0, -0.6), 2)
	var b := _replica(Vector3(2.6, 0, 0.8), 3)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 2.6, 6.5)
	cam.look_at(Vector3(0.3, 1.0, 0))
	cam.current = true
	await get_tree().create_timer(1.0).timeout
	# 1) dois aliados juntos: a borda marca só o mirado
	a.set_heal_highlight(true)
	await _wait(0.4)
	cam.position = Vector3(0.4, 1.8, 2.6)
	cam.look_at(Vector3(1.6, 1.0, 0))
	await _snap()
	cam.position = Vector3(0, 2.6, 6.5)
	cam.look_at(Vector3(0.3, 1.0, 0))
	await _snap()
	# 2) a cura voa em arco do healer até o aliado e explode em luz
	HolyFX.heal_beam(healer.global_position + Vector3.UP * 1.4, a, true)
	await _wait(0.13)
	await _snap()
	await _wait(0.3)
	await _snap()
	a.set_heal_highlight(false)
	await _wait(1.0)
	# 3) Lança de Luz voando e o impacto
	var p := PROJECTILE.new()
	p.kind = "holy_lance"
	p.direction = Vector3(1, 0, 0)
	p.visual_only = true
	p.speed = 12.0
	p.life = 0.55
	add_child(p)
	p.global_position = Vector3(-2.0, 1.3, 2.0)
	await _wait(0.3)
	await _snap()
	cam.position = p.global_position + Vector3(0.0, 0.6, 2.2)
	cam.look_at(p.global_position)
	await _snap()
	cam.position = Vector3(0, 2.6, 6.5)
	cam.look_at(Vector3(0.3, 1.0, 0))
	await _wait(0.32)
	await _snap()
	await _wait(0.8)
	# 4) explosão radiante (Escudo de Luz)
	cam.position = Vector3(0, 5.5, 12.0)
	cam.look_at(Vector3(-1.0, 0.5, 0))
	# círculo da mira do Julgamento de Luz e a queda no ponto escolhido
	var mk := HolyFX.area_marker(ScepterAbilities.NOVA_RADIUS)
	add_child(mk)
	mk.global_position = Vector3(3.5, 0, 1.5)
	await _wait(0.3)
	await _snap()
	mk.queue_free()
	HolyFX.radiant_nova(Vector3(3.5, 0, 1.5), ScepterAbilities.NOVA_RADIUS)
	await _wait(0.15)
	await _snap()
	await _wait(1.2)
	# 5) Banquete do Herói
	HolyFX.feast(b.global_position, ScepterAbilities.FEAST_RADIUS)
	await _wait(0.3)
	await _snap()
	await _wait(1.5)
	# 6) auras dos buffs (Banquete e Escudo de Luz) e a cura em si mesmo, de perto
	for pair in [[b, "sagrado"], [a, "luz"]]:
		var au := BuffAura.new()
		pair[0].model.add_child(au)
		au.set_styles([pair[1]])
	cam.position = Vector3(1.9, 1.7, 4.2)
	cam.look_at(Vector3(1.9, 1.0, 0))
	await _wait(0.6)
	await _snap()
	HolyFX.heal_burst(healer.global_position)
	cam.position = Vector3(-2.2, 1.8, 4.5)
	cam.look_at(Vector3(-2.2, 1.2, 0))
	await _wait(0.2)
	await _snap()
	_save()


func _replica(pos: Vector3, id: int) -> Node3D:
	var rp := PLAYER.new()
	rp.remote = true
	rp.peer_id = id
	rp.display_name = "Jogador %d" % id
	rp.position = pos
	add_child(rp)
	rp.apply_net_state(pos, 0.0, Vector3.ZERO, 1, 0, 0.0)
	return rp


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _snap() -> void:
	await RenderingServer.frame_post_draw
	_imgs.append(get_viewport().get_texture().get_image())


func _save() -> void:
	var w := _imgs[0].get_width() / 2
	var h := _imgs[0].get_height() / 2
	var cols := 3
	var rows := ceili(_imgs.size() / float(cols))
	var sheet := Image.create(w * cols, h * rows, false, _imgs[0].get_format())
	for i in _imgs.size():
		_imgs[i].resize(w, h)
		sheet.blit_rect(_imgs[i], Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	sheet.save_png(_out)
	print("salvo ", _out)
	get_tree().quit()
