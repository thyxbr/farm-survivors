extends Node3D
## Modo construção: mostra um "fantasma" da construção onde a câmera mira (verde = pode, vermelho = não),
## os limites da cidade e o alcance das torres. Clique constrói, roda do mouse/R gira 45°, X demolir.
## Muros, portões e estacas encaixam na ponta de outro muro com a mesma direção.

var world: Node
var colony: Colony
var active := false
var selected := ""        # tipo de construção ou "demolish"
var rot := 0.0
var aim := Vector3.ZERO
var place_pos := Vector3.ZERO
var reason := ""
var hover: ColonyBuilding = null

var _ghost: Node3D
var _ghost_kind := ""
var _foot: MeshInstance3D
var _range_ring: MeshInstance3D
var _city_ring: MeshInstance3D
var _ok_mat: StandardMaterial3D
var _bad_mat: StandardMaterial3D
var _foot_ok: StandardMaterial3D
var _foot_bad: StandardMaterial3D
var _demolish_mat: StandardMaterial3D
var _help_was := true
## Cidade em grupo: o fantasma vai para os outros jogadores (só quando muda, e um "estou aqui" a cada 0,8 s).
const NET_GAP := 0.12
const NET_HEARTBEAT := 0.8
var _net_t := 0.0
var _net_beat := 0.0
var _net_last: Array = []


func _ready() -> void:
	_ok_mat = _ghost_mat(Color(0.35, 1.0, 0.45, 0.42))
	_bad_mat = _ghost_mat(Color(1.0, 0.3, 0.25, 0.42))
	_foot_ok = _ghost_mat(Color(0.35, 1.0, 0.45, 0.28))
	_foot_bad = _ghost_mat(Color(1.0, 0.3, 0.25, 0.28))
	_demolish_mat = _ghost_mat(Color(1.0, 0.25, 0.15, 0.45))
	_foot = MeshInstance3D.new()
	_foot.mesh = PlaneMesh.new()
	_foot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_foot)
	_range_ring = _ring(Color(1.0, 0.85, 0.35, 0.55))
	_city_ring = _ring(Color(0.5, 0.75, 1.0, 0.5))
	_set_visible(false)


