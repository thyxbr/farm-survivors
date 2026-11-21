class_name EarthquakeRules
extends RefCounted
## Terremoto Devastador: contas puras (sem nó nem autoload), para os testes unitários: a expansão da onda de
## choque, quando ela chega em cada ponto, quem é atingido (uma vez por ativação, só dentro do raio), o desenho das
## rachaduras (radiais com ramificações), onde ficam as placas de pedra e as explosões secundárias, e a grade polar
## de alturas do chão que faz os efeitos seguirem o relevo.

## Curva da expansão: r(t) = R·(1 − (1 − t/T)^EASE_POW). Começa na velocidade configurada e freia até parar no
## raio máximo (a onda "perde força" no fim).
const EASE_POW := 1.6
## Grade polar de alturas: anéis do centro até a borda e fatias em volta.
const GRID_RINGS := 12
const GRID_SLICES := 48
## Altura de um ponto que foge demais dos vizinhos (pedra, tronco, telhado): troca pela dos vizinhos (m).
const GRID_OUTLIER := 0.6


## Quanto a onda leva do centro até o raio máximo `radius` começando a `speed` m/s (s).
static func expansion_time(radius: float, speed: float) -> float:
	return EASE_POW * maxf(radius, 0.0) / maxf(speed, 0.01)


## Raio da onda `t` s depois do impacto (m): 0 no impacto, `radius` no fim da expansão (e daí em diante).
static func wave_radius(t: float, radius: float, speed: float) -> float:
	if t <= 0.0 or radius <= 0.0:
		return 0.0
	var u := clampf(t / expansion_time(radius, speed), 0.0, 1.0)
	return radius * (1.0 - pow(1.0 - u, EASE_POW))


## Quando (s depois do impacto) a onda chega à distância `d` do centro; INF se `d` está fora do raio.
static func time_to_reach(d: float, radius: float, speed: float) -> float:
	if d <= 0.0:
		return 0.0
	if d > radius:
		return INF
	var u := 1.0 - pow(1.0 - d / radius, 1.0 / EASE_POW)
	return u * expansion_time(radius, speed)


## Distância no chão (sem a altura) entre o centro e `pos`.
static func flat_distance(center: Vector3, pos: Vector3) -> float:
	return Vector2(pos.x - center.x, pos.z - center.z).length()


## O inimigo (centro `pos`, raio do corpo `er`) está dentro do raio máximo da habilidade?
static func in_radius(center: Vector3, pos: Vector3, radius: float, er := 0.0) -> bool:
	return flat_distance(center, pos) <= radius + er


## A onda (raio atual `wave_r`) já chegou no corpo do inimigo?
static func reached(center: Vector3, pos: Vector3, wave_r: float, er := 0.0) -> bool:
	return flat_distance(center, pos) - er <= wave_r


## Alvos que a onda acabou de alcançar: dentro do raio máximo, com a frente da onda já no corpo e ainda não
## atingidos nesta ativação (`hit`, ids). Marca os escolhidos em `hit` (cada um leva dano uma vez só).
## `targets` = [{id, pos, radius}].
static func pick_reached(targets: Array, center: Vector3, wave_r: float, radius: float, hit: Dictionary) -> Array:
	var out := []
	for t in targets:
		var id = t.id
		if hit.has(id):
			continue
		var er := float(t.get("radius", 0.0))
		if not in_radius(center, t.pos, radius, er) or not reached(center, t.pos, wave_r, er):
			continue
		hit[id] = true
		out.append(t)
	return out


