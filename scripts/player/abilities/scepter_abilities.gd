class_name ScepterAbilities
extends RefCounted
## Habilidades da classe cetro (mesma API de StaffAbilities). Estático: o estado vive no Player
## (ability, ability_t, ability_data). A Cura segue em Player.cast() / confirm_heal() (mira no aliado).
## Lança de Luz (slot 2): projétil de dano alto num alvo. Escudo de Luz (slot 3): buff em aliados.
## Banquete do Herói (slot 4): buff e cura total. Julgamento de Luz (slot 5): área mirada no chão
## (Player.area_point) com dano e atordoamento.
## Os buffs em aliados o servidor distribui; o dano segue o caminho normal (take_damage → servidor).

const PROJECTILE := preload("res://scripts/player/projectile.gd")

const BUFF_TIME := 0.5
const WARD_COLOR := Color(0.5, 0.75, 1.0)
const FEAST_COLOR := Color(1.0, 0.85, 0.3)

## Lança de Luz: a lança sai em LANCE_RELEASE s (gesto de arremesso) e a pose acaba em KnightMoves.CAST_TIME.
const LANCE_RELEASE := 0.12
const LANCE_SPEED := 44.0
const LANCE_RANGE := 34.0
const LANCE_BASE := 35.0
const LANCE_SP := 4.5

## Julgamento de Luz: o raio é o `aim_radius` da habilidade (ItemDB), o mesmo do círculo mostrado na mira.
const NOVA_RADIUS := 5.0
const NOVA_BASE := 30.0
const NOVA_SP := 3.5
const NOVA_STUN := 0.8
## Raio dos aliados no Banquete (o mesmo HealRules.RADIUS do servidor, só para o visual).
const FEAST_RADIUS := 8.0


## Executa a habilidade `id` para `player`. Devolve true só se ela começou.
static func use(player: Node, id: String) -> bool:
	if id == "scepter_lance":
		player.begin_ability(id, {"fired": false})
		return true
	if id == "scepter_judgment":
		var at: Vector3 = player.area_point
		player.begin_ability(id, {})
		Network.send_event(id, player.global_position, at)
		_cast_fx(player.global_position, id, at)
		_radiant_damage(player, at)
		return true
	if not HealRules.ALLY_BUFFS.has(id):
		return false
	# buffs: online o servidor decide quem recebe (o próprio incluído, pelo mesmo caminho da Cura);
	# no solo o buff vai direto para o jogador
	player.begin_ability(id, {})
	if Network.is_client():
		Network.request_ally_buff(id)
	else:
		Game.add_buff(HealRules.ALLY_BUFFS[id], Game.buff_duration(HealRules.ALLY_BUFFS[id]))
		if id == "scepter_ult":
			player.receive_heal(HealRules.ULT_HEAL)
	Network.send_event(id, player.global_position, Vector3.ZERO)
	_cast_fx(player.global_position, id)
	return true


## Visual de conjuração (local e réplicas). `pos` = o healer; `at` = onde cai o Julgamento de Luz.
static func _cast_fx(pos: Vector3, id: String, at := Vector3.ZERO) -> void:
	if id == "scepter_judgment":
		HolyFX.radiant_nova(at, NOVA_RADIUS)
		Sfx.play_at("arcane_cast", pos, 0.05, -2.0)
		Sfx.play_at("explode", at, 0.1, -8.0)
	elif id == "scepter_ward":
		HolyFX.ward(pos, HealRules.RADIUS)
		Sfx.play_at("arcane_cast", pos, 0.05, -4.0)
	else:
		HolyFX.feast(pos, FEAST_RADIUS)
		Sfx.play_at("heal", pos, 0.0, -2.0)
		Sfx.play_at("arcane_cast", pos, 0.05, -4.0)


