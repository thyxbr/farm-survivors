extends Node3D
## Gema de XP (ou coração/ímã) do Desafio da Horda. Leve: sem física nem luz própria.
## kind: "xp" (value = 1, 5 ou 20), "heal" ou "magnet".

const BASE_PICKUP_RADIUS := 2.6

static var _meshes := {}

var kind := "xp"
var value := 1
var survival: Node
var pulled := false
var _vel := Vector3.ZERO
var _grounded := false
var _t := 0.0
var _speed := 4.0
var _vis: MeshInstance3D


func _ready() -> void:
	add_to_group("xp_gems")
	_vis = MeshInstance3D.new()
	_vis.mesh = _mesh_for(_mesh_key())
	_vis.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_vis)
	_vel = Vector3(randf_range(-1.5, 1.5), 4.0, randf_range(-1.5, 1.5))
	_t = randf() * 3.0


func _mesh_key() -> String:
	if kind != "xp":
		return kind
	return "xp20" if value >= 20 else ("xp5" if value >= 5 else "xp1")


static func _mesh_for(key: String) -> Mesh:
	if _meshes.has(key):
		return _meshes[key]
	var mesh: Mesh
	var c := Color(0.3, 0.6, 1.0)
	match key:
		"heal":
			var s := SphereMesh.new()
			s.radius = 0.2
			s.height = 0.4
			mesh = s
			c = Color(1.0, 0.25, 0.35)
		"magnet":
			var t := TorusMesh.new()
			t.inner_radius = 0.12
			t.outer_radius = 0.26
			mesh = t
			c = Color(1.0, 0.85, 0.2)
		_:
			# losango: esfera com poucos segmentos
			var s := SphereMesh.new()
			s.radial_segments = 4
			s.rings = 2
			var size: float = {"xp1": 0.13, "xp5": 0.17, "xp20": 0.23}[key]
			s.radius = size
			s.height = size * 2.6
			mesh = s
			c = {"xp1": Color(0.3, 0.6, 1.0), "xp5": Color(0.3, 1.0, 0.45), "xp20": Color(1.0, 0.25, 0.3)}[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 1.4
	m.roughness = 0.3
	mesh.surface_set_material(0, m)
	_meshes[key] = mesh
	return mesh


func _process(delta: float) -> void:
	_t += delta
	var player: Player = survival.player if survival else null
	if player == null:
		return
	if not _grounded:
		_vel.y -= 14.0 * delta
		global_position += _vel * delta
		if global_position.y <= 0.35:
			global_position.y = 0.35
			_grounded = true
	var target := player.global_position + Vector3.UP * 0.8
	var to := target - global_position
	var dist := to.length()
	if not player.dead and _t > 0.35:
		if not pulled and dist < BASE_PICKUP_RADIUS * Game.run_mods.magnet:
			pulled = true
		if pulled:
			_grounded = true
			_speed = min(_speed + 30.0 * delta, 26.0)
			if dist < 0.6:
				survival.collect_gem(self)
				queue_free()
				return
			global_position += to / dist * min(dist, _speed * delta)
	_vis.rotation.y += delta * 3.0
	if _grounded and not pulled:
		_vis.position.y = sin(_t * 3.0) * 0.08
