class_name ColonyVillager
extends Node3D
## Aldeão decorativo (só no cliente com tela, nunca no headless): um boneco de peças simples que anda da
## porta da construção até o alvo de trabalho, faz um gesto por alguns segundos e volta. Sem colisão nem rede.

const WORK_TIME := 3.0
const SPEED := 1.6

var home: ColonyBuilding
var _tool: Node3D
var _state := "idle"   # idle | go | work | back
var _t := 0.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _target_id := -1
var _work_pos := Vector3.ZERO
var _bob := 0.0


func _ready() -> void:
	add_to_group("villager_visual")
	var tunic := Color.from_hsv(randf(), 0.35, 0.55)
	ColonyVisuals._box(self, Vector3(0.34, 0.5, 0.2), Vector3(0, 0.62, 0), tunic)
	ColonyVisuals._box(self, Vector3(0.12, 0.4, 0.14), Vector3(-0.09, 0.2, 0), Color(0.3, 0.22, 0.15))
	ColonyVisuals._box(self, Vector3(0.12, 0.4, 0.14), Vector3(0.09, 0.2, 0), Color(0.3, 0.22, 0.15))
	ColonyVisuals._sphere(self, 0.15, Vector3(0, 1.0, 0), Color(0.85, 0.68, 0.52))
	ColonyVisuals._cyl(self, 0.1, 0.17, 0.1, Vector3(0, 1.14, 0), Color(0.5, 0.4, 0.25))
	_tool = Node3D.new()
	_tool.position = Vector3(0.24, 0.75, 0.05)
	add_child(_tool)
	_make_tool()
	_idle(randf() * 4.0)


func _make_tool() -> void:
	match home.kind:
		"lumber_camp":   # machado
			ColonyVisuals._cyl(_tool, 0.025, 0.025, 0.6, Vector3(0, -0.2, 0.1), ColonyVisuals.WOOD, 5, Vector3(PI / 2.5, 0, 0))
			ColonyVisuals._box(_tool, Vector3(0.05, 0.16, 0.2), Vector3(0, 0.0, 0.3), ColonyVisuals.IRON)
		"quarry":   # picareta
			ColonyVisuals._cyl(_tool, 0.025, 0.025, 0.6, Vector3(0, -0.2, 0.1), ColonyVisuals.WOOD, 5, Vector3(PI / 2.5, 0, 0))
			ColonyVisuals._box(_tool, Vector3(0.05, 0.05, 0.4), Vector3(0, 0.0, 0.3), ColonyVisuals.IRON)
		"farm":   # enxada
			ColonyVisuals._cyl(_tool, 0.025, 0.025, 0.7, Vector3(0, -0.15, 0.1), ColonyVisuals.WOOD, 5, Vector3(PI / 2.5, 0, 0))
			ColonyVisuals._box(_tool, Vector3(0.18, 0.2, 0.03), Vector3(0, 0.08, 0.35), ColonyVisuals.IRON)
		"market":   # caixote
			ColonyVisuals._box(_tool, Vector3(0.26, 0.2, 0.26), Vector3(-0.1, 0.0, 0.2), ColonyVisuals.WOOD_DARK)
		_:   # lança de vigia
			ColonyVisuals._cyl(_tool, 0.02, 0.02, 1.3, Vector3(0.05, 0.3, 0), ColonyVisuals.WOOD, 5)


func _door() -> Vector3:
	return home.global_transform * Vector3(randf_range(-0.6, 0.6), 0, home.size.y / 2.0 + 0.6)


func _flat_y() -> float:
	return home.global_position.y


func _idle(wait: float) -> void:
	_state = "idle"
	_t = wait
	_target_id = -1
	global_position = _door()


func _pick_target() -> bool:
	var nat = home.colony.nature if home.colony else null
	match home.kind:
		"lumber_camp", "quarry":
			if nat == null:
				return false
			var ids: Array[int] = nat.alive_near(home.data.gather, home.global_position, float(home.data.reach))
			if ids.is_empty():
				return false
			var best := -1
			var bd := INF
			for id in ids:
				var d: float = nat.node(id).global_position.distance_to(home.global_position) + randf() * 3.0
				if d < bd:
					bd = d
					best = id
			_target_id = best
			var np: Vector3 = nat.node(best).global_position
			var dir := (home.global_position - np) * Vector3(1, 0, 1)
			_to = np + dir.normalized() * 0.9
		"farm":
			_to = home.global_transform * Vector3(randf_range(-2.6, 2.6), 0, randf_range(-5.0, -1.2))
		"market":
			var sx := -1.0 if randf() < 0.5 else 1.0
			_to = home.global_transform * Vector3(sx * 1.6 + randf_range(-0.4, 0.4), 0, randf_range(-1.0, 1.2))
		_:   # torre e demais: parado ao pé
			_to = home.global_transform * Vector3(randf_range(-1.4, 1.4), 0, home.size.y / 2.0 + 0.9)
	_to.y = _flat_y()
	return true


func _go(to: Vector3, next: String) -> void:
	_from = global_position
	_to = to
	_state = next
	_t = 0.0


func _process(delta: float) -> void:
	if not is_instance_valid(home):
		return
	match _state:
		"idle":
			_t -= delta
			if _t <= 0.0:
				if _pick_target():
					_from = global_position
					_state = "go"
					_t = 0.0
				else:
					_idle(3.0)
		"go", "back":
			var dist := maxf(0.01, Vector2(_to.x - _from.x, _to.z - _from.z).length())
			_t += delta * SPEED / dist
			var p := _from.lerp(_to, clampf(_t, 0.0, 1.0))
			_bob += delta * 9.0
			p.y = _flat_y() + absf(sin(_bob)) * 0.05
			global_position = p
			if dist > 0.05:
				rotation.y = atan2(_to.x - _from.x, _to.z - _from.z)
			_tool.rotation.x = 0.0
			if _t >= 1.0:
				if _state == "go":
					_state = "work"
					_t = 0.0
					_work_pos = _to
				else:
					_idle(randf_range(1.0, 4.0))
		"work":
			_t += delta
			_tool.rotation.x = sin(_t * 7.0) * 0.8 - 0.3
			if _target_id >= 0 and home.colony and home.colony.nature:
				var n = home.colony.nature.node(_target_id)
				if n and n.alive:
					var d: Vector3 = n.global_position - global_position
					rotation.y = atan2(d.x, d.z)
			if _t >= WORK_TIME:
				_tool.rotation.x = 0.0
				_go(_door(), "back")
