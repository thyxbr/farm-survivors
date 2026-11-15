class_name Rival
extends KnightNPC
## Kael, a Lâmina Carmesim: o rival do herói, no portão leste da vila (e, no Arco 2, no Pico das Cinzas,
## como "kael_pico"). Sobreveste da guarda, sabre e luvas, sem elmo para o rosto aparecer no close; ensaia
## a "pose heroica" sozinho e faz a pose ao abrir o diálogo.

const LOOK := {"weapon": "steel_saber", "armor": "guard_surcoat", "hands": "leather_gloves",
	"feet": "leather_boots", "head": ""}


func _init() -> void:
	npc_id = "rival"
	look = LOOK
	model_scale = 1.02
	gesture = "comemorar"
	show_off = true
