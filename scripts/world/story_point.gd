class_name StoryPoint
extends StaticBody3D
## Objeto da história que se examina com E: o bilhete do Rei Goblin no acampamento ("camp_note"), o diário do
## Lich na Mina ("diario"), o gato da Dona Zélia no pomar ("gato") e o Quadro de Contratos da guilda
## ("board", sem visual próprio: fica na frente do quadro de avisos). Fala pelo mesmo roteiro dos NPCs
## (StoryDialogue, npc_id = id do objeto), sem close de câmera. Mostra o marcador da história por cima e,
## quando há algo a fazer nele, brilha.

const PROMPTS := {"board": "Ver contratos", "gato": "Chamar o gato", "diario": "Ler o diário",
	"camp_note": "Examinar bilhete"}

@export var npc_id := "camp_note"

var npc_name := ""
var marker: Label3D
var marker_h := 1.2
var _glow: OmniLight3D
var _t := 0.0


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("npc")
	collision_layer = 8
	collision_mask = 0
	npc_name = StoryDialogue.NAMES.get(npc_id, npc_id)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.5, 0.6)
	col.shape = box
	col.position.y = 0.25
	add_child(col)
	match npc_id:
		"camp_note":
			_paper()
		"diario":
			_book()
		"gato":
			_cat()
			marker_h = 1.3
		"board":
			marker_h = 3.0
	if DisplayServer.get_name() != "headless":
		_glow = OmniLight3D.new()
		_glow.light_color = Color(1.0, 0.85, 0.5)
		_glow.omni_range = 2.5
		_glow.light_energy = 0.0
		_glow.position.y = 0.5
		add_child(_glow)
	marker = Label3D.new()
	marker.font_size = 110
	marker.outline_size = 14
	marker.pixel_size = 0.006
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.position.y = marker_h
	add_child(marker)
	Game.quests_changed.connect(_update_marker)
	Game.inventory_changed.connect(_queue_marker)
	_update_marker()


func interact_prompt() -> String:
	return PROMPTS.get(npc_id, "Examinar")


func interact(_player: Node) -> void:
	var world := get_tree().current_scene
	if world.has_method("open_dialogue") and world.get("modal") == null:
		world.open_dialogue(npc_name, StoryDialogue.build(self), null)


var _marker_queued := false


## Mochila mudou: o marcador é refeito uma vez no fim do quadro (cada abate no solo muda a mochila duas vezes).
func _queue_marker() -> void:
	if not _marker_queued:
		_marker_queued = true
		_flush_marker.call_deferred()


func _flush_marker() -> void:
	_marker_queued = false
	_update_marker()


func _update_marker() -> void:
	var here := StoryDialogue.present(npc_id)
	visible = here
	collision_layer = 8 if here else 0
	for g in ["interactable", "npc"]:
		if here and not is_in_group(g):
			add_to_group(g)
		elif not here and is_in_group(g):
			remove_from_group(g)
	var m := StoryRules.marker(ItemDB.QUESTS, Game.quests, npc_id, {}, Game.access_rank())
	NPC_SCRIPT.set_marker(marker, m)
	if _glow:
		_glow.light_energy = 1.2 if m != "" and npc_id != "board" else 0.0


const NPC_SCRIPT := preload("res://scripts/world/npc.gd")


func _process(delta: float) -> void:
	_t += delta
	marker.position.y = marker_h + sin(_t * 3.0) * 0.08


# ---------------------------------------------------------------- visuais
func _mesh(m: Mesh, c: Color, pos: Vector3, rot := Vector3.ZERO, metal := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.metallic = metal
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
	return mi


func _box(size: Vector3, c: Color, pos: Vector3, rot := Vector3.ZERO, metal := 0.0) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mesh(b, c, pos, rot, metal)


func _sphere(r: float, c: Color, pos: Vector3, squash := Vector3.ONE) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	var mi := _mesh(s, c, pos)
	mi.scale = squash
	return mi


## O bilhete: papel amassado com uma faca de manteiga espetada.
func _paper() -> void:
	_box(Vector3(0.32, 0.02, 0.24), Color(0.93, 0.88, 0.72), Vector3.ZERO, Vector3(0.12, 0.5, -0.08))
	_box(Vector3(0.03, 0.18, 0.012), Color(0.75, 0.76, 0.8), Vector3(0.04, 0.08, 0.02), Vector3(0, 0, 0.25), 0.8)


## O diário do Lich: livro grosso de capa roxa num pedestal de pedra.
func _book() -> void:
	_box(Vector3(0.6, 0.8, 0.6), Color(0.35, 0.33, 0.36), Vector3(0, 0.4, 0))
	_box(Vector3(0.42, 0.1, 0.32), Color(0.3, 0.12, 0.38), Vector3(0, 0.85, 0), Vector3(0, 0.3, 0))
	_box(Vector3(0.38, 0.08, 0.3), Color(0.9, 0.86, 0.72), Vector3(0.012, 0.85, 0), Vector3(0, 0.3, 0))
	marker_h = 1.7


## O Sr. Bigodes: gato laranja gordo, sentado, com orelhas e rabo.
func _cat() -> void:
	var fur := Color(0.95, 0.55, 0.18)
	_sphere(0.22, fur, Vector3(0, 0.2, 0), Vector3(1.0, 0.95, 1.2))
	_sphere(0.15, fur, Vector3(0, 0.46, 0.12))
	for x in [-0.08, 0.08]:
		_box(Vector3(0.07, 0.1, 0.03), fur.darkened(0.15), Vector3(x, 0.6, 0.12), Vector3(0, 0, 0.3 * signf(x)))
		_sphere(0.025, Color(0.1, 0.12, 0.08), Vector3(x * 0.7, 0.49, 0.26))
	_box(Vector3(0.05, 0.05, 0.38), fur.darkened(0.2), Vector3(0.12, 0.12, -0.3), Vector3(0.6, 0.4, 0))
