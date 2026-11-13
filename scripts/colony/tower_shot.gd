extends Node3D
## Disparo das torres e dos arqueiros: persegue o alvo e aplica o dano ao chegar.
## kind: "arrow" (flecha reta), "ball" (bala de canhão em arco, explode em área),
## "bolt" (raio gélido: deixa lento e salta para outros monstros).

var kind := "arrow"
var target   # Enemy (sem tipo: o alvo pode sumir no meio do caminho)
var damage := 10.0
var splash := 0.0
var slow := 0.0
var chain := 0
var speed := 0.0
## Cliente (cooperativo): só o visual; o dano é aplicado pelo servidor.
var visual_only := false
## Cliente: sem alvo réplica, voa até este ponto.
var aim_point := Vector3.INF

var _start := Vector3.ZERO
var _last := Vector3.ZERO
var _t := 0.0
var _dur := 0.5
var _mesh: Node3D
var _hit := {}


func _ready() -> void:
	_start = global_position if is_inside_tree() else position
	_mesh = Node3D.new()
	add_child(_mesh)
	var mi := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	match kind:
		"ball":
			var s := SphereMesh.new()
			s.radius = 0.24
			s.height = 0.48
			mi.mesh = s
			m.albedo_color = Color(0.12, 0.12, 0.13)
			m.metallic = 0.6
			m.roughness = 0.4
		"bolt":
			var s := SphereMesh.new()
			s.radius = 0.2
			s.height = 0.4
			mi.mesh = s
			m.albedo_color = Color(0.55, 0.85, 1.0)
			m.emission_enabled = true
			m.emission = Color(0.55, 0.85, 1.0)
			m.emission_energy_multiplier = 3.0
			var l := OmniLight3D.new()
			l.light_color = Color(0.5, 0.8, 1.0)
			l.light_energy = 1.2
			l.omni_range = 3.0
			_mesh.add_child(l)
		_:
			var b := BoxMesh.new()
			b.size = Vector3(0.05, 0.05, 0.75)
			mi.mesh = b
			m.albedo_color = Color(0.5, 0.36, 0.2)
	mi.material_override = m
	_mesh.add_child(mi)
	if speed <= 0.0:
		speed = {"arrow": 34.0, "ball": 20.0, "bolt": 26.0}.get(kind, 30.0)


func _aim() -> Vector3:
	if aim_point != Vector3.INF and (target == null or not is_instance_valid(target)):
		_last = aim_point
		return _last
	if target and is_instance_valid(target) and not target.get("dead"):
		var h: float = 0.6
		if target is Enemy:
			h = target.data.height * target.data.scale * 0.55
		_last = target.global_position + Vector3.UP * h
	return _last


func _physics_process(delta: float) -> void:
	if _t == 0.0:
		_start = global_position
		_last = _aim()
		_dur = maxf(0.12, _start.distance_to(_last) / speed)
	_t += delta
	var goal := _aim()
	var k := clampf(_t / _dur, 0.0, 1.0)
	var p := _start.lerp(goal, k)
	if kind == "ball":
		p.y += sin(k * PI) * minf(6.0, _start.distance_to(goal) * 0.25)
	var dir := p - global_position
	global_position = p
	if dir.length() > 0.001 and kind != "bolt":
		_mesh.look_at(global_position + dir, Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT)
	if k >= 1.0:
		_impact()


func _impact() -> void:
	set_physics_process(false)
	match kind:
		"ball":
			Sfx.play_at("explode", global_position, 0.15, -6.0)
			FX.burst(global_position, Color(1.0, 0.6, 0.25), 26, 6.0, 0.14, 0.45, -3.0)
			FX.burst(global_position, Color(0.35, 0.33, 0.3), 16, 3.0, 0.25, 0.9, -1.0)
			FX.ring(Vector3(global_position.x, 0.05, global_position.z), Color(1.0, 0.6, 0.3, 0.8), splash, 0.35)
			for e in _enemies():
				var d := Vector2(e.global_position.x - global_position.x, e.global_position.z - global_position.z).length()
				if d <= splash + e.radius:
					var falloff := 1.0 if d < splash * 0.4 else 0.6
					e.take_damage(damage * falloff * randf_range(0.9, 1.1) * e.resist_mult(kind), global_position, false, slow)
		"bolt":
			if visual_only:
				if target and is_instance_valid(target) and not target.dead:
					FX.burst(target.global_position + Vector3.UP * 0.8, Color(0.55, 0.85, 1.0), 10, 3.0, 0.08, 0.4)
			else:
				_zap(target, damage, chain)
		_:
			if not visual_only and target and is_instance_valid(target) and not target.dead:
				target.take_damage(damage * randf_range(0.9, 1.1) * target.resist_mult(kind), target.global_position, false, slow)
			FX.burst(global_position, Color(0.6, 0.45, 0.3), 5, 2.0, 0.05, 0.25)
	queue_free()


## Raio que salta de monstro em monstro (cada salto causa 75% do anterior).
func _zap(e, dmg: float, left: int) -> void:
	if e == null or not is_instance_valid(e) or e.dead:
		return
	_hit[e.get_instance_id()] = true
	e.take_damage(dmg * randf_range(0.9, 1.1) * e.resist_mult("bolt"), e.global_position, false, slow)
	FX.burst(e.global_position + Vector3.UP * 0.8, Color(0.55, 0.85, 1.0), 10, 3.0, 0.08, 0.4)
	if left <= 0:
		return
	var best: Enemy = null
	var best_d := 7.0
	for o in _enemies():
		if _hit.has(o.get_instance_id()):
			continue
		var d: float = o.global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = o
	if best:
		_beam(e.global_position + Vector3.UP * 0.8, best.global_position + Vector3.UP * 0.8)
		_zap(best, dmg * 0.75, left - 1)


## Monstros vivos da cidade do disparo (o pai é a Colony).
func _enemies() -> Array:
	if visual_only:
		return []
	var c := get_parent()
	if c and c.has_method("live_enemies"):
		return c.live_enemies()
	var out: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Enemy and not e.dead:
			out.append(e)
	return out


func _beam(a: Vector3, b: Vector3) -> void:
	if a.distance_to(b) < 0.05:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.06, 0.06, a.distance_to(b))
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.7, 0.9, 1.0)
	mi.material_override = m
	get_parent().add_child(mi)
	mi.global_position = (a + b) * 0.5
	mi.look_at(b, Vector3.UP)
	var tw := mi.create_tween()
	tw.tween_interval(0.12)
	tw.tween_callback(mi.queue_free)
