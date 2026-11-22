class_name SeismicSpikesAbilities
extends RefCounted
## Estacas Sísmicas: habilidade 3 da montante (ItemDB "sword_spikes", "offhand": "two_handed": com a montante nas mãos
## ela troca a Fúria Picante na tecla 3, e a Fúria vai para a tecla 5). Em duas fases:
##   1. Impacto e rachaduras: o herói vira a montante com a ponta para baixo, ergue e a crava no chão à frente. O chão
##      racha do centro até o raio (4,5 m), com a sprite sheet 8x8 de terra rachando e fissuras projetadas (Decal).
##   2. Terremoto e dano: depois de um intervalo a terra treme (chão sacudindo, pedrinhas pulando, poeira, ronco e a
##      câmera tremendo); o tremor corre do centro até a borda e cada inimigo na área leva o golpe quando ele chega
##      (uma vez por ativação). O herói segura a espada cravada, sacudindo junto.
##   3. Finalização: o herói arranca a espada, o tremor para e o visual some suavemente e se libera.
## Peças: SeismicSpikesAoE (o visual, cena própria na cena do mundo), SeismicSpikesDamage (o dano, só no dono),
## SeismicSpikesRules (contas puras) e SeismicSpikesConfig (assets/vfx/seismic_spikes/seismic_spikes_config.tres, no
## Inspector: tempos, raio, dano, recarga e o visual).
## Movimento: parado do começo ao fim. A esquiva só cancela antes da espada tocar o chão (sem rachar nem ferir).
## Rede: o dono manda "sword_spikes" (a = posição, b = (yaw, semente)): as réplicas tocam a mesma animação e o mesmo
## visual, sem dano. Cancelado antes do impacto: "sword_spikes_cancel".

const ID := "sword_spikes"
const CANCEL_EVENT := "sword_spikes_cancel"
const SKILL := preload("res://scenes/vfx/seismic_spikes/seismic_spikes_aoe.tscn")
const CONFIG := preload("res://assets/vfx/seismic_spikes/seismic_spikes_config.tres")
const HIT_SFX_GAP_MS := 60

## Mão direita (junto da guarda) no alto, com a ponta já virada para baixo (espaço do modelo: +Z = frente, +X =
## esquerda do herói, Y = altura a partir dos pés).
const RAISE_HAND := Vector3(0.0, 1.5, 0.36)
## Mão direita depois de arrancar a espada: alta e à frente, a ponta saindo do chão.
const PULL_HAND := Vector3(0.0, 1.42, 0.55)
## A mão fica este tanto atrás da ponta cravada (a lâmina inclina um pouco para a frente).
const PLANT_BACK := 0.2
## O gume aponta para a esquerda do herói: de costas a câmera vê a largura da lâmina.
const EDGE := Vector3(1.0, 0.0, 0.0)
## Cotovelo direito para fora e para trás (as duas mãos juntas na frente do corpo).
const POLE := Vector3(-1.0, -0.3, -0.4)
const POLE_W := 1.0
## Corpo em cada pose-chave (por cima da locomoção): erguido, cravado (agachado, inclinado sobre a espada) e puxando.
const BODY_RAISE := {"body_x": -0.1, "body_y": 0.02, "twist": 0.0, "head_x": -0.08, "head_y": 0.0,
	"leg_l": -0.3, "knee_l": 0.25, "leg_r": 0.26, "knee_r": 0.2}
const BODY_PLANT := {"body_x": 0.4, "body_y": -0.24, "twist": 0.0, "head_x": 0.12, "head_y": 0.0,
	"leg_l": -0.95, "knee_l": 1.35, "leg_r": 0.5, "knee_r": 0.95}
const BODY_PULL := {"body_x": -0.12, "body_y": 0.0, "twist": 0.0, "head_x": -0.05, "head_y": 0.0,
	"leg_l": -0.35, "knee_l": 0.3, "leg_r": 0.3, "knee_r": 0.22}
const BODY_JOINTS := ["body_x", "body_y", "twist", "head_x", "head_y", "leg_l", "knee_l", "leg_r", "knee_r"]

static var _last_hit_sfx := -1000


static func use(player: Node, id: String) -> bool:
	if id != ID:
		return false
	var f: Vector3 = player.facing()
	var yaw := atan2(f.x, f.z)
	var seed_v := randi() % 65536
	_begin(player, yaw, seed_v, player.global_position)
	Network.send_event(ID, player.global_position, Vector3(yaw, float(seed_v), 0.0))
	Sfx.play("sword_swing_heavy", 0.06, -6.0)
	return true


## Onde a ponta da espada crava: à frente dos pés do herói (o centro da área).
static func impact_point(pos: Vector3, yaw: float) -> Vector3:
	return pos + Vector3(sin(yaw), 0.0, cos(yaw)) * CONFIG.forward_offset


