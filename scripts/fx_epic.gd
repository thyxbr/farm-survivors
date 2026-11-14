class_name FXEpic
extends RefCounted
## Efeitos "épicos" criados por código: partículas com brilho aditivo, faíscas, fumaça,
## luz instantânea, marcas no chão, rastro de fita e hit stop. Base das habilidades.
## Nada disto roda no servidor dedicado (FX._scene() devolve null nele).

## Soma máxima de partículas vivas; acima disso novos emissores usam metade do amount.
const ACTIVE_LIMIT := 900

static var _active_amount := 0
static var _tex_glow: ImageTexture
static var _tex_smoke: ImageTexture
static var _tex_ring: ImageTexture
static var _tex_crack: ImageTexture
static var _tex_scorch: ImageTexture
static var _hs_until_ms := 0
static var _hs_active := false
static var _hs_guard: Node
## Materiais compartilhados (por textura/aditivo/sRGB). Material novo a cada efeito custava 10-20 ms:
## quando o último material de um tipo é liberado o Godot descarta o shader e o recompila no
## próximo efeito (engasgo em todo golpe depois de uns segundos parado). As cores vêm por vértice.
static var _mats := {}
static var _spark_mesh_c: ArrayMesh


# ---------------------------------------------------------------- texturas (geradas uma vez)
static func _make_tex(size: int, fn: Callable) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var u := (x + 0.5) / size * 2.0 - 1.0
			var v := (y + 0.5) / size * 2.0 - 1.0
			var a: float = fn.call(u, v)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


static func _glow_tex() -> ImageTexture:
	if _tex_glow == null:
		# núcleo brilhante com borda suave
		_tex_glow = _make_tex(64, func(u: float, v: float) -> float:
			var d := sqrt(u * u + v * v)
			if d >= 1.0:
				return 0.0
			var f := 1.0 - d
			return f * f * (0.5 + 0.5 * smoothstep(0.6, 0.0, d)))
	return _tex_glow


static func _smoke_tex() -> ImageTexture:
	if _tex_smoke == null:
		# nuvem irregular: disco suave modulado por ruído
		var noise := FastNoiseLite.new()
		noise.frequency = 0.045
		noise.seed = 7
		_tex_smoke = _make_tex(64, func(u: float, v: float) -> float:
			var d := sqrt(u * u + v * v)
			if d >= 1.0:
				return 0.0
			var n := noise.get_noise_2d((u + 1.0) * 32.0, (v + 1.0) * 32.0) * 0.5 + 0.5
			return smoothstep(1.0, 0.25, d) * (0.45 + 0.75 * n))
	return _tex_smoke


static func _ring_tex() -> ImageTexture:
	if _tex_ring == null:
		_tex_ring = _make_tex(128, func(u: float, v: float) -> float:
			var d := sqrt(u * u + v * v)
			var band := 1.0 - absf(d - 0.82) / 0.1
			var outer := 1.0 - absf(d - 0.6) / 0.03
			return maxf(maxf(band, 0.0), maxf(outer, 0.0) * 0.5) * smoothstep(1.0, 0.9, d))
	return _tex_ring


static func _scorch_tex() -> ImageTexture:
	if _tex_scorch == null:
		var noise := FastNoiseLite.new()
		noise.frequency = 0.05
		noise.seed = 21
		_tex_scorch = _make_tex(128, func(u: float, v: float) -> float:
			var d := sqrt(u * u + v * v)
			if d >= 1.0:
				return 0.0
			var n := noise.get_noise_2d((u + 1.0) * 64.0, (v + 1.0) * 64.0) * 0.5 + 0.5
			var edge := 0.55 + 0.4 * n
			return smoothstep(edge, edge - 0.35, d) * 0.95)
	return _tex_scorch


