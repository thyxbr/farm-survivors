class_name SeismicSpikesRules
extends RefCounted
## Estacas Sísmicas: contas puras (sem nó nem autoload), para os testes unitários: fases da animação do herói, o
## avanço das rachaduras (fase 1), a frente do tremor (fase 2: cada inimigo leva o dano uma vez, quando ela chega
## nele) e o sacolejo do herói enquanto a terra treme.

## Fases da pose, na ordem: erguer a espada de ponta para baixo, cravar, segurar cravada, arrancar, voltar à guarda.
enum { WINDUP, PLUNGE, HOLD, PULL, RECOVER }
const PHASES := 5
## O tremor desacelera perto da borda (como a onda do Terremoto, EarthquakeRules.EASE_POW).
const EASE_POW := 1.6


## Duração de cada fase (s), nunca zero: [erguer, cravar, segurar, arrancar, voltar].
static func durations(windup: float, plunge: float, hold: float, pull: float, recover: float) -> Array[float]:
	var d: Array[float] = [windup, plunge, hold, pull, recover]
	for i in d.size():
		d[i] = maxf(d[i], 0.001)
	return d


## Fase e progresso nela (0..1) no instante `t` (s desde o começo). Antes de 0: a primeira em 0; depois do fim: a
## última em 1.
static func phase_at(t: float, durs: Array[float]) -> Vector2:
	if t <= 0.0:
		return Vector2(0, 0.0)
	var acc := 0.0
	for i in durs.size():
		if t < acc + durs[i]:
			return Vector2(i, clampf((t - acc) / durs[i], 0.0, 1.0))
		acc += durs[i]
	return Vector2(durs.size() - 1, 1.0)


## Fase 1: quanto das rachaduras já apareceu (0 = nada, 1 = até o raio) `s` s depois do impacto. Rápido no começo
## (o golpe) e assentando na borda.
static func crack_reveal(s: float, crack_time: float) -> float:
	if s <= 0.0:
		return 0.0
	var u := clampf(s / maxf(crack_time, 0.001), 0.0, 1.0)
	return 1.0 - pow(1.0 - u, 2.2)


## Fase 2: raio (m) da frente do tremor `s` s depois de ele começar; chega a `radius` em `propagate` s.
static func quake_front(s: float, radius: float, propagate: float) -> float:
	if s < 0.0 or radius <= 0.0:
		return 0.0
	if propagate <= 0.0:
		return radius
	var u := clampf(s / propagate, 0.0, 1.0)
	return radius * (1.0 - pow(1.0 - u, EASE_POW))


## Quando (s depois do começo do tremor) a frente chega à distância `d` do centro; INF fora do raio. Inversa de
## quake_front.
static func time_to_reach(d: float, radius: float, propagate: float) -> float:
	if d <= 0.0:
		return 0.0
	if d > radius:
		return INF
	var u := 1.0 - pow(1.0 - d / radius, 1.0 / EASE_POW)
	return u * maxf(propagate, 0.0)


## No plano do chão (a altura não importa): o corpo de raio `er` em `pos` está dentro do raio `radius` de `center`?
static func in_radius(center: Vector3, pos: Vector3, radius: float, er := 0.0) -> bool:
	return Vector2(pos.x - center.x, pos.z - center.z).length() <= radius + er


## Os alvos que a frente do tremor (raio `front`) acabou de alcançar: dentro de `radius`, ainda fora de `hit` (ids).
## Marca os escolhidos em `hit` (cada um leva dano uma vez). `targets` = [{id, pos, radius}].
static func pick_reached(targets: Array, center: Vector3, front: float, radius: float, hit: Dictionary) -> Array:
	var out := []
	for t in targets:
		if hit.has(t.id):
			continue
		var er := float(t.get("radius", 0.0))
		if not in_radius(center, t.pos, radius, er) or not in_radius(center, t.pos, front, er):
			continue
		hit[t.id] = true
		out.append(t)
	return out


## A ponta da espada fica em `tip` (espaço do modelo) e a mão direita (junto da guarda) a `length` m dela, na altura
## `hand_z` à frente: a mão fica em cima da ponta, na distância certa (a lâmina não estica nem encolhe).
static func hand_over_tip(tip: Vector3, length: float, hand_z: float) -> Vector3:
	var dz := hand_z - tip.z
	var dy := sqrt(maxf(length * length - dz * dz, 0.0))
	return Vector3(tip.x, tip.y + dy, hand_z)


## Sacolejo do herói (rad) no instante `t` enquanto a terra treme, com força `amp` (0..1): soma de senos em frequências
## que não batem (parece aleatório, mas é igual no dono e nas réplicas e não pula de um quadro para o outro).
## x = para a frente/trás (body_x), y = giro (twist).
static func quake_wobble(t: float, amp: float) -> Vector2:
	if amp <= 0.0:
		return Vector2.ZERO
	var x := sin(t * 41.0) * 0.6 + sin(t * 67.0 + 1.3) * 0.4
	var y := sin(t * 53.0 + 0.7) * 0.6 + sin(t * 29.0 + 2.1) * 0.4
	return Vector2(x, y) * 0.035 * clampf(amp, 0.0, 1.0)
