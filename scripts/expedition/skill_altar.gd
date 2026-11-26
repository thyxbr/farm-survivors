extends StaticBody3D
## Altar da Deusa (expedição roguelite): onde o jogador ganha as habilidades da run. [E] perto dele abre a escolha
## de 1 entre 3 habilidades do kit do personagem (skill_altar_ui.gd; regras em ExpeditionSkills/ExpeditionRun).
## Serve uma vez só.
##
## Visual (combina com o Pântano Sussurrante e a Deusa): pedestal de pedra sextavado tomado por musgo e raízes,
## numa poça rasa de água escura; em cima, um cristal de luz da Deusa flutua girando dentro de um halo dourado,
## com vaga-lumes em volta e um anel de runas no chão.
## Estados (`state`):
##   dormant — sala de luta ainda não limpa: pedra apagada, cristal cinza, sem interação ("Vença a luta").
##   ready   — desperto: cristal e halo brilham e pulsam, luz azul-esverdeada; [E] abre a escolha.
##   used    — já deu a habilidade: o cristal se partiu, sobra o halo escuro e um brilho fraco.
##
## Quem decide o estado é o dono (expedition_mode.gd: refresh_altars); quem aplica a escolha também
## (expedition.open_altar / choose_skill).

const DORMANT := "dormant"
const READY := "ready"
const USED := "used"

const COLOR_LIGHT := Color(0.55, 1.0, 0.85)     # luz da Deusa (verde-água)
const COLOR_GOLD := Color(1.0, 0.84, 0.45)      # halo
const COLOR_STONE := Color(0.33, 0.35, 0.31)
const COLOR_MOSS := Color(0.24, 0.36, 0.17)
const COLOR_ROOT := Color(0.24, 0.17, 0.1)
const COLOR_WATER := Color(0.06, 0.12, 0.1)
const RADIUS := 0.75   ## colisão do pedestal (m)
const CRYSTAL_Y := 1.85

var expedition: Node
## Sala do ExpeditionDefs onde o altar fica.
var room := ""
var state := DORMANT
## Altar de evolução da build (Altar Ancestral, ExpeditionDefs "mode": "evolve"): só muda o texto do [E].
var evolve := false
var npc_id := "skill_altar"   # lido pelos testes e pela depuração junto com os NPCs

var _crystal: MeshInstance3D
var _crystal_mat: StandardMaterial3D
var _halo: MeshInstance3D
var _halo_mat: StandardMaterial3D
var _rune_mat: StandardMaterial3D
var _light: OmniLight3D
var _motes: Array[MeshInstance3D] = []
## Lascas do cristal partido no tampo (só no estado "used").
var _shards: Node3D
var _visual: Node3D
var _t := 0.0


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = RADIUS
	cyl.height = 1.4
	shape.shape = cyl
	shape.position.y = 0.7
	add_child(shape)
	if DisplayServer.get_name() != "headless":
		_build_visual()
	_apply_state()


# ================================================================ interação
func interact_prompt() -> String:
	if evolve:
		return "Altar Ancestral — evoluir a build"
	return "Altar da Deusa — receber uma habilidade"


func interact(_player: Node) -> void:
	if state != READY or expedition == null or not is_instance_valid(expedition):
		return
	expedition.open_altar(room)


## Muda o estado (o dono chama). Só fica no grupo "interactable" desperto: dormindo ou gasto não mostra o [E].
func set_state(s: String) -> void:
	if s == state:
		return
	var was := state
	state = s
	_apply_state()
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		if s == READY and was == DORMANT:
			FX.burst(global_position + Vector3.UP * CRYSTAL_Y, COLOR_LIGHT, 22, 3.0, 0.1, 0.9, -1.0)
			FX.ring(global_position + Vector3.UP * 0.08, COLOR_LIGHT, 2.4, 0.8)
		elif s == USED:
			# o cristal estoura em lascas de luz (pequenas, para não cobrir a tela) e assenta no tampo
			FX.burst(global_position + Vector3.UP * CRYSTAL_Y, COLOR_LIGHT, 18, 2.6, 0.06, 0.8, -6.0)
			FX.ring(global_position + Vector3.UP * 0.08, COLOR_LIGHT, 1.7, 0.5)