static func _crack_tex() -> ImageTexture:
	if _tex_crack == null:
		var noise := FastNoiseLite.new()
		noise.frequency = 0.06
		noise.seed = 3
		# rachaduras radiais: linhas finas em ângulos fixos, tortas por ruído
		_tex_crack = _make_tex(128, func(u: float, v: float) -> float:
			var d := sqrt(u * u + v * v)
			if d >= 1.0:
				return 0.0
			var ang := atan2(v, u)
			var wob := noise.get_noise_2d((u + 1.0) * 64.0, (v + 1.0) * 64.0) * 0.45
			var arms := 9.0
			var t := fposmod((ang + wob) / TAU * arms, 1.0)
			var line := 1.0 - absf(t - 0.5) * 2.0   # 1 no centro do braço
			var width := lerpf(0.16, 0.02, d)       # afina para a ponta
			var crack := smoothstep(1.0 - width * 2.0, 1.0, line) * smoothstep(1.0, 0.55, d)
			var core := smoothstep(0.3, 0.0, d) * 0.85
			return maxf(crack, core))
	return _tex_crack


# ---------------------------------------------------------------- materiais / emissores
static func _particle_mat(tex: Texture2D, additive: bool, srgb := false) -> StandardMaterial3D:
	var key := "%d/%s/%s" % [tex.get_instance_id(), additive, srgb]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	# cores em sRGB (como no resto do código) são convertidas; sem isso laranja e vermelho desbotam
	m.vertex_color_is_srgb = srgb
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.particles_anim_h_frames = 1
	m.particles_anim_v_frames = 1
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


