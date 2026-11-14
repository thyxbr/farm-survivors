class_name FX
extends RefCounted
## Efeitos visuais simples criados por código (números de dano, partículas, anéis).

## Material das partículas de burst (compartilhado: a cor vem por vértice) e um material do anel que
## fica vivo: quando o último material de um tipo é liberado o Godot descarta o shader e o recompila
## no próximo efeito, um engasgo de 10-20 ms em todo golpe depois de uns segundos sem efeitos.
static var _burst_mat: StandardMaterial3D
static var _ring_keep: StandardMaterial3D


static func _scene() -> Node:
	if Network.is_server():
		return null   # servidor dedicado: ninguém vê os efeitos
	return (Engine.get_main_loop() as SceneTree).current_scene


## Materiais compartilhados prontos antes do primeiro efeito (FXEpic.prewarm chama).
static func prewarm() -> void:
	_burst_material()
	_ring_material()


static func _burst_material() -> StandardMaterial3D:
	if _burst_mat == null:
		_burst_mat = StandardMaterial3D.new()
		_burst_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_burst_mat.vertex_color_use_as_albedo = true
		_burst_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _burst_mat


static func _ring_material() -> StandardMaterial3D:
	if _ring_keep == null:
		_ring_keep = StandardMaterial3D.new()
		_ring_keep.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ring_keep.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ring_keep.emission_enabled = true
	return _ring_keep


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
	var p := CPUParticles3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * size
	mesh.material = _burst_material()
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
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	root.get_tree().create_timer(lifetime + 0.5).timeout.connect(p.queue_free)


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
	var m := _ring_material().duplicate() as StandardMaterial3D   # cada anel apaga a própria cor
	m.albedo_color = color
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
