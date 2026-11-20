class_name BurrowRules
extends RefCounted
## Cavar e emergir (Toupeira-Broca e Mãe-Verme): quando afundar, como andar por baixo da terra, quando sair e
## quando não pode ser atingida. Puro: sem autoloads (roda no runner de unitários).
## `cfg` são as chaves do enemies.json: dig_min, dig_max (m), surface_secs (janela vulnerável na superfície) e
## dig_max_secs (tempo máximo debaixo da terra).

## Distância (m, no plano) em que conta como "chegou" debaixo do alvo.
const ARRIVE := 0.6


## Afunda quando o alvo está a média distância e já passou a janela na superfície.
static func should_dig(dist: float, surface_t: float, cfg: Dictionary) -> bool:
	return dist >= float(cfg.dig_min) and dist <= float(cfg.dig_max) and surface_t >= float(cfg.surface_secs)


## Um passo debaixo da terra em linha reta até o alvo, no plano (mantém a altura), sem passar dele.
static func dig_step(pos: Vector3, target: Vector3, speed: float, delta: float) -> Vector3:
	var d := Vector3(target.x - pos.x, 0.0, target.z - pos.z)
	var step := speed * delta
	if d.length() <= step:
		return Vector3(target.x, pos.y, target.z)
	return pos + d.normalized() * step


## Sai quando chegou debaixo do alvo (o corpo, de raio cfg.radius, encosta no dele antes do centro chegar) ou
## quando esgotou o tempo debaixo da terra.
static func should_emerge(pos: Vector3, target: Vector3, dig_t: float, cfg: Dictionary) -> bool:
	var arrive := ARRIVE + float(cfg.get("radius", 0.0))
	return Vector2(target.x - pos.x, target.z - pos.z).length() <= arrive or dig_t >= float(cfg.dig_max_secs)


## Ponto limitado ao retângulo de meio-tamanho `half_size` (x, z) em volta de `home` (o fosso da Mãe-Verme).
static func clamp_to_leash(p: Vector3, home: Vector3, half_size: Vector2) -> Vector3:
	return Vector3(clampf(p.x, home.x - half_size.x, home.x + half_size.x), p.y,
		clampf(p.z, home.z - half_size.y, home.z + half_size.y))


## Escondida debaixo da terra (não leva dano nem atordoamento): cavando, ou subindo antes do golpe de emergir.
static func hidden(state: String, attack_kind: String, hit_done: bool) -> bool:
	return state == "burrow" or (state == "attack" and attack_kind == "emerge" and not hit_done)
