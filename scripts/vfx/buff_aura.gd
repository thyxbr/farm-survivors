class_name BuffAura
extends Node3D
## PROTÓTIPO (spike): efeito no personagem enquanto um buff está ativo.
## Coloque como filho do modelo (origem nos pés) e chame set_buffs([...ids de comida...]).
##
## Toda aura tem a mesma base, para o conjunto parecer uma coisa só:
##   1. marca luminosa no chão (aura_ground)      -> "tem um buff aqui", legível de longe
##   2. contorno de luz no corpo (aura_rim)       -> liga o efeito ao personagem
##   3. o detalhe do buff: chamas, bolha, espiral, cruzes, estrelas (poucas partículas, pequenas)

const SH_SWIRL := preload("res://shaders/aura_swirl.gdshader")
const SH_GROUND := preload("res://shaders/aura_ground.gdshader")
const SH_SHIELD := preload("res://shaders/aura_shield.gdshader")
const SH_RIM := preload("res://shaders/aura_rim.gdshader")

## Estilo de aura de cada buff (comida). Comida fora da lista usa o primeiro bônus (ver style_for).
const FOOD_AURA := {
	"bread": "cura", "carrot_stew": "escudo", "spicy_soup": "furia", "dragon_chili": "dragao",
	"mint_tea": "vento", "garden_salad": "sorte", "pumpkin_pie": "escudo", "valdoria_feast": "heroi",
}
const STAT_AURA := {
	"damage": "furia", "crit": "furia", "defense": "escudo", "max_hp_flat": "escudo",
	"regen": "cura", "lifesteal": "cura", "speed": "vento", "cooldown": "vento",
	"xp": "sorte", "magnet": "sorte", "gold": "sorte",
}
## Cor principal de cada estilo (marca no chão e contorno do corpo).
const COLORS := {
	"cura": Color(0.35, 1.0, 0.45), "escudo": Color(0.35, 0.65, 1.0), "furia": Color(1.0, 0.22, 0.08),
	"dragao": Color(1.0, 0.5, 0.08), "vento": Color(0.6, 0.95, 1.0), "sorte": Color(1.0, 0.85, 0.3),
	"heroi": Color(1.0, 0.8, 0.3),
}
const STYLES := ["cura", "escudo", "furia", "dragao", "vento", "sorte", "heroi"]
## Marca no chão de cada estilo: traços do anel, giro (voltas/s) e brilho do miolo.
const GROUND := {
	"cura": [0.0, 0.0, 0.3], "escudo": [16.0, 0.12, 0.15], "furia": [0.0, 0.0, 0.55],
	"dragao": [10.0, 0.5, 0.6], "vento": [0.0, 0.0, 0.2], "sorte": [8.0, -0.2, 0.12],
	"heroi": [14.0, 0.3, 0.45],
}
const RING_RADIUS := 0.64      # anel da primeira aura
const RING_STEP := 0.2         # cada aura a mais ganha um anel maior, por fora
const FLOOR_MASK := 1          # camada de colisão do cenário

var _active := {}   # estilo -> Node3D
var _rim: ShaderMaterial
var _rim_style := ""
var _ground_root: Node3D       # anéis no chão: fora da hierarquia, colados no terreno
var _floor_y := 0.0
var _floor_n := Vector3.UP
var _floor_hit := false
var _n_smooth := Vector3.UP
var _y_smooth := 0.0
var _first := true


static func style_for(food_id: String) -> String:
	if FOOD_AURA.has(food_id):
		return FOOD_AURA[food_id]
	var add: Dictionary = ItemDB.get_item(food_id).get("buff", {}).get("add", {})
	for k in add:
		if STAT_AURA.has(k):
			return STAT_AURA[k]
	return "cura"


## ids: comidas com buff ativo (ex.: Game.food_buffs.keys()). Mais de uma comida = auras somadas.
func set_buffs(ids: Array) -> void:
	var want := {}
	for id in ids:
		want[style_for(id)] = true
	set_styles(want.keys())


