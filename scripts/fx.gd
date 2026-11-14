class_name FX
extends RefCounted
## Efeitos visuais simples criados por código (números de dano, partículas, anéis).


static func _scene() -> Node:
	if Network.is_server():
		return null   # servidor dedicado: ninguém vê os efeitos
	return (Engine.get_main_loop() as SceneTree).current_scene


static func damage_number(pos: Vector3, text: String, color := Color.WHITE, size := 48) -> void:
	var root := _scene()
	if root == null:
		return
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = 10
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	l.pixel_size = 0.006
	root.add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "global_position:y", l.global_position.y + 1.2, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.45).set_delay(0.45)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.45).set_delay(0.45)
	tw.chain().tween_callback(l.queue_free)


static func burst(pos: Vector3, color: Color, amount := 16, speed := 4.0, size := 0.12, lifetime := 0.6, gravity := -9.0) -> void:
	var root := _scene()
	if root == null:
		return
	var p := burst_particles(color, amount, speed, size, lifetime, gravity)
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	root.get_tree().create_timer(lifetime + 0.5).timeout.connect(p.queue_free)


## Emissor de uma rajada, sem pai e parado: quem dispara sempre no mesmo lugar guarda um e chama
## restart() a cada vez (ex.: as faíscas da bigorna do ferreiro).
static func burst_particles(color: Color, amount := 16, speed := 4.0, size := 0.12, lifetime := 0.6, gravity := -9.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = m
	p.mesh = mesh
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = lifetime
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, gravity, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var grad := Gradient.new()
	grad.set_color(0, color)
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = grad
	p.emitting = false
	return p


static func ring(pos: Vector3, color: Color, radius: float, duration := 0.5) -> void:
	var root := _scene()
	if root == null:
		return
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 6
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = color
	torus.material = m
	mi.mesh = torus
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.15, 0)
	mi.scale = Vector3(0.3, 1.0, 0.3)
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3(radius, 1.5, radius), duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(m, "albedo_color:a", 0.0, duration)
	tw.chain().tween_callback(mi.queue_free)


## Círculo vermelho no chão usado como aviso de ataque em área.
static func telegraph(pos: Vector3, radius: float, duration: float) -> void:
	var root := _scene()
	if root == null:
		return
	var mi := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.04
	disc.radial_segments = 40
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 0.1, 0.05, 0.15)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc.material = m
	mi.mesh = disc
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.06, 0)
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.55, duration)
	tw.tween_callback(mi.queue_free)
