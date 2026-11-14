class_name Enemy
extends CharacterBody3D
## Inimigo genérico (slime, goblin, rei goblin) com IA simples de estados.

signal died(enemy: Enemy)
signal health_changed(enemy: Enemy)

const PICKUP := preload("res://scripts/world/pickup.gd")
const ENEMY_ARROW := preload("res://scripts/enemies/enemy_arrow.gd")
const PROVOKE_TIME := 4.0   # ver `provoked`
const MODELS := {
	"slime": preload("res://assets/models/slime.glb"),
	"goblin": preload("res://assets/models/goblin.glb"),
}
## Tipos de inimigo: vêm de data/balance/enemies.json (autoload Balance). "ai" muda o comportamento,
## "tint" recolore o modelo do goblin, "bld" multiplica o dano em construções.
static var TYPES: Dictionary = {}

@export var kind := "slime"
## Desafio da Horda: persegue sempre o jogador, não volta para casa e não dá XP/loot do RPG.
var horde := false
var hp_mult := 1.0
var dmg_mult := 1.0
var speed_mult := 1.0
## Desafio da Horda: versão de elite (maior, dourada, mais vida e dano; o servidor manda junto no spawn).
var elite := false
## Defesa da Cidade em grupo: elite (chave de ColonyData.AFFIXES) com resistências por tipo de dano.
var affix := ""
## Multiplayer (servidor): "world" (Valdoria) ou "city" (Defesa da Cidade em grupo).
var net_zone := "world"
## Goblin Dourado que fugiu: some sem contar como abate.
var escaped := false
var born_t := 0.0
## Defesa da Cidade: marcha até a prefeitura e ataca construções, soldados e o jogador no caminho.
var siege := false
## Defesa da Cidade: guarda de covil (ColonyDen.id). Atraído para além de DEN_LEASH do centro, volta ao covil.
var den_id := -1
var den_center := Vector3.ZERO
var _siege_target = null     # Player, ColonySoldier ou ColonyBuilding
var _retarget := 0.0
var _lock_t := 0.0

var data: Dictionary
var display_name := ""
var max_hp := 1.0
var hp := 1.0
var radius := 0.5
var dead := false
var is_boss := false
var state := "idle"
var state_timer := 0.0
var attack_cd := 0.0
var attack_timer := 0.0
var attack_kind := "swing"
var attack_count := 0
var hit_done := false
var slow_timer := 0.0
var stagger := 0.0
## Segundos em que o inimigo segue perseguindo depois de levar dano, mesmo com o jogador longe.
## Sem isso, um acerto de longe (ou, no servidor, antes de chegar a posição nova do jogador)
## fazia o inimigo desistir na hora, voltar para casa e curar a vida toda, apagando o dano.
var provoked := 0.0
var home := Vector3.ZERO
var wander_target := Vector3.ZERO
var enraged := false
var summoned := false
var model: Node3D
var parts := {}
var meshes: Array[MeshInstance3D] = []
var anim_t := 0.0
var bar_root: Node3D
var bar_fg: MeshInstance3D
var _overlay_hit: StandardMaterial3D
var _overlay_slow: StandardMaterial3D
var _overlay_base: Material = null
var _flash_t := 0.0

## Multiplayer: id comum entre servidor e clientes.
var net_id := 0
## Cliente: réplica de um inimigo do servidor (sem IA; segue os snapshots).
var puppet := false
## Servidor: peers que acertaram este inimigo (todos ganham XP e loot ao matar).
var contributors := {}
var last_hitter := 0
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0


