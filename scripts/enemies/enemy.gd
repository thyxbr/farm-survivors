class_name Enemy
extends CharacterBody3D
## Inimigo genérico (slime, goblin, rei goblin) com IA simples de estados.

signal died(enemy: Enemy)
signal health_changed(enemy: Enemy)

const PICKUP := preload("res://scripts/world/pickup.gd")
const MODELS := {
	"slime": preload("res://assets/models/slime.glb"),
	"goblin": preload("res://assets/models/goblin.glb"),
}
const TYPES := {
	"slime": {"name": "Slime", "model": "slime", "hp": 40, "damage": 9, "speed": 2.8, "xp": 18,
		"gold": [1, 5], "aggro": 11.0, "reach": 1.5, "cooldown": 1.5, "radius": 0.5, "height": 0.8,
		"scale": 1.0, "color": Color(0.3, 0.9, 0.35),
		"loot": [["slime_gel", 0.6], ["health_potion", 0.08], ["mana_potion", 0.06], ["seed_tomato", 0.12],
			["leather_gloves", 0.02], ["leather_boots", 0.02], ["apprentice_staff", 0.015], ["short_bow", 0.015], ["life_amulet", 0.01]]},
	# variantes usadas no Desafio da Horda
	"slime_grande": {"name": "Slime Grande", "model": "slime", "hp": 150, "damage": 16, "speed": 2.3, "xp": 40,
		"gold": [3, 8], "aggro": 14.0, "reach": 2.2, "cooldown": 1.8, "radius": 0.85, "height": 1.3,
		"scale": 1.7, "color": Color(0.6, 0.3, 0.9), "goo": Color(0.55, 0.25, 0.85, 0.8), "bld": 1.5,
		"loot": [["slime_gel", 0.8]]},
	"slime_veloz": {"name": "Slime Veloz", "model": "slime", "hp": 24, "damage": 7, "speed": 5.2, "xp": 12,
		"gold": [1, 3], "aggro": 14.0, "reach": 1.3, "cooldown": 1.2, "radius": 0.36, "height": 0.6,
		"scale": 0.7, "color": Color(0.95, 0.3, 0.2), "goo": Color(0.95, 0.3, 0.2, 0.8),
		"loot": [["slime_gel", 0.4]]},
	"goblin": {"name": "Goblin Batedor", "model": "goblin", "hp": 80, "damage": 14, "speed": 4.2, "xp": 42,
		"gold": [4, 11], "aggro": 15.0, "reach": 1.8, "cooldown": 1.3, "radius": 0.4, "height": 1.35,
		"scale": 1.0, "color": Color(0.7, 0.1, 0.05), "bld": 1.5,
		"loot": [["goblin_ear", 0.7], ["health_potion", 0.18], ["mana_potion", 0.15], ["iron_sword", 0.05], ["leather_armor", 0.05],
			["seed_pepper", 0.15], ["seed_mint", 0.1], ["leather_cap", 0.04], ["leather_gloves", 0.04], ["leather_boots", 0.04],
			["hunter_bow", 0.03], ["oak_staff", 0.03], ["wooden_shield", 0.04], ["strength_ring", 0.02], ["wind_ring", 0.02],
			["ranger_hood", 0.015], ["frost_brand", 0.01], ["ember_staff", 0.01], ["elven_bow", 0.01]]},
	# Defesa da Cidade: brutamontes que derruba muros (dano em construções x3)
	"goblin_bruto": {"name": "Goblin Bruto", "model": "goblin", "hp": 280, "damage": 24, "speed": 2.9, "xp": 70,
		"gold": [8, 14], "aggro": 8.0, "reach": 2.2, "cooldown": 1.8, "radius": 0.62, "height": 1.35,
		"scale": 1.5, "color": Color(0.7, 0.1, 0.05), "bld": 3.0,
		"loot": [["goblin_ear", 0.8], ["health_potion", 0.12], ["iron_helm", 0.02], ["chain_mail", 0.02]]},
	"goblin_king": {"name": "Rei Goblin", "model": "goblin", "hp": 900, "damage": 26, "speed": 3.6, "xp": 450,
		"gold": [90, 130], "aggro": 20.0, "reach": 3.2, "cooldown": 1.5, "radius": 0.95, "height": 2.9,
		"scale": 2.2, "color": Color(0.7, 0.1, 0.05), "boss": true, "bld": 2.5,
		"loot": [["goblin_crown", 1.0], ["goblin_cleaver", 1.0], ["health_potion", 1.0], ["seed_pumpkin", 1.0], ["seed_mint", 1.0],
			["goblin_warbow", 0.5], ["knight_helm", 0.35], ["guardian_greatsword", 0.25], ["vampire_ring", 0.2],
			["frost_scepter", 0.3], ["swift_boots", 0.3], ["sage_amulet", 0.25],
			["dragonfang", 0.06], ["archmage_staff", 0.06], ["storm_bow", 0.06], ["dragon_plate", 0.06]]},
}

@export var kind := "slime"
## Desafio da Horda: persegue sempre o jogador, não volta para casa e não dá XP/loot do RPG.
var horde := false
var hp_mult := 1.0
var dmg_mult := 1.0
var speed_mult := 1.0
## Defesa da Cidade em grupo: elite (chave de ColonyData.AFFIXES) com resistências por tipo de dano.
var affix := ""
## Multiplayer (servidor): "world" (Valdoria) ou "city" (Defesa da Cidade em grupo).
var net_zone := "world"
## Defesa da Cidade: marcha até a prefeitura e ataca construções, soldados e o jogador no caminho.
var siege := false
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
	max_hp = data.hp * hp_mult
	hp = max_hp
	radius = data.radius
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
	model.scale = Vector3.ONE * data.scale
	add_child(model)
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
	if is_boss:
		var aura := OmniLight3D.new()
		aura.light_color = Color(1, 0.3, 0.1)
		aura.light_energy = 1.5
		aura.omni_range = 6.0
		aura.position.y = 2.0
		add_child(aura)

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