func set_styles(styles: Array) -> void:
	for s in _active.keys():
		if not styles.has(s):
			_active[s].queue_free()
			_active.erase(s)
	for s in styles:
		if not _active.has(s):
			var n := _build(s)
			add_child(n)
			_active[s] = n
	_layout_grounds()
	_update_rim(_rim_key())


## Estilos ativos na ordem fixa de STYLES (o mesmo conjunto dá sempre o mesmo resultado).
func styles() -> Array:
	var out: Array = []
	for s in STYLES:
		if _active.has(s):
			out.append(s)
	return out


func _rim_key() -> String:
	return ",".join(styles().slice(0, 2))


# ------------------------------------------------------------------ marcas no chão
## Uma aura = um anel. Várias auras = anéis concêntricos, um de cada cor, em vez de discos
## empilhados que se misturam. Só o primeiro tem o miolo aceso.
func _layout_grounds() -> void:
	if _ground_root == null:
		_ground_root = Node3D.new()
		_ground_root.top_level = true
		add_child(_ground_root)
		_first = true
	for c in _ground_root.get_children():
		c.queue_free()
	var act := styles()
	for i in act.size():
		var g: Array = GROUND[act[i]]
		_ground_root.add_child(_ground(COLORS[act[i]], RING_RADIUS + RING_STEP * i, g[0], g[1],
			g[2] if i == 0 else 0.0))


## Acha o chão debaixo do personagem (funciona no jogador local e nas réplicas).
func _physics_process(_delta: float) -> void:
	if _active.is_empty() or not is_inside_tree():
		return
	var from := global_position + Vector3.UP * 1.0
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 6.0, FLOOR_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	_floor_hit = not hit.is_empty()
	if _floor_hit:
		_floor_y = hit.position.y
		_floor_n = hit.normal


## Cola os anéis no terreno: acompanham a inclinação e ficam no chão quando o personagem pula.
func _process(delta: float) -> void:
	if _ground_root == null or _active.is_empty():
		return
	var o := get_global_transform_interpolated().origin
	var ty := _floor_y if _floor_hit else o.y
	var tn := _floor_n if _floor_hit else Vector3.UP
	var k := 1.0 if _first else 1.0 - exp(-14.0 * delta)
	_first = false
	_y_smooth = lerpf(_y_smooth, ty, k)
	_n_smooth = _n_smooth.lerp(tn, k).normalized()
	var x := (Vector3.RIGHT - _n_smooth * _n_smooth.dot(Vector3.RIGHT)).normalized()
	_ground_root.global_transform = Transform3D(Basis(x, _n_smooth, x.cross(_n_smooth)),
		Vector3(o.x, _y_smooth, o.z) + _n_smooth * 0.03)


## O modelo trocou de peças (equipamento novo): recoloca o contorno de luz nelas.
func refresh() -> void:
	var st := _rim_style
	_rim_style = ""
	_update_rim(st)


func _exit_tree() -> void:
	_update_rim("")
	if _ground_root:
		_ground_root.queue_free()
		_ground_root = null


# ------------------------------------------------------------------ contorno no corpo
## Põe (ou tira) o contorno de luz nas peças do personagem. A arma fica de fora: ela tem o
## brilho do encantamento. Com várias auras, o contorno alterna entre as cores das duas primeiras.
## `key` = estilos separados por vírgula ("" = sem contorno).
func _update_rim(key: String) -> void:
	if key == _rim_style:
		return
	var had := _rim != null
	_rim_style = key
	var model := get_parent()
	if model == null:
		return
	_rim = null
	if key == "" and not had:
		return
	if key != "":
		var st := key.split(",")
		var strong := false
		var fire := false
		for s in st:
			strong = strong or s in ["furia", "dragao", "heroi"]
			fire = fire or s in ["furia", "dragao"]
		_rim = ShaderMaterial.new()
		_rim.shader = SH_RIM
		_rim.set_shader_parameter("color", COLORS[st[0]])
		_rim.set_shader_parameter("color2", COLORS[st[st.size() - 1]])
		_rim.set_shader_parameter("strength", 1.5 if strong else 1.1)
		_rim.set_shader_parameter("rise", 1.0 if fire else 0.0)
	_set_overlay(model, _rim)


