class_name DarkBladeTrail
extends MeshInstance3D
## Rastro de energia sombria que segue o corte da montante (Ciclone de Aço, Dança do Abismo): a cada quadro guarda onde
## estão o cabo (`base_node`) e a ponta (`tip_node`) da lâmina e monta uma fita entre as posições dos últimos `lifetime`
## segundos (ImmediateMesh, curva Catmull-Rom entre os quadros: sem quinas mesmo num giro rápido). A fita vai do cabo
## (um pouco acima: `hilt`) até além da ponta (`reach`): a energia sai da lâmina.
## Material: dark_trail_mat.tres (fumaça escura + brilho violeta e carmesim em next_pass, dark_energy.gdshaderinc).
##   UV.x = idade (0 = agora, 1 = o mais velho), UV.y = do cabo (0) à ponta (1), COLOR.a = força do golpe no ponto.
## A força sai da velocidade da ponta (`min_speed` .. `full_speed`): parada, a lâmina não deixa rastro; num corte, o
## rastro acende. `strength_override` >= 0 manda no lugar dela (o giro usa a velocidade do giro).
## top_level: a fita fica no mundo (o herói pode andar: o rastro fica para trás, como deve).

const MAT := preload("res://assets/vfx/greatsword_dark/dark_trail_mat.tres")
const SUB := 5           ## pontos interpolados entre dois quadros
const MAX_SAMPLES := 48

var base_node: Node3D
var tip_node: Node3D
## Quanto tempo um ponto do rastro dura (s).
var lifetime := 0.28
## A energia passa da ponta este tanto (m) e começa esta fração da lâmina acima do cabo.
var reach := 0.5
var hilt := 0.12
## Velocidade da ponta (m/s) em que o rastro começa a aparecer e em que fica cheio.
var min_speed := 3.5
var full_speed := 9.0
## >= 0: força fixa (0..1) no lugar da velocidade.
var strength_override := -1.0
## false: para de guardar pontos (o que já existe some sozinho em `lifetime`).
var emitting := true
## Brilho geral (instance uniform do shader): o apagar no fim.
var intensity := 1.0:
	set(v):
		intensity = v
		set_instance_shader_parameter("intensity", v)

var _imesh := ImmediateMesh.new()
var _samples: Array[Dictionary] = []
var _time := 0.0
var _last_tip := Vector3.ZERO
var _has_last := false
var _strength := 0.0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _imesh
	material_override = MAT
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 4.0
	set_instance_shader_parameter("intensity", intensity)
	set_instance_shader_parameter("seed", randf() * 10.0)


## Força atual do rastro (0..1): a da última amostra.
func strength() -> float:
	return _strength


## Quantos pontos o rastro tem agora (testes e o apagar).
func sample_count() -> int:
	return _samples.size()


## Apaga tudo na hora.
func clear() -> void:
	_samples.clear()
	_imesh.clear_surfaces()
	_has_last = false


func _process(delta: float) -> void:
	_time += delta
	if emitting and _valid(base_node) and _valid(tip_node):
		_push(delta)
	while not _samples.is_empty() and _time - float(_samples[0].time) > lifetime:
		_samples.pop_front()
	_rebuild()


func _valid(n: Node3D) -> bool:
	return n != null and is_instance_valid(n) and n.is_inside_tree()


func _push(delta: float) -> void:
	var b := base_node.global_position
	var t := tip_node.global_position
	var s := strength_override
	if s < 0.0:
		var spd := (t - _last_tip).length() / maxf(delta, 0.001) if _has_last else 0.0
		s = smoothstep(min_speed, full_speed, spd)
	_last_tip = t
	_has_last = true
	# sobe depressa, cai um pouco mais devagar (sem piscar entre dois quadros parecidos)
	_strength = s if s > _strength else lerpf(_strength, s, 1.0 - exp(-14.0 * delta))
	var axis := t - b
	var len := axis.length()
	var dir := axis / len if len > 0.001 else Vector3.UP
	_samples.append({"b": b + axis * hilt, "t": t + dir * reach, "time": _time, "s": _strength})
	if _samples.size() > MAX_SAMPLES:
		_samples.pop_front()


func _rebuild() -> void:
	_imesh.clear_surfaces()
	var n := _samples.size()
	if n < 2:
		return
	var any := false
	for smp in _samples:
		if float(smp.s) > 0.01:
			any = true
			break
	if not any:
		return
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev_b := Vector3.ZERO
	var prev_t := Vector3.ZERO
	var prev_age := 0.0
	var prev_s := 0.0
	var first := true
	for i in n - 1:
		var s0: Dictionary = _samples[maxi(i - 1, 0)]
		var s1: Dictionary = _samples[i]
		var s2: Dictionary = _samples[i + 1]
		var s3: Dictionary = _samples[mini(i + 2, n - 1)]
		var steps := SUB if i < n - 2 else SUB + 1
		for k in steps:
			var u := float(k) / float(SUB)
			var pb := _cr(s0.b, s1.b, s2.b, s3.b, u)
			var pt := _cr(s0.t, s1.t, s2.t, s3.t, u)
			var tm := lerpf(float(s1.time), float(s2.time), u)
			var age := clampf((_time - tm) / lifetime, 0.0, 1.0)
			var st := lerpf(float(s1.s), float(s2.s), u)
			if not first:
				_quad(prev_b, prev_t, pb, pt, prev_age, age, prev_s, st)
			first = false
			prev_b = pb
			prev_t = pt
			prev_age = age
			prev_s = st
	_imesh.surface_end()


func _quad(b0: Vector3, t0: Vector3, b1: Vector3, t1: Vector3, a0: float, a1: float, s0: float, s1: float) -> void:
	# o mais velho fica em a0 (a fita vai do mais velho para o mais novo)
	var c0 := Color(1, 1, 1, s0)
	var c1 := Color(1, 1, 1, s1)
	_v(b0, Vector2(a0, 0.0), c0)
	_v(t0, Vector2(a0, 1.0), c0)
	_v(t1, Vector2(a1, 1.0), c1)
	_v(b0, Vector2(a0, 0.0), c0)
	_v(t1, Vector2(a1, 1.0), c1)
	_v(b1, Vector2(a1, 0.0), c1)


func _v(p: Vector3, uv: Vector2, c: Color) -> void:
	_imesh.surface_set_uv(uv)
	_imesh.surface_set_color(c)
	_imesh.surface_add_vertex(p)


static func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	var u2 := u * u
	var u3 := u2 * u
	return 0.5 * ((2.0 * p1) + (p2 - p0) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * u3)
