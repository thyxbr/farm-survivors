extends Node3D
## Portal da expedição (o mesmo redemoinho das portas de dungeon, PortalVortex). [E] para usar.
##   action "enter": na Guilda (vila); abre o Quadro de Expedições (world.open_expedition_board, a seleção de
##                   expedição: expedition_select_ui.gd), de onde a expedição começa.
##   action "exit":  dentro da expedição; volta à Guilda (o modo da expedição decide se é abandono ou fim).

const RADIUS := 2.4
const COLORS := {"enter": Color(0.4, 1.0, 0.45), "exit": Color(0.6, 0.5, 1.0), "victory": Color(1.0, 0.85, 0.4)}

var action := "enter"
var expedition_id := "pantano"
## Só a cor (o portal que abre quando o chefe cai é dourado).
var look := ""
var npc_id := "expedition_portal"   # lido pelos testes e pela depuração junto com os NPCs


func _ready() -> void:
	add_to_group("interactable")
	if DisplayServer.get_name() == "headless":
		return
	var v := PortalVortex.new()
	v.color = COLORS.get(look if look != "" else action, Color(0.8, 0.8, 0.9))
	v.radius = RADIUS
	v.position.y = RADIUS * 0.82
	add_child(v)


func interact_prompt() -> String:
	if action == "enter":
		return "Expedições da Guilda"
	return "Voltar à Guilda"


func interact(_player: Node) -> void:
	var world := get_tree().current_scene
	if world == null:
		return
	if action == "enter":
		if world.has_method("open_expedition_board"):
			world.open_expedition_board(expedition_id)
	else:
		var ex = world.get("expedition")
		if ex != null:
			ex.request_return()
