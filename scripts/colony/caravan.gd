class_name ColonyEventProp
extends StaticBody3D
## Figurante de um evento do dia (ColonyEvents), no grupo `interactable`:
##   caravan  — o mercador (merchant.glb) com a carroça; E abre a janela de troca (ColonyData.TRADES);
##   villager — um aldeão perdido (elder.glb); E pede o resgate (só depois que os lobos caem);
##   chest    — o baú esquecido (chest.glb); E abre.
## É só cenário: quem decide é o servidor (Colony.trade / Colony.event_interact). No cliente nasce do
## Lobby.city_event e some quando o evento acaba.

const MODELS := {
	"caravan": preload("res://assets/models/merchant.glb"),
	"villager": preload("res://assets/models/elder.glb"),
	"chest": preload("res://assets/models/chest.glb"),
	"crate": preload("res://assets/models/crate.glb"),
	"barrel": preload("res://assets/models/barrel.glb"),
}

var kind := "caravan"
var colony: Colony
var model: Node3D


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("event_props")
	if kind == "caravan":
		add_to_group("caravan")
	collision_layer = 8
	collision_mask = 0
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45 if kind != "chest" else 0.6
	cap.height = 1.8 if kind != "chest" else 1.2
	col.shape = cap
	col.position.y = cap.height / 2.0
	add_child(col)
	if DisplayServer.get_name() == "headless":
		return
	model = MODELS[kind].instantiate()
	model.rotation.y = randf() * TAU
	add_child(model)
	if kind == "caravan":
		# a "carroça": caixas e barril ao lado do mercador
		for p in [["crate", Vector3(1.6, 0, 0.4), 0.3], ["crate", Vector3(1.9, 0, -0.8), -0.2], ["barrel", Vector3(-1.4, 0, 0.6), 0.0]]:
			var m: Node3D = MODELS[p[0]].instantiate()
			m.position = p[1]
			m.rotation.y = p[2]
			add_child(m)
	var tag := Label3D.new()
	tag.text = {"caravan": "Caravana", "villager": "Aldeão perdido", "chest": ""}[kind]
	tag.font_size = 40
	tag.outline_size = 8
	tag.pixel_size = 0.005
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position.y = 2.35
	tag.modulate = Color(1, 0.95, 0.8)
	add_child(tag)


func interact_prompt() -> String:
	match kind:
		"caravan":
			return "Negociar com a caravana"
		"villager":
			return "Resgatar os aldeões"
	return "Abrir o baú"


func interact(_player: Node) -> void:
	if colony == null:
		return
	if kind == "caravan":
		if colony.world and colony.world.has_method("open_trade_menu"):
			colony.world.open_trade_menu()
		return
	var err := colony.event_interact()
	if err != "":
		Game.notify.emit(err, Color(1, 0.7, 0.5))
