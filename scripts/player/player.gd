class_name Player
extends CharacterBody3D
## Cavaleiro controlado pelo jogador: movimento, câmera em 3ª pessoa, combo de espada, esquiva e magias.

signal died

const KNIGHT := preload("res://assets/models/knight.glb")
const FIREBALL := preload("res://scripts/player/fireball.gd")

const WALK_SPEED := 5.2
const SPRINT_SPEED := 8.6
const JUMP_VELOCITY := 7.0
const GRAVITY := 20.0
const DODGE_SPEED := 13.0
const DODGE_TIME := 0.36
const SWING_TIMES := [0.42, 0.42, 0.6]
const SWING_MULT := [1.0, 1.1, 1.6]

var dead := false
var cam_yaw: Node3D
var cam_pitch: Node3D
var spring: SpringArm3D
var camera: Camera3D
var model: Node3D
var parts := {}
var blade_meshes: Array[MeshInstance3D] = []
var torso_mesh: MeshInstance3D

var anim_t := 0.0
var idle_t := 0.0
var attacking := false
var attack_timer := 0.0
var combo := 0
var combo_window := 0.0
var buffered_attack := false
var hit_done := false
var dodge_timer := 0.0
var dodge_dir := Vector3.ZERO
var invuln := 0.0
var cast_timer := 0.0
var stamina_delay := 0.0
var shake := 0.0
var cooldowns := {"fireball": 0.0, "heal": 0.0, "frost_nova": 0.0}
var interact_target: Node3D = null
var spawn_point := Vector3(0, 0.5, 6)
var _footstep := 0.0

## Multiplayer: réplica de outro jogador (sem câmera, sem input, sem atributos locais).
var remote := false
var peer_id := 0
var display_name := ""
## Bloqueia o controle sem pausar a árvore (menus abertos no multiplayer).
var input_locked := false
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_floor := true
var _net_send_t := 0.0


func _ready() -> void:
	add_to_group("players")
	if remote:
		_ready_remote()
		return
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 4 | 8
	floor_snap_length = 0.4
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)

	_build_model()
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	cam_yaw = Node3D.new()
	cam_yaw.position.y = 1.55
	add_child(cam_yaw)
	cam_pitch = Node3D.new()
	cam_pitch.rotation.x = -0.25
	cam_yaw.add_child(cam_pitch)
	spring = SpringArm3D.new()
	spring.spring_length = 4.0
	spring.collision_mask = 1
	spring.margin = 0.2
	spring.position.x = 0.45
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	spring.shape = sphere
	spring.add_excluded_object(get_rid())
	cam_pitch.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.far = 400.0
	spring.add_child(camera)
	camera.current = true

	if Game.spawn_position != null:
		global_position = Game.spawn_position
		model.rotation.y = Game.spawn_yaw
		cam_yaw.rotation.y = Game.spawn_yaw + PI
		Game.spawn_position = null
	else:
		global_position = spawn_point
		model.rotation.y = PI
	Game.inventory_changed.connect(_update_equipment_visual)
	Game.leveled_up.connect(_on_level_up)
	Game.food_eaten.connect(_on_food_eaten)
	_update_equipment_visual()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_model() -> void:
	model = KNIGHT.instantiate()
	add_child(model)
	for n in ["LegL", "LegR", "ArmL", "ArmR", "Body", "Head"]:
		parts[n] = model.find_child(n, true, false)
	parts["body_y"] = parts.Body.position.y
	for n in ["Blade", "BladeTip"]:
		var m := model.find_child(n, true, false) as MeshInstance3D
		if m:
			blade_meshes.append(m)
	torso_mesh = model.find_child("Torso", true, false) as MeshInstance3D


func _ready_remote() -> void:
	# sem colisão: a réplica só mostra onde o outro jogador está
	collision_layer = 0
	collision_mask = 0
	_build_model()
	_net_pos = position
	var tag := Label3D.new()
	tag.text = display_name
	tag.font_size = 40
	tag.outline_size = 8
	tag.pixel_size = 0.006
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color(0.75, 0.9, 1.0)
	tag.position.y = 2.25
	add_child(tag)


