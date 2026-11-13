class_name Player
extends CharacterBody3D
## Cavaleiro controlado pelo jogador: movimento, câmera em 3ª pessoa, combo de espada, esquiva e magias.

signal died

const KNIGHT := preload("res://assets/models/knight.glb")
const FIREBALL := preload("res://scripts/player/fireball.gd")
const PROJECTILE := preload("res://scripts/player/projectile.gd")
const AUTO_WEAPONS := preload("res://scripts/survival/auto_weapons.gd")

const WALK_SPEED := 5.2
const SPRINT_SPEED := 8.6
const JUMP_VELOCITY := 7.0
const GRAVITY := 20.0
const DODGE_SPEED := 13.0
const DODGE_TIME := 0.36
const SWING_TIMES := [0.42, 0.42, 0.6]
const SWING_MULT := [1.0, 1.1, 1.6]
const STAFF_TIMES := [0.4, 0.4, 0.6]
const BOW_FULL := 0.85        # segundos para tensionar o arco por completo
const BOW_RECOVER := 0.28
## Ganho da aproximação exponencial da velocidade (chão: andando, parando, invertendo; ar).
const ACCEL_RUN := 14.0
const ACCEL_STOP := 18.0
const ACCEL_TURN := 22.0
const ACCEL_AIR := 4.0

var dead := false
var cam_yaw: Node3D
var cam_pitch: Node3D
var spring: SpringArm3D
var camera: Camera3D
var model: Node3D
var parts := {}
## Referências do visual da arma (KnightLook.apply): classe, suporte, ponta, flecha.
var look := {"class": "sword", "holder": null, "tip": null, "arrow": null, "arm": null, "elbow": null, "counter": 0.0}
## Arco: tensionando (segurando o ataque) e quanto já tensionou.
var drawing := false
var draw_t := 0.0

var anim_t := 0.0
var idle_t := 0.0
## Animação procedural: amplitude da passada, inclinação, curva e impacto da aterrissagem (suavizados).
var _amp := 0.0      # 0..1: quanto está andando (suavizado)
var _run := 0.0      # 0..1: quanto está correndo
var _air := 0.0      # 0..1: quanto está no ar
var _cast_t := 99.0  # segundos desde a última magia (a pose toca até KnightMoves.CAST_TIME)
var _cast_kind := "fireball"
var _pending_spell := ""   # magia esperando o fim do movimento de apontar
var _pending_t := 0.0
var _lean := 0.0
var _bank := 0.0
var _land := 0.0
var _air_vy := 0.0
var _was_floor := true
var _prev_yaw := 0.0
var _prev_hvel := Vector3.ZERO
## Capa com física (CapeRig) e câmera: posição da última física, para detectar teleportes.
var cape: CapeRig
var _last_pos := Vector3.ZERO
var _cam_y := 0.0
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
## Desafio da Horda em grupo: parado enquanto o grupo escolhe as cartas de nível.
var horde_frozen := false
## Digitando no chat: as teclas vão para a caixa de texto, não para o personagem.
var chat_typing := false
## Defesa da Cidade: no modo construção o clique posiciona prédios (sem atacar, esquivar ou conjurar).
var build_lock := false
var name_tag: Label3D
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_floor := true
var _net_vel := Vector3.ZERO
var _net_age := 0.0
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

	# o suporte da câmera fica fora da hierarquia interpolada: o mouse gira na hora, e
	# _process o coloca sobre a posição interpolada do jogador a cada quadro.
	cam_yaw = Node3D.new()
	cam_yaw.top_level = true
	cam_yaw.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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
	_snap_visuals()
	Game.inventory_changed.connect(_update_equipment_visual)
	Game.leveled_up.connect(_on_level_up)
	Game.food_eaten.connect(_on_food_eaten)
	_update_equipment_visual()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_model() -> void:
	# jogador e réplicas são interpolados entre os passos de física (movimento liso em telas >60 Hz)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	model = KNIGHT.instantiate()
	add_child(model)
	parts = KnightAnim.rig(model)
	var cape_mesh := model.find_child("Cape", true, false) as MeshInstance3D
	if cape_mesh:
		cape = CapeRig.attach(cape_mesh)
	if cape:
		cape.add_capsule(parts.LegL, 0.11, 0.95, Vector3(0, -0.45, 0))
		cape.add_capsule(parts.LegR, 0.11, 0.95, Vector3(0, -0.45, 0))
		cape.add_capsule(parts.Body, 0.14, 0.75, Vector3(0, 0.25, 0.02))


