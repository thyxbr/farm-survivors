class_name EarthquakeGround
extends RefCounted
## Terremoto Devastador: a forma do chão em volta do impacto, para a onda, as rachaduras, as placas e as pedras
## seguirem o relevo (sem flutuar nem atravessar o terreno). Uma grade polar (EarthquakeRules.GRID_RINGS anéis x
## GRID_SLICES fatias) medida com raios para baixo na camada do cenário; a medição é feita aos poucos, um anel por
## quadro, enquanto o herói ergue o escudo (`measure_step`), e `finish` completa o que faltar no impacto. Alturas
## relativas ao centro; pontos que fogem dos vizinhos (pedra, tronco, telhado) são suavizados (EarthquakeRules.clean_grid).

const RAY_UP := 4.0
const RAY_DOWN := 7.0
const MASK := 1          ## camada do cenário (chão, pedras, construções)

var center := Vector3.ZERO
## Raio coberto pela grade (m): um pouco além do raio da onda, para a borda do anel e as pedras que caem longe.
var reach := 10.0
var heights := PackedFloat32Array()
var _raw := PackedFloat32Array()
var _next_ring := 0
var _done := false


func _init(c: Vector3, r: float) -> void:
	center = c
	reach = maxf(r, 0.5)
	var n := (EarthquakeRules.GRID_RINGS + 1) * EarthquakeRules.GRID_SLICES
	_raw.resize(n)
	_raw.fill(NAN)
	heights.resize(n)
	heights.fill(0.0)


## Mede `rings` anéis da grade (do centro para fora). Devolve true quando terminou.
func measure_step(space: PhysicsDirectSpaceState3D, rings := 1) -> bool:
	if _done:
		return true
	if space == null:
		_finish_clean()
		return true
	var S := EarthquakeRules.GRID_SLICES
	for _i in rings:
		if _next_ring > EarthquakeRules.GRID_RINGS:
			break
		var ring := _next_ring
		var count := 1 if ring == 0 else S
		for s in count:
			var p := EarthquakeRules.grid_point(ring, s, reach)
			var from := center + Vector3(p.x, RAY_UP, p.y)
			var q := PhysicsRayQueryParameters3D.create(from, center + Vector3(p.x, -RAY_DOWN, p.y), MASK)
			var hit := space.intersect_ray(q)
			var h: float = float(hit.position.y) - center.y if not hit.is_empty() else NAN
			if ring == 0:
				for k in S:
					_raw[k] = h
			else:
				_raw[ring * S + s] = h
		_next_ring += 1
	if _next_ring > EarthquakeRules.GRID_RINGS:
		_finish_clean()
	else:
		_partial()
	return _done


## Medição pela metade: os anéis medidos valem já (sem chão: o de dentro) e os de fora repetem o último medido,
## para os efeitos da carga (perto do centro) já seguirem o chão.
func _partial() -> void:
	var S := EarthquakeRules.GRID_SLICES
	for r in EarthquakeRules.GRID_RINGS + 1:
		for s in S:
			var i := r * S + s
			if r >= _next_ring:
				heights[i] = heights[(r - 1) * S + s] if r > 0 else 0.0
			elif is_nan(_raw[i]):
				heights[i] = heights[(r - 1) * S + s] if r > 0 else 0.0
			else:
				heights[i] = _raw[i]


## Mede o que faltar de uma vez (impacto antes da medição terminar).
func finish(space: PhysicsDirectSpaceState3D) -> void:
	while not _done:
		measure_step(space, EarthquakeRules.GRID_RINGS + 1)


func is_done() -> bool:
	return _done


func _finish_clean() -> void:
	var c0: float = _raw[0] if not is_nan(_raw[0]) else 0.0
	for i in _raw.size():
		if i < EarthquakeRules.GRID_SLICES and is_nan(_raw[i]):
			_raw[i] = c0
	heights = EarthquakeRules.clean_grid(_raw, c0)
	_done = true


## Altura do chão (relativa ao centro) no ponto `p` (x, z a partir do centro, m).
func height_at(p: Vector2) -> float:
	return EarthquakeRules.grid_height(heights, p, reach)


## Ponto no chão (relativo ao centro) em `p`, erguido `lift` m.
func local_at(p: Vector2, lift := 0.0) -> Vector3:
	return Vector3(p.x, height_at(p) + lift, p.y)


## Inclinação do chão em `p` (normal, aproximada pelos vizinhos).
func normal_at(p: Vector2, step := 0.4) -> Vector3:
	var hx := height_at(p + Vector2(step, 0.0)) - height_at(p - Vector2(step, 0.0))
	var hz := height_at(p + Vector2(0.0, step)) - height_at(p - Vector2(0.0, step))
	return Vector3(-hx, 2.0 * step, -hz).normalized()
