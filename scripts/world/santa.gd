class_name Santa
extends Elder
## Papai Noel na vila, ao lado da árvore de Natal grande e do trenó. Mesmo corpo, esqueleto e clipes do Bram
## (santa.glb sai de build_elder(santa=True) em tools/blender/characters.py), com a bengala doce presa à mão
## no lugar do cajado.
##
## Fala pelo roteiro em dados como os outros NPCs (StoryDialogue, npc_id "santa"): os quatro eventos de Natal
## são missões secundárias de quests.json ("event": "natal", "giver_id": "santa"), fora da cadeia da história:
## - natal_presentes (gather): 8 presentes caídos pelo vale (VillageLayout.GIFTS, ChristmasEventPoint);
## - natal_ladroes (kill, "targets"): 6 goblins de qualquer tipo;
## - natal_ceia (deliver): levar 2 Pães Rústicos e 1 Ensopado de Cenoura;
## - natal_entregas (visit): deixar presentes nas 6 portas marcadas (VillageLayout.deliveries(), as casas com "delivery" no vale.tscn).
## O marcador ("+" evento novo, "?" pronto para entregar) vem de StoryRules, como nos outros NPCs.

const EVENTS := ["natal_presentes", "natal_ladroes", "natal_ceia", "natal_entregas"]


func _init() -> void:
	npc_id = "santa"