func _set_overlay(n: Node, mat: Material) -> void:
	for c in n.get_children():
		if c == self or c.name == "WeaponHolder":
			continue
		if c is MeshInstance3D:
			c.material_overlay = mat
		_set_overlay(c, mat)


# ------------------------------------------------------------------ estilos
func _build(style: String) -> Node3D:
	var root := Node3D.new()
	root.name = style
	var c: Color = COLORS[style]
	match style:
		"cura":     # verde calmo: fios de luz subindo devagar + poucas cruzinhas
			root.add_child(_swirl(c, {"radius": 0.45, "height": 1.7, "streaks": 4.0, "twist": 1.0,
				"spin": 0.14, "rise": 0.6, "thin": 0.93, "strength": 0.6}))
			root.add_child(_emitter({"tex": "cross", "color": Color(0.75, 1.0, 0.7), "amount": 6, "life": 2.0,
				"radius": 0.42, "y": 0.5, "vel": Vector2(0.25, 0.4), "size": 0.09}))
			root.add_child(_emitter({"color": Color(0.5, 1.0, 0.55), "amount": 10, "life": 1.8,
				"radius": 0.4, "y": 0.1, "vel": Vector2(0.35, 0.6), "size": 0.03}))
		"escudo":   # azul: bolha de proteção com favos + anel no chão
			root.add_child(_shield(c))
		"furia":    # vermelho: línguas de fogo subindo dos pés + brasas
			root.add_child(_flames(Color(1.0, 0.75, 0.25), Color(1.0, 0.2, 0.05), 28, 0.33, 0.26))
			root.add_child(_emitter({"color": Color(1.0, 0.55, 0.2), "amount": 8, "life": 1.3,
				"radius": 0.35, "y": 0.3, "vel": Vector2(0.7, 1.3), "size": 0.025, "spread": 25.0}))
		"dragao":   # laranja: fogo mais alto e claro, anel de brasa girando, mais fagulhas
			root.add_child(_flames(Color(1.0, 0.95, 0.55), Color(1.0, 0.4, 0.05), 34, 0.36, 0.28))
			root.add_child(_swirl(Color(1.0, 0.6, 0.15), {"radius": 0.5, "height": 1.2, "y": 0.6, "streaks": 3.0,
				"twist": 1.2, "spin": 0.9, "rise": 1.2, "thin": 0.86, "strength": 0.7}))
			root.add_child(_emitter({"color": Color(1.0, 0.7, 0.25), "amount": 16, "life": 1.4,
				"radius": 0.4, "y": 0.3, "vel": Vector2(0.9, 1.7), "size": 0.03, "spread": 30.0}))
		"vento":    # ciano: riscos de ar girando rápido em volta do corpo
			root.add_child(_swirl(c, {"radius": 0.5, "height": 1.7, "streaks": 3.0, "twist": 1.6,
				"spin": 1.3, "rise": 0.8, "thin": 0.88, "strength": 0.8}))
			root.add_child(_swirl(Color(1, 1, 1), {"radius": 0.62, "height": 1.3, "y": 0.75, "streaks": 2.0,
				"twist": -1.0, "spin": 0.9, "rise": 0.6, "thin": 0.93, "strength": 0.5}))
		"sorte":    # dourado: poucas estrelas piscando em volta
			root.add_child(_emitter({"tex": "star", "color": Color(1.0, 0.93, 0.6), "amount": 12, "life": 1.2,
				"shape": "sphere", "radius": 0.62, "y": 1.0, "vel": Vector2(0.0, 0.08), "size": 0.2,
				"twinkle": true}))
		"heroi":    # banquete: selo dourado no chão + coluna de luz subindo + estrelas
			root.add_child(_swirl(c, {"radius": 0.48, "height": 2.1, "y": 1.0, "streaks": 4.0, "twist": 0.5,
				"spin": 0.25, "rise": 1.4, "thin": 0.9, "strength": 0.75}))
			root.add_child(_emitter({"tex": "star", "color": Color(1.0, 0.97, 0.75), "amount": 8, "life": 1.1,
				"shape": "sphere", "radius": 0.6, "y": 1.1, "vel": Vector2(0.0, 0.1), "size": 0.18,
				"twinkle": true}))
			root.add_child(_emitter({"color": Color(1.0, 0.9, 0.5), "amount": 12, "life": 1.6,
				"radius": 0.45, "y": 0.1, "vel": Vector2(0.5, 0.9), "size": 0.03}))
	return root


