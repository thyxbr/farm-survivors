class_name RockDebris
extends MultiMeshInstance3D
## Terremoto Devastador: fragmentos de pedra (scenes/vfx/earthquake/rock_debris.tscn), num MultiMesh só, simulados
## aqui (sem física do motor): cada pedra sai com tamanho, direção, velocidade e giro sorteados, sobe, perde
## velocidade, cai, quica no chão de verdade (EarthquakeGround: segue o relevo), fica um tempo parada e afunda se
## desfazendo (eq_stone.gdshader, INSTANCE_CUSTOM.y). As mais novas ainda brilham com a energia (INSTANCE_CUSTOM.x).
## `burst` lança um punhado (impacto, passagem da onda, explosões secundárias); `tremble` põe pedrinhas pulando
## no chão enquanto o herói ergue o escudo, e `launch_trembling` arremessa essas no impacto.

const CAPACITY := 480
const GRAVITY := 24.0
const COOL_TIME := 1.3
const SINK_TIME := 0.7

var config: EarthquakeConfig
var ground: EarthquakeGround
var landed := 0
var _rocks: Array = []
var _rng := RandomNumberGenerator.new()
var _ending := false
var _end_time := 3.0
var _end_clock := 0.0


func setup(cfg: EarthquakeConfig, g: EarthquakeGround, seed_v: int) -> void:
	config = cfg
	ground = g
	_rng.seed = seed_v * 3 + 1


func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = rock_mesh()
	mm.instance_count = CAPACITY
	mm.visible_instance_count = 0
	multimesh = mm
	var R := ground.reach + 6.0
	custom_aabb = AABB(Vector3(-R, -6.0, -R), Vector3(R * 2.0, 24.0, R * 2.0))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func count() -> int:
	return _rocks.size()


## Lança `n` pedras de `at` (x, z a partir do centro). `height` = altura máxima das maiores (m), `spread` =
## velocidade para os lados (m/s), `size` = tamanho mínimo e máximo (m), `outward` = direção preferida no chão
## (zero = todas as direções), `hot` = quanto brilham ao sair.
func burst(at: Vector2, n: int, height: float, spread: float, size: Vector2, outward := Vector2.ZERO, hot := 1.0) -> void:
	for _i in n:
		if _rocks.size() >= CAPACITY:
			return
		var s := _rng.randf_range(size.x, size.y)
		# as pequenas sobem mais (são mais leves), as grandes menos; todas variam
		var big := inverse_lerp(size.x, maxf(size.y, size.x + 0.001), s)
		var h := height * _rng.randf_range(0.35, 1.0) * lerpf(1.1, 0.7, big)
		var a := _rng.randf() * TAU
		if outward.length() > 0.01:
			a = outward.angle() + _rng.randf_range(-0.9, 0.9)
		var horiz := Vector2.from_angle(a) * spread * _rng.randf_range(0.25, 1.0)
		var start := ground.local_at(at + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, 0.5), s * 0.3)
		_add(start, Vector3(horiz.x, sqrt(2.0 * GRAVITY * maxf(h, 0.05)), horiz.y), s, hot, 0)


## Pedrinhas no chão em volta do centro (até `radius` m), pulando de leve: o chão tremendo antes do impacto.
func tremble(n: int, radius: float) -> void:
	for _i in n:
		if _rocks.size() >= CAPACITY:
			return
		var p := Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * radius
		var s := _rng.randf_range(0.05, 0.14)
		var r := _add(ground.local_at(p, s * 0.3), Vector3.ZERO, s, 0.0, 2)
		r.hop_t = _rng.randf_range(0.0, 0.25)


## O escudo bateu: as pedrinhas que tremiam são arremessadas para fora.
func launch_trembling(height: float) -> void:
	for r in _rocks:
		if int(r.state) != 2:
			continue
		var out := Vector2(r.pos.x, r.pos.z)
		var dir := out.normalized() if out.length() > 0.05 else Vector2.from_angle(_rng.randf() * TAU)
		var horiz := dir * _rng.randf_range(2.0, 6.0)
		r.vel = Vector3(horiz.x, sqrt(2.0 * GRAVITY * height * _rng.randf_range(0.3, 0.8)), horiz.y)
		r.state = 0
		r.heat = 0.8


## Fim da habilidade: as pedras que ainda estão por aí afundam aos poucos (cada uma num momento, em `time` s) e
## o nó se libera quando a última sumir.
func dissipate(time: float) -> void:
	_ending = true
	_end_time = maxf(time, 0.2)
	_end_clock = 0.0
	for r in _rocks:
		r.end_at = _rng.randf_range(0.15, 0.85) * _end_time