func _unhandled_input(event: InputEvent) -> void:
	if remote or input_locked:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s: float = Game.settings.mouse_sensitivity * 0.01
		var inv := -1.0 if Game.settings.invert_y else 1.0
		cam_yaw.rotate_y(-event.relative.x * s)
		cam_pitch.rotation.x = clamp(cam_pitch.rotation.x - event.relative.y * s * inv, -1.25, 0.6)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if remote:
		_remote_process(delta)
		return
	if Network.is_client():
		_net_send(delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	if dead:
		velocity.x = move_toward(velocity.x, 0, 20 * delta)
		velocity.z = move_toward(velocity.z, 0, 20 * delta)
		move_and_slide()
		return

	_tick_timers(delta)
	_regen(delta)

	if input_locked:
		velocity.x = move_toward(velocity.x, 0, 45 * delta)
		velocity.z = move_toward(velocity.z, 0, 45 * delta)
		move_and_slide()
		_update_attack(delta)
		_animate(delta)
		_update_camera(delta)
		return

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var fwd := -cam_yaw.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var right := cam_yaw.global_basis.x
	right.y = 0
	right = right.normalized()
	var dir := (right * input.x + fwd * -input.y)
	if dir.length() > 1.0:
		dir = dir.normalized()

	var sprinting := Input.is_action_pressed("sprint") and dir.length() > 0.1 and Game.stamina > 1.0 and not attacking
	if sprinting:
		Game.stamina = max(0.0, Game.stamina - 20.0 * delta)
		stamina_delay = 0.6
	var speed := (SPRINT_SPEED if sprinting else WALK_SPEED) * Game.speed_multiplier()
	if attacking:
		speed *= 0.3
	elif cast_timer > 0:
		speed *= 0.6

	if dodge_timer > 0:
		dodge_timer -= delta
		velocity.x = dodge_dir.x * DODGE_SPEED
		velocity.z = dodge_dir.z * DODGE_SPEED
	else:
		var accel := 45.0 if is_on_floor() else 12.0
		velocity.x = move_toward(velocity.x, dir.x * speed, accel * delta)
		velocity.z = move_toward(velocity.z, dir.z * speed, accel * delta)

	if Input.is_action_just_pressed("jump") and is_on_floor() and not attacking and dodge_timer <= 0:
		velocity.y = JUMP_VELOCITY
	if Input.is_action_just_pressed("dodge"):
		_try_dodge(dir)
	if Input.is_action_just_pressed("attack"):
		_try_attack()
	for i in 3:
		if Input.is_action_just_pressed("spell_%d" % (i + 1)):
			cast(["fireball", "heal", "frost_nova"][i])
	if Input.is_action_just_pressed("potion"):
		_quick_potion("health_potion")
	if Input.is_action_just_pressed("mana_potion"):
		_quick_potion("mana_potion")
	if Input.is_action_just_pressed("eat"):
		Game.eat_selected()
	if Input.is_action_just_pressed("food_next"):
		Game.cycle_food()
	if Input.is_action_just_pressed("quicksave"):
		Game.save_game(global_position, model.rotation.y)
	if Input.is_action_just_pressed("quickload"):
		if Network.is_online():
			Game.notify.emit("Carregar save não funciona no multiplayer.", Color(1, 0.6, 0.5))
		else:
			Game.load_game()
			return

	_find_interact_target()
	if Input.is_action_just_pressed("interact") and interact_target:
		interact_target.interact(self)

	# orientação do modelo: mira para frente da câmera ao atacar/conjurar, senão para onde anda
	var face := Vector3.ZERO
	if attacking or cast_timer > 0:
		face = fwd
	elif dodge_timer > 0:
		face = dodge_dir
	elif dir.length() > 0.1:
		face = dir
	if face != Vector3.ZERO:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(face.x, face.z), 14.0 * delta)

	move_and_slide()
	if global_position.y < -25:
		global_position = spawn_point
		velocity = Vector3.ZERO

	_update_attack(delta)
	_animate(delta)
	_update_camera(delta)