func _apply_state() -> void:
	if state == READY:
		if not is_in_group("interactable"):
			add_to_group("interactable")
	elif is_in_group("interactable"):
		remove_from_group("interactable")
	if _visual == null:
		return
	_crystal.visible = state != USED
	_shards.visible = state == USED
	match state:
		READY:
			_crystal_mat.albedo_color = COLOR_LIGHT
			_crystal_mat.emission = COLOR_LIGHT
			_crystal_mat.emission_energy_multiplier = 2.2
			_halo_mat.albedo_color = Color(COLOR_GOLD, 0.9)
			_rune_mat.albedo_color = Color(COLOR_LIGHT, 0.55)
			_light.light_energy = 2.4
		USED:
			_halo_mat.albedo_color = Color(COLOR_GOLD.darkened(0.55), 0.4)
			_rune_mat.albedo_color = Color(COLOR_GOLD, 0.06)
			_light.light_energy = 0.5
		_:
			_crystal_mat.albedo_color = Color(0.5, 0.55, 0.55)
			_crystal_mat.emission = Color(0.3, 0.4, 0.4)
			_crystal_mat.emission_energy_multiplier = 0.25
			_halo_mat.albedo_color = Color(COLOR_GOLD.darkened(0.5), 0.35)
			_rune_mat.albedo_color = Color(COLOR_LIGHT, 0.06)
			_light.light_energy = 0.45
	for m in _motes:
		m.visible = state == READY


func _process(delta: float) -> void:
	if _visual == null:
		return
	_t += delta
	if _crystal.visible:
		var sp := 1.4 if state == READY else 0.3
		_crystal.rotation.y += delta * sp
		_crystal.position.y = CRYSTAL_Y + (0.09 * sin(_t * 1.8) if state == READY else 0.0)
	_halo.rotation.y = sin(_t * 0.4) * 0.25
	if state == READY:
		var pulse := 0.5 + 0.5 * sin(_t * 2.6)
		_crystal_mat.emission_energy_multiplier = 1.6 + 1.2 * pulse
		_light.light_energy = 2.0 + 0.8 * pulse
		_rune_mat.albedo_color.a = 0.35 + 0.3 * pulse
		for i in _motes.size():
			var a := _t * (0.7 + 0.15 * i) + TAU * i / _motes.size()
			var r := 1.1 + 0.25 * sin(_t * 1.3 + i)
			_motes[i].position = Vector3(cos(a) * r, 1.2 + 0.6 * sin(_t * 0.9 + i * 1.7), sin(a) * r)