func _ready() -> void:
	data = TYPES[kind]
	display_name = data.name
	if elite:
		display_name += " de Elite"
	max_hp = data.hp * hp_mult
	hp = max_hp
	radius = data.radius * (1.2 if elite else 1.0)
	is_boss = data.get("boss", false)
	add_to_group("enemies")
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = max(data.height, radius * 2.0)
	col.shape = cap
	col.position.y = cap.height / 2.0
	add_child(col)

	model = MODELS[data.model].instantiate()
	model.scale = Vector3.ONE * data.scale * (1.3 if elite else 1.0)
	add_child(model)
	if elite:
		_make_elite_glow()
	for n in ["LegL", "LegR", "ArmL", "ArmR", "Body", "Head"]:
		parts[n] = model.find_child(n, true, false)
	var crown := model.find_child("Crown", true, false)
	if crown:
		crown.visible = is_boss
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		meshes.append(mi)
	if data.model == "slime":
		var body_mesh := model.find_child("BodyMesh", true, false) as MeshInstance3D
		var base := model.find_child("Base", true, false) as MeshInstance3D
		var goo := StandardMaterial3D.new()
		goo.albedo_color = data.get("goo", Color(0.25, 0.85, 0.3, 0.78))
		goo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		goo.roughness = 0.1
		goo.rim_enabled = true
		goo.rim = 0.6
		for m in [body_mesh, base]:
			if m:
				m.material_override = goo
	if data.has("tint"):
		_apply_tint(data.tint[0], data.tint[1])
	if is_boss or data.get("elite", false):
		var aura := OmniLight3D.new()
		aura.light_color = Color(1, 0.3, 0.1) if is_boss else data.color
		aura.light_energy = 1.5 if is_boss else 1.1
		aura.omni_range = 6.0 if is_boss else 4.0
		aura.position.y = 2.0 if is_boss else 1.4
		add_child(aura)
	if data.get("ai", "") == "bomber":
		var glow := OmniLight3D.new()
		glow.light_color = data.color
		glow.light_energy = 0.8
		glow.omni_range = 2.5
		glow.position.y = 0.6
		add_child(glow)

	_overlay_hit = StandardMaterial3D.new()
	_overlay_hit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay_hit.albedo_color = Color(1, 1, 1, 0.7)
	_overlay_hit.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay_slow = StandardMaterial3D.new()
	_overlay_slow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay_slow.albedo_color = Color(0.4, 0.75, 1.0, 0.35)
	_overlay_slow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	if not is_boss:
		_make_health_bar()
		if data.get("elite", false):
			bar_root.visible = true
	home = global_position
	wander_target = home
	state_timer = randf_range(1.0, 3.0)
	model.rotation.y = randf() * TAU
	if horde or siege:
		state = "chase"
	if siege:
		collision_mask |= 64   # soldados seguram a passagem
		_retarget = randf() * 0.3
	if affix != "":
		set_affix(affix)
	if Network.is_server():
		Network.server_register_enemy(self)


## Elite: anel dourado no chão e brilho, para ser lido de longe no meio da horda.
func _make_elite_glow() -> void:
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = radius + 0.25
	tor.outer_radius = radius + 0.45
	tor.rings = 24
	tor.ring_segments = 6
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.8, 0.25, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(1.0, 0.7, 0.2)
	m.emission_energy_multiplier = 2.5
	tor.material = m
	ring.mesh = tor
	ring.scale = Vector3(1, 0.15, 1)
	ring.position.y = 0.08
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.3)
	light.light_energy = 1.2
	light.omni_range = 3.5
	light.position.y = 1.0
	add_child(light)


func _exit_tree() -> void:
	if net_id != 0:
		Network.unregister_enemy(self)


## Recolore o modelo (variantes do goblin): cada material é copiado e puxado para a cor.
func _apply_tint(c: Color, amount: float) -> void:
	for mi in meshes:
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i) as StandardMaterial3D
			if mat == null:
				continue
			var m2 := mat.duplicate() as StandardMaterial3D
			m2.albedo_color = mat.albedo_color.lerp(c, amount)
			if kind == "goblin_dourado":
				m2.metallic = 0.7
				m2.roughness = 0.3
			mi.set_surface_override_material(i, m2)


func ai() -> String:
	return data.get("ai", "melee")


## A horda fica parada enquanto o grupo escolhe as cartas de nível (survival_mode.frozen).
## No servidor/solo o pai é o modo sobrevivência; na réplica do cliente, o mundo.
func _horde_frozen() -> bool:
	if not horde or get_parent() == null:
		return false
	if get_parent().get("frozen") == true:
		return true
	var sv = get_parent().get("survival")
	return sv != null and is_instance_valid(sv) and sv.get("frozen") == true


func _make_health_bar() -> void:
	bar_root = Node3D.new()
	bar_root.position.y = data.height * data.scale + 0.45
	add_child(bar_root)
	var bg := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 0.12)
	bg.mesh = q
	bg.material_override = _bar_mat(Color(0, 0, 0, 0.7), 0)
	bar_root.add_child(bg)
	bar_fg = MeshInstance3D.new()
	var q2 := QuadMesh.new()
	q2.size = Vector2(0.96, 0.08)
	bar_fg.mesh = q2
	bar_fg.material_override = _bar_mat(Color(0.85, 0.15, 0.1), 1)
	bar_root.add_child(bar_fg)
	bar_root.visible = false


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


