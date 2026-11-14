extends StaticBody3D
## Um ponto da praça com que o jogador interage ([E]): portal da Horda, mesa de guerra (Defesa da Cidade),
## estrada para Valdoria, mestre das passivas, mercador, quadro de recordes ou uma construção da base.
## Monta o próprio visual pelo `kind`. A estrada viaja na hora; os outros abrem o painel da praça
## (hub_world.open_point_panel); o botão do painel do portal leva à Horda (Hub.go_horde).
##
## A construção da base fica atrás do ponto (o nó é a placa/caixa de doações na frente dela, virada para
## o centro da praça): a distância de interação do Player é medida até este nó, e um prédio de 6 m com o
## ponto no meio ficaria fora do alcance.

const MODELS := {
	"elder": preload("res://assets/models/elder.glb"),
	"merchant": preload("res://assets/models/merchant.glb"),
	"crate": preload("res://assets/models/crate.glb"),
	"barrel": preload("res://assets/models/barrel.glb"),
	"fence": preload("res://assets/models/fence.glb"),
	"chest": preload("res://assets/models/chest.glb"),
}
const PORTAL := preload("res://scripts/world/challenge_portal.gd")
const KINDS := ["horde_portal", "war_table", "road", "passive_master", "merchant", "records", "building"]
## Nomes dos personagens da praça.
const NPC_NAMES := {"passive_master": "Mestre Orin, guardião dos Ecos", "merchant": "Tobias, o Mercador"}
## Pegada (largura, altura, profundidade) dos modelos de ColonyVisuals usados pela base, para a colisão.
const BUILDING_SIZE := {"barracks": Vector3(6.6, 4.0, 5.6), "gate": Vector3(4.4, 4.0, 1.4), "farm": Vector3(7.0, 3.0, 6.0)}
## Distância do prédio atrás do ponto (m).
const BUILDING_BACK := 4.2

@export var kind: String = "road"
@export var building_id := ""

var model: Node3D
var _label: Label3D
var _building: Node3D
var _level := -1
var _base_yaw := 0.0
var _t := 0.0


func _ready() -> void:
	add_to_group("interactable")
	collision_layer = 8
	collision_mask = 0
	match kind:
		"horde_portal":
			_build_portal()
		"war_table":
			_build_war_table()
		"road":
			_build_road()
		"passive_master", "merchant":
			_build_npc()
		"records":
			_build_records()
		"building":
			_build_base_building()
	set_process(kind in ["passive_master", "merchant"])   # só os NPCs viram para o jogador
	if kind == "records" or kind == "building":
		Hub.changed.connect(_on_hub_changed)
		_on_hub_changed()


func interact_prompt() -> String:
	match kind:
		"horde_portal":
			return "Entrar no Portal do Desafio da Horda"
		"war_table":
			return "Mesa de guerra — Defesa da Cidade"
		"road":
			return "Seguir a estrada para Valdoria"
		"passive_master":
			return "Falar com Mestre Orin (passivas)"
		"merchant":
			return "Falar com Tobias, o Mercador"
		"records":
			return "Ler o quadro de recordes"
		"building":
			return "%s — doar para a base" % _building_name()
	return ""


func interact(_player: Node) -> void:
	match kind:
		"road":
			Lobby.go_world()
		_:
			var w := get_tree().current_scene
			if w != null and w.has_method("open_point_panel"):
				w.open_point_panel(self)


func _process(delta: float) -> void:
	if model == null:
		return
	# o NPC vira para o jogador local quando ele chega perto (como os da vila; réplicas não contam)
	_t += delta
	var w := get_tree().current_scene
	var player := w.get("player") as Node3D if w != null else null
	var target := _base_yaw
	if player and player.global_position.distance_to(global_position) < 7.0:
		var to := player.global_position - global_position
		target = atan2(to.x, to.z) - global_rotation.y
	model.rotation.y = lerp_angle(model.rotation.y, target, 4.0 * delta)


# ================================================================ visuais
func _shape(size: Vector3, pos: Vector3, capsule := false) -> void:
	var cs := CollisionShape3D.new()
	if capsule:
		var cap := CapsuleShape3D.new()
		cap.radius = size.x
		cap.height = size.y
		cs.shape = cap
	else:
		var b := BoxShape3D.new()
		b.size = size
		cs.shape = b
	cs.position = pos
	add_child(cs)


func _tag(text: String, y: float, color: Color, size := 40) -> Label3D:
	var tag := Label3D.new()
	tag.text = text
	tag.font_size = size
	tag.outline_size = 8
	tag.pixel_size = 0.005
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position.y = y
	tag.modulate = color
	add_child(tag)
	return tag


