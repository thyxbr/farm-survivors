class_name SwordAbilities
extends RefCounted
## Habilidades da espada. Estado em player.gd: `ability` (id em execução), `ability_t` (tempo desde
## o início) e `ability_data` (rascunho da habilidade; end_ability() libera os nós de "nodes" e
## restaura "mask"). Enquanto `ability != ""` o jogador não ataca, não usa outras habilidades nem o
## arco, e _physics_process chama tick() (local e réplicas; nas réplicas só o visual).
## A recarga é de player.cast(): use() só diz se a habilidade começou.

## Habilidade de buff (slot 3; com a montante, slot 5): pose curta de braços erguidos; o efeito é o buff "sword_fury"
## (Game.add_buff). "sword_fury_great" é a mesma Fúria Picante na tecla 5 da montante (ItemDB.ABILITIES).
const BUFF_TIME := 0.5
const FURY_BUFF := "sword_fury"
const BUFF_COLOR := Color(1.0, 0.3, 0.15)

# ------------------------------------------------------------------ Investida (slot 1)
const CHARGE_WINDUP := 0.15     ## preparo: agacha com a espada para trás (a esquiva cancela)
const CHARGE_DASH := 0.25       ## avanço
const CHARGE_RECOVER := 0.2     ## recuperação
const CHARGE_TIME := CHARGE_WINDUP + CHARGE_DASH + CHARGE_RECOVER
const CHARGE_CUT_AT := 0.41     ## a lâmina começa o corte de chegada (medido: ver FXToon.CHARGE_CUT)
const CHARGE_DIST := 5.0
const CHARGE_MULT := 1.6        ## dano = Game.melee_damage() * CHARGE_MULT, uma vez por inimigo
const CHARGE_RADIUS := 1.4
const CHARGE_ENEMY_LAYER := 4   ## atravessa inimigos (para só em parede)

# ------------------------------------------------------------------ Golpe Sísmico (slot 2)
const QUAKE_WINDUP := 0.35      ## ergue a espada com as duas mãos (pulinho) e crava no chão aos 0,35 s
const QUAKE_RECOVER := 0.3
const QUAKE_TIME := QUAKE_WINDUP + QUAKE_RECOVER
const QUAKE_CUT_AT := 0.345     ## a lâmina começa a descer (medido: ver FXToon.QUAKE_CUT)
const QUAKE_TIP := 0.9          ## a lâmina crava a esta distância à frente dos pés (m)
const QUAKE_MULT := 2.0         ## dano = Game.melee_damage() * QUAKE_MULT
const QUAKE_RANGE := 6.0        ## alcance do cone (m)
const QUAKE_HALF_ANGLE := 35.0  ## meio ângulo do cone (graus): 70° no total
const QUAKE_STUN := 1.0         ## atordoamento (s)
const QUAKE_HOP := 3.3          ## impulso do pulinho: com a gravidade de 20 aterrissa em ~0,33 s
const QUAKE_WAVE_STEP := 0.08   ## a onda avança 1 m a cada 0,08 s
const QUAKE_ROCK := Color(0.24, 0.18, 0.13)