# ------------------------------------------------------------------- movimento do herói
## Fase da pose (KnightMoves.EARTHQUAKE_SLAM) `t` s depois do começo: 0..1 erguendo o escudo (sobe rápido e
## assenta no alto), 1..2 descendo (acelera até bater: a fase 2 é o instante do contato), 2..3 cravado no chão e
## 3..4 voltando à postura; 4 depois do fim.
static func pose_phase(t: float, windup: float, slam: float, hold: float, recover: float) -> float:
	if t <= 0.0:
		return 0.0
	if t < windup:
		var u := t / windup
		return 1.0 - (1.0 - u) * (1.0 - u)
	t -= windup
	if t < slam:
		var u := t / slam
		return 1.0 + u * u
	t -= slam
	if t < hold:
		return 2.0 + t / hold
	t -= hold
	if t < recover:
		var u := t / recover
		return 3.0 + u * u * (3.0 - 2.0 * u)
	return 4.0


# ------------------------------------------------------------------- rachaduras
## Rachaduras saindo do centro: `count` principais em volta (fatias iguais com desvio sorteado), cada uma andando
## para fora com zigue-zague (sem perder a direção radial) até `reach` m e abrindo ramificações (chance
## `branching` por trecho), mais finas e curtas. Mesma `seed` = mesmo desenho (o dono e as réplicas veem o mesmo
## chão). Cada rachadura: {points (Vector2, m a partir do centro), widths (m), main (é principal?)}; a distância de
## cada ponto ao centro diz quando a onda o revela.
static func crack_paths(count: int, reach: float, branching: float, width: float, seed: int) -> Array:
	var out := []
	if count <= 0 or reach <= 0.0:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var a0 := rng.randf() * TAU
	for i in count:
		var a := a0 + TAU * (float(i) + rng.randf_range(-0.32, 0.32)) / count
		# umas compridas, outras pela metade: fissuras maiores e menores
		var len := reach * (rng.randf_range(0.75, 1.0) if i % 3 != 2 else rng.randf_range(0.4, 0.65))
		var w := width * (rng.randf_range(0.85, 1.15) if i % 3 != 2 else rng.randf_range(0.55, 0.75))
		var start := Vector2.from_angle(a) * rng.randf_range(0.15, 0.45)
		_walk(out, rng, start, a, len, w, branching, 2, true)
	return out


static func _walk(out: Array, rng: RandomNumberGenerator, from: Vector2, a0: float, length: float, width: float,
		branching: float, depth: int, main: bool) -> void:
	var pts := PackedVector2Array([from])
	var ws := PackedFloat32Array([width])
	var p := from
	var a := a0
	var walked := 0.0
	var step := clampf(length / 14.0, 0.25, 0.7)
	var pending := []
	while walked < length:
		# zigue-zague com memória da direção original (a fissura não dá a volta)
		a = lerp_angle(a + rng.randf_range(-0.55, 0.55), a0, 0.3)
		var s := step * rng.randf_range(0.7, 1.3)
		p += Vector2.from_angle(a) * s
		walked += s
		var k := clampf(walked / length, 0.0, 1.0)
		pts.append(p)
		ws.append(width * lerpf(1.0, 0.18, k * k))
		if depth > 0 and k > 0.15 and k < 0.85 and rng.randf() < branching * 0.32:
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			pending.append([p, a + side * rng.randf_range(0.45, 0.95), (length - walked) * rng.randf_range(0.35, 0.7),
				width * lerpf(1.0, 0.18, k * k) * 0.6])
	out.append({"points": pts, "widths": ws, "main": main})
	for b in pending:
		if float(b[2]) > 0.3:
			_walk(out, rng, b[0], b[1], b[2], b[3], branching * 0.6, depth - 1, false)


