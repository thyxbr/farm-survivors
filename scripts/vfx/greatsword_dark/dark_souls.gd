class_name DarkSouls
extends Node3D
## Lâmina Suprema: as almas que saem voando de dentro da cratera e fogem em várias direções. Cada alma é um quad de pé
## na direção do voo (dark_soul.gdshader: cabeça pálida gritando e cauda de fumaça) com um rastro violeta atrás
## (soul_trail.gdshader, fita montada das últimas posições, de frente para a câmera).
## Voo: nasce dentro da cratera (GreatswordSupremeRules.soul_spawn), sobe depressa e se vira para longe dela
## (soul_flee_dir), acelerando como quem foge, serpenteando de lado e para cima; no fim da vida some e se desfaz.
## top_level: as almas ficam no mundo. O nó sai sozinho (queue_free) quando a última some.

const SOUL_MAT := preload("res://assets/vfx/greatsword_dark/dark_soul_mat.tres")
const TRAIL_MAT := preload("res://assets/vfx/greatsword_dark/soul_trail_mat.tres")
const TRAIL_POINTS := 14
const TRAIL_STEP := 0.035     ## um ponto do rastro a cada tanto (s)
const TRAIL_WIDTH := 0.12     ## em fração do tamanho da alma
const RISE_TIME := 0.35       ## a subida de dentro da cratera (s)

var _souls: Array[Dictionary] = []
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY


## Quantas almas ainda voam (ou ainda vão sair).
func active_count() -> int:
	return _souls.size()


## Solta `count` almas ao longo da cratera de `start` a `end` (meia largura `half_width`), ao longo de `stagger` s.
func spawn(start: Vector3, end: Vector3, half_width: float, count: int, speed: float, life: float, stagger: float,
		size: float, seed_v: int) -> void:
	_rng.seed = seed_v
	for i in count:
		var along := (float(i) + _rng.randf_range(0.1, 0.9)) / float(maxi(count, 1))
		var from := GreatswordSupremeRules.soul_spawn(start, end, half_width, along, _rng.randf()) + Vector3.UP * 0.05
		var flee := GreatswordSupremeRules.soul_flee_dir(start, end, from, _rng.randf())
		var head := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		q.center_offset = Vector3(0, -0.5, 0)   # a cabeça no ponto da alma, a cauda atrás
		head.mesh = q
		head.material_override = SOUL_MAT
		head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		head.extra_cull_margin = 2.0
		head.visible = false
		add_child(head)
		var sd := _rng.randf() * 10.0
		head.set_instance_shader_parameter("seed", sd)
		var tr := MeshInstance3D.new()
		var im := ImmediateMesh.new()
		tr.mesh = im
		tr.material_override = TRAIL_MAT
		tr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tr.extra_cull_margin = 4.0
		add_child(tr)
		var sz := size * _rng.randf_range(0.75, 1.2)
		_souls.append({"head": head, "trail": tr, "mesh": im, "at": _t + stagger * float(i) / float(maxi(count, 1))
			+ _rng.randf_range(0.0, 0.08), "pos": from, "vel": Vector3.UP * _rng.randf_range(3.0, 5.0),
			"flee": flee, "speed": speed * _rng.randf_range(0.8, 1.25), "life": life * _rng.randf_range(0.8, 1.15),
			"size": sz, "wob": _rng.randf_range(2.5, 4.5), "phase": _rng.randf() * TAU, "climb": _rng.randf_range(0.6, 1.8),
			"hist": [], "hist_t": 0.0, "seed": sd, "voice": i % 4 == 0})


func _process(delta: float) -> void:
	_t += delta
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var cam_pos := cam.global_position if cam != null else Vector3(0, 10, 10)
	var i := 0
	while i < _souls.size():
		var s: Dictionary = _souls[i]
		var age := _t - float(s.at)
		if age < 0.0:
			i += 1
			continue
		var life: float = s.life
		if age >= life:
			(s.head as Node).queue_free()
			(s.trail as Node).queue_free()
			_souls.remove_at(i)
			continue
		if not (s.head as MeshInstance3D).visible:
			(s.head as MeshInstance3D).visible = true
			if bool(s.voice):
				Sfx.play_at("portal", s.pos, 0.25, -14.0)
		_fly(s, age, delta)
		_draw(s, age, cam_pos, delta)
		i += 1
	if _souls.is_empty():
		queue_free()


