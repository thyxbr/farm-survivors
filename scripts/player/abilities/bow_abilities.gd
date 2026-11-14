class_name BowAbilities
extends RefCounted
## Habilidades da classe arco (mesma API de SwordAbilities). Estático: o estado vive no Player
## (ability, ability_t, ability_data). Habilidades sem implementação: use() devolve false.

# ------------------------------------------------------------------ Tiro Triplo (slot 1)
const TRIPLE_DRAW := 0.12       ## puxa a corda (a esquiva cancela só até aqui)
const TRIPLE_RECOVER := 0.25
const TRIPLE_TIME := TRIPLE_DRAW + TRIPLE_RECOVER
const TRIPLE_MULT := 0.8        ## dano de cada flecha = Game.melee_damage() * TRIPLE_MULT
const TRIPLE_SPREAD := 12.0     ## ângulo entre flechas do leque (graus, plano horizontal)
const TRIPLE_SPEED := 42.0      ## velocidade da flecha de carga cheia
const PROJECTILE := preload("res://scripts/player/projectile.gd")
const TRIPLE_COLOR := Color(1.0, 0.85, 0.5)

# ------------------------------------------------------------------ Flecha Glacial (slot 2)
const FROST_DRAW := 0.35        ## tensão com a ponta brilhando (a esquiva cancela só até aqui)
const FROST_RECOVER := 0.25
const FROST_TIME := FROST_DRAW + FROST_RECOVER
const FROST_MULT := 1.4         ## dano = Game.melee_damage() * FROST_MULT
const FROST_SPEED := 40.0
const FROST_COLOR := Color(0.6, 0.88, 1.0)


## Executa a habilidade `id` para `player`. Devolve true só se ela começou.
static func use(player: Node, id: String) -> bool:
	match id:
		"bow_triple", "bow_frost":
			player.begin_ability(id, {})
			Sfx.play("swing", 0.3, -12.0)
			return true
	return false


## Um passo de física da habilidade em execução (jogador local e réplicas).
static func tick(player: Node, delta: float, _move_dir := Vector3.ZERO, _move_speed := 0.0) -> void:
	var t0: float = player.ability_t
	player.ability_t += delta
	match player.ability:
		"bow_triple":
			if not player.remote:
				# parado enquanto puxa e solta a corda
				player.velocity.x = move_toward(player.velocity.x, 0.0, 40.0 * delta)
				player.velocity.z = move_toward(player.velocity.z, 0.0, 40.0 * delta)
				if t0 < TRIPLE_DRAW and player.ability_t >= TRIPLE_DRAW:
					_triple_fire(player)
			if player.ability_t >= TRIPLE_TIME - 0.0001:
				player.end_ability()
		"bow_frost":
			if not player.remote:
				player.velocity.x = move_toward(player.velocity.x, 0.0, 40.0 * delta)
				player.velocity.z = move_toward(player.velocity.z, 0.0, 40.0 * delta)
				if t0 == 0.0:
					_frost_glow(player.weapon_tip())
				if t0 < FROST_DRAW and player.ability_t >= FROST_DRAW:
					_frost_fire(player)
			if player.ability_t >= FROST_TIME - 0.0001:
				player.end_ability()
		_:
			player.end_ability()


## A esquiva pode interromper a habilidade agora?
static func can_dodge_cancel(player: Node) -> bool:
	if player.ability == "bow_frost":
		return player.ability_t < FROST_DRAW
	return player.ability == "bow_triple" and player.ability_t < TRIPLE_DRAW


## Pose da habilidade por cima da locomoção (de _animate).
static func pose(player: Node, p: Dictionary) -> void:
	match player.ability:
		"bow_triple":
			if player.ability_t < TRIPLE_DRAW:
				KnightAnim.bow_draw_pose(p, player.ability_t / TRIPLE_DRAW)
			else:
				KnightAnim.bow_release_pose(p, clampf((player.ability_t - TRIPLE_DRAW) / TRIPLE_RECOVER, 0.0, 1.0), 0.0)
		"bow_frost":
			if player.ability_t < FROST_DRAW:
				KnightAnim.bow_draw_pose(p, player.ability_t / FROST_DRAW)
			else:
				KnightAnim.bow_release_pose(p, clampf((player.ability_t - FROST_DRAW) / FROST_RECOVER, 0.0, 1.0), 0.0)


