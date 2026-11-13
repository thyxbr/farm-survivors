extends Node3D
## Baú de recompensa da cidade em grupo: aparece perto da prefeitura no amanhecer das noites de chefe.
## Cada jogador que segurou a noite tem o próprio saque lá dentro (o servidor sorteia e guarda);
## E abre o baú e mostra a janela do saque. Um facho de luz na cor da melhor raridade marca onde ele está
## enquanto ainda houver algo para você. Os outros veem a tampa abrir quando alguém mexe nele.

const MODEL := preload("res://assets/models/chest.glb")
const OPEN_ANGLE := -1.25
const NONE_COLOR := Color(0.8, 0.78, 0.7)

var world: Node
var chest_id := 0
var night := 0
## Melhor raridade do seu saque ("" = nada para você neste baú).
var rarity := ""
## Itens que ainda são seus aqui dentro.
var count := 0
## Já teve algo para você (depois de esvaziar o baú fica aberto e apagado).
var had_loot := false

var _lid_pivot: Node3D
var _lid := 0.0
var _lid_target := 0.0
var _close_t := 0.0
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _light: OmniLight3D
var _label: Label3D
var _t := 0.0
var _gone := false


func _ready() -> void:
	had_loot = count > 0
	var m: Node3D = MODEL.instantiate()
	m.scale = Vector3.ONE * 1.35
	add_child(m)
	# a tampa gira na dobradiça de trás (o modelo tem a tampa como peça própria)
	var lid := m.get_node_or_null("ChestLid") as Node3D
	if lid:
		_lid_pivot = Node3D.new()
		_lid_pivot.position = Vector3(0, 0.5, -0.3)
		m.add_child(_lid_pivot)
		lid.reparent(_lid_pivot, true)
	var c := _color()
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mat.albedo_color = Color(c.r, c.g, c.b, 0.32)
	_beam = MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 0.12
	cy.bottom_radius = 0.3
	cy.height = 9.0
	cy.cap_top = false
	cy.cap_bottom = false
	_beam.mesh = cy
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.position.y = 5.6   # começa no topo do baú (não vaza pela caixa)
	add_child(_beam)
	_light = OmniLight3D.new()
	_light.light_color = c
	_light.light_energy = 1.6
	_light.omni_range = 4.5
	_light.position.y = 1.1
	add_child(_light)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = true
	_label.pixel_size = 0.0011
	_label.font_size = 24
	_label.outline_size = 8
	_label.outline_modulate = Color(0, 0, 0, 0.85)
	_label.position.y = 1.7
	add_child(_label)
	add_to_group("interactable")
	add_to_group("city_chests")
	_refresh()
	# chega quicando do céu
	scale = Vector3.ONE * 0.01
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		FX.burst(global_position + Vector3.UP * 0.6, c, 24, 4.0, 0.12, 0.8)
		FX.ring(global_position + Vector3.UP * 0.05, c, 2.2, 0.6)
	Sfx.play_at("quest", global_position, 0.05, -4.0)


func _color() -> Color:
	if rarity != "" and ItemDB.RARITY.has(rarity):
		return ItemDB.RARITY[rarity].color
	return NONE_COLOR


func _refresh() -> void:
	var c := _color()
	var mine := count > 0
	_beam.visible = mine
	_light.visible = mine
	_light.light_color = c
	_beam_mat.albedo_color = Color(c.r, c.g, c.b, 0.32)
	if mine:
		_label.text = "Baú da noite %d" % night
		_label.modulate = c.lerp(Color.WHITE, 0.3)
	elif had_loot:
		_label.text = "Baú vazio"
		_label.modulate = Color(0.75, 0.72, 0.65)
		_lid_target = OPEN_ANGLE * 0.8
	else:
		_label.text = "Baú da noite %d" % night
		_label.modulate = NONE_COLOR
	_label.visible = true


func interact_prompt() -> String:
	if count > 0:
		return "Abrir o baú da noite %d" % night
	if had_loot:
		return "Baú vazio"
	return "Baú da noite %d (de quem segurou a noite)" % night


func interact(_player: Node) -> void:
	if _gone:
		return
	if count <= 0:
		if had_loot:
			Game.notify.emit("Você já pegou tudo deste baú.", Color(0.85, 0.82, 0.7))
		else:
			Game.notify.emit("Você não estava na noite %d: o saque deste baú é de quem a segurou." % night, Color(1, 0.8, 0.5))
		return
	open_lid()
	if world and world.has_method("open_chest"):
		world.open_chest(self)


## Tampa abrindo (o próprio jogador abriu ou viu outro abrir). `hold` = segundos até fechar sozinha (0 = fica).
func open_lid(hold := 0.0) -> void:
	if _lid_target != OPEN_ANGLE:
		Sfx.play_at("bloop", global_position, 0.1, -6.0)
		if DisplayServer.get_name() != "headless":
			FX.burst(global_position + Vector3.UP * 0.8, _color() if count > 0 else Color(1, 0.85, 0.4), 14, 2.5, 0.08, 0.6, -2.0)
	_lid_target = OPEN_ANGLE
	_close_t = hold


func close_lid() -> void:
	_close_t = 0.0
	_lid_target = 0.0 if count > 0 or not had_loot else OPEN_ANGLE * 0.8


func is_lid_open() -> bool:
	return _lid < OPEN_ANGLE * 0.5


## Outro jogador abriu o baú: a tampa abre e fecha, e o nome dele aparece por um instante.
func opened_by(who: String) -> void:
	if _close_t <= 0.0 and is_lid_open():
		return   # você está com ele aberto
	open_lid(2.2)
	_label.text = "%s abriu" % who
	_label.modulate = Color(1, 0.92, 0.7)
	get_tree().create_timer(2.2).timeout.connect(func() -> void:
		if is_instance_valid(self) and not _gone:
			_refresh())


## O servidor mandou o que sobrou do seu saque.
func set_remaining(n: int, best: String) -> void:
	count = n
	if n > 0:
		had_loot = true
	if best != "":
		rarity = best
	_refresh()


func vanish() -> void:
	if _gone:
		return
	_gone = true
	remove_from_group("interactable")
	remove_from_group("city_chests")
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 0.01, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


func _process(delta: float) -> void:
	_t += delta
	if _close_t > 0.0:
		_close_t -= delta
		if _close_t <= 0.0:
			close_lid()
	_lid = move_toward(_lid, _lid_target, delta * 5.0)
	if _lid_pivot:
		_lid_pivot.rotation.x = _lid
	if _beam.visible:
		var pulse := 0.26 + 0.08 * sin(_t * 3.0)
		_beam_mat.albedo_color.a = pulse
		_light.light_energy = 1.3 + 0.4 * sin(_t * 3.0)
