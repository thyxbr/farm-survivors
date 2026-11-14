class_name ColonySoldier
extends CharacterBody3D
## Soldado do exército da cidade. Fica no posto em volta do ponto de reunião (modo "guard")
## ou acompanha o jogador (modo "follow", útil para caçar). Ataca monstros que chegam perto.
## Usa o modelo do cavaleiro vestido pelo KnightLook conforme o tipo de unidade.

const KNIGHT := preload("res://assets/models/knight.glb")
const SHOT := preload("res://scripts/colony/tower_shot.gd")

var unit := "soldier"
var data: Dictionary
var colony: Node
var hp := -1.0
var max_hp := 100.0
var dead := false
var radius := 0.4
var post := Vector3.ZERO
var follow_offset := Vector3.ZERO
## Cooperativo: id comum entre servidor e clientes; puppet = réplica no cliente (segue os snapshots).
var net_id := 0
var puppet := false
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_attack := false

var model: Node3D
var parts := {}
var look := {}
var target: Enemy = null
var _retarget := 0.0
var _has_ammo := true   # o último disparo à distância teve munição (senão o intervalo dobra)
var _cd := 0.0
var _attack_t := -1.0
var _hit_done := false
var _anim_t := 0.0
var _calm := 0.0
var _stuck := 0.0
var _ignore := {}          # id do inimigo -> segundos (inalcançável atrás de um muro)
var _flash := 0.0
var _bar_root: Node3D
var _bar_fg: MeshInstance3D


func _ready() -> void:
	data = ColonyData.UNITS[unit]
	max_hp = float(data.hp) * _tech("unit_hp")
	if hp < 0.0:
		hp = max_hp
	add_to_group("soldiers")
	add_to_group("colony_units")
	collision_layer = 64
	collision_mask = 1 | 4     # mundo e monstros (o portão, na camada 32, não segura os soldados)
	floor_snap_length = 0.4
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	model = KNIGHT.instantiate()
	model.scale = Vector3.ONE * (1.05 if unit == "knight" else 0.95)
	add_child(model)
	for n in ["LegL", "LegR", "ArmL", "ArmR", "Body", "Head"]:
		parts[n] = model.find_child(n, true, false)
	look = KnightLook.apply(model, data.look)
	var arrow: Node3D = look.get("arrow")
	if arrow and is_instance_valid(arrow):
		arrow.visible = false
	_make_bar()
	_cd = randf() * 0.6
	_net_pos = position
	if puppet:
		collision_layer = 0
		collision_mask = 0


## Multiplicador de pesquisa da cidade (1.0 fora dela).
func _tech(key: String) -> float:
	return colony.mult(key) if colony and colony.has_method("mult") else 1.0


## Treino de Elite concluído: a vida máxima sobe e a atual sobe junto.
func refresh_max_hp() -> void:
	if dead:
		return
	var old := max_hp
	max_hp = float(data.hp) * _tech("unit_hp")
	hp = clampf(hp + max_hp - old, 1.0, max_hp)


## Dano de um golpe/flecha: Treino de Elite e, para os arqueiros, Flechas de Ferro.
func unit_damage() -> float:
	return float(data.damage) * _tech("unit_dmg") * (_tech("arrow_dmg") if is_ranged() else 1.0)


func is_ranged() -> bool:
	return data.get("ranged", false)


# ---------------------------------------------------------------- IA
func attacking() -> bool:
	return _attack_t >= 0.0


func _physics_process(delta: float) -> void:
	if puppet:
		_puppet_process(delta)
		return
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	if dead:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	_cd = maxf(0.0, _cd - delta)
	_retarget -= delta
	for id in _ignore.keys():
		_ignore[id] -= delta
		if _ignore[id] <= 0.0:
			_ignore.erase(id)
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0:
			_set_overlay(null)

	if target != null and (not is_instance_valid(target) or target.dead):
		target = null
	if _retarget <= 0.0:
		_retarget = 0.3
		target = _find_target()

	var spd: float = data.speed
	var move := Vector3.ZERO
	var face := Vector3.ZERO
	var reach: float = data.reach
	if _attack_t >= 0.0:
		_update_attack(delta)
		if target:
			face = target.global_position - global_position
	elif target:
		_calm = 0.0
		var to := target.global_position - global_position
		to.y = 0.0
		var dist := to.length() - target.radius
		face = to
		if dist <= reach:
			if _cd <= 0.0:
				_begin_attack()
		else:
			move = to.normalized() * spd
	else:
		_calm += delta
		var goal := _goal()
		var to := goal - global_position
		to.y = 0.0
		var d := to.length()
		var follow: bool = colony != null and colony.army_mode == "follow"
		if d > (2.0 if follow else 0.7):
			var mult := 1.0
			if d > 10.0:
				mult = 1.6
			move = to.normalized() * spd * mult * clampf(d / 2.0, 0.4, 1.0)
		elif follow:
			var p := _player()
			if p:
				face = p.facing()
		# descanso: recupera vida longe do combate
		if _calm > 4.0 and hp < max_hp:
			hp = minf(max_hp, hp + max_hp * 0.03 * delta)

	if face.length() > 0.01:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(face.x, face.z), 10.0 * delta)
	elif move.length() > 0.1:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(move.x, move.z), 10.0 * delta)
	velocity.x = move_toward(velocity.x, move.x, 30.0 * delta)
	velocity.z = move_toward(velocity.z, move.z, 30.0 * delta)
	var before := global_position
	move_and_slide()
	# preso num muro tentando alcançar um monstro do outro lado: desiste dele por um tempo
	if target and move.length() > 0.5:
		var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
		_stuck = _stuck + delta if moved < spd * delta * 0.2 else maxf(0.0, _stuck - delta)
		if _stuck > 1.2:
			_ignore[target.get_instance_id()] = 4.0
			target = null
			_stuck = 0.0
	_animate(delta)
	if _bar_root.visible:
		_bar_fg.scale.x = maxf(0.001, hp / max_hp)
		if hp >= max_hp - 0.5:
			_bar_root.visible = false


