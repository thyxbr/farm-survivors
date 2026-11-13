extends Node3D
## Armas automáticas do Desafio da Horda. Fica como filho do jogador durante a partida.

const FIREBALL := preload("res://scripts/player/fireball.gd")

var player: Player
var levels := {}          # id -> nível (1..5)
var _timers := {"fogo": 0.5, "raio": 1.0, "aura": 0.0}
var _blade_pivot: Node3D
var _blades: Array[MeshInstance3D] = []
var _blade_hits := {}     # instance_id -> tempo até poder acertar de novo
var _aura: MeshInstance3D
var _aura_mat: StandardMaterial3D
var _t := 0.0


func _ready() -> void:
	player = get_parent() as Player


func set_level(id: String, lv: int) -> void:
	levels[id] = lv
	match id:
		"laminas":
			_build_blades()
		"aura":
			_build_aura()


func _physics_process(delta: float) -> void:
	if player == null or player.dead:
		return
	_t += delta
	var cd_mult: float = max(0.35, Game.mod("cooldown"))
	for id in _timers:
		_timers[id] -= delta
	if levels.has("fogo") and _timers.fogo <= 0.0:
		_timers.fogo = [1.8, 1.5, 1.5, 1.25, 1.1][levels.fogo - 1] * cd_mult
		_fire_orbs()
	if levels.has("raio") and _timers.raio <= 0.0:
		_timers.raio = [2.6, 2.4, 2.1, 2.0, 1.7][levels.raio - 1] * cd_mult
		_lightning()
	if levels.has("aura"):
		_update_aura(delta)
	if levels.has("laminas"):
		_update_blades(delta)


# ------------------------------------------------------------ utilidades
func _damage(base: float) -> Array:
	var crit: bool = randf() < 0.05 + Game.mod("crit")
	return [base * Game.damage_mult() * randf_range(0.9, 1.1) * (1.8 if crit else 1.0), crit]


func _enemies_by_distance(max_dist: float) -> Array:
	var out: Array = []
	var p := player.global_position
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var d: float = e.global_position.distance_to(p)
		if d <= max_dist:
			out.append([d, e])
	out.sort_custom(func(a, b) -> bool: return a[0] < b[0])
	return out


# ------------------------------------------------------------ Orbe de Fogo
func _fire_orbs() -> void:
	var lv: int = levels.fogo
	var count: int = [1, 1, 2, 2, 3][lv - 1]
	var dmg: float = [16.0, 21.0, 24.0, 30.0, 38.0][lv - 1]
	var targets := _enemies_by_distance(20.0)
	if targets.is_empty():
		return
	var origin := player.global_position + Vector3.UP * 1.3
	for i in count:
		var e: Enemy = targets[i % targets.size()][1]
		var aim := e.global_position + Vector3.UP * 0.5
		var dir := (aim - origin).normalized()
		if i >= targets.size():
			dir = dir.rotated(Vector3.UP, 0.25 * (i - targets.size() + 1))
		var fb := FIREBALL.new()
		fb.direction = dir
		fb.damage = _damage(dmg)[0]
		fb.speed = 20.0
		get_tree().current_scene.add_child(fb)
		fb.global_position = origin + Vector3(dir.x, 0, dir.z).normalized() * 0.5
	Sfx.play("fire", 0.15, -9.0)


# ------------------------------------------------------------ Relâmpago
func _lightning() -> void:
	var lv: int = levels.raio
	var n: int = [1, 2, 2, 3, 5][lv - 1]
	var dmg: float = [22.0, 26.0, 34.0, 38.0, 50.0][lv - 1]
	var near := _enemies_by_distance(16.0 * Game.mod("area"))
	if near.is_empty():
		return
	near.shuffle()
	for i in min(n, near.size()):
		var e: Enemy = near[i][1]
		var d := _damage(dmg)
		_bolt_fx(e.global_position)
		e.take_damage(d[0], e.global_position, d[1])
	Sfx.play("zap", 0.15, -4.0)


