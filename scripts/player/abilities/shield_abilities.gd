class_name ShieldAbilities
extends RefCounted
## Égide Cristalina: habilidade 1 da espada quando há um escudo na mão secundária (ItemDB: "sword_aegis",
## "offhand": "shield", troca a Investida no kit). Segurando a tecla, o herói ergue o escudo (guarda medida no
## clipe "Sword And Shield Impact" do Mixamo, KnightMoves.AEGIS_GUARD) e uma barreira de placas em losango
## (AegisBarrier) se forma em volta dele. A barreira absorve o dano até a integridade acabar:
##   - Defesa (aqui + AegisRules): integridade própria em ability_data.aegis; Player.take_damage passa cada
##     golpe por absorb() antes da vida (Game.hp) e só o que sobra vira dano. Nada de segunda vida: a
##     absorção vale só enquanto a habilidade está ativa e some quando ela acaba.
##   - Visual (AegisBarrier): só recebe a fração de integridade, os golpes e o fim (quebra ou dissolve).
## Soltar a tecla, esquivar, morrer ou trocar de arma dissolve o escudo; integridade zero o quebra (a guarda
## cai na hora e a barreira estoura). A recarga conta a partir do fim (mais longa se quebrou).
## Parede (AegisWalls): enquanto erguido, monstros não entram (o círculo os empurra ao se formar) e projéteis
## de monstros param na coroa, com o golpe indo para o escudo. O servidor registra a mesma parede pela réplica.
## Rede: o dono manda "sword_aegis" (início, b.x = integridade máx.), "sword_aegis_hit" (a = ponto do golpe,
## b.x = fração) e "sword_aegis_break"; as réplicas só mostram. Para o servidor mandar na integridade, ele
## guarda o mesmo state de AegisRules por peer e chama absorb() antes de Network.server_damage_player.

const ID := "sword_aegis"
const HIT_EVENT := "sword_aegis_hit"
const BREAK_EVENT := "sword_aegis_break"
const BARRIER := preload("res://scenes/vfx/aegis/aegis_barrier.tscn")
const CONFIG := preload("res://assets/vfx/aegis/aegis_config.tres")
const BREAK_COOLDOWN_MULT := 1.5   ## recarga depois de uma quebra (x a recarga normal)
const TURN_RATE := 14.0            ## o escudo vira para onde a câmera olha (suavização)
const SHIELD_INVULN := 0.15         ## imunidade depois de um golpe absorvido (a da vida é 0,45 s)


## Começa a guarda. Devolve true se começou.
static func use(player: Node, id: String) -> bool:
	if id != ID:
		return false
	var max_i := AegisRules.max_integrity(CONFIG, Game.level, Game.defense())
	_begin(player, max_i)
	Network.send_event(ID, player.global_position, Vector3(max_i, 0.0, 0.0))
	Sfx.play("arcane_cast", 0.08, -4.0)
	return true


static func _begin(player: Node, max_i: float) -> void:
	# visual só onde alguém vê (o servidor dedicado só registra a parede)
	var barrier: AegisBarrier = null
	if FX._scene() != null:
		barrier = BARRIER.instantiate()
		barrier.config = CONFIG
		player.add_child(barrier)
		barrier.position = Vector3.ZERO
	# parede sólida (AegisWalls): o raio cresce com o círculo e a barreira, empurrando quem estiver perto
	var wall := AegisWalls.add(player, CONFIG.shield_width, CONFIG.shield_height,
		CONFIG.circle_form_time + CONFIG.barrier_form_time * 0.5)
	var d := {"aegis": AegisRules.new_state(max_i), "barrier": barrier, "wall": wall, "hit_at": -10.0}
	player.begin_ability(ID, d)
	# fim por qualquer caminho (end_ability): a barreira dissolve (ou termina a quebra) e se libera sozinha
	d["on_end"] = _on_end.bind(player, d)


static func _on_end(player: Node, d: Dictionary) -> void:
	AegisWalls.remove(d.get("wall", {}))   # sem escudo, sem parede
	var b = d.get("barrier")
	if is_instance_valid(b):
		b.finish()
	if not player.remote and player.cooldowns.has(ID):
		var sp: Dictionary = ItemDB.ABILITIES[ID]
		var mult := BREAK_COOLDOWN_MULT if bool(d.aegis.get("broken", false)) else 1.0
		player.cooldowns[ID] = Game.ability_cooldown(ID, float(sp.cooldown) * mult, Game.cooldown_mult(ID))
		Game.stats_changed.emit()