## Faísca: dois quads em cruz ao longo de Y (visíveis de qualquer ângulo). Sem billboard,
## para o align_y das partículas alongar de verdade na direção da velocidade.
static func _spark_mesh() -> ArrayMesh:
	if _spark_mesh_c != null:
		return _spark_mesh_c
	var hw := 0.07
	var hl := 0.5
	var verts := PackedVector3Array([
		Vector3(-hw, -hl, 0), Vector3(hw, -hl, 0), Vector3(hw, hl, 0), Vector3(-hw, hl, 0),
		Vector3(0, -hl, -hw), Vector3(0, -hl, hw), Vector3(0, hl, hw), Vector3(0, hl, -hw)])
	var uvs := PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0),
		Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	var idx := PackedInt32Array([0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, _spark_mat())
	_spark_mesh_c = m
	return m


static func _spark_mat() -> StandardMaterial3D:
	if _mats.has("spark"):
		return _mats.spark
	var m := _particle_mat(_glow_tex(), true).duplicate() as StandardMaterial3D
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	_mats.spark = m
	return m


## Aplica o limite global de partículas e devolve o amount efetivo.
static func _reserve(amount: int) -> int:
	if _active_amount + amount > ACTIVE_LIMIT:
		amount = maxi(1, amount / 2)
	_active_amount += amount
	return amount


static func _release(amount: int) -> void:
	_active_amount = maxi(0, _active_amount - amount)


static func _launch(root: Node, p: CPUParticles3D, pos: Vector3, amount: int) -> void:
	p.one_shot = true
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	p.global_position = pos
	# devolve o orçamento exatamente uma vez: ao terminar ou se o nó sair da árvore antes
	var released := [false]
	var give_back := func() -> void:
		if not released[0]:
			released[0] = true
			_release(amount)
	p.finished.connect(func() -> void:
		give_back.call()
		p.queue_free())
	p.tree_exiting.connect(give_back)
	p.emitting = true


## Cor com brilho acima de 1 (HDR): o aditivo precisa disso para aparecer à luz do dia.
static func _hdr(c: Color, gain: float, a := 1.0) -> Color:
	return Color(c.r * gain, c.g * gain, c.b * gain, a)


static func _fade_ramp(c0: Color, c1: Color, c2: Color) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([c0, c1, c2])
	return g


# ---------------------------------------------------------------- API
## Cria texturas e materiais (gera os shaders) antes do primeiro efeito: tira a maior parte do
## engasgo da primeira habilidade da sessão. Chamado ao carregar o jogador local.
static func prewarm() -> void:
	if Network.is_server():
		return   # servidor dedicado: sem efeitos
	for srgb in [false, true]:
		_particle_mat(_glow_tex(), true, srgb)
		_particle_mat(_smoke_tex(), false, srgb)
	_spark_mesh()
	_scorch_tex()
	_crack_tex()
	_ring_tex()
	TrailNode.shared_mat()
	FX.prewarm()


## Cria uma vez cada tipo de efeito, longe da vista: o primeiro nó de cada malha/material ainda custava
## ~10 ms (o Godot prepara o pipeline de desenho ao criar a instância), e a primeira habilidade juntava
## vários disso num quadro só (60-90 ms). Chamado (deferred) pelo jogador local, com a cena já montada.
static func prewarm_instances(at: Node3D) -> void:
	if FX._scene() == null or at == null or not is_instance_valid(at) or not at.is_inside_tree():
		return
	var p := at.global_position + Vector3(0, -200, 0)   # bem abaixo do mapa
	glow_burst(p, Color.WHITE, 1, 0.1, 0.05, 0.1, 0.0)
	nova(p, Color.WHITE, 1, 0.1, 0.05, 0.1)
	sparks(p, Vector3.UP, Color.WHITE, 1, 0.1, 0.1)
	smoke(p, Color(1, 1, 1, 0.01), 1, 0.1, 0.1)
	FX.ring(p, Color(1, 1, 1, 0.0), 0.1, 0.1)
	FX.burst(p, Color.WHITE, 1, 0.1, 0.05, 0.1)
	for kind in ["crack", "scorch", "ring"]:
		ground_mark(p, Color(1, 1, 1, 0.0), 0.1, 0.1, kind)
	var holder := Node3D.new()
	FX._scene().add_child(holder)
	holder.global_position = p
	for kind in ["glow", "smoke"]:
		stream(holder, kind, Color.WHITE, 1, 0.1)
	trail(holder, Color.WHITE, 0.1, 0.05, 0.05)
	holder.get_tree().create_timer(0.3).timeout.connect(holder.queue_free)


## Explosão de brilho: bolas de luz aditivas que desbotam e encolhem.
static func glow_burst(pos: Vector3, color: Color, amount := 40, speed := 6.0, size := 0.18, lifetime := 0.7, gravity := -4.0) -> void:
	var root := FX._scene()
	if root == null:
		return
	amount = _reserve(amount)
	var p := CPUParticles3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * size * 2.4   # a textura suave perde borda: compensa
	mesh.material = _particle_mat(_glow_tex(), true)
	p.mesh = mesh
	p.amount = amount
	p.lifetime = lifetime
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, gravity, 0)
	p.damping_min = speed * 0.5
	p.damping_max = speed * 0.9
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.6
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1.0))
	sc.add_point(Vector2(1, 0.1))
	p.scale_amount_curve = sc
	var hot := color.lerp(Color.WHITE, 0.25)
	p.color_ramp = _fade_ramp(_hdr(hot, 1.5), _hdr(color, 1.25), _hdr(color, 1.0, 0.0))
	_launch(root, p, pos, amount)


## Onda de chamas: bolas de luz aditivas saindo na horizontal em todas as direções, freando até
## ~speed²/20 m (anel de fogo que se expande rente ao chão).
static func nova(pos: Vector3, color: Color, amount := 60, speed := 9.0, size := 0.2, lifetime := 0.6) -> void:
	var root := FX._scene()
	if root == null:
		return
	amount = _reserve(amount)
	var p := CPUParticles3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * size * 2.4
	mesh.material = _particle_mat(_glow_tex(), true)
	p.mesh = mesh
	p.amount = amount
	p.lifetime = lifetime
	p.explosiveness = 1.0
	p.direction = Vector3.RIGHT
	p.spread = 180.0
	p.flatness = 1.0   # só no plano horizontal
	p.initial_velocity_min = speed * 0.85
	p.initial_velocity_max = speed
	p.damping_min = 10.0
	p.damping_max = 10.0
	p.gravity = Vector3(0, 1.5, 0)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.4
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.6))
	sc.add_point(Vector2(0.3, 1.0))
	sc.add_point(Vector2(1, 0.2))
	p.scale_amount_curve = sc
	p.color_ramp = _fade_ramp(_hdr(color.lerp(Color.WHITE, 0.15), 1.6), _hdr(color, 1.3), _hdr(color, 1.0, 0.0))
	_launch(root, p, pos, amount)


