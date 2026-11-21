class_name HammerRules
extends RefCounted
## Martelo de Energia: contas puras (sem nó nem autoload), para os testes unitários: a queda com aceleração, a
## distribuição das crateras em volta do impacto e quem está dentro do raio de dano.


## Tempo para cair `h` m começando a `v0` m/s com aceleração `a` m/s² (h = v0·t + a·t²/2).
static func fall_time(h: float, v0: float, a: float) -> float:
	if h <= 0.0:
		return 0.0
	if a <= 0.0001:
		return h / maxf(v0, 0.01)
	return (-v0 + sqrt(v0 * v0 + 2.0 * a * h)) / a


## Quanto já caiu `t` s depois de começar a queda (m).
static func fall_distance(t: float, v0: float, a: float) -> float:
	t = maxf(t, 0.0)
	return v0 * t + 0.5 * a * t * t


## Crateras em volta do centro: `count` pontos (x, z, em m) cobrindo o disco entre `min_d` e `max_d`, em
## distribuição circular mas sem a mesma distância para todas: os ângulos são fatias iguais com um desvio
## sorteado e as distâncias se alternam entre um anel de dentro e um de fora, também com desvio. Mesma
## `seed` = mesmas crateras (o dono e as réplicas veem o mesmo chão). Em ordem de distância (a onda se espalha).
static func crater_layout(count: int, min_d: float, max_d: float, seed: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if count <= 0:
		return out
	max_d = maxf(max_d, 0.1)
	min_d = clampf(min_d, 0.0, max_d)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var step := TAU / count
	var a0 := rng.randf() * TAU
	for i in count:
		var a := a0 + step * i + rng.randf_range(-0.32, 0.32) * step
		# anéis alternados (dentro/fora) para cobrir o disco todo, com desvio para não ficar um círculo perfeito
		var ring := 0.62 if (i % 2 == 0) else 0.95
		if count < 5:
			ring = 0.8
		var u := clampf(ring + rng.randf_range(-0.12, 0.08), 0.0, 1.0)
		var d := lerpf(min_d, max_d, u)
		out.append(Vector2(cos(a), sin(a)) * d)
	out.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.length() < q.length())
	return out


## O inimigo (centro `pos`, raio `er`) está no alcance do martelo caído em `center` com raio `radius`? Conta a
## distância no chão (a altura não importa: o golpe é no chão) e o corpo do inimigo encostando na borda.
static func in_radius(center: Vector3, pos: Vector3, radius: float, er := 0.0) -> bool:
	return Vector2(pos.x - center.x, pos.z - center.z).length() <= radius + er


## Filtra os alvos de uma ativação: só inimigos ainda não atingidos (`hit`, ids de instância), dentro do raio.
## Marca os escolhidos em `hit`, para cada um levar dano uma vez só. `targets` = [{id, pos, radius}].
static func pick_targets(targets: Array, center: Vector3, radius: float, hit: Dictionary) -> Array:
	var out := []
	for t in targets:
		var id = t.id
		if hit.has(id):
			continue
		if not in_radius(center, t.pos, radius, float(t.get("radius", 0.0))):
			continue
		hit[id] = true
		out.append(t)
	return out
