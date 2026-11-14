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

# ------------------------------------------------------------------ Flecha do Vendaval (ultimate, slot 4)
const GALE_CHARGE := 1.2        ## segurando a tecla a carga vai de 0 a 1 neste tempo (s); cheia, dispara sozinha
const GALE_MIN := 0.25          ## carga mínima do disparo (soltar antes continua tensionando até aqui)
const GALE_RANGE := 40.0        ## alcance do raio (m); para antes na primeira parede
const GALE_TRAVEL := 0.25       ## o raio percorre GALE_RANGE neste tempo (s)
const GALE_RECOVER := 0.4
const GALE_MULT_MIN := 3.0      ## dano = Game.melee_damage() * lerp(GALE_MULT_MIN, GALE_MULT_MAX, carga)
const GALE_MULT_MAX := 6.0
const GALE_HEIGHT := 1.1        ## altura do raio acima dos pés (m)
const GALE_RADIUS := 1.1        ## meia largura da linha (m), somada ao raio do inimigo
const GALE_VERT := 2.5          ## diferença de altura máxima entre os pés do inimigo e os do jogador (m)
const GALE_WALL_MASK := 1       ## só o cenário para o raio (inimigos, camada 4, são atravessados)
const GALE_CAM_BACK := 0.7      ## a câmera recua (m) com a carga cheia
const GALE_FOV := 7.0           ## o FOV fecha até 7 graus com a carga (foco) e abre 4 no disparo
const GALE_RECOIL := 6.0        ## recuo do corpo no disparo (m/s, para trás, com a carga cheia)
const GALE_SPIRAL := TAU / 9.0  ## giro do vento em espiral ao longo da linha (rad por m)
const GALE_WIND := Color(0.78, 0.9, 1.0)
const GALE_CORE := Color(0.93, 0.97, 1.0)
const GALE_BEAM := Color(0.42, 0.8, 1.0)       ## núcleo da linha: ciano frio (a borda vai a GALE_BEAM_HOT)
const GALE_BEAM_HOT := Color(0.85, 1.0, 1.0)
const GALE_BEAM_GAIN := 1.5                      ## brilho HDR do núcleo (se destaca sobre areia ao sol)
const GALE_DUST := Color(0.72, 0.68, 0.6, 0.45)
const GALE_MARK := Color(0.4, 0.38, 0.34, 0.55)


## Executa a habilidade `id` para `player`. Devolve true só se ela começou.
static func use(player: Node, id: String) -> bool:
	match id:
		"bow_triple", "bow_frost":
			player.begin_ability(id, {})
			Sfx.play("swing", 0.3, -12.0)
			return true
		"bow_gale":
			player.begin_ability(id, {"charge": 0.0, "fov0": player.camera.fov})
			Network.send_event(id, player.global_position, Vector3.ZERO)
			_gale_start(player)
			Sfx.play("swing", 0.25, -10.0)
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
		"bow_gale":
			_gale_tick(player, t0, player.ability_t, delta)
		_:
			player.end_ability()


## A esquiva pode interromper a habilidade agora?
static func can_dodge_cancel(player: Node) -> bool:
	if player.ability == "bow_gale":
		return false   # a fúria já foi gasta em use(): a esquiva não desperdiça a ultimate
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
		"bow_gale":
			var d: Dictionary = player.ability_data
			var rec := -1.0
			if d.get("fired", false):
				rec = clampf((player.ability_t - float(d.fire_t)) / GALE_RECOVER, 0.0, 1.0)
			KnightAnim.bow_gale_pose(p, float(d.get("charge", 0.0)), rec)


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
		"bow_gale":
			# o dono começou a tensionar: pose e vento (o disparo chega em "bow_gale_fire")
			player.begin_ability(kind, {"charge": 0.0})
			_gale_start(player)
			Sfx.play_at("swing", a, 0.25, -10.0)
		"bow_gale_fire":
			# b = direção * carga; sem dano nem hit stop (o dano é do dono)
			if player.ability != "bow_gale" or player.ability_data.get("fired", false):
				player.begin_ability("bow_gale", {"charge": 0.0})
			var dir := Vector3(b.x, 0.0, b.z)
			var c := clampf(dir.length(), GALE_MIN, 1.0)
			dir = dir.normalized() if dir.length() > 0.001 else player.facing()
			_gale_shoot(player, a, dir, c)


