@tool
class_name EnemySpawn
extends Node3D
## Ponto de nascimento de monstros. O servidor (ou o solo) cria `count` monstros do tipo `kind`, espalhados no
## raio (spread), e cada um volta `respawn` segundos depois de morrer. Os números do monstro (vida, dano, loot)
## vêm do data/balance/enemies.json. `boss`: só nasce quando a missão chama (o rei goblin).

## Tipo do monstro (chave do enemies.json).
@export var kind := "slime"
## Quantos monstros este ponto mantém.
@export_range(0, 50) var count := 1
## Raio (m) em volta do ponto onde eles nascem; 0 = todos no centro.
@export_range(0.0, 40.0, 0.1) var radius := 0.0
## Segundos até um monstro morto voltar.
@export_range(1.0, 3600.0, 1.0) var respawn := 30.0
## Só nasce pela missão (o chefe).
@export var boss := false
## Assenta no relevo (a altura do nó vira distância até o chão).
@export var follow_ground := true

const GOLDEN := 2.399963229728653   # ângulo áureo (rad)


## Onde nasce cada um dos `count` monstros: o primeiro no centro e os outros numa espiral de ângulo áureo até
## o raio (espalha por igual e dá sempre o mesmo resultado, então servidor, solo e testes concordam).
static func spread(center: Vector3, count: int, radius: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in maxi(count, 0):
		if i == 0 or radius <= 0.0:
			out.append(center)
			continue
		var r := radius * sqrt(float(i) / float(count - 1))
		var a := i * GOLDEN
		out.append(center + Vector3(cos(a) * r, 0.0, sin(a) * r))
	return out
