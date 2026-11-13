extends StaticBody3D
## NPC da vila. O diálogo é montado conforme o estado das missões.

const MODELS := {
	"elder": preload("res://assets/models/elder.glb"),
	"merchant": preload("res://assets/models/merchant.glb"),
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
	collision_layer = 8
	collision_mask = 0
	npc_name = "Ancião Bram" if npc_id == "elder" else "Mira, a Mercadora"
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	model = MODELS[npc_id].instantiate()
	add_child(model)
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
	_update_marker()


func interact_prompt() -> String:
	return "Falar com %s" % npc_name


func interact(_player: Node) -> void:
	var world := get_tree().current_scene
	if world.has_method("open_dialogue"):
		world.open_dialogue(npc_name, _build_dialogue(), self)


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
	if npc_id != "elder":
		marker.text = ""
		return
	var available := false
	var can_turn_in := false
	for id in ["slimes", "goblins", "goblin_king"]:
		if Game.quest_state(id) == "ready":
			can_turn_in = true
	var next := _next_quest()
	if next != "" and Game.quest_state(next) == "none":
		available = true
	marker.text = "?" if can_turn_in else ("!" if available else "")


func _next_quest() -> String:
	for id in ["slimes", "goblins", "goblin_king"]:
		if Game.quest_state(id) != "done":
			return id
	return ""


# ---------------------------------------------------------------- diálogos
## Cada página: {"text": String, "choices": [{"text": String, "action": Callable}]}
func _build_dialogue() -> Array:
	if npc_id == "merchant":
		return [{
			"text": "Bem-vindo à barraca da Mira! Poções, lâminas e armaduras — tudo pelo preço justo. Também compro o que você trouxer da mata.",
			"choices": [
				{"text": "Ver mercadorias", "action": _open_shop},
				{"text": "Até logo", "action": Callable()},
			]}]

	var pages: Array = []
	var q := _next_quest()
	if q == "":
		pages.append({"text": "Herói de Valdoria! As crianças já cantam canções sobre você. Obrigado por salvar nossa vila."})
		pages.append({"text": "(Você concluiu todas as missões deste protótipo. Sinta-se livre para explorar e caçar!)"})
		return pages

	var st := Game.quest_state(q)
	if st == "ready":
		pages.append_array(_completion_text(q))
		pages.append({"text": "Tome, você mereceu esta recompensa.", "on_show": _complete.bind(q)})
		var nxt := _next_quest_after(q)
		if nxt != "":
			pages.append_array(_offer(nxt))
		else:
			pages.append({"text": "Valdoria está livre do Rei Goblin. Você é um verdadeiro herói!"})
		return pages
	if st == "active":
		var prog: int = Game.quests[q].progress
		var count: int = ItemDB.QUESTS[q].count
		pages.append({"text": _reminder(q) + "  (%d/%d)" % [prog, count]})
		return pages
	# nenhuma missão ativa: oferecer
	if q == "slimes":
		pages.append({"text": "Ah, um viajante! Seja bem-vindo a Valdoria. Sou Bram, o ancião desta vila."})
	pages.append_array(_offer(q))
	return pages


func _accept(q: String) -> void:
	Game.start_quest(q)
	Sfx.play("quest", 0.0)


func _complete(q: String) -> void:
	Game.complete_quest(q)
	Sfx.play("quest", 0.0)


func _open_shop() -> void:
	get_tree().current_scene.open_shop()


func _next_quest_after(q: String) -> String:
	var order := ["slimes", "goblins", "goblin_king"]
	var i := order.find(q)
	return order[i + 1] if i + 1 < order.size() else ""


func _offer(q: String) -> Array:
	var intro := {
		"slimes": "Nossas plantações ao norte foram tomadas por slimes. Os aldeões têm medo de sair de casa...",
		"goblins": "Mas temo que haja algo pior. Batedores goblins montaram acampamento na floresta a leste.",
		"goblin_king": "Os batedores falavam de um rei... O Rei Goblin se esconde nas ruínas antigas, bem ao norte, depois dos campos.",
	}
	var data: Dictionary = ItemDB.QUESTS[q]
	return [
		{"text": intro[q]},
		{"text": "%s\nRecompensa: %d ouro, %d XP." % [data.desc, data.reward_gold, data.reward_xp],
			"choices": [
				{"text": "Aceitar missão", "action": _accept.bind(q)},
				{"text": "Agora não", "action": Callable()},
			]},
	]


func _reminder(q: String) -> String:
	match q:
		"slimes":
			return "Os slimes ainda infestam os campos ao norte da vila."
		"goblins":
			return "O acampamento goblin fica na floresta a leste. Siga a trilha de terra."
		_:
			return "As ruínas ficam no extremo norte. Ele é forte — leve poções da Mira."


func _completion_text(q: String) -> Array:
	match q:
		"slimes":
			return [{"text": "Os campos estão limpos! Os fazendeiros já voltaram ao trabalho. Muito obrigado!"}]
		"goblins":
			return [{"text": "Você dispersou os batedores! Agora eles pensarão duas vezes antes de chegar perto."}]
		_:
			return [{"text": "O Rei Goblin... derrotado?! Eu mal posso acreditar!"}]
