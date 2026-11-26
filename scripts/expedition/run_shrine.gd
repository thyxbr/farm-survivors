extends StaticBody3D
## Santuário de uma sala sem luta da expedição (event, reward, rest no ExpeditionDefs): o objeto da sala com que o
## jogador interage ([E]). Serve uma vez por run; quem decide o que acontece é o modo da expedição
## (expedition.use_shrine), as regras ficam no ExpeditionRun (choose_event, offer_reward, rest).
##
## Visual por tipo (`kind`), feito dos modelos de assets/models e de formas simples:
##   event  — estátua caída da Deusa (knight_f tingida de pedra) diante de uma bacia de sangue com runas vermelhas.
##   reward — baú das oferendas (chest) num estrado de pedra, com moedas e um brilho dourado.
##   rest   — fonte das raízes: poça de água clara com a fogueira (campfire) ao lado e vaga-lumes.
## Estados: ready (brilha, [E]), used (apagado, sem [E]) e sealed (o baú da Defesa das Oferendas enquanto os
## guardiões estão de pé: luz vermelha baixa, sem [E]; abre em ready quando a sala é limpa).

const READY := "ready"
const USED := "used"
const SEALED := "sealed"
const SEAL_COLOR := Color(0.9, 0.2, 0.18)

const LOOK := {
	"event": {"color": Color(0.95, 0.25, 0.25), "prompt": "Santuário Abandonado — examinar a oferenda"},
	"reward": {"color": Color(1.0, 0.82, 0.4), "prompt": "Baú das Oferendas — receber uma bênção"},
	"rest": {"color": Color(0.55, 0.95, 1.0), "prompt": "Fonte das Raízes — descansar"},
}
const RADIUS := 0.9

var expedition: Node
var room := ""
## event, reward ou rest (o tipo da sala).
var kind := "event"
var state := READY
var npc_id := "run_shrine"   # lido pelos testes e pela depuração junto com os NPCs

var _visual: Node3D
var _glow_mat: StandardMaterial3D
var _light: OmniLight3D
var _motes: Array[MeshInstance3D] = []
var _t := 0.0


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = RADIUS
	cyl.height = 1.2
	shape.shape = cyl
	shape.position.y = 0.6
	add_child(shape)
	if DisplayServer.get_name() != "headless":
		_build_visual()
	_apply_state()


func color() -> Color:
	return LOOK.get(kind, LOOK.event).color


func interact_prompt() -> String:
	return str(LOOK.get(kind, LOOK.event).prompt)


func interact(_player: Node) -> void:
	if state != READY or expedition == null or not is_instance_valid(expedition):
		return
	expedition.use_shrine(room)


func set_state(s: String) -> void:
	if s == state:
		return
	var was := state
	state = s
	_apply_state()
	if s in [USED, READY] and was != "" and is_inside_tree() and DisplayServer.get_name() != "headless":
		if s == USED or was == SEALED:   # gastou, ou o lacre se quebrou (as oferendas se libertam)
			FX.burst(global_position + Vector3.UP * 1.0, color(), 18, 2.6, 0.08, 0.8, -3.0)
			FX.ring(global_position + Vector3.UP * 0.08, color(), 2.2, 0.6)


func _apply_state() -> void:
	if state == READY:
		if not is_in_group("interactable"):
			add_to_group("interactable")
	elif is_in_group("interactable"):
		remove_from_group("interactable")
	if _visual == null:
		return
	var c := SEAL_COLOR if state == SEALED else color()
	_glow_mat.albedo_color = Color(c, 0.6 if state == READY else (0.3 if state == SEALED else 0.05))
	_light.light_color = c
	_light.light_energy = 2.2 if state == READY else (0.9 if state == SEALED else 0.35)
	for m in _motes:
		m.visible = state == READY


func _process(delta: float) -> void:
	if _visual == null or state != READY:
		return
	_t += delta
	var pulse := 0.5 + 0.5 * sin(_t * 2.2)
	_glow_mat.albedo_color.a = 0.35 + 0.35 * pulse
	_light.light_energy = 1.8 + 0.8 * pulse
	for i in _motes.size():
		var a := _t * (0.6 + 0.12 * i) + TAU * i / _motes.size()
		var r := 1.2 + 0.3 * sin(_t * 1.1 + i)
		_motes[i].position = Vector3(cos(a) * r, 0.9 + 0.5 * sin(_t * 0.8 + i * 1.9), sin(a) * r)


# ================================================================ visual
func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	var c := color()
	# anel no chão (o mesmo desenho do altar, na cor do santuário)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.55
	tm.outer_radius = 1.72
	tm.rings = 32
	tm.ring_segments = 4
	ring.mesh = tm
	ring.scale = Vector3(1.0, 0.05, 1.0)
	ring.position.y = 0.06
	_glow_mat = _glow(Color(c, 0.6))
	ring.material_override = _glow_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(ring)
	match kind:
		"event":
			_build_event()
		"reward":
			_build_reward()
		_:
			_build_rest()
	_light = OmniLight3D.new()
	_light.light_color = c
	_light.omni_range = 7.5
	_light.position.y = 1.6
	_visual.add_child(_light)
	var mote_mat := _glow(Color(c.lightened(0.3), 0.95))
	for i in 5:
		var m := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.035
		s.height = 0.07
		s.radial_segments = 6
		s.rings = 3
		m.mesh = s
		m.material_override = mote_mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_visual.add_child(m)
		_motes.append(m)


