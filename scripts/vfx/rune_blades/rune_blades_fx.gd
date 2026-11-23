class_name RuneBladesFX
extends RefCounted
## Lâminas Rúnicas: lâminas de cristal vermelho em fuso, com runas acesas correndo pelas bordas. Feitas em código
## sobre duas pinturas (claro em fundo preto): lamina_runica.png (o corpo) e runas_faixa.png (os glifos).
##   make_blade  uma lâmina (nó cujo Y local é a direção dela): corpo, runas e uma luz vermelha
##   charge      a invocação: as lâminas nascem uma a uma nos pontos dados, em pé, cada uma com um aro fino que
##               abre girando; ficam no ar balançando e, no fim, deitam apontando para onde vão disparar
##   impact      o acerto: estrela laranja (clarao.png do Vórtice), clarão vermelho, faíscas e luz
## Em jogo: a Rajada de Sombras do Arauto do Abismo (Enemy._abyss_warn chama `charge`; cada projétil é um
## EnemyArrow com `blade`, que usa `make_blade` e `impact`).

const RED := Color(1.0, 0.14, 0.1)
const ORANGE := Color(1.0, 0.55, 0.2)
const BLADE_TEX := preload("res://assets/vfx/rune_blades/lamina_runica.png")
const RUNES_TEX := preload("res://assets/vfx/rune_blades/runas_faixa.png")
const BLADE := preload("res://shaders/rune_blades/blade.gdshader")
const RUNES := preload("res://shaders/rune_blades/runes.gdshader")
const FLARE := preload("res://shaders/sword_vortex/tex_flash.gdshader")
const FLARE_TEX := preload("res://assets/vfx/sword_vortex/clarao.png")
## Largura do corpo da lâmina em fração do comprimento (o recorte da pintura) e das runas em volta.
const BODY_W := 0.23
const RUNES_W := 0.42

static var _blade_mat: ShaderMaterial
static var _runes_mat: ShaderMaterial


static func _mats() -> void:
	if _blade_mat != null:
		return
	_blade_mat = ShaderMaterial.new()
	_blade_mat.shader = BLADE
	_blade_mat.set_shader_parameter("blade", BLADE_TEX)
	_blade_mat.render_priority = 1
	_runes_mat = ShaderMaterial.new()
	_runes_mat.shader = RUNES
	_runes_mat.set_shader_parameter("runes", RUNES_TEX)
	_runes_mat.render_priority = 2


## Uma lâmina de `length` m. O Y local do nó devolvido é a direção dela (use `basis_along`).
static func make_blade(length := 1.7, c := RED) -> Node3D:
	_mats()
	var root := Node3D.new()
	var cv := Vector3(c.r, c.g, c.b)
	var quad := QuadMesh.new()
	for i in 2:
		var n := MeshInstance3D.new()
		n.mesh = quad
		n.material_override = _blade_mat if i == 0 else _runes_mat
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.extra_cull_margin = length
		n.scale = Vector3(length * (BODY_W if i == 0 else RUNES_W), length, 1.0)
		n.set_instance_shader_parameter("col", cv)
		if i == 1:
			n.set_instance_shader_parameter("phase", randf())
		root.add_child(n)
	var light := OmniLight3D.new()
	light.light_color = c
	light.light_energy = 0.8
	light.omni_range = 2.6
	light.shadow_enabled = false
	root.add_child(light)
	return root


## Apaga ou acende uma lâmina inteira (0 a 1).
static func set_blade_intensity(blade: Node3D, v: float) -> void:
	for n in blade.get_children():
		if n is MeshInstance3D:
			n.set_instance_shader_parameter("intensity", v)
		elif n is OmniLight3D:
			n.light_energy = 0.8 * v


## Base com o Y apontando para `dir`.
static func basis_along(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.UP if absf(y.y) < 0.95 else Vector3.FORWARD
	var x := ref.cross(y).normalized()
	return Basis(x, y, x.cross(y))


## A invocação: uma lâmina em cada `points[i]`, que vai disparar para `dirs[i]`; dura `time` s e some (quem
## chamou solta os projétis nesse instante, dos mesmos pontos).
## `hover` (opcional): onde cada lâmina fica no ar antes de mirar; ao deitar para a mira ela vai para `points[i]`.
static func charge(root: Node, points: Array, dirs: Array, time: float, length := 1.7, c := RED, hover: Array = []) -> Node3D:
	var ch := Charge.new()
	ch.hover = hover if hover.size() == points.size() else points
	ch.points = points
	ch.dirs = dirs
	ch.time = time
	ch.length = length
	ch.color = c
	root.add_child(ch)
	return ch


## O acerto em `pos`.
static func impact(root: Node, pos: Vector3, c := RED) -> void:
	if root == null or not root.is_inside_tree():
		return
	var box := Node3D.new()
	root.add_child(box)
	box.global_position = pos
	_flare(box, ORANGE, 1.7, 0.26, 0.7, 0.32)
	_flare(box, c, 2.6, 0.34, -0.5, 0.28)
	var light := OmniLight3D.new()
	light.light_color = c.lerp(ORANGE, 0.3)
	light.light_energy = 3.0
	light.omni_range = 5.0
	light.shadow_enabled = false
	box.add_child(light)
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = c.lerp(ORANGE, 0.5) * 2.5
	q.material = m
	p.mesh = q
	p.amount = 22
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 0.6
	p.lifetime_randomness = 0.5
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(0.0, -6.0, 0.0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	box.add_child(p)
	p.emitting = true
	var tw := box.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.45).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.35)
	tw.tween_callback(box.queue_free)


