class_name HolyFX
extends RefCounted
## Efeitos de luz sagrada do healer (cetro) no estilo "desenhado", o mesmo conceito do corte da espada
## (FXToon / fx_slash): poucas formas grandes em malha, borda dura, três tons chapados (núcleo quase
## branco, meio saturado, borda escura), uma camada de sombra atrás (maior e atrasada), animação "em
## dois" (o ruído muda a 12 quadros por segundo) e sumiço por erosão em vez de transparência. Nada de
## partícula aditiva: o bloom do cenário estourava colunas finas em borrões brancos.
## Formas (shaders/fx_holy_*.gdshader): coluna de feixes, selo no chão, estrela, pincelada em fita e
## domo de silhueta. Cada efeito é uma receita de camadas. Nada aparece no servidor dedicado.

const SHADERS := {
	"column": preload("res://shaders/fx_holy_column.gdshader"),
	"seal": preload("res://shaders/fx_holy_seal.gdshader"),
	"star": preload("res://shaders/fx_holy_star.gdshader"),
	"stroke": preload("res://shaders/fx_holy_stroke.gdshader"),
	"dome": preload("res://shaders/fx_holy_dome.gdshader"),
}
const GOLD := Color(1.0, 0.87, 0.4)
const LIFE := Color(0.36, 0.93, 0.5)          ## verde da cura
## Paletas de três tons (como FXToon.palette, mas escolhidas à mão: a borda da luz é clara e quente —
## escura e laranja lê como fogo, não como luz sagrada).
const PAL_GOLD := {"core": Color(1.0, 1.0, 0.93), "mid": GOLD, "edge": Color(0.98, 0.64, 0.14)}
const PAL_LIFE := {"core": Color(0.93, 1.0, 0.9), "mid": LIFE, "edge": Color(0.06, 0.45, 0.38)}
const PAL_WARD := {"core": Color(0.95, 0.98, 1.0), "mid": Color(0.55, 0.8, 1.0), "edge": Color(0.22, 0.45, 0.88)}

static var _mats := {}
static var _tube: ArrayMesh
static var _plane: PlaneMesh
static var _quad: QuadMesh
static var _hemi: SphereMesh


# ------------------------------------------------------------------ base
static func _mat(key: String) -> ShaderMaterial:
	var m: ShaderMaterial = _mats.get(key)
	if m == null:
		m = ShaderMaterial.new()
		m.shader = SHADERS[key]
		_mats[key] = m
	return m


## Paleta da camada de sombra: só os tons de borda, sem núcleo.
static func _shade(pal: Dictionary) -> Dictionary:
	return {"core": pal.edge, "mid": pal.edge, "edge": (pal.edge as Color).darkened(0.3)}


## Tubo aberto de raio 1 e altura 1 (base em y = 0). UV.x em volta, UV.y = 0 na base e 1 no topo.
static func tube_mesh() -> ArrayMesh:
	if _tube != null:
		return _tube
	var seg := 24
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in seg + 1:
		var u := float(i) / seg
		var a := TAU * u
		verts.append(Vector3(cos(a), 0.0, sin(a)))
		uvs.append(Vector2(u, 0.0))
		verts.append(Vector3(cos(a), 1.0, sin(a)))
		uvs.append(Vector2(u, 1.0))
		if i < seg:
			var b := i * 2
			idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
	_tube = _build(verts, uvs, idx)
	return _tube