# ------------------------------------------------------------------ peças
## Marca no chão: raio `r`, `ticks` traços girando a `spin` voltas/s, `glow` = brilho do miolo.
func _ground(c: Color, r: float, ticks: float, spin: float, glow: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE * r * 2.0
	var m := ShaderMaterial.new()
	m.shader = SH_GROUND
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("ticks", ticks)
	m.set_shader_parameter("spin", spin)
	m.set_shader_parameter("glow", glow)
	pm.material = m
	mi.mesh = pm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Tubo de riscos de luz em espiral (ver aura_swirl.gdshader).
func _swirl(c: Color, o: Dictionary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	var h: float = o.get("height", 1.8)
	cm.top_radius = float(o.radius) * 0.85
	cm.bottom_radius = float(o.radius)
	cm.height = h
	cm.radial_segments = 32
	cm.rings = 6
	cm.cap_top = false
	cm.cap_bottom = false
	var m := ShaderMaterial.new()
	m.shader = SH_SWIRL
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("height", h)
	for k in ["streaks", "twist", "spin", "rise", "thin", "strength"]:
		if o.has(k):
			m.set_shader_parameter(k, o[k])
	cm.material = m
	mi.mesh = cm
	mi.position.y = float(o.get("y", h * 0.5))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _shield(c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.72
	sm.height = 1.44
	sm.radial_segments = 40
	sm.rings = 20
	var m := ShaderMaterial.new()
	m.shader = SH_SHIELD
	m.set_shader_parameter("color", c)
	sm.material = m
	mi.mesh = sm
	mi.scale = Vector3(1.0, 1.45, 1.0)
	mi.position.y = 0.98
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Línguas de fogo: quadrados com textura de chama, nascem num anel junto aos pés, crescem,
## sobem e afinam. `hot` = cor ao nascer, `cool` = cor ao morrer.
func _flames(hot: Color, cool: Color, amount: int, radius: float, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size * 0.6, size)
	quad.center_offset = Vector3(0, size * 0.35, 0)
	var m := _particle_mat("flame")
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX   # soma estoura em branco sob o sol
	quad.material = m
	p.mesh = quad
	p.amount = amount
	p.lifetime = 0.75
	p.preprocess = 1.0
	p.local_coords = true    # as chamas acompanham o corpo; quem deixa rastro são as fagulhas
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = radius
	p.emission_ring_inner_radius = radius * 0.55
	p.emission_ring_height = 0.02
	p.position.y = 0.03
	p.direction = Vector3.UP
	p.spread = 6.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.1
	p.gravity = Vector3(0, 0.6, 0)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.5
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.35))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1, 0.15))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(hot.r, hot.g, hot.b, 0.0))
	grad.add_point(0.12, hot)
	grad.add_point(0.55, cool)
	grad.set_color(grad.get_point_count() - 1, Color(cool.r * 0.6, cool.g * 0.3, cool.b * 0.3, 0.0))
	p.color_ramp = grad
	p.emitting = true
	return p