func _physics_process(delta: float) -> void:
	if puppet:
		_puppet_process(delta)
		return
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	if dead:
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return
	if _horde_frozen():
		velocity = Vector3.ZERO
		return
	born_t += delta
	attack_cd = max(0.0, attack_cd - delta)
	slow_timer = max(0.0, slow_timer - delta)
	stagger = max(0.0, stagger - delta)
	provoked = maxf(0.0, provoked - delta)
	_update_flash(delta)
	if siege:
		_siege_process(delta)
		return

	var player := _nearest_player()
	var to_player := Vector3.ZERO
	var dist := INF
	if player and not player.dead:
		to_player = player.global_position - global_position
		to_player.y = 0
		dist = to_player.length()

	var spd: float = data.speed * speed_mult * (0.45 if slow_timer > 0 else 1.0) * (1.3 if enraged else 1.0)
	var move := Vector3.ZERO
	var face := Vector3.ZERO

	match state:
		"idle":
			state_timer -= delta
			if dist < data.aggro or (horde and dist < INF):
				_set_state("chase")
			elif state_timer <= 0:
				wander_target = home + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
				_set_state("wander")
		"wander":
			var to := wander_target - global_position
			to.y = 0
			if dist < data.aggro:
				_set_state("chase")
			elif to.length() < 0.6 or state_timer > 6.0:
				state_timer = randf_range(2.0, 4.5)
				state = "idle"
			else:
				move = to.normalized() * spd * 0.4
				state_timer += delta
		"chase":
			if horde and ai() != "melee" and ai() != "bomber":
				if dist == INF:
					_set_state("idle")
				else:
					var r := _ranged_move(to_player, dist, spd)
					move = r[0]
					face = r[1]
			elif horde:
				if dist == INF:
					_set_state("idle")
				elif dist <= data.reach and attack_cd <= 0:
					_begin_attack()
				elif dist > data.reach * 0.8:
					move = to_player.normalized() * spd
			elif global_position.distance_to(home) > 45.0 or _off_leash(global_position) \
					or (dist > data.aggro * 1.9 and provoked <= 0.0):
				_set_state("return")
			elif dist <= data.reach and attack_cd <= 0:
				_begin_attack()
			elif dist > data.reach * 0.8:
				move = to_player.normalized() * spd
			if face == Vector3.ZERO:
				face = to_player
		"return":
			var to := home - global_position
			to.y = 0
			if dist < data.aggro * 0.7 and not _off_leash(player.global_position):
				_set_state("chase")
			elif to.length() < 1.0:
				hp = max_hp
				health_changed.emit(self)
				_set_state("idle")
			else:
				move = to.normalized() * spd
		"attack":
			_update_attack(delta, player, to_player, dist)
			if attack_kind == "lunge" and attack_timer > 0.35 and attack_timer < 0.6:
				move = model_forward() * spd * 3.2
			elif dist < INF and (attack_timer < 0.35 or (attack_kind == "shoot" and attack_timer < _hit_time())):
				face = to_player

	if stagger > 0:
		move = Vector3.ZERO
	if face == Vector3.ZERO and move.length() > 0.1:
		face = move
	if face.length() > 0.01:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(face.x, face.z), 8.0 * delta)

	var accel := 30.0
	velocity.x = move_toward(velocity.x, move.x, accel * delta)
	velocity.z = move_toward(velocity.z, move.z, accel * delta)
	move_and_slide()
	_animate(delta, Vector2(velocity.x, velocity.z).length())
	if bar_root and bar_root.visible:
		bar_fg.scale.x = max(0.001, hp / max_hp)
		bar_fg.position.x = 0.0


## Guarda de covil: o ponto p está longe demais do centro do covil?
func _off_leash(p: Vector3) -> bool:
	return den_id >= 0 and Vector2(p.x - den_center.x, p.z - den_center.z).length() > ColonyData.DEN_LEASH


## Jogador vivo mais próximo (no multiplayer, o servidor tem réplicas de todos).
## A horda só persegue quem está no desafio (get_parent() é o modo sobrevivência).
func _nearest_player() -> Player:
	var best: Player = null
	var best_d := INF
	var pool: Array = get_parent().targets() if horde and get_parent().has_method("targets") 		else get_tree().get_nodes_in_group("players")
	var w := get_world_3d()
	for p in pool:
		if p.dead or p.get_world_3d() != w:   # o servidor roda Valdoria e a cidade em mundos separados
			continue
		var d := global_position.distance_squared_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


func model_forward() -> Vector3:
	return Vector3(sin(model.rotation.y), 0, cos(model.rotation.y))


func _set_state(s: String) -> void:
	state = s
	state_timer = 0.0
	if s == "chase" and bar_root and not horde:
		bar_root.visible = true


## Arqueiro, xamã e goblin dourado: mantêm distância (ou fogem) em vez de correr para cima.
## Devolve [movimento, direção para olhar].
func _ranged_move(to_player: Vector3, dist: float, spd: float) -> Array:
	var dir := to_player.normalized() if dist > 0.01 else Vector3.FORWARD
	var side := dir.cross(Vector3.UP) * (1.0 if net_id % 2 == 0 else -1.0)
	var move := Vector3.ZERO
	if ai() == "flee":
		if dist < 16.0:
			move = (-dir + side * 0.5).normalized() * spd
		else:
			move = side * spd * 0.4
		# não sai da arena: puxa para o centro perto da borda
		var sv := get_parent()
		if sv and sv.get("center") != null:
			var to_c: Vector3 = sv.center - global_position
			to_c.y = 0
			if to_c.length() > sv.ARENA_RADIUS - 4.0:
				move = (move.normalized() + to_c.normalized() * 1.6).normalized() * spd
		return [move, move if move.length() > 0.1 else dir]
	var keep: float = data.get("keep", 7.0)
	if dist < keep * 0.7:
		move = (-dir + side * 0.4).normalized() * spd * 0.9
	elif dist > data.reach * 0.85:
		move = dir * spd
	else:
		move = side * spd * 0.35
	if dist <= data.reach and attack_cd <= 0:
		_begin_attack()
		move = Vector3.ZERO
	return [move, dir]