## Placas de pedra levantadas ao lado das rachaduras principais: `count` pontos sorteados ao longo delas, para um
## lado ou outro da fissura, com o tamanho variando. Cada uma: {pos (Vector2), size, yaw (rad, o lado que fica no
## chão aponta para a rachadura), dist (m do centro)}. Em ordem de distância (a onda as levanta em sequência).
static func plate_spots(paths: Array, count: int, size: float, seed: int) -> Array:
	var out := []
	var mains := paths.filter(func(c: Dictionary) -> bool: return bool(c.main))
	if count <= 0 or mains.is_empty():
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 13 + 5
	for i in count:
		var c: Dictionary = mains[i % mains.size()]
		var pts: PackedVector2Array = c.points
		if pts.size() < 3:
			continue
		var j := rng.randi_range(1, pts.size() - 2)
		var dir := (pts[j + 1] - pts[j - 1]).normalized()
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var normal := Vector2(-dir.y, dir.x) * side
		var s := size * rng.randf_range(0.6, 1.35)
		var pos := pts[j] + normal * (float(c.widths[j]) * 0.5 + s * 0.45)
		out.append({"pos": pos, "size": s, "yaw": atan2(normal.x, normal.y), "dist": pos.length()})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.dist) < float(b.dist))
	return out


## Pontas das rachaduras principais mais compridas: onde as explosões secundárias acontecem. Até `count`
## pontos (Vector2), espalhados em volta (pega as mais longas e alterna). Em ordem de distância.
static func secondary_spots(paths: Array, count: int) -> Array:
	var tips := []
	for c in paths:
		if bool(c.main):
			var pts: PackedVector2Array = c.points
			tips.append(pts[pts.size() - 1])
	tips.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.length() > b.length())
	var out := tips.slice(0, mini(count, tips.size()))
	out.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.length() < b.length())
	return out


# ------------------------------------------------------------------- grade polar de alturas do chão
## Ponto (x, z a partir do centro, m) da grade: anel `ring` (0 = centro) e fatia `slice`.
static func grid_point(ring: int, slice: int, radius: float, rings := GRID_RINGS, slices := GRID_SLICES) -> Vector2:
	return Vector2.from_angle(TAU * float(slice) / slices) * (radius * float(ring) / rings)


## Altura do chão no ponto `p` (x, z a partir do centro) pela grade `h` (índice ring * slices + slice), com mistura
## entre os vizinhos. Fora da grade: a borda.
static func grid_height(h: PackedFloat32Array, p: Vector2, radius: float, rings := GRID_RINGS, slices := GRID_SLICES) -> float:
	if h.size() < (rings + 1) * slices:
		return 0.0
	var fr := clampf(p.length() / maxf(radius, 0.001) * rings, 0.0, float(rings))
	var fa := fposmod(atan2(p.y, p.x) / TAU * slices, float(slices))
	var r0 := mini(int(fr), rings - 1)
	var a0 := int(fa) % slices
	var a1 := (a0 + 1) % slices
	var u := fr - r0
	var v := fa - floorf(fa)
	var lo := lerpf(h[r0 * slices + a0], h[r0 * slices + a1], v)
	var hi := lerpf(h[(r0 + 1) * slices + a0], h[(r0 + 1) * slices + a1], v)
	return lerpf(lo, hi, u)


## Limpa a grade medida: um ponto que foge mais que GRID_OUTLIER da média dos vizinhos no anel e nos anéis
## vizinhos (um raio que caiu numa pedra ou num telhado) vira a média deles; NAN (raio sem chão) vira a altura do
## anel de dentro. O centro (anel 0) é um ponto só: todas as fatias ficam com a mediana.
static func clean_grid(h: PackedFloat32Array, center_h: float, rings := GRID_RINGS, slices := GRID_SLICES) -> PackedFloat32Array:
	var out := h.duplicate()
	for s in slices:
		out[s] = center_h
	for r in range(1, rings + 1):
		for s in slices:
			var i := r * slices + s
			if is_nan(out[i]):
				out[i] = out[(r - 1) * slices + s]
	for r in range(1, rings + 1):
		for s in slices:
			var nb := [out[r * slices + (s + 1) % slices], out[r * slices + (s + slices - 1) % slices], out[(r - 1) * slices + s]]
			if r < rings:
				nb.append(out[(r + 1) * slices + s])
			var sum := 0.0
			for x in nb:
				sum += float(x)
			var avg := sum / nb.size()
			if absf(out[r * slices + s] - avg) > GRID_OUTLIER:
				out[r * slices + s] = avg
	return out
