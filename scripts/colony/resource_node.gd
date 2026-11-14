class_name ColonyResourceNode
extends Node3D
## Nó de recurso da Defesa da Cidade (árvore, pedra, veio de ferro ou de ouro, cristal, arbusto de frutas).
## O ataque normal do jogador acerta os nós do grupo `harvest` (nunca `enemies`: torres e soldados não miram).
## Esgotado, some, perde a colisão e sai de `colony.obstacles`; ao voltar, retoma o mesmo lugar.
## Quem decide golpes, esgotamento e volta é a ColonyNature (no servidor ou no solo).

const MODELS := {
	"tree_pine": preload("res://assets/models/tree_pine.glb"),
	"tree_oak": preload("res://assets/models/tree_oak.glb"),
	"tree_fir": preload("res://assets/models/tree_fir.glb"),
	"tree_birch": preload("res://assets/models/tree_birch.glb"),
	"tree_maple": preload("res://assets/models/tree_maple.glb"),
	"rock": preload("res://assets/models/rock.glb"),
	"bush_berry": preload("res://assets/models/bush_berry.glb"),
}

var id := 0
var kind := "tree"
var model := "tree_pine"
var yaw := 0.0
var size := 1.0
## Raio da colisão (já com a escala); o golpe do jogador usa o mesmo raio.
var radius := 0.4
## Total de recurso que o nó entrega até esgotar (nós ricos têm mais).
var total := 0
var hits_left := 0
var alive := true
var nature: Node   # ColonyNature
## Obstáculo deste nó em colony.obstacles ([centro XZ, raio]); guardado para voltar ao reaparecer.
var obstacle: Array = []

var _shape: CollisionShape3D
var _visual: Node3D
var _tween: Tween


func data() -> Dictionary:
	return ColonyData.NODES[kind]


func _ready() -> void:
	add_to_group("harvest")
	if total <= 0:
		total = int(data().total)
	hits_left = int(data().hits)
	var body := StaticBody3D.new()
	body.collision_mask = 0
	_shape = CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = radius
	c.height = 3.0
	_shape.shape = c
	_shape.position.y = 1.5
	body.add_child(_shape)
	add_child(body)
	obstacle = [Vector2(global_position.x, global_position.z), radius + 0.3]
	if DisplayServer.get_name() != "headless":
		_build_visual()


## Golpe do jogador: no solo vira coleta direta; no cliente, pedido ao servidor.
func hit(from: Vector3) -> void:
	if not alive or nature == null or not nature.take_hit(id):
		return
	_shake(from)
	var c: Colony = nature.colony
	if c.role == "client":
		Lobby.city_hit_node(id)
	else:
		c.harvest(id, from)


