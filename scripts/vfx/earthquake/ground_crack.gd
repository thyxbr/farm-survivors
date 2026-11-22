class_name GroundCrack
extends Node3D
## Terremoto Devastador: a destruição do terreno (scenes/vfx/earthquake/ground_crack.tscn), acompanhando a onda:
##   Cracks   as rachaduras (EarthquakeRules.crack_paths: radiais, umas maiores e outras menores, com ramificações)
##            como fitas que seguem o relevo. Cada ponto guarda a distância ao centro (UV.y): o shader só mostra o
##            trecho por onde a onda já passou e a fissura ABRE logo atrás da frente, com a energia azul e branca
##            fervendo no fundo (eq_crack + eq_crack_glow). Nada aparece de uma vez.
##   Plates   placas de pedra (MultiMesh) que se levantam ao lado das fissuras quando a onda chega nelas, com a
##            face de baixo brilhando, e voltam para dentro do chão na dissipação (uma de cada vez)
##   flashes  raios de energia da sprite sheet (EarthquakeSheet.LIGHTNING) estalando em alguns pontos das
##            rachaduras na passagem da onda
## Também serve para as rachaduras pequenas sob o herói enquanto ele ergue o escudo (só Cracks, revelados pela
## carga). `set_wave` a cada quadro; `dissipate` esfria e some tudo aos poucos.

const SHEET := preload("res://scenes/vfx/earthquake/earthquake_sheet.tscn")
const LIFT := 0.035
const PLATE_RISE := 0.2          ## tempo para a placa subir (s)
const PLATE_COOL := 1.6          ## tempo para a face de baixo esfriar (s)

var config: EarthquakeConfig
var ground: EarthquakeGround
var paths: Array = []
var plates: Array = []           ## EarthquakeRules.plate_spots
var flashes: Array = []          ## Vector2 (pontos das rachaduras onde estala um raio)
var wave_r := 0.0
var plates_up := 0
var _mat: ShaderMaterial
var _glow_mat: ShaderMaterial
var _glow := 1.0
var _alpha := 1.0
var _states: Array = []          ## por placa: {t (s desde que subiu; < 0 = ainda no chão), tilt, lift, sink, heat}
var _sink := false
var _flash_i := 0
var _rng := RandomNumberGenerator.new()

@onready var cracks: MeshInstance3D = $Cracks
@onready var plate_mm: MultiMeshInstance3D = $Plates


func setup(cfg: EarthquakeConfig, g: EarthquakeGround, crack_paths: Array, plate_spots := [], flash_spots := [], seed_v := 0) -> void:
	config = cfg
	ground = g
	paths = crack_paths
	plates = plate_spots
	flashes = flash_spots
	_rng.seed = seed_v * 7 + 11


func _ready() -> void:
	_mat = (cracks.material_override as ShaderMaterial).duplicate()
	_glow_mat = (_mat.next_pass as ShaderMaterial).duplicate()
	_mat.next_pass = _glow_mat
	cracks.material_override = _mat
	cracks.mesh = _crack_mesh()
	var R := ground.reach
	cracks.custom_aabb = AABB(Vector3(-R, -4.0, -R), Vector3(R * 2.0, 8.0, R * 2.0))
	_build_plates()
	set_wave(0.0)


func set_wave(r: float) -> void:
	wave_r = r
	_mat.set_shader_parameter("wave_r", r)
	_glow_mat.set_shader_parameter("wave_r", r)
	while _flash_i < flashes.size() and (flashes[_flash_i] as Vector2).length() <= r:
		_flash(flashes[_flash_i])
		_flash_i += 1


## Esfria e some aos poucos: o brilho das fissuras apaga primeiro, as placas voltam para o chão uma a uma e por
## último o fundo escuro das fissuras desbota. Se libera no fim.
func dissipate(time: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "_glow", 0.0, time * 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "_alpha", 0.0, time * 0.45).set_delay(time * 0.55)
	tw.tween_callback(queue_free)
	_sink = true
	# a ordem de afundar: espalhada no tempo (não todas juntas), de fora para dentro
	var n := _states.size()
	for i in n:
		var st: Dictionary = _states[i]
		st.sink_at = time * (0.15 + 0.55 * (1.0 - float(i) / maxf(n - 1, 1)) + _rng.randf_range(-0.05, 0.05))
		st.sink_len = time * _rng.randf_range(0.22, 0.32)


