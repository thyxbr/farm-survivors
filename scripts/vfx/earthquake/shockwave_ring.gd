class_name ShockwaveRing
extends Node3D
## Terremoto Devastador: a onda de choque circular (scenes/vfx/earthquake/shockwave_ring.tscn). Começa no centro, sob
## o escudo, e se espalha em todas as direções rente ao chão:
##   Disc   disco que segue o relevo (montado pela grade de alturas, EarthquakeGround) com o anel de energia no shader
##          (eq_ring.gdshader): borda branca e fina na frente, brilho azul arrastando para dentro, quebrado por ruído
##   Wall   faixa baixa de energia em pé sobre a frente da onda, refeita a cada quadro no raio atual com a base no
##          chão de cada ponto (não flutua nem atravessa o terreno)
##   Center o miolo da onda da sprite sheet (EarthquakeSheet.WAVE: anel aceso no chão rachado, placas e fumaça)
## O EarthquakeSkill passa o raio a cada quadro (`set_wave`) e chama `dissipate` quando a onda para.

const SHEET := preload("res://scenes/vfx/earthquake/earthquake_sheet.tscn")
const RINGS := 40
const SLICES := 96
const LIFT := 0.05
const WALL_SEGMENTS := 96
const WALL_HEIGHT := 1.15
## Largura da borda do anel (m), convertida para a escala do shader pelo raio.
const RING_WIDTH_M := 0.5
const TRAIL_M := 0.8

var config: EarthquakeConfig
var ground: EarthquakeGround
var wave_r := 0.0
var intensity := 1.0
var _wall_k := 1.0
var _disc_mat: ShaderMaterial
var _wall_mat: ShaderMaterial
var _wall_mesh := ImmediateMesh.new()
var _center: EarthquakeSheet
var _fading := false

@onready var disc: MeshInstance3D = $Disc
@onready var wall: MeshInstance3D = $Wall


func setup(cfg: EarthquakeConfig, g: EarthquakeGround) -> void:
	config = cfg
	ground = g


func _ready() -> void:
	_disc_mat = (disc.material_override as ShaderMaterial).duplicate()
	disc.material_override = _disc_mat
	_wall_mat = (wall.material_override as ShaderMaterial).duplicate()
	wall.material_override = _wall_mat
	wall.mesh = _wall_mesh
	var R := config.radius
	disc.mesh = build_disc(ground, R * 1.1, R, RINGS, SLICES, LIFT)
	_disc_mat.set_shader_parameter("ring_width", RING_WIDTH_M * config.size_k() / R)
	_disc_mat.set_shader_parameter("trail", TRAIL_M * config.size_k() / R)
	var aabb := AABB(Vector3(-R * 1.2, -4.0, -R * 1.2), Vector3(R * 2.4, 8.0, R * 2.4))
	disc.custom_aabb = aabb
	wall.custom_aabb = aabb
	_center = SHEET.instantiate()
	_center.name = "Center"
	add_child(_center)
	_center.place(ground.local_at(Vector2.ZERO), maxf(minf(R * 0.6, 6.0), 2.6) * clampf(config.impact_intensity, 0.6, 1.4))
	_center.play(EarthquakeSheet.WAVE, config.expansion_time() + 0.5)
	_center.intensity = 0.6
	set_wave(0.0)


## Raio atual da onda (m).
func set_wave(r: float) -> void:
	wave_r = r
	_disc_mat.set_shader_parameter("wave", r / config.radius)
	_disc_mat.set_shader_parameter("intensity", intensity * config.impact_intensity)
	# a parede é mais alta no começo e baixa conforme a onda perde força
	var k := 1.0 - 0.55 * clampf(r / config.radius, 0.0, 1.0)
	_rebuild_wall(r, WALL_HEIGHT * k * _wall_k * sqrt(maxf(config.impact_intensity, 0.1)) * sqrt(config.size_k()))


## A onda parou no raio máximo: a parede baixa primeiro, depois o anel apaga e o miolo da sheet some.
func dissipate(time: float) -> void:
	if _fading:
		return
	_fading = true
	var tw := create_tween()
	tw.tween_property(self, "_wall_k", 0.0, time * 0.18).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "intensity", 0.0, time * 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(_set_residual, 0.05, 0.0, time * 0.45)
	tw.tween_callback(queue_free)
	if is_instance_valid(_center):
		_center.fade_out(time * 0.3)


func _process(_delta: float) -> void:
	if _fading:
		set_wave(wave_r)


func _set_residual(v: float) -> void:
	_disc_mat.set_shader_parameter("residual", v)


func _rebuild_wall(r: float, h: float) -> void:
	_wall_mesh.clear_surfaces()
	if r < 0.3 or h < 0.02 or intensity <= 0.01:
		wall.visible = false
		return
	wall.visible = true
	_wall_mat.set_shader_parameter("intensity", intensity * config.impact_intensity)
	_wall_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in WALL_SEGMENTS + 1:
		var a := TAU * float(i) / WALL_SEGMENTS
		var dir := Vector2.from_angle(a)
		var base := ground.local_at(dir * r, 0.02)
		# o topo inclina para fora (a onda empurra para fora)
		var top := ground.local_at(dir * (r + h * 0.3)) + Vector3(0.0, h, 0.0)
		_wall_mesh.surface_set_normal(Vector3.UP)
		_wall_mesh.surface_set_uv(Vector2(float(i) / WALL_SEGMENTS, 0.0))
		_wall_mesh.surface_add_vertex(base)
		_wall_mesh.surface_set_uv(Vector2(float(i) / WALL_SEGMENTS, 1.0))
		_wall_mesh.surface_add_vertex(top)
	_wall_mesh.surface_end()


## Disco polar que segue o chão: `rings` anéis até `mesh_r` m e `slices` fatias, cada vértice na altura da grade
## + `lift`. UV.x = distância ao centro / `uv_r` (o raio da onda), UV.y = ângulo (0..1). Usado também pelo anel
## inicial do impacto (GroundImpact).
static func build_disc(g: EarthquakeGround, mesh_r: float, uv_r: float, rings: int, slices: int, lift: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in rings + 1:
		var r := mesh_r * float(i) / rings
		for j in slices + 1:
			var p := Vector2.from_angle(TAU * float(j) / slices) * r
			verts.append(g.local_at(p, lift) if g != null else Vector3(p.x, lift, p.y))
			uvs.append(Vector2(r / uv_r, float(j) / slices))
			normals.append(Vector3.UP)
	var row := slices + 1
	for i in rings:
		for j in slices:
			var a := i * row + j
			var b := a + row
			idx.append_array([a, b, a + 1, a + 1, b, b + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