## Liga ou desliga o nó (esgotado/restaurado). fx = animação de queda ou de volta.
func set_alive(on: bool, fx := true) -> void:
	if on == alive:
		return
	alive = on
	if _shape:
		_shape.set_deferred("disabled", not on)
	var obs: Array = nature.colony.obstacles if nature and nature.colony else []
	if on:
		hits_left = int(data().hits)
		if not obstacle.is_empty() and not obs.has(obstacle):
			obs.append(obstacle)
	else:
		obs.erase(obstacle)
	if _visual == null:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_visual.rotation = Vector3(0, yaw, 0)
	_visual.scale = Vector3.ONE * size
	if on:
		_visual.visible = true
		if fx:
			_visual.scale = Vector3.ONE * size * 0.05
			_tween = create_tween()
			_tween.tween_property(_visual, "scale", Vector3.ONE * size, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		return
	if not fx:
		_visual.visible = false
		return
	FX.burst(global_position + Vector3.UP * 0.8, _burst_color(), 22, 4.0, 0.14, 0.7)
	_tween = create_tween()
	if kind == "tree":
		# a árvore tomba para um lado e some
		_tween.tween_property(_visual, "rotation:x", PI / 2.1, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_tween.tween_property(_visual, "scale", Vector3.ONE * size * 0.05, 0.35)
	else:
		_tween.tween_property(_visual, "scale", Vector3.ONE * size * 0.05, 0.3)
	_tween.tween_callback(func() -> void: _visual.visible = false)


func _shake(from: Vector3) -> void:
	if _visual == null:
		return
	Sfx.play_at("harvest" if kind == "berry" else "hit", global_position, 0.2, -4.0)
	FX.burst(global_position + Vector3.UP * 1.0, _burst_color(), 8, 3.0, 0.08, 0.4)
	if _tween and _tween.is_valid():
		return
	var away := global_position - from
	away.y = 0
	var lean := away.normalized() * 0.08 if away.length() > 0.01 else Vector3.ZERO
	_tween = create_tween()
	_tween.tween_property(_visual, "rotation", Vector3(lean.z, yaw, -lean.x), 0.06)
	_tween.tween_property(_visual, "rotation", Vector3(0, yaw, 0), 0.18)


func _burst_color() -> Color:
	match kind:
		"tree":
			return Color(0.45, 0.33, 0.2)
		"iron":
			return Color(0.55, 0.3, 0.2)
		"gold":
			return Color(1.0, 0.85, 0.3)
		"crystal":
			return Color(0.55, 0.45, 1.0)
		"berry":
			return Color(0.7, 0.15, 0.3)
	return Color(0.6, 0.6, 0.6)


# ================================================================ visual (fora do headless)
func _build_visual() -> void:
	if kind == "crystal":
		_visual = Node3D.new()
	else:
		_visual = MODELS[model].instantiate()
	_visual.rotation.y = yaw
	_visual.scale = Vector3.ONE * size
	add_child(_visual)
	var r := RandomNumberGenerator.new()
	r.seed = id * 7919 + 13   # detalhes só visuais: não mexem no rng do mapa
	match kind:
		"iron":
			_tint(_visual, Color(0.55, 0.3, 0.2))
			for i in 6:
				_bit(r, SphereMesh.new(), Color(0.12, 0.1, 0.1), 0.0, 0.12)
		"gold":
			for i in 7:
				var m := CylinderMesh.new()
				m.radial_segments = 6
				m.top_radius = 0.0
				_bit(r, m, Color(1.0, 0.82, 0.25), 1.6, 0.14)
		"crystal":
			_build_crystal(r)


func _bit(r: RandomNumberGenerator, mesh: PrimitiveMesh, color: Color, glow: float, s: float) -> void:
	var a := r.randf() * TAU
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color, glow)
	mi.position = Vector3(cos(a) * 0.45, r.randf_range(0.25, 0.65), sin(a) * 0.45)
	mi.rotation = Vector3(r.randf_range(-0.6, 0.6), r.randf() * TAU, r.randf_range(-0.6, 0.6))
	mi.scale = Vector3.ONE * s * r.randf_range(0.8, 1.3)
	_visual.add_child(mi)


func _build_crystal(r: RandomNumberGenerator) -> void:
	var color := Color(0.5, 0.42, 1.0)
	for i in r.randi_range(3, 5):
		var m := CylinderMesh.new()
		m.radial_segments = 6
		m.rings = 1
		m.top_radius = 0.04
		m.bottom_radius = r.randf_range(0.16, 0.26)
		m.height = r.randf_range(0.9, 1.8)
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = _mat(color.lerp(Color(0.35, 0.6, 1.0), r.randf()), 2.2)
		var a := r.randf() * TAU
		var d := 0.0 if i == 0 else r.randf_range(0.2, 0.45)
		mi.position = Vector3(cos(a) * d, m.height * 0.42, sin(a) * d)
		mi.rotation = Vector3(r.randf_range(-0.35, 0.35), 0, r.randf_range(-0.35, 0.35))
		_visual.add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.6
	light.omni_range = 4.5
	light.position.y = 1.0
	_visual.add_child(light)


func _mat(color: Color, glow: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.4 if glow > 0.0 else 0.9
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


func _tint(n: Node, color: Color) -> void:
	if n is MeshInstance3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.95
		n.material_override = m
	for c in n.get_children():
		_tint(c, color)