func _ghost_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.no_depth_test = false
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _ring(c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.92
	t.outer_radius = 1.0
	t.rings = 64
	t.ring_segments = 4
	mi.mesh = t
	mi.material_override = _ghost_mat(c)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Anel fino no chão com o raio dado (o tubo fica com 30 cm, qualquer que seja o raio).
func _set_ring(mi: MeshInstance3D, r: float) -> void:
	var t := mi.mesh as TorusMesh
	if absf(t.outer_radius - (r + 0.15)) > 0.01:
		t.inner_radius = r - 0.15
		t.outer_radius = r + 0.15


func _set_visible(on: bool) -> void:
	_foot.visible = on
	_range_ring.visible = on
	_city_ring.visible = on
	if _ghost:
		_ghost.visible = on


# ---------------------------------------------------------------- controle
func set_active(on: bool) -> void:
	if colony.phase == "over":
		on = false
	if on != active and world.hud and world.hud.help_panel:
		# a barra de construção ocupa a parte de baixo: a ajuda some enquanto constrói
		if on:
			_help_was = world.hud.help_panel.visible
			world.hud.help_panel.visible = false
		else:
			world.hud.help_panel.visible = _help_was
	active = on
	if world.player:
		world.player.build_lock = on
	if on:
		if colony.hall == null or not is_instance_valid(colony.hall):
			select("town_hall")
		elif selected == "" or selected == "town_hall":
			select("house")
		else:
			select(selected)
	else:
		_clear_hover()
		_send_ghost_off()
	_set_visible(on)


func toggle() -> void:
	set_active(not active)
	Sfx.play("click", 0.0)


func select(kind: String) -> void:
	if kind != "town_hall" and kind != "demolish" and (colony.hall == null or not is_instance_valid(colony.hall)):
		Game.notify.emit("Primeiro posicione a prefeitura.", Color(1, 0.8, 0.5))
		kind = "town_hall"
	selected = kind
	_clear_hover()
	if _ghost_kind != kind:
		if _ghost:
			_ghost.queue_free()
			_ghost = null
		_ghost_kind = kind
		if kind != "demolish":
			_ghost = ColonyVisuals.make(kind, 1)
			for l in _ghost.find_children("*", "Light3D", true, false):
				l.queue_free()
			add_child(_ghost)
	if _ghost:
		_ghost.visible = active


func select_index(i: int) -> void:
	if colony.hall == null or not is_instance_valid(colony.hall):
		select("town_hall")
		return
	if i >= 0 and i < ColonyData.ORDER.size():
		select(ColonyData.ORDER[i])
		Sfx.play("click", 0.0)


func rotate_step(dir: int) -> void:
	rot = wrapf(rot + dir * PI / 4.0, -PI, PI)


func try_place() -> void:
	if selected == "demolish":
		if hover:
			colony.demolish(hover)
			hover = null
		else:
			Game.notify.emit("Mire numa construção para demolir.", Color(1, 0.8, 0.5))
		return
	if reason != "":
		Game.notify.emit(reason, UITheme.BAD)
		Sfx.play("click", 0.0, -6.0)
		return
	var kind := selected
	colony.place(kind, place_pos, rot)
	if kind == "town_hall" and colony.role != "client":   # em grupo a prefeitura chega do servidor
		select("house")


# ---------------------------------------------------------------- atualização
func _process(delta: float) -> void:
	if not active or world.player == null:
		return
	_update_preview()
	_send_ghost(delta)


## Cidade em grupo: manda o que está sendo posicionado (tipo, lugar, giro, se cabe e o alvo da demolição).
func _send_ghost(delta: float) -> void:
	if colony.role != "client":
		return
	_net_t -= delta
	_net_beat -= delta
	var target: int = hover.net_id if hover != null and is_instance_valid(hover) else 0
	var p := [selected, snappedf(place_pos.x, 0.01), snappedf(place_pos.z, 0.01), snappedf(rot, 0.01), reason == "", target]
	if selected == "demolish":
		p[1] = snappedf(aim.x, 0.25)
		p[2] = snappedf(aim.z, 0.25)
	if (p != _net_last and _net_t <= 0.0) or _net_beat <= 0.0:
		_net_t = NET_GAP
		_net_beat = NET_HEARTBEAT
		_net_last = p
		Lobby.city_ghost(p[0], p[1], p[2], p[3], p[4], p[5])


func _send_ghost_off() -> void:
	if is_instance_valid(colony) and colony.role == "client" and not _net_last.is_empty():
		_net_last = []
		Lobby.city_ghost("", 0.0, 0.0, 0.0, false, 0)


func _update_preview() -> void:
	aim = _aim_point()
	var center: Vector3
	var radius: float
	if colony.hall and is_instance_valid(colony.hall) and not colony.hall.dead:
		center = colony.hall.global_position
		radius = ColonyData.CITY_RADIUS
	else:
		center = Vector3.ZERO
		radius = ColonyData.HALL_ZONE
	_city_ring.position = Vector3(center.x, 0.06, center.z)
	_set_ring(_city_ring, radius)

	if selected == "demolish":
		_update_hover()
		_foot.visible = false
		_range_ring.visible = false
		reason = "" if hover else "Mire numa construção."
		return

	var d := ColonyData.building(selected)
	place_pos = _snap(aim, d)
	reason = colony.can_place(selected, place_pos, rot)
	var ok := reason == ""
	if _ghost:
		_ghost.visible = true
		_ghost.position = place_pos
		_ghost.rotation.y = rot
		var m := _ok_mat if ok else _bad_mat
		for mi in _ghost.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).material_override != m:
				(mi as MeshInstance3D).material_override = m
				(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_foot.visible = true
	_foot.position = place_pos + Vector3.UP * 0.07
	_foot.rotation.y = rot
	(_foot.mesh as PlaneMesh).size = d.size
	_foot.material_override = _foot_ok if ok else _foot_bad
	if ColonyData.is_tower(selected):
		var r: float = d.range
		_range_ring.visible = true
		_range_ring.position = place_pos + Vector3.UP * 0.08
		_set_ring(_range_ring, r)
	else:
		_range_ring.visible = false


## Ponto no chão para onde a câmera mira (limitado a uma distância razoável do jogador).
func _aim_point() -> Vector3:
	var p: Player = world.player
	var cam := p.camera
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var flat := Vector3(dir.x, 0, dir.z)
	if flat.length() < 0.01:
		flat = p.facing()
	flat = flat.normalized()
	var hit: Vector3
	if dir.y < -0.03:
		hit = from + dir * (-from.y / dir.y)
	else:
		hit = p.global_position + flat * 24.0
	var off := hit - p.global_position
	off.y = 0.0
	if off.length() > 28.0:
		hit = p.global_position + off.normalized() * 28.0
	hit.y = 0.0
	return hit


func _snap(p: Vector3, d: Dictionary) -> Vector3:
	var q := Vector3(snappedf(p.x, 0.5), 0.0, snappedf(p.z, 0.5))
	if not d.get("wall", false):
		return q
	# encaixe na ponta de outro muro/portão/estaca alinhado
	var half: float = d.size.x / 2.0
	var best := q
	var best_d := 1.8
	for b in colony.buildings():
		if not b.data.get("wall", false):
			continue
		var diff := absf(angle_difference(b.rotation.y, rot))
		if diff > 0.05 and absf(diff - PI) > 0.05:
			continue
		var axis := Vector3(cos(b.rotation.y), 0, -sin(b.rotation.y))
		var bh: float = b.size.x / 2.0
		for sgn in [-1.0, 1.0]:
			var cand: Vector3 = b.global_position + axis * (bh + half) * sgn
			var dist := Vector2(cand.x - p.x, cand.z - p.z).length()
			if dist < best_d:
				best_d = dist
				best = Vector3(cand.x, 0.0, cand.z)
	return best


func _update_hover() -> void:
	var found: ColonyBuilding = null
	var best := 2.0
	for b in colony.buildings():
		var dd: float = b.distance_to_point(aim)
		if dd < best:
			best = dd
			found = b
	if found != hover:
		_clear_hover()
		hover = found
		if hover:
			hover._set_overlay(_demolish_mat)


func _exit_tree() -> void:
	_send_ghost_off()


func _clear_hover() -> void:
	if hover and is_instance_valid(hover) and not hover.dead:
		hover._set_overlay(null)
	hover = null