func _process(delta: float) -> void:
	_glow_mat.set_shader_parameter("glow", _glow * clampf(config.impact_intensity, 0.3, 2.0))
	_mat.set_shader_parameter("alpha_mul", _alpha)
	_update_plates(delta)


# ------------------------------------------------------------------- fitas das rachaduras
func _crack_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	for c in paths:
		var pts: PackedVector2Array = c.points
		var ws: PackedFloat32Array = c.widths
		if pts.size() < 2:
			continue
		var base := verts.size()
		for k in pts.size():
			var t := (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
			var n := Vector2(-t.y, t.x) * ws[k] * 0.5
			var d := pts[k].length()
			verts.append(ground.local_at(pts[k] + n, LIFT))
			verts.append(ground.local_at(pts[k] - n, LIFT))
			uvs.append(Vector2(0.0, d))
			uvs.append(Vector2(1.0, d))
			normals.append(Vector3.UP)
			normals.append(Vector3.UP)
			if k > 0:
				var a := base + (k - 1) * 2
				idx.append_array([a, a + 1, a + 2, a + 2, a + 1, a + 3])
	var m := ArrayMesh.new()
	if verts.is_empty():
		return m
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = idx
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _flash(p: Vector2) -> void:
	var s: EarthquakeSheet = SHEET.instantiate()
	s.name = "CrackFlash"
	add_child(s)
	var size := _rng.randf_range(2.4, 3.6) * clampf(config.impact_intensity, 0.6, 1.4) * config.size_k()
	s.place(ground.local_at(p), size)
	s.intensity = 1.1
	s.play(EarthquakeSheet.LIGHTNING, _rng.randf_range(0.35, 0.5), false, true)


# ------------------------------------------------------------------- placas de pedra
func _build_plates() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = plate_mesh()
	mm.instance_count = plates.size()
	mm.visible_instance_count = 0
	plate_mm.multimesh = mm
	var R := ground.reach
	plate_mm.custom_aabb = AABB(Vector3(-R, -4.0, -R), Vector3(R * 2.0, 10.0, R * 2.0))
	for p in plates:
		_states.append({"t": -1.0, "tilt": _rng.randf_range(0.35, 0.8), "lift": _rng.randf_range(0.05, 0.22),
			"sink_at": INF, "sink_len": 1.0, "wobble": _rng.randf_range(5.0, 9.0)})
	if plates.is_empty():
		plate_mm.visible = false


func _update_plates(delta: float) -> void:
	if plates.is_empty():
		return
	var mm := plate_mm.multimesh
	var shown := 0
	for i in plates.size():
		var p: Dictionary = plates[i]
		var st: Dictionary = _states[i]
		if float(st.t) < 0.0:
			if float(p.dist) <= wave_r:
				st.t = 0.0
				plates_up += 1
			else:
				break   # em ordem de distância: as de fora ainda não subiram
		st.t = float(st.t) + delta
		shown = i + 1
		var t: float = st.t
		# sobe com tranco (passa um pouco e assenta) e treme um pouco enquanto a onda ainda está perto
		var u := clampf(t / PLATE_RISE, 0.0, 1.0)
		var up := 1.0 + 2.70158 * pow(u - 1.0, 3.0) + 1.70158 * pow(u - 1.0, 2.0)   # back-out
		var tilt := float(st.tilt) * up + 0.04 * sin(t * float(st.wobble)) * exp(-t * 2.0)
		var lift := float(st.lift) * up
		var heat := clampf(1.0 - t / PLATE_COOL, 0.04, 1.0)
		var gone := 0.0
		if _sink:
			var s := _sink_clock(st, delta)
			s = s * s * (3.0 - 2.0 * s)
			tilt *= 1.0 - s
			lift = lerpf(lift, -0.35 * float(p.size), s)
			heat *= 1.0 - s
			gone = smoothstep(0.55, 1.0, s)
		mm.set_instance_transform(i, _plate_xform(p, tilt, lift))
		mm.set_instance_custom_data(i, Color(heat, gone, 0.0, 0.0))
	mm.visible_instance_count = maxi(mm.visible_instance_count, shown)


## Avança o relógio da volta ao chão de uma placa e devolve o progresso (0..1).
func _sink_clock(st: Dictionary, delta: float) -> float:
	st["sink_t"] = float(st.get("sink_t", 0.0)) + delta
	return clampf((float(st.sink_t) - float(st.sink_at)) / maxf(float(st.sink_len), 0.01), 0.0, 1.0)


## Transformação de uma placa: no chão (seguindo a inclinação), girada para a fissura e levantada pela borda do lado
## da rachadura (dobradiça na borda de fora).
func _plate_xform(p: Dictionary, tilt: float, lift: float) -> Transform3D:
	var pos: Vector2 = p.pos
	var s := float(p.size)
	var n := ground.normal_at(pos)
	var yaw_b := Basis(Vector3.UP, float(p.yaw))
	var x := yaw_b.x
	x = (x - n * x.dot(n)).normalized()
	var ground_b := Basis(x, n, x.cross(n).normalized())
	var hinge := Vector3(0.0, 0.0, s * 0.5)
	var local := Transform3D(Basis.IDENTITY, hinge) * Transform3D(Basis(Vector3.RIGHT, tilt), Vector3.ZERO) \
		* Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), -hinge)
	return Transform3D(ground_b, ground.local_at(pos) + n * lift) * local


