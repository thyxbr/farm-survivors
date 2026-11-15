class_name Alchemist
extends SkinnedNPC
## Pip, a Alquimista: na frente da botica, cochilando em pé (o parado dos aldeões, mais lento). Durante a
## conversa ela "acorda" (o mesmo clipe na velocidade normal). Usa o modelo e os clipes dos aldeões da
## colônia (villager_2.glb + villager_mixamo.res). O marcador !/? e o virar para quem chega vêm do npc.gd.

const LIBRARY := "res://assets/animations/villager_mixamo.res"
## Velocidade do parado quando ninguém fala com ela (sonolenta).
const SLEEPY := 0.55


func _init() -> void:
	npc_id = "alchemist"


func library_path() -> String:
	return LIBRARY


func _ready() -> void:
	super._ready()
	model.scale = Vector3.ONE * 0.9
	if _animate:
		_idle()


func _idle() -> void:
	var c := clip("idle")
	if anim.has_animation(c):
		anim.play(c, BLEND, SLEEPY)


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