## Depois de um teleporte: sem interpolação do ponto antigo ao novo e capa de volta ao repouso.
func _snap_visuals() -> void:
	_last_pos = global_position
	_cam_y = global_position.y
	reset_physics_interpolation()
	if cape:
		cape.reset()
	if cam_yaw:
		cam_yaw.global_position = global_position + Vector3.UP * 1.55


func _check_teleport() -> void:
	if global_position.distance_to(_last_pos) > 3.0:
		_snap_visuals()
	_last_pos = global_position


func _process(delta: float) -> void:
	if remote or cam_yaw == null:
		return
	# câmera sobre a posição interpolada; na vertical segue com leve atraso (degraus, pulos)
	var o := get_global_transform_interpolated().origin
	_cam_y = lerpf(_cam_y, o.y, 1.0 - exp(-12.0 * delta))
	_cam_y = clampf(_cam_y, o.y - 0.6, o.y + 0.6)
	cam_yaw.global_position = Vector3(o.x, _cam_y + 1.55, o.z)


func _ready_remote() -> void:
	# sem colisão: a réplica só mostra onde o outro jogador está
	collision_layer = 0
	collision_mask = 0
	_build_model()
	_net_pos = position
	_snap_visuals()
	var tag := Label3D.new()
	name_tag = tag
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
	else:
		_local_process(delta)
	_check_teleport()


func _local_process(delta: float) -> void:
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

	if input_locked or horde_frozen or chat_typing:
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

	var sprinting := Input.is_action_pressed("sprint") and dir.length() > 0.1 and Game.stamina > 1.0 and not attacking and not drawing
	if sprinting:
		Game.stamina = max(0.0, Game.stamina - 20.0 * delta)
		stamina_delay = 0.6
	var speed := (SPRINT_SPEED if sprinting else WALK_SPEED) * Game.speed_multiplier()
	if attacking:
		speed *= 0.3 if look["class"] == "sword" else 0.55
	elif drawing:
		speed *= 0.45
	elif cast_timer > 0:
		speed *= 0.6

	if dodge_timer > 0:
		dodge_timer -= delta
		velocity.x = dodge_dir.x * DODGE_SPEED
		velocity.z = dodge_dir.z * DODGE_SPEED
	else:
		# aproximação exponencial: arranca rápido e assenta suave; inverter a direção freia mais forte
		var hv := Vector3(velocity.x, 0, velocity.z)
		var target := dir * speed
		var rate := ACCEL_AIR
		if is_on_floor():
			if target.length() < 0.1:
				rate = ACCEL_STOP
			elif hv.dot(target) < 0.0:
				rate = ACCEL_TURN
			else:
				rate = ACCEL_RUN
		hv = hv.lerp(target, 1.0 - exp(-rate * delta))
		if target == Vector3.ZERO and hv.length() < 0.05:
			hv = Vector3.ZERO
		velocity.x = hv.x
		velocity.z = hv.z

	if Input.is_action_just_pressed("jump") and is_on_floor() and not attacking and dodge_timer <= 0:
		velocity.y = JUMP_VELOCITY
	if Input.is_action_just_pressed("dodge") and not build_lock:
		_try_dodge(dir)
	if build_lock:
		_cancel_draw()
	elif look["class"] == "bow":
		_update_bow(delta)
	elif Input.is_action_just_pressed("attack"):
		_try_attack()
	for i in 3:
		if Input.is_action_just_pressed("spell_%d" % (i + 1)) and not build_lock:
			cast(["fireball", "heal", "frost_nova"][i])
	if Input.is_action_just_pressed("potion") and not build_lock:   # R gira a construção no modo construção
		_quick_potion("health_potion")
	if Input.is_action_just_pressed("mana_potion"):
		_quick_potion("mana_potion")
	if Input.is_action_just_pressed("eat"):
		Game.eat_selected()
	if Input.is_action_just_pressed("food_next"):
		Game.cycle_food()
	var scene := get_tree().current_scene
	if Input.is_action_just_pressed("quicksave"):
		if scene.has_method("quick_save"):
			scene.quick_save()
		else:
			Game.save_game(global_position, model.rotation.y)
	if Input.is_action_just_pressed("quickload"):
		if scene.has_method("quick_load"):
			scene.quick_load()
			return
		elif Network.is_online():
			Game.notify.emit("Carregar save não funciona no multiplayer.", Color(1, 0.6, 0.5))
		else:
			Game.load_game()
			return

	_find_interact_target()
	if Input.is_action_just_pressed("interact") and interact_target:
		interact_target.interact(self)

	# orientação do modelo: mira para frente da câmera ao atacar/conjurar, senão para onde anda
	var face := Vector3.ZERO
	if attacking or cast_timer > 0 or drawing:
		face = fwd
	elif dodge_timer > 0:
		face = dodge_dir
	elif dir.length() > 0.1:
		face = dir
	if face != Vector3.ZERO:
		var turn := 22.0 if (attacking or cast_timer > 0 or drawing or dodge_timer > 0) else 13.0
		model.rotation.y = lerp_angle(model.rotation.y, atan2(face.x, face.z), 1.0 - exp(-turn * delta))

	move_and_slide()
	if global_position.y < -25:
		global_position = spawn_point
		velocity = Vector3.ZERO

	_update_attack(delta)
	_animate(delta)
	_update_camera(delta)