## A tecla do slot da habilidade em execução foi solta: a Flecha do Vendaval dispara (com carga >= GALE_MIN;
## antes disso continua tensionando até GALE_MIN e dispara sozinha no tick).
static func release(player: Node) -> void:
	if player.ability != "bow_gale" or player.remote:
		return
	var d: Dictionary = player.ability_data
	if d.get("fired", false):
		return
	d.released = true
	if float(d.get("charge", 0.0)) >= GALE_MIN:
		_gale_fire(player, d)


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


# ------------------------------------------------------------------ Flecha do Vendaval
## Direção do raio: o rumo da mira (do peito até onde a câmera aponta) no plano horizontal. A inclinação
## da câmera fica de fora: a mira padrão aponta para o chão a ~10 m e o raio pararia ali.
static func _gale_dir(player: Node) -> Vector3:
	var d: Vector3 = player.aim_dir(player.global_position + Vector3.UP * GALE_HEIGHT)
	d.y = 0.0
	if d.length() < 0.01:
		return player.facing()
	return d.normalized()


## Até onde o raio vai de `origin` em `dir`: GALE_RANGE ou a primeira parede (só o cenário).
static func _gale_length(player: Node, origin: Vector3, dir: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * GALE_RANGE, GALE_WALL_MASK)
	q.exclude = [player.get_rid()]
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(q)
	return GALE_RANGE if hit.is_empty() else origin.distance_to(hit.position)


## Começo da tensão (dono e réplicas): luz na ponta da flecha, vento espiralando em volta e sendo
## puxado para o jogador, poeira girando no chão. Os nós vão em "nodes" (end_ability os libera).
static func _gale_start(player: Node) -> void:
	var d: Dictionary = player.ability_data
	var nodes: Array = d.get_or_add("nodes", [])
	if FX._scene() == null:
		return   # servidor dedicado: sem efeitos
	var light := OmniLight3D.new()
	light.light_color = GALE_WIND
	light.light_energy = 0.0
	light.omni_range = 2.5
	light.shadow_enabled = false
	player.add_child(light)
	light.global_position = player.weapon_tip()
	nodes.append(light)
	d.light = light
	# vento: fios de luz finos girando em volta do jogador e puxados para o centro (para a flecha)
	var wind := FXEpic.stream(player, "glow", GALE_WIND, 90, 0.6, 0.08)
	if wind:
		wind.position = Vector3(0, GALE_HEIGHT, 0)
		wind.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		wind.emission_ring_axis = Vector3.UP
		wind.emission_ring_radius = 1.9
		wind.emission_ring_inner_radius = 1.2
		wind.emission_ring_height = 1.6
		wind.direction = Vector3.UP
		wind.spread = 30.0
		wind.initial_velocity_min = 0.3
		wind.initial_velocity_max = 0.8
		wind.gravity = Vector3.ZERO
		wind.radial_accel_min = -4.0
		wind.radial_accel_max = -3.0
		wind.tangential_accel_min = 6.0
		wind.tangential_accel_max = 9.0
		wind.scale_amount_min = 0.5
		wind.scale_amount_max = 0.9
		nodes.append(wind)
		d.wind = wind
	# poeira girando no chão em volta dos pés
	var dust := FXEpic.stream(player, "smoke", GALE_DUST, 22, 1.0, 0.9)
	if dust:
		dust.position = Vector3(0, 0.15, 0)
		dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		dust.emission_ring_axis = Vector3.UP
		dust.emission_ring_radius = 2.3
		dust.emission_ring_inner_radius = 1.2
		dust.emission_ring_height = 0.05
		dust.direction = Vector3.UP
		dust.spread = 15.0
		dust.initial_velocity_min = 0.2
		dust.initial_velocity_max = 0.6
		dust.gravity = Vector3(0, 0.3, 0)
		dust.radial_accel_min = -1.5
		dust.radial_accel_max = -0.5
		dust.tangential_accel_min = 5.0
		dust.tangential_accel_max = 8.0
		dust.damping_min = 0.5
		dust.damping_max = 1.0
		nodes.append(dust)
		d.dust = dust
	# brilho na ponta da flecha (preso ao marcador da ponta da arma)
	var tip = player.look.get("tip")
	if is_instance_valid(tip):
		var glow := FXEpic.stream(tip, "glow", GALE_CORE, 20, 0.22, 0.05)
		if glow:
			glow.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			glow.emission_sphere_radius = 0.06
			glow.direction = Vector3.UP
			glow.spread = 180.0
			glow.initial_velocity_min = 0.1
			glow.initial_velocity_max = 0.4
			glow.gravity = Vector3.ZERO
			nodes.append(glow)
			d.tip_glow = glow
	FXEpic.glow_burst(player.global_position + Vector3.UP * 0.2, GALE_WIND, 10, 2.0, 0.08, 0.5, 2.0)


