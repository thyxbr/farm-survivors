class_name Alchemist
extends VillagerNPC
## Pip, a Alquimista: na frente da botica, cochilando em pé (o parado dos aldeões, mais lento); durante a
## conversa ela "acorda".


func _init() -> void:
	npc_id = "alchemist"
	look_index = 2
	model_scale = 0.9
	idle_speed = 0.55