# ------------------------------------------------------------------ Turbilhão (ultimate, slot 4)
const WHIRL_WINDUP := 0.4       ## preparo: agacha com a espada para trás, brasas e luz crescendo
const WHIRL_SPIN := 1.5         ## giro: WHIRL_TURNS voltas
const WHIRL_FINALE := 0.2       ## golpe final para baixo
const WHIRL_TIME := WHIRL_WINDUP + WHIRL_SPIN + WHIRL_FINALE
const WHIRL_IMPACT := WHIRL_WINDUP + WHIRL_SPIN + 0.08   ## a espada bate no chão
const WHIRL_CUT_AT := 1.965     ## a lâmina começa a descer no golpe final (medido: ver FXToon.WHIRL_CUT)
const WHIRL_TIP := 0.9          ## a lâmina crava a esta distância à frente dos pés (m)
const WHIRL_TURNS := 4
const WHIRL_RAMP := 0.3         ## o giro acelera nos primeiros 0,3 s e depois mantém a velocidade
const WHIRL_MULT := 1.2         ## dano por volta = Game.melee_damage() * WHIRL_MULT
const WHIRL_RADIUS := 3.5
const WHIRL_PULL := 6.0         ## puxão (m/s) em direção ao jogador a cada volta (6 = teto do servidor)
const WHIRL_FINAL_MULT := 2.5   ## dano do golpe final
const WHIRL_FINAL_RADIUS := 4.0
const WHIRL_WALK := 0.4         ## anda a 40% da velocidade durante o giro
const WHIRL_CAM_BACK := 0.9     ## a câmera recua (m)
const WHIRL_FX_STEP := 0.25     ## poeira e marca de queimado a cada 0,25 s
const WHIRL_FLAME := Color(1.0, 0.36, 0.05)    ## chamas (saturado: o ACES desbota cores muito fortes)
const WHIRL_EMBER := Color(1.0, 0.55, 0.16)
const WHIRL_SCORCH := Color(0.07, 0.04, 0.02, 0.75)


## Executa a habilidade `id` para `player`. Devolve true só se ela começou.
static func use(player: Node, id: String) -> bool:
	match id:
		"sword_charge":
			player.begin_ability(id, {"dir": player.facing()})
			Network.send_event(id, player.global_position, player.facing())
			Sfx.play("sword_swing", 0.1, -6.0)
			return true
		"sword_quake":
			player.begin_ability(id, {"dir": player.facing(), "origin": player.global_position})
			Network.send_event(id, player.global_position, player.facing())
			Sfx.play("sword_swing_heavy", 0.1, -4.0)
			return true
		"sword_fury", "sword_fury_great":
			player.begin_ability(id, {})
			Game.add_buff(FURY_BUFF, Game.buff_duration(FURY_BUFF))
			Network.send_event(id, player.global_position, Vector3.ZERO)
			FX.ring(player.global_position + Vector3.UP * 0.1, BUFF_COLOR, 2.2, 0.4)
			Sfx.play("sword_swing_heavy", 0.1, -4.0)
			return true
		"sword_whirl":
			player.begin_ability(id, {"yaw0": player.model.rotation.y})
			Network.send_event(id, player.global_position, Vector3.ZERO)
			_whirl_start(player)
			Sfx.play("sword_swing", 0.1, -2.0)
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
		"sword_quake":
			_quake_tick(player, t0, player.ability_t, delta)
		"sword_fury", "sword_fury_great":
			if player.ability_t >= BUFF_TIME:
				player.end_ability()
		"sword_whirl":
			_whirl_tick(player, t0, player.ability_t, delta, move_dir, move_speed)
		_:
			player.end_ability()


## A tecla do slot da habilidade em execução foi solta (nenhuma habilidade da espada depende disso).
static func release(_player: Node) -> void:
	pass


## A esquiva pode interromper a habilidade agora?
static func can_dodge_cancel(player: Node) -> bool:
	# o Golpe Sísmico é curto demais: a esquiva não o cancela
	return player.ability == "sword_charge" and player.ability_t <= CHARGE_WINDUP


## A esquiva interrompeu a habilidade (can_dodge_cancel deu true).
static func dodge_cancel(player: Node) -> void:
	player.end_ability()