## Sobe de dentro da cratera, vira para longe dela acelerando (fugindo) e serpenteia de lado e para cima.
func _fly(s: Dictionary, age: float, delta: float) -> void:
	var flee: Vector3 = s.flee
	var side := Vector3.UP.cross(flee).normalized()
	var k := smoothstep(0.0, RISE_TIME, age)
	var spd: float = float(s.speed) * lerpf(0.3, 1.0, k) * (1.0 + 0.35 * age)
	var wob := sin(age * float(s.wob) + float(s.phase))
	var want := (flee * spd + side * wob * spd * 0.45 + Vector3.UP * (float(s.climb) + 2.5 * (1.0 - k) + cos(age * 3.1 + float(s.phase)) * 0.8))
	var v: Vector3 = (s.vel as Vector3).lerp(want, 1.0 - exp(-4.5 * delta))
	s.vel = v
	s.pos = (s.pos as Vector3) + v * delta


func _draw(s: Dictionary, age: float, cam_pos: Vector3, delta: float) -> void:
	var life: float = s.life
	var fade := smoothstep(0.0, 0.15, age) * (1.0 - smoothstep(life - 0.7, life, age))
	var pos: Vector3 = s.pos
	var v: Vector3 = s.vel
	var dir := v.normalized() if v.length() > 0.01 else Vector3.UP
	var sz: float = float(s.size) * (0.6 + 0.4 * smoothstep(0.0, 0.3, age)) * (1.0 - 0.3 * smoothstep(life - 0.7, life, age))
	# o quad de pé na direção do voo (o shader gira em volta dele para a câmera): a malha vai de Y = 0 (a cabeça, no
	# ponto da alma) a Y = -1 (a ponta da cauda), então o eixo Y do nó aponta para a frente do voo
	var y := dir * sz
	var x := dir.cross(Vector3.UP)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized() * sz * 0.55
	var head: MeshInstance3D = s.head
	head.global_transform = Transform3D(Basis(x, y, x.cross(y).normalized()), pos)
	head.set_instance_shader_parameter("intensity", fade)
	# rastro: guarda um ponto a cada TRAIL_STEP
	var hist: Array = s.hist
	s.hist_t = float(s.hist_t) + delta
	if hist.is_empty() or float(s.hist_t) >= TRAIL_STEP:
		s.hist_t = 0.0
		hist.push_front(pos - dir * sz * 0.35)
		if hist.size() > TRAIL_POINTS:
			hist.pop_back()
	var im: ImmediateMesh = s.mesh
	im.clear_surfaces()
	if hist.size() < 2:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := sz * TRAIL_WIDTH
	var prev_a := Vector3.ZERO
	var prev_b := Vector3.ZERO
	var prev_u := 0.0
	for k in hist.size():
		var p: Vector3 = hist[k]
		var nxt: Vector3 = hist[mini(k + 1, hist.size() - 1)]
		var prv: Vector3 = hist[maxi(k - 1, 0)]
		var along := (prv - nxt)
		var side := along.cross(cam_pos - p)
		side = side.normalized() if side.length() > 0.0001 else Vector3.RIGHT
		var u := float(k) / float(hist.size() - 1)
		var a := p + side * w * (1.0 - u * 0.6)
		var b := p - side * w * (1.0 - u * 0.6)
		if k > 0:
			var c0 := Color(float(s.seed) * 0.1, 0, 0, fade)
			_vtx(im, prev_a, Vector2(prev_u, 0.0), c0)
			_vtx(im, prev_b, Vector2(prev_u, 1.0), c0)
			_vtx(im, b, Vector2(u, 1.0), c0)
			_vtx(im, prev_a, Vector2(prev_u, 0.0), c0)
			_vtx(im, b, Vector2(u, 1.0), c0)
			_vtx(im, a, Vector2(u, 0.0), c0)
		prev_a = a
		prev_b = b
		prev_u = u
	im.surface_end()


func _vtx(im: ImmediateMesh, p: Vector3, uv: Vector2, c: Color) -> void:
	im.surface_set_uv(uv)
	im.surface_set_color(c)
	im.surface_add_vertex(p)