func _player() -> Player:
	return colony.follow_target() if colony else null


func _goal() -> Vector3:
	if colony and colony.army_mode == "follow":
		var p := _player()
		if p and not p.dead:
			return p.global_position + follow_offset.rotated(Vector3.UP, p.model.rotation.y)
	return post


func _find_target() -> Enemy:
	var aggro: float = data.aggro
	var anchor := _goal()
	var leash := aggro + (10.0 if colony and colony.army_mode == "follow" else 16.0)
	var best: Enemy = null
	var best_d := INF
	for e in colony.live_enemies():
		if _ignore.has(e.get_instance_id()):
			continue
		var d := global_position.distance_to(e.global_position)
		if d > aggro or anchor.distance_to(e.global_position) > leash:
			continue
		if d < best_d:
			best_d = d
			best = e
	return best


func _begin_attack() -> void:
	_attack_t = 0.0
	_hit_done = false
	if not is_ranged():
		Sfx.play_at("swing", global_position, 0.15, -12.0)


func _update_attack(delta: float) -> void:
	_attack_t += delta
	var hit_time := 0.45 if is_ranged() else 0.32
	if not _hit_done and _attack_t >= hit_time:
		_hit_done = true
		if target and is_instance_valid(target) and not target.dead:
			if is_ranged():
				_has_ammo = colony == null or colony.use_ammo(unit)
				var s := SHOT.new()
				s.kind = "arrow"
				s.target = target
				s.damage = unit_damage()
				get_parent().add_child(s)
				s.global_position = global_position + Vector3.UP * 1.45 + model.global_basis.z * 0.4
				Sfx.play_at("swing", global_position, 0.25, -16.0)
				if colony and colony.role == "server":
					Lobby.city_shot("arrow", s.global_position, target, 0.0)
			else:
				var to := target.global_position - global_position
				to.y = 0.0
				if to.length() - target.radius <= float(data.reach) + 0.6:
					target.take_damage(unit_damage() * randf_range(0.9, 1.1) * target.resist_mult("melee"), global_position, false)
	if _attack_t >= (0.75 if is_ranged() else 0.6):
		_attack_t = -1.0
		_cd = float(data.cooldown) * randf_range(0.9, 1.1) * (1.0 if _has_ammo else ColonyData.NO_AMMO_RATE)


# ---------------------------------------------------------------- dano
func take_damage(amount: float, from_pos: Vector3) -> void:
	if dead or puppet:
		return
	var dmg := maxf(1.0, amount * 50.0 / (50.0 + float(data.armor) * 4.0))
	hp -= dmg
	_calm = 0.0
	_flash = 0.1
	_set_overlay(_hit_mat())
	_bar_root.visible = true
	var kb := global_position - from_pos
	kb.y = 0.0
	if kb.length() > 0.01:
		kb = kb.normalized() * 3.0
		velocity.x = kb.x
		velocity.z = kb.z
	FX.burst(global_position + Vector3.UP, Color(0.8, 0.1, 0.08), 6, 3.0, 0.08, 0.4)
	if hp <= 0.0:
		_die()


func _die() -> void:
	dead = true
	remove_from_group("soldiers")
	remove_from_group("colony_units")
	collision_layer = 0
	_bar_root.visible = false
	Sfx.play_at("hurt", global_position, 0.1, -4.0)
	if colony and not puppet:
		colony.on_soldier_died(self)
		colony.on_soldier_gone(self, true)
	var tw := create_tween()
	tw.tween_property(parts.Body, "rotation:x", -1.4, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.5)
	tw.tween_property(model, "position:y", -1.6, 1.0)
	tw.tween_callback(queue_free)


## Deserção (salário atrasado) ou dispensa: some sem cair em combate.
func leave() -> void:
	if dead:
		return
	dead = true
	remove_from_group("soldiers")
	remove_from_group("colony_units")
	if colony and not puppet:
		colony.on_soldier_gone(self, false)
	FX.burst(global_position + Vector3.UP, Color(0.7, 0.7, 0.7), 20, 3.0, 0.15, 0.8)
	queue_free()