## Faíscas alongadas pela velocidade, num cone de 35 graus em dir.
static func sparks(pos: Vector3, dir: Vector3, color: Color, amount := 30, speed := 12.0, lifetime := 0.45) -> void:
	var root := FX._scene()
	if root == null:
		return
	amount = _reserve(amount)
	var p := CPUParticles3D.new()
	p.mesh = _spark_mesh()
	p.amount = amount
	p.lifetime = lifetime
	p.explosiveness = 0.9
	p.direction = dir.normalized() if dir.length() > 0.001 else Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = speed * 0.45
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -9.0, 0)
	p.particle_flag_align_y = true
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1.0))
	sc.add_point(Vector2(1, 0.2))
	p.scale_amount_curve = sc
	var hot := color.lerp(Color.WHITE, 0.6)
	p.color_ramp = _fade_ramp(_hdr(hot, 2.2), _hdr(color, 1.8), _hdr(color, 1.0, 0.0))
	_launch(root, p, pos, amount)


## Fumaça/poeira: nuvens alfa que crescem e somem subindo devagar.
static func smoke(pos: Vector3, color := Color(0.35, 0.32, 0.3, 0.6), amount := 16, radius := 1.0, lifetime := 1.4) -> void:
	var root := FX._scene()
	if root == null:
		return
	amount = _reserve(amount)
	var p := CPUParticles3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * 1.1
	mesh.material = _particle_mat(_smoke_tex(), false)
	p.mesh = mesh
	p.amount = amount
	p.lifetime = lifetime
	p.explosiveness = 0.8
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.6
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = radius * 0.3
	p.initial_velocity_max = radius * 1.2
	p.gravity = Vector3(0, 0.6, 0)
	p.damping_min = 0.8
	p.damping_max = 1.6
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.scale_amount_min = 0.7 * radius
	p.scale_amount_max = 1.3 * radius
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = sc
	p.color_ramp = _fade_ramp(Color(color.r, color.g, color.b, 0.0), color, Color(color.r, color.g, color.b, 0.0))
	# o início da rampa (alfa 0) cresce rápido: reposiciona o pico logo no começo
	p.color_ramp.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	_launch(root, p, pos, amount)


## Clarão: luz omni que apaga com tween e se libera.
static func flash(pos: Vector3, color: Color, energy := 4.0, range_m := 6.0, time := 0.25) -> void:
	var root := FX._scene()
	if root == null:
		return
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.shadow_enabled = false
	root.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(l.queue_free)


## Mancha no chão (Decal): "crack" rachaduras, "scorch" queimado, "ring" anel.
static func ground_mark(pos: Vector3, color: Color, radius: float, time := 2.5, kind := "crack") -> void:
	var root := FX._scene()
	if root == null:
		return
	var d := Decal.new()
	match kind:
		"scorch":
			d.texture_albedo = _scorch_tex()
		"ring":
			d.texture_albedo = _ring_tex()
		_:
			d.texture_albedo = _crack_tex()
	d.size = Vector3(radius * 2.0, 2.0, radius * 2.0)
	d.modulate = Color(color.r, color.g, color.b, 0.0)
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	d.cull_mask = 1   # só o cenário, nunca personagens
	root.add_child(d)
	d.global_position = pos + Vector3(0, 0.4, 0)
	d.rotation.y = randf() * TAU
	var tw := d.create_tween()
	tw.tween_property(d, "modulate:a", color.a, minf(0.08, time * 0.1))
	tw.tween_interval(maxf(0.0, time * 0.5))
	tw.tween_property(d, "modulate:a", 0.0, maxf(0.05, time * 0.4))
	tw.tween_callback(d.queue_free)


