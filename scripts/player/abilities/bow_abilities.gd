class_name BowAbilities
extends RefCounted
## Habilidades da classe arco (mesma API de SwordAbilities). Estático: o estado vive no Player
## (ability, ability_t, ability_data). Ainda sem habilidades implementadas: use() devolve false.


## Executa a habilidade `id` para `player`. Devolve true só se ela começou.
static func use(_player: Node, _id: String) -> bool:
	return false


## Um passo de física da habilidade em execução (jogador local e réplicas).
static func tick(player: Node, _delta: float, _move_dir := Vector3.ZERO, _move_speed := 0.0) -> void:
	player.end_ability()


## A esquiva pode interromper a habilidade agora?
static func can_dodge_cancel(_player: Node) -> bool:
	return false


## Pose da habilidade por cima da locomoção (de _animate).
static func pose(_player: Node, _p: Dictionary) -> void:
	pass


## Réplica: começa a habilidade de outro jogador pelo evento de rede (só visual).
static func play_remote(_player: Node, _kind: String, _a: Vector3, _b: Vector3) -> void:
	pass


## A tecla do slot da habilidade em execução foi solta.
static func release(_player: Node) -> void:
	pass
