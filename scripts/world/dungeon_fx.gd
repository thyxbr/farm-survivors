extends Node3D
## Efeitos da dungeon no cliente (MapDungeon monta; só com tela): tochas tremendo e a entrada da sala do chefe.
## O portão fica fechado e a sala do chefe escura; quando o jogador local chega perto, a tela treme, as folhas do
## portão giram para dentro, os braseiros da sala acendem um a um em volta e o círculo de runas pulsa, com o nome da
## sala em destaque. Cada cliente abre o seu (o portão não tem colisão: é cena, não tranca).

const OPEN_DIST := 10.0
const OPEN_TIME := 2.6
const IGNITE_STEP := 0.32

var _flicker: Array = []   # [luz, energia, fase]
var _gate: Node3D
var _leaves: Array = []    # [dobradiça, lado]
var _ring: Array = []      # braseiros da sala, do mais perto ao mais longe do portão
var _circle: MeshInstance3D
var _gate_pos := Vector3.ZERO
var _opened := false
var _t := 0.0
var _check := 0.0


func add_flicker(l: OmniLight3D) -> void:
	_flicker.append([l, l.light_energy, randf() * 10.0])


func setup_gate(gate: Node3D, leaves: Array, ring: Array, circle: MeshInstance3D, pos: Vector3) -> void:
	_gate = gate
	_leaves = leaves
	_ring = ring
	_circle = circle
	_gate_pos = pos
	if _circle != null:
		_circle.visible = false


func is_open() -> bool:
	return _opened


func _process(delta: float) -> void:
	_t += delta
	for f in _flicker:
		var l: OmniLight3D = f[0]
		var ph: float = f[2]
		l.light_energy = float(f[1]) * (0.85 + 0.1 * sin(_t * 9.0 + ph) + 0.05 * sin(_t * 23.0 + ph * 2.0))
	if _gate == null or _opened:
		return
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.2
	var p := _local_player()
	if p != null and p.global_position.distance_to(to_global(_gate_pos)) < OPEN_DIST:
		open()


func _local_player() -> Node3D:
	var w := get_tree().current_scene
	return w.get("player") if w != null else null


## Abre o portão (a cena inteira de entrada). Chamar de novo não faz nada.
func open() -> void:
	if _opened or _gate == null:
		return
	_opened = true
	var p := _local_player()
	if p != null and p.has_method("add_shake"):
		p.add_shake(0.7)
	Sfx.play_at("slam", to_global(_gate_pos), 0.0)
	var tw := create_tween().set_parallel(true)
	for lf in _leaves:
		var hinge: Node3D = lf[0]
		var side: float = lf[1]
		tw.tween_property(hinge, "rotation:y", -side * 1.7, OPEN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for i in _ring.size():
		var b: Node3D = _ring[i]
		var l: OmniLight3D = b.get_node("Light")
		var flame: Node3D = b.get_node("Flame")
		var e: float = b.get_meta("energy", 2.4)
		var at := 0.8 + i * IGNITE_STEP
		tw.tween_callback(func() -> void:
			flame.visible = true
			flame.scale = Vector3.ONE * 0.2).set_delay(at)
		tw.tween_property(flame, "scale", Vector3.ONE, 0.35).set_delay(at)
		tw.tween_property(l, "light_energy", e, 0.4).set_delay(at)
	if _circle != null:
		var on := 0.8 + _ring.size() * IGNITE_STEP
		tw.tween_callback(func() -> void: _circle.visible = true).set_delay(on)
		tw.tween_property(_circle, "scale", Vector3(1.0, 0.05, 1.0), 0.6).from(Vector3(0.2, 0.05, 0.2)).set_delay(on)
	_banner()


## Nome da sala do chefe em destaque (o letreiro das regiões).
func _banner() -> void:
	var w := get_tree().current_scene
	var hud = w.get("hud") if w != null else null
	if hud == null or hud.get("region_banner") == null:
		return
	var at := to_global(_gate_pos)
	var region := Regions.region_at(at)
	var title := Regions.display_name(region)
	var id := Regions.area_at(at - _gate.global_basis.z * 8.0)   # 8 m para dentro da sala
	if id != "":
		title = Regions.area_info(Balance.tables.get_table("regions"), id).name
	hud.region_banner.show_area(title, "Sala do chefe · %s" % Regions.display_name(region))