## Rastro de fita atrás de target durante time segundos (depois some). A fita vai de target ao
## longo do seu eixo Y por `width`. `life` = quanto cada ponto dura (comprimento do rastro);
## `end_color` (alfa > 0) = cor para onde o rastro esfria ao envelhecer (fogo: amarelo -> vermelho).
static func trail(target: Node3D, color: Color, width := 0.5, time := 1.0, life := 0.45, end_color := Color(0, 0, 0, 0)) -> void:
	var root := FX._scene()
	if root == null or target == null or not is_instance_valid(target):
		return
	var t := TrailNode.new()
	t.target = target
	t.color = color
	t.end_color = end_color if end_color.a > 0.0 else color
	t.width = width
	t.duration = time
	t.life = maxf(life, 0.05)
	root.add_child(t)


## Emissor contínuo preso a `parent`: segue o nó, mas as partículas ficam no mundo (preso a algo que
## gira, desenha espirais). kind "glow" = brasas aditivas; "smoke" = nuvens alfa. Devolve o emissor
## já emitindo, para ajustar forma e velocidade (null no servidor). Conta no ACTIVE_LIMIT enquanto
## existir. Pare com stop_stream: as partículas vivas terminam a vida antes de o nó sumir.
static func stream(parent: Node3D, kind: String, color: Color, amount: int, lifetime: float, size := 0.15) -> CPUParticles3D:
	if FX._scene() == null or parent == null or not is_instance_valid(parent):
		return null
	amount = _reserve(amount)
	var p := CPUParticles3D.new()
	var mesh := QuadMesh.new()
	var sc := Curve.new()
	var mat: StandardMaterial3D
	if kind == "smoke":
		mesh.size = Vector2.ONE * size
		mat = _particle_mat(_smoke_tex(), false, true)
		sc.add_point(Vector2(0, 0.5))
		sc.add_point(Vector2(1, 1.5))
		p.color_ramp = _fade_ramp(Color(color.r, color.g, color.b, 0.0), color, Color(color.r, color.g, color.b, 0.0))
		p.color_ramp.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
		p.angle_min = -180.0
		p.angle_max = 180.0
	else:
		mesh.size = Vector2.ONE * size * 2.4
		mat = _particle_mat(_glow_tex(), true, true)
		sc.add_point(Vector2(0, 1.0))
		sc.add_point(Vector2(1, 0.15))
		# gamas baixas: a cor é sRGB (linearizada no material), um ganho alto estoura para branco
		var hot := color.lerp(Color(1.0, 0.92, 0.6), 0.3)
		p.color_ramp = _fade_ramp(_hdr(hot, 1.15, 0.9), _hdr(color, 1.0, 0.8), _hdr(color, 0.8, 0.0))
	mesh.material = mat
	p.mesh = mesh
	p.scale_amount_curve = sc
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.tree_exiting.connect(func() -> void: _release(amount), CONNECT_ONE_SHOT)
	parent.add_child(p)
	p.emitting = true
	return p


## Para um emissor de stream(): não cria mais partículas e libera o nó quando as vivas acabarem.
static func stop_stream(p: CPUParticles3D) -> void:
	if p == null or not is_instance_valid(p) or not p.is_inside_tree():
		return
	p.emitting = false
	p.get_tree().create_timer(p.lifetime + 0.1).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())