## Réplica: começa a habilidade de outro jogador pelo evento de rede (só visual).
## O evento chega no disparo: pula a puxada e cria as 3 flechas visuais.
static func play_remote(player: Node, kind: String, a: Vector3, b: Vector3) -> void:
	match kind:
		"bow_triple":
			player.begin_ability(kind, {})
			player.ability_t = TRIPLE_DRAW
			for d in _triple_dirs(b):
				_spawn_visual(player, a, d)
			_triple_fx(player, a, b)
			Sfx.play_at("swing", a, 0.1, -2.0)
		"bow_frost":
			player.begin_ability(kind, {})
			player.ability_t = FROST_DRAW
			_spawn_visual(player, a, b.normalized(), true)
			_frost_fx(a, b)
			Sfx.play_at("swing", a, 0.1, -2.0)


## A tecla do slot da habilidade em execução foi solta.
static func release(_player: Node) -> void:
	pass


# ------------------------------------------------------------------ Tiro Triplo
## Direção central e os dois lados do leque (plano horizontal).
static func _triple_dirs(center: Vector3) -> Array:
	var a := deg_to_rad(TRIPLE_SPREAD)
	return [center.rotated(Vector3.UP, -a), center, center.rotated(Vector3.UP, a)]


## Dispara as 3 flechas (só o dono): a arma "multishot" não multiplica; "pierce" soma 2 de perfuração.
static func _triple_fire(player: Node) -> void:
	var origin: Vector3 = player.weapon_tip()
	var dir: Vector3 = player.aim_dir(origin)
	var pierce := 2 if player._weapon_fx() == "pierce" else 0
	for d in _triple_dirs(dir):
		var crit: bool = randf() < Game.crit_chance()
		var dmg: float = Game.melee_damage() * TRIPLE_MULT * (1.8 if crit else 1.0)
		player._spawn_projectile("arrow", origin, d, dmg, crit, pierce, TRIPLE_SPEED)
	Network.send_event("bow_triple", origin, dir)
	_triple_fx(player, origin, dir)
	Sfx.play("swing", 0.1, -2.0)
	player.add_shake(0.06)


## Efeito contido: faíscas curtas na mão do arco e um clarão fraco.
static func _triple_fx(_player: Node, origin: Vector3, dir: Vector3) -> void:
	FXEpic.sparks(origin, dir + Vector3.UP * 0.3, TRIPLE_COLOR, 8, 5.0, 0.2)
	FXEpic.flash(origin, TRIPLE_COLOR, 1.2, 3.0, 0.12)


## Flecha só visual (réplica): como o evento "arrow".
static func _spawn_visual(player: Node, origin: Vector3, d: Vector3, frost := false) -> void:
	var p := PROJECTILE.new()
	p.kind = "arrow"
	p.direction = d
	p.visual_only = true
	if frost:
		p.color = FROST_COLOR
		p.fx = "glacial"
		p.speed = FROST_SPEED
	else:
		p.color = ItemDB.get_item(player._last_look.get("weapon", "")).get("color", Color(0.6, 0.8, 1.0))
		p.speed = TRIPLE_SPEED
	p.life = 1.6
	player.get_tree().current_scene.add_child(p)
	p.global_position = origin
	if frost:
		FXEpic.trail(p, FROST_COLOR, 0.22, 0.5)


# ------------------------------------------------------------------ Flecha Glacial
## Tensão: brilho azul-gelo na ponta da flecha.
static func _frost_glow(tip: Vector3) -> void:
	FXEpic.glow_burst(tip, FROST_COLOR, 14, 1.2, 0.14, FROST_DRAW, 0.0)


## Dispara a flecha única (só o dono): dano x1,4, velocidade 40, sem perfuração; o gelo é do projétil (fx "glacial").
static func _frost_fire(player: Node) -> void:
	var origin: Vector3 = player.weapon_tip()
	var dir: Vector3 = player.aim_dir(origin)
	var crit: bool = randf() < Game.crit_chance()
	var dmg: float = Game.melee_damage() * FROST_MULT * (1.8 if crit else 1.0)
	var p = player._spawn_projectile("arrow", origin, dir, dmg, crit, 0, FROST_SPEED, "glacial", FROST_COLOR)
	FXEpic.trail(p, FROST_COLOR, 0.22, 0.5)
	Network.send_event("bow_frost", origin, dir)
	_frost_fx(origin, dir)
	Sfx.play("swing", 0.1, -2.0)
	player.add_shake(0.06)


static func _frost_fx(origin: Vector3, dir: Vector3) -> void:
	FXEpic.sparks(origin, dir + Vector3.UP * 0.3, FROST_COLOR, 8, 5.0, 0.2)
	FXEpic.flash(origin, FROST_COLOR, 1.4, 3.0, 0.12)
