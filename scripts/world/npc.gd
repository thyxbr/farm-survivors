extends StaticBody3D
## NPC da vila. O diálogo vem do roteiro da história (StoryDialogue), conforme o estado das missões;
## o marcador !/? sobre a cabeça vem de StoryRules.

const MODELS := {
	"elder": "res://assets/models/elder.glb",
	"merchant": "res://assets/models/merchant.glb",
	"blacksmith": "res://assets/models/blacksmith.glb",
	"alchemist": "res://assets/models/villager_2.glb",
}

@export var npc_id := "elder"

var npc_name := ""
var model: Node3D
var head: Node3D
var marker: Label3D
var _t := 0.0
var _base_yaw := 0.0


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("npc")
	collision_layer = 8
	collision_mask = 0
	npc_name = StoryDialogue.NAMES[npc_id]
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	model = _make_model()
	add_child(model)
	if ToonLook.enabled():
		ToonLook.apply(model)
	_base_yaw = model.rotation.y
	head = model.find_child("Head", true, false)
	var tag := Label3D.new()
	tag.text = npc_name
	tag.font_size = 40
	tag.outline_size = 8
	tag.pixel_size = 0.005
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position.y = 2.35
	tag.modulate = Color(1, 0.95, 0.8)
	add_child(tag)
	marker = Label3D.new()
	marker.font_size = 110
	marker.outline_size = 14
	marker.pixel_size = 0.006
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.modulate = Color(1, 0.8, 0.2)
	marker.position.y = 2.85
	add_child(marker)
	Game.quests_changed.connect(_update_marker)
	Game.inventory_changed.connect(_update_marker)   # coleta: o "?" aparece quando os itens chegam
	_update_marker()


## Modelo do NPC (as subclasses com modelo próprio sobrescrevem).
func _make_model() -> Node3D:
	return (load(MODELS[npc_id]) as PackedScene).instantiate()


func interact_prompt() -> String:
	return "Falar com %s" % npc_name


func interact(_player: Node) -> void:
	var world := get_tree().current_scene
	if world.has_method("open_dialogue"):
		world.open_dialogue(npc_name, _build_dialogue(), self)


## Cor da plaquinha de nome no diálogo.
func speaker_color() -> Color:
	return StoryDialogue.COLORS.get(npc_id, Color.WHITE)


## Ponto entre os olhos, em coordenadas globais (usado pelo close do diálogo).
func face_point() -> Vector3:
	if head:
		return head.global_transform * Vector3(0, 0.175, 0.03)
	return global_position + Vector3(0, 1.62, 0)


## Direção para onde o rosto está virado (frente do modelo = +Z).
func face_dir() -> Vector3:
	var f := model.global_basis.z
	f.y = 0.0
	return f.normalized()


## Vira o modelo na hora para olhar um ponto (o diálogo pausa o jogo, então não dá para girar aos poucos).
func turn_to(pos: Vector3) -> void:
	var to := pos - global_position
	model.rotation.y = atan2(to.x, to.z) - global_rotation.y


func _process(delta: float) -> void:
	_t += delta
	marker.position.y = 2.85 + sin(_t * 3.0) * 0.08
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var target_yaw := _base_yaw
	if player and player.global_position.distance_to(global_position) < 7.0:
		var to := player.global_position - global_position
		target_yaw = atan2(to.x, to.z) - global_rotation.y
	model.rotation.y = lerp_angle(model.rotation.y, target_yaw, 4.0 * delta)
	if head:
		head.rotation.z = sin(_t * 0.8) * 0.05


func _update_marker() -> void:
	if marker == null:
		return
	var qt: Dictionary = ItemDB.QUESTS
	var counts := {}
	for id in qt:
		if CharRules.quest_type(qt[id]) == "collect":
			counts[qt[id].target] = Game.count_item(str(qt[id].target))
	marker.text = StoryRules.marker(qt, Game.quests, npc_id, counts)
	# "?" (entregar) em verde-dourado, "!" (missão nova) em dourado
	marker.modulate = Color(0.55, 1.0, 0.45) if marker.text == "?" else Color(1, 0.8, 0.2)


# ---------------------------------------------------------------- diálogos
## Páginas do diálogo agora (roteiro em StoryDialogue, conforme o estado das missões).
func _build_dialogue() -> Array:
	return StoryDialogue.build(self)