func _tick_timers(delta: float) -> void:
	if _pending_spell != "":
		_pending_t -= delta
		if _pending_t <= 0.0:
			_pending_spell = ""
			if not dead:
				_cast_fireball()
	invuln = max(0.0, invuln - delta)
	cast_timer = max(0.0, cast_timer - delta)
	stamina_delay = max(0.0, stamina_delay - delta)
	for k in cooldowns:
		cooldowns[k] = max(0.0, cooldowns[k] - delta)
	Game.tick_food(delta)


func _regen(delta: float) -> void:
	Game.mp = min(Game.max_mp(), Game.mp + (0.8 + Game.attr("int") * 0.15) * delta)
	Game.hp = min(Game.max_hp(), Game.hp + (0.3 + Game.attr("vit") * 0.05 + Game.mod("regen")) * delta)
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
	_cancel_draw()
	Sfx.play("swing", 0.1, -6.0)


# ------------------------------------------------------------ ataque corpo a corpo
func _try_attack() -> void:
	if dodge_timer > 0:
		return
	if attacking:
		if attack_timer > _swing_time(combo) * 0.35:
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
	var staff: bool = look["class"] == "staff"
	Game.stamina -= (4.0 + combo * 1.5) if staff else (8.0 + combo * 2.0)
	stamina_delay = 0.6
	if staff:
		Sfx.play("swing", 0.15, -10.0)
		return
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
	var dur := _swing_time(combo)
	var t := attack_timer / dur
	if t >= (0.35 if look["class"] == "staff" else 0.42) and not hit_done:
		hit_done = true
		match look["class"]:
			"staff":
				_staff_shot()
			"bow":
				pass   # o disparo do arco acontece ao soltar o botão
			_:
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
		var crit: bool = randf() < Game.crit_chance()
		var dmg: float = Game.melee_damage() * mult * randf_range(0.9, 1.1) * (1.8 if crit else 1.0)
		e.take_damage(dmg, global_position, crit, 2.5 if _weapon_fx() == "slow" else 0.0)
		Game.on_damage_dealt(dmg)
		hit_any = true
	if hit_any:
		Sfx.play("hit")
		add_shake(0.12 if combo < 3 else 0.22)


func _swing_time(c: int) -> float:
	match look["class"]:
		"staff":
			return STAFF_TIMES[clampi(c, 1, 3) - 1]
		"bow":
			return BOW_RECOVER
	return SWING_TIMES[clampi(c, 1, 3) - 1]


func _weapon_fx() -> String:
	return ItemDB.get_item(Game.equipment.weapon).get("fx", "")


