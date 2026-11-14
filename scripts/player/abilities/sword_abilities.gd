class_name SwordAbilities
extends RefCounted
## Habilidades da espada. Estado em player.gd: `ability` (id em execução), `ability_t` (tempo desde
## o início) e `ability_data` (rascunho da habilidade; end_ability() libera os nós de "nodes" e
## restaura "mask"). Enquanto `ability != ""` o jogador não ataca, não usa outras habilidades nem o
## arco, e _physics_process chama tick() (local e réplicas; nas réplicas só o visual).
## A recarga é de player.cast(): use() só diz se a habilidade começou.

# ------------------------------------------------------------------ Investida (slot 1)
const CHARGE_WINDUP := 0.15     ## preparo: agacha com a espada para trás (a esquiva cancela)
const CHARGE_DASH := 0.25       ## avanço
const CHARGE_RECOVER := 0.2     ## recuperação
const CHARGE_TIME := CHARGE_WINDUP + CHARGE_DASH + CHARGE_RECOVER
const CHARGE_DIST := 5.0
const CHARGE_MULT := 1.6        ## dano = Game.melee_damage() * CHARGE_MULT, uma vez por inimigo
const CHARGE_RADIUS := 1.4
const CHARGE_ENEMY_LAYER := 4   ## atravessa inimigos (para só em parede)
const CHARGE_TRAIL_W := 0.32    ## altura da fita do rastro (m)
const CHARGE_DUST := Color(0.5, 0.44, 0.36, 0.55)


## Executa a habilidade `id` para `player`. Devolve true só se ela começou.
static func use(player: Node, id: String) -> bool:
	match id:
		"sword_charge":
			player.begin_ability(id, {"dir": player.facing()})
			Network.send_event(id, player.global_position, player.facing())
			Sfx.play("swing", 0.1, -8.0)
			return true
	return false


## Um passo de física da habilidade em execução (jogador local e réplicas).
## `move_dir` = direção pedida pelo jogador, relativa à câmera (comprimento 0..1) e `move_speed` =
## velocidade de andar atual: para habilidades que deixam andar devagar. Nas réplicas vêm zerados.
static func tick(player: Node, delta: float, move_dir := Vector3.ZERO, move_speed := 0.0) -> void:
	var t0: float = player.ability_t
	player.ability_t += delta
	match player.ability:
		"sword_charge":
			_charge_tick(player, t0, player.ability_t, delta)
		_:
			player.end_ability()


## A esquiva pode interromper a habilidade agora?
static func can_dodge_cancel(player: Node) -> bool:
	return player.ability == "sword_charge" and player.ability_t <= CHARGE_WINDUP


## Pose da habilidade por cima da locomoção (de _animate). O passo inteiro das pernas: move = 0.
static func pose(player: Node, p: Dictionary) -> void:
	match player.ability:
		"sword_charge":
			KnightAnim.play_track(p, KnightMoves.CHARGE, clampf(player.ability_t / CHARGE_TIME, 0.0, 1.0), 0.0)


## Réplica: começa a habilidade de outro jogador pelo evento de rede (só visual; dano já foi do dono).
static func play_remote(player: Node, kind: String, a: Vector3, b: Vector3) -> void:
	match kind:
		"sword_charge":
			player.begin_ability(kind, {"dir": b, "origin": a})
			Sfx.play_at("swing", a, 0.1, -8.0)


