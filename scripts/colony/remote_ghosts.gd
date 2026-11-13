extends Node3D
## Cidade em grupo: mostra o que os outros jogadores estão posicionando no modo construção, antes de
## confirmarem — um fantasma translúcido na cor do jogador (vermelho quando não cabe) com o nome em cima.
## No modo demolir, a construção mirada fica marcada. Quem para de mandar some depois de TIMEOUT.

const TIMEOUT := 2.5
const BAD := Color(1.0, 0.32, 0.25)

var colony: Colony
var _g := {}   # peer -> {"root", "model", "kind", "foot", "label", "mat", "foot_mat", "pos", "rot", "t", "target"}
var _demolish_mat: StandardMaterial3D


func _ready() -> void:
	_demolish_mat = _mat(Color(1.0, 0.25, 0.15, 0.4))


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
	return m


static func player_color(pid: int) -> Color:
	return Color.from_hsv(fposmod(pid * 0.618034, 1.0), 0.55, 1.0)


static func player_name(pid: int) -> String:
	if Network.players.has(pid):
		return str(Network.players[pid].name)
	return "?"


func count() -> int:
	return _g.size()


func has_ghost(pid: int) -> bool:
	return _g.has(pid)


func ghost_kind(pid: int) -> String:
	return str(_g[pid].kind) if _g.has(pid) else ""


func ghost_position(pid: int) -> Vector3:
	return _g[pid].pos if _g.has(pid) else Vector3.ZERO


## Chegou o estado do fantasma de um jogador ("" = saiu do modo construção).
func update_ghost(pid: int, kind: String, x: float, z: float, rot: float, ok: bool, target: int) -> void:
	if kind == "":
		_remove(pid)
		return
	var g: Dictionary = _g.get(pid, {})
	if g.is_empty():
		g = _create(pid)
		_g[pid] = g
		g.root.position = Vector3(x, 0, z)
		g.root.rotation.y = rot
	if g.kind != kind:
		_set_kind(g, kind)
	g.pos = Vector3(x, 0, z)
	g.rot = rot
	g.t = TIMEOUT
	var who := player_name(pid)
	var col := player_color(pid)
	if kind == "demolish":
		_set_target(g, target)
		g.label.text = "%s vai demolir" % who
		g.label.modulate = BAD
		if g.target != null and is_instance_valid(g.target):
			g.pos = g.target.global_position
		g.foot.visible = false
		return
	_set_target(g, 0)
	var d := ColonyData.building(kind)
	var c := col if ok else BAD
	g.mat.albedo_color = Color(c.r, c.g, c.b, 0.36)
	g.foot_mat.albedo_color = Color(c.r, c.g, c.b, 0.26)
	(g.foot.mesh as PlaneMesh).size = d.get("size", Vector2(2, 2))
	g.foot.visible = true
	g.label.text = "%s · %s%s" % [who, str(d.get("name", kind)), "" if ok else " (não cabe)"]
	g.label.modulate = col.lerp(Color.WHITE, 0.35) if ok else BAD


func _create(pid: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "Ghost_%d" % pid
	add_child(root)
	var foot := MeshInstance3D.new()
	foot.mesh = PlaneMesh.new()
	foot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	foot.position.y = 0.06
	var fm := _mat(Color(1, 1, 1, 0.25))
	foot.material_override = fm
	root.add_child(foot)
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.font_size = 26
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0, 0.85)
	add_child(label)
	return {"root": root, "model": null, "kind": "", "foot": foot, "label": label, "mat": _mat(Color(1, 1, 1, 0.36)),
		"foot_mat": fm, "pos": Vector3.ZERO, "rot": 0.0, "t": TIMEOUT, "target": null, "h": 4.0}


func _set_kind(g: Dictionary, kind: String) -> void:
	if g.model != null and is_instance_valid(g.model):
		g.model.queue_free()
	g.model = null
	g.kind = kind
	if kind == "demolish":
		return
	var m: Node3D = ColonyVisuals.make(kind, 1)
	for l in m.find_children("*", "Light3D", true, false):
		l.queue_free()
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = g.mat
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.root.add_child(m)
	g.model = m
	var d := ColonyData.building(kind)
	g.h = 3.0 + maxf(d.get("size", Vector2(2, 2)).x, d.get("size", Vector2(2, 2)).y) * 0.35


## Demolição: marca a construção mirada (e desmarca a anterior).
func _set_target(g: Dictionary, net_id: int) -> void:
	var b = colony.bmap.get(net_id) if net_id != 0 and colony != null else null
	if b != null and (not is_instance_valid(b) or b.dead):
		b = null
	if g.target == b:
		return
	_unmark(g)
	g.target = b
	if b != null:
		b._set_overlay(_demolish_mat)


func _unmark(g: Dictionary) -> void:
	var old = g.target
	g.target = null
	if old != null and is_instance_valid(old) and not old.dead:
		old._set_overlay(null)


func _remove(pid: int) -> void:
	var g: Dictionary = _g.get(pid, {})
	if g.is_empty():
		return
	_unmark(g)
	g.root.queue_free()
	g.label.queue_free()
	_g.erase(pid)


func clear() -> void:
	for pid in _g.keys():
		_remove(pid)


func _process(delta: float) -> void:
	for pid in _g.keys():
		var g: Dictionary = _g[pid]
		g.t -= delta
		if g.t <= 0.0 or (colony != null and colony.phase == "over"):
			_remove(pid)
			continue
		var r: Node3D = g.root
		var k := minf(1.0, delta * 14.0)
		r.position = r.position.lerp(g.pos, k)
		r.rotation.y = lerp_angle(r.rotation.y, g.rot, k)
		var h: float = g.h
		if g.kind == "demolish" and g.target != null and is_instance_valid(g.target):
			h = 2.5 + g.target.size.length() * 0.3
		g.label.position = r.position + Vector3.UP * h
