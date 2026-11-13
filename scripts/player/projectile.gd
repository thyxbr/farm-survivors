extends Area3D
## Projétil do ataque básico: "bolt" (cajado, faísca arcana) ou "arrow" (arco, com leve queda).
## fx: "slow" deixa o alvo lento, "splash" explode em área, "pierce" atravessa inimigos.

var kind := "bolt"
var direction := Vector3.FORWARD
var damage := 10.0
var speed := 30.0
var color := Color(0.6, 0.8, 1.0)
var fx := ""
var crit := false
var pierce := 0
var life := 1.6
## Multiplayer: projétil de outro jogador — só o visual, sem dano.
var visual_only := false
var _vel := Vector3.ZERO
var _done := false
var _hit := {}
var _vis: Node3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | 4
	var col := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.22 if kind == "bolt" else 0.16
	col.shape = sh
	add_child(col)
	_vel = direction.normalized() * speed
	_vis = Node3D.new()
	add_child(_vis)
	if kind == "arrow":
		_build_arrow()
	else:
		_build_bolt()
	body_entered.connect(_on_body)
	_orient()


func _build_bolt() -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.28
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color.lightened(0.4)
	sm.material = m
	mi.mesh = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis.add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 2.0
	light.omni_range = 3.5
	add_child(light)
	add_child(_trail(color, 0.07, 30, 0.3))


func _build_arrow() -> void:
	var shaft := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.012
	c.bottom_radius = 0.012
	c.height = 0.8
	c.radial_segments = 6
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.55, 0.4, 0.22)
	c.material = wm
	shaft.mesh = c
	shaft.rotation.x = PI / 2
	_vis.add_child(shaft)
	var head := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.03
	cone.height = 0.1
	cone.radial_segments = 6
	var hm := StandardMaterial3D.new()
	hm.albedo_color = color
	hm.emission_enabled = true
	hm.emission = color
	hm.emission_energy_multiplier = 1.5
	cone.material = hm
	head.mesh = cone
	head.rotation.x = PI / 2
	head.position.z = 0.44
	_vis.add_child(head)
	add_child(_trail(color, 0.04, 16, 0.18))


func _trail(c: Color, size: float, amount: int, lifetime: float) -> CPUParticles3D:
	var trail := CPUParticles3D.new()
	var tm := SphereMesh.new()
	tm.radius = size
	tm.height = size * 2.0
	var tmat := StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.vertex_color_use_as_albedo = true
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.material = tmat
	trail.mesh = tm
	trail.amount = amount
	trail.lifetime = lifetime
	trail.local_coords = false
	trail.gravity = Vector3.ZERO
	trail.spread = 15
	trail.initial_velocity_max = 0.3
	var g := Gradient.new()
	g.set_color(0, Color(c.r, c.g, c.b, 0.9))
	g.set_color(1, Color(c.r, c.g, c.b, 0.0))
	trail.color_ramp = g
	return trail


func _orient() -> void:
	if _vel.length() > 0.01:
		var up := Vector3.UP if abs(_vel.normalized().dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
		_vis.look_at(global_position + _vel if is_inside_tree() else _vel, up, true)


func _physics_process(delta: float) -> void:
	if _done:
		return
	if kind == "arrow":
		_vel.y -= 4.0 * delta
	global_position += _vel * delta
	_orient()
	life -= delta
	if life <= 0:
		_finish(false)


func _on_body(body: Node) -> void:
	if _done or body.is_in_group("player") or body.is_in_group("players"):
		return
	if body.is_in_group("enemies"):
		if body.dead or _hit.has(body.get_instance_id()):
			return
		_hit[body.get_instance_id()] = true
		if not visual_only:
			_damage(body, damage)
		if fx == "splash":
			_finish(true)
		elif pierce > 0:
			pierce -= 1
			damage *= 0.85
			FX.burst(global_position, color, 8, 3.0, 0.06, 0.25)
		else:
			_finish(true)
		return
	_finish(fx == "splash")


func _damage(e: Node, amount: float) -> void:
	var dmg := amount * randf_range(0.9, 1.1)
	e.take_damage(dmg, global_position - _vel.normalized(), crit, 2.5 if fx == "slow" else 0.0)
	Game.on_damage_dealt(dmg)


func _finish(impact: bool) -> void:
	if _done:
		return
	_done = true
	set_deferred("monitoring", false)
	if fx == "splash" and impact:
		FX.burst(global_position, color, 30, 6.0, 0.12, 0.45, -3.0)
		FX.ring(global_position - Vector3.UP * 0.4, Color(color.r, color.g, color.b, 0.8), 2.4, 0.3)
		Sfx.play_at("explode", global_position, 0.1, -6.0)
		if not visual_only:
			for e in get_tree().get_nodes_in_group("enemies"):
				if e.dead or _hit.has(e.get_instance_id()):
					continue
				if e.global_position.distance_to(global_position) <= 2.4 + e.radius:
					_damage(e, damage * 0.6)
	else:
		FX.burst(global_position, color, 10 if kind == "bolt" else 6, 3.0, 0.07, 0.3)
	queue_free()