# ------------------------------------------------------------ ataques
func _begin_attack() -> void:
	state = "attack"
	attack_timer = 0.0
	hit_done = false
	attack_count += 1
	match ai():
		"ranged":
			attack_kind = "shoot"
			return
		"caster":
			attack_kind = "cast"
			return
		"bomber":
			attack_kind = "fuse"
			FX.telegraph(global_position, data.blast, _hit_time())
			return
	if data.model == "slime":
		attack_kind = "lunge"
		velocity.y = 4.5
	elif (is_boss and attack_count % 3 == 0) or (data.has("slam_every") and attack_count % int(data.slam_every) == 0):
		attack_kind = "slam"
		FX.telegraph(global_position, _slam_radius(), 0.9)
	else:
		attack_kind = "swing"


func _slam_radius() -> float:
	return 5.0 if is_boss else 3.6


func _attack_duration() -> float:
	match attack_kind:
		"slam":
			return 1.6
		"lunge":
			return 1.0
		"shoot":
			return 1.0
		"cast":
			return 1.3
		"fuse":
			return 1.2
	return 0.95 if not is_boss else 1.1


func _hit_time() -> float:
	match attack_kind:
		"slam":
			return 0.9
		"lunge":
			return 0.45
		"shoot":
			return 0.6
		"cast":
			return 0.75
		"fuse":
			return 0.95
	return 0.5 if not is_boss else 0.6


## player: o alvo do ataque (Player no RPG; no cerco também soldado ou construção).
func _update_attack(delta: float, player, to_player: Vector3, dist: float) -> void:
	var mult := 1.0
	if player != null and player.is_in_group("buildings"):
		mult = float(data.get("bld", 1.0))
		if affix != "":
			mult *= float(ColonyData.AFFIXES[affix].get("bld", 1.0))
	attack_timer += delta
	if not hit_done and attack_timer >= _hit_time():
		hit_done = true
		if attack_kind == "shoot":
			_shoot(false)
		elif attack_kind == "cast":
			_cast_heal(false)
		elif attack_kind == "fuse":
			_explode(false)
			return
		elif attack_kind == "slam":
			var sr := _slam_radius()
			Sfx.play_at("slam", global_position, 0.0)
			FX.ring(global_position, Color(0.8, 0.6, 0.3, 0.9), sr, 0.4)
			FX.burst(global_position + Vector3.UP * 0.3, Color(0.5, 0.4, 0.3), 40, 7.0, 0.2, 0.8)
			if player and dist <= sr:
				player.take_damage(data.damage * dmg_mult * 1.4 * mult, global_position)
			if player is Player:
				player.add_shake(0.4)
		elif player and dist <= data.reach * 1.3 + 0.3:
			var facing_ok := model_forward().dot(to_player.normalized()) > 0.2 or dist < 1.0
			if facing_ok:
				player.take_damage(data.damage * dmg_mult * randf_range(0.9, 1.1) * mult, global_position)
		if attack_kind == "swing":
			Sfx.play_at("swing", global_position, 0.15, -4.0)
	if attack_timer >= _attack_duration():
		attack_cd = data.cooldown * (0.7 if enraged else 1.0) * randf_range(0.8, 1.2)
		_set_state("chase")


## Ataques especiais dos monstros novos. visual: réplica no cliente (só efeitos; o servidor aplica o dano).
func _shoot(visual: bool) -> void:
	Sfx.play_at("swing", global_position, 0.2, -5.0)
	var origin: Vector3 = global_position + Vector3.UP * 1.1 * float(data.scale) + model_forward() * 0.6
	var arrow := ENEMY_ARROW.new()
	arrow.direction = model_forward()
	arrow.damage = 0.0 if visual else data.damage * dmg_mult
	arrow.source = get_parent()
	get_parent().add_child(arrow)
	arrow.global_position = origin


