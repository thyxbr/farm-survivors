class_name GreatswordSpinRules
extends RefCounted
## Ciclone de Aço: contas puras (sem nó nem autoload), para os testes unitários: a fase, a velocidade e o ângulo do
## giro em cada instante e quem leva um corte agora (alcance + intervalo por alvo).

## Fases, na ordem das durações.
enum Phase { STANCE, ACCEL, SPIN, DECEL, RECOVER }
const PHASE_COUNT := 5


## Duração de cada fase (s): [postura, aceleração, giro, desaceleração, volta].
static func durations(stance: float, accel: float, spin: float, decel: float, recover: float) -> Array[float]:
	var d: Array[float] = [stance, accel, spin, decel, recover]
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


## Velocidade angular máxima (rad/s) para fechar `turns` voltas: a aceleração e a desaceleração (curvas suaves)
## andam metade do que andariam na velocidade máxima.
static func max_speed(durs: Array[float], turns: int) -> float:
	return float(turns) * TAU / (durs[Phase.ACCEL] * 0.5 + durs[Phase.SPIN] + durs[Phase.DECEL] * 0.5)


## Fração da velocidade máxima (0..1) no instante `t`: sobe suave na aceleração e desce suave até parar.
static func speed_frac(t: float, durs: Array[float]) -> float:
	var ph := phase_at(t, durs)
	match int(ph.x):
		Phase.ACCEL:
			return smoothstep(0.0, 1.0, ph.y)
		Phase.SPIN:
			return 1.0
		Phase.DECEL:
			return 1.0 - smoothstep(0.0, 1.0, ph.y)
	return 0.0


## Ângulo girado (rad) até o instante `t`: a integral de speed_frac. No fim é exatamente `turns` voltas.
static func angle(t: float, durs: Array[float], turns: int) -> float:
	var w := max_speed(durs, turns)
	var ph := phase_at(t, durs)
	var u := ph.y
	var ta := durs[Phase.ACCEL]
	match int(ph.x):
		Phase.STANCE:
			return 0.0
		Phase.ACCEL:
			# integral de smoothstep (3u² - 2u³): u³ - u⁴/2
			return w * ta * (u * u * u - u * u * u * u * 0.5)
		Phase.SPIN:
			return w * (ta * 0.5 + durs[Phase.SPIN] * u)
		Phase.DECEL:
			return w * (ta * 0.5 + durs[Phase.SPIN] + durs[Phase.DECEL] * (u - u * u * u + u * u * u * u * 0.5))
	return float(turns) * TAU


## Quanto o tronco está inclinado para trás (0..1) no instante `t`: nada na postura (se houver), inclina junto com a
## aceleração, fica no giro e volta ao normal da metade da desaceleração até a metade da volta à guarda.
static func lean_weight(t: float, durs: Array[float]) -> float:
	var accel_at := durs[Phase.STANCE]
	var decel_at := accel_at + durs[Phase.ACCEL] + durs[Phase.SPIN]
	var recover_at := decel_at + durs[Phase.DECEL]
	var rise := smoothstep(accel_at, accel_at + durs[Phase.ACCEL], t)
	var fall := smoothstep(decel_at + durs[Phase.DECEL] * 0.5, recover_at + durs[Phase.RECOVER] * 0.5, t)
	return rise * (1.0 - fall)


## O ponto `pos` (corpo de raio `er`) está no alcance do giro em volta de `center`? Conta no chão, com limite de altura.
static func in_reach(center: Vector3, pos: Vector3, radius: float, height: float, er := 0.0) -> bool:
	if absf(pos.y - center.y) > height:
		return false
	return Vector2(pos.x - center.x, pos.z - center.z).length() <= radius + er


## Quem leva um corte agora (`now`, s): no alcance e sem corte nos últimos `interval` s (`last_hit`: id -> instante do
## último corte; os escolhidos são marcados). `targets` = [{id, pos, radius}].
static func pick_targets(targets: Array, center: Vector3, radius: float, height: float, now: float, interval: float,
		last_hit: Dictionary) -> Array:
	var out := []
	for t in targets:
		if last_hit.has(t.id) and now - float(last_hit[t.id]) < interval - 0.0001:
			continue
		if not in_reach(center, t.pos, radius, height, float(t.get("radius", 0.0))):
			continue
		last_hit[t.id] = now
		out.append(t)
	return out
