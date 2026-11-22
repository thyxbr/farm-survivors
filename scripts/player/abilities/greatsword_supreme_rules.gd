class_name GreatswordSupremeRules
extends RefCounted
## Lâmina Suprema: contas puras (sem nó nem autoload), para os testes unitários: em que fase da animação a habilidade
## está e quem fica dentro da área do golpe (o ponto do golpe à frente mais o caminho da lâmina até ele).

## Fases, na ordem de KnightMovesGreatCast.TRACKS (RAISE, HOLD, SLASH, KNEEL, RISE).
const PHASE_COUNT := 5


## Duração de cada fase (s) a partir dos tempos da configuração: [erguer, carga, corte, ajoelhado, levantar].
static func durations(raise: float, charge: float, slash: float, kneel: float, rise: float) -> Array[float]:
	var d: Array[float] = [raise, charge, slash, kneel, rise]
	for i in d.size():
		d[i] = maxf(d[i], 0.001)
	return d


## Fase e progresso nela (0..1) no instante `t` (s desde o começo). Depois do fim: a última fase em 1.
static func phase_at(t: float, durs: Array[float]) -> Vector2:
	var acc := 0.0
	for i in durs.size():
		if t < acc + durs[i]:
			return Vector2(i, clampf((t - acc) / durs[i], 0.0, 1.0))
		acc += durs[i]
	return Vector2(durs.size() - 1, 1.0)


## O ponto `pos` (corpo de raio `er`) está na área do golpe? Conta no chão (a altura não importa): dentro do raio
## `radius` do ponto do golpe `center`, ou a até `half_width` do segmento entre o herói (`origin`) e esse ponto.
static func in_area(origin: Vector3, center: Vector3, pos: Vector3, radius: float, half_width: float, er := 0.0) -> bool:
	var p := Vector2(pos.x, pos.z)
	var c := Vector2(center.x, center.z)
	if p.distance_to(c) <= radius + er:
		return true
	if half_width <= 0.0:
		return false
	var o := Vector2(origin.x, origin.z)
	var seg := c - o
	var l2 := seg.length_squared()
	var u := 0.0 if l2 < 0.000001 else clampf((p - o).dot(seg) / l2, 0.0, 1.0)
	return p.distance_to(o + seg * u) <= half_width + er


## Filtra os alvos de uma ativação: só os ainda não atingidos (`hit`, ids), dentro da área; marca os escolhidos em
## `hit` (cada um leva dano uma vez). `targets` = [{id, pos, radius}].
static func pick_targets(targets: Array, origin: Vector3, center: Vector3, radius: float, half_width: float, hit: Dictionary) -> Array:
	var out := []
	for t in targets:
		if hit.has(t.id):
			continue
		if not in_area(origin, center, t.pos, radius, half_width, float(t.get("radius", 0.0))):
			continue
		hit[t.id] = true
		out.append(t)
	return out


## Peso da volta à guarda no fim da fase de levantar (0 até `from`, 1 no fim).
static func back_weight(rise_u: float, from := 0.6) -> float:
	return clampf((rise_u - from) / maxf(1.0 - from, 0.001), 0.0, 1.0)
