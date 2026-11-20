class_name ThrowRules
extends RefCounted
## Arremesso de dinamite (Kobold Lanterneiro): onde cai, o arco do voo e como a distância vai no snapshot de rede.
## Puro: sem autoloads (roda no runner de unitários).

## O ponto de queda vai nos bits altos de `flags` do snapshot, relativo à posição do monstro: distância em passos
## de 0,25 m (bits 2..9) e ângulo no plano em 256 passos (bits 10..17). Bits 0 e 1 são lento e enfurecido.
## Tudo abaixo de 2^24, então sobrevive ao float32 do snapshot.
const DIST_SHIFT := 2
const ANGLE_SHIFT := 10
const DIST_STEP := 0.25
const MAX_STEPS := 255


## Ponto de queda no chão de quem joga (y = from.y), na direção de `to`, a no máximo `max_range`.
static func target(from: Vector3, to: Vector3, max_range: float) -> Vector3:
	var d := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if d.length() > max_range:
		d = d.normalized() * max_range
	return Vector3(from.x + d.x, from.y, from.z + d.z)


static func pack_flags(flags: int, offset: Vector3) -> int:
	var flat := Vector2(offset.x, offset.z)
	var steps := clampi(roundi(flat.length() / DIST_STEP), 0, MAX_STEPS)
	var ang := posmod(roundi(flat.angle() / TAU * 256.0), 256)
	return (flags & ((1 << DIST_SHIFT) - 1)) | (steps << DIST_SHIFT) | (ang << ANGLE_SHIFT)


static func unpack_offset(flags: int) -> Vector3:
	var dist := float((flags >> DIST_SHIFT) & MAX_STEPS) * DIST_STEP
	var ang := float((flags >> ANGLE_SHIFT) & 255) / 256.0 * TAU
	return Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)


## Posição da dinamite no voo (t de 0 a 1): reta no chão de `from` a `to`, mais uma parábola com pico `height`.
static func arc(from: Vector3, to: Vector3, t: float, height: float) -> Vector3:
	t = clampf(t, 0.0, 1.0)
	return from.lerp(to, t) + Vector3.UP * (4.0 * height * t * (1.0 - t))