## Pose da habilidade por cima da locomoção (de _animate). O passo inteiro das pernas: move = 0.
static func pose(player: Node, p: Dictionary) -> void:
	match player.ability:
		"sword_charge":
			KnightAnim.play_track(p, KnightMoves.CHARGE, clampf(player.ability_t / CHARGE_TIME, 0.0, 1.0), 0.0)
		"sword_quake":
			KnightAnim.play_track(p, KnightMoves.QUAKE, clampf(player.ability_t / QUAKE_TIME, 0.0, 1.0), 0.0)
		"sword_fury", "sword_fury_great":
			KnightAnim.play_track(p, KnightMoves.BUFF, clampf(player.ability_t / BUFF_TIME, 0.0, 1.0), 0.0)
		"sword_whirl":
			KnightAnim.play_track(p, KnightMoves.WHIRL, clampf(player.ability_t / WHIRL_TIME, 0.0, 1.0), 0.0)
			# no giro os pés trocam de apoio acompanhando as voltas (não patinam parados)
			var s: float = player.ability_t - WHIRL_WINDUP
			if s > 0.0 and s < WHIRL_SPIN:
				var w := sin(_whirl_angle(s)) * smoothstep(0.0, WHIRL_RAMP, s)
				p.leg_l += 0.2 * w
				p.leg_r -= 0.2 * w
				p.knee_l += 0.15 * maxf(w, 0.0)
				p.knee_r += 0.15 * maxf(-w, 0.0)
				p.body_y -= 0.02 * absf(w)


## Réplica: começa a habilidade de outro jogador pelo evento de rede (só visual; dano já foi do dono).
static func play_remote(player: Node, kind: String, a: Vector3, b: Vector3) -> void:
	match kind:
		"sword_charge":
			player.begin_ability(kind, {"dir": b, "origin": a})
			Sfx.play_at("sword_swing", a, 0.1, -8.0)
		"sword_quake":
			player.begin_ability(kind, {"dir": b, "origin": a})
			Sfx.play_at("sword_swing_heavy", a, 0.1, -6.0)
		"sword_fury", "sword_fury_great":
			# a aura vem do buff no visual do dono (look.fx); aqui só a pose e o anel
			player.begin_ability(kind, {})
			FX.ring(a + Vector3.UP * 0.1, BUFF_COLOR, 2.2, 0.4)
			Sfx.play_at("sword_swing_heavy", a, 0.1, -6.0)
		"sword_whirl":
			player.begin_ability(kind, {"yaw0": player.model.rotation.y})
			_whirl_start(player)
			Sfx.play_at("sword_swing", a, 0.1, -4.0)


# ------------------------------------------------------------------ Investida
static func _charge_tick(player: Node, t0: float, t: float, delta: float) -> void:
	var d: Dictionary = player.ability_data
	var dir: Vector3 = d.dir
	var dash_end := CHARGE_WINDUP + CHARGE_DASH
	var local: bool = not player.remote
	# saída: poeira, a lança que acompanha a lâmina, e passa a atravessar inimigos (até end_ability)
	if t0 <= CHARGE_WINDUP and t > CHARGE_WINDUP:
		d.origin = player.global_position
		d.dashing = true
		FXToon.charge_kick(player.global_position, dir)
		d.lance = FXToon.charge_lance(player.global_position, dir, player.slash_color())
		Sfx.play_at("sword_swing", player.global_position, 0.05, -2.0)
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
			_lance_follow(player, d)
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
	# o corte de chegada é da pose, pelo relógio: sai igual se o avanço parou antes numa parede
	if t0 < CHARGE_CUT_AT and t >= CHARGE_CUT_AT:
		FXToon.charge_cut(player, dir, player.slash_color())
		Sfx.play_at("sword_swing", player.global_position, 0.05, -4.0)
	if t >= CHARGE_TIME - 0.0001:
		player.end_ability()


static func _charge_arrive(player: Node, d: Dictionary) -> void:
	d.dashing = false
	var dir: Vector3 = d.dir
	if not player.remote:
		_charge_hits(player, d)
		player.velocity.x = dir.x * 2.5
		player.velocity.z = dir.z * 2.5
	_lance_follow(player, d)
	var lance = d.get("lance")
	if is_instance_valid(lance):
		lance.finish()
	FXToon.charge_arrive(player.global_position, dir)


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
		Sfx.play("sword_hit_flesh", 0.1)
		player.add_shake(0.18)
		if first:
			FXEpic.flash(player.global_position + Vector3.UP * 1.0 + d.dir * 0.8, Color(1.0, 0.8, 0.5), 1.6, 4.0, 0.15)


