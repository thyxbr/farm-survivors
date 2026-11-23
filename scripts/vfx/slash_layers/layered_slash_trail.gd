class_name LayeredSlashTrail
extends MeshInstance3D
## Corte em camadas (protótipo, `--slashfx2`): segue a lâmina de verdade (cabo `base_node` e ponta `tip_node`, como o
## DarkBladeTrail) e desenha o golpe em camadas, no estilo dos cortes desenhados de MMO:
##   corpo     meia-lua da cor da arma, larga junto da lâmina e fina na cauda, com dentes do lado de dentro e que se
##             desfaz em pedaços (erosão) em vez de ficar transparente. Fundo escuro (mistura normal: lê de dia) e
##             brilho aditivo por cima (o fio quase branco na borda de fora passa de 1 e o glow do mundo pega).
##   arcos     duas fitas finas um pouco fora e um pouco dentro do corpo, que duram mais (os riscos soltos)
##   lascas    espinhos que saltam da borda de fora enquanto o golpe está forte
##   faíscas   riscos rápidos que saem da ponta, com gravidade
## Corpo: superfície deste nó (slash_mat.tres). Arcos, lascas e faíscas: o nó filho `_bits` (slash_bits_mat.tres).
## Contas da malha do corpo em slash_common.gdshaderinc. A força sai da velocidade da ponta: parada, nada aparece.

const MAT := preload("res://assets/vfx/slash_layers/slash_mat.tres")
const BITS_MAT := preload("res://assets/vfx/slash_layers/slash_bits_mat.tres")
const SUB := 5
const MAX_SAMPLES := 64

var base_node: Node3D
var tip_node: Node3D
## Quanto dura o corpo (s); os arcos duram `arc_life` vezes isso.
var lifetime := 0.36
var arc_life := 1.2
var reach := 0.45
var hilt := 0.15
var min_speed := 3.0
var full_speed := 9.0
var emitting := true
## Forma do corpo (slash_common): largura na cabeça e quão rápido afina.
var head_w := 0.92
var tail_pow := 0.55
## Quantas lascas e faíscas saem (1 = todas; o golpe básico usa menos).
var bits_scale := 1.0
## false: sem os arcos finos (girando sem parar eles fecham círculos e parecem arame)
var show_arcs := true
var intensity := 1.0:
	set(v):
		intensity = v
		set_instance_shader_parameter("intensity", v)

var _color := Color(1.0, 0.35, 0.85)
var _imesh := ImmediateMesh.new()
var _bits: MeshInstance3D
var _bmesh := ImmediateMesh.new()
var _samples: Array[Dictionary] = []
var _spikes: Array[Dictionary] = []
var _sparks: Array[Dictionary] = []
var _time := 0.0
var _last_tip := Vector3.ZERO
var _has_last := false
var _strength := 0.0
var _spike_acc := 0.0
var _spark_acc := 0.0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _imesh
	material_override = MAT
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 6.0
	set_instance_shader_parameter("seed", randf() * 10.0)
	_bits = MeshInstance3D.new()
	_bits.top_level = true
	_bits.mesh = _bmesh
	_bits.material_override = BITS_MAT
	_bits.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bits.extra_cull_margin = 6.0
	add_child(_bits)
	_bits.global_transform = Transform3D.IDENTITY
	set_color(_color)
	intensity = intensity
	set_instance_shader_parameter("head_w", head_w)
	set_instance_shader_parameter("tail_pow", tail_pow)


## A cor da arma (ou do encantamento): o resto da paleta sai dela.
func set_color(c: Color) -> void:
	# a cor do item costuma ser clara; o corte quer a versão saturada
	var h := c.h
	var sat := clampf(maxf(c.s, 0.8), 0.0, 1.0)
	_color = Color.from_hsv(h, sat, 1.0)
	set_instance_shader_parameter("tint", Vector3(_color.r, _color.g, _color.b))
	var d := Color.from_hsv(fposmod(h - 0.04, 1.0), 1.0, 0.22)
	set_instance_shader_parameter("deep", Vector3(d.r, d.g, d.b))