## Dano do Julgamento de Luz nos inimigos em volta de `pos` (só o dono: as réplicas só veem).
static func _radiant_damage(player: Node, pos: Vector3) -> void:
	player.add_shake(0.2)
	var dmg := (NOVA_BASE + Game.spell_power() * NOVA_SP) * Game.damage_mult()
	for e in player.get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		if e.global_position.distance_to(pos) <= NOVA_RADIUS + e.radius:
			var d := dmg * randf_range(0.92, 1.08)
			e.take_damage(d, pos, false, 0.0, NOVA_STUN)
			Game.add_fury_from_damage(d, e.max_hp)
			HolyFX.smite(e.global_position)


## Dispara a Lança de Luz da ponta do cetro para onde a câmera mira.
static func _fire_lance(player: Node) -> void:
	var origin: Vector3 = player.weapon_tip()
	var d: Vector3 = player.aim_dir(origin)
	var crit: bool = randf() < Game.crit_chance()
	var dmg := (LANCE_BASE + Game.spell_power() * LANCE_SP) * Game.damage_mult() * (1.8 if crit else 1.0)
	player._spawn_projectile("holy_lance", origin, d, dmg, crit, 0)
	Network.send_event("scepter_lance", origin, d)
	Sfx.play("arcane_cast", 0.1, -2.0)
	player.add_shake(0.06)


## Um passo de física da habilidade em execução.
static func tick(player: Node, delta: float, move_dir := Vector3.ZERO, move_speed := 0.0) -> void:
	player.ability_t += delta
	if player.ability == "scepter_lance":
		if not player.remote:
			# anda devagar durante o arremesso (como ao conjurar)
			player.velocity.x = move_dir.x * move_speed * 0.6
			player.velocity.z = move_dir.z * move_speed * 0.6
			if not player.ability_data.get("fired", false) and player.ability_t >= LANCE_RELEASE:
				player.ability_data["fired"] = true
				_fire_lance(player)
		if player.ability_t >= KnightMoves.CAST_TIME:
			player.end_ability()
		return
	if player.ability_t >= BUFF_TIME:
		player.end_ability()


## A esquiva pode interromper a habilidade agora? (sem habilidade longa: sempre)
static func can_dodge_cancel(_player: Node) -> bool:
	return true


static func dodge_cancel(player: Node) -> void:
	player.end_ability()


## Pose da habilidade por cima da locomoção.
static func pose(player: Node, p: Dictionary) -> void:
	if player.ability == "scepter_lance":
		# gesto da bola de fogo com cajado (ergue, tomba a gema para o alvo, coice), adiantado para o
		# disparo cair em LANCE_RELEASE
		var t := clampf((player.ability_t + KnightMoves.CAST_RELEASE * KnightMoves.CAST_TIME - LANCE_RELEASE)
			/ KnightMoves.CAST_TIME, 0.0, 1.0)
		KnightAnim.cast_pose(p, "fireball", t, 0.0, true)
		return
	KnightAnim.play_track(p, KnightMoves.BUFF, clampf(player.ability_t / BUFF_TIME, 0.0, 1.0), 0.0)


## Réplica: habilidade de outro jogador pelo evento de rede (só visual).
static func play_remote(player: Node, kind: String, a: Vector3, b: Vector3) -> void:
	if kind == "scepter_lance":
		player.begin_ability(kind, {"fired": true})
		player.ability_t = LANCE_RELEASE   # o evento chega no disparo
		var p := PROJECTILE.new()
		p.kind = "holy_lance"
		p.direction = b
		p.visual_only = true
		p.speed = LANCE_SPEED
		p.life = LANCE_RANGE / LANCE_SPEED
		player.get_tree().current_scene.add_child(p)
		p.global_position = a
		Sfx.play_at("arcane_cast", a, 0.1, -6.0)
		return
	player.begin_ability(kind, {})
	_cast_fx(a, kind, b if b != Vector3.ZERO else a)


## A tecla do slot foi solta (sem habilidade segurada).
static func release(_player: Node) -> void:
	pass
