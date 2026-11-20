class_name BossRules
extends RefCounted
## Habilidades de chefe da Mãe-Verme: qual golpe vem agora, a Onda de Cristais (anéis que abrem a partir dela),
## o Desmoronamento (pedras caindo em pontos sorteados), as Poças de Ácido e a Fúria (mergulhos seguidos).
## Puro: sem autoloads (roda no runner de unitários). O servidor e o cliente chegam aos mesmos pontos pela semente.

## Onda de Cristais: anéis de `QUAKE_WIDTH` m, o primeiro a QUAKE_R0 m e cada um QUAKE_STEP m mais longe e
## QUAKE_DT s mais tarde; entre dois anéis sobra um vão seguro.
const QUAKE_RINGS := 4
const QUAKE_R0 := 3.5
const QUAKE_STEP := 4.0
const QUAKE_WIDTH := 2.0
const QUAKE_T0 := 1.0
const QUAKE_DT := 0.5
## Fúria (abaixo de 50%): mergulhos seguidos, sem golpes na superfície entre eles.
const FURY_DIVES := 3
## Desmoronamento: pedras sorteadas em volta do chefe (além de uma sob cada jogador).
const ROCKS := 6
const ROCK_SPREAD := 12.0
## Semente do desmoronamento nos bits 2..17 de `flags` do snapshot (0 e 1 são lento e enfurecido).
const SEED_SHIFT := 2


## O golpe da vez na superfície. `hits` = golpes já dados desde que saiu do chão; `specials` = especiais já
## feitos na luta. O 2º golpe de cada subida é um especial (Onda e Desmoronamento, alternados); os outros são
## mordida perto ou, longe, o cuspe (1º golpe) e as Poças de Ácido (3º em diante).
static func worm_attack(hits: int, specials: int, dist: float, reach: float) -> String:
	if hits == 1:
		return "quake" if specials % 2 == 0 else "rockfall"
	if dist <= reach:
		return "slam"
	return "shoot" if hits == 0 else "acid_rain"


## Anel `i` da Onda: {r: raio do meio (m), w: largura (m), t: segundos depois do início do golpe}.
static func quake_ring(i: int) -> Dictionary:
	return {"r": QUAKE_R0 + QUAKE_STEP * i, "w": QUAKE_WIDTH, "t": QUAKE_T0 + QUAKE_DT * i}


## A distância `dist` (no plano, do centro) está dentro do anel `i`.
static func in_quake_ring(dist: float, i: int) -> bool:
	var q := quake_ring(i)
	return absf(dist - float(q.r)) <= float(q.w) / 2.0


## Pontos do Desmoronamento sorteados pela semente, até `spread` m em volta de `center` (na altura dele).
static func rockfall_points(seed: int, center: Vector3, spread: float, n: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out := []
	for i in n:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * spread
		out.append(Vector3(center.x + cos(a) * d, center.y, center.z + sin(a) * d))
	return out


## Poças de Ácido: a primeira no alvo e duas abrindo 30° para cada lado, um pouco mais perto do chefe.
static func acid_points(origin: Vector3, target: Vector3) -> Array:
	var to := Vector3(target.x - origin.x, 0.0, target.z - origin.z)
	var out := [target]
	for s in [-1.0, 1.0]:
		var v := to.rotated(Vector3.UP, s * deg_to_rad(30.0)) * 0.8
		out.append(Vector3(origin.x + v.x, target.y, origin.z + v.z))
	return out


## Golpes na superfície antes de mergulhar: zero enquanto houver mergulhos de fúria pendentes.
static func surface_attacks(normal: int, fury_left: int) -> int:
	return 0 if fury_left > 0 else normal


## Índice do ponto mais perto de `origin` no plano (a altura não conta); -1 se a lista está vazia. A Mãe-Verme
## escolhe o alvo do cuspe e da mordida assim, só entre quem está dentro do fosso.
static func nearest_index(origin: Vector3, points: Array) -> int:
	var best := -1
	var best_d := INF
	for i in points.size():
		var p: Vector3 = points[i]
		var d := Vector2(p.x - origin.x, p.z - origin.z).length()
		if d < best_d:
			best_d = d
			best = i
	return best


## Índice do ponto mais distante de `origin` no plano (a altura não conta); -1 se a lista está vazia. As Poças de
## Ácido e o Mergulho miram quem está mais longe dentro do fosso: quem ataca de longe também fica sob pressão.
static func farthest_index(origin: Vector3, points: Array) -> int:
	var best := -1
	var best_d := -1.0
	for i in points.size():
		var p: Vector3 = points[i]
		var d := Vector2(p.x - origin.x, p.z - origin.z).length()
		if d > best_d:
			best_d = d
			best = i
	return best


static func pack_seed(flags: int, seed: int) -> int:
	return (flags & ((1 << SEED_SHIFT) - 1)) | ((seed & 0xFFFF) << SEED_SHIFT)


static func unpack_seed(flags: int) -> int:
	return (flags >> SEED_SHIFT) & 0xFFFF
