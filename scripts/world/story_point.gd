class_name StoryPoint
extends StaticBody3D
## Objeto da história que se examina com E (o bilhete do Rei Goblin no acampamento). Fala pelo mesmo roteiro
## dos NPCs (StoryDialogue, npc_id = id do objeto), sem close de câmera. Enquanto a missão que pede para
## examiná-lo está ativa, brilha e mostra o "?" por cima.

@export var npc_id := "camp_note"

var npc_name := ""
var marker: Label3D
var _glow: OmniLight3D
var _paper: MeshInstance3D
var _paper_mat: StandardMaterial3D
var _t := 0.0


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("npc")
	collision_layer = 8
	collision_mask = 0
	npc_name = StoryDialogue.NAMES.get(npc_id, npc_id)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.3, 0.5)
	col.shape = box
	add_child(col)
	# o bilhete: um papel amassado (caixa fina, um pouco torta) com uma faca de manteiga espetada
	_paper = MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.32, 0.02, 0.24)
	_paper.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.93, 0.88, 0.72)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.5)
	mat.emission_energy_multiplier = 0.0
	_paper.material_override = mat
	_paper_mat = mat
	_paper.rotation = Vector3(0.12, 0.5, -0.08)
	add_child(_paper)
	var knife := MeshInstance3D.new()
	var km := BoxMesh.new()
	km.size = Vector3(0.03, 0.18, 0.012)
	knife.mesh = km
	var kmat := StandardMaterial3D.new()
	kmat.albedo_color = Color(0.75, 0.76, 0.8)
	kmat.metallic = 0.8
	knife.material_override = kmat
	knife.position = Vector3(0.04, 0.08, 0.02)
	knife.rotation.z = 0.25
	add_child(knife)
	if DisplayServer.get_name() != "headless":
		_glow = OmniLight3D.new()
		_glow.light_color = Color(1.0, 0.85, 0.5)
		_glow.omni_range = 2.5
		_glow.light_energy = 0.0
		_glow.position.y = 0.4
		add_child(_glow)
	marker = Label3D.new()
	marker.font_size = 110
	marker.outline_size = 14
	marker.pixel_size = 0.006
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.modulate = Color(0.55, 1.0, 0.45)
	marker.position.y = 1.2
	add_child(marker)
	Game.quests_changed.connect(_update_marker)
	_update_marker()


func interact_prompt() -> String:
	return "Examinar %s" % npc_name.to_lower()


func interact(_player: Node) -> void:
	var world := get_tree().current_scene
	if world.has_method("open_dialogue") and world.get("modal") == null:
		world.open_dialogue(npc_name, StoryDialogue.build(self), null)


func _update_marker() -> void:
	marker.text = StoryRules.marker(ItemDB.QUESTS, Game.quests, npc_id, {})
	var lit := marker.text != ""
	_paper_mat.emission_energy_multiplier = 1.2 if lit else 0.0
	if _glow:
		_glow.light_energy = 1.2 if lit else 0.0


func _process(delta: float) -> void:
	_t += delta
	marker.position.y = 1.2 + sin(_t * 3.0) * 0.08