static func _gale_tick(player: Node, t0: float, t: float, delta: float) -> void:
	var d: Dictionary = player.ability_data
	var local: bool = not player.remote
	if not d.get("fired", false):
		var c := clampf(t / GALE_CHARGE, 0.0, 1.0)
		d.charge = c
		if local:
			# parado; a câmera recua, o FOV fecha (foco) e o corpo segue a mira da câmera
			player.velocity.x = move_toward(player.velocity.x, 0.0, 40.0 * delta)
			player.velocity.z = move_toward(player.velocity.z, 0.0, 40.0 * delta)
			player.cam_back = GALE_CAM_BACK * c
			if d.has("fov0"):
				player.camera.fov = float(d.fov0) - GALE_FOV * smoothstep(0.0, 1.0, c)
			var f: Vector3 = -player.cam_yaw.global_basis.z
			f.y = 0.0
			if f.length() > 0.01:
				player.model.rotation.y = lerp_angle(player.model.rotation.y, atan2(f.x, f.z), 1.0 - exp(-14.0 * delta))
		_gale_charge_fx(player, d, t0, t, c)
		if local and (c >= 1.0 or (d.get("released", false) and c >= GALE_MIN)):
			_gale_fire(player, d)
		elif not local and t > GALE_CHARGE + 1.5:
			player.end_ability()   # réplica: o disparo nunca chegou
		return
	var since: float = t - float(d.fire_t)
	var light = d.get("light")
	if is_instance_valid(light):
		light.light_energy = 6.0 * maxf(0.0, 1.0 - since / 0.2)
	if local:
		# o recuo assenta; a câmera volta aos poucos e o FOV, aberto no disparo, também
		player.velocity.x = move_toward(player.velocity.x, 0.0, 22.0 * delta)
		player.velocity.z = move_toward(player.velocity.z, 0.0, 22.0 * delta)
		player.cam_back = GALE_CAM_BACK * float(d.charge) * (1.0 - smoothstep(0.0, 1.0, since / GALE_RECOVER))
		if d.has("fov0"):
			player.camera.fov = lerpf(player.camera.fov, float(d.fov0), 1.0 - exp(-8.0 * delta))
		_gale_hits(player, d, minf(float(d.len), since / GALE_TRAVEL * GALE_RANGE))
	if since >= GALE_RECOVER - 0.0001:
		player.end_ability()


