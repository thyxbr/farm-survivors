class_name HitGuard
extends RefCounted
## Servidor: confere um acerto mandado pelo cliente antes de contar o jogador como "quem acertou"
## (XP e sorteio de loot próprio no abate). O combate continua no cliente; isto só barra o óbvio:
## acerto de dano quase zero e acerto de longe (marcar todos os inimigos da zona sem lutar).

## Dano mínimo de um acerto que conta.
const MIN_DAMAGE := 1.0
## Distância máxima entre a última posição recebida do jogador e o inimigo (flecha/magia de longe cabem).
const MAX_RANGE := 45.0


## true = o acerto vale (dano, lentidão e contribuição). `hitter_pos` não finito = posição desconhecida.
## amount == 0 (só lentidão) precisa só do alcance.
static func accepts(amount: float, hitter_pos: Vector3, enemy_pos: Vector3) -> bool:
	if not hitter_pos.is_finite() or hitter_pos.distance_to(enemy_pos) > MAX_RANGE:
		return false
	return amount == 0.0 or amount >= MIN_DAMAGE