func _weapon_color() -> Color:
	return ItemDB.get_item(Game.equipment.weapon).get("color", Color(0.6, 0.8, 1.0))


# ------------------------------------------------------------ ataque à distância (cajado e arco)
## Direção da mira: do ponto de origem até onde a câmera aponta.
func aim_dir(origin: Vector3) -> Vector3:
	var from := camera.global_position
	var to := from - camera.global_basis.z * 80.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var target: Vector3 = hit.position if not hit.is_empty() else to
	return (target - origin).normalized()


## De onde saem as magias: a gema do cajado, ou a mão esquerda sem cajado.
func spell_origin() -> Vector3:
	if look["class"] == "staff":
		return weapon_tip()
	var hand := model.find_child("ArmL_Hand", true, false) as MeshInstance3D
	if hand and hand.is_inside_tree():
		return hand.global_transform * hand.get_aabb().get_center() + facing() * 0.25
	return global_position + Vector3.UP * 1.3 + facing() * 0.6


func weapon_tip() -> Vector3:
	var tip: Node3D = look.get("tip")
	if tip and is_instance_valid(tip) and tip.is_inside_tree():
		return tip.global_position
	return global_position + Vector3.UP * 1.3 + facing() * 0.6


## Cajado: faísca arcana; o 3º golpe do combo dispara um leque de 3 mais fortes.
func _staff_shot() -> void:
	var origin := weapon_tip()
	var dir := aim_dir(origin)
	var spread := [0.0] if combo < 3 else [-0.14, 0.0, 0.14]
	for a in spread:
		var crit: bool = randf() < Game.crit_chance()
		var d: Vector3 = dir.rotated(Vector3.UP, a)
		_spawn_projectile("bolt", origin, d, Game.melee_damage() * (1.25 if combo == 3 else 1.0) * (1.8 if crit else 1.0), crit, 0)
		Network.send_event("bolt", origin, d)
	Sfx.play("fire", 0.2, -8.0)


## Arco: segurar o ataque tensiona, soltar dispara (dano e alcance crescem com a tensão).
func _update_bow(delta: float) -> void:
	if Input.is_action_just_pressed("attack") and not drawing and not attacking and dodge_timer <= 0:
		if Game.stamina < 5.0:
			Game.notify.emit("Sem fôlego!", Color(1, 0.8, 0.5))
		else:
			drawing = true
			draw_t = 0.0
			Sfx.play("swing", 0.3, -12.0)
	if not drawing:
		return
	var was := draw_t
	draw_t = min(draw_t + delta, BOW_FULL)
	if was < BOW_FULL and draw_t >= BOW_FULL:
		Sfx.play("click", 0.0, -4.0)
	stamina_delay = 0.4
	if not Input.is_action_pressed("attack"):
		release_arrow()


func bow_charge() -> float:
	return clampf(draw_t / BOW_FULL, 0.0, 1.0) if drawing else 0.0


func release_arrow() -> void:
	var charge := bow_charge()
	drawing = false
	draw_t = 0.0
	Game.stamina = max(0.0, Game.stamina - 5.0)
	var origin := weapon_tip()
	var dir := aim_dir(origin)
	var full := charge >= 0.99
	var fx := _weapon_fx()
	var crit: bool = randf() < Game.crit_chance() + (0.1 if full else 0.0)
	var dmg := Game.melee_damage() * lerpf(0.45, 1.5, charge) * (1.8 if crit else 1.0)
	var pierce := 2 if full else 0
	if fx == "pierce":
		pierce += 2
	var dirs := [dir]
	if full and fx == "multishot":
		dirs = [dir.rotated(Vector3.UP, -0.1), dir, dir.rotated(Vector3.UP, 0.1)]
	for d in dirs:
		_spawn_projectile("arrow", origin, d, dmg, crit, pierce, lerpf(22.0, 42.0, charge))
		Network.send_event("arrow", origin, d)
	attacking = true
	combo = 1
	attack_timer = 0.0
	hit_done = true
	Sfx.play("swing", 0.1, -2.0 if full else -6.0)
	if full:
		add_shake(0.06)


func _cancel_draw() -> void:
	drawing = false
	draw_t = 0.0


