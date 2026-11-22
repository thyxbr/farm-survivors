class_name DragSlashRules
extends RefCounted
## Corte do Abismo (montante, tecla 2): contas puras (sem nó nem autoload), para os testes unitários: o perfil de
## velocidade da corrida, quando ela para, a trajetória da lâmina no corte de baixo para cima e quem fica dentro do corte
## e das garras.

## Fases da habilidade no herói.
enum { WINDUP, DASH, SLASH, DONE }


## Velocidade da corrida (m/s) depois de `t` s correndo, com `left` m ainda por correr: arranca em `ramp` s até `top` e,
## nos últimos `brake` m, freia até ~45% (o pé de apoio do corte já chega desacelerando, sem parar de uma vez).
static func dash_speed(t: float, left: float, top: float, ramp := 0.12, brake := 1.2) -> float:
	var up := smoothstep(0.0, maxf(ramp, 0.001), t)
	var down := lerpf(0.45, 1.0, smoothstep(0.0, maxf(brake, 0.001), left))
	return top * lerpf(0.35, 1.0, up) * down


## Distância (m, no chão) até o inimigo mais perto no corredor à frente: até `reach` m de `origin` na direção `fwd`
## (normalizada, no chão) e a até `half_width` m do eixo (mais o raio dele). INF se não houver nenhum.
## `targets` = [{pos, radius}].
static func nearest_ahead(origin: Vector3, fwd: Vector3, targets: Array, reach: float, half_width: float) -> float:
	var best := INF
	var f := Vector2(fwd.x, fwd.z).normalized()
	var o := Vector2(origin.x, origin.z)
	for t in targets:
		var p := Vector2((t.pos as Vector3).x, (t.pos as Vector3).z) - o
		var along := p.dot(f)
		var r := float(t.get("radius", 0.0))
		if along < -r or along - r > reach:
			continue
		if absf(p.cross(f)) > half_width + r:
			continue
		best = minf(best, maxf(along - r, 0.0))
	return best


## A corrida para agora? Completou a distância, bateu de frente numa parede ou chegou perto de um inimigo no caminho.
static func dash_should_stop(traveled: float, dist: float, ahead: float, stop_at: float, wall: bool) -> bool:
	return wall or traveled >= dist - 0.02 or ahead <= stop_at


## O ponto `pos` (corpo de raio `er`) está no arco do corte? No chão: a até `radius` m de `origin` e a até `half_angle`
## (graus) da direção `fwd`; colado no herói (dentro de `er` + 0,6 m) sempre conta.
static func in_slash(origin: Vector3, fwd: Vector3, pos: Vector3, radius: float, half_angle: float, er := 0.0) -> bool:
	var to := Vector2(pos.x - origin.x, pos.z - origin.z)
	var d := to.length()
	if d > radius + er:
		return false
	if d <= er + 0.6:
		return true
	var f := Vector2(fwd.x, fwd.z).normalized()
	var ang := rad_to_deg(absf(f.angle_to(to)))
	return ang <= half_angle + rad_to_deg(asin(clampf(er / d, 0.0, 1.0)))


## Centros (no chão, altura de `origin`) das `count` garras: em fila à frente, a primeira a `first` m e as outras a cada
## `step` m, alternando `spread` m para os lados (a do meio no eixo).
static func claw_centers(origin: Vector3, fwd: Vector3, count: int, first: float, step: float, spread: float) -> Array[Vector3]:
	var f := Vector3(fwd.x, 0.0, fwd.z).normalized()
	var side := f.cross(Vector3.UP)
	var out: Array[Vector3] = []
	for i in count:
		var lat := 0.0 if i == 0 else spread * (1.0 if i % 2 == 1 else -1.0)
		out.append(origin + f * (first + step * i) + side * lat)
	return out


## O ponto está dentro da garra de centro `center` (círculo de raio `radius` no chão)?
static func in_claw(center: Vector3, pos: Vector3, radius: float, er := 0.0) -> bool:
	return Vector2(pos.x - center.x, pos.z - center.z).length() <= radius + er


## Filtra os alvos com `test(alvo) -> bool`: só os ainda não atingidos (`hit`, ids), marcando os escolhidos em `hit`
## (cada um leva o golpe uma vez). `targets` = [{id, pos, radius}].
static func pick(targets: Array, test: Callable, hit: Dictionary) -> Array:
	var out := []
	for t in targets:
		if hit.has(t.id) or not test.call(t):
			continue
		hit[t.id] = true
		out.append(t)
	return out


# ------------------------------------------------------------------ trajetória da lâmina (espaço do modelo)
## A lâmina é dada por azimute `az` (rad, 0 = à frente +Z, -PI/2 = para a direita do herói, que é -X) e por elevação
## `el` (rad a partir de apontar para baixo: 0 = para baixo, PI/2 = na horizontal, PI = para cima).
static func blade_dir(az: float, el: float) -> Vector3:
	return Vector3(sin(az) * sin(el), -cos(el), cos(az) * sin(el))


## A menor elevação que mantém a ponta acima do chão: mão (o cabo) a `hand_y` m, chão a `ground_y`, lâmina de `length` m
## das mãos à ponta. Com a mão mais alta que a lâmina, 0 (pode apontar reto para baixo).
static func min_elevation(hand_y: float, ground_y: float, length: float) -> float:
	return acos(clampf((hand_y - ground_y) / maxf(length, 0.001), -1.0, 1.0))


## Interpola chaves [t, valor] (t crescente) com Catmull-Rom uniforme entre a chave anterior e a seguinte. `v` é float
## ou Vector3.
static func spline(keys: Array, t: float):
	var n := keys.size()
	if n == 0:
		return 0.0
	if t <= float(keys[0][0]):
		return keys[0][1]
	if t >= float(keys[n - 1][0]):
		return keys[n - 1][1]
	var i := 0
	while i < n - 2 and t > float(keys[i + 1][0]):
		i += 1
	var t0 := float(keys[i][0])
	var t1 := float(keys[i + 1][0])
	var u := clampf((t - t0) / maxf(t1 - t0, 0.0001), 0.0, 1.0)
	var p0 = keys[maxi(i - 1, 0)][1]
	var p1 = keys[i][1]
	var p2 = keys[i + 1][1]
	var p3 = keys[mini(i + 2, n - 1)][1]
	var u2 := u * u
	var u3 := u2 * u
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3)