static func _begin(player: Node, yaw: float, seed_v: int, pos: Vector3) -> void:
	var skill: SeismicSpikesAoE = null
	var root := FX._scene()
	if root != null:   # servidor dedicado: sem visual (o dano é do cliente dono)
		skill = SKILL.instantiate()
		skill.config = CONFIG
		skill.seed_value = seed_v
		skill.position = impact_point(pos, yaw)   # a cena do mundo fica na origem: local = global
		root.add_child(skill)
		if not player.remote:
			skill.impacted.connect(_on_impacted.bind(weakref(player)))
			skill.quake_started.connect(_on_quake_started)
	var d := {"skill": skill, "yaw": yaw, "from": KnightAnim.capture_pose(player.parts), "blade_len": _blade_length(player)}
	player.begin_ability(ID, d)
	d["on_end"] = _on_end.bind(player, d)


## Comprimento da lâmina da mão direita até a ponta, no espaço do modelo (muda com a montante e com o corpo).
static func _blade_length(player: Node) -> float:
	var lk: Dictionary = player.look
	var h = lk.get("holder")
	var tp = lk.get("tip")
	if h is Node3D and tp is Node3D and is_instance_valid(h) and is_instance_valid(tp) and (h as Node3D).is_inside_tree():
		var m: Node3D = player.model
		var l := (m.to_local((tp as Node3D).global_position) - m.to_local((h as Node3D).global_position)).length()
		if l > 0.3:
			return l
	return 1.3


static func tick(player: Node, delta: float, _move_dir := Vector3.ZERO, _move_speed := 0.0) -> void:
	player.ability_t += delta
	var d: Dictionary = player.ability_data
	# virado para onde a espada crava (na réplica também: o yaw da rede só volta depois)
	player.model.rotation.y = lerp_angle(player.model.rotation.y, float(d.get("yaw", 0.0)), 1.0 - exp(-14.0 * delta))
	if not player.remote:
		# parado do começo ao fim: a tecla de andar não move
		player.velocity.x = move_toward(player.velocity.x, 0.0, 40.0 * delta)
		player.velocity.z = move_toward(player.velocity.z, 0.0, 40.0 * delta)
		player.cam_back = CONFIG.camera_back
	if player.ability_t >= CONFIG.total_time():
		player.end_ability()


static func release(_player: Node) -> void:
	pass


## Até a espada tocar o chão a esquiva cancela.
static func can_dodge_cancel(player: Node) -> bool:
	if player.ability != ID:
		return false
	# o visual roda em _process e o relógio da habilidade em _physics_process: quem cravou primeiro manda
	var skill = player.ability_data.get("skill")
	if is_instance_valid(skill) and not skill.can_cancel():
		return false
	return player.ability_t < CONFIG.impact_time()


static func dodge_cancel(player: Node) -> void:
	player.end_ability()


## A pose por cima da locomoção (o player.gd já tirou a arma de carregar: "tool" é desta habilidade).
static func pose(player: Node, p: Dictionary) -> void:
	var d: Dictionary = player.ability_data
	var cfg: SeismicSpikesConfig = CONFIG
	var ph := SeismicSpikesRules.phase_at(float(player.ability_t), cfg.pose_durations())
	var phase := int(ph.x)
	var u := ph.y
	var length := float(d.get("blade_len", 1.3))
	var tip := Vector3(0.0, -cfg.plunge_depth, cfg.forward_offset)
	var plant := SeismicSpikesRules.hand_over_tip(tip, length, cfg.forward_offset - PLANT_BACK)
	var k_raise := _blade(RAISE_HAND, (tip - RAISE_HAND).normalized())
	var k_plant := _blade(plant, (tip - plant).normalized())
	var k_pull := _blade(PULL_HAND, (tip - plant).normalized())
	var tl: Dictionary
	var body_a := {}
	var body_b := {}
	var k := 0.0
	match phase:
		SeismicSpikesRules.WINDUP:
			# a lâmina gira para a frente e para baixo pelo caminho curto (a ponta passa pela frente, não por cima)
			var from: Dictionary = d.get("from", {}).get("tool", KnightMoves.GREAT_GUARD)
			k = smoothstep(0.0, 1.0, u)
			tl = _mix(from, k_raise, k)
			body_b = BODY_RAISE
		SeismicSpikesRules.PLUNGE:
			k = u * u   # acelera até cravar
			tl = _mix(k_raise, k_plant, k)
			body_a = BODY_RAISE
			body_b = BODY_PLANT
		SeismicSpikesRules.HOLD:
			tl = k_plant
			body_a = BODY_PLANT
			body_b = BODY_PLANT
			k = 1.0
		SeismicSpikesRules.PULL:
			k = smoothstep(0.0, 1.0, u)
			tl = _mix(k_plant, k_pull, k)
			body_a = BODY_PLANT
			body_b = BODY_PULL
		_:
			# a volta à guarda: a arma vai para a de carregar e o corpo devolve a pose à locomoção
			var cp := p.duplicate(true)
			KnightAnim.great_carry(cp, float(player.get("_amp")), float(player.get("_run")))
			k = smoothstep(0.0, 1.0, u)
			tl = _mix(k_pull, cp.tool, k)
			body_a = BODY_PULL
	p["tool"] = tl
	for j in BODY_JOINTS:
		var a := float(body_a.get(j, p.get(j, 0.0)))
		var b := float(body_b.get(j, p.get(j, 0.0)))
		p[j] = lerpf(a, b, k)
	var snap: Array = p.snap
	for j in ["arm_l", "arm_r", "elbow_l", "elbow_r"]:
		snap.append(j)   # os braços saem do IK da trajetória, que já é suave
	# a terra tremendo: o herói sacode junto, agarrado na espada cravada (sem suavizar, senão o tremor some)
	var t_ab := float(player.ability_t)
	var quake := 0.0
	if t_ab >= cfg.quake_time() and t_ab < cfg.pull_end():
		quake = smoothstep(cfg.quake_time(), cfg.quake_time() + 0.25, t_ab) \
			* (1.0 - smoothstep(cfg.pull_start(), cfg.pull_end(), t_ab))
	var wob := SeismicSpikesRules.quake_wobble(t_ab, quake)
	p.body_x = float(p.body_x) + wob.x
	p.twist = float(p.twist) + wob.y
	if phase == SeismicSpikesRules.PLUNGE or (phase == SeismicSpikesRules.HOLD and u < 0.1) or quake > 0.0:
		for j in BODY_JOINTS:
			if not (j in snap):
				snap.append(j)   # a descida (e o tremor) são rápidos demais para a suavização


