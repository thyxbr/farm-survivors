class_name FootprintRules
extends RefCounted
## Regras puras das pegadas (sem cena): onde cada pé pisa e quanto tempo a marca dura com o chão
## de cada jeito. O desenho fica em scripts/world/footprints.gd e assets/shaders/footprint.gdshader.

## Distância andada entre uma pegada e a seguinte (pé esquerdo, depois o direito...).
const STRIDE := 0.72
## Distância de cada pé até a linha do meio do caminho.
const GAUGE := 0.11
## Quanto tempo (s) a marca fica: chão seco (mal se vê), lama e neve funda.
const LIFE_DRY := 14.0
const LIFE_MUD := 45.0
const LIFE_SNOW := 120.0
## Com neve caindo forte, a pegada enche de novo em ~LIFE_FILL segundos.
const LIFE_FILL := 35.0


## Ponto do chão onde o pé de `side` (-1 esquerdo, 1 direito) pisa, andando de `pos` na direção
## `dir` (xz, não precisa estar normalizada). Só desloca para o lado, o y fica o de `pos`.
static func foot_pos(pos: Vector3, dir: Vector2, side: int) -> Vector3:
	var d := dir.normalized() if dir.length_squared() > 1e-6 else Vector2(0, 1)
	var right := Vector2(-d.y, d.x)
	return pos + Vector3(right.x, 0.0, right.y) * GAUGE * float(side)


## Ângulo (y) que vira o comprimento da pegada (+z local) para a direção do passo.
static func yaw_of(dir: Vector2) -> float:
	return atan2(dir.x, dir.y)


## Vida da pegada (s) com o chão assim: cover = neve acumulada, snowing = neve caindo, wet = lama.
static func life(cover: float, snowing: float, wet: float) -> float:
	var base := lerpf(LIFE_DRY, LIFE_MUD, clampf(wet, 0.0, 1.0))
	var snow := clampf(cover * 1.6, 0.0, 1.0)
	var deep := lerpf(LIFE_SNOW, LIFE_FILL, clampf(snowing, 0.0, 1.0))
	return lerpf(base, deep, snow)