## Acerto em `pos` (o golpe vinha no sentido `dir`): clarão redondo branco e bolhas na cor da arma (FXToon.pop), riscos em estrela (FXToon.spark_hit), uma coroa de lascas grandes saindo do ponto, mais
## para a frente do golpe, e um punhado de faíscas. `size` ~1 num golpe normal, maior no golpe final.
func impact(pos: Vector3, dir: Vector3, size := 1.0) -> void:
	var pal := FXToon.palette(_color)
	# clarão cheio que encolhe (sem anel: um anel de contorno lê como bolha) e bolinhas na cor espirrando para a frente
	FXToon.pop(pos, pal, {"size0": 0.85 * size, "size1": 0.0, "time": 0.12, "ease_in": true, "core": Color.WHITE})
	FXToon.pop(pos, pal, {"size0": 0.5 * size, "size1": 0.0, "time": 0.16, "ease_in": true, "core": Color.WHITE, "sort": 0.1})
	var bright := {"core": Color.WHITE, "mid": pal.core, "edge": pal.mid}
	for i in 7:
		var v := (_rand_unit() + dir * 0.9).normalized()
		FXToon.pop(pos + v * 0.15, bright, {"size0": randf_range(0.18, 0.3) * size, "size1": 0.0,
			"time": randf_range(0.22, 0.34), "vel": v * randf_range(3.5, 6.5) * size, "ease_in": true})
	FXToon.spark_hit(pos, -dir, pal, 6, 1.3 * size)
	for i in 10:
		var d := (_rand_unit() + dir * 0.7).normalized()
		_spikes.append({"p": pos + d * 0.12 * size, "d": d, "len": randf_range(0.7, 1.5) * size,
			"w": randf_range(0.07, 0.13) * size, "born": _time, "life": randf_range(0.18, 0.32)})
	for i in 16:
		_sparks.append({"p": pos, "v": (_rand_unit() + dir * 0.8) * randf_range(4.0, 8.0) * size + Vector3.UP * 2.0,
			"born": _time, "life": randf_range(0.25, 0.5)})


func strength() -> float:
	return _strength


func clear() -> void:
	_samples.clear()
	_spikes.clear()
	_sparks.clear()
	_imesh.clear_surfaces()
	_bmesh.clear_surfaces()
	_has_last = false


func _process(delta: float) -> void:
	_time += delta
	if emitting and _valid(base_node) and _valid(tip_node):
		_push(delta)
	else:
		_has_last = false
		_strength = 0.0
	var keep := lifetime * arc_life
	while not _samples.is_empty() and _time - float(_samples[0].time) > keep:
		_samples.pop_front()
	_step_bits(delta)
	_rebuild()
	_rebuild_bits()


func _valid(n: Variant) -> bool:   # sem tipo: pode chegar um nó já liberado
	return n != null and is_instance_valid(n) and n.is_inside_tree()


func _push(delta: float) -> void:
	var b := base_node.global_position
	var t := tip_node.global_position
	var vel := (t - _last_tip) / maxf(delta, 0.001) if _has_last else Vector3.ZERO
	var s := smoothstep(min_speed, full_speed, vel.length())
	_last_tip = t
	_has_last = true
	_strength = s if s > _strength else lerpf(_strength, s, 1.0 - exp(-12.0 * delta))
	var axis := t - b
	var len := axis.length()
	var dir := axis / len if len > 0.001 else Vector3.UP
	var tip := t + dir * reach
	_samples.append({"b": b + axis * hilt, "t": tip, "dir": dir, "time": _time, "s": _strength, "raw": s})
	if _samples.size() > MAX_SAMPLES:
		_samples.pop_front()
	if _strength > 0.45:
		var move := vel.normalized() if vel.length() > 0.01 else Vector3.ZERO
		_spike_acc += delta * 55.0 * _strength * bits_scale
		while _spike_acc >= 1.0:
			_spike_acc -= 1.0
			_spawn_spike(tip, dir, move)
		_spark_acc += delta * 50.0 * _strength * bits_scale
		while _spark_acc >= 1.0:
			_spark_acc -= 1.0
			_spawn_spark(tip, dir, vel)


func _spawn_spike(tip: Vector3, dir: Vector3, move: Vector3) -> void:
	# sai da borda de fora, inclinado para trás do movimento (o golpe "arranca" a lasca)
	var back := -move
	var d := (dir * 0.85 + back * randf_range(0.2, 0.7) + _rand_unit() * 0.25).normalized()
	var at := tip - dir * randf_range(0.0, 0.25) + back * randf_range(0.0, 0.15)
	_spikes.append({"p": at, "d": d, "len": randf_range(0.18, 0.55) * _strength, "w": randf_range(0.035, 0.07),
		"born": _time, "life": randf_range(0.14, 0.26)})


