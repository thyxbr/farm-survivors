class_name ChristmasEventPoint
extends StaticBody3D
## Ponto de um evento de Natal do Papai Noel com que o jogador interage ([E]):
## - "gift": um presente caído no vale (Presentes Espalhados), embrulhado e com um brilho que pulsa;
## - "door": a porta de uma casa da vila (Entregas na Vila), com uma estrela dourada girando em cima.
## Só aparece (e só é interagível) com a missão ativa e o ponto ainda não feito; cada jogador vê os seus
## (os pontos feitos ficam em quests[id].got, no servidor ou no save solo). Interagir pede Game.quest_mark.

const QUEST := {"gift": "natal_presentes", "door": "natal_entregas"}

@export var kind := "gift"
@export var index := 0

var quest := ""
var _visual: Node3D
var _shape: CollisionShape3D
var _light: OmniLight3D
var _t := 0.0


func _ready() -> void:
	quest = QUEST[kind]
	collision_layer = 0
	collision_mask = 0
	_t = index * 0.7
	_visual = Node3D.new()
	add_child(_visual)
	_shape = CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.5
	sh.height = 1.2
	_shape.shape = sh
	_shape.position.y = 0.6
	add_child(_shape)
	if kind == "gift":
		var rng := RandomNumberGenerator.new()
		rng.seed = 900 + index
		var wraps := [ChristmasDecor.RED, ChristmasDecor.GREEN, Color(0.2, 0.35, 0.8), Color(0.85, 0.75, 0.2)]
		ChristmasDecor.gift(_visual, Vector3(0, 0, 0), Vector3(0.55, 0.42, 0.55), wraps[index % wraps.size()],
			ChristmasDecor.GOLD if index % 2 == 0 else Color(0.95, 0.95, 0.95), rng.randf() * TAU)
		ChristmasDecor.gift(_visual, Vector3(0.45, 0, 0.25), Vector3(0.3, 0.28, 0.3), wraps[(index + 1) % wraps.size()],
			ChristmasDecor.GOLD, rng.randf() * TAU)
	else:
		var star := MeshInstance3D.new()
		star.mesh = ChristmasDecor._star_mesh(0.28, 0.12, 0.08)
		star.material_override = ChristmasDecor.mat(ChristmasDecor.GOLD, 0.6, 2.5)
		star.position.y = 2.75
		_visual.add_child(star)
		var tag := Label3D.new()
		tag.text = "Entrega do Noel"
		tag.font_size = 34
		tag.outline_size = 8
		tag.pixel_size = 0.005
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.modulate = Color(1, 0.9, 0.55)
		tag.position.y = 3.25
		_visual.add_child(tag)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.85, 0.45)
	_light.omni_range = 3.5
	_light.light_energy = 1.2
	_light.shadow_enabled = false
	_light.position.y = 1.0 if kind == "gift" else 2.6
	add_child(_light)
	Game.quests_changed.connect(_refresh)
	_refresh()


## Visível e interagível só com a missão ativa e este ponto ainda não feito.
func active() -> bool:
	return Game.quest_state(quest) == "active" and not index in Game.quest_got(quest)


func _refresh() -> void:
	var on := active()
	visible = on
	set_process(on)
	collision_layer = 8 if on else 0
	if on and not is_in_group("interactable"):
		add_to_group("interactable")
	elif not on and is_in_group("interactable"):
		remove_from_group("interactable")


func interact_prompt() -> String:
	return "Pegar o presente" if kind == "gift" else "Deixar o presente do Noel"


func interact(_player: Node) -> void:
	if not active():
		return
	Game.quest_mark(quest, index)
	Sfx.play("pickup", 0.0)
	# some na hora (a resposta do servidor confirma pelo quests_changed)
	visible = false
	collision_layer = 0
	remove_from_group("interactable")
	set_process(false)


func _process(delta: float) -> void:
	_t += delta
	if kind == "gift":
		_visual.position.y = 0.06 + sin(_t * 2.2) * 0.06
		_visual.rotation.y += delta * 0.6
	else:
		_visual.rotation.y += delta * 1.5
	_light.light_energy = 1.0 + 0.5 * sin(_t * 3.0)