func _cast_heal(visual: bool) -> void:
	var r: float = data.heal_radius
	FX.ring(global_position, Color(0.5, 1.0, 0.4, 0.9), r, 0.6)
	FX.burst(global_position + Vector3.UP * 1.6, Color(0.6, 1.0, 0.4), 24, 3.0, 0.1, 0.8, 2.0)
	Sfx.play_at("heal", global_position, 0.1, -6.0)
	if visual:
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or e.dead or not e.horde or e.is_boss:
			continue
		if e.global_position.distance_to(global_position) <= r and e.hp < e.max_hp:
			e.hp = minf(e.max_hp, e.hp + e.max_hp * 0.25)
			e.health_changed.emit(e)
			FX.burst(e.global_position + Vector3.UP * 1.0, Color(0.5, 1.0, 0.4), 6, 2.0, 0.08, 0.5, 2.0)


func _explode(visual: bool) -> void:
	var r: float = data.blast
	Sfx.play_at("explode", global_position, 0.1, -2.0)
	FX.ring(global_position, Color(1.0, 0.6, 0.15, 0.95), r, 0.35)
	FX.burst(global_position + Vector3.UP * 0.5, Color(1.0, 0.5, 0.1), 50, 7.0, 0.16, 0.7)
	FX.burst(global_position + Vector3.UP * 0.5, Color(0.25, 0.2, 0.18), 20, 3.0, 0.25, 1.0, 1.0)
	if visual:
		return
	var pool: Array = get_parent().targets() if get_parent().has_method("targets") else get_tree().get_nodes_in_group("players")
	for p in pool:
		if not p.dead and p.global_position.distance_to(global_position) <= r:
			p.take_damage(data.damage * dmg_mult, global_position)
			p.add_shake(0.35)
	_die()


# ------------------------------------------------------------ dano
func take_damage(amount: float, from_pos: Vector3, crit: bool, slow := 0.0, stun := 0.0, pull := 0.0) -> void:
	if dead:
		return
	if puppet:
		# o servidor decide; os números de dano chegam de volta em show_hit()
		Network.client_hit_enemy(net_id, amount, from_pos, crit, slow, stun, pull)
		return
	if last_hitter != 0:
		contributors[last_hitter] = true
	if slow > 0.0:
		apply_slow(slow)
	if horde and get_parent().has_method("on_enemy_damaged"):
		# placar do Desafio da Horda (last_hitter = quem acertou no multiplayer; 0 no solo)
		get_parent().on_enemy_damaged(last_hitter, minf(amount, maxf(hp, 0.0)))
	hp -= amount
	health_changed.emit(self)
	var top: Vector3 = global_position + Vector3.UP * (data.height * data.scale + 0.2)
	FX.damage_number(top, ("%d!" if crit else "%d") % int(round(amount)),
		Color(1, 0.85, 0.2) if crit else Color.WHITE, 64 if crit else 48)
	FX.burst(global_position + Vector3.UP * data.height * data.scale * 0.5, data.color, 5 if horde else 10, 3.5, 0.1, 0.5)
	_flash_t = 0.1
	provoked = PROVOKE_TIME
	if state in ["idle", "wander", "return"]:
		_set_state("chase")
	if bar_root:
		bar_root.visible = true
	if not is_boss:
		var heavy: bool = data.get("elite", false) or elite   # campeões e elites da horda quase não recuam
		var kb := global_position - from_pos
		kb.y = 0
		if kb.length() > 0.01:
			# `pull` > 0: em vez de empurrar, puxa (m/s) em direção a quem bateu (Turbilhão)
			kb = kb.normalized() * ((-pull) if pull > 0.0 else (6.0 if data.model == "slime" else 4.0)) * (0.3 if heavy else 1.0)
			velocity.x = kb.x
			velocity.z = kb.z
		if (state != "attack" and not heavy) or (crit and attack_kind != "fuse"):
			stagger = 0.3
			if state == "attack":
				_set_state("chase")
	if is_boss and not enraged and hp < max_hp * 0.5:
		enraged = true
		Game.notify.emit("O Rei Goblin está enfurecido!", Color(1, 0.4, 0.3))
		if not summoned:
			summoned = true
			get_parent().call_deferred("summon_minions", global_position, 2)
	if hp <= 0:
		_die()
	elif stun > 0.0:
		apply_stun(stun)


## Atordoamento: para de andar por t segundos e perde o golpe em andamento (chefes são imunes).
func apply_stun(t: float) -> void:
	if puppet:
		Network.client_hit_enemy(net_id, 0.0, global_position, false, 0.0, t)
		return
	if dead or is_boss:
		return
	stagger = max(stagger, t)
	attack_cd = max(attack_cd, t)   # sem golpe novo durante o atordoamento (o stagger de um golpe comum fica como está)
	if state == "attack":
		_set_state("chase")


func apply_slow(t: float) -> void:
	if puppet:
		Network.client_hit_enemy(net_id, 0.0, global_position, false, t)
		return
	if affix != "" and ColonyData.AFFIXES[affix].get("no_slow", false):
		return
	slow_timer = max(slow_timer, t)