## Passo de física: fica parado (CONFIG.walk_speed_mult = 0; > 0 deixa andar devagar), vira para a câmera e
## confere a tecla (local). Nas réplicas só o tempo.
static func tick(player: Node, delta: float, move_dir := Vector3.ZERO, move_speed := 0.0) -> void:
	player.ability_t += delta
	if player.remote:
		return
	var target: Vector3 = move_dir * move_speed * CONFIG.walk_speed_mult
	var hv := Vector3(player.velocity.x, 0.0, player.velocity.z).lerp(target, 1.0 - exp(-10.0 * delta))
	player.velocity.x = hv.x
	player.velocity.z = hv.z
	var cam: Node3D = player.cam_yaw
	if cam:
		var f := -cam.global_basis.z
		f.y = 0.0
		if f.length() > 0.01:
			player.model.rotation.y = lerp_angle(player.model.rotation.y, atan2(f.x, f.z), 1.0 - exp(-TURN_RATE * delta))
	# a tecla do slot é a fonte da verdade: soltou (mesmo sem o evento de soltar, ex.: chat aberto), acaba
	var slot: int = player.ability_slot
	if slot >= 1 and not Input.is_action_pressed("spell_%d" % slot):
		release(player)


## Soltou a tecla: o escudo se desfaz.
static func release(player: Node) -> void:
	if player.ability == ID:
		player.end_ability()


static func can_dodge_cancel(_player: Node) -> bool:
	return true


static func dodge_cancel(player: Node) -> void:
	player.end_ability()


## Guarda com o escudo; o tranco do golpe toca por cima (hit_at = ability_t do último golpe).
static func pose(player: Node, p: Dictionary) -> void:
	var d: Dictionary = player.ability_data
	var raise := clampf(float(player.ability_t) / KnightMoves.AEGIS_RAISE, 0.0, 1.0)
	raise = raise * raise * (3.0 - 2.0 * raise)
	var since := float(player.ability_t) - float(d.get("hit_at", -10.0))
	KnightAnim.aegis_guard_pose(p, raise, since, float(player.get("_amp")))


## Réplica: começa a guarda, mostra golpes e a quebra (o dono já decidiu tudo).
static func play_remote(player: Node, kind: String, a: Vector3, b: Vector3) -> void:
	match kind:
		ID:
			_begin(player, maxf(b.x, 1.0))
			if FX._scene() != null:
				Sfx.play_at("arcane_cast", a, 0.08, -6.0)
		HIT_EVENT:
			if player.ability != ID:
				return
			var d: Dictionary = player.ability_data
			d.aegis.integrity = clampf(b.x, 0.0, 1.0) * float(d.aegis.max)
			d.hit_at = player.ability_t
			_show_hit(player, d, a, b.x)
		BREAK_EVENT:
			if player.ability != ID:
				return
			var d: Dictionary = player.ability_data
			d.aegis.integrity = 0.0
			d.aegis.broken = true
			_show_break(player, d, a)
			player.end_ability()


## Dono: passa o dano (já reduzido pela defesa) pelo escudo. Devolve o que sobra para a vida.
## Chamado por Player.take_damage com a habilidade ativa.
static func absorb(player: Node, amount: float, from_pos: Vector3) -> float:
	var d: Dictionary = player.ability_data
	var st: Dictionary = d.get("aegis", {})
	if not AegisRules.active(st):
		return amount
	var res := AegisRules.absorb(st, amount, CONFIG.absorb_ratio)
	var hit := _hit_point(player, from_pos)
	if res.absorbed > 0.0:
		d.hit_at = player.ability_t
		FX.damage_number(player.global_position + Vector3.UP * 2.3, str(int(round(res.absorbed))), Color(0.55, 0.85, 1.0), 44)
	if res.broke:
		_show_break(player, d, hit)
		Network.send_event(BREAK_EVENT, hit, Vector3.ZERO)
		player.end_ability()   # a proteção sai na hora; a barreira continua a quebra sozinha
	else:
		var frac := AegisRules.fraction(st)
		_show_hit(player, d, hit, frac)
		Network.send_event(HIT_EVENT, hit, Vector3(frac, 0.0, 0.0))
	return float(res.overflow)


## Ponto do escudo virado para quem bateu (na altura do peito).
static func _hit_point(player: Node, from_pos: Vector3) -> Vector3:
	var c: Vector3 = player.global_position + Vector3.UP * CONFIG.shield_height * 0.45
	var dir := from_pos - c
	dir.y = clampf(dir.y, -0.5, 0.8)
	if dir.length() < 0.01:
		dir = player.facing()
	return c + dir.normalized() * CONFIG.shield_width


static func _show_hit(player: Node, d: Dictionary, hit: Vector3, frac: float) -> void:
	var b = d.get("barrier")
	if is_instance_valid(b):
		b.impact(hit)
		b.set_integrity(frac, hit)
	if FX._scene() != null:
		Sfx.play_at("gem", hit, 0.12, -5.0 if not player.remote else -8.0)


static func _show_break(player: Node, d: Dictionary, hit: Vector3) -> void:
	var b = d.get("barrier")
	if is_instance_valid(b):
		b.set_integrity(0.0, hit)
		b.shatter()
	if FX._scene() != null:
		Sfx.play_at("frost_nova", player.global_position, 0.05, -3.0 if not player.remote else -6.0)
	if not player.remote:
		Game.notify.emit("A Égide se partiu!", Color(0.6, 0.85, 1.0))
		player.add_shake(0.35)