func _exit_tree() -> void:
	if net_id != 0:
		Network.unregister_enemy(self)


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
	attack_cd = max(0.0, attack_cd - delta)
	slow_timer = max(0.0, slow_timer - delta)
	stagger = max(0.0, stagger - delta)
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
			if horde:
				if dist == INF:
					_set_state("idle")
				elif dist <= data.reach and attack_cd <= 0:
					_begin_attack()
				elif dist > data.reach * 0.8:
					move = to_player.normalized() * spd
			elif dist > data.aggro * 1.9 or global_position.distance_to(home) > 45.0:
				_set_state("return")
			elif dist <= data.reach and attack_cd <= 0:
				_begin_attack()
			elif dist > data.reach * 0.8:
				move = to_player.normalized() * spd
			face = to_player
		"return":
			var to := home - global_position
			to.y = 0
			if dist < data.aggro * 0.7:
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
			elif dist < INF and attack_timer < 0.35:
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


# ------------------------------------------------------------ ataques
func _begin_attack() -> void:
	state = "attack"
	attack_timer = 0.0
	hit_done = false
	attack_count += 1
	if data.model == "slime":
		attack_kind = "lunge"
		velocity.y = 4.5
	elif is_boss and attack_count % 3 == 0:
		attack_kind = "slam"
		FX.telegraph(global_position, 5.0, 0.9)
	else:
		attack_kind = "swing"


func _attack_duration() -> float:
	match attack_kind:
		"slam":
			return 1.6
		"lunge":
			return 1.0
	return 0.95 if not is_boss else 1.1


func _hit_time() -> float:
	match attack_kind:
		"slam":
			return 0.9
		"lunge":
			return 0.45
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
		if attack_kind == "slam":
			Sfx.play_at("slam", global_position, 0.0)
			FX.ring(global_position, Color(0.8, 0.6, 0.3, 0.9), 5.0, 0.4)
			FX.burst(global_position + Vector3.UP * 0.3, Color(0.5, 0.4, 0.3), 40, 7.0, 0.2, 0.8)
			if player and dist <= 5.0:
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


# ------------------------------------------------------------ dano
func take_damage(amount: float, from_pos: Vector3, crit: bool, slow := 0.0) -> void:
	if dead:
		return
	if puppet:
		# o servidor decide; os números de dano chegam de volta em show_hit()
		Network.client_hit_enemy(net_id, amount, from_pos, crit, slow)
		return
	if last_hitter != 0:
		contributors[last_hitter] = true
	if slow > 0.0:
		apply_slow(slow)
	hp -= amount
	health_changed.emit(self)
	var top: Vector3 = global_position + Vector3.UP * (data.height * data.scale + 0.2)
	FX.damage_number(top, ("%d!" if crit else "%d") % int(round(amount)),
		Color(1, 0.85, 0.2) if crit else Color.WHITE, 64 if crit else 48)
	FX.burst(global_position + Vector3.UP * data.height * data.scale * 0.5, data.color, 5 if horde else 10, 3.5, 0.1, 0.5)
	_flash_t = 0.1
	if state in ["idle", "wander", "return"]:
		_set_state("chase")
	if bar_root:
		bar_root.visible = true
	if not is_boss:
		var kb := global_position - from_pos
		kb.y = 0
		if kb.length() > 0.01:
			kb = kb.normalized() * (6.0 if data.model == "slime" else 4.0)
			velocity.x = kb.x
			velocity.z = kb.z
		if state != "attack" or crit:
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
		# XP, missões e loot são de cada jogador: quem acertou recebe no próprio PC
		Network.server_enemy_killed(self)
	elif siege:
		# cerco: o ouro vai direto para o cofre da cidade (os abates acontecem longe do jogador)
		Game.on_enemy_killed(kind, int(data.xp * 0.6))
		var g: Array = data.gold
		Game.add_gold(randi_range(g[0], g[1]))
		drop_loot(get_parent(), kind, global_position, false)
	elif not horde:
		Game.on_enemy_killed(kind, data.xp)
		if is_boss:
			Game.flags["king_dead"] = true
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


static func drop_loot(parent: Node, enemy_kind: String, pos: Vector3, with_gold := true) -> void:
	var t: Dictionary = TYPES[enemy_kind]
	var g: Array = t.gold
	if with_gold:
		_spawn_pickup(parent, "", randi_range(g[0], g[1]), pos)
	for entry in t.loot:
		if randf() < entry[1]:
			_spawn_pickup(parent, entry[0], 1, pos)


static func _spawn_pickup(parent: Node, id: String, qty: int, pos: Vector3) -> void:
	var p := PICKUP.new()
	p.item_id = id
	p.amount = qty
	parent.add_child(p)
	p.global_position = pos + Vector3.UP * 0.8


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
				FX.telegraph(global_position, 5.0, 0.9)
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
				FX.ring(global_position, Color(0.8, 0.6, 0.3, 0.9), 5.0, 0.4)
				FX.burst(global_position + Vector3.UP * 0.3, Color(0.5, 0.4, 0.3), 40, 7.0, 0.2, 0.8)
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
