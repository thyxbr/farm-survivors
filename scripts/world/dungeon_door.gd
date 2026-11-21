extends Node3D
## Porta de dungeon (MapEntity kind "dungeon_door"): um arco de pedra com um véu escuro que brilha na cor da
## dungeon. No mapa de fora `target` é o id da dungeon (Regions.DATA, pede o rank dela); dentro, "out" leva de
## volta à porta de fora. [E] chama world.use_dungeon_door.
## "entrance" é o portal da sala do chefe (MapLoader): só aparece, e só dá para usar, enquanto não há chefe vivo
## na `arena` (a sala); leva de volta à entrada da dungeon.

const PILLAR := "res://assets/models/ruin_pillar.glb"
const COLORS := {"dg_bosque": Color(0.4, 1.0, 0.45), "dg_mina": Color(1.0, 0.65, 0.3), "dg_pico": Color(0.65, 0.35, 1.0),
	"dg_final": Color(1.0, 0.25, 0.35), "out": Color(0.95, 0.9, 0.7), "entrance": Color(0.55, 0.85, 1.0)}
## Segundos seguidos sem chefe vivo na sala até o portal abrir (o chefe de um cliente online pode demorar a chegar).
const OPEN_AFTER := 1.5

var target := "out"
var npc_id := "dungeon_door"   # lido pelos testes e pela depuração junto com os NPCs
var _veil: MeshInstance3D
var _t := 0.0
## Portal do chefe: a sala dele (x, z do mundo) e há quanto tempo ela está sem chefe vivo.
var arena := Rect2()
var _empty_t := 0.0
var _check := 0.0


func _ready() -> void:
	if target != "entrance":
		add_to_group("interactable")
	else:
		visible = false
	if DisplayServer.get_name() == "headless":
		return
	var c: Color = COLORS.get(target, Color(0.8, 0.8, 0.9))
	if ResourceLoader.exists(PILLAR):
		for x in [-1.6, 1.6]:
			var p: Node3D = (load(PILLAR) as PackedScene).instantiate()
			p.position = Vector3(x, 0, 0)
			p.scale = Vector3.ONE * 1.5
			add_child(p)
	var top := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(4.2, 0.5, 0.7)
	top.mesh = tb
	top.position.y = 4.1
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.45, 0.43, 0.4)
	top.material_override = stone
	add_child(top)
	_veil = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.6, 3.8)
	_veil.mesh = q
	_veil.position.y = 1.95
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r * 0.25, c.g * 0.25, c.b * 0.25, 0.85)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.8
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_veil.material_override = m
	add_child(_veil)
	var light := OmniLight3D.new()
	light.light_color = c
	light.light_energy = 1.2
	light.omni_range = 7.0
	light.position = Vector3(0, 2.0, 0.8)
	add_child(light)


func _process(delta: float) -> void:
	if target == "entrance":
		_watch_boss(delta)
	if _veil == null:
		return
	_t += delta
	(_veil.material_override as StandardMaterial3D).emission_energy_multiplier = 0.65 + 0.25 * sin(_t * 2.2)


## Portal do chefe: abre quando a sala fica sem chefe vivo e fecha quando ele volta.
func _watch_boss(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.25
	if is_open() and not boss_alive():
		return
	if boss_alive():
		_empty_t = 0.0
		_set_open(false)
		return
	_empty_t += 0.25
	if _empty_t >= OPEN_AFTER:
		_set_open(true)


## Se há chefe vivo na sala (com folga: perseguindo alguém na porta ele pode sair um pouco dela).
func boss_alive() -> bool:
	var area := arena.grow(6.0)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.get("is_boss") and not e.dead and area.has_point(Vector2(e.global_position.x, e.global_position.z)):
			return true
	return false


func is_open() -> bool:
	return is_in_group("interactable")


func _set_open(on: bool) -> void:
	if on == is_open():
		return
	visible = on
	if on:
		add_to_group("interactable")
		if DisplayServer.get_name() != "headless":
			FX.burst(global_position + Vector3.UP * 2.0, COLORS.entrance, 24, 4.0, 0.15, 0.9)
	else:
		remove_from_group("interactable")


func interact_prompt() -> String:
	if target == "out":
		return "Sair da dungeon"
	if target == "entrance":
		return "Portal: voltar à entrada"
	return "Entrar: %s (Rank %s)" % [Regions.display_name(target), str(Regions.DATA.get(target, {}).get("rank", "?"))]


func interact(_player: Node) -> void:
	var world := get_tree().current_scene
	if world.has_method("use_dungeon_door"):
		world.use_dungeon_door(target)