## Fração do dano que passa para este tipo ("arrow", "ball", "bolt", "melee"). Elites resistem a alguns.
func resist_mult(dmg_kind: String) -> float:
	if affix == "":
		return 1.0
	return 1.0 - float(ColonyData.AFFIXES[affix].resist.get(dmg_kind, 0.0))


## Visual do elite (cor, tamanho e nome). Chamado no _ready e nas réplicas quando o servidor avisa.
func set_affix(a: String) -> void:
	if not ColonyData.AFFIXES.has(a) or model == null:
		return
	affix = a
	var d: Dictionary = ColonyData.AFFIXES[a]
	display_name = "%s %s" % [data.name, d.name]
	model.scale = Vector3.ONE * data.scale * float(d.get("scale", 1.12))
	if bar_root:
		bar_root.position.y = data.height * data.scale * float(d.get("scale", 1.12)) + 0.45
	var glow := OmniLight3D.new()
	glow.light_color = d.color
	glow.light_energy = 1.2
	glow.omni_range = 3.0
	glow.position.y = data.height * 0.6
	add_child(glow)
	var tag := Label3D.new()
	tag.text = d.name
	tag.font_size = 34
	tag.outline_size = 8
	tag.pixel_size = 0.006
	tag.modulate = d.color
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.position.y = data.height * data.scale * float(d.get("scale", 1.12)) + 0.75
	add_child(tag)
	var tint := StandardMaterial3D.new()
	tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tint.albedo_color = Color(d.color.r, d.color.g, d.color.b, 0.28)
	tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay_base = tint
	for m in meshes:
		m.material_overlay = tint


func _update_flash(delta: float) -> void:
	_flash_t = max(0.0, _flash_t - delta)
	var over: Material = _overlay_base
	if _flash_t > 0:
		over = _overlay_hit
	elif slow_timer > 0:
		over = _overlay_slow
	for m in meshes:
		if m.material_overlay != over:
			m.material_overlay = over


func _die() -> void:
	if Network.is_server():
		# XP, missões e loot de cada jogador que acertou: o servidor concede (CharacterService + pickups)
		Network.server_enemy_killed(self)
	elif siege or (get_parent() != null and get_parent().has_method("add_siege_xp")):
		# cidade solo (cerco e monstros errantes): o ouro do saque vai para o caixa da cidade e o XP do abate
		# fica na partida, concedido ao personagem no amanhecer junto com a recompensa da noite (sem abate,
		# missão nem chefe no personagem: o Rei Goblin da cidade não é o de Valdoria). Sem itens no chão,
		# como em grupo.
		Game.kill_lifesteal()
		var loot := LootRules.roll(Balance.tables, kind, _loot_rng())
		var c := get_parent()
		if c != null and c.has_method("add_siege_xp"):
			c.add_siege_xp(int(data.xp * 0.6))
			if int(loot.gold) > 0:
				c.earn(int(loot.gold))
	elif not horde:
		# solo: XP, missão e o chefe derrotado (king_dead) ficam com as regras (Econ.kill)
		Game.on_enemy_killed(kind, data.xp)
		drop_loot(get_parent(), kind, global_position)
	die_visual()


## Morte sem regras de jogo (também usada pelas réplicas no cliente).
func die_visual() -> void:
	dead = true
	state = "dead"
	remove_from_group("enemies")
	collision_layer = 0
	collision_mask = 1
	for m in meshes:
		m.material_overlay = null
	if bar_root:
		bar_root.visible = false
	Sfx.play_at("bloop" if data.model == "slime" else "hit", global_position, 0.1, -4.0 if horde else 0.0)
	FX.burst(global_position + Vector3.UP * 0.6 * data.scale, data.color, 30 if not is_boss else 120, 5.0, 0.14, 0.9)
	died.emit(self)
	var tw := create_tween()
	if data.model == "slime":
		tw.tween_property(model, "scale", Vector3(1.6, 0.05, 1.6) * data.scale, 0.35).set_ease(Tween.EASE_IN)
	else:
		tw.tween_property(model, "rotation:x", -PI / 2, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.8)
		tw.tween_property(model, "position:y", -1.5 * data.scale, 1.0)
	tw.tween_callback(queue_free)


## Solo: sorteio do loot (LootRules, o mesmo do servidor) em pickups no chão.
static func drop_loot(parent: Node, enemy_kind: String, pos: Vector3, with_gold := true) -> void:
	var loot := LootRules.roll(Balance.tables, enemy_kind, _loot_rng())
	_spawn_loot(parent, pos, int(loot.gold) if with_gold else 0, loot.items)


static func _spawn_loot(parent: Node, pos: Vector3, gold: int, items: Dictionary) -> void:
	if gold > 0:
		PICKUP.spawn(parent, "", gold, pos + Vector3.UP * 0.8)
	for id in items:
		for i in int(items[id]):
			PICKUP.spawn(parent, id, 1, pos + Vector3.UP * 0.8)


static var _rng: RandomNumberGenerator = null


