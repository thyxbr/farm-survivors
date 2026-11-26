class_name DarkTauntAbilities
extends RefCounted
## Círculo da Provocação Sombria: habilidade 3 da espada quando há um escudo na mão secundária (ItemDB: "sword_taunt",
## "offhand": "shield", troca a Fúria Picante no kit; tecla 3). O herói recolhe os braços e solta uma onda de
## energia sombria (pose medida no clipe "Sword And Shield Power Up" do Mixamo, KnightAnim.taunt_pose) e fica parado
## enquanto um círculo mágico se desenha no chão em volta dele; mãos sombrias saem do chão, agarram cada inimigo
## dentro do raio (imobilizados) e, ao soltar, eles ficam provocados: só perseguem e atacam este herói.
##   - Sequência e visual: DarkTauntSkill (cena própria, na cena do mundo; vive mais que a habilidade e se libera
##     sozinha). Configuração em DarkTauntConfig (assets/vfx/dark_taunt/dark_taunt_config.tres, no Inspector).
##   - Provocação: no instante em que cada mão fecha o DarkTauntSkill emite `captured`; aqui cada inimigo recebe
##     Enemy.apply_taunt(herói, imobilização, provocação), uma vez por ativação. A IA de sempre faz o resto: o alvo
##     dela (Enemy._nearest_player) passa a ser o herói. No multiplayer a réplica do inimigo pede ao servidor
##     (Network._taunt_enemy), que provoca com a réplica deste jogador como alvo.
##   - Rede: o dono manda "sword_taunt" (a = posição, b = (semente, 0, 0)): as réplicas montam a mesma sequência
##     (mesmas mãos pela semente), só visual. Cancelado antes de alguma mão fechar: "sword_taunt_cancel".
## A esquiva (ou morte, troca de arma) antes de alguma mão fechar cancela: o círculo e as mãos se desfazem.

const ID := "sword_taunt"
const CANCEL_EVENT := "sword_taunt_cancel"
const SKILL := preload("res://scenes/vfx/dark_taunt/dark_taunt_skill.tscn")
const CONFIG := preload("res://assets/vfx/dark_taunt/dark_taunt_config.tres")


static func use(player: Node, id: String) -> bool:
	if id != ID:
		return false
	var seed_v := randi() % 65536
	_begin(player, seed_v)
	Network.send_event(ID, player.global_position, Vector3(float(seed_v), 0.0, 0.0))
	Sfx.play("arcane_cast", 0.04, -3.0)
	return true


static func _begin(player: Node, seed_v: int) -> void:
	var skill: DarkTauntSkill = null
	var root := FX._scene()
	if root != null:   # servidor dedicado: sem visual (a provocação vem do cliente dono, por Network._taunt_enemy)
		skill = SKILL.instantiate()
		skill.config = CONFIG
		skill.caster = player
		skill.seed_value = seed_v
		skill.deal_effects = not player.remote
		skill.position = player.global_position   # antes de entrar na cena: o _ready usa a posição
		root.add_child(skill)
		if not player.remote:
			skill.captured.connect(_on_captured.bind(weakref(player)))
	var d := {"skill": skill}
	player.begin_ability(ID, d)
	d["on_end"] = _on_end.bind(player, d)


## Tempo total da habilidade no herói: até as mãos agarrarem e ele voltar à guarda. Depois disso a sequência
## (mãos segurando, dissipação) segue sozinha e o herói já está livre para tankar.
static func total_time() -> float:
	return CONFIG.grab_at() + KnightMoves.TAUNT_RETURN


## Até quando a esquiva cancela (antes das mãos fecharem).
static func cancel_window() -> float:
	return CONFIG.grab_at()


static func tick(player: Node, delta: float, _move_dir := Vector3.ZERO, _move_speed := 0.0) -> void:
	player.ability_t += delta
	if not player.remote:
		# parado enquanto invoca: a tecla de andar não move
		player.velocity.x = move_toward(player.velocity.x, 0.0, 40.0 * delta)
		player.velocity.z = move_toward(player.velocity.z, 0.0, 40.0 * delta)
		player.cam_back = CONFIG.camera_back if player.ability_t < cancel_window() else 0.0
	if player.ability_t >= total_time():
		player.end_ability()


static func release(_player: Node) -> void:
	pass


static func can_dodge_cancel(player: Node) -> bool:
	if player.ability != ID:
		return false
	var skill = player.ability_data.get("skill")
	return player.ability_t < cancel_window() and (skill == null or not is_instance_valid(skill) or skill.can_cancel())


static func dodge_cancel(player: Node) -> void:
	player.end_ability()


## Recolhe os braços, explode a energia, segura enquanto as mãos sobem e volta à guarda depois que elas agarram.
static func pose(player: Node, p: Dictionary) -> void:
	KnightAnim.taunt_pose(p, DarkTauntRules.clip_time(player.ability_t, cancel_window(), KnightMoves.TAUNT_RETURN))


static func play_remote(player: Node, kind: String, a: Vector3, b: Vector3) -> void:
	match kind:
		ID:
			_begin(player, int(b.x))
			if FX._scene() != null:
				Sfx.play_at("arcane_cast", a, 0.06, -5.0)
		CANCEL_EVENT:
			if player.ability == ID:
				player.end_ability()


## Fim por qualquer caminho: antes de alguma mão fechar, tudo se desfaz (sem provocação); depois segue sozinho.
static func _on_end(player: Node, d: Dictionary) -> void:
	var skill = d.get("skill")
	if is_instance_valid(skill) and skill.can_cancel():
		skill.cancel()
		if not player.remote:
			Network.send_event(CANCEL_EVENT, player.global_position, Vector3.ZERO)


## Uma mão fechou num inimigo (dono): imobiliza e provoca, uma vez por ativação (DarkTauntSkill já filtrou).
static func _on_captured(enemy: Node3D, player_ref: WeakRef) -> void:
	var player = player_ref.get_ref()
	if player == null or not is_instance_valid(player) or player.dead:
		return
	if not is_instance_valid(enemy) or enemy.get("dead") == true or not enemy.has_method("apply_taunt"):
		return
	# Correntes do Abismo (bênção do Tank na expedição): run_mods "taunt_time" alonga a prisão e a provocação
	var k := 1.0 + maxf(float(Game.run_mods.get("taunt_time", 0.0)), 0.0)
	enemy.apply_taunt(player, CONFIG.hold_time * k, CONFIG.taunt_time * k)