# ---------------------------------------------------------------- réplica (cliente)
func apply_net(pos: Vector3, yaw: float, new_hp: float, atk: bool) -> void:
	_net_pos = pos
	_net_yaw = yaw
	if new_hp < hp - 0.5:
		_flash = 0.1
		_set_overlay(_hit_mat())
		_bar_root.visible = true
	hp = new_hp
	if atk and not _net_attack:
		_attack_t = 0.0
		_hit_done = false
		if not is_ranged():
			Sfx.play_at("swing", global_position, 0.15, -12.0)
	_net_attack = atk


func net_die() -> void:
	if not dead:
		_die()


func _puppet_process(delta: float) -> void:
	if dead:
		return
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0:
			_set_overlay(null)
	var prev := global_position
	if global_position.distance_to(_net_pos) > 6.0:
		global_position = _net_pos
	else:
		global_position = global_position.lerp(_net_pos, 1.0 - exp(-12.0 * delta))
	model.rotation.y = lerp_angle(model.rotation.y, _net_yaw, 1.0 - exp(-12.0 * delta))
	velocity = (global_position - prev) / maxf(delta, 0.0001)
	if _attack_t >= 0.0:
		_attack_t += delta
		if _attack_t >= (0.75 if is_ranged() else 0.6):
			_attack_t = -1.0
	_animate(delta)
	if _bar_root.visible:
		_bar_fg.scale.x = maxf(0.001, hp / max_hp)
		if hp >= max_hp - 0.5:
			_bar_root.visible = false


var _hit_overlay: StandardMaterial3D


func _hit_mat() -> StandardMaterial3D:
	if _hit_overlay == null:
		_hit_overlay = StandardMaterial3D.new()
		_hit_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_hit_overlay.albedo_color = Color(1, 0.2, 0.2, 0.5)
		_hit_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _hit_overlay


func _set_overlay(m: Material) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = m


func _make_bar() -> void:
	_bar_root = Node3D.new()
	_bar_root.position.y = 2.35
	add_child(_bar_root)
	var bg := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.1)
	bg.mesh = q
	bg.material_override = _bar_mat(Color(0, 0, 0, 0.7), 0)
	_bar_root.add_child(bg)
	_bar_fg = MeshInstance3D.new()
	var q2 := QuadMesh.new()
	q2.size = Vector2(0.86, 0.06)
	_bar_fg.mesh = q2
	_bar_fg.material_override = _bar_mat(Color(0.35, 0.65, 1.0), 1)
	_bar_root.add_child(_bar_fg)
	_bar_root.visible = false


func _bar_mat(c: Color, priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.no_depth_test = true
	m.render_priority = priority
	return m


# ---------------------------------------------------------------- animação
func _animate(delta: float) -> void:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	_anim_t += delta * (2.0 + hspeed * 1.6)
	var s := sin(_anim_t)
	var amp: float = clampf(hspeed / 6.0, 0.0, 1.0) * 0.75
	var k := 1.0 - exp(-14.0 * delta)
	parts.LegL.rotation.x = lerpf(parts.LegL.rotation.x, s * amp, k)
	parts.LegR.rotation.x = lerpf(parts.LegR.rotation.x, -s * amp, k)
	var arm_l := Vector3(-s * amp * 0.5, 0, 0)
	var arm_r := Vector3(s * amp * 0.4 - 0.15, 0, 0)
	if _attack_t >= 0.0:
		if is_ranged():
			arm_l = Vector3(-1.52, 0, -0.12)
			arm_r = Vector3(-1.45, 0, 0.35).lerp(Vector3(-1.35, 0.2, 1.05), clampf(_attack_t / 0.45, 0.0, 1.0))
		else:
			var t := clampf(_attack_t / 0.6, 0.0, 1.0)
			if t < 0.4:
				arm_r = Vector3(-0.15, 0, 0).lerp(Vector3(-2.7, 0, -0.2), smoothstep(0.0, 0.4, t))
			elif t < 0.6:
				arm_r = Vector3(-2.7, 0, -0.2).lerp(Vector3(0.5, 0, 0.1), smoothstep(0.4, 0.6, t))
			else:
				arm_r = Vector3(0.5, 0, 0.1).lerp(Vector3(-0.15, 0, 0), smoothstep(0.6, 1.0, t))
			parts.ArmR.rotation = arm_r
	parts.ArmL.rotation = parts.ArmL.rotation.lerp(arm_l, k)
	if not (_attack_t >= 0.0 and not is_ranged()):
		parts.ArmR.rotation = parts.ArmR.rotation.lerp(arm_r, k)
	var holder: Node3D = look.get("holder")
	var arm: Node3D = look.get("arm")
	if holder and is_instance_valid(holder) and arm:
		holder.rotation.x = -arm.rotation.x * float(look.get("counter", 0.0))