## A lança desenhada vai até a ponta da lâmina, pela altura e pelo lado dela (FXToon.charge_lance).
static func _lance_follow(player: Node, d: Dictionary) -> void:
	var lance = d.get("lance")
	if not is_instance_valid(lance):
		return
	var tip = player.look.get("tip")
	var holder = player.look.get("holder")
	if is_instance_valid(tip) and is_instance_valid(holder):
		var at: Vector3 = (tip as Node3D).global_position
		lance.reach(at, (at + (holder as Node3D).global_position) * 0.5)
	else:
		var chest: Vector3 = player.global_position + Vector3.UP
		lance.reach(chest + d.dir, chest)


# ------------------------------------------------------------------ Golpe Sísmico
static func _quake_tick(player: Node, t0: float, t: float, delta: float) -> void:
	var d: Dictionary = player.ability_data
	var local: bool = not player.remote
	if local:
		# o pulinho do preparo (a física já aplica a gravidade); parado no chão
		if t0 <= 0.0 and player.is_on_floor():
			player.velocity.y = QUAKE_HOP
		player.velocity.x = move_toward(player.velocity.x, 0.0, 40.0 * delta)
		player.velocity.z = move_toward(player.velocity.z, 0.0, 40.0 * delta)
	if t0 < QUAKE_CUT_AT and t >= QUAKE_CUT_AT:
		FXToon.quake_cut(player, d.dir, player.slash_color())
	if t0 < QUAKE_WINDUP and t >= QUAKE_WINDUP:
		_quake_impact(player, d)
	if d.get("impact", false):
		_quake_wave(player, d, t - QUAKE_WINDUP)
	if t >= QUAKE_TIME - 0.0001:
		player.end_ability()


## A espada crava no chão: marca, choque e o dano do cone (só no dono).
static func _quake_impact(player: Node, d: Dictionary) -> void:
	var dir: Vector3 = d.dir
	var base: Vector3 = player.global_position
	d.impact = true
	d.base = base
	d.wave_m = 0
	var tip := base + dir * QUAKE_TIP
	FXToon.quake_impact(base, dir, tip, QUAKE_RANGE, QUAKE_HALF_ANGLE, QUAKE_WAVE_STEP)
	Sfx.play_at("slam", base, 0.05, -2.0)
	if player.remote:
		return
	player.add_shake(0.3)
	var half := deg_to_rad(QUAKE_HALF_ANGLE)
	var any := false
	for e in player.get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var to: Vector3 = e.global_position - base
		to.y = 0.0
		var dist := to.length()
		if dist - e.radius > QUAKE_RANGE:
			continue
		# dentro do cone; quem está colado nos pés também conta
		if dist > e.radius and dir.angle_to(to) > half + asin(clampf(e.radius / dist, 0.0, 1.0)):
			continue
		var dmg: float = Game.melee_damage() * QUAKE_MULT
		# atordoa (stagger + interrompe o golpe); em puppet o servidor aplica (Network._hit_enemy)
		e.take_damage(dmg, base, false, 0.0, QUAKE_STUN)
		Game.on_damage_dealt(dmg, e.max_hp)
		any = true
		FXEpic.sparks(e.global_position + Vector3.UP * 0.4, Vector3.UP, QUAKE_ROCK.lightened(0.3), 10, 6.0, 0.35)
	if any:
		Sfx.play("sword_hit_flesh", 0.1)
		FXEpic.flash(tip + Vector3.UP * 0.6, Color(1.0, 0.8, 0.5), 1.6, 4.0, 0.15)
		FXEpic.hit_stop(0.05)