func _tick_timers(delta: float) -> void:
	invuln = max(0.0, invuln - delta)
	cast_timer = max(0.0, cast_timer - delta)
	stamina_delay = max(0.0, stamina_delay - delta)
	for k in cooldowns:
		cooldowns[k] = max(0.0, cooldowns[k] - delta)
	Game.tick_food(delta)


func _regen(delta: float) -> void:
	Game.mp = min(Game.max_mp(), Game.mp + (0.8 + Game.attributes.int * 0.15) * delta)
	Game.hp = min(Game.max_hp(), Game.hp + (0.3 + Game.attributes.vit * 0.05 + Game.mod("regen")) * delta)
	if stamina_delay <= 0:
		Game.stamina = min(Game.max_stamina(), Game.stamina + 32.0 * delta)


func facing() -> Vector3:
	return Vector3(sin(model.rotation.y), 0, cos(model.rotation.y))


# ------------------------------------------------------------ esquiva
func _try_dodge(dir: Vector3) -> void:
	if dodge_timer > 0 or not is_on_floor() or Game.stamina < 20.0:
		return
	Game.stamina -= 20.0
	stamina_delay = 0.7
	dodge_dir = dir.normalized() if dir.length() > 0.1 else facing()
	dodge_timer = DODGE_TIME
	invuln = DODGE_TIME + 0.08
	attacking = false
	buffered_attack = false
	Sfx.play("swing", 0.1, -6.0)


# ------------------------------------------------------------ ataque corpo a corpo
func _try_attack() -> void:
	if dodge_timer > 0:
		return
	if attacking:
		if attack_timer > SWING_TIMES[combo - 1] * 0.35:
			buffered_attack = true
		return
	_start_swing()


func _start_swing() -> void:
	if Game.stamina < 8.0:
		Game.notify.emit("Sem fôlego!", Color(1, 0.8, 0.5))
		return
	combo = (combo % 3) + 1 if combo_window > 0 else 1
	attacking = true
	attack_timer = 0.0
	hit_done = false
	Game.stamina -= 8.0 + combo * 2.0
	stamina_delay = 0.6
	if is_on_floor():
		var f := facing()
		velocity.x += f.x * 3.0
		velocity.z += f.z * 3.0
	Sfx.play("swing", 0.12)


func _update_attack(delta: float) -> void:
	if not attacking:
		combo_window = max(0.0, combo_window - delta)
		return
	attack_timer += delta
	var dur: float = SWING_TIMES[combo - 1]
	var t := attack_timer / dur
	if t >= 0.42 and not hit_done:
		hit_done = true
		_do_hit()
	if t >= 1.0:
		attacking = false
		combo_window = 0.45
		parts.Body.rotation.y = 0.0
		if buffered_attack:
			buffered_attack = false
			_start_swing()


func _do_hit() -> void:
	var mult: float = SWING_MULT[combo - 1]
	var reach := 2.4 if combo < 3 else 2.9
	var hit_any := false
	var f := facing()
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var to: Vector3 = e.global_position - global_position
		to.y = 0
		var dist := to.length()
		if dist > reach + e.radius:
			continue
		if combo < 3 and dist > 0.6 and f.dot(to.normalized()) < 0.3:
			continue
		var crit: bool = randf() < 0.08 + Game.attributes.agi * 0.004 + Game.mod("crit")
		var dmg: float = Game.melee_damage() * mult * randf_range(0.9, 1.1) * (1.8 if crit else 1.0)
		e.take_damage(dmg, global_position, crit)
		hit_any = true
	if hit_any:
		Sfx.play("hit")
		add_shake(0.12 if combo < 3 else 0.22)