# ------------------------------------------------------------------ Investida
static func _charge_tick(player: Node, t0: float, t: float, delta: float) -> void:
	var d: Dictionary = player.ability_data
	var dir: Vector3 = d.dir
	var dash_end := CHARGE_WINDUP + CHARGE_DASH
	var local: bool = not player.remote
	_follow_trail(d)
	# saída: poeira, rastro na espada e passa a atravessar inimigos (até end_ability)
	if t0 <= CHARGE_WINDUP and t > CHARGE_WINDUP:
		d.origin = player.global_position
		d.dashing = true
		FXEpic.smoke(player.global_position + Vector3.UP * 0.2, CHARGE_DUST, 10, 0.7, 0.9)
		_attach_trail(player)
		Sfx.play_at("swing", player.global_position, 0.05, -2.0)
		if local:
			d.mask = player.collision_mask
			player.collision_mask &= ~CHARGE_ENEMY_LAYER
	if d.get("dashing", false):
		var flat: Vector3 = player.global_position - d.origin
		flat.y = 0.0
		var left: float = CHARGE_DIST - flat.length()
		if local:
			# para em parede (o passo anterior bateu de frente) ou ao completar a distância
			var wall: bool = player.is_on_wall() and player.get_wall_normal().dot(dir) < -0.5 and t0 > CHARGE_WINDUP
			if wall or left <= 0.02 or t > dash_end:
				_charge_arrive(player, d)
			else:
				# o que falta no tempo que falta (os passos de física não caem certinho nas fases)
				var base := CHARGE_DIST / CHARGE_DASH
				var spd := clampf(left / maxf(dash_end - t + delta, delta), base, base * 1.5)
				spd = minf(spd, left / maxf(delta, 0.001))
				player.velocity.x = dir.x * spd
				player.velocity.z = dir.z * spd
				_charge_hits(player, d)
		elif t > dash_end:
			_charge_arrive(player, d)
		if d.get("dashing", false):
			# faíscas raspando no chão atrás dos pés
			d.spark_t = float(d.get("spark_t", 0.0)) - delta
			if d.spark_t <= 0.0:
				d.spark_t = 0.045
				FXEpic.sparks(player.global_position + Vector3.UP * 0.08, -dir + Vector3.UP * 0.6,
					Color(1.0, 0.72, 0.35), 5, 5.0, 0.28)
	elif local:
		# preparo parado; na recuperação escorrega um pouco e assenta
		player.velocity.x = move_toward(player.velocity.x, 0.0, 30.0 * delta)
		player.velocity.z = move_toward(player.velocity.z, 0.0, 30.0 * delta)
	if t >= CHARGE_TIME - 0.0001:
		player.end_ability()


static func _charge_arrive(player: Node, d: Dictionary) -> void:
	d.dashing = false
	var dir: Vector3 = d.dir
	if not player.remote:
		_charge_hits(player, d)
		player.velocity.x = dir.x * 2.5
		player.velocity.z = dir.z * 2.5
	FXEpic.smoke(player.global_position + dir * 0.4 + Vector3.UP * 0.2, CHARGE_DUST, 14, 0.9, 1.1)


## Fere uma vez cada inimigo vivo a até CHARGE_RADIUS do jogador.
static func _charge_hits(player: Node, d: Dictionary) -> void:
	var hit: Dictionary = d.get_or_add("hit", {})
	var first := hit.is_empty()
	var any := false
	for e in player.get_tree().get_nodes_in_group("enemies"):
		if e.dead or hit.has(e.get_instance_id()):
			continue
		var to: Vector3 = e.global_position - player.global_position
		to.y = 0.0
		if to.length() > CHARGE_RADIUS + e.radius:
			continue
		hit[e.get_instance_id()] = true
		var dmg: float = Game.melee_damage() * CHARGE_MULT
		e.take_damage(dmg, player.global_position, false)
		Game.on_damage_dealt(dmg, e.max_hp)
		any = true
		FXEpic.sparks(e.global_position + Vector3.UP * 0.6, d.dir, Color(1.0, 0.85, 0.5), 14, 9.0, 0.3)
	if any:
		Sfx.play("hit")
		player.add_shake(0.18)
		if first:
			FXEpic.flash(player.global_position + Vector3.UP * 1.0 + d.dir * 0.8, Color(1.0, 0.8, 0.5), 1.6, 4.0, 0.15)


## Rastro da lâmina: na estocada a espada aponta para onde o jogador vai, então uma fita presa ao eixo
## da lâmina viraria um lençol deitado no caminho. O marcador fica perto da ponta (filho do suporte da
## espada, mas top_level) com o eixo Y sempre para cima: a fita fica em pé atrás da lâmina.
static func _attach_trail(player: Node) -> void:
	var holder = player.look.get("holder")
	var tip = player.look.get("tip")
	if not is_instance_valid(holder) or not is_instance_valid(tip):
		return
	var m := Node3D.new()
	m.name = "ChargeTrail"
	m.top_level = true
	holder.add_child(m)
	var d: Dictionary = player.ability_data
	d.get_or_add("nodes", []).append(m)
	d.trail = m
	d.trail_at = (tip.position as Vector3) * 0.75
	_follow_trail(d)
	var c: Color = ItemDB.get_item(player._last_look.get("weapon", "")).get("color", Color(0.75, 0.88, 1.0))
	FXEpic.trail(m, Color(1.0, 0.55, 0.15).lerp(c, 0.25), CHARGE_TRAIL_W, CHARGE_TIME)


static func _follow_trail(d: Dictionary) -> void:
	var m = d.get("trail")
	if not is_instance_valid(m) or not is_instance_valid(m.get_parent()):
		return
	var holder: Node3D = m.get_parent()
	m.global_transform = Transform3D(Basis.IDENTITY, holder.to_global(d.trail_at) - Vector3.UP * CHARGE_TRAIL_W * 0.5)
