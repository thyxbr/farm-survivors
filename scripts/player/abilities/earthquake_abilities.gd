class_name EarthquakeAbilities
extends RefCounted
## Terremoto Devastador: habilidade 2 da espada quando há um escudo na mão secundária (ItemDB: "sword_earthquake",
## "offhand": "shield", troca o Golpe Sísmico no kit; tecla 2). O herói ergue o escudo bem alto e o bate com tudo
## no chão à frente (pose em KnightAnim.earthquake_pose, sobre o braço e o giro do escudo da guarda); no instante do
## contato a onda de choque sai do ponto do golpe e corre em círculo pelo terreno, rachando o chão.
##   - Sequência e visual: EarthquakeSkill (cena própria, na cena do mundo; vive mais que a habilidade e se libera
##     sozinha). Configuração em EarthquakeConfig (assets/vfx/earthquake/earthquake_config.tres, no Inspector).
##   - Dano: separado do visual. No sinal `impacted` do EarthquakeSkill o dono cria um EarthquakeDamage no ponto do
##     impacto; ele segue o mesmo relógio da onda e avisa (`hit`) cada inimigo quando a frente da onda chega nele
##     (dentro do raio máximo, uma vez por ativação). Aqui cada um leva Enemy.take_damage (o caminho dos golpes: no
##     multiplayer vira Network.client_hit_enemy e o servidor aplica). Só o dono fere; o herói e os aliados não
##     estão na camada dos inimigos.
##   - Rede: o dono manda "sword_earthquake" (a = posição, b = (yaw, semente)): as réplicas montam a mesma sequência
##     (mesmas rachaduras pela semente), só visual. Cancelado antes do impacto: "sword_earthquake_cancel".
## A esquiva (ou morte, troca de arma) antes do escudo tocar o chão cancela: a carga se desfaz, sem onda nem dano.

const ID := "sword_earthquake"
const CANCEL_EVENT := "sword_earthquake_cancel"
const SKILL := preload("res://scenes/vfx/earthquake/earthquake_skill.tscn")
const CONFIG := preload("res://assets/vfx/earthquake/earthquake_config.tres")
const HIT_SFX_GAP_MS := 60   ## um som de golpe por vez (a onda pega vários no mesmo quadro)

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


## Ponto onde a borda do escudo toca o chão: à frente dos pés do herói.
static func impact_point(pos: Vector3, yaw: float) -> Vector3:
	return pos + Vector3(sin(yaw), 0.0, cos(yaw)) * CONFIG.forward_offset


static func _begin(player: Node, yaw: float, seed_v: int, pos: Vector3) -> void:
	var skill: EarthquakeSkill = null
	var root := FX._scene()
	if root != null:   # servidor dedicado: sem visual (o dano é do cliente dono)
		skill = SKILL.instantiate()
		skill.config = CONFIG
		skill.seed_value = seed_v
		skill.position = impact_point(pos, yaw)   # a cena do mundo fica na origem: local = global
		root.add_child(skill)
		if not player.remote:
			skill.impacted.connect(_on_impacted.bind(weakref(player)))
	var d := {"skill": skill, "yaw": yaw}
	player.begin_ability(ID, d)
	d["on_end"] = _on_end.bind(player, d)


static func tick(player: Node, delta: float, _move_dir := Vector3.ZERO, _move_speed := 0.0) -> void:
	player.ability_t += delta
	var d: Dictionary = player.ability_data
	# virado para onde o escudo bate (na réplica também: o yaw da rede só volta depois)
	player.model.rotation.y = lerp_angle(player.model.rotation.y, float(d.get("yaw", 0.0)), 1.0 - exp(-14.0 * delta))
	if not player.remote:
		# parado enquanto bate: a tecla de andar não move
		player.velocity.x = move_toward(player.velocity.x, 0.0, 40.0 * delta)
		player.velocity.z = move_toward(player.velocity.z, 0.0, 40.0 * delta)
		player.cam_back = CONFIG.camera_back
	if player.ability_t >= CONFIG.total_time():
		player.end_ability()


static func release(_player: Node) -> void:
	pass


## Até o escudo tocar o chão a esquiva cancela.
static func can_dodge_cancel(player: Node) -> bool:
	return player.ability == ID and player.ability_t < CONFIG.impact_time()


static func dodge_cancel(player: Node) -> void:
	player.end_ability()


## Ergue o escudo e bate no chão (KnightAnim.earthquake_pose; tempos do EarthquakeConfig).
static func pose(player: Node, p: Dictionary) -> void:
	KnightAnim.earthquake_pose(p, EarthquakeRules.pose_phase(float(player.ability_t), CONFIG.windup_time,
		CONFIG.slam_time, CONFIG.hold_time, CONFIG.recover_time))


static func play_remote(player: Node, kind: String, a: Vector3, b: Vector3) -> void:
	match kind:
		ID:
			_begin(player, b.x, int(b.y), a)
		CANCEL_EVENT:
			if player.ability == ID:
				player.end_ability()


## Fim por qualquer caminho: antes do impacto a carga é desfeita (sem onda nem dano); depois a onda segue sozinha.
static func _on_end(player: Node, d: Dictionary) -> void:
	var skill = d.get("skill")
	if is_instance_valid(skill) and skill.can_cancel():
		skill.cancel()
		if not player.remote:
			Network.send_event(CANCEL_EVENT, player.global_position, Vector3.ZERO)


## O escudo tocou o chão (dono): o dano da onda começa no ponto do impacto, e o congelamento curto destaca o golpe.
static func _on_impacted(center: Vector3, player_ref: WeakRef) -> void:
	var root := FX._scene()
	if root == null:
		return
	var dmg := EarthquakeDamage.new()
	dmg.name = "EarthquakeDamage"
	dmg.setup(CONFIG, center)
	dmg.hit.connect(_on_hit)
	root.add_child(dmg)
	var player = player_ref.get_ref()
	if player != null and is_instance_valid(player) and CONFIG.hitstop_time > 0.0:
		FXEpic.hit_stop(CONFIG.hitstop_time)


## A frente da onda chegou num inimigo (uma vez por ativação; EarthquakeDamage já filtrou).
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