# ------------------------------------------------------------ magias
func cast(id: String) -> void:
	var sp: Dictionary = ItemDB.SPELLS[id]
	if not Game.knows_spell(id):
		Game.notify.emit("%s exige nível %d" % [sp.name, sp.level], Color(1, 0.6, 0.6))
		return
	if cooldowns[id] > 0 or attacking or dodge_timer > 0:
		return
	if Game.mp < sp.cost:
		Game.notify.emit("Mana insuficiente!", Color(0.6, 0.7, 1.0))
		return
	Game.mp -= sp.cost
	cooldowns[id] = sp.cooldown
	cast_timer = 0.4
	match id:
		"fireball":
			_cast_fireball()
		"heal":
			var amount := 30.0 + Game.spell_power() * 4.0
			Game.hp = min(Game.max_hp(), Game.hp + amount)
			_heal_fx()
			FX.damage_number(global_position + Vector3.UP * 2.2, "+%d" % amount, Color(0.4, 1.0, 0.5))
			Network.send_event("heal", global_position)
		"frost_nova":
			_cast_frost_nova()
	Game.stats_changed.emit()


func _cast_fireball() -> void:
	var origin := global_position + Vector3.UP * 1.3 + facing() * 0.6
	var from := camera.global_position
	var to := from - camera.global_basis.z * 80.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var target: Vector3 = hit.position if not hit.is_empty() else to
	var fb := FIREBALL.new()
	fb.direction = (target - origin).normalized()
	fb.damage = (18.0 + Game.spell_power() * 2.5) * Game.damage_mult()
	get_tree().current_scene.add_child(fb)
	fb.global_position = origin
	Sfx.play("fire")
	Network.send_event("fireball", origin, fb.direction)


func _cast_frost_nova() -> void:
	var radius := 6.5
	_frost_fx(radius)
	Network.send_event("frost_nova", global_position)
	add_shake(0.15)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		if e.global_position.distance_to(global_position) <= radius + e.radius:
			e.take_damage((15.0 + Game.spell_power() * 2.0) * Game.damage_mult(), global_position, false, 4.0)


func _frost_fx(radius: float) -> void:
	FX.ring(global_position, Color(0.55, 0.85, 1.0, 0.9), radius, 0.5)
	FX.burst(global_position + Vector3.UP * 0.5, Color(0.7, 0.9, 1.0), 50, 9.0, 0.14, 0.7, -2.0)
	Sfx.play("frost", 0.0)


func _heal_fx() -> void:
	FX.burst(global_position + Vector3.UP, Color(0.4, 1.0, 0.5), 30, 3.0, 0.1, 1.0, 2.0)
	Sfx.play("heal", 0.0)


func _quick_potion(id: String) -> void:
	if Game.count_item(id) <= 0:
		Game.notify.emit("Sem %s!" % ItemDB.get_item(id).name, Color(1, 0.6, 0.6))
		return
	if Game.use_item(id):
		Sfx.play("heal", 0.0, -4.0)
		FX.burst(global_position + Vector3.UP, Color(1, 0.35, 0.35) if id == "health_potion" else Color(0.4, 0.5, 1), 20, 2.5, 0.08, 0.8, 2.0)


# ------------------------------------------------------------ comida
func _on_food_eaten(id: String) -> void:
	if dead or not is_inside_tree():
		return
	var it := ItemDB.get_item(id)
	var c: Color = it.get("color", ItemDB.CROPS[id].color if ItemDB.CROPS.has(id) else Color(0.6, 1, 0.5))
	Sfx.play("eat", 0.1)
	FX.burst(global_position + Vector3.UP * 1.5, c, 18, 2.2, 0.08, 0.6, -4.0)
	if it.has("buff"):
		FX.ring(global_position, Color(c.r, c.g, c.b, 0.85), 2.2, 0.5)
		FX.burst(global_position + Vector3.UP * 0.3, c, 30, 3.5, 0.1, 1.0, 3.0)
		Sfx.play("heal", 0.0, -5.0)
	match it.get("special", ""):
		"fire_nova":
			_food_fire_nova()
		"frost_nova":
			_food_frost_nova()