## Tensão: luz da ponta crescendo, o vento girando mais rápido e mais apertado, pulsos de brilho na
## ponta e um anel quando a carga passa do mínimo (a partir daí soltar já dispara).
static func _gale_charge_fx(player: Node, d: Dictionary, t0: float, t: float, c: float) -> void:
	var tip: Vector3 = player.weapon_tip()
	var light = d.get("light")
	if is_instance_valid(light):
		light.global_position = tip
		light.light_energy = 0.3 + 3.2 * c * c
		light.omni_range = 2.5 + 3.0 * c
	var wind = d.get("wind")
	if is_instance_valid(wind):
		wind.tangential_accel_min = 6.0 + 10.0 * c
		wind.tangential_accel_max = 9.0 + 14.0 * c
		wind.radial_accel_min = -(4.0 + 8.0 * c)
		wind.radial_accel_max = -(3.0 + 6.0 * c)
		wind.scale_amount_max = 0.9 + 0.8 * c
	if FX._scene() == null:
		return
	if int(t0 / 0.3) != int(t / 0.3):
		FXEpic.glow_burst(tip, GALE_CORE, 6 + int(8.0 * c), 0.6 + c, 0.05 + 0.06 * c, 0.3, 0.0)
	var ready_t := GALE_MIN * GALE_CHARGE
	if t0 < ready_t and t >= ready_t:
		FX.ring(player.global_position, Color(GALE_WIND.r, GALE_WIND.g, GALE_WIND.b, 0.6), 2.2, 0.35)


## Dispara (só o dono): direção da mira, avisa as réplicas e começa o raio; o dano corre no tick.
static func _gale_fire(player: Node, d: Dictionary) -> void:
	var dir := _gale_dir(player)
	var origin: Vector3 = player.global_position + Vector3.UP * GALE_HEIGHT
	var c: float = maxf(float(d.get("charge", 0.0)), GALE_MIN)
	player.model.rotation.y = atan2(dir.x, dir.z)
	Network.send_event("bow_gale_fire", origin, dir * c)
	_gale_shoot(player, origin, dir, c)
	# recuo forte: o corpo escorrega para trás, a tela treme e o FOV abre num soco
	player.velocity.x = -dir.x * GALE_RECOIL * (0.5 + 0.5 * c)
	player.velocity.z = -dir.z * GALE_RECOIL * (0.5 + 0.5 * c)
	player.add_shake(0.35)
	if d.has("fov0"):
		player.camera.fov = float(d.fov0) + 4.0 * c


## Disparo (dono e réplicas): guarda a linha, para o vento da tensão e cria os efeitos do tiro.
static func _gale_shoot(player: Node, origin: Vector3, dir: Vector3, c: float) -> void:
	var d: Dictionary = player.ability_data
	d.fired = true
	d.fire_t = player.ability_t
	d.charge = c
	d.origin = origin
	d.dir = dir
	d.len = _gale_length(player, origin, dir)
	d.hit = {}
	for key in ["wind", "dust", "tip_glow"]:
		_stop_stream(d, key)
	Sfx.play_at("swing", origin, 0.05, 2.0)
	Sfx.play_at("slam", origin, 0.1, -6.0)
	var root := FX._scene()
	if root == null:
		return
	var feet := origin - Vector3.UP * GALE_HEIGHT
	var muzzle := origin + dir * 0.7
	# onda de choque no disparo
	FX.ring(feet, Color(0.85, 0.93, 1.0, 0.3), 2.5 + 2.0 * c, 0.4)
	FXEpic.nova(feet + Vector3.UP * 0.25, GALE_WIND, 40, 8.0, 0.14, 0.45)
	FXEpic.glow_burst(muzzle, Color.WHITE, 30, 7.0, 0.2, 0.45, 0.0)
	FXEpic.flash(muzzle, GALE_WIND, 5.0, 9.0, 0.3)
	# linhas de velocidade saindo da corda e poeira levantada atrás do recuo
	FXEpic.sparks(muzzle, dir, GALE_CORE, 24, 30.0, 0.25)
	FXEpic.smoke(feet + Vector3.UP * 0.2 - dir * 0.6, GALE_DUST, 10, 1.0, 0.8)
	var line := GaleLine.new()
	line.origin = origin
	line.dir = dir
	line.length = d.len
	line.charge = c
	root.add_child(line)