## Congela a tela por instantes (impacto forte). Só afeta o cliente local.
static func hit_stop(duration := 0.06, scale := 0.05) -> void:
	if Network.is_server():
		return
	var tree := Engine.get_main_loop() as SceneTree
	var until := Time.get_ticks_msec() + int(duration * 1000.0)
	if _hs_active and is_instance_valid(_hs_guard) and _hs_guard.is_inside_tree():
		_hs_until_ms = maxi(_hs_until_ms, until)   # já ativo: só estende, não empilha
		return
	_hs_active = true
	_hs_until_ms = until
	Engine.time_scale = scale
	# o guarda fica na raiz (sobrevive a troca de cena) e restaura pelo relógio real
	_hs_guard = HitStopGuard.new()
	_hs_guard.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(_hs_guard)


static func _hs_restore() -> void:
	Engine.time_scale = 1.0
	_hs_active = false


class HitStopGuard extends Node:
	func _process(_delta: float) -> void:
		if Time.get_ticks_msec() >= FXEpic._hs_until_ms:
			queue_free()

	func _exit_tree() -> void:
		FXEpic._hs_restore()


# ---------------------------------------------------------------- nó auxiliar do rastro
class TrailNode extends MeshInstance3D:
	const MAX_POINTS := 64
	static var _mat: StandardMaterial3D   # compartilhado (ver FXEpic._mats)
	var target: Node3D
	var color := Color.WHITE
	var end_color := Color.WHITE
	var width := 0.5
	var duration := 1.0
	var life := 0.45
	var _im := ImmediateMesh.new()
	var _pts: Array = []   # [base, ponta, instante]
	var _age := 0.0
	var _fade := 0.0

	func _ready() -> void:
		top_level = true
		mesh = _im
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		material_override = shared_mat()
		global_transform = Transform3D.IDENTITY
		extra_cull_margin = 4096.0   # os vértices estão em coordenadas do mundo

	static func shared_mat() -> StandardMaterial3D:
		if _mat == null:
			# núcleo com mistura alfa (a cor fica saturada mesmo sobre a grama ao sol) e, por cima,
			# um passe aditivo mais fraco que dá o brilho sem lavar a cor para creme
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.vertex_color_use_as_albedo = true
			# cor de vértice em sRGB, como as cores do código: lida como linear o laranja vira creme
			m.vertex_color_is_srgb = true
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			var glow := m.duplicate() as StandardMaterial3D
			glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			glow.albedo_color = Color(1, 1, 1, 0.5)
			m.next_pass = glow
			_mat = m
		return _mat

	func _process(delta: float) -> void:
		_age += delta
		var following := _age < duration and target != null and is_instance_valid(target) and target.is_inside_tree()
		if following:
			var base := target.global_position
			var tip := base + target.global_basis.y * width
			_pts.push_back([base, tip, _age])
			if _pts.size() > MAX_POINTS:
				_pts.pop_front()
		else:
			_fade += delta
		# descarta pontos velhos (o rastro encurta sozinho ao parar)
		while _pts.size() > 0 and _age - float(_pts[0][2]) > life:
			_pts.pop_front()
		_im.clear_surfaces()
		if _pts.size() >= 2:
			_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
			var fade := clampf(1.0 - _fade / 0.25, 0.0, 1.0)
			for i in _pts.size():
				var old := clampf((_age - float(_pts[i][2])) / life, 0.0, 1.0)
				var a := pow(1.0 - old, 0.6) * fade
				var c := color.lerp(end_color, old)
				# borda de fora (ponta da fita) mais quente, sem ir ao branco
				var hot := c.lerp(Color(1.0, 0.9, 0.55), 0.35)
				_im.surface_set_color(Color(c.r, c.g, c.b, a * 0.85))
				_im.surface_add_vertex(_pts[i][0])
				_im.surface_set_color(Color(hot.r, hot.g, hot.b, a))
				_im.surface_add_vertex(_pts[i][1])
			_im.surface_end()
		if not following and (_pts.size() < 2 or _fade > 0.3):
			queue_free()