func _glb(id: String, pos: Vector3, yaw := 0.0, s := 1.0) -> Node3D:
	var n: Node3D = MODELS[id].instantiate()
	n.position = pos
	n.rotation.y = yaw
	n.scale = Vector3.ONE * s
	add_child(n)
	return n


func _box(size: Vector3, pos: Vector3, c: Color, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	bm.material = m
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_npc() -> void:
	model = _glb("elder" if kind == "passive_master" else "merchant", Vector3.ZERO)
	_base_yaw = model.rotation.y
	_shape(Vector3(0.4, 1.8, 0), Vector3(0, 0.9, 0), true)
	_tag(NPC_NAMES[kind], 2.35, Color(1, 0.95, 0.8))
	if kind == "merchant":
		# a banca do Tobias
		_glb("crate", Vector3(-1.1, 0, -0.6), 0.3)
		_glb("crate", Vector3(-1.05, 0.8, -0.6), -0.2, 0.75)
		_glb("barrel", Vector3(1.1, 0, -0.5))
		_glb("chest", Vector3(0.0, 0, -1.2), PI)
	else:
		# brilho azulado dos Ecos em volta do mestre
		var l := OmniLight3D.new()
		l.light_color = Color(0.55, 0.75, 1.0)
		l.light_energy = 1.2
		l.omni_range = 4.5
		l.position = Vector3(0, 1.6, 0.4)
		add_child(l)


## Reaproveita o portal da vila só como visual: quem interage é este ponto (a Horda pela praça).
func _build_portal() -> void:
	var p: Node3D = PORTAL.new()
	add_child(p)
	p.remove_from_group("interactable")
	_shape(Vector3(2.4, 0.2, 0.6), Vector3(0, 0.1, 0))


func _build_war_table() -> void:
	var wood := Color(0.42, 0.28, 0.16)
	_box(Vector3(2.6, 0.12, 1.5), Vector3(0, 0.95, 0), wood)
	for x in [-1.15, 1.15]:
		for z in [-0.6, 0.6]:
			_box(Vector3(0.12, 0.9, 0.12), Vector3(x, 0.45, z), wood.darkened(0.2))
	# o mapa da cidade aberto na mesa, com marcadores
	_box(Vector3(2.0, 0.02, 1.1), Vector3(0, 1.02, 0), Color(0.86, 0.78, 0.58))
	for m in [[Vector3(-0.5, 1.07, -0.2), Color(0.75, 0.15, 0.12)], [Vector3(0.4, 1.07, 0.25), Color(0.15, 0.3, 0.75)],
			[Vector3(0.1, 1.07, -0.3), Color(0.75, 0.15, 0.12)]]:
		_box(Vector3(0.1, 0.1, 0.1), m[0], m[1])
	_glb("crate", Vector3(-1.9, 0, 0.5), 0.4)
	_glb("crate", Vector3(-1.85, 0, -0.5), -0.2)
	_glb("crate", Vector3(-1.9, 0.8, 0.0), 0.1, 0.75)
	_glb("barrel", Vector3(1.9, 0, -0.6))
	_shape(Vector3(2.6, 1.0, 1.5), Vector3(0, 0.5, 0))
	_tag("Mesa de Guerra", 2.0, Color(1, 0.85, 0.55))


func _build_road() -> void:
	# placa de madeira na saída sul da praça
	var wood := Color(0.45, 0.3, 0.17)
	_box(Vector3(0.18, 2.4, 0.18), Vector3(0, 1.2, 0), wood.darkened(0.15))
	var plank := _box(Vector3(1.7, 0.42, 0.08), Vector3(0.35, 1.95, 0.13), wood)   # na frente do poste
	plank.rotation.z = -0.05
	var txt := Label3D.new()   # a frente do ponto (+Z) está virada para o centro da praça
	txt.text = "VALDORIA"
	txt.font_size = 48
	txt.outline_size = 6
	txt.pixel_size = 0.005
	txt.modulate = Color(1, 0.92, 0.75)
	txt.position = Vector3(0.35, 1.95, 0.18)
	add_child(txt)
	_shape(Vector3(0.3, 2.4, 0.3), Vector3(0, 1.2, 0))
	_tag("Estrada para Valdoria", 2.9, Color(0.85, 1.0, 0.7))


func _build_records() -> void:
	var wood := Color(0.4, 0.27, 0.15)
	for x in [-1.1, 1.1]:
		_box(Vector3(0.14, 2.6, 0.14), Vector3(x, 1.3, 0), wood.darkened(0.2))
	_box(Vector3(2.4, 1.5, 0.08), Vector3(0, 1.6, 0), wood)
	_box(Vector3(2.2, 1.3, 0.02), Vector3(0, 1.6, 0.05), Color(0.82, 0.74, 0.55))
	_label = Label3D.new()
	_label.font_size = 30
	_label.outline_size = 0
	_label.pixel_size = 0.004
	_label.modulate = Color(0.18, 0.12, 0.06)
	_label.width = 520
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.position = Vector3(0, 1.6, 0.07)
	add_child(_label)
	_shape(Vector3(2.4, 2.6, 0.3), Vector3(0, 1.3, 0))
	_tag("Recordes da cidade", 2.75, UITheme.GOLD)


func _records_text() -> String:
	var r: Dictionary = Hub.records
	var lines: Array[String] = []
	var h: Dictionary = r.get("horde", {})
	if int(h.get("reached", 0)) > 0:
		lines.append("Horda: rodada %d — %s" % [int(h.reached), ", ".join(h.get("names", []))])
	else:
		lines.append("Horda: ninguém ainda.")
	var c: Dictionary = r.get("city", {})
	if int(c.get("reached", 0)) > 0:
		lines.append("Defesa: %d noite(s) — %s" % [int(c.reached), ", ".join(c.get("names", []))])
	else:
		lines.append("Defesa: ninguém ainda.")
	return "\n\n".join(lines)


# ---------------------------------------------------------------- construção da base
func _building_def() -> Dictionary:
	return Balance.tables.get_table("base_buildings").get("buildings", {}).get(building_id, {})


func _building_name() -> String:
	return str(_building_def().get("name", building_id))


func _build_base_building() -> void:
	# caixa de doações na frente (o ponto em si)
	_glb("chest", Vector3.ZERO, 0.0, 0.9)
	_shape(Vector3(0.9, 0.7, 0.6), Vector3(0, 0.35, 0))
	_label = _tag("", 1.6, Color(1, 0.9, 0.6), 44)
	_building = Node3D.new()
	_building.position = Vector3(0, 0, -BUILDING_BACK)
	add_child(_building)
	var visual := str(_building_def().get("visual", "barracks"))
	var sz: Vector3 = BUILDING_SIZE.get(visual, Vector3(6, 4, 6))
	var body := StaticBody3D.new()   # o prédio bloqueia como parede comum (camada 1)
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = sz
	cs.shape = b
	cs.position.y = sz.y / 2.0
	body.add_child(cs)
	_building.add_child(body)


## Nível 0: canteiro de obra cercado; depois o modelo da Defesa da Cidade (3 visuais para 5 níveis).
func _set_building_level(level: int) -> void:
	if level == _level:
		return
	_level = level
	for c in _building.get_children():
		if not (c is StaticBody3D):
			c.queue_free()
	var visual := str(_building_def().get("visual", "barracks"))
	if level <= 0:
		var sz: Vector3 = BUILDING_SIZE.get(visual, Vector3(6, 4, 6))
		_box(Vector3(sz.x, 0.04, maxf(sz.z, 3.0)), Vector3(0, 0.02, 0), Color(0.42, 0.33, 0.22), _building)
		var hx := sz.x / 2.0 + 0.3
		var hz := maxf(sz.z, 3.0) / 2.0 + 0.3
		var x := -hx + 1.0
		while x <= hx - 0.9:
			for z in [-hz, hz]:
				var f: Node3D = MODELS.fence.instantiate()
				f.position = Vector3(x, 0, z)
				_building.add_child(f)
			x += 2.0
		var zz := -hz + 1.0
		while zz <= hz - 0.9:
			for xx in [-hx, hx]:
				var f: Node3D = MODELS.fence.instantiate()
				f.position = Vector3(xx, 0, zz)
				f.rotation.y = PI / 2
				_building.add_child(f)
			zz += 2.0
		var cr: Node3D = MODELS.crate.instantiate()
		cr.position = Vector3(-0.8, 0, 0.2)
		_building.add_child(cr)
		var br: Node3D = MODELS.barrel.instantiate()
		br.position = Vector3(1.0, 0, -0.4)
		_building.add_child(br)
	else:
		_building.add_child(ColonyVisuals.make(visual, clampi(1 + level / 2, 1, 3)))


func _on_hub_changed() -> void:
	if kind == "records":
		_label.text = _records_text()
		return
	var level := int(Hub.base.get(building_id, {}).get("level", 0))
	_set_building_level(level)
	_label.text = "%s — nível %d" % [_building_name(), level]
