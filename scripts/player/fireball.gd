extends Area3D
## Bola de fogo: voa reto, explode ao tocar em inimigo ou cenário causando dano em área.

var direction := Vector3.FORWARD
var damage := 20.0
var speed := 24.0
var life := 3.0
## Multiplayer: bola de fogo de outro jogador — só o visual, sem dano.
var visual_only := false
## Desafio da Horda: chamado com a posição da explosão (gatilho dos combos em grupo).
var on_explode := Callable()
var _done := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | 4
	var col := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.3
	col.shape = sh
	add_child(col)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.5
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.6, 0.15)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.45, 0.05)
	m.emission_energy_multiplier = 4.0
	sm.material = m
	mi.mesh = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 3.0
	light.omni_range = 5.0
	add_child(light)
	var trail := CPUParticles3D.new()
	var tm := SphereMesh.new()
	tm.radius = 0.1
	tm.height = 0.2
	var tmat := StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.vertex_color_use_as_albedo = true
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.material = tmat
	trail.mesh = tm
	trail.amount = 40
	trail.lifetime = 0.4
	trail.local_coords = false
	trail.gravity = Vector3(0, 1.5, 0)
	trail.spread = 25
	trail.initial_velocity_max = 0.6
	var g := Gradient.new()
	g.set_color(0, Color(1, 0.8, 0.3, 1))
	g.set_color(1, Color(0.6, 0.1, 0.0, 0))
	trail.color_ramp = g
	add_child(trail)
	body_entered.connect(_on_body)


func _physics_process(delta: float) -> void:
	if _done:
		return
	global_position += direction * speed * delta
	life -= delta
	if life <= 0:
		_explode()


func _on_body(body: Node) -> void:
	if body.is_in_group("player"):
		return
	_explode()


func _explode() -> void:
	if _done:
		return
	_done = true
	set_deferred("monitoring", false)
	FX.burst(global_position, Color(1, 0.5, 0.1), 30, 6.0, 0.14, 0.5, -4.0)
	FX.ring(global_position - Vector3.UP * 0.5, Color(1, 0.5, 0.1, 0.8), 2.2, 0.3)
	Sfx.play_at("explode", global_position)
	if visual_only:
		queue_free()
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var d: float = e.global_position.distance_to(global_position)
		if d <= 1.0 + e.radius + 0.6:
			e.take_damage(damage * randf_range(0.9, 1.1), global_position - direction, false)
		elif d <= 2.5 + e.radius:
			e.take_damage(damage * 0.5, global_position - direction, false)
	if on_explode.is_valid():
		on_explode.call(global_position)
	queue_free()