## Onda no chão: avança QUAKE_WAVE_STEP s por metro, levantando estilhaços de pedra e poeira dentro do cone.
static func _quake_wave(_player: Node, d: Dictionary, since: float) -> void:
	var reach: int = mini(int(since / QUAKE_WAVE_STEP), int(QUAKE_RANGE))
	while d.wave_m < reach:
		d.wave_m += 1
		FXToon.quake_wave(d.base, d.dir, d.wave_m, QUAKE_HALF_ANGLE)


# ------------------------------------------------------------------ Turbilhão
## Cor sRGB do código para os efeitos de FXEpic que leem a cor como linear (glow_burst, sparks):
## sem isto o laranja do fogo desbota para creme à luz do dia.
static func _lin(c: Color) -> Color:
	var l := c.srgb_to_linear()
	l.a = c.a
	return l


## Ângulo do giro (rad) `s` segundos depois do preparo: acelera por WHIRL_RAMP e mantém, fechando
## exatamente WHIRL_TURNS voltas no fim do giro (o modelo termina olhando para onde começou).
static func _whirl_angle(s: float) -> float:
	var w := WHIRL_TURNS * TAU / (WHIRL_SPIN - WHIRL_RAMP * 0.5)
	if s <= 0.0:
		return 0.0
	if s >= WHIRL_SPIN:
		return WHIRL_TURNS * TAU
	if s < WHIRL_RAMP:
		return 0.5 * w / WHIRL_RAMP * s * s
	return w * (s - WHIRL_RAMP * 0.5)


## Começo (dono e réplicas): luz laranja presa ao jogador, brasas subindo em volta e a lâmina pegando
## fogo. Os nós vão em "nodes" (end_ability os libera se a habilidade for interrompida).
static func _whirl_start(player: Node) -> void:
	var d: Dictionary = player.ability_data
	var nodes: Array = d.get_or_add("nodes", [])
	if FX._scene() == null:
		return   # servidor dedicado: sem efeitos
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.18)
	light.light_energy = 0.0
	light.omni_range = 7.0
	light.shadow_enabled = false
	light.position = Vector3(0, 1.0, 0)
	player.add_child(light)
	nodes.append(light)
	d.light = light
	# brasas subindo em espiral ao redor (tangential_accel gira em volta do jogador)
	var embers := FXEpic.stream(player, "glow", WHIRL_EMBER, 40, 0.9, 0.06)
	if embers:
		embers.position = Vector3(0, 0.15, 0)
		embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		embers.emission_ring_axis = Vector3.UP
		embers.emission_ring_radius = 1.6
		embers.emission_ring_inner_radius = 0.5
		embers.emission_ring_height = 0.1
		embers.direction = Vector3.UP
		embers.spread = 25.0
		embers.initial_velocity_min = 1.2
		embers.initial_velocity_max = 3.2
		embers.gravity = Vector3(0, 1.5, 0)
		embers.tangential_accel_min = 3.0
		embers.tangential_accel_max = 6.0
		embers.scale_amount_min = 0.6
		embers.scale_amount_max = 1.4
		nodes.append(embers)
		d.embers = embers
	FXEpic.glow_burst(player.global_position + Vector3.UP * 0.3, _lin(WHIRL_EMBER), 16, 2.5, 0.07, 0.8, 3.0)
	_whirl_ignite(player, d)


