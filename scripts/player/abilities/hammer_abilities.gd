class_name HammerAbilities
extends RefCounted
## Martelo de Energia: habilidade 4 da espada quando há um escudo na mão secundária (ItemDB: "sword_hammer",
## "offhand": "shield", troca o Turbilhão no kit; tecla 4, com recarga em vez de fúria). O herói ergue a espada (pose medida no clipe
## "Sword And Shield Casting" do Mixamo, KnightAnim.hammer_raise_pose) e fica parado enquanto um círculo mágico
## se forma acima da cabeça, um martelo gigante de energia sai dele, o círculo fecha e o martelo cai à frente,
## ferindo todos os inimigos no raio (uma vez cada) e abrindo crateras em volta.
##   - Sequência e visual: HammerSkill (cena própria, na cena do mundo; vive mais que a habilidade e se libera
##     sozinha). Configuração em HammerConfig (assets/vfx/hammer/hammer_config.tres, editável no Inspector).
##   - Dano: no instante do impacto o HammerSkill emite `landed` com os inimigos dentro da Area3D (camada dos
##     inimigos, grupo "enemies"); aqui cada um leva Enemy.take_damage uma vez (o mesmo caminho dos golpes: no
##     multiplayer vira Network.client_hit_enemy e o servidor aplica). Só o dono fere; aliados e o próprio herói
##     não estão na camada dos inimigos.
##   - Rede: o dono manda "sword_hammer" (a = posição, b = (yaw, semente)): as réplicas montam a mesma sequência
##     (mesmas crateras pela semente), só visual. Cancelado antes da queda: "sword_hammer_cancel".
## A esquiva (ou morte, troca de arma) antes da queda cancela: o círculo e o martelo se desfazem, sem dano.

const ID := "sword_hammer"
const CANCEL_EVENT := "sword_hammer_cancel"
const SKILL := preload("res://scenes/vfx/hammer/hammer_skill.tscn")
const CONFIG := preload("res://assets/vfx/hammer/hammer_config.tres")
const RECOVER := 0.3   ## depois do impacto o herói ainda baixa a espada antes de soltar (s)


static func use(player: Node, id: String) -> bool:
	if id != ID:
		return false
	var f: Vector3 = player.facing()
	var yaw := atan2(f.x, f.z)
	var seed_v := randi() % 65536
	_begin(player, yaw, seed_v)
	Network.send_event(ID, player.global_position, Vector3(yaw, float(seed_v), 0.0))
	Sfx.play("arcane_cast", 0.06, -2.0)
	return true


static func _begin(player: Node, yaw: float, seed_v: int) -> void:
	var skill: HammerSkill = null
	var root := FX._scene()
	if root != null:   # servidor dedicado: sem visual (o dano é do cliente dono)
		skill = SKILL.instantiate()
		skill.config = CONFIG
		skill.follow = player
		skill.yaw = yaw
		skill.seed_value = seed_v
		skill.deal_damage = not player.remote
		root.add_child(skill)
		if not player.remote:
			skill.landed.connect(_on_landed.bind(weakref(player)))
	var d := {"skill": skill, "yaw": yaw}
	player.begin_ability(ID, d)
	d["on_end"] = _on_end.bind(player, d)


## Tempo total da habilidade no herói: até o impacto e a espada baixando.
static func total_time() -> float:
	return CONFIG.impact_time() + RECOVER


## Até quando a esquiva cancela (antes da queda).
static func cancel_window() -> float:
	return CONFIG.circle_form_time + CONFIG.formation_time + CONFIG.circle_close_time


static func tick(player: Node, delta: float, _move_dir := Vector3.ZERO, _move_speed := 0.0) -> void:
	player.ability_t += delta
	var d: Dictionary = player.ability_data
	# virado para onde o martelo cai (na réplica também: o yaw da rede só volta depois)
	player.model.rotation.y = lerp_angle(player.model.rotation.y, float(d.get("yaw", 0.0)), 1.0 - exp(-12.0 * delta))
	if not player.remote:
		# parado enquanto invoca: a tecla de andar não move
		player.velocity.x = move_toward(player.velocity.x, 0.0, 40.0 * delta)
		player.velocity.z = move_toward(player.velocity.z, 0.0, 40.0 * delta)
		player.cam_back = CONFIG.camera_back
		# olha para cima enquanto o círculo e o martelo estão no alto; na queda volta para ver o impacto no chão
		player.cam_tilt = CONFIG.camera_tilt if player.ability_t < cancel_window() else 0.0
	if player.ability_t >= total_time():
		player.end_ability()


static func release(_player: Node) -> void:
	pass


static func can_dodge_cancel(player: Node) -> bool:
	return player.ability == ID and player.ability_t < cancel_window()


static func dodge_cancel(player: Node) -> void:
	player.end_ability()


## A espada sobe (clipe do Mixamo), fica erguida enquanto o martelo se forma e cai, e baixa depois do impacto.
static func pose(player: Node, p: Dictionary) -> void:
	var t: float = player.ability_t
	var lower := clampf((t - CONFIG.impact_time()) / KnightMoves.HAMMER_LOWER, 0.0, 1.0)
	KnightAnim.hammer_raise_pose(p, t, lower)


static func play_remote(player: Node, kind: String, a: Vector3, b: Vector3) -> void:
	match kind:
		ID:
			_begin(player, b.x, int(b.y))
			if FX._scene() != null:
				Sfx.play_at("arcane_cast", a, 0.06, -5.0)
		CANCEL_EVENT:
			if player.ability == ID:
				player.end_ability()


## Fim por qualquer caminho: antes da queda o martelo é desfeito (sem dano); depois ele segue sozinho.
static func _on_end(player: Node, d: Dictionary) -> void:
	var skill = d.get("skill")
	if is_instance_valid(skill) and skill.can_cancel():
		skill.cancel()
		if not player.remote:
			Network.send_event(CANCEL_EVENT, player.global_position, Vector3.ZERO)


## O martelo bateu (dono): dano em cada inimigo atingido, uma vez por ativação (HammerSkill já filtrou).
static func _on_landed(center: Vector3, targets: Array, player_ref: WeakRef) -> void:
	var dmg := Game.melee_damage() * CONFIG.damage_mult * Game.ability_dmg_mult(ID)
	var any := false
	for e in targets:
		if not is_instance_valid(e) or e.dead:
			continue
		e.take_damage(dmg, center, false, 0.0, CONFIG.stun_time)
		Game.on_damage_dealt(dmg, e.max_hp)
		any = true
	if any:
		Sfx.play("sword_hit_heavy", 0.1)
	# o tremor da câmera é do HammerGroundShock (de todo mundo perto, também nas réplicas); o congelamento curto é
	# só de quem bateu
	var player = player_ref.get_ref()
	if player != null and is_instance_valid(player) and CONFIG.hitstop_time > 0.0:
		FXEpic.hit_stop(CONFIG.hitstop_time)