## Chili do Dragão: explosão de fogo que empurra e queima tudo em volta.
func _food_fire_nova() -> void:
	var radius := 7.5
	FX.ring(global_position, Color(1, 0.45, 0.1, 0.95), radius, 0.55)
	FX.burst(global_position + Vector3.UP * 0.6, Color(1, 0.5, 0.1), 70, 10.0, 0.16, 0.8, -1.0)
	FX.burst(global_position + Vector3.UP * 1.0, Color(1, 0.85, 0.3), 40, 6.0, 0.12, 0.6, 2.0)
	Sfx.play("explode", 0.05)
	add_shake(0.35)
	var dmg := (40.0 + Game.level * 6.0 + Game.spell_power() * 2.0) * Game.damage_mult()
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		if e.global_position.distance_to(global_position) <= radius + e.radius:
			e.take_damage(dmg, global_position, false)


## Chá de Menta Gélida: congela (lentidão forte) e fere os inimigos próximos.
func _food_frost_nova() -> void:
	var radius := 8.0
	FX.ring(global_position, Color(0.55, 0.9, 1.0, 0.95), radius, 0.6)
	FX.burst(global_position + Vector3.UP * 0.5, Color(0.75, 0.95, 1.0), 60, 9.0, 0.14, 0.8, -2.0)
	Sfx.play("frost", 0.0)
	add_shake(0.2)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		if e.global_position.distance_to(global_position) <= radius + e.radius:
			e.take_damage((12.0 + Game.level * 3.0) * Game.damage_mult(), global_position, false, 6.0)


# ------------------------------------------------------------ dano e morte
func take_damage(amount: float, from_pos: Vector3) -> void:
	if remote:
		# no servidor, o golpe de um inimigo na réplica vira dano no PC do dono
		if Network.is_server() and not dead:
			Network.server_damage_player(peer_id, amount, from_pos)
		return
	if dead or invuln > 0:
		return
	var final_dmg: float = max(1.0, amount * 50.0 / (50.0 + Game.defense() * 4.0))
	Game.hp -= final_dmg
	invuln = 0.45
	var kb := global_position - from_pos
	kb.y = 0
	if kb.length() > 0.01:
		kb = kb.normalized() * 6.0
		velocity.x = kb.x
		velocity.z = kb.z
	velocity.y = 3.0
	FX.damage_number(global_position + Vector3.UP * 2.0, str(int(round(final_dmg))), Color(1, 0.3, 0.25), 56)
	FX.burst(global_position + Vector3.UP, Color(0.8, 0.05, 0.05), 12, 3.0)
	Sfx.play("hurt")
	add_shake(0.3)
	_flash()
	Game.stats_changed.emit()
	if Game.hp <= 0:
		_die()


func _flash() -> void:
	var over := StandardMaterial3D.new()
	over.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	over.albedo_color = Color(1, 0.2, 0.2, 0.5)
	over.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		mi.material_overlay = over
	get_tree().create_timer(0.12).timeout.connect(_clear_flash)


func _clear_flash() -> void:
	if is_instance_valid(model):
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			mi.material_overlay = null