# ================================================================ visual
func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	var stone := _lit(COLOR_STONE, 0.95)
	var moss := _lit(COLOR_MOSS, 1.0)
	var root_mat := _lit(COLOR_ROOT, 0.95)
	# poça rasa de água escura em volta (o altar "brota" do brejo)
	var pool := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 1.9
	pm.bottom_radius = 1.9
	pm.height = 0.04
	pm.radial_segments = 24
	pool.mesh = pm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = COLOR_WATER
	wm.metallic = 0.3
	wm.roughness = 0.08
	pool.material_override = wm
	pool.position.y = 0.02
	_visual.add_child(pool)
	# anel de runas no chão (brilho aditivo): pulsa com o altar desperto
	var rune := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.45
	tm.outer_radius = 1.62
	tm.rings = 32
	tm.ring_segments = 4
	rune.mesh = tm
	rune.scale = Vector3(1.0, 0.05, 1.0)
	rune.position.y = 0.06
	_rune_mat = _glow(Color(COLOR_LIGHT, 0.5))
	rune.material_override = _rune_mat
	rune.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(rune)
	# pedestal: degrau largo, coluna sextavada e tampo, com musgo no topo de cada parte
	for part in [[0.95, 1.05, 0.28, 0.14], [0.5, 0.6, 1.0, 0.78], [0.72, 0.62, 0.18, 1.37]]:
		var m := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = part[0]
		c.bottom_radius = part[1]
		c.height = part[2]
		c.radial_segments = 6
		c.rings = 1
		m.mesh = c
		m.material_override = stone
		m.position.y = part[3]
		_visual.add_child(m)
		var cap := MeshInstance3D.new()
		var cc := CylinderMesh.new()
		cc.top_radius = part[0] * 0.92
		cc.bottom_radius = part[0] * 1.02
		cc.height = 0.05
		cc.radial_segments = 6
		cap.mesh = cc
		cap.material_override = moss
		cap.position.y = part[3] + part[2] / 2.0
		_visual.add_child(cap)
	# raízes que abraçam a coluna
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(room)
	for i in 5:
		var a := TAU * i / 5.0 + rng.randf_range(-0.2, 0.2)
		var r := MeshInstance3D.new()
		var rc := CylinderMesh.new()
		rc.top_radius = 0.03
		rc.bottom_radius = 0.11
		rc.height = rng.randf_range(1.1, 1.5)
		rc.radial_segments = 5
		rc.rings = 2
		r.mesh = rc
		r.material_override = root_mat
		r.position = Vector3(cos(a) * 0.72, rc.height * 0.42, sin(a) * 0.72)
		r.rotation = Vector3(sin(a) * -0.45, 0.0, cos(a) * 0.45)
		_visual.add_child(r)
	# halo dourado da Deusa, em pé atrás do cristal
	_halo = MeshInstance3D.new()
	var hm := TorusMesh.new()
	hm.inner_radius = 0.5
	hm.outer_radius = 0.56
	hm.rings = 36
	hm.ring_segments = 6
	_halo.mesh = hm
	_halo.rotation.x = PI / 2.0
	_halo.position.y = CRYSTAL_Y
	_halo_mat = _glow(Color(COLOR_GOLD, 0.9))
	_halo.material_override = _halo_mat
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(_halo)
	# cristal (octaedro: esfera de 4 lados e 2 anéis), esticado em pé
	_crystal = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.2
	sm.height = 0.62
	sm.radial_segments = 4
	sm.rings = 2
	_crystal.mesh = sm
	_crystal_mat = StandardMaterial3D.new()
	_crystal_mat.emission_enabled = true
	_crystal_mat.roughness = 0.2
	_crystal_mat.metallic = 0.2
	_crystal.material_override = _crystal_mat
	_crystal.position.y = CRYSTAL_Y
	_visual.add_child(_crystal)
	# vaga-lumes
	var mote_mat := _glow(Color(0.8, 1.0, 0.6, 0.95))
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
	# lascas do cristal partido, caídas no tampo (aparecem quando o altar é usado), com um resto de brilho
	_shards = Node3D.new()
	_shards.position.y = 1.47
	_shards.visible = false
	_visual.add_child(_shards)
	var shard_mat := StandardMaterial3D.new()
	shard_mat.albedo_color = COLOR_LIGHT.darkened(0.35)
	shard_mat.emission_enabled = true
	shard_mat.emission = COLOR_LIGHT
	shard_mat.emission_energy_multiplier = 0.6
	shard_mat.roughness = 0.25
	for i in 6:
		var sh := MeshInstance3D.new()
		var pm2 := PrismMesh.new()
		var h := rng.randf_range(0.12, 0.26)
		pm2.size = Vector3(rng.randf_range(0.06, 0.11), h, rng.randf_range(0.05, 0.09))
		sh.mesh = pm2
		sh.material_override = shard_mat
		var a := TAU * i / 6.0 + rng.randf_range(-0.3, 0.3)
		var d := rng.randf_range(0.1, 0.45)
		sh.position = Vector3(cos(a) * d, h * 0.3, sin(a) * d)
		sh.rotation = Vector3(rng.randf_range(-1.1, 1.1), rng.randf_range(0, TAU), rng.randf_range(-1.1, 1.1))
		_shards.add_child(sh)
	_light = OmniLight3D.new()
	_light.light_color = COLOR_LIGHT
	_light.omni_range = 8.0
	_light.position.y = CRYSTAL_Y
	_visual.add_child(_light)
	# luz baixa e fraca no pedestal: a pedra e as raízes aparecem mesmo no escuro da dungeon
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.7, 0.85, 0.75)
	fill.light_energy = 0.5
	fill.omni_range = 3.2
	fill.position = Vector3(0.0, 0.9, 1.3)
	_visual.add_child(fill)


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
