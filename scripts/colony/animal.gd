class_name ColonyAnimal
extends CharacterBody3D
## Animal de caça (coelho, cervo, javali). Fica no grupo "enemies" para as armas do jogador
## o acertarem, mas torres e soldados ignoram (só miram em Enemy). Coelhos e cervos fogem;
## o javali revida. Ao morrer, rende comida e ouro (couro) para a cidade.

var kind := "deer"
var colony: Node
var data: Dictionary
var display_name := ""
var hp := 1.0
var max_hp := 1.0
var radius := 0.5
var dead := false
var home := Vector3.ZERO

var model: Node3D
var legs: Array[Node3D] = []
var _state := "idle"     # idle | wander | flee | charge
var _state_t := 0.0
var _wander := Vector3.ZERO
var _anim := 0.0
var _slow := 0.0
var _cd := 0.0
var _flash := 0.0
var _overlay: StandardMaterial3D


func _ready() -> void:
	data = ColonyData.ANIMALS[kind]
	display_name = data.name
	max_hp = float(data.hp)
	hp = max_hp
	radius = float(data.radius)
	add_to_group("enemies")
	add_to_group("animals")
	collision_layer = 4
	collision_mask = 1
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = maxf(radius * 2.0, 0.9 if kind != "rabbit" else 0.5)
	col.shape = cap
	col.position.y = cap.height / 2.0
	add_child(col)
	model = Node3D.new()
	add_child(model)
	match kind:
		"rabbit":
			_build_rabbit()
		"boar":
			_build_boar()
		_:
			_build_deer()
	model.rotation.y = randf() * TAU
	home = global_position
	_wander = home
	_state_t = randf_range(0.5, 3.0)
	_overlay = StandardMaterial3D.new()
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.albedo_color = Color(1, 1, 1, 0.6)
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


# ---------------------------------------------------------------- comportamento
func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	if dead:
		velocity = Vector3(0, velocity.y, 0)
		move_and_slide()
		return
	_slow = maxf(0.0, _slow - delta)
	_cd = maxf(0.0, _cd - delta)
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0:
			_set_overlay(null)
	var p := get_tree().get_first_node_in_group("player") as Player
	var to_p := Vector3.ZERO
	var dist := INF
	if p and not p.dead:
		to_p = p.global_position - global_position
		to_p.y = 0.0
		dist = to_p.length()
	var spd: float = data.speed * (0.45 if _slow > 0.0 else 1.0)
	var move := Vector3.ZERO
	_state_t -= delta
	match _state:
		"idle":
			if _scared(dist):
				_go("flee", 4.0)
			elif _state_t <= 0.0:
				_wander = home + Vector3(randf_range(-9, 9), 0, randf_range(-9, 9))
				_go("wander", 6.0)
		"wander":
			var to := _wander - global_position
			to.y = 0.0
			if _scared(dist):
				_go("flee", 4.0)
			elif to.length() < 0.8 or _state_t <= 0.0:
				_go("idle", randf_range(2.0, 5.0))
			else:
				move = to.normalized() * spd * 0.3
		"flee":
			if dist < INF:
				move = -to_p.normalized() * spd
			if _state_t <= 0.0 and dist > 14.0:
				home = global_position
				_go("idle", 2.0)
		"charge":
			if dist == INF or _state_t <= 0.0:
				_go("idle", 2.0)
			else:
				move = to_p.normalized() * spd * 1.15
				if dist < radius + 1.0 and _cd <= 0.0:
					_cd = 1.4
					p.take_damage(float(data.damage), global_position)
					Sfx.play_at("hit", global_position, 0.2, -4.0)
					velocity.x = -to_p.normalized().x * 5.0
					velocity.z = -to_p.normalized().z * 5.0
	if move.length() > 0.1:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(move.x, move.z), 8.0 * delta)
	velocity.x = move_toward(velocity.x, move.x, 25.0 * delta)
	velocity.z = move_toward(velocity.z, move.z, 25.0 * delta)
	move_and_slide()
	_animate(delta)