## Placa de pedra: prisma irregular (7 lados) de 1 m, topo no y = 0 e espessura 0,28 m para baixo. A cor de vértice
## marca a energia: preta no topo, azul na lateral de baixo e no fundo (o que estava enterrado brilha).
static func plate_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var sides := 7
	var ring := PackedVector2Array()
	for i in sides:
		var a := TAU * (float(i) + rng.randf_range(-0.2, 0.2)) / sides
		ring.append(Vector2(cos(a), sin(a)) * 0.5 * rng.randf_range(0.8, 1.05))
	var th := 0.28
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var black := Color(0, 0, 0)
	var blue := Color(0.6, 0.85, 1.0)
	# topo (um pouco abaulado e torto) e fundo
	for i in sides:
		var a := ring[i]
		var b := ring[(i + 1) % sides]
		st.set_color(black)
		st.add_vertex(Vector3(0.0, 0.03, 0.0))
		st.add_vertex(Vector3(a.x, 0.0, a.y))
		st.add_vertex(Vector3(b.x, 0.0, b.y))
		st.set_color(blue)
		st.add_vertex(Vector3(0.0, -th, 0.0))
		st.add_vertex(Vector3(b.x * 0.85, -th, b.y * 0.85))
		st.add_vertex(Vector3(a.x * 0.85, -th, a.y * 0.85))
	# laterais: escura em cima, energia embaixo
	for i in sides:
		var a := ring[i]
		var b := ring[(i + 1) % sides]
		var a0 := Vector3(a.x, 0.0, a.y)
		var b0 := Vector3(b.x, 0.0, b.y)
		var a1 := Vector3(a.x * 0.85, -th, a.y * 0.85)
		var b1 := Vector3(b.x * 0.85, -th, b.y * 0.85)
		st.set_color(black)
		st.add_vertex(a0)
		st.set_color(blue)
		st.add_vertex(b1)
		st.set_color(black)
		st.add_vertex(b0)
		st.set_color(blue)
		st.add_vertex(b1)
		st.set_color(black)
		st.add_vertex(a0)
		st.set_color(blue)
		st.add_vertex(a1)
	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, preload("res://assets/vfx/earthquake/earthquake_stone_mat.tres"))
	return m
