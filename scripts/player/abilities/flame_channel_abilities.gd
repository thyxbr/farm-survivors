class_name FlameChannelAbilities
extends RefCounted
## Canalização de Fogo: a habilidade da tecla 1 do mago com cajado (ItemDB "staff_flame", no lugar da antiga Bola de
## Fogo da tecla; a bola de fogo segue no clique do cajado, MageStaffAttack).
##   1. Preparo (`windup_time`): o mago estica o braço esquerdo (o que não segura o cajado) e vira a palma para a
##      frente; um círculo mágico de fogo se forma na frente da palma e começa a girar rápido.
##   2. Canalização (enquanto a tecla estiver segurada): uma labareda volumosa sai do centro do círculo e vai `length`
##      m à frente, com brasas, fumaça e calor. Cada inimigo dentro dela leva um tique de dano a cada `hit_interval`.
##      Gasta `mana_per_second`; dá para andar devagar, e o mago vira para onde a câmera olha (a labareda segue a mira).
##   3. Soltar a tecla (ou a mana acabar, ou `max_time`): o círculo e a labareda somem num fade-out (Tween) e as
##      partículas param de nascer. Um toque rápido ainda canaliza `min_time` s.
## Ritmo, dano e visual em FlameChannelConfig (assets/vfx/flame_channel/flame_channel_config.tres, no Inspector); as
## contas em FlameChannelRules; o visual e a detecção em FlameChanneling (cena própria na cena do mundo).
## A esquiva cancela a qualquer momento (fim macio, como soltar).
## Rede: o dono manda "staff_flame" (a = posição, b = (yaw, 0, 0)) e "staff_flame_end" ao parar: as réplicas tocam a
## mesma pose e o mesmo visual, sem dano (a direção vem do yaw da rede, que segue o dono).

const ID := "staff_flame"
const END_EVENT := "staff_flame_end"
const SKILL := preload("res://scenes/vfx/flame_channel/flame_channeling.tscn")
const CONFIG := preload("res://assets/vfx/flame_channel/flame_channel_config.tres")
const SOUND_EVERY := 0.32   ## estalos do fogo enquanto canaliza (s)


static func use(player: Node, id: String) -> bool:
	if id != ID:
		return false
	var yaw: float = player.model.rotation.y
	var look_f := _cam_forward(player)
	if look_f != Vector3.ZERO:
		yaw = atan2(look_f.x, look_f.z)   # já sai virado para onde a câmera olha
		player.model.rotation.y = yaw
	_begin(player)
	Network.send_event(ID, player.global_position, Vector3(yaw, 0.0, 0.0))
	return true


static func _begin(player: Node) -> void:
	var skill: FlameChanneling = null
	if FX._scene() != null:   # servidor dedicado: sem visual (o dano é do cliente dono)
		skill = SKILL.instantiate()
		skill.config = CONFIG
		skill.caster = player
		skill.model = player.model
		skill.hand = player.model.find_child("ArmL_Hand", true, false) as Node3D
		skill.deal_damage = not player.remote
		FX._scene().add_child(skill)
		if not player.remote:
			skill.hit.connect(_on_hit.bind(weakref(player)))
	var d := {"skill": skill, "released": false, "snd": 0.0, "soft": false}
	player.begin_ability(ID, d)
	d["on_end"] = _on_end.bind(player, d)
	Sfx.play_at("fire_cast", player.global_position, 0.1, -4.0 if not player.remote else -8.0)


## Para onde a câmera do jogador local olha (no plano); ZERO se não houver câmera (réplica).
static func _cam_forward(player: Node) -> Vector3:
	if player.remote:
		return Vector3.ZERO
	var cy = player.get("cam_yaw")
	if cy == null or not is_instance_valid(cy):
		return Vector3.ZERO
	var f: Vector3 = -(cy as Node3D).global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.ZERO


static func tick(player: Node, delta: float, move_dir := Vector3.ZERO, move_speed := 0.0) -> void:
	player.ability_t += delta
	var d: Dictionary = player.ability_data
	var t: float = player.ability_t
	var cfg: FlameChannelConfig = CONFIG
	# estalos do fogo enquanto a labareda está acesa
	d.snd = float(d.snd) - delta
	if t >= cfg.windup_time and float(d.snd) <= 0.0:
		d.snd = SOUND_EVERY
		Sfx.play_at("fire", player.global_position, 0.12, -9.0 if not player.remote else -13.0)
	if player.remote:
		return   # a réplica segue o yaw e a posição da rede; o fim vem do evento "staff_flame_end"
	# vira para a mira (a labareda vai junto) e anda devagar para onde a tecla mandar
	var look_f := _cam_forward(player)
	if look_f != Vector3.ZERO and not d.get("lock_yaw", false):   # lock_yaw: a demonstração filma de lado
		player.model.rotation.y = lerp_angle(player.model.rotation.y, atan2(look_f.x, look_f.z), 1.0 - exp(-cfg.turn_rate * delta))
	var want := move_dir * move_speed * cfg.move_speed
	var k := 1.0 - exp(-10.0 * delta)
	player.velocity.x = lerpf(player.velocity.x, want.x, k)
	player.velocity.z = lerpf(player.velocity.z, want.z, k)
	player.cam_back = cfg.camera_back * smoothstep(0.0, cfg.windup_time + 0.3, t)
	if t >= cfg.windup_time:
		player.add_shake(cfg.shake)
		Game.mp = maxf(0.0, Game.mp - cfg.mana_per_second * delta)
	if FlameChannelRules.should_end(t, bool(d.released), cfg.min_time, cfg.max_time, Game.mp if cfg.mana_per_second > 0.0 else 1.0):
		_soft_end(player)