func _scared(dist: float) -> bool:
	if data.get("aggressive", false):
		if dist < 4.5:
			_go("charge", 7.0)
		return false
	return dist < (7.0 if kind == "rabbit" else 11.0)


func _go(s: String, t: float) -> void:
	_state = s
	_state_t = t


func take_damage(amount: float, from_pos: Vector3, crit := false, slow := 0.0) -> void:
	if dead:
		return
	hp -= amount
	if slow > 0.0:
		_slow = maxf(_slow, slow)
	_flash = 0.1
	_set_overlay(_overlay)
	FX.damage_number(global_position + Vector3.UP * (radius * 2.0 + 0.6), ("%d!" if crit else "%d") % int(round(amount)),
		Color(1, 0.85, 0.2) if crit else Color.WHITE, 44)
	FX.burst(global_position + Vector3.UP * radius, Color(0.6, 0.08, 0.06), 8, 3.0, 0.08, 0.4)
	var kb := global_position - from_pos
	kb.y = 0.0
	if kb.length() > 0.01:
		velocity.x = kb.normalized().x * 4.0
		velocity.z = kb.normalized().z * 4.0
	if data.get("aggressive", false):
		_go("charge", 8.0)
	else:
		_go("flee", 5.0)
	if hp <= 0.0:
		_die()


func apply_slow(t: float) -> void:
	_slow = maxf(_slow, t)


func _die() -> void:
	dead = true
	remove_from_group("enemies")
	remove_from_group("animals")
	collision_layer = 0
	_set_overlay(null)
	Sfx.play_at("bloop", global_position, 0.2, -4.0)
	if colony:
		colony.on_animal_killed(self)
	var tw := create_tween()
	tw.tween_property(model, "rotation:z", PI / 2, 0.4).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.0)
	tw.tween_property(model, "position:y", -1.0, 1.0)
	tw.tween_callback(queue_free)


func _set_overlay(m: Material) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = m


func _animate(delta: float) -> void:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	_anim += delta * (3.0 + hspeed * 2.5)
	var amp := clampf(hspeed / 5.0, 0.0, 1.0) * 0.7
	for i in legs.size():
		var ph := 0.0 if i % 2 == 0 else PI
		if i >= 2:
			ph += PI * 0.5
		legs[i].rotation.x = sin(_anim + ph) * amp
	if kind == "rabbit":
		model.position.y = absf(sin(_anim)) * 0.25 * clampf(hspeed / 3.0, 0.0, 1.0)


