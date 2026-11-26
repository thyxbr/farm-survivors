extends StaticBody3D
## Barreira de passagem (reaproveitável): fecha a boca de um corredor ou um vão entre salas enquanto uma luta
## está em andamento. Fechada, é uma cerca de raízes cruzadas com espinhos, que brota do chão, com um brilho
## verde fraco de seiva entre elas; bloqueia quem anda (jogador e monstros) e a câmera (camada 1: a câmera não
## atravessa para o lado de fora e a vista do jogador não fica atrás da cerca). Aberta, afunda no chão.
##
## Quem decide quando abre e fecha é o dono (expedition_mode.gd: tranca ao começar o encontro da sala e solta
## quando a última onda cai). Fica de pé no lugar dela; `inward` aponta para dentro da sala que ela protege.

const RISE := 0.55
const SINK := 0.7
const COLOR_GLOW := Color(0.45, 1.0, 0.5)
const COLOR_ROOT := Color(0.24, 0.17, 0.1)
const COLOR_THORN := Color(0.36, 0.3, 0.16)
const COLOR_DUST := Color(0.45, 0.36, 0.22)

## Largura do vão fechado (m), altura e espessura da parede.
var width := 6.0
var height := 4.0
var thickness := 0.8
## Para dentro da sala protegida (x, z do mundo; normalizado).
var inward := Vector3.FORWARD
## Sala que esta barreira fecha (nome do ExpeditionDefs).
var room := ""

var locked := false
var _shape: CollisionShape3D
var _visual: Node3D
var _veil: MeshInstance3D
var _light: OmniLight3D
var _tw: Tween
var _t := 0.0


func _ready() -> void:
	collision_layer = 1 | MapRiver.WALL_LAYER
	collision_mask = 0
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, height, thickness)
	_shape.shape = box
	_shape.position.y = height / 2.0
	_shape.disabled = true
	add_child(_shape)
	# vira para o corredor: o eixo z local cruza a passagem
	look_at(global_position + inward, Vector3.UP)
	if DisplayServer.get_name() == "headless":
		return
	_visual = Node3D.new()
	_visual.visible = false
	add_child(_visual)
	_build_visual()
	_visual.position.y = -height - 0.3


func _build_visual() -> void:
	var root_mat := StandardMaterial3D.new()
	root_mat.albedo_color = COLOR_ROOT
	root_mat.roughness = 0.95
	var thorn_mat := StandardMaterial3D.new()
	thorn_mat.albedo_color = COLOR_THORN
	thorn_mat.roughness = 0.8
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(room + str(global_position.snapped(Vector3.ONE)))
	# duas fileiras de raízes inclinadas para lados opostos: de frente formam uma treliça em X
	var n := maxi(4, int(width / 0.9))
	for row in 2:
		var z := -0.2 if row == 0 else 0.2
		for i in n:
			var x := -width / 2.0 + (i + 0.5 + (0.5 if row == 1 else 0.0)) * width / n
			if x > width / 2.0:
				continue
			var h := height * rng.randf_range(0.85, 1.1)
			var lean := (0.32 if (i + row) % 2 == 0 else -0.32) + rng.randf_range(-0.08, 0.08)
			var stake := Node3D.new()
			stake.position = Vector3(x, 0.0, z + rng.randf_range(-0.06, 0.06))
			stake.rotation = Vector3(rng.randf_range(-0.1, 0.1), 0.0, lean)
			_visual.add_child(stake)
			var m := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.025
			cyl.bottom_radius = rng.randf_range(0.13, 0.2)
			cyl.height = h
			cyl.radial_segments = 5
			cyl.rings = 2
			m.mesh = cyl
			m.material_override = root_mat
			m.position.y = h / 2.0
			stake.add_child(m)
			# espinhos para fora (dos dois lados da cerca)
			for k in 2:
				var t := MeshInstance3D.new()
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = 0.05
				cone.height = 0.32
				cone.radial_segments = 4
				cone.rings = 1
				t.mesh = cone
				t.material_override = thorn_mat
				var y := h * rng.randf_range(0.25, 0.8)
				t.position = Vector3(0.0, y, 0.0)
				t.rotation = Vector3(PI / 2.0 * (1.0 if k == 0 else -1.0), 0.0, rng.randf_range(-0.5, 0.5))
				t.translate_object_local(Vector3(0, 0.14, 0))
				stake.add_child(t)
	# brilho de seiva entre as raízes: forte embaixo, some antes do topo (diz "fechado" sem virar parede)
	_veil = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(width * 0.96, height)
	_veil.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(0.55, Color(1, 1, 1, 0.35))
	g.add_point(0.9, Color(1, 1, 1, 1.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	var vm := StandardMaterial3D.new()
	vm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	vm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	vm.cull_mode = BaseMaterial3D.CULL_DISABLED
	vm.albedo_texture = gt
	vm.albedo_color = Color(COLOR_GLOW, 0.12)
	_veil.material_override = vm
	_veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_veil.position.y = height / 2.0
	_visual.add_child(_veil)
	_light = OmniLight3D.new()
	_light.light_color = COLOR_GLOW
	_light.light_energy = 0.45
	_light.omni_range = minf(width * 0.6, 4.0)
	_light.position = Vector3(0, 0.8, 0)
	_visual.add_child(_light)


func _process(delta: float) -> void:
	if _veil == null or not locked:
		return
	_t += delta
	var m := _veil.material_override as StandardMaterial3D
	m.albedo_color.a = 0.1 + 0.05 * sin(_t * 2.4)


## Fecha (true) ou abre (false). `instant` pula a animação.
func set_locked(on: bool, instant := false) -> void:
	if on == locked:
		return
	locked = on
	if _shape != null:
		_shape.set_deferred("disabled", not on)
	if _visual == null:
		return
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_visual.visible = true
	var to := 0.0 if on else -height - 0.3
	if instant:
		_visual.position.y = to
		_visual.visible = on
		return
	_tw = create_tween()
	if on:
		_tw.tween_property(_visual, "position:y", to, RISE).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_tw.tween_property(_visual, "position:y", to, SINK).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_tw.tween_callback(func() -> void: _visual.visible = false)
	# terra levantada ao longo da cerca (brotando ou afundando)
	var side := global_basis.x
	for i in 3:
		var p := global_position + side * (width * (i - 1) / 3.0) + Vector3.UP * 0.3
		FX.burst(p, COLOR_DUST if on else COLOR_GLOW, 10, 3.0, 0.11, 0.55)


## Distância (m) de `p` até a parede, medida para dentro da sala (negativa = do lado de fora), e se `p` está
## na frente do vão (dentro da largura).
func depth_of(p: Vector3) -> float:
	var d := p - global_position
	return Vector2(d.x, d.z).dot(Vector2(inward.x, inward.z))


func spans(p: Vector3) -> bool:
	var d := p - global_position
	var side := Vector2(-inward.z, inward.x)
	return absf(Vector2(d.x, d.z).dot(side)) <= width / 2.0 + 0.6
