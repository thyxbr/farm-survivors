class_name PartyShieldAbilities
extends RefCounted
## Grito do Bastião: habilidade 5 da espada quando há um escudo na mão secundária (ItemDB: "sword_rally",
## "offhand": "shield", slot 5, que a espada sem escudo não usa; tecla 5). O herói toca o clipe "Sword And Shield Power
## Up" do Mixamo inteiro (KnightAnim.taunt_pose; 2,36 s em 1x, acelerado por PartyShieldConfig.cast_speed) parado,
## envolto numa aura azul suave (PartyShieldCast); na explosão do clipe solta o grito (onda no chão, som); quando a animação termina, ele e todo o grupo por perto ganham
## o buff Bastião de Escudos (data/balance/buffs.json "sword_rally": +defesa fixa e percentual, Game.defense()).
##   - Buff: no solo vai direto para o herói (Game.add_buff). Online o cliente pede ao servidor
##     (Network.request_party_buff), que confere tudo (espada e escudo, nível, intervalo, vivo) e manda o buff para o
##     herói e para cada membro do grupo dele na mesma zona e a até PartyShieldConfig.radius m (PartyShieldRules.targets),
##     pelo mesmo _you_got_buff do Escudo de Luz do healer. Reaplicar renova o tempo (Game.add_buff), não empilha.
##   - Visual do buff: estilo de aura "bastiao" (BuffAura → PartyShieldBuff em cada personagem com o buff, inclusive
##     nas réplicas). Quando o buff acaba, os escudos se desfazem em partículas (PartyShieldBuff.dissipate).
##   - Rede: o dono manda "sword_rally" (a = posição); as réplicas tocam a mesma animação e aura, só visual. Cancelado
##     antes do fim: "sword_rally_cancel".
## A esquiva (ou morte, troca de arma) antes da animação terminar cancela: a aura apaga e ninguém ganha o buff (a
## recarga já foi gasta, como nas outras habilidades).

const ID := PartyShieldRules.ID
const BUFF := PartyShieldRules.BUFF
const CANCEL_EVENT := "sword_rally_cancel"
const CAST := preload("res://scenes/vfx/party_shield/party_shield_cast.tscn")
const CONFIG := preload("res://assets/vfx/party_shield/party_shield_config.tres")


static func use(player: Node, id: String) -> bool:
	if id != ID:
		return false
	_begin(player)
	Network.send_event(ID, player.global_position, Vector3.ZERO)
	Sfx.play("arcane_cast", 0.04, -5.0)
	return true


static func _begin(player: Node) -> void:
	var fx: PartyShieldCast = null
	if FX._scene() != null:   # servidor dedicado: sem visual
		fx = CAST.instantiate()
		fx.config = CONFIG
		fx.duration = total_time()
		player.add_child(fx)
	var d := {"fx": fx, "shout": false, "done": false}
	player.begin_ability(ID, d)
	d["on_end"] = _on_end.bind(player, d)


## Tempo da habilidade no herói: a animação inteira, na velocidade do PartyShieldConfig (cast_speed). O buff entra
## no fim dela.
static func total_time() -> float:
	return PartyShieldRules.cast_time(CONFIG.cast_speed)


## Instante do clipe (s, na escala original de 2,36 s) para o tempo da habilidade `t`.
static func clip_t(t: float) -> float:
	return minf(t * CONFIG.cast_speed, PartyShieldRules.CLIP_END)


static func tick(player: Node, delta: float, _move_dir := Vector3.ZERO, _move_speed := 0.0) -> void:
	player.ability_t += delta
	var d: Dictionary = player.ability_data
	if not player.remote:
		# parado enquanto grita: a tecla de andar não move
		player.velocity.x = move_toward(player.velocity.x, 0.0, 40.0 * delta)
		player.velocity.z = move_toward(player.velocity.z, 0.0, 40.0 * delta)
		player.cam_back = CONFIG.camera_back
	if not d.get("shout", false) and clip_t(player.ability_t) >= PartyShieldRules.SHOUT_AT:
		d["shout"] = true
		_shout(player, d)
	if player.ability_t >= total_time():
		d["done"] = true
		if not player.remote:
			grant(player)
		player.end_ability()


## O grito: onda azul no chão, pulso da aura e o som (dono e réplicas).
static func _shout(player: Node, d: Dictionary) -> void:
	var fx = d.get("fx")
	if is_instance_valid(fx):
		fx.shout()
	if FX._scene() != null:
		Sfx.play_at("slam", player.global_position, 0.05, -9.0)
		Sfx.play_at("frost", player.global_position, 0.08, -8.0)
	if not player.remote:
		player.add_shake(0.08)


## Dá o buff (dono, quando a animação termina). Online o servidor escolhe quem do grupo recebe (o herói incluído).
static func grant(_player: Node) -> void:
	if Network.is_client():
		Network.request_party_buff(ID)
	else:
		Game.add_buff(BUFF, Game.buff_duration(BUFF))
	Sfx.play("heal", 0.04, -6.0)


static func release(_player: Node) -> void:
	pass


static func can_dodge_cancel(player: Node) -> bool:
	return player.ability == ID and player.ability_t < total_time()


static func dodge_cancel(player: Node) -> void:
	player.end_ability()


static func pose(player: Node, p: Dictionary) -> void:
	KnightAnim.taunt_pose(p, clip_t(player.ability_t))


static func play_remote(player: Node, kind: String, _a: Vector3, _b: Vector3) -> void:
	match kind:
		ID:
			_begin(player)
			if FX._scene() != null:
				Sfx.play_at("arcane_cast", player.global_position, 0.06, -7.0)
		CANCEL_EVENT:
			if player.ability == ID:
				player.end_ability()


## Fim por qualquer caminho: animação completa → a aura apaga com um último pulso; antes disso (esquiva, morte, troca
## de arma) → cancela, sem buff, e avisa as réplicas.
static func _on_end(player: Node, d: Dictionary) -> void:
	var fx = d.get("fx")
	if d.get("done", false):
		if is_instance_valid(fx):
			fx.finish()
		return
	if is_instance_valid(fx):
		fx.cancel()
	if not player.remote:
		Network.send_event(CANCEL_EVENT, player.global_position, Vector3.ZERO)