func _die() -> void:
	dead = true
	Game.hp = 0
	Game.clear_food()
	attacking = false
	Sfx.play("death", 0.0)
	var tw := create_tween()
	tw.tween_property(parts.Body, "rotation:x", -1.4, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(parts.Body, "position:y", 0.35, 0.6)
	died.emit()


func revive(pos: Vector3) -> void:
	dead = false
	Game.hp = Game.max_hp()
	Game.mp = Game.max_mp()
	Game.stamina = Game.max_stamina()
	global_position = pos
	velocity = Vector3.ZERO
	parts.Body.rotation = Vector3.ZERO
	parts.Body.position.y = parts.body_y
	invuln = 2.0
	Game.stats_changed.emit()


# ------------------------------------------------------------ interação
func _find_interact_target() -> void:
	var best: Node3D = null
	var best_d := 3.0
	for n in get_tree().get_nodes_in_group("interactable"):
		var d: float = n.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = n
	interact_target = best


# ------------------------------------------------------------ visual
func _update_equipment_visual() -> void:
	apply_look(Game.equipment.weapon, Game.equipment.armor)
	Network.send_look(Game.equipment.weapon, Game.equipment.armor)


func apply_look(wid: String, armor: String) -> void:
	var col: Color = ItemDB.get_item(wid).get("color", Color(0.5, 0.5, 0.5)) if wid != "" else Color(0, 0, 0, 0)
	for b in blade_meshes:
		b.visible = wid != ""
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.metallic = 0.0 if wid == "wooden_sword" else 0.85
		m.roughness = 0.8 if wid == "wooden_sword" else 0.25
		if wid == "knight_blade" or wid == "goblin_cleaver":
			m.emission_enabled = true
			m.emission = col
			m.emission_energy_multiplier = 0.6
		b.material_override = m
	if torso_mesh:
		var armor_colors := {"": Color(0.35, 0.25, 0.18), "leather_armor": Color(0.45, 0.28, 0.13),
			"chain_mail": Color(0.55, 0.58, 0.65), "royal_plate": Color(0.85, 0.7, 0.35)}
		var tm := StandardMaterial3D.new()
		tm.albedo_color = armor_colors.get(armor, Color.GRAY)
		tm.metallic = 0.0 if armor in ["", "leather_armor"] else 0.85
		tm.roughness = 0.8 if armor in ["", "leather_armor"] else 0.35
		torso_mesh.material_override = tm


func _on_level_up(_lvl: int) -> void:
	Sfx.play("levelup", 0.0)
	FX.burst(global_position + Vector3.UP * 0.2, Color(1, 0.85, 0.3), 60, 6.0, 0.12, 1.2, 3.0)
	FX.ring(global_position, Color(1, 0.85, 0.3, 0.9), 3.0, 0.8)


func add_shake(amount: float) -> void:
	if remote:
		if Network.is_server():
			Network.server_shake_player(peer_id, amount)
		return
	shake = max(shake, amount)


# ------------------------------------------------------------ multiplayer
const NF_FLOOR := 1
const NF_ATTACK := 2
const NF_DODGE := 4
const NF_CAST := 8
const NF_DEAD := 16


func _net_send(delta: float) -> void:
	_net_send_t -= delta
	if _net_send_t > 0.001:
		return
	_net_send_t = maxf(_net_send_t + 1.0 / Network.SEND_RATE, 0.0)
	var flags := (NF_FLOOR if is_on_floor() else 0) | (NF_ATTACK if attacking else 0) \
		| (NF_DODGE if dodge_timer > 0 else 0) | (NF_CAST if cast_timer > 0 else 0) | (NF_DEAD if dead else 0)
	Network.send_player_state(global_position, model.rotation.y, velocity, flags, combo, attack_timer)


func apply_net_state(pos: Vector3, yaw: float, vel: Vector3, flags: int, c: int, attack_t: float) -> void:
	_net_pos = pos
	_net_yaw = yaw
	velocity = vel
	_net_floor = flags & NF_FLOOR != 0
	dodge_timer = 0.12 if flags & NF_DODGE else 0.0
	cast_timer = 0.15 if flags & NF_CAST else 0.0
	if flags & NF_ATTACK:
		if not attacking or c != combo:
			Sfx.play("swing", 0.12, -6.0)
		attacking = true
		combo = clampi(c, 1, 3)
		attack_timer = attack_t
	elif attacking:
		attacking = false
		parts.Body.rotation.y = 0.0
	var now_dead := flags & NF_DEAD != 0
	if now_dead and not dead:
		dead = true
		attacking = false
		var tw := create_tween()
		tw.tween_property(parts.Body, "rotation:x", -1.4, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(parts.Body, "position:y", 0.35, 0.6)
	elif dead and not now_dead:
		dead = false
		parts.Body.rotation = Vector3.ZERO
		parts.Body.position.y = parts.body_y


func _remote_process(delta: float) -> void:
	if global_position.distance_to(_net_pos) > 8.0:
		global_position = _net_pos
	else:
		global_position = global_position.lerp(_net_pos, 1.0 - exp(-15.0 * delta))
	model.rotation.y = lerp_angle(model.rotation.y, _net_yaw, 1.0 - exp(-15.0 * delta))
	if dead:
		return
	dodge_timer = max(0.0, dodge_timer - delta)
	cast_timer = max(0.0, cast_timer - delta)
	if attacking:
		attack_timer = minf(attack_timer + delta, SWING_TIMES[combo - 1])
	_animate(delta)


## Efeitos das ações de outro jogador (só visuais: o dano já foi enviado pelo dono).
func play_remote_event(kind: String, a: Vector3, b: Vector3) -> void:
	match kind:
		"fireball":
			var fb := FIREBALL.new()
			fb.direction = b
			fb.visual_only = true
			get_tree().current_scene.add_child(fb)
			fb.global_position = a
			Sfx.play("fire", 0.08, -4.0)
		"frost_nova":
			_frost_fx(6.5)
		"heal":
			_heal_fx()


func _update_camera(delta: float) -> void:
	shake = max(0.0, shake - delta * 1.2)
	camera.h_offset = randf_range(-1, 1) * shake * 0.4
	camera.v_offset = randf_range(-1, 1) * shake * 0.4


func _animate(delta: float) -> void:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var on_floor := _net_floor if remote else is_on_floor()
	anim_t += delta * (2.0 + hspeed * 1.6)
	idle_t += delta
	var amp: float = clamp(hspeed / 6.0, 0.0, 1.0) * 0.75
	var s := sin(anim_t)
	var k := 1.0 - exp(-14.0 * delta)
	var leg_l := s * amp
	var leg_r := -s * amp
	var body_x := 0.0
	var body_y: float = parts.body_y + abs(s) * 0.05 * amp + sin(idle_t * 2.0) * 0.01
	if not on_floor:
		leg_l = -0.5
		leg_r = 0.3
	if dodge_timer > 0:
		body_x = 0.7
		body_y = parts.body_y - 0.25
		leg_l = -0.9
		leg_r = 0.6
	parts.LegL.rotation.x = lerp(parts.LegL.rotation.x, leg_l, k)
	parts.LegR.rotation.x = lerp(parts.LegR.rotation.x, leg_r, k)
	parts.Body.rotation.x = lerp(parts.Body.rotation.x, body_x, k)
	parts.Body.position.y = lerp(parts.Body.position.y, body_y, k)

	# braço do escudo / conjuração
	var arm_l := Vector3(-s * amp * 0.5, 0, 0)
	if cast_timer > 0:
		arm_l = Vector3(-1.5, 0, 0.5)
	parts.ArmL.rotation = parts.ArmL.rotation.lerp(arm_l, k)

	# braço da espada
	var arm_r := Vector3(s * amp * 0.4 - 0.15, 0, 0)
	if attacking:
		var t: float = clamp(attack_timer / SWING_TIMES[combo - 1], 0.0, 1.0)
		match combo:
			1:
				arm_r = _swing_pose(t, Vector3(-2.8, 0, -0.2), Vector3(0.5, 0, 0.1))
			2:
				arm_r = _swing_pose(t, Vector3(-1.6, 0, -1.3), Vector3(-1.4, 0, 1.0))
				parts.Body.rotation.y = lerp(0.5, -0.6, smoothstep(0.25, 0.55, t))
			3:
				arm_r = Vector3(-1.5, 0, -0.5)
				parts.Body.rotation.y = -TAU * smoothstep(0.2, 0.75, t)
		parts.ArmR.rotation = arm_r
	else:
		parts.Body.rotation.y = lerp(parts.Body.rotation.y, 0.0, k)
		parts.ArmR.rotation = parts.ArmR.rotation.lerp(arm_r, k)

	if on_floor and hspeed > 1.0:
		_footstep -= delta * hspeed
		if _footstep <= 0:
			_footstep = 2.2


func _swing_pose(t: float, windup: Vector3, strike: Vector3) -> Vector3:
	if t < 0.3:
		return Vector3(-0.15, 0, 0).lerp(windup, smoothstep(0.0, 0.3, t))
	if t < 0.5:
		return windup.lerp(strike, smoothstep(0.3, 0.5, t))
	return strike.lerp(Vector3(-0.15, 0, 0), smoothstep(0.5, 1.0, t))