## Para um emissor de stream() guardado em d[key] deixando as partículas vivas terminarem.
static func _stop_stream(d: Dictionary, key: String) -> void:
	var p = d.get(key)
	if not is_instance_valid(p):
		return
	d.erase(key)
	d.get("nodes", []).erase(p)
	FXEpic.stop_stream(p)


## Fere (uma vez) cada inimigo na linha até `front` m da origem; empurra para os lados da linha.
static func _gale_hits(player: Node, d: Dictionary, front: float) -> void:
	var origin: Vector3 = d.origin
	var dir: Vector3 = d.dir
	var feet_y := origin.y - GALE_HEIGHT
	var hit: Dictionary = d.hit
	var first := hit.is_empty()
	var n := hit.size()
	var dmg: float = Game.melee_damage() * lerpf(GALE_MULT_MIN, GALE_MULT_MAX, float(d.charge))
	var any := false
	for e in player.get_tree().get_nodes_in_group("enemies"):
		if e.dead or hit.has(e.get_instance_id()):
			continue
		var rel: Vector3 = e.global_position - origin
		rel.y = 0.0
		var along := rel.dot(dir)
		if along < -e.radius or along > front + e.radius:
			continue
		var lat := rel - dir * along
		if lat.length() > GALE_RADIUS + e.radius or absf(e.global_position.y - feet_y) > GALE_VERT:
			continue
		hit[e.get_instance_id()] = true
		# o golpe "vem" do outro lado da linha: o empurrão sai para o lado
		var out := lat.normalized() if lat.length() > 0.05 else dir.cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
		e.take_damage(dmg, e.global_position - out, false)
		Game.on_damage_dealt(dmg, e.max_hp, false)   # a ultimate não recarrega a própria fúria
		any = true
		if n < 6:   # faíscas para o lado em quem foi atravessado (numa multidão, só nos 6 primeiros)
			var at: Vector3 = e.global_position + Vector3.UP * 0.6
			FXEpic.sparks(at, dir + out * 0.4, GALE_WIND, 12, 14.0, 0.3)
			if n < 3:
				FXEpic.glow_burst(at, GALE_CORE, 10, 4.0, 0.12, 0.3, 0.0)
		n += 1
	if any:
		Sfx.play("hit")
		if first:
			FXEpic.hit_stop(0.06)