## Fita ao longo de `points`, com meia largura `sides[i]` em cada ponto. UV.x = 0 no primeiro ponto
## (cauda) e 1 no último (ponta); UV.y atravessa a fita.
static func ribbon_mesh(points: PackedVector3Array, sides: PackedVector3Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var n := points.size()
	for i in n:
		var u := float(i) / (n - 1)
		verts.append(points[i] - sides[i])
		uvs.append(Vector2(u, 0.0))
		verts.append(points[i] + sides[i])
		uvs.append(Vector2(u, 1.0))
		if i < n - 1:
			var b := i * 2
			idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
	return _build(verts, uvs, idx)


static func _build(verts: PackedVector3Array, uvs: PackedVector2Array, idx: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Uma camada de efeito: malha `mesh` com o shader `key` e a paleta `pal` (ainda fora da árvore).
static func _shape(key: String, mesh: Mesh, pal: Dictionary, shadow := false) -> Shape:
	var s := Shape.new()
	s.mesh = mesh
	s.material_override = _mat(key)
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.seed0 = randf() * 20.0
	var p := _shade(pal) if shadow else pal
	s.set_instance_shader_parameter("col_core", p.core)
	s.set_instance_shader_parameter("col_mid", p.mid)
	s.set_instance_shader_parameter("col_edge", p.edge)
	s.set_instance_shader_parameter("core", 0.0 if shadow else 1.0)
	if shadow:
		s.sorting_offset = -0.1
	return s


static func _put(s: Shape, pos: Vector3) -> bool:
	var root := FX._scene()
	if root == null:
		s.free()
		return false
	root.add_child(s)
	s.global_position = pos
	return true


## Uma forma animada: abre em `grow_t` (escala de scale0 a scale1 e `head` de 0 a 1), segura `hold` e
## se desfaz por erosão em `fade`. O ruído muda a 12 quadros por segundo, como desenho quadro a quadro.
class Shape extends MeshInstance3D:
	var delay := 0.0
	var grow_t := 0.12
	var hold := 0.1
	var fade := 0.3
	var seed0 := 0.0
	var scale0 := Vector3.ONE
	var scale1 := Vector3.ONE
	var ease_pow := 2.5       ## 1 = abre em velocidade constante; maior = estala e freia
	var rise := Vector3.ZERO  ## velocidade (m/s), freando
	var trail := -1.0         ## >= 0: a cauda da pincelada segue a ponta a esta distância (fração da fita)
	var _age := 0.0

	func _ready() -> void:
		_apply()

	func _process(delta: float) -> void:
		_age += delta
		var t := _age - delay
		if t >= grow_t + hold + fade:
			queue_free()
			return
		if t > 0.0 and rise != Vector3.ZERO:
			position += rise * delta
			rise *= exp(-2.2 * delta)
		_apply()

	func _apply() -> void:
		var t := _age - delay
		visible = t >= 0.0
		if not visible:
			return
		var k := clampf(t / grow_t, 0.0, 1.0)
		var h := 1.0 - pow(1.0 - k, ease_pow)
		var out := clampf((t - grow_t - hold) / fade, 0.0, 1.0)
		set_instance_shader_parameter("head", h)
		set_instance_shader_parameter("erode", out)
		set_instance_shader_parameter("seed", seed0 + floorf(t * 12.0) * 0.13)
		if trail >= 0.0:
			set_instance_shader_parameter("tail", lerpf(maxf(0.0, h - trail), h, 0.6 * out * out))
		scale = scale0.lerp(scale1, h) * (1.0 + 0.05 * out)


# ------------------------------------------------------------------ peças
## Coluna de luz em `pos` (base no chão): feixes de pincel que sobem num estalo e se desfazem.
## `o`: dense (> 1 = feixes mais cheios), delay (atrasa o começo: raios em sequência), alpha (< 1 = coluna
## translúcida, suave) e core (< 1 = menos branco no miolo).
static func pillar(pos: Vector3, pal: Dictionary, radius := 0.6, height := 3.5, time := 0.8, o := {}) -> void:
	var alpha: float = o.get("alpha", 1.0)
	for layer in 2:
		var shadow := layer == 0
		var s := _shape("column", tube_mesh(), pal, shadow)
		var r := radius * (1.2 if shadow else 1.0)
		var mid: Color = (_shade(pal) if shadow else pal).mid
		s.set_instance_shader_parameter("col_mid", Color(mid.r, mid.g, mid.b, alpha * (0.6 if shadow and alpha < 1.0 else 1.0)))
		if not shadow:
			s.set_instance_shader_parameter("core", float(o.get("core", 1.0)))
		s.delay = float(o.get("delay", 0.0)) + (0.03 if shadow else 0.0)
		s.grow_t = time * 0.2
		s.hold = time * 0.3
		s.fade = time * 0.5
		s.scale0 = Vector3(r * 0.5, height * 0.6, r * 0.5)
		s.scale1 = Vector3(r, height, r)
		s.set_instance_shader_parameter("dense", float(o.get("dense", 1.0)))
		_put(s, pos)


## Selo no chão em `pos`: anel de pincel que se desenha em volta e abre até `radius`.
## `o`: glyph (cruz no centro), ticks (marcas radiais), thick, inner (anel de dentro), delay.
static func seal(pos: Vector3, pal: Dictionary, radius: float, time := 0.9, o := {}) -> void:
	if _plane == null:
		_plane = PlaneMesh.new()
		_plane.size = Vector2(2, 2)
	for layer in 2:
		var shadow := layer == 0
		var s := _shape("seal", _plane, pal, shadow)
		var r := radius * (1.05 if shadow else 1.0)
		s.delay = float(o.get("delay", 0.0)) + (0.03 if shadow else 0.0)
		s.grow_t = time * 0.3
		s.hold = time * 0.25
		s.fade = time * 0.45
		s.scale0 = Vector3(r * 0.55, 1.0, r * 0.55)
		s.scale1 = Vector3(r, 1.0, r)
		s.set_instance_shader_parameter("thick", float(o.get("thick", 0.12)) * (1.25 if shadow else 1.0))
		s.set_instance_shader_parameter("glyph", 1.0 if o.get("glyph", false) else 0.0)
		s.set_instance_shader_parameter("ticks", float(o.get("ticks", 0)))
		s.set_instance_shader_parameter("inner", 1.0 if o.get("inner", true) else 0.0)
		_put(s, pos + Vector3.UP * (0.05 if shadow else 0.07))


## Estrela de frente para a câmera em `pos`. `o`: points, sharp, body (forma), delay, grow, hold, fade,
## rise (velocidade), shadow (camada de sombra atrás).
static func star(pos: Vector3, pal: Dictionary, size: float, o := {}) -> void:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(2, 2)
	for layer in (2 if o.get("shadow", false) else 1):
		var shadow: bool = o.get("shadow", false) and layer == 0
		var s := _shape("star", _quad, pal, shadow)
		var sz := size * (1.22 if shadow else 1.0)
		s.delay = float(o.get("delay", 0.0)) + (0.03 if shadow else 0.0)
		s.grow_t = o.get("grow", 0.07)
		s.hold = o.get("hold", 0.08)
		s.fade = o.get("fade", 0.25)
		s.rise = o.get("rise", Vector3.ZERO)
		s.scale0 = Vector3.ONE * sz * 0.35
		s.scale1 = Vector3.ONE * sz
		s.set_instance_shader_parameter("points", float(o.get("points", 4)))
		s.set_instance_shader_parameter("sharp", float(o.get("sharp", 5.0)))
		s.set_instance_shader_parameter("body", float(o.get("body", 0.16)))
		_put(s, pos)


## `count` brilhos de 4 pontas espalhados em volta de `pos` (raio `spread`), saindo com `speed` m/s
## para cima (`up` = 1) ou para todos os lados (`up` = 0), uns depois dos outros.
static func sparkles(pos: Vector3, pal: Dictionary, count: int, spread: float, speed: float, up := 1.0, size := 0.3) -> void:
	for i in count:
		var a := TAU * (i + randf() * 0.6) / count
		var out := Vector3(cos(a), 0.0, sin(a))
		var dir := (out * (1.0 - up) + Vector3.UP * (up + randf() * 0.3)).normalized()
		star(pos + out * spread * randf_range(0.5, 1.0) + Vector3.UP * randf() * 0.6, pal, size * randf_range(0.6, 1.25),
			{"delay": randf() * 0.25, "hold": randf_range(0.1, 0.3), "fade": 0.3, "rise": dir * speed * randf_range(0.6, 1.0)})


## Onda de choque em domo: a silhueta de meia esfera abre até `radius` e se desfaz.
static func dome(pos: Vector3, pal: Dictionary, radius: float, time := 0.55) -> void:
	if _hemi == null:
		_hemi = SphereMesh.new()
		_hemi.radius = 1.0
		_hemi.height = 1.0
		_hemi.is_hemisphere = true
		_hemi.radial_segments = 32
		_hemi.rings = 12
	var s := _shape("dome", _hemi, pal)
	s.grow_t = time * 0.55
	s.hold = 0.0
	s.fade = time * 0.45
	s.scale0 = Vector3.ONE * radius * 0.3
	s.scale1 = Vector3(radius, radius * 0.5, radius)
	_put(s, pos)


static func _flash(pos: Vector3, color: Color, energy: float, range_m: float, time: float) -> void:
	FXEpic.flash(pos, color, energy, range_m, time)


# ------------------------------------------------------------------ cura
## Cura recebida em `pos` (pés do personagem): coluna de feixes verdes, selo com a cruz no chão e
## brilhos subindo. `big` = Banquete do Herói.
static func heal_burst(pos: Vector3, big := false) -> void:
	if FX._scene() == null:
		return
	# coluna suave: translúcida, pouco branco e mais vazada (opaca e cheia virava uma faixa de luz forte demais)
	pillar(pos, PAL_LIFE, 0.8 if big else 0.52, 4.0 if big else 2.7, 0.9 if big else 0.75, {"alpha": 0.45, "core": 0.3, "dense": 0.8})
	seal(pos, PAL_LIFE, 1.9 if big else 1.4, 1.0, {"glyph": true, "ticks": 12})
	sparkles(pos + Vector3.UP * 0.4, PAL_LIFE, 8 if big else 6, 0.7, 2.6, 1.0, 0.32)
	sparkles(pos + Vector3.UP * 0.9, PAL_GOLD, 3, 0.5, 2.0, 1.0, 0.24)
	_flash(pos + Vector3.UP * 1.2, LIFE, 1.0, 4.0, 0.4)


## Pincelada de luz em arco de `from` até `target`, com um brilho na ponta; a cura estoura ao chegar.
## `burst` = toca heal_burst no alvo ao chegar (quem só assiste); falso = só um brilho (o curado já vê
## o próprio heal_burst, vindo de receive_heal).
static func heal_beam(from: Vector3, target: Node3D, burst := true) -> void:
	var root := FX._scene()
	if root == null or target == null or not is_instance_valid(target):
		return
	var end := target.global_position + Vector3.UP * 1.1
	var dist := from.distance_to(end)
	var dur := clampf(dist / 20.0, 0.2, 0.6)
	var mid := from.lerp(end, 0.5) + Vector3.UP * clampf(dist * 0.22, 0.6, 3.0)
	var cam := root.get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else from + Vector3(0, 2, 6)
	var half_w := 0.26
	var pts := PackedVector3Array()
	var sides := PackedVector3Array()
	var n := 24
	for i in n + 1:
		var t := float(i) / n
		var p := from.lerp(mid, t).lerp(mid.lerp(end, t), t)
		var tan := (mid - from).lerp(end - mid, t).normalized()
		var side := tan.cross(eye - p).normalized()
		pts.append(p)
		sides.append(side * half_w)
	var mesh := ribbon_mesh(pts, sides)
	for layer in 2:
		var shadow := layer == 0
		var s := _shape("stroke", mesh, PAL_LIFE, shadow)
		s.delay = 0.02 if shadow else 0.0
		s.grow_t = dur
		s.ease_pow = 1.3
		s.hold = 0.02
		s.fade = 0.22
		s.trail = 0.6
		s.set_instance_shader_parameter("len", dist / (half_w * 2.0))
		_put(s, Vector3.ZERO)
	star(from, PAL_LIFE, 0.5, {"hold": 0.05, "fade": 0.2})
	root.get_tree().create_timer(dur).timeout.connect(func() -> void:
		var at := (target.global_position + Vector3.UP * 1.1) if is_instance_valid(target) else end
		if burst:
			heal_burst(at - Vector3.UP * 1.1)
		else:
			star(at, PAL_LIFE, 0.9, {"hold": 0.06, "fade": 0.25, "shadow": true}))


## Mãos brilhando enquanto a Cura espera o alvo: brilhos verdes subindo de `parent`. Solte com queue_free.
static func charge_stream(parent: Node3D) -> Node3D:
	if FX._scene() == null or parent == null or not is_instance_valid(parent):
		return null
	var c := Charge.new()
	parent.add_child(c)
	return c


## Emissor dos brilhos da Cura preparada (um brilho a cada 0,14 s).
class Charge extends Node3D:
	var _t := 0.0

	func _process(delta: float) -> void:
		_t -= delta
		if _t > 0.0:
			return
		_t = 0.14
		var off := Vector3(randf_range(-0.2, 0.2), randf_range(-0.1, 0.15), randf_range(-0.2, 0.2))
		HolyFX.star(global_position + off, HolyFX.PAL_LIFE, randf_range(0.16, 0.3),
			{"hold": 0.12, "fade": 0.25, "rise": Vector3(0, randf_range(0.6, 1.3), 0)})


# ------------------------------------------------------------------ auras de buff (BuffAura)
## Forma permanente de uma aura: só o ruído anda (12 quadros por segundo) e a peça gira devagar.
class Loop extends MeshInstance3D:
	var seed0 := 0.0
	var spin := 0.0
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		set_instance_shader_parameter("seed", seed0 + floorf(_t * 12.0) * 0.13)
		if spin != 0.0:
			rotation.y += spin * delta


static func _loop(key: String, mesh: Mesh, pal: Dictionary, alpha: float, core: float, erode: float) -> Loop:
	var l := Loop.new()
	l.mesh = mesh
	l.material_override = _mat(key)
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.seed0 = randf() * 20.0
	var mid: Color = pal.mid
	l.set_instance_shader_parameter("col_core", pal.core)
	l.set_instance_shader_parameter("col_mid", Color(mid.r, mid.g, mid.b, alpha))
	l.set_instance_shader_parameter("col_edge", pal.edge)
	l.set_instance_shader_parameter("core", core)
	l.set_instance_shader_parameter("head", 1.0)
	l.set_instance_shader_parameter("erode", erode)
	return l


## Selo desenhado no chão de uma aura (raio `radius`), girando devagar.
static func aura_seal(pal: Dictionary, radius: float) -> MeshInstance3D:
	if _plane == null:
		_plane = PlaneMesh.new()
		_plane.size = Vector2(2, 2)
	var l := _loop("seal", _plane, pal, 0.8, 0.6, 0.12)
	l.spin = 0.5
	l.scale = Vector3(radius, 1.0, radius)
	l.set_instance_shader_parameter("thick", 0.09)
	l.set_instance_shader_parameter("ticks", 12.0)
	return l


## Feixes de luz suaves em volta do corpo (origem nos pés): a coluna da habilidade, translúcida e vazada.
static func aura_column(pal: Dictionary, radius := 0.55, height := 2.0) -> MeshInstance3D:
	var l := _loop("column", tube_mesh(), pal, 0.38, 0.25, 0.32)
	l.spin = 0.35
	l.scale = Vector3(radius, height, radius)
	l.set_instance_shader_parameter("dense", 0.75)
	return l


## Brilhos de 4 pontas nascendo em volta do corpo de tempos em tempos (filho do modelo).
static func aura_stars(pal: Dictionary) -> Node3D:
	var t := Twinkle.new()
	t.pal = pal
	return t


class Twinkle extends Node3D:
	var pal := {}
	var _t := 0.0

	func _process(delta: float) -> void:
		_t -= delta
		if _t > 0.0:
			return
		_t = randf_range(0.3, 0.5)
		var a := randf() * TAU
		var at := global_position + Vector3(cos(a) * 0.6, randf_range(0.3, 1.8), sin(a) * 0.6)
		HolyFX.star(at, pal, randf_range(0.16, 0.28), {"hold": 0.15, "fade": 0.3, "rise": Vector3(0, 0.5, 0)})


# ------------------------------------------------------------------ dano
## Uma camada da lança: dois cones de 4 lados (ponta à frente em +Z, rabo curto atrás).
static func _lance_layer(vis: Node3D, color: Color, k: float, hull: bool) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	if hull:
		mat.cull_mode = BaseMaterial3D.CULL_FRONT   # casca invertida: só a silhueta em volta
	var grow := 1.0 + (k - 1.0) * 0.1
	for part in [[1.15, 1.0], [0.5, -1.0]]:      # [comprimento, sentido]
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.075 * k
		cm.height = float(part[0]) * grow
		cm.radial_segments = 4
		cm.rings = 1
		cm.cap_bottom = false
		cm.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.rotation.x = PI * 0.5 * float(part[1])   # eixo Y do cone vira +Z (ponta) ou -Z (rabo)
		mi.position.z = float(part[0]) * 0.5 * float(part[1])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		vis.add_child(mi)


## Visual da Lança de Luz dentro do projétil `owner` (`vis` gira para a direção do voo, +Z à frente):
## lança em três tons (miolo claro e duas cascas de contorno), rastro de pincelada em cruz e a guarda.
static func build_lance(vis: Node3D, owner: Node3D, life: float) -> void:
	if FX._scene() == null:
		return
	_lance_layer(vis, PAL_GOLD.core, 1.0, false)
	_lance_layer(vis, PAL_GOLD.mid, 2.0, true)
	_lance_layer(vis, PAL_GOLD.edge, 2.9, true)
	# rastro: duas fitas em cruz atrás da lança, com a ponta da pincelada junto dela
	var pts := PackedVector3Array()
	for i in 9:
		pts.append(Vector3(0, 0, lerpf(-2.9, -0.15, i / 8.0)))
	for side in [Vector3.RIGHT, Vector3.UP]:
		var sides := PackedVector3Array()
		sides.resize(pts.size())
		sides.fill(side * 0.22)
		var s := _shape("stroke", ribbon_mesh(pts, sides), PAL_GOLD)
		s.grow_t = 0.03
		s.hold = life + 0.2
		s.fade = 0.05
		s.set_instance_shader_parameter("len", 6.0)
		vis.add_child(s)
	# guarda: brilho de 4 pontas na base da ponta
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(2, 2)
	var g := _shape("star", _quad, PAL_GOLD)
	g.grow_t = 0.03
	g.hold = life + 0.2
	g.fade = 0.05
	g.scale0 = Vector3.ONE * 0.42
	g.scale1 = Vector3.ONE * 0.42
	vis.add_child(g)
	var light := OmniLight3D.new()
	light.light_color = GOLD
	light.light_energy = 1.6
	light.omni_range = 4.5
	owner.add_child(light)


## Impacto da Lança de Luz em `pos` (voando na direção `dir`): estouro de pontas, anel e brilhos.
static func lance_impact(pos: Vector3, dir: Vector3) -> void:
	if FX._scene() == null:
		return
	star(pos, PAL_GOLD, 1.7, {"points": 9, "sharp": 2.2, "body": 0.3, "grow": 0.05, "hold": 0.07, "fade": 0.22, "shadow": true})
	seal(pos - Vector3.UP * 1.0, PAL_GOLD, 1.5, 0.5, {"inner": false, "thick": 0.16})
	pillar(pos - Vector3.UP * 1.0, PAL_GOLD, 0.32, 2.6, 0.5)
	for i in 5:
		var d := (-dir + Vector3(randf_range(-1, 1), randf_range(-0.2, 1.0), randf_range(-1, 1))).normalized()
		star(pos, PAL_GOLD, randf_range(0.2, 0.34), {"hold": 0.12, "fade": 0.25, "rise": d * randf_range(4.0, 7.0)})
	_flash(pos, GOLD, 3.0, 6.0, 0.3)


## Explosão radiante do Escudo de Luz em `pos`: anel de pincel que abre no chão, domo de choque,
## coluna central, raios de luz em volta (em sequência) e um estouro no centro.
static func radiant_nova(pos: Vector3, radius: float) -> void:
	if FX._scene() == null:
		return
	seal(pos, PAL_GOLD, radius, 0.9, {"ticks": 16, "thick": 0.1})
	dome(pos, PAL_GOLD, radius, 0.6)
	pillar(pos, PAL_GOLD, 1.0, 5.5, 0.85, {"dense": 1.3})
	star(pos + Vector3.UP * 1.3, PAL_GOLD, 2.6, {"points": 12, "sharp": 2.0, "body": 0.28, "hold": 0.08, "fade": 0.25, "shadow": true})
	for i in 8:
		var a := TAU * i / 8.0 + randf() * 0.3
		pillar(pos + Vector3(cos(a), 0.0, sin(a)) * radius * 0.65, PAL_GOLD, 0.26, 3.4, 0.5, {"delay": 0.05 + 0.04 * i})
	sparkles(pos + Vector3.UP * 0.6, PAL_GOLD, 8, radius * 0.5, 4.0, 0.3, 0.36)
	_flash(pos + Vector3.UP * 1.5, GOLD, 4.0, radius * 1.4, 0.45)


## Luz caindo num inimigo atingido pela explosão radiante.
static func smite(pos: Vector3) -> void:
	if FX._scene() == null:
		return
	pillar(pos, PAL_GOLD, 0.34, 2.6, 0.45)
	star(pos + Vector3.UP * 0.9, PAL_GOLD, 0.9, {"points": 7, "sharp": 2.2, "body": 0.3, "hold": 0.06, "fade": 0.2})


## Banquete do Herói em `pos`: coluna dourada larga, selo com a cruz, anel até `radius` e brilhos.
static func feast(pos: Vector3, radius: float) -> void:
	if FX._scene() == null:
		return
	pillar(pos, PAL_GOLD, 1.1, 6.0, 1.1, {"alpha": 0.5, "core": 0.4})
	seal(pos, PAL_GOLD, 3.2, 1.3, {"glyph": true, "ticks": 16})
	seal(pos, PAL_LIFE, radius, 1.0, {"inner": false, "thick": 0.05, "delay": 0.08})
	dome(pos, PAL_GOLD, radius, 0.8)
	sparkles(pos + Vector3.UP * 0.5, PAL_GOLD, 10, 1.6, 3.4, 1.0, 0.4)
	sparkles(pos + Vector3.UP * 0.8, PAL_LIFE, 6, 2.4, 2.6, 1.0, 0.32)
	_flash(pos + Vector3.UP * 2.0, GOLD, 2.0, radius * 1.2, 0.6)