func _add(pos: Vector3, vel: Vector3, s: float, hot: float, state: int) -> Dictionary:
	var axis := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
	if axis.length() < 0.01:
		axis = Vector3.UP
	var r := {"pos": pos, "vel": vel, "basis": Basis(axis.normalized(), _rng.randf() * TAU), "axis": axis.normalized(),
		"spin": _rng.randf_range(-14.0, 14.0), "size": s,
		"shape": Vector3(_rng.randf_range(0.75, 1.3), _rng.randf_range(0.55, 1.0), _rng.randf_range(0.75, 1.3)),
		"state": state, "heat": hot, "t": 0.0, "rest": _rng.randf_range(0.5, 1.0) * config.dissipation_time,
		"sink": 0.0, "end_at": INF, "hop_t": 0.0}
	if _ending:
		r.end_at = _end_clock + _rng.randf_range(0.2, 0.6) * _end_time
	_rocks.append(r)
	return r


func _process(delta: float) -> void:
	if _ending:
		_end_clock += delta
	var i := 0
	while i < _rocks.size():
		var r: Dictionary = _rocks[i]
		if _step(r, delta):
			_rocks[i] = _rocks[_rocks.size() - 1]   # troca com a última (sem buraco no MultiMesh)
			_rocks.pop_back()
			continue
		i += 1
	var mm := multimesh
	for k in _rocks.size():
		var r: Dictionary = _rocks[k]
		var s: float = r.size
		mm.set_instance_transform(k, Transform3D((r.basis as Basis).scaled(r.shape * s), r.pos))
		mm.set_instance_custom_data(k, Color(float(r.heat), float(r.sink), 0.0, 0.0))
	mm.visible_instance_count = _rocks.size()
	if _ending and _rocks.is_empty() and _end_clock > 0.3:
		queue_free()


## Um passo de uma pedra. Devolve true quando ela sumiu de vez.
func _step(r: Dictionary, delta: float) -> bool:
	r.t = float(r.t) + delta
	r.heat = maxf(0.0, float(r.heat) - delta / COOL_TIME)
	var s: float = r.size
	var pos: Vector3 = r.pos
	var gy := ground.height_at(Vector2(pos.x, pos.z))
	match int(r.state):
		0:   # no ar
			var v: Vector3 = r.vel
			v.y -= GRAVITY * delta
			v *= 1.0 - 0.15 * delta   # um pouco de arrasto
			pos += v * delta
			r.basis = Basis(r.axis, float(r.spin) * delta) * (r.basis as Basis)
			var bottom := s * 0.25
			if pos.y - bottom <= gy and v.y < 0.0:
				pos.y = gy + bottom
				if absf(v.y) > 3.0:
					v = Vector3(v.x * 0.5, -v.y * 0.3, v.z * 0.5)   # quica
					r.spin = float(r.spin) * 0.5
				else:
					v = Vector3.ZERO
					r.state = 1
					r.t = 0.0
					pos.y = gy + s * 0.12   # assenta meio enterrada
					landed += 1
			r.vel = v
		1:   # parada no chão
			pos.y = gy + s * 0.12
			if float(r.t) > float(r.rest) and r.end_at == INF:
				r.end_at = _end_clock if _ending else -1.0
		2:   # tremendo antes do impacto: pulinhos
			r.hop_t = float(r.hop_t) - delta
			var v: Vector3 = r.vel
			v.y -= GRAVITY * delta
			pos += v * delta
			if pos.y <= gy + s * 0.25:
				pos.y = gy + s * 0.25
				v = Vector3.ZERO
				if float(r.hop_t) <= 0.0:
					v = Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(0.8, 2.2), _rng.randf_range(-0.3, 0.3))
					r.basis = Basis(r.axis, _rng.randf_range(-0.6, 0.6)) * (r.basis as Basis)
					r.hop_t = _rng.randf_range(0.05, 0.3)
			r.vel = v
	r.pos = pos
	# afundando: some aos poucos (sem parar a pedra que ainda está no ar)
	var end_at: float = r.end_at
	var sinking := end_at < 0.0 or (end_at != INF and _ending and _end_clock >= end_at)
	if sinking and int(r.state) != 0:
		r.sink = minf(1.0, float(r.sink) + delta / SINK_TIME)
		r.pos = pos - Vector3(0.0, s * 0.35 * delta / SINK_TIME, 0.0)
		return float(r.sink) >= 1.0
	return false


## Pedra baixa e irregular (esfera de poucas faces amassada), facetada. A cor de vértice marca as faces que guardam
## energia (o miolo azul que brilha enquanto a pedra está quente).
static func rock_mesh() -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 7
	sm.rings = 4
	var arr := sm.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var rng := RandomNumberGenerator.new()
	var jit := {}
	for i in v.size():
		var key := Vector3i(roundi(v[i].x * 100.0), roundi(v[i].y * 100.0), roundi(v[i].z * 100.0))
		if not jit.has(key):
			rng.seed = hash(key)
			jit[key] = v[i] * rng.randf_range(0.7, 1.15)
		v[i] = jit[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	rng.seed = 777
	for t in range(0, idx.size(), 3):
		var glow := Color(0.5, 0.8, 1.0) * (rng.randf_range(0.0, 1.0) if rng.randf() < 0.45 else 0.0)
		for k in 3:
			st.set_color(glow)
			st.add_vertex(v[idx[t + k]])
	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, preload("res://assets/vfx/earthquake/earthquake_stone_mat.tres"))
	return m