func _spawn_spark(tip: Vector3, dir: Vector3, vel: Vector3) -> void:
	var v := vel * randf_range(0.15, 0.35) + dir * randf_range(1.0, 3.5) + _rand_unit() * 2.5 + Vector3.UP * 1.5
	_sparks.append({"p": tip - dir * randf_range(0.0, 0.5), "v": v, "born": _time, "life": randf_range(0.2, 0.45)})


static func _rand_unit() -> Vector3:
	return Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()


func _step_bits(delta: float) -> void:
	var i := 0
	while i < _spikes.size():
		if _time - float(_spikes[i].born) > float(_spikes[i].life):
			_spikes.remove_at(i)
		else:
			i += 1
	i = 0
	while i < _sparks.size():
		var sp: Dictionary = _sparks[i]
		if _time - float(sp.born) > float(sp.life):
			_sparks.remove_at(i)
			continue
		sp.v = (sp.v as Vector3) * exp(-3.0 * delta) + Vector3.DOWN * 7.0 * delta
		sp.p = (sp.p as Vector3) + (sp.v as Vector3) * delta
		i += 1


# --- corpo -------------------------------------------------------------------------------------------------------

func _rebuild() -> void:
	_imesh.clear_surfaces()
	var pts := _curve(lifetime)
	if pts.size() < 2:
		return
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in pts.size() - 1:
		var p0: Dictionary = pts[i]
		var p1: Dictionary = pts[i + 1]
		var c0 := Color(1, 1, 1, p0.s)
		var c1 := Color(1, 1, 1, p1.s)
		_v(_imesh, p0.b, Vector2(p0.age, 0.0), c0)
		_v(_imesh, p0.t, Vector2(p0.age, 1.0), c0)
		_v(_imesh, p1.t, Vector2(p1.age, 1.0), c1)
		_v(_imesh, p0.b, Vector2(p0.age, 0.0), c0)
		_v(_imesh, p1.t, Vector2(p1.age, 1.0), c1)
		_v(_imesh, p1.b, Vector2(p1.age, 0.0), c1)
	_imesh.surface_end()