## A arma (trajetória do tool) com a mão direita em `hand` e a lâmina na direção `dir`.
static func _blade(hand: Vector3, dir: Vector3) -> Dictionary:
	var e := EDGE - dir * EDGE.dot(dir)
	return {"end": hand - dir * KnightMoves.GREAT_GRIP, "dir": dir, "edge": e.normalized(), "slide": 0.0, "left": 1.0,
		"w": 1.0, "grip": KnightMoves.GREAT_GRIP, "pole_r": POLE, "pole_w": POLE_W}


static func _mix(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var m := KnightAnim.great_mix(a, b, k)
	m["w"] = 1.0
	m["grip"] = KnightMoves.GREAT_GRIP
	m["pole_r"] = (a.get("pole_r", POLE) as Vector3).lerp(b.get("pole_r", POLE), k).normalized()
	m["pole_w"] = lerpf(float(a.get("pole_w", POLE_W)), float(b.get("pole_w", POLE_W)), k)
	return m


static func play_remote(player: Node, kind: String, a: Vector3, b: Vector3) -> void:
	match kind:
		ID:
			_begin(player, b.x, int(b.y), a)
		CANCEL_EVENT:
			if player.ability == ID:
				player.end_ability()


## Fim por qualquer caminho: antes do impacto o visual é desfeito (sem rachar nem ferir); depois ele segue sozinho.
static func _on_end(player: Node, d: Dictionary) -> void:
	var skill = d.get("skill")
	if is_instance_valid(skill) and skill.can_cancel():
		skill.cancel()
		if not player.remote:
			Network.send_event(CANCEL_EVENT, player.global_position, Vector3.ZERO)


## A espada cravou (dono): congelamento curto para destacar o golpe.
static func _on_impacted(_center: Vector3, player_ref: WeakRef) -> void:
	var player = player_ref.get_ref()
	if player != null and is_instance_valid(player) and CONFIG.hitstop_time > 0.0:
		FXEpic.hit_stop(CONFIG.hitstop_time)


## A terra começou a tremer (dono): o dano começa no centro e acompanha o tremor até a borda.
static func _on_quake_started(center: Vector3) -> void:
	var root := FX._scene()
	if root == null:
		return
	var dmg := SeismicSpikesDamage.new()
	dmg.name = "SeismicSpikesDamage"
	dmg.setup(CONFIG, center)
	dmg.hit.connect(_on_hit)
	root.add_child(dmg)


## O tremor chegou num inimigo (uma vez por ativação; SeismicSpikesDamage já filtrou).
static func _on_hit(e: Node, center: Vector3) -> void:
	if not is_instance_valid(e) or e.dead:
		return
	var dmg := Game.melee_damage() * CONFIG.damage_mult * Game.ability_dmg_mult(ID)
	e.take_damage(dmg, center, false, 0.0, CONFIG.stun_time)
	Game.on_damage_dealt(dmg, e.max_hp)
	var now := Time.get_ticks_msec()
	if now - _last_hit_sfx >= HIT_SFX_GAP_MS:
		_last_hit_sfx = now
		Sfx.play_at("sword_hit_heavy", e.global_position, 0.1, -4.0)


## Toca o visual uma vez, bem abaixo do mapa, para os shaders ficarem prontos antes do primeiro uso da sessão.
## Chamado (deferred) pelo jogador local.
static func prewarm_instances(at: Node3D) -> void:
	var root := FX._scene()
	if root == null or at == null or not is_instance_valid(at) or not at.is_inside_tree():
		return
	var s: SeismicSpikesAoE = SKILL.instantiate()
	s.config = CONFIG
	s.warm_only = true
	root.add_child(s)
	s.global_position = at.global_position + Vector3(0, -200, 0)
