extends StaticBody3D
## Um ponto que veio da antiga praça da cidade e hoje fica nas ruas da vila (MapEntity "hub_point" no vale.tscn), com que o
## jogador interage ([E]): o Mestre Orin (passivas compradas com Ecos) ou o quadro de recordes da Horda.
## Monta o próprio visual pelo `kind` e abre o painel pela cena (world.open_point_panel).

const MODELS := {
	"elder": preload("res://assets/models/elder.glb"),
	"notice_board": preload("res://assets/models/notice_board.glb"),
}
const KINDS := ["passive_master", "records"]

@export var kind: String = "passive_master"

var model: Node3D
var _label: Label3D
var _base_yaw := 0.0
var _t := 0.0


func _ready() -> void:
	add_to_group("interactable")
	collision_layer = 8
	collision_mask = 0
	if kind == "passive_master":
		_build_npc()
	else:
		_build_records()
	set_process(kind == "passive_master")   # só o mestre vira para o jogador
	if kind == "records":
		Hub.changed.connect(_on_hub_changed)
		_on_hub_changed()


func interact_prompt() -> String:
	return "Falar com Mestre Orin (passivas)" if kind == "passive_master" else "Ler o quadro de recordes"


func interact(_player: Node) -> void:
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


func _build_npc() -> void:
	model = _glb("elder", Vector3.ZERO)
	if ToonLook.enabled():
		ToonLook.apply(model)
	# modelo com esqueleto: parado no idle (sem isso, pose T); o cajado do Orin preso à mão
	SkinnedNPC.pose_model(model, {"Staff": "LeftHand"}, Elder.MIXAMO_LIB, "idle")
	_base_yaw = model.rotation.y
	_shape(Vector3(0.4, 1.8, 0), Vector3(0, 0.9, 0), true)
	_tag("Mestre Orin, guardião dos Ecos", 2.35, Color(1, 0.95, 0.8))
	# brilho azulado dos Ecos em volta do mestre
	var l := OmniLight3D.new()
	l.light_color = Color(0.55, 0.75, 1.0)
	l.light_energy = 1.2
	l.omni_range = 4.5
	l.position = Vector3(0, 1.6, 0.4)
	add_child(l)


func _build_records() -> void:
	_glb("notice_board", Vector3.ZERO)
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
	_tag("Recordes da Horda", 2.75, UITheme.GOLD)


func _records_text() -> String:
	var r: Dictionary = Hub.records
	var lines: Array[String] = []
	var h: Dictionary = r.get("horde", {})
	if int(h.get("reached", 0)) > 0:
		lines.append("Horda: rodada %d — %s" % [int(h.reached), ", ".join(h.get("names", []))])
	else:
		lines.append("Horda: ninguém ainda.")
	return "\n\n".join(lines)


func _on_hub_changed() -> void:
	_label.text = _records_text()