static func _whirl_tick(player: Node, t0: float, t: float, delta: float, move_dir: Vector3, move_speed: float) -> void:
	var d: Dictionary = player.ability_data
	var local: bool = not player.remote
	var spin_end := WHIRL_WINDUP + WHIRL_SPIN
	# o giro do modelo (na réplica também: durante o giro o yaw da rede é ignorado)
	player.model.rotation.y = wrapf(float(d.yaw0) + _whirl_angle(t - WHIRL_WINDUP), -PI, PI)
	if local:
		# anda devagar seguindo o input só no giro; parado no preparo e no golpe final
		var target := Vector3.ZERO
		if t > WHIRL_WINDUP and t < spin_end:
			target = move_dir * move_speed * WHIRL_WALK
		var hv := Vector3(player.velocity.x, 0.0, player.velocity.z).lerp(target, 1.0 - exp(-10.0 * delta))
		player.velocity.x = hv.x
		player.velocity.z = hv.z
		player.cam_back = WHIRL_CAM_BACK
	_whirl_light(d, t)
	if t0 <= WHIRL_WINDUP and t > WHIRL_WINDUP:
		_whirl_spin_start(player, d)
	if t > WHIRL_WINDUP:
		var turns := mini(int(_whirl_angle(t - WHIRL_WINDUP) / TAU + 0.0001), WHIRL_TURNS)
		while int(d.get("turns", 0)) < turns:
			d.turns = int(d.get("turns", 0)) + 1
			_whirl_turn(player, d)
	if t > WHIRL_WINDUP and t0 < spin_end:
		# poeira em anel no chão e o queimado se arrastando atrás do jogador
		var steps := int((minf(t, spin_end) - WHIRL_WINDUP) / WHIRL_FX_STEP)
		while int(d.get("fx_steps", 0)) < steps:
			d.fx_steps = int(d.get("fx_steps", 0)) + 1
			_whirl_ground(player, d)
	if t0 < spin_end and t >= spin_end:
		_stop_stream(d, "blade_embers")
	if t0 < WHIRL_CUT_AT and t >= WHIRL_CUT_AT:
		FXToon.whirl_cut(player, Vector3(sin(float(d.yaw0)), 0.0, cos(float(d.yaw0))))
	if t0 < WHIRL_IMPACT and t >= WHIRL_IMPACT:
		_whirl_finale(player, d)
	if t >= WHIRL_TIME - 0.0001:
		player.model.rotation.y = float(d.yaw0)
		_stop_stream(d, "embers")
		_stop_stream(d, "blade_embers")
		player.end_ability()


## Luz laranja: cresce no preparo, pulsa no giro, estoura no golpe final e apaga.
static func _whirl_light(d: Dictionary, t: float) -> void:
	var light = d.get("light")
	if not is_instance_valid(light):
		return
	var e := 0.0
	if t < WHIRL_WINDUP:
		e = 3.0 * pow(t / WHIRL_WINDUP, 2.0)
	elif t < WHIRL_IMPACT:
		e = 2.4 + 0.8 * sin((t - WHIRL_WINDUP) * 24.0)
	else:
		e = 5.0 * clampf(1.0 - (t - WHIRL_IMPACT) / (WHIRL_TIME - WHIRL_IMPACT), 0.0, 1.0)
	light.light_energy = e


## Para um emissor de stream() guardado em d[key] deixando as partículas vivas terminarem.
static func _stop_stream(d: Dictionary, key: String) -> void:
	var p = d.get(key)
	if not is_instance_valid(p):
		return
	d.erase(key)
	d.get("nodes", []).erase(p)
	FXEpic.stop_stream(p)


## Começo do giro: o redemoinho desenhado, que roda com a lâmina (FXToon.whirl_spin).
static func _whirl_spin_start(player: Node, d: Dictionary) -> void:
	Sfx.play_at("sword_swing_heavy", player.global_position, 0.1, -2.0)
	_whirl_ground(player, d)
	var tip = player.look.get("tip")
	if is_instance_valid(tip):
		var spin := FXToon.whirl_spin(player, tip, WHIRL_SPIN)
		if spin:
			d.nodes.append(spin)


