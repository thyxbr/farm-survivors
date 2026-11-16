class_name ScepterAbilities
extends RefCounted
## Habilidades da classe cetro (mesma API de StaffAbilities). Estático: o estado vive no Player
## (ability, ability_t, ability_data). A Cura segue em Player.cast() (match das magias antigas);
## o Escudo de Luz (slot 2) e o Banquete do Herói (slot 4) são buffs em aliados: o servidor distribui.


const BUFF_TIME := 0.5
const WARD_COLOR := Color(0.5, 0.75, 1.0)
const FEAST_COLOR := Color(1.0, 0.85, 0.3)


## Executa a habilidade `id` para `player`. Devolve true só se ela começou. Online o servidor decide quem
## recebe (o próprio incluído, pelo mesmo caminho da Cura); no solo o buff vai direto para o jogador.
static func use(player: Node, id: String) -> bool:
	if not HealRules.ALLY_BUFFS.has(id):
		return false
	player.begin_ability(id, {})
	if Network.is_client():
		Network.request_ally_buff(id)
	else:
		Game.add_buff(HealRules.ALLY_BUFFS[id], Game.buff_duration(HealRules.ALLY_BUFFS[id]))
		if id == "scepter_ult":
			player.receive_heal(HealRules.ULT_HEAL)
	Network.send_event(id, player.global_position, Vector3.ZERO)
	FX.ring(player.global_position + Vector3.UP * 0.1, _color(id), 2.6, 0.5)
	Sfx.play("arcane_cast", 0.05, -4.0)
	return true


static func _color(id: String) -> Color:
	return FEAST_COLOR if id == "scepter_ult" else WARD_COLOR


## Um passo de física da habilidade em execução: só a pose curta de braços erguidos.
static func tick(player: Node, delta: float, _move_dir := Vector3.ZERO, _move_speed := 0.0) -> void:
	player.ability_t += delta
	if player.ability_t >= BUFF_TIME:
		player.end_ability()


## A esquiva pode interromper a habilidade agora? (sem habilidade longa: sempre)
static func can_dodge_cancel(_player: Node) -> bool:
	return true


static func dodge_cancel(player: Node) -> void:
	player.end_ability()


## Pose da habilidade por cima da locomoção.
static func pose(player: Node, p: Dictionary) -> void:
	KnightAnim.play_track(p, KnightMoves.BUFF, clampf(player.ability_t / BUFF_TIME, 0.0, 1.0), 0.0)


## Réplica: habilidade de outro jogador pelo evento de rede (só visual).
static func play_remote(player: Node, kind: String, a: Vector3, _b: Vector3) -> void:
	player.begin_ability(kind, {})
	FX.ring(a + Vector3.UP * 0.1, _color(kind), 2.6, 0.5)
	Sfx.play_at("arcane_cast", a, 0.05, -8.0)


## A tecla do slot foi solta (sem habilidade segurada).
static func release(_player: Node) -> void:
	pass