static func _loot_rng() -> RandomNumberGenerator:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	return _rng


# ------------------------------------------------------------ cerco (Defesa da Cidade)
func _siege_process(delta: float) -> void:
	_retarget -= delta
	_lock_t = maxf(0.0, _lock_t - delta)
	if not _target_alive(_siege_target):
		_siege_target = null
	if (_retarget <= 0.0 and state != "attack" and _lock_t <= 0.0) or (_siege_target == null and state != "attack"):
		_retarget = 0.4
		_siege_target = _pick_siege_target()
	var t = _siege_target
	var to := Vector3.ZERO
	var dist := INF
	if t != null:
		var aim: Vector3 = t.closest_point(global_position) if t.has_method("closest_point") else t.global_position
		to = aim - global_position
		to.y = 0.0
		dist = to.length()
		if not t.has_method("closest_point"):
			dist -= float(t.radius) if t.get("radius") != null else 0.35
	var spd: float = data.speed * speed_mult * (0.45 if slow_timer > 0 else 1.0) * (1.3 if enraged else 1.0)
	var move := Vector3.ZERO
	var face := Vector3.ZERO
	if state == "attack":
		_update_attack(delta, t, to, dist)
		if attack_kind == "lunge" and attack_timer > 0.35 and attack_timer < 0.6:
			move = model_forward() * spd * 3.2
		elif dist < INF and attack_timer < 0.35:
			face = to
	else:
		state = "chase"
		if t != null:
			if dist <= data.reach and attack_cd <= 0:
				_begin_attack()
			elif dist > data.reach * 0.8:
				move = to.normalized() * spd
			face = to
	if stagger > 0:
		move = Vector3.ZERO
	if face == Vector3.ZERO and move.length() > 0.1:
		face = move
	if face.length() > 0.01:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(face.x, face.z), 8.0 * delta)
	velocity.x = move_toward(velocity.x, move.x, 30.0 * delta)
	velocity.z = move_toward(velocity.z, move.z, 30.0 * delta)
	move_and_slide()
	# esbarrou num muro/construção (ou num soldado) no caminho: derruba antes de seguir
	if state != "attack":
		for i in get_slide_collision_count():
			var c = get_slide_collision(i).get_collider()
			if c == null or c == t:
				continue
			if c.is_in_group("buildings") and not c.dead:
				_siege_target = c
				_lock_t = 2.0
				break
			if c.is_in_group("soldiers") and not c.dead and not (t is Player):
				_siege_target = c
				_lock_t = 1.0
				break
	_animate(delta, Vector2(velocity.x, velocity.z).length())
	if bar_root and bar_root.visible:
		bar_fg.scale.x = max(0.001, hp / max_hp)


func _target_alive(t) -> bool:
	return t != null and is_instance_valid(t) and t.is_inside_tree() and not t.dead


## Prioridade: jogador/soldado por perto > construção a poucos passos > prefeitura > qualquer construção.
func _pick_siege_target():
	var best = null
	var best_d := INF
	var aggro: float = data.aggro
	var w := get_world_3d()
	for u in get_tree().get_nodes_in_group("colony_units"):
		if u.dead or u.get_world_3d() != w:
			continue
		var d := global_position.distance_to(u.global_position)
		if d < aggro and d < best_d:
			best = u
			best_d = d
	if best != null:
		return best
	var goal = null
	var any = null
	var any_d := INF
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.dead or not b.targetable:
			continue
		var d: float = b.distance_to_point(global_position)
		if b.is_core:
			goal = b
		if d < 7.0 and d < best_d:
			best = b
			best_d = d
		if d < any_d:
			any = b
			any_d = d
	if best != null:
		return best
	if goal != null:
		return goal
	if any != null:
		return any
	return _nearest_player()


# ------------------------------------------------------------ réplica (cliente)
func set_net_target(pos: Vector3, yaw: float) -> void:
	_net_pos = pos
	_net_yaw = yaw


func apply_snapshot(pos: Vector3, yaw: float, new_hp: float, new_state: String, atk_t: float, atk_kind: String, flags: int) -> void:
	_net_pos = pos
	_net_yaw = yaw
	if new_hp != hp:
		if new_hp < hp - 0.5 and _flash_t <= 0.0:
			_flash_t = 0.06
		hp = new_hp
		health_changed.emit(self)
	slow_timer = 0.25 if flags & 1 else 0.0
	var now_enraged := flags & 2 != 0
	if now_enraged and not enraged and (not horde or get_tree().current_scene.get("survival") != null):
		Game.notify.emit("O Rei Goblin está enfurecido!", Color(1, 0.4, 0.3))
	enraged = now_enraged
	if new_state == "attack":
		if state != "attack":
			attack_kind = atk_kind
			attack_timer = atk_t
			hit_done = atk_t >= _hit_time()
			if attack_kind == "slam":
				FX.telegraph(global_position, _slam_radius(), 0.9)
			elif attack_kind == "fuse":
				FX.telegraph(global_position, data.blast, maxf(0.2, _hit_time() - atk_t))
		elif atk_t < attack_timer - 0.3:
			# um novo ataque começou entre dois snapshots
			attack_kind = atk_kind
			attack_timer = atk_t
			hit_done = atk_t >= _hit_time()
	if new_state != state:
		_set_state(new_state)