## Estátua da Deusa tombada (de lado, meio afundada) e a bacia de sangue com a inscrição.
func _build_event() -> void:
	var stone := _lit(Color(0.42, 0.42, 0.4), 0.95)
	var statue := _model("knight_f", stone)
	if statue != null:
		statue.scale = Vector3.ONE * 1.25
		statue.rotation = Vector3(0.0, 0.4, PI / 2.0 - 0.12)   # caída de lado
		statue.position = Vector3(-0.4, 0.45, -1.4)
		_visual.add_child(statue)
	# bacia: degrau de pedra e a tigela com o sangue
	for part in [[0.85, 0.95, 0.3, 0.15, stone], [0.45, 0.55, 0.5, 0.55, stone]]:
		var m := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = part[0]
		cm.bottom_radius = part[1]
		cm.height = part[2]
		cm.radial_segments = 8
		m.mesh = cm
		m.material_override = part[4]
		m.position.y = part[3]
		_visual.add_child(m)
	var bowl := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.62
	bm.bottom_radius = 0.38
	bm.height = 0.22
	bm.radial_segments = 10
	bowl.mesh = bm
	bowl.material_override = stone
	bowl.position.y = 0.9
	_visual.add_child(bowl)
	var blood := MeshInstance3D.new()
	var bl := CylinderMesh.new()
	bl.top_radius = 0.54
	bl.bottom_radius = 0.54
	bl.height = 0.02
	blood.mesh = bl
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.35, 0.02, 0.04)
	bmat.roughness = 0.1
	bmat.metallic = 0.3
	bmat.emission_enabled = true
	bmat.emission = Color(0.6, 0.05, 0.08)
	bmat.emission_energy_multiplier = 0.6
	blood.material_override = bmat
	blood.position.y = 1.01
	_visual.add_child(blood)
	# pilares partidos atrás
	for i in 2:
		var p := _model("ruin_pillar", null)
		if p != null:
			p.scale = Vector3.ONE * (0.55 + 0.15 * i)
			p.position = Vector3(1.6 - 3.4 * i, 0.0, -2.2)
			p.rotation.y = 0.7 * i
			_visual.add_child(p)


## Baú das oferendas num estrado, com moedas espalhadas.
func _build_reward() -> void:
	var stone := _lit(Color(0.36, 0.34, 0.3), 0.9)
	var dais := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(2.2, 0.3, 1.6)
	dais.mesh = dm
	dais.material_override = stone
	dais.position.y = 0.15
	_visual.add_child(dais)
	var chest := _model("chest", null)
	if chest != null:
		chest.scale = Vector3.ONE * 1.3
		chest.position.y = 0.3
		_visual.add_child(chest)
	var gold := _lit(Color(1.0, 0.78, 0.3), 0.3)
	gold.metallic = 0.9
	gold.emission_enabled = true
	gold.emission = Color(1.0, 0.7, 0.2)
	gold.emission_energy_multiplier = 0.4
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(room)
	for i in 14:
		var coin := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.08
		cm.bottom_radius = 0.08
		cm.height = 0.02
		cm.radial_segments = 8
		coin.mesh = cm
		coin.material_override = gold
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.9, 1.5)
		coin.position = Vector3(cos(a) * d, 0.02 + rng.randf() * 0.02, sin(a) * d * 0.8)
		coin.rotation = Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3))
		_visual.add_child(coin)


## Poça clara cercada de pedras, com a fogueira acesa ao lado.
func _build_rest() -> void:
	var pool := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 1.3
	pm.bottom_radius = 1.3
	pm.height = 0.04
	pm.radial_segments = 24
	pool.mesh = pm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.12, 0.35, 0.38)
	wm.metallic = 0.3
	wm.roughness = 0.05
	wm.emission_enabled = true
	wm.emission = Color(0.2, 0.6, 0.65)
	wm.emission_energy_multiplier = 0.5
	pool.material_override = wm
	pool.position.y = 0.03
	_visual.add_child(pool)
	var stone := _lit(Color(0.38, 0.38, 0.33), 0.95)
	for i in 9:
		var r := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.3
		sm.radial_segments = 6
		sm.rings = 3
		r.mesh = sm
		r.material_override = stone
		var a := TAU * i / 9.0
		r.position = Vector3(cos(a) * 1.4, 0.1, sin(a) * 1.4)
		_visual.add_child(r)
	var fire := _model("campfire", null)
	if fire != null:
		fire.position = Vector3(2.4, 0.0, 0.6)
		_visual.add_child(fire)
	var warm := OmniLight3D.new()
	warm.light_color = Color(1.0, 0.65, 0.35)
	warm.light_energy = 1.6
	warm.omni_range = 6.0
	warm.position = Vector3(2.4, 0.8, 0.6)
	_visual.add_child(warm)


## Modelo de assets/models (com o material `mat` em todas as malhas, se vier).
static func _model(name: String, mat: Material) -> Node3D:
	var path := "res://assets/models/%s.glb" % name
	if not ResourceLoader.exists(path):
		return null
	var inst: Node3D = (load(path) as PackedScene).instantiate()
	if mat != null:
		for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = mat
	return inst


static func _lit(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func _glow(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = c
	return m
