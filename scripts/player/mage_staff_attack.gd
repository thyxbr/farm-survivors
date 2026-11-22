class_name MageStaffAttack
extends RefCounted
## Ataque básico do cajado (Mago, botão esquerdo): Bola de Fogo. Estático: o estado vive no Player
## (attacking, combo, attack_timer, fireball_orb), como nos módulos de habilidade.
##
## - Clique rápido (soltou antes de TAP_TIME): bola de tamanho normal, dano num alvo só.
## - Segurar: a bola nasce na gema do cajado e cresce até MAX_SCALE em CHARGE_TIME, com fagulhas correndo para
##   ela. Soltar (ou passar FULL_HOLD com a carga cheia) dispara a bola carregada: rastro mais largo e explosão
##   em área no impacto, com empurrão e tremor de câmera. Dano, raio e fôlego crescem com a carga.
##
## Rede: `combo` diz a fase (CHARGE / RECOVER) e `attack_timer` o tempo nela, pelo estado de sempre
## (Player._net_send). A réplica desenha a bola crescendo pela mesma conta (tick_orb) e o disparo chega pelo
## evento "staff_fireball" (a = origem, b = direção com o comprimento codificando a carga, ver encode/decode).
## O cetro mantém o ataque próprio (Player._scepter_shot).

const SCENE := preload("res://scenes/vfx/fireball/fireball_projectile.tscn")

const CHARGE := 1             ## combo durante a carga (botão segurado)
const RECOVER := 2            ## combo depois do disparo (cajado volta)
const TAP_TIME := 0.2         ## soltar antes disto = clique (bola normal)
const CHARGE_TIME := 1.1      ## s da bola normal até a cheia
const FULL_HOLD := 0.35       ## cheia, segura isto e dispara sozinha
const RECOVER_TIME := 0.32    ## s de volta do cajado depois do disparo
const RAISE_TIME := 0.18      ## s para erguer e inclinar o cajado
const MAX_SCALE := 2.5        ## tamanho da bola cheia (1 = clique)
const SPEED := 24.0           ## m/s do clique
const CHARGED_SPEED := 20.0   ## m/s da carregada
const RANGE := 30.0           ## m de alcance
const TAP_MULT := 1.0         ## dano do clique (× dano base da arma)
const CHARGED_MULT_MIN := 1.4 ## dano da carregada logo depois do clique
const CHARGED_MULT_MAX := 3.2 ## e cheia
const AOE_MIN := 1.8          ## raio da explosão (m) logo depois do clique
const AOE_MAX := 3.4          ## e cheia
const KNOCKBACK := 5.0        ## m/s do empurrão da explosão
const STAMINA := 2.5          ## fôlego do clique
const STAMINA_CHARGED := 6.0  ## a mais com a carga cheia
const ORB_AHEAD := 0.28       ## a bola fica este tanto (m × tamanho) à frente da gema: a gema encosta atrás dela


## O ataque básico desta arma é a Bola de Fogo? (cajado sim; o cetro tem o seu)
static func active(player: Node) -> bool:
	return player.look["class"] == "staff" and not player._is_scepter()


## Carga 0..1 depois de `t` s segurando (0 até passar do clique).
static func charge_of(t: float) -> float:
	return clampf((t - TAP_TIME) / CHARGE_TIME, 0.0, 1.0)


## Tamanho da bola na carga: nasce pequena, chega a 1 no fim do clique e cresce até MAX_SCALE.
static func orb_scale(t: float) -> float:
	return lerpf(0.45, 1.0, smoothstep(0.0, TAP_TIME, t)) * lerpf(1.0, MAX_SCALE, charge_of(t))


## Duração de cada fase (Player._swing_time; a réplica limita o relógio a isto).
static func phase_time(combo: int) -> float:
	return TAP_TIME + CHARGE_TIME + FULL_HOLD if combo == CHARGE else RECOVER_TIME


## Evento de rede: direção × (1 no clique; 2 + carga na carregada).
static func encode(dir: Vector3, charged: bool, c: float) -> Vector3:
	return dir.normalized() * ((2.0 + c) if charged else 1.0)


## [direção, carregada, carga] do evento.
static func decode(b: Vector3) -> Array:
	var l := b.length()
	return [b / maxf(l, 0.0001), l >= 1.5, clampf(l - 2.0, 0.0, 1.0)]


# ---------------------------------------------------------------- jogador local
## Botão desceu (Player._start_swing): ergue o cajado e começa a carga.
static func begin(player: Node) -> void:
	player.attacking = true
	player.combo = CHARGE
	player.attack_timer = 0.0
	player.hit_done = false
	player.buffered_attack = false
	Sfx.play("staff_wind", 0.15, -8.0)


## Um passo do ataque (Player._update_attack). Carga: dispara ao soltar o botão ou ao estourar o tempo.
static func update(player: Node, delta: float, held: bool) -> void:
	player.attack_timer += delta
	if player.combo == CHARGE:
		if not held or player.attack_timer >= phase_time(CHARGE):
			release(player)
		return
	if player.attack_timer >= RECOVER_TIME:
		player.attacking = false
		player.combo_window = 0.0
		if player.buffered_attack:
			player.buffered_attack = false
			player._start_swing()