## Pontos da curva (Catmull-Rom entre as amostras) com idade < `life`: {b, t, dir, age (0..1 em `life`), s}.
func _curve(life: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n := _samples.size()
	if n < 2:
		return out
	var any := false
	for smp in _samples:
		if float(smp.s) > 0.01 and _time - float(smp.time) < life:
			any = true
			break
	if not any:
		return out
	for i in n - 1:
		var s1: Dictionary = _samples[i]
		var s2: Dictionary = _samples[i + 1]
		if _time - float(s2.time) > life:
			continue
		var s0: Dictionary = _samples[maxi(i - 1, 0)]
		var s3: Dictionary = _samples[mini(i + 2, n - 1)]
		var steps := SUB if i < n - 2 else SUB + 1
		for k in steps:
			var u := float(k) / float(SUB)
			var tm := lerpf(float(s1.time), float(s2.time), u)
			var age := (_time - tm) / life
			if age > 1.0:
				continue
			out.append({
				"b": _cr(s0.b, s1.b, s2.b, s3.b, u), "t": _cr(s0.t, s1.t, s2.t, s3.t, u),
				"dir": (s1.dir as Vector3).lerp(s2.dir, u).normalized(),
				"age": clampf(age, 0.0, 1.0), "s": lerpf(float(s1.s), float(s2.s), u),
				"raw": lerpf(float(s1.raw), float(s2.raw), u)})
	return out


# --- arcos, lascas, faíscas ----------------------------------------------------------------------------------------

func _rebuild_bits() -> void:
	_bmesh.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam != null else Vector3.ZERO
	var pts := _curve(lifetime * arc_life)
	var any := pts.size() >= 2 or not _spikes.is_empty() or not _sparks.is_empty()
	if not any:
		return
	_bmesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	if pts.size() >= 2 and show_arcs:
		var light := _color.lerp(Color.WHITE, 0.55)
		_arc(pts, 1.08, 0.018, light, 0.05)
		_arc(pts, 0.72, 0.012, _color, 0.15)
	var hot := _color.lerp(Color.WHITE, 0.7)
	for sp in _spikes:
		var k := (_time - float(sp.born)) / float(sp.life)
		var grow := minf(k / 0.25, 1.0)
		var len := float(sp.len) * (0.4 + 0.6 * grow)
		var w := float(sp.w) * (1.0 - k)
		var a: Vector3 = sp.p
		var tipp := a + (sp.d as Vector3) * len
		var side := _side(a, sp.d, eye) * w
		var c := Color(hot.r, hot.g, hot.b, 1.0 - k * k)
		_v(_bmesh, a - side, Vector2(0.0, 0.0), c)
		_v(_bmesh, a + side, Vector2(1.0, 0.0), c)
		_v(_bmesh, tipp, Vector2(0.5, 1.0), c)
	var spark := _color.lerp(Color.WHITE, 0.6)
	for sp in _sparks:
		var k := (_time - float(sp.born)) / float(sp.life)
		var p: Vector3 = sp.p
		var v: Vector3 = sp.v
		var tail := p - v * 0.022
		var d := (p - tail)
		if d.length() < 0.01:
			continue
		var side := _side(tail, d.normalized(), eye) * 0.008
		var c := Color(spark.r, spark.g, spark.b, 1.0 - k)
		_quad(_bmesh, tail, p, side, c)
	_bmesh.surface_end()


## Fita fina ao longo da curva, a uma fração `r` do raio (cabo -> borda de fora), começando com `delay` de atraso
## (idade) e se apagando até o fim da vida dos arcos.
func _arc(pts: Array[Dictionary], r: float, width: float, col: Color, delay: float) -> void:
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_c := Color()
	var first := true
	var prev_center := Vector3.ZERO
	var prev_step := Vector3.ZERO
	for p in pts:
		var age := float(p.age)
		var center: Vector3 = (p.b as Vector3).lerp(p.t, r)
		# onde o golpe vira (volta da guarda, troca de golpe) a fita quebra em vez de fazer quina
		var step := center - prev_center
		if not first and prev_step.length() > 0.001 and step.length() > 0.001 and prev_step.normalized().dot(step.normalized()) < 0.75:
			first = true
		prev_step = step
		prev_center = center
		var half: Vector3 = (p.dir as Vector3) * width * (1.0 - age * 0.6)
		# só onde a lâmina passou rápido de verdade (a força crua, sem o apagar suave do corpo)
		var raw := float(p.raw)
		var on := smoothstep(delay, delay + 0.08, age) * (1.0 - smoothstep(0.5, 1.0, age)) * raw * raw
		var c := Color(col.r, col.g, col.b, on)
		var l := center - half
		var rr := center + half
		if not first:
			_v(_bmesh, prev_l, Vector2(0, 1), prev_c)
			_v(_bmesh, prev_r, Vector2(1, 1), prev_c)
			_v(_bmesh, rr, Vector2(1, 1), c)
			_v(_bmesh, prev_l, Vector2(0, 1), prev_c)
			_v(_bmesh, rr, Vector2(1, 1), c)
			_v(_bmesh, l, Vector2(0, 1), c)
		first = false
		prev_l = l
		prev_r = rr
		prev_c = c


static func _side(p: Vector3, d: Vector3, eye: Vector3) -> Vector3:
	var to_eye := (eye - p)
	var s := d.cross(to_eye)
	if s.length() < 0.0001:
		s = d.cross(Vector3.UP)
	return s.normalized()


static func _quad(m: ImmediateMesh, a: Vector3, b: Vector3, side: Vector3, c: Color) -> void:
	_v(m, a - side, Vector2(0, 0), c)
	_v(m, a + side, Vector2(1, 0), c)
	_v(m, b + side, Vector2(1, 1), c)
	_v(m, a - side, Vector2(0, 0), c)
	_v(m, b + side, Vector2(1, 1), c)
	_v(m, b - side, Vector2(0, 1), c)


static func _v(m: ImmediateMesh, p: Vector3, uv: Vector2, c: Color) -> void:
	m.surface_set_uv(uv)
	m.surface_set_color(c)
	m.surface_add_vertex(p)


static func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	var u2 := u * u
	var u3 := u2 * u
	return 0.5 * ((2.0 * p1) + (p2 - p0) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * u3)