# ---------------------------------------------------------------- modelos
func _mat(c: Color) -> StandardMaterial3D:
	return ColonyVisuals._mat(c)


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, c: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(c)
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _bx(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


func _sp(r: float, h := -1.0) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = h if h > 0.0 else r * 2.0
	s.radial_segments = 10
	s.rings = 6
	return s


func _leg(pos: Vector3, length: float, thick: float, c: Color, hoof: Color) -> void:
	var pivot := Node3D.new()
	pivot.position = pos
	model.add_child(pivot)
	_part(pivot, _bx(Vector3(thick, length, thick)), Vector3(0, -length / 2.0, 0), c)
	_part(pivot, _bx(Vector3(thick * 1.1, 0.08, thick * 1.2)), Vector3(0, -length + 0.04, 0.01), hoof)
	legs.append(pivot)


func _build_deer() -> void:
	var fur := Color(0.6, 0.4, 0.22)
	var belly := Color(0.85, 0.75, 0.6)
	_part(model, _bx(Vector3(0.5, 0.5, 1.15)), Vector3(0, 1.05, 0), fur)
	_part(model, _bx(Vector3(0.42, 0.12, 0.95)), Vector3(0, 0.78, 0), belly)
	_part(model, _bx(Vector3(0.24, 0.6, 0.26)), Vector3(0, 1.45, 0.55), fur, Vector3(0.45, 0, 0))
	var head := Node3D.new()
	head.position = Vector3(0, 1.78, 0.78)
	model.add_child(head)
	_part(head, _bx(Vector3(0.24, 0.24, 0.42)), Vector3(0, 0, 0.08), fur)
	_part(head, _bx(Vector3(0.14, 0.12, 0.08)), Vector3(0, -0.04, 0.32), Color(0.15, 0.1, 0.08))
	for sx in [-1.0, 1.0]:
		_part(head, _bx(Vector3(0.05, 0.16, 0.1)), Vector3(sx * 0.16, 0.14, -0.04), fur, Vector3(0, 0, sx * -0.5))
		_part(head, _sp(0.03), Vector3(sx * 0.12, 0.05, 0.2), Color(0.05, 0.05, 0.05))
		if randf() < 0.6:   # galhada
			var a := Color(0.85, 0.78, 0.62)
			_part(head, _bx(Vector3(0.04, 0.4, 0.04)), Vector3(sx * 0.1, 0.32, -0.05), a, Vector3(0, 0, sx * -0.3))
			_part(head, _bx(Vector3(0.03, 0.2, 0.03)), Vector3(sx * 0.2, 0.42, 0.04), a, Vector3(0.6, 0, sx * -0.6))
	_part(model, _bx(Vector3(0.12, 0.16, 0.08)), Vector3(0, 1.18, -0.6), Color(0.95, 0.93, 0.9))
	for z in [0.42, -0.42]:
		for x in [-0.17, 0.17]:
			_leg(Vector3(x, 0.85, z), 0.85, 0.09, fur.darkened(0.15), Color(0.12, 0.1, 0.08))


func _build_boar() -> void:
	var fur := Color(0.3, 0.22, 0.17)
	_part(model, _bx(Vector3(0.62, 0.6, 1.1)), Vector3(0, 0.62, 0), fur)
	_part(model, _bx(Vector3(0.3, 0.2, 0.8)), Vector3(0, 0.98, -0.05), fur.darkened(0.3))   # crina
	var head := Node3D.new()
	head.position = Vector3(0, 0.62, 0.65)
	model.add_child(head)
	_part(head, _bx(Vector3(0.46, 0.44, 0.42)), Vector3(0, 0, 0.1), fur)
	_part(head, _bx(Vector3(0.24, 0.2, 0.18)), Vector3(0, -0.08, 0.38), Color(0.55, 0.38, 0.32))
	for sx in [-1.0, 1.0]:
		_part(head, _bx(Vector3(0.04, 0.16, 0.04)), Vector3(sx * 0.15, 0.0, 0.42), Color(0.95, 0.92, 0.82), Vector3(-0.4, 0, 0))
		_part(head, _bx(Vector3(0.1, 0.14, 0.05)), Vector3(sx * 0.18, 0.26, 0.0), fur, Vector3(0, 0, sx * -0.4))
		_part(head, _sp(0.035), Vector3(sx * 0.16, 0.08, 0.3), Color(0.6, 0.1, 0.05))
	for z in [0.36, -0.36]:
		for x in [-0.2, 0.2]:
			_leg(Vector3(x, 0.38, z), 0.38, 0.13, fur.darkened(0.1), Color(0.1, 0.08, 0.07))


func _build_rabbit() -> void:
	var fur := Color(0.62, 0.55, 0.47)
	_part(model, _sp(0.22, 0.38), Vector3(0, 0.25, 0), fur)
	_part(model, _sp(0.14), Vector3(0, 0.42, 0.18), fur)
	for sx in [-1.0, 1.0]:
		_part(model, _bx(Vector3(0.06, 0.26, 0.04)), Vector3(sx * 0.06, 0.64, 0.14), fur, Vector3(-0.2, 0, sx * 0.15))
		_part(model, _sp(0.025), Vector3(sx * 0.08, 0.46, 0.3), Color(0.05, 0.05, 0.05))
	_part(model, _sp(0.07), Vector3(0, 0.3, -0.22), Color(0.97, 0.97, 0.95))
	for z in [0.1, -0.1]:
		for x in [-0.1, 0.1]:
			_leg(Vector3(x, 0.12, z), 0.12, 0.06, fur.darkened(0.1), fur.darkened(0.3))