func _spawn_projectile(kind: String, origin: Vector3, d: Vector3, dmg: float, crit: bool, pierce: int, spd := 30.0) -> void:
	var p := PROJECTILE.new()
	p.kind = kind
	p.direction = d
	p.damage = dmg
	p.crit = crit
	p.pierce = pierce
	p.fx = _weapon_fx() if _weapon_fx() != "multishot" else ""
	p.color = _weapon_color()
	p.speed = spd if kind == "arrow" else 26.0
	p.life = 1.8 if kind == "arrow" else 1.2
	get_tree().current_scene.add_child(p)
	p.global_position = origin


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
	_cancel_draw()
	Game.mp -= sp.cost
	cooldowns[id] = sp.cooldown * Game.cooldown_mult()
	cast_timer = 0.4
	_start_cast_pose(id)
	match id:
		"fireball":
			# sai da gema do cajado (ou da mão) depois do movimento de apontar
			_pending_spell = id
			_pending_t = KnightMoves.CAST_RELEASE * KnightMoves.CAST_TIME
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
	var origin := spell_origin()
	var fb := FIREBALL.new()
	fb.direction = aim_dir(origin)
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
	Sfx.play_at("frost", global_position, 0.0)


func _heal_fx() -> void:
	FX.burst(global_position + Vector3.UP, Color(0.4, 1.0, 0.5), 30, 3.0, 0.1, 1.0, 2.0)
	Sfx.play_at("heal", global_position, 0.0)


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
	_cancel_draw()
	Sfx.play("death", 0.0)
	var tw := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
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
var _last_look := {}


func _update_equipment_visual() -> void:
	var l: Dictionary = Game.equipment.duplicate()
	if l == _last_look:
		return
	apply_look(l)
	Network.send_look(l)


func apply_look(l: Dictionary) -> void:
	_last_look = l.duplicate()
	var old_class: String = look["class"]
	look = KnightLook.apply(model, l)
	if old_class != look["class"]:
		attacking = false
		combo = 0
		_cancel_draw()
		parts.Body.rotation.y = 0.0


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
const NF_DRAW := 32


func _net_send(delta: float) -> void:
	_net_send_t -= delta
	if _net_send_t > 0.001:
		return
	_net_send_t = maxf(_net_send_t + 1.0 / Network.SEND_RATE, 0.0)
	var flags := (NF_FLOOR if is_on_floor() else 0) | (NF_ATTACK if attacking else 0) \
		| (NF_DODGE if dodge_timer > 0 else 0) | (NF_CAST if cast_timer > 0 else 0) | (NF_DEAD if dead else 0) | (NF_DRAW if drawing else 0)
	Network.send_player_state(global_position, model.rotation.y, velocity, flags, combo, attack_timer)