## Para a carga sem disparar (menu, chat, tela de carregamento).
static func cancel(player: Node) -> void:
	if player.attacking and player.combo == CHARGE:
		player.attacking = false
	tick_orb(player)


## Dispara a bola que está na gema (ou uma nova, se ainda não nasceu).
static func release(player: Node) -> void:
	var t: float = player.attack_timer
	var charged := t >= TAP_TIME
	var c := charge_of(t)
	var origin: Vector3 = player.weapon_tip()
	var dir: Vector3 = player.aim_dir(origin)
	var fb: FireballProjectile = player.fireball_orb
	player.fireball_orb = null
	if fb == null or not is_instance_valid(fb) or fb._state != FireballProjectile.CHARGING:
		fb = _new_orb(player, false)
	fb.global_position = origin + dir * ORB_AHEAD * fb.size
	var crit: bool = randf() < Game.crit_chance()
	fb.crit = crit
	fb.is_charged = charged
	fb.size = orb_scale(t) if charged else 1.0
	fb.damage = Game.melee_damage() * (lerpf(CHARGED_MULT_MIN, CHARGED_MULT_MAX, c) if charged else TAP_MULT) * (1.8 if crit else 1.0)
	fb.aoe_radius = lerpf(AOE_MIN, AOE_MAX, c)
	fb.knockback = KNOCKBACK
	fb.speed = CHARGED_SPEED if charged else SPEED
	fb.life = RANGE / fb.speed
	fb.slow = 2.5 if player._weapon_fx() == "slow" else 0.0
	fb.launch(dir)
	Network.send_event("staff_fireball", fb.global_position, encode(dir, charged, c))
	Game.stamina = maxf(0.0, Game.stamina - STAMINA - (STAMINA_CHARGED * c if charged else 0.0))
	player.stamina_delay = 0.4
	Sfx.play("fire_cast", 0.12, -4.0 if charged else -6.0)
	if charged:
		player.add_shake(0.05 + 0.1 * c)   # coice do disparo pesado
	player.combo = RECOVER
	player.attack_timer = 0.0


# ---------------------------------------------------------------- local e réplica
## Bola da carga na gema: existe enquanto o jogador está na fase CHARGE (de _animate, local e réplica).
static func tick_orb(player: Node) -> void:
	var want: bool = player.attacking and player.combo == CHARGE and not player.dead and active(player)
	var fb: FireballProjectile = player.fireball_orb
	if fb != null and not is_instance_valid(fb):
		fb = null
		player.fireball_orb = null
	if not want:
		if fb:
			fb.cancel()
			player.fireball_orb = null
		return
	if fb == null:
		fb = _new_orb(player, player.remote)
		player.fireball_orb = fb
	var t: float = player.attack_timer
	fb.set_charge(t, orb_scale(t), charge_of(t))
	fb.global_position = player.weapon_tip() + player.facing() * ORB_AHEAD * fb.size


static func _new_orb(player: Node, visual: bool) -> FireballProjectile:
	var fb: FireballProjectile = SCENE.instantiate()
	fb.visual_only = visual
	fb.shooter = player
	player.get_tree().current_scene.add_child(fb)
	fb.global_position = player.weapon_tip()
	return fb


## Pose: na carga ergue o cajado e tomba um pouco a gema para a frente (sobe mais com a carga); depois do
## disparo, o coice e a volta.
static func pose(player: Node, p: Dictionary, move: float) -> void:
	var t: float = player.attack_timer
	if player.combo == CHARGE:
		KnightAnim.play_track(p, KnightMoves.STAFF_FB_RAISE, clampf(t / RAISE_TIME, 0.0, 1.0), move)
		var c := charge_of(t)
		if c > 0.0:
			KnightAnim.play_track(p, KnightMoves.STAFF_FB_CHARGE, c, move)
	else:
		KnightAnim.play_track(p, KnightMoves.STAFF_FB_RELEASE, clampf(t / RECOVER_TIME, 0.0, 1.0), move)


## Réplica: a bola de outro jogador saiu (só o visual; o dano é do dono).
static func play_remote(player: Node, a: Vector3, b: Vector3) -> void:
	var d := decode(b)
	if player.fireball_orb and is_instance_valid(player.fireball_orb):
		player.fireball_orb.queue_free()
	player.fireball_orb = null
	var fb := _new_orb(player, true)
	fb.global_position = a
	fb.is_charged = d[1]
	fb.size = lerpf(1.0, MAX_SCALE, d[2]) if d[1] else 1.0
	fb.aoe_radius = lerpf(AOE_MIN, AOE_MAX, d[2])
	fb.speed = CHARGED_SPEED if d[1] else SPEED
	fb.life = RANGE / fb.speed
	fb.launch(d[0])
	Sfx.play_at("fire_cast", a, 0.12, -8.0)
