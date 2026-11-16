class_name ScepterAbilities
extends RefCounted
## Habilidades da classe cetro (mesma API de StaffAbilities). Estático: o estado vive no Player
## (ability, ability_t, ability_data). A Cura segue em Player.cast() (match das magias antigas);
## o Escudo de Luz (slot 2) e a ultimate (slot 4) ainda estão "Em breve" (ready: false em ItemDB.ABILITIES),
## então `use` não começa nada e o Player mostra o aviso.


## Executa a habilidade `id` para `player`. Devolve true só se ela começou.
static func use(_player: Node, _id: String) -> bool:
	return false


## Um passo de física da habilidade em execução (nenhuma ainda: encerra na hora).
static func tick(player: Node, _delta: float, _move_dir := Vector3.ZERO, _move_speed := 0.0) -> void:
	player.end_ability()


## A esquiva pode interromper a habilidade agora? (sem habilidade longa: sempre)
static func can_dodge_cancel(_player: Node) -> bool:
	return true


static func dodge_cancel(player: Node) -> void:
	player.end_ability()


## Pose da habilidade por cima da locomoção.
static func pose(_player: Node, _p: Dictionary) -> void:
	pass


## Réplica: habilidade de outro jogador pelo evento de rede (só visual).
static func play_remote(_player: Node, _kind: String, _a: Vector3, _b: Vector3) -> void:
	pass


## A tecla do slot foi solta (sem habilidade segurada).
static func release(_player: Node) -> void:
	pass