## A tecla foi solta: termina (depois do mínimo; antes dele fica guardado e termina no mínimo).
static func release(player: Node) -> void:
	if player.ability != ID or player.remote:
		return
	player.ability_data.released = true
	if player.ability_t >= CONFIG.min_time:
		_soft_end(player)


static func can_dodge_cancel(player: Node) -> bool:
	return player.ability == ID


static func dodge_cancel(player: Node) -> void:
	_soft_end(player)


## Fim macio (soltar, mana, tempo, esquiva; réplica: o evento): o visual apaga no fade-out normal.
static func _soft_end(player: Node) -> void:
	if player.ability != ID:
		return
	player.ability_data.soft = true
	var skill = player.ability_data.get("skill")
	if is_instance_valid(skill):
		skill.stop()
	if not player.remote:
		Network.send_event(END_EVENT, player.global_position, Vector3.ZERO)
	player.end_ability()


## Fim por qualquer caminho: fora do fim macio (morte, troca de arma, menu) o visual apaga depressa.
static func _on_end(player: Node, d: Dictionary) -> void:
	var skill = d.get("skill")
	if is_instance_valid(skill) and skill.channeling:
		skill.stop(0.15)
	if not d.get("soft", false) and not player.remote:
		Network.send_event(END_EVENT, player.global_position, Vector3.ZERO)


## Pose: o braço esquerdo estica para a frente na altura do ombro com a palma virada para o alvo (o cajado fica na
## direita, baixo e de lado), base firme e um tremor leve enquanto o fogo sai (o coice da labareda).
static func pose(player: Node, p: Dictionary) -> void:
	var cfg: FlameChannelConfig = CONFIG
	var t: float = player.ability_t
	var w := smoothstep(0.0, cfg.windup_time * 0.8, t)
	var a: Dictionary = KnightMoves.FLAME_PALM
	var move := clampf(float(player.get("_amp")) if player.get("_amp") != null else 0.0, 0.0, 1.0)
	KnightAnim.drop_gait_comp(p)
	for j in a:
		if j in KnightAnim.LEG_KEYS:
			p[j] = lerp(p[j], a[j], w * (1.0 - move))   # andando, as pernas seguem a marcha
		else:
			p[j] = lerp(p[j], a[j], w)
	var shake := smoothstep(cfg.windup_time, cfg.windup_time + 0.3, t)
	if shake > 0.0:
		var ms := float(Time.get_ticks_msec())
		var n1 := sin(ms * 0.061) * 0.6 + sin(ms * 0.149 + 1.3) * 0.4
		var n2 := sin(ms * 0.047 + 2.1) * 0.6 + sin(ms * 0.127 + 0.4) * 0.4
		var tr: float = KnightMoves.FLAME_TREMBLE * shake
		p.arm_l += Vector3(n1 * tr, n2 * tr * 0.5, 0.0)
		p.wrist_l += n2 * tr
		p.body_x += n1 * tr * 0.2
	p.ground = 1.0
	for j in ["arm_l", "elbow_l", "wrist_l", "arm_r", "elbow_r", "twist", "body_x", "head_y"]:
		p.speed[j] = KnightMoves.FLAME_RAISE_SPEED


static func play_remote(player: Node, kind: String, _a: Vector3, b: Vector3) -> void:
	match kind:
		ID:
			player.model.rotation.y = b.x
			_begin(player)
		END_EVENT:
			if player.ability == ID:
				_soft_end(player)


## Tiques da labareda (dono): dano de fogo em cada inimigo atingido agora, sem empurrão.
static func _on_hit(targets: Array, player_ref: WeakRef) -> void:
	var player = player_ref.get_ref()
	if player == null or not is_instance_valid(player):
		return
	var cfg: FlameChannelConfig = CONFIG
	var dmg: float = cfg.damage_for(Game.spell_power()) * Game.damage_mult() * Game.ability_dmg_mult(ID)
	var n := 0
	for e in targets:
		if not is_instance_valid(e) or e.dead:
			continue
		# `pull` < 0 empurra com essa força (0 seria o empurrão padrão de um golpe, forte demais a cada tique)
		e.take_damage(dmg, player.global_position, false, 0.0, 0.0, -maxf(cfg.push, 0.01), "fogo")
		Game.on_damage_dealt(dmg, e.max_hp)
		n += 1
	if n > 0:
		player.add_shake(cfg.hit_shake)
		Sfx.play_at("fire_hit", (targets[0] as Node3D).global_position, 0.15, -10.0)


## Toca o visual uma vez, bem abaixo do mapa, para os shaders e pipelines ficarem prontos antes da primeira
## canalização da sessão (como GreatswordSpinAbilities.prewarm_instances). Chamado (deferred) pelo jogador local.
static func prewarm_instances(at: Node3D) -> void:
	var root := FX._scene()
	if root == null or at == null or not is_instance_valid(at) or not at.is_inside_tree():
		return
	var s: FlameChanneling = SKILL.instantiate()
	s.config = CONFIG
	s.warm_only = true
	root.add_child(s)
	s.global_position = at.global_position + Vector3(0, -200, 0)