static func _flare(box: Node3D, c: Color, size: float, time: float, turn: float, gain: float) -> void:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = FLARE
	mat.set_shader_parameter("flare", FLARE_TEX)
	mat.render_priority = 5
	qm.material = mat
	q.mesh = qm
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	q.extra_cull_margin = size
	var rot0 := randf() * TAU
	q.set_instance_shader_parameter("col", Vector3(c.r, c.g, c.b))
	q.set_instance_shader_parameter("intensity", gain)
	q.set_instance_shader_parameter("spin", rot0)
	box.add_child(q)
	q.scale = Vector3.ONE * size * 0.3
	var tw := q.create_tween().set_parallel(true)
	tw.tween_property(q, "scale", Vector3.ONE * size, time * 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_method(func(v: float) -> void: q.set_instance_shader_parameter("spin", v), rot0, rot0 + turn, time)
	tw.tween_method(func(v: float) -> void: q.set_instance_shader_parameter("intensity", v), gain, 0.0, time) \
		.set_delay(time * 0.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_callback(q.queue_free)


## As lâminas no ar antes do disparo.
class Charge:
	extends Node3D

	const RISE := 0.16       ## cada lâmina abre neste tempo (s)
	const RING := 0.42       ## o aro de invocação dura isto (s)
	const AIM := 0.28        ## nos últimos AIM s as lâminas deitam para a mira
	const SPREAD := 0.6      ## as lâminas nascem ao longo desta fração do tempo total

	var points: Array = []
	var hover: Array = []
	var dirs: Array = []
	var time := 0.9
	var length := 1.7
	var color := RuneBladesFX.RED
	var _t := 0.0
	var _blades: Array[Node3D] = []
	var _rings: Array[MeshInstance3D] = []
	var _born: Array[float] = []
	var _ring_mat: StandardMaterial3D

	func _ready() -> void:
		top_level = true
		global_transform = Transform3D.IDENTITY
		_ring_mat = StandardMaterial3D.new()
		_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_ring_mat.albedo_color = color
		var tor := TorusMesh.new()
		tor.inner_radius = 0.93
		tor.outer_radius = 1.0
		tor.rings = 40
		tor.ring_segments = 4
		var n := points.size()
		for i in n:
			var b := RuneBladesFX.make_blade(length, color)
			add_child(b)
			b.global_position = hover[i]
			b.scale = Vector3.ONE * 0.001
			_blades.append(b)
			_born.append(time * SPREAD * float(i) / maxf(1.0, float(n - 1)) if n > 1 else 0.0)
			var r := MeshInstance3D.new()
			r.mesh = tor
			r.material_override = _ring_mat.duplicate()
			r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			r.visible = false
			add_child(r)
			r.global_position = hover[i]
			r.rotation = Vector3(randf() * TAU, randf() * TAU, 0.0)
			_rings.append(r)

	func _process(delta: float) -> void:
		_t += delta
		if _t >= time:
			queue_free()
			return
		var aim := clampf((_t - (time - AIM)) / (AIM * 0.8), 0.0, 1.0)
		aim = aim * aim * (3.0 - 2.0 * aim)
		for i in _blades.size():
			var age := _t - _born[i]
			var b := _blades[i]
			var r := _rings[i]
			if age < 0.0:
				continue
			var k := clampf(age / RISE, 0.0, 1.0)
			var pop := 1.0 + 0.25 * sin(k * PI)    # passa um pouco do tamanho e volta
			b.scale = Vector3.ONE * maxf(0.001, k * pop)
			var d: Vector3 = dirs[i]
			# em leque: as do meio em pé, as das pontas tombadas para fora
			var side := d.cross(Vector3.UP).normalized()
			var lean := lerpf(-1.0, 1.0, float(i) / maxf(1.0, float(_blades.size() - 1))) if _blades.size() > 1 else 0.0
			var up := (Vector3.UP + side * lean * 0.85 + d * 0.3).normalized()
			var q0 := RuneBladesFX.basis_along(up).get_rotation_quaternion()
			var q1 := RuneBladesFX.basis_along(d).get_rotation_quaternion()
			b.global_basis = Basis(q0.slerp(q1, aim)).scaled(b.scale)
			b.global_position = (hover[i] as Vector3).lerp(points[i], aim) + Vector3.UP * sin(age * 5.0 + float(i)) * 0.06 * (1.0 - aim)
			var rk := clampf(age / RING, 0.0, 1.0)
			r.visible = rk < 1.0
			if r.visible:
				r.scale = Vector3.ONE * length * lerpf(0.12, 0.45, 1.0 - pow(1.0 - rk, 2.0))
				r.rotate_object_local(Vector3.UP, delta * 9.0)
				r.rotate_object_local(Vector3.RIGHT, delta * 4.0)
				(r.material_override as StandardMaterial3D).albedo_color = color * (1.8 * (1.0 - rk))