## O raio visual (dono e réplicas): a cabeça percorre a linha em GALE_TRAVEL (proporcional ao
## comprimento) levando três fitas de vento em espiral e duas fitas do núcleo em cruz, com uma luz;
## solta faíscas alinhadas pelo caminho e deixa marcas de vento no chão. Some sozinho.
class GaleLine extends Node3D:
	var origin := Vector3.ZERO
	var dir := Vector3.FORWARD
	var length := 40.0
	var charge := 1.0
	var _t := 0.0
	var _side := Vector3.RIGHT
	var _spirals: Array = []
	var _flat: Node3D
	var _upright: Node3D
	var _light: OmniLight3D
	var _next_spark := 2.0
	var _marks: Array = []
	var _ended := false
	var _core_w := 0.6

	func _ready() -> void:
		top_level = true
		global_transform = Transform3D.IDENTITY
		_side = dir.cross(Vector3.UP).normalized()
		var travel := _travel()
		for i in 3:
			var m := Node3D.new()
			add_child(m)
			_spirals.append(m)
		_flat = Node3D.new()
		add_child(_flat)
		_upright = Node3D.new()
		add_child(_upright)
		_core_w = 0.35 + 0.35 * charge
		_light = OmniLight3D.new()
		_light.light_color = BowAbilities.GALE_WIND
		_light.light_energy = 4.0
		_light.omni_range = 6.0
		_light.shadow_enabled = false
		add_child(_light)
		_place(0.0)
		# a fita segue a cabeça e fica parada no fim: a linha inteira continua no ar até os pontos
		# envelhecerem (life), em vez de sumir toda junto quando o alvo para
		for m in _spirals:
			FXEpic.trail(m, BowAbilities.GALE_WIND, 0.22, travel + 0.4, 0.7, Color(0, 0, 0, 0), BowAbilities.GALE_BEAM_HOT, 1.4)
		for m in [_flat, _upright]:
			FXEpic.trail(m, BowAbilities.GALE_BEAM, _core_w, travel + 0.4, 0.8, Color(0, 0, 0, 0),
				BowAbilities.GALE_BEAM_HOT, BowAbilities.GALE_BEAM_GAIN)
		for f in [0.12, 0.37, 0.62, 0.87]:
			if length * f >= 1.5:
				_marks.append(length * f)

	func _travel() -> float:
		return BowAbilities.GALE_TRAVEL * length / BowAbilities.GALE_RANGE

	## Põe a cabeça do raio a `s` m da origem.
	func _place(s: float) -> void:
		var head := origin + dir * s
		var r := 0.35 + 0.2 * charge
		for i in _spirals.size():
			var a := i * TAU / _spirals.size() + s * BowAbilities.GALE_SPIRAL
			var radial := _side * cos(a) + Vector3.UP * sin(a)
			# eixo Y para fora: a fita vai de r a r + largura, uma pá girando em volta da linha
			(_spirals[i] as Node3D).global_transform = Transform3D(Basis(dir, radial, dir.cross(radial)), head + radial * r)
		_flat.global_transform = Transform3D(Basis(dir, _side, dir.cross(_side)), head - _side * _core_w * 0.5)
		_upright.global_transform = Transform3D(Basis(-_side, Vector3.UP, dir), head - Vector3.UP * _core_w * 0.5)
		_light.global_position = head

	func _process(delta: float) -> void:
		_t += delta
		var s := minf(_t / BowAbilities.GALE_TRAVEL * BowAbilities.GALE_RANGE, length)
		if not _ended:
			_place(s)
			while _next_spark <= s:
				FXEpic.sparks(origin + dir * _next_spark, dir + Vector3.UP * 0.05, BowAbilities.GALE_WIND, 6, 16.0, 0.3)
				_next_spark += 3.5
			while not _marks.is_empty() and float(_marks[0]) <= s:
				_mark(float(_marks.pop_front()))
			if s >= length:
				_ended = true
				_impact()
		_light.light_energy = 4.0 * clampf(1.0 - (_t - _travel()) / 0.3, 0.0, 1.0)
		if _t > _travel() + 1.5:
			queue_free()

	## Marca de vento no chão sob o ponto `at` da linha, com poeira.
	func _mark(at: float) -> void:
		var p := origin + dir * at
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP, p - Vector3.UP * 4.0, BowAbilities.GALE_WALL_MASK)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			return
		FXEpic.ground_mark(hit.position, BowAbilities.GALE_MARK, 1.3, 2.5, "scorch")
		FXEpic.smoke(hit.position + Vector3.UP * 0.2, BowAbilities.GALE_DUST, 6, 0.7, 0.8)

	## Fim da linha: estoura contra a parede (ou se dissipa no alcance máximo).
	func _impact() -> void:
		var p := origin + dir * length
		if length < BowAbilities.GALE_RANGE - 0.01:
			FXEpic.glow_burst(p, BowAbilities.GALE_CORE, 20, 5.0, 0.16, 0.4, 0.0)
			FXEpic.sparks(p, -dir + Vector3.UP * 0.4, BowAbilities.GALE_WIND, 16, 10.0, 0.35)
			FXEpic.smoke(p, BowAbilities.GALE_DUST, 8, 0.8, 0.9)
		else:
			FXEpic.glow_burst(p, BowAbilities.GALE_WIND, 10, 2.5, 0.1, 0.35, 0.0)