func show_hit(amount: float, crit: bool) -> void:
	if dead:
		return
	var top: Vector3 = global_position + Vector3.UP * (data.height * data.scale + 0.2)
	FX.damage_number(top, ("%d!" if crit else "%d") % int(round(amount)),
		Color(1, 0.85, 0.2) if crit else Color.WHITE, 64 if crit else 48)
	FX.burst(global_position + Vector3.UP * data.height * data.scale * 0.5, data.color, 10, 3.5, 0.1, 0.5)
	_flash_t = 0.1
	if bar_root:
		bar_root.visible = true


func _puppet_process(delta: float) -> void:
	if dead:
		return
	_update_flash(delta)
	if _horde_frozen():
		return
	var prev := global_position
	if global_position.distance_to(_net_pos) > 6.0:
		global_position = _net_pos
	else:
		global_position = global_position.lerp(_net_pos, 1.0 - exp(-12.0 * delta))
	model.rotation.y = lerp_angle(model.rotation.y, _net_yaw, 1.0 - exp(-12.0 * delta))
	if state == "attack":
		var before := attack_timer
		attack_timer += delta
		if not hit_done and before < _hit_time() and attack_timer >= _hit_time():
			hit_done = true
			if attack_kind == "slam":
				Sfx.play_at("slam", global_position, 0.0)
				FX.ring(global_position, Color(0.8, 0.6, 0.3, 0.9), _slam_radius(), 0.4)
				FX.burst(global_position + Vector3.UP * 0.3, Color(0.5, 0.4, 0.3), 40, 7.0, 0.2, 0.8)
			elif attack_kind == "shoot":
				_shoot(true)
			elif attack_kind == "cast":
				_cast_heal(true)
			elif attack_kind == "fuse":
				_explode(true)
			elif attack_kind == "swing":
				Sfx.play_at("swing", global_position, 0.15, -4.0)
	var hspeed := Vector2(global_position.x - prev.x, global_position.z - prev.z).length() / maxf(delta, 0.0001)
	_animate(delta, hspeed)
	if bar_root and bar_root.visible:
		bar_fg.scale.x = max(0.001, hp / max_hp)


# ------------------------------------------------------------ animação procedural
func _animate(delta: float, hspeed: float) -> void:
	anim_t += delta * (3.0 + hspeed * 2.0)
	var s := sin(anim_t)
	var k := 1.0 - exp(-12.0 * delta)
	if data.model == "slime":
		var body: Node3D = parts.Body
		var sq := 1.0 + s * 0.12
		var target := Vector3(1.0 / sqrt(sq), sq, 1.0 / sqrt(sq))
		if state == "attack":
			var t := attack_timer
			if t < 0.3:
				target = Vector3(1.3, 0.6, 1.3)
			elif t < 0.6:
				target = Vector3(0.8, 1.4, 0.8)
		body.scale = body.scale.lerp(target, k)
		return
	var amp: float = clamp(hspeed / 4.0, 0.0, 1.0) * 0.8
	parts.LegL.rotation.x = lerp(parts.LegL.rotation.x, s * amp, k)
	parts.LegR.rotation.x = lerp(parts.LegR.rotation.x, -s * amp, k)
	parts.ArmL.rotation.x = lerp(parts.ArmL.rotation.x, -s * amp * 0.6, k)
	var arm := Vector3(s * amp * 0.5, 0, 0)
	var body_x := 0.0
	if state == "attack":
		var ht := _hit_time()
		var t := attack_timer
		if attack_kind == "slam":
			if t < ht:
				arm = Vector3(-3.0, 0, 0)
				body_x = -0.3
				parts.ArmL.rotation.x = -3.0
			else:
				arm = Vector3(0.3, 0, 0)
				body_x = 0.4
				parts.ArmL.rotation.x = 0.3
		else:
			if t < ht:
				arm = Vector3(-2.7, 0, -0.3)
				body_x = -0.2
			elif t < ht + 0.25:
				arm = Vector3(0.6, 0, 0.2)
				body_x = 0.3
	var kk := k if not (state == "attack" and attack_timer >= _hit_time() and attack_timer < _hit_time() + 0.12) else 1.0 - exp(-40.0 * delta)
	parts.ArmR.rotation = parts.ArmR.rotation.lerp(arm, kk)
	parts.Body.rotation.x = lerp(parts.Body.rotation.x, body_x, k)