func apply_net_state(pos: Vector3, yaw: float, vel: Vector3, flags: int, c: int, attack_t: float) -> void:
	_net_pos = pos
	_net_yaw = yaw
	velocity = vel
	_net_vel = vel
	_net_age = 0.0
	_net_floor = flags & NF_FLOOR != 0
	dodge_timer = 0.12 if flags & NF_DODGE else 0.0
	cast_timer = 0.15 if flags & NF_CAST else 0.0
	if flags & NF_DRAW:
		if not drawing:
			draw_t = 0.0
		drawing = true
	else:
		drawing = false
	if flags & NF_ATTACK:
		if not attacking or c != combo:
			Sfx.play_at("swing", global_position, 0.12, -6.0)
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
		var tw := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		tw.tween_property(parts.Body, "rotation:x", -1.4, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(parts.Body, "position:y", 0.35, 0.6)
	elif dead and not now_dead:
		dead = false
		parts.Body.rotation = Vector3.ZERO
		parts.Body.position.y = parts.body_y


func set_display_name(n: String) -> void:
	display_name = n
	if name_tag:
		name_tag.text = n


func _remote_process(delta: float) -> void:
	# entre pacotes (20/s) segue andando na última velocidade conhecida, em vez de parar e dar tranco
	_net_age += delta
	var target := _net_pos + Vector3(_net_vel.x, 0, _net_vel.z) * minf(_net_age, 0.2)
	if global_position.distance_to(target) > 8.0:
		global_position = target
	else:
		global_position = global_position.lerp(target, 1.0 - exp(-12.0 * delta))
	model.rotation.y = lerp_angle(model.rotation.y, _net_yaw, 1.0 - exp(-15.0 * delta))
	if dead:
		return
	dodge_timer = max(0.0, dodge_timer - delta)
	cast_timer = max(0.0, cast_timer - delta)
	if attacking:
		attack_timer = minf(attack_timer + delta, _swing_time(combo))
	if drawing:
		draw_t = min(draw_t + delta, BOW_FULL)
	_animate(delta)


## Começa a pose de conjuração (jogador local e réplicas, pelo evento da magia).
func _start_cast_pose(kind: String) -> void:
	_cast_kind = kind
	_cast_t = 0.0


## Efeitos das ações de outro jogador (só visuais: o dano já foi enviado pelo dono).
func play_remote_event(kind: String, a: Vector3, b: Vector3) -> void:
	match kind:
		"fireball":
			_start_cast_pose(kind)
			_cast_t = KnightMoves.CAST_RELEASE * KnightMoves.CAST_TIME   # o evento chega no disparo
			var fb := FIREBALL.new()
			fb.direction = b
			fb.visual_only = true
			get_tree().current_scene.add_child(fb)
			fb.global_position = a
			Sfx.play_at("fire", a, 0.08, -4.0)
		"frost_nova":
			_start_cast_pose(kind)
			_frost_fx(6.5)
		"heal":
			_start_cast_pose(kind)
			_heal_fx()
		"bolt", "arrow":
			var p := PROJECTILE.new()
			p.kind = kind
			p.direction = b
			p.visual_only = true
			p.color = ItemDB.get_item(_last_look.get("weapon", "")).get("color", Color(0.6, 0.8, 1.0))
			p.speed = 34.0 if kind == "arrow" else 26.0
			p.life = 1.6 if kind == "arrow" else 1.2
			get_tree().current_scene.add_child(p)
			p.global_position = a
		"zap":
			AUTO_WEAPONS.bolt_fx(get_tree().current_scene, a)
			Sfx.play_at("zap", a, 0.15, -8.0)
		"combo":
			AUTO_WEAPONS.combo_fx_index(get_tree().current_scene, int(b.x), a)
		"horde_gear":
			# armas automáticas do Desafio da Horda girando em volta do outro jogador
			var aw: Node = get_node_or_null("HordeGear")
			if a == Vector3.ZERO and b == Vector3.ZERO:
				if aw:
					aw.queue_free()
				return
			if aw == null:
				aw = AUTO_WEAPONS.new()
				aw.name = "HordeGear"
				aw.visual_only = true
				add_child(aw)
			aw.apply_gear(a, b)


func _update_camera(delta: float) -> void:
	shake = max(0.0, shake - delta * 1.2)
	camera.h_offset = randf_range(-1, 1) * shake * 0.4
	camera.v_offset = randf_range(-1, 1) * shake * 0.4


func _animate(delta: float) -> void:
	var hvel := Vector3(velocity.x, 0, velocity.z)
	var hspeed := hvel.length()
	var on_floor := _net_floor if remote else is_on_floor()
	idle_t += delta
	var k := 1.0 - exp(-14.0 * delta)

	# quanto anda (0..1) e quanto corre (0..1), suavizados: as transições parado/andar/correr misturam
	# as poses em vez de trocar de uma vez (parar é um pouco mais lento que arrancar)
	var move_t := clampf(hspeed / WALK_SPEED, 0.0, 1.0) if on_floor else 0.0
	var run_t := clampf((hspeed - WALK_SPEED) / (SPRINT_SPEED - WALK_SPEED), 0.0, 1.0)
	_amp = lerpf(_amp, move_t, 1.0 - exp(-(10.0 if move_t > _amp else 6.0) * delta))
	_run = lerpf(_run, run_t, 1.0 - exp(-6.0 * delta))
	_air = lerpf(_air, 0.0 if on_floor else 1.0, 1.0 - exp(-12.0 * delta))
	# a fase avança pela distância percorrida: meia volta = uma passada, então o pé não desliza
	anim_t += delta * KnightAnim.cadence(parts, hspeed, _amp, _run)

	# inclinação para a frente com a velocidade e a aceleração; para o lado nas curvas
	var fwd := Vector3(sin(model.rotation.y), 0, cos(model.rotation.y))
	var accel := (hvel - _prev_hvel) / maxf(delta, 0.001)
	_prev_hvel = hvel
	if remote:
		accel = Vector3.ZERO   # a velocidade da réplica muda aos saltos (pacotes): só a local dá aceleração confiável
	var lean_t := 0.0
	if on_floor:
		lean_t = clampf(lerpf(KnightAnim.LEAN_WALK, KnightAnim.LEAN_RUN, _run) * clampf(hspeed / WALK_SPEED, 0.0, 1.0)
			+ accel.dot(fwd) * KnightAnim.LEAN_ACCEL, KnightAnim.LEAN_MIN, KnightAnim.LEAN_MAX)
	_lean = lerpf(_lean, lean_t, 1.0 - exp(-8.0 * delta))
	var yaw_rate := wrapf(model.rotation.y - _prev_yaw, -PI, PI) / maxf(delta, 0.001)
	_prev_yaw = model.rotation.y
	var bank_t := clampf(-yaw_rate * hspeed * 0.012, -0.18, 0.18) if on_floor and dodge_timer <= 0 else 0.0
	_bank = lerpf(_bank, bank_t, 1.0 - exp(-8.0 * delta))
	model.rotation.z = _bank

	# aterrissagem: agacha conforme a velocidade da queda, depois volta
	if not on_floor:
		_air_vy = velocity.y
	elif not _was_floor and _air_vy < -3.0:
		_land = clampf(-_air_vy / 14.0, 0.3, 1.0)
	_was_floor = on_floor
	_land = move_toward(_land, 0.0, delta * 3.5)
	var land := _land * _land * (3.0 - 2.0 * _land)

	# pose: parado -> andar/correr -> ar, misturados pelos pesos suavizados
	var p := KnightAnim.blend(KnightAnim.idle_pose(idle_t), KnightAnim.locomotion_pose(parts, anim_t, _amp, _run), _amp)
	if _air > 0.001:
		p = KnightAnim.blend(p, KnightAnim.air_pose(clampf(velocity.y / JUMP_VELOCITY, -1.0, 1.0)), _air)
	KnightAnim.add_landing(p, land)
	p.body_x += _lean * (1.0 - _air)
	# a cabeça compensa parte da inclinação e continua olhando para a frente
	p.head_x -= (_lean + land * KnightAnim.LAND_BODY_X) * 0.5
	if dodge_timer > 0:
		p.body_x = 0.7
		p.body_y = -0.25
		p.leg_l = -0.9
		p.leg_r = 0.6
		p.knee_l = 1.1
		p.knee_r = 0.9
		p.head_x = 0.0
		p.ground = 0.0

	# golpes, arco e magias: trilhas de KnightMoves por cima da locomoção
	var cls: String = look["class"]
	_cast_t += delta
	var arrow: Node3D = look.get("arrow")
	if arrow and is_instance_valid(arrow):
		arrow.visible = drawing
	if cls == "bow" and drawing:
		KnightAnim.bow_draw_pose(p, bow_charge())
	elif cls == "bow" and attacking:
		KnightAnim.bow_release_pose(p, attack_timer / BOW_RECOVER, _amp)
	elif attacking and cls == "staff":
		KnightAnim.staff_pose(p, combo, attack_timer / _swing_time(combo), _amp)
	elif attacking and cls == "sword":
		KnightAnim.sword_pose(p, combo, attack_timer / SWING_TIMES[clampi(combo, 1, 3) - 1], _amp)
	elif _cast_t < KnightMoves.CAST_TIME:
		KnightAnim.cast_pose(p, _cast_kind, _cast_t / KnightMoves.CAST_TIME, _amp, cls == "staff")
	KnightAnim.apply(parts, p, k)

	KnightAnim.hold_weapon_upright(look, parts)

	if on_floor and hspeed > 1.0:
		_footstep -= delta * hspeed
		if _footstep <= 0:
			_footstep = 2.2