## Partículas pequenas (pontos, cruzes, estrelas) subindo de um anel ou flutuando numa esfera.
func _emitter(o: Dictionary) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * float(o.get("size", 0.05))
	quad.material = _particle_mat(o.get("tex", "dot"))
	p.mesh = quad
	p.amount = int(o.get("amount", 10))
	p.lifetime = float(o.get("life", 1.2))
	p.preprocess = p.lifetime
	p.randomness = 1.0
	p.local_coords = false
	if o.get("shape", "ring") == "sphere":
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = float(o.radius)
	else:
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		p.emission_ring_axis = Vector3.UP
		p.emission_ring_radius = float(o.radius)
		p.emission_ring_inner_radius = float(o.radius) * 0.7
		p.emission_ring_height = 0.3
	p.position.y = float(o.get("y", 0.0))
	p.direction = Vector3.UP
	p.spread = float(o.get("spread", 8.0))
	var vel: Vector2 = o.get("vel", Vector2(0.3, 0.6))
	p.initial_velocity_min = vel.x
	p.initial_velocity_max = vel.y
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var curve := Curve.new()
	if o.get("twinkle", false):   # estrela: abre e fecha rápido
		curve.add_point(Vector2(0, 0))
		curve.add_point(Vector2(0.35, 1))
		curve.add_point(Vector2(0.5, 0.45))
		curve.add_point(Vector2(0.65, 0.9))
		curve.add_point(Vector2(1, 0))
	else:
		curve.add_point(Vector2(0, 0))
		curve.add_point(Vector2(0.2, 1))
		curve.add_point(Vector2(1, 0.2))
	p.scale_amount_curve = curve
	var c: Color = o.color
	var grad := Gradient.new()
	grad.set_color(0, Color(c.r, c.g, c.b, 0.0))
	grad.add_point(0.15, c)
	grad.add_point(0.7, c)
	grad.set_color(grad.get_point_count() - 1, Color(c.r, c.g, c.b, 0.0))
	p.color_ramp = grad
	p.emitting = true
	return p


func _particle_mat(tex: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.albedo_texture = _tex(tex)
	return m


static var _texs := {}
## Texturas de partícula desenhadas por código:
## "dot" (bolinha macia), "cross" (cruz de cura), "star" (brilho de 4 pontas), "flame" (gota de fogo).
static func _tex(kind: String) -> Texture2D:
	if _texs.has(kind):
		return _texs[kind]
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var u := (x + 0.5) / s * 2.0 - 1.0
			var v := (y + 0.5) / s * 2.0 - 1.0     # -1 em cima, +1 embaixo
			var a := 0.0
			match kind:
				"cross":
					var d := minf(maxf(absf(u) - 0.16, absf(v) - 0.7), maxf(absf(v) - 0.16, absf(u) - 0.7))
					a = clampf(-d / 0.1, 0.0, 1.0)
				"star":
					var d := sqrt(u * u + v * v)
					a = pow(clampf(1.0 - d * 2.5, 0.0, 1.0), 2.0)
					a = maxf(a, pow(clampf(1.0 - absf(u) * 9.0, 0.0, 1.0), 1.5) * pow(clampf(1.0 - absf(v), 0.0, 1.0), 1.5))
					a = maxf(a, pow(clampf(1.0 - absf(v) * 9.0, 0.0, 1.0), 1.5) * pow(clampf(1.0 - absf(u), 0.0, 1.0), 1.5))
				"flame":
					# gota: ponta fina em cima, barriga embaixo, base arredondada
					var t := (v + 1.0) * 0.5
					var w := 0.62 * sin(pow(t, 1.7) * PI)
					if w > 0.001:
						a = pow(clampf(1.0 - absf(u) / w, 0.0, 1.0), 1.3)
						a *= smoothstep(0.0, 0.25, t)
				_:
					a = clampf(1.0 - sqrt(u * u + v * v), 0.0, 1.0)
					a *= a
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var tx := ImageTexture.create_from_image(img)
	_texs[kind] = tx
	return tx
