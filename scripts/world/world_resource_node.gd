class_name WorldResourceNode
extends Node3D
## Veio de ferro ou cristal arcano de Valdoria (materiais do encantamento). Cada jogador tem os seus veios,
## como o saque pessoal. O ataque normal do jogador acerta os nós do grupo `harvest` (nunca `enemies`).
## Os golpes são contados aqui; no último o nó some e pede a coleta ao Econ (solo: concede na hora;
## online: o servidor confere distância e tempo de volta, ver WorldHarvest).

const ROCK := preload("res://assets/models/rock.glb")

## Id do nó (node_id fixo da MapEntity "resource_node" na cena do mapa; ver WorldHarvest).
var node_id := 0
## Visual: "iron" (rocha com veios), "ore" (rocha na cor `tint`), "crystal" ou um modelo de árvore ("tree_pine"...).
var kind := "iron"
var tint := Color(0.55, 0.3, 0.2)
## Profissão de coleta e o nível dela que o nó pede (sem nível, os golpes não contam e avisa).
var prof := ""
var level := 1
var yaw := 0.0
var size := 1.1
## Raio da colisão (já com a escala); o golpe do jogador usa o mesmo raio.
var radius := 0.75
## Golpes para quebrar e segundos para voltar (da tabela).
var hits := 5
var respawn := 180.0
var hits_left := 0
var alive := true

var _shape: CollisionShape3D
var _visual: Node3D
var _tween: Tween


## Monta o nó a partir de WorldHarvest.node_def().
static func from_def(def: Dictionary) -> WorldResourceNode:
	var n := WorldResourceNode.new()
	n.node_id = int(def.id)
	n.kind = str(def.model)
	n.tint = def.get("tint", n.tint)
	n.prof = str(def.get("prof", ""))
	n.level = int(def.get("level", 1))
	n.yaw = float(def.id) * 1.7
	n.hits = int(def.hits)
	n.respawn = float(def.respawn)
	n.position = def.pos
	return n


func _ready() -> void:
	add_to_group("harvest")
	hits_left = hits
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
	if DisplayServer.get_name() != "headless":
		_build_visual()


func hit(from: Vector3) -> void:
	if not alive:
		return
	if prof != "" and Game.prof_level(prof) < level:
		_shake(from)
		Game.notify.emit("Precisa de %s nível %d." % [Game.prof_name(prof), level], CharRules.C_BAD)
		return
	hits_left -= 1
	_shake(from)
	if hits_left > 0:
		return
	set_alive(false)
	Econ.gather_node(node_id, from)
	get_tree().create_timer(respawn).timeout.connect(_restore)


func _restore() -> void:
	if is_inside_tree():
		set_alive(true)


## Liga ou desliga o nó (esgotado/restaurado), com a animação de queda ou de volta.
func set_alive(on: bool) -> void:
	if on == alive:
		return
	alive = on
	if _shape:
		_shape.set_deferred("disabled", not on)
	if on:
		hits_left = hits
	if _visual == null:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_visual.rotation = Vector3(0, yaw, 0)
	_visual.scale = Vector3.ONE * size
	if on:
		_visual.visible = true
		_visual.scale = Vector3.ONE * size * 0.05
		_tween = create_tween()
		_tween.tween_property(_visual, "scale", Vector3.ONE * size, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		return
	FX.burst(global_position + Vector3.UP * 0.8, _burst_color(), 22, 4.0, 0.14, 0.7)
	_tween = create_tween()
	_tween.tween_property(_visual, "scale", Vector3.ONE * size * 0.05, 0.3)
	_tween.tween_callback(func() -> void: _visual.visible = false)


func _shake(from: Vector3) -> void:
	if _visual == null:
		return
	Sfx.play_at("chop_wood" if kind.begins_with("tree_") else "chop_stone", global_position, 0.15, -4.0)
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
	if kind == "crystal":
		return Color(0.55, 0.45, 1.0)
	if kind.begins_with("tree_"):
		return Color(0.45, 0.3, 0.15)
	return tint


# ================================================================ visual (fora do headless)
func _build_visual() -> void:
	if kind.begins_with("tree_"):
		_visual = (load(MapProp.model_path(kind)) as PackedScene).instantiate()
		_visual.rotation.y = yaw
		_visual.scale = Vector3.ONE * size
		add_child(_visual)
		if tint != Color(0.55, 0.3, 0.2):
			_tint(_visual, tint)
		# fita amarela no tronco: árvore que dá para cortar (as de enfeite não têm)
		var band := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.3
		cyl.bottom_radius = 0.3
		cyl.height = 0.18
		band.mesh = cyl
		band.position.y = 1.1
		band.material_override = _mat(Color(1.0, 0.8, 0.2), 0.3)
		_visual.add_child(band)
		return
	_visual = Node3D.new() if kind == "crystal" else ROCK.instantiate()
	_visual.rotation.y = yaw
	_visual.scale = Vector3.ONE * size
	add_child(_visual)
	var r := RandomNumberGenerator.new()
	r.seed = node_id * 7919 + 13   # detalhes só visuais: não mexem no rng do mapa
	if kind == "crystal":
		_build_crystal(r)
		return
	_tint(_visual, Color(0.55, 0.3, 0.2) if kind == "iron" else Color(0.42, 0.4, 0.38))
	for i in 6:
		var a := r.randf() * TAU
		var mi := MeshInstance3D.new()
		mi.mesh = SphereMesh.new()
		mi.material_override = _mat(Color(0.12, 0.1, 0.1), 0.0) if kind == "iron" else _mat(tint, 0.4)
		mi.position = Vector3(cos(a) * 0.45, r.randf_range(0.25, 0.65), sin(a) * 0.45)
		mi.rotation = Vector3(r.randf_range(-0.6, 0.6), r.randf() * TAU, r.randf_range(-0.6, 0.6))
		mi.scale = Vector3.ONE * 0.12 * r.randf_range(0.8, 1.3)
		_visual.add_child(mi)


func _build_crystal(r: RandomNumberGenerator) -> void:
	var color := Color(0.55, 0.3, 0.95)
	for i in r.randi_range(3, 5):
		var m := CylinderMesh.new()
		m.radial_segments = 6
		m.rings = 1
		m.top_radius = 0.04
		m.bottom_radius = r.randf_range(0.16, 0.26)
		m.height = r.randf_range(0.9, 1.8)
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = _mat(color.lerp(Color(0.4, 0.35, 1.0), r.randf()), 1.0)
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