## A lâmina pega fogo (desde o preparo): chamas saindo dela; o emissor gira com a espada e deixa
## uma espiral de fogo no ar.
static func _whirl_ignite(player: Node, d: Dictionary) -> void:
	var holder = player.look.get("holder")
	var tip = player.look.get("tip")
	if FX._scene() == null or not is_instance_valid(holder) or not is_instance_valid(tip):
		return
	var tip_pos: Vector3 = tip.position
	var be := FXEpic.stream(holder, "glow", WHIRL_FLAME, 70, 0.4, 0.16)
	if be:
		be.position = tip_pos * 0.7
		be.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		be.emission_sphere_radius = tip_pos.length() * 0.3
		be.direction = Vector3.UP
		be.spread = 180.0
		be.initial_velocity_min = 0.3
		be.initial_velocity_max = 1.2
		be.gravity = Vector3(0, 3.0, 0)
		be.scale_amount_min = 0.5
		be.scale_amount_max = 1.4
		d.nodes.append(be)
		d.blade_embers = be


## A cada WHIRL_FX_STEP no giro: se o jogador andou, mais queimado no chão.
static func _whirl_ground(player: Node, d: Dictionary) -> void:
	var pos: Vector3 = player.global_position
	var last = d.get("scorch_at")
	if last == null or pos.distance_to(last) > 0.6:
		d.scorch_at = pos
		FXEpic.ground_mark(pos, WHIRL_SCORCH, 2.0, 2.5, "scorch")


## Uma volta completa: fere e puxa quem está no raio (só o dono); faíscas nos acertos (todos veem).
static func _whirl_turn(player: Node, d: Dictionary) -> void:
	var base: Vector3 = player.global_position
	Sfx.play_at("sword_swing", base, 0.15, -5.0)
	var local: bool = not player.remote
	var any := false
	var n := 0
	for e in player.get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var to: Vector3 = e.global_position - base
		to.y = 0.0
		if to.length() > WHIRL_RADIUS + e.radius or absf(e.global_position.y - base.y) > 3.0:
			continue
		if local:
			var dmg: float = Game.melee_damage() * WHIRL_MULT * Game.ability_dmg_mult("sword_whirl")
			e.take_damage(dmg, base, false, 0.0, 0.0, WHIRL_PULL)
			Game.on_damage_dealt(dmg, e.max_hp, false)   # a ultimate não recarrega a própria fúria
		any = true
		if n < 8:   # faíscas para onde a lâmina corre (tangente ao giro)
			var along := Vector3.UP.cross(to).normalized() if to.length() > 0.01 else Vector3.UP
			FXEpic.sparks(e.global_position + Vector3.UP * 0.6, along + Vector3.UP * 0.35, _lin(WHIRL_EMBER), 10, 8.0, 0.3)
		n += 1
	if any:
		Sfx.play_at("sword_hit_flesh", base, 0.1)
		if local:
			player.add_shake(0.15)
			FXEpic.hit_stop(0.03)


## Golpe final: a espada desce no chão à frente; explosão de fogo, onda e dano maior (empurra).
static func _whirl_finale(player: Node, d: Dictionary) -> void:
	var base: Vector3 = player.global_position
	var yaw: float = d.yaw0
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	FXToon.whirl_finale(base, fwd, base + fwd * WHIRL_TIP, WHIRL_FINAL_RADIUS)
	FXEpic.ground_mark(base, WHIRL_SCORCH, 3.2, 3.5, "scorch")
	Sfx.play_at("slam", base, 0.05, 0.0)
	if player.remote:
		return
	player.add_shake(0.4)
	FXEpic.hit_stop(0.08)
	var any := false
	for e in player.get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var to: Vector3 = e.global_position - base
		to.y = 0.0
		if to.length() > WHIRL_FINAL_RADIUS + e.radius or absf(e.global_position.y - base.y) > 3.0:
			continue
		var dmg: float = Game.melee_damage() * WHIRL_FINAL_MULT * Game.ability_dmg_mult("sword_whirl")
		e.take_damage(dmg, base, false)
		Game.on_damage_dealt(dmg, e.max_hp, false)
		any = true
	if any:
		Sfx.play("sword_hit_flesh", 0.1)
