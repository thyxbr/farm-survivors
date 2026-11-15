class_name Santa
extends Elder
## Papai Noel na vila, ao lado da árvore de Natal grande e do trenó. Mesmo corpo, esqueleto e clipes do Bram
## (santa.glb sai de build_elder(santa=True) em tools/blender/characters.py), com a bengala doce presa à mão.
##
## Dá os quatro eventos de Natal (quests.json, "event": "natal"), fora da cadeia do Bram e em qualquer ordem:
## - Presentes Espalhados (collect): 8 presentes caídos pelo vale (VillageLayout.GIFTS);
## - Ladrões de Natal (kill, "goblin*"): 6 goblins de qualquer tipo;
## - A Ceia do Noel (deliver): levar 1 Torta de Abóbora e 2 Pães Rústicos;
## - Entregas na Vila (visit): deixar presentes nas 6 casas marcadas (VillageLayout.DELIVERY).
## O marcador mostra "!" quando há evento novo e "?" quando há um pronto para entregar.

const EVENTS := ["natal_presentes", "natal_ladroes", "natal_ceia", "natal_entregas"]
## Rótulos curtos dos botões do diálogo (cabem cinco na linha).
const SHORT := {"natal_presentes": "Presentes", "natal_ladroes": "Ladrões", "natal_ceia": "Ceia",
	"natal_entregas": "Entregas"}

## Evento escolhido no menu: a próxima conversa mostra só ele (oferta ou lembrete).
var _focus := ""


func _init() -> void:
	npc_id = "santa"


func _update_marker() -> void:
	if marker == null:
		return
	var turn_in := false
	var fresh := false
	for id in EVENTS:
		if _can_turn_in(id):
			turn_in = true
		elif Game.quest_state(id) == "none":
			fresh = true
	marker.text = "?" if turn_in else ("!" if fresh else "")
	marker.modulate = Color(1, 0.3, 0.25) if turn_in else Color(1, 0.85, 0.3)


## Pronto para concluir: missão "ready" ou entrega ativa com os itens na mochila.
func _can_turn_in(id: String) -> bool:
	var st := Game.quest_state(id)
	if st == "ready":
		return true
	return st == "active" and ItemDB.QUESTS[id].has("deliver") and _has_delivery(id)


func _has_delivery(id: String) -> bool:
	var need: Dictionary = ItemDB.QUESTS[id].get("deliver", {})
	for item in need:
		if Game.count_item(item) < int(need[item]):
			return false
	return true


func _process(delta: float) -> void:
	super._process(delta)
	# a mochila muda sem quests_changed (cozinhar a torta): confere o "?" da ceia de vez em quando
	if Engine.get_process_frames() % 30 == 0:
		_update_marker()


# ---------------------------------------------------------------- diálogo
func _build_dialogue() -> Array:
	if _focus != "":
		var f := _focus
		_focus = ""
		return _event_pages(f)
	for id in EVENTS:
		if _can_turn_in(id):
			return _turn_in_pages(id)
	var open: Array = EVENTS.filter(func(id) -> bool: return Game.quest_state(id) != "done")
	if open.is_empty():
		return [{"text": "Ho, ho, ho! Graças a você o Natal de Valdoria vai ser o mais bonito de todos."},
			{"text": "O trenó está carregado e as renas descansadas. Feliz Natal, herói! Volte sempre que quiser conversar."}]
	var choices: Array = []
	for id in open:
		var label: String = SHORT[id]
		if Game.quest_state(id) == "active":
			label += " ✓"
		choices.append({"text": label, "action": _pick.bind(id)})
	choices.append({"text": "Até logo", "action": Callable()})
	var hello := "Ho, ho, ho! Feliz Natal! O velho Noel parou o trenó em Valdoria, mas está precisando de uma ajudinha."
	if Game.quest_state(EVENTS[0]) != "none" or Game.quest_state(EVENTS[1]) != "none":
		hello = "Ho, ho, ho! Que bom te ver de novo. Ainda há muito a fazer antes da grande noite."
	return [{"text": hello + "\nEm que você pode ajudar?", "choices": choices}]


## Escolheu um evento no menu: reabre a conversa só com ele (o diálogo de escolhas já fechou).
func _pick(id: String) -> void:
	_focus = id
	var w := get_tree().current_scene
	if w != null and w.get("player") != null:
		interact.call_deferred(w.player)


func _event_pages(id: String) -> Array:
	var q: Dictionary = ItemDB.QUESTS[id]
	if Game.quest_state(id) == "active":
		return [{"text": _reminder(id)}]
	return [
		{"text": _intro(id)},
		{"text": "%s\nRecompensa: %d ouro, %d XP e um presente do Noel." % [q.desc, int(q.reward_gold), int(q.reward_xp)],
			"choices": [
				{"text": "Aceitar", "action": _accept.bind(id)},
				{"text": "Agora não", "action": Callable()},
			]},
	]


func _turn_in_pages(id: String) -> Array:
	var thanks := {
		"natal_presentes": "Todos os presentes de volta no saco! Nenhuma criança vai ficar sem o seu. Obrigado!",
		"natal_ladroes": "As meias estão a salvo! Aqueles goblins vão ganhar carvão este ano, ho, ho!",
		"natal_ceia": "Hmm, que cheiro! Torta de abóbora e pão quentinho... a Horta de Valdoria é a melhor do reino!",
		"natal_entregas": "Todas as casas receberam o presente. Ouvi daqui as crianças comemorando!",
	}
	return [{"text": thanks[id]}, {"text": "Tome, isto é para você. Feliz Natal!", "on_show": _complete.bind(id)}]


func _intro(id: String) -> String:
	match id:
		"natal_presentes":
			return "Uma das renas se assustou com um slime e o saco abriu no meio do voo. Os presentes caíram por todo o vale!"
		"natal_ladroes":
			return "E tem mais: goblins andam rondando as janelas e roubando as meias penduradas. Que falta de espírito natalino!"
		"natal_ceia":
			return "Uma viagem dessas pede uma boa ceia. Disseram que a Horta de Valdoria tem as melhores abóboras do reino..."
	return "Algumas famílias pediram para receber os presentes antes da noite de Natal. Marquei as portas com uma estrela."


func _reminder(id: String) -> String:
	var q: Dictionary = ItemDB.QUESTS[id]
	var prog := int(Game.quests[id].get("progress", 0)) if Game.quests.has(id) else 0
	match id:
		"natal_presentes":
			return "Os presentes brilham no chão: procure nos campos, perto das ruínas, da floresta e do ninho dos slimes. (%d/%d)" % [prog, int(q.count)]
		"natal_ladroes":
			return "Os goblins ficam no acampamento a leste e nas ruínas ao norte. (%d/%d)" % [prog, int(q.count)]
		"natal_ceia":
			var need: Dictionary = q.deliver
			var parts: Array[String] = []
			for item in need:
				parts.append("%s %d/%d" % [ItemDB.ITEMS[item].name, mini(Game.count_item(item), int(need[item])), int(need[item])])
			return "Plante e cozinhe no Caldeirão da Horta, pelo portão sul. Ainda faltam: %s." % ", ".join(parts)
	return "As casas com a estrela dourada na porta esperam o presente. (%d/%d)" % [prog, int(q.count)]
