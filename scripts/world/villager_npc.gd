class_name VillagerNPC
extends SkinnedNPC
## NPC com o modelo dos aldeões da colônia (villager_<look>.glb + villager_mixamo.res): Pip, Lina, Dona
## Zélia, Seu Tonico, o cocheiro Beto e o Tico. Fica no parado (idle_speed < 1 = sonolento) e, durante a
## conversa, toca o parado na velocidade normal.

const LIBRARY := "res://assets/animations/villager_mixamo.res"
const LOOKS := ["res://assets/models/villager_1.glb", "res://assets/models/villager_2.glb",
	"res://assets/models/villager_3.glb"]

## Roupa (1 a 3), escala do modelo e velocidade do parado fora da conversa.
var look_index := 1
var model_scale := 1.0
var idle_speed := 1.0


func _make_model() -> Node3D:
	return (load(LOOKS[clampi(look_index, 1, LOOKS.size()) - 1]) as PackedScene).instantiate()


func library_path() -> String:
	return LIBRARY


func _ready() -> void:
	super._ready()
	model.scale = Vector3.ONE * model_scale
	if _animate:
		_idle()


func _idle() -> void:
	var c := clip("idle")
	if anim.has_animation(c):
		anim.play(c, BLEND, idle_speed)


func _on_dialogue_opened() -> void:
	if not _animate:
		return
	var c := clip("idle")
	if anim.has_animation(c):
		anim.play(c, BLEND, 1.0)


func _process(delta: float) -> void:
	if not get_tree().paused:
		super._process(delta)
	if _dialogue != null and not dialogue_open():
		_end_dialogue()
		_idle()