func _bolt_fx(pos: Vector3) -> void:
	var root := get_tree().current_scene
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.14
	cyl.height = 14.0
	cyl.radial_segments = 6
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.75, 0.9, 1.0, 1.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(0.5, 0.8, 1.0)
	m.emission_energy_multiplier = 6.0
	cyl.material = m
	mi.mesh = cyl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = pos + Vector3.UP * 7.0
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 0.25)
	tw.tween_callback(mi.queue_free)
	FX.burst(pos + Vector3.UP * 0.3, Color(0.6, 0.85, 1.0), 14, 5.0, 0.08, 0.35)


# ------------------------------------------------------------ Lâminas Orbitais
func _blade_stats() -> Dictionary:
	var lv: int = levels.laminas
	return {
		"count": [2, 3, 3, 4, 5][lv - 1],
		"dmg": [8.0, 9.0, 11.0, 12.0, 15.0][lv - 1],
		"radius": [2.1, 2.1, 2.5, 2.6, 2.8][lv - 1] * Game.mod("area"),
		"speed": [3.0, 3.0, 3.2, 3.8, 4.0][lv - 1],
	}


func _build_blades() -> void:
	if _blade_pivot == null:
		_blade_pivot = Node3D.new()
		_blade_pivot.position.y = 0.9
		add_child(_blade_pivot)
	for b in _blades:
		b.queue_free()
	_blades.clear()
	var st := _blade_stats()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.1, 0.05, 1.0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.85, 1.0)
	m.metallic = 0.9
	m.roughness = 0.2
	m.emission_enabled = true
	m.emission = Color(0.4, 0.6, 1.0)
	m.emission_energy_multiplier = 1.5
	mesh.material = m
	for i in st.count:
		var b := MeshInstance3D.new()
		b.mesh = mesh
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_blade_pivot.add_child(b)
		_blades.append(b)


func _update_blades(delta: float) -> void:
	var st := _blade_stats()
	_blade_pivot.rotation.y += st.speed * delta
	var n := _blades.size()
	for i in n:
		var a := TAU * i / n
		var b := _blades[i]
		b.position = Vector3(cos(a), 0, sin(a)) * st.radius
		b.rotation.y = -a  # alinhada com a direção do giro
	for k in _blade_hits.keys():
		_blade_hits[k] -= delta
		if _blade_hits[k] <= 0.0:
			_blade_hits.erase(k)
	var ppos := player.global_position
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var to: Vector3 = e.global_position - ppos
		to.y = 0
		if abs(to.length() - st.radius) > 0.9 + e.radius:
			continue
		var id: int = e.get_instance_id()
		if _blade_hits.has(id):
			continue
		for b in _blades:
			var bp := b.global_position
			if Vector2(bp.x - e.global_position.x, bp.z - e.global_position.z).length() < 0.75 + e.radius:
				var d := _damage(st.dmg)
				e.take_damage(d[0], ppos, d[1])
				_blade_hits[id] = 0.4
				break


# ------------------------------------------------------------ Aura Gélida
func _aura_radius() -> float:
	return [2.4, 2.8, 3.2, 3.6, 4.0][levels.aura - 1] * Game.mod("area")


func _build_aura() -> void:
	if _aura == null:
		_aura = MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 1.0
		disc.bottom_radius = 1.0
		disc.height = 0.03
		disc.radial_segments = 40
		_aura_mat = StandardMaterial3D.new()
		_aura_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_aura_mat.albedo_color = Color(0.45, 0.8, 1.0, 0.18)
		_aura_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_aura_mat.emission_enabled = true
		_aura_mat.emission = Color(0.4, 0.8, 1.0)
		disc.material = _aura_mat
		_aura.mesh = disc
		_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_aura.position.y = 0.08
		add_child(_aura)


func _update_aura(delta: float) -> void:
	var r := _aura_radius()
	_aura.scale = Vector3(r, 1, r)
	_aura_mat.albedo_color.a = 0.14 + 0.06 * sin(_t * 4.0)
	if _timers.aura > 0.0:
		return
	_timers.aura = 0.5
	var lv: int = levels.aura
	var dmg: float = [5.0, 6.5, 8.5, 9.5, 13.0][lv - 1]
	var slow: float = 0.7 if lv < 4 else 1.2
	for item in _enemies_by_distance(r + 1.0):
		var e: Enemy = item[1]
		if item[0] > r + e.radius:
			continue
		var d := _damage(dmg)
		e.take_damage(d[0], e.global_position, d[1])
		e.apply_slow(slow)
