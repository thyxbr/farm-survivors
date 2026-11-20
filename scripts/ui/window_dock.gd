class_name WindowDock
extends Node
## Janelas laterais abertas ao mesmo tempo, sem sobrepor (estilo dos MMOs de vista de cima): o inventário
## encosta na direita, o resto (herói, loja, bancadas, horta, social...) na esquerda. Cada lado tem uma
## janela; abrir outra no mesmo lado troca a anterior. Estação que mexe com a mochila (`wants_inventory`)
## abre o inventário junto, e ele fecha com ela se foi aberto por ela.
## Também cuida dos atalhos (I, C, K, J, L, P, O) enquanto alguma janela está aberta: o mundo fica pausado
## e não recebe tecla. Quem abre e fecha de verdade é o mundo (`world.gd`, `_open_modal`).

## Ações de entrada que abrem uma janela -> [lado, aba do menu do herói ou do social].
const HOTKEYS := {"inventory": ["right", 0], "character": ["left", 1], "talents": ["left", 2],
	"quest_log": ["left", 3], "professions": ["left", 4], "party": ["left", -1], "friends": ["left", -2]}

var world: Node
var windows := {}            # "left"/"right" -> Control
var _companion := {}         # janela aberta junto -> janela que a abriu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_open() -> bool:
	_prune()
	return not windows.is_empty()


func has(c: Control) -> bool:
	_prune()
	return c != null and windows.values().has(c)


func at(side: String) -> Control:
	_prune()
	return windows.get(side)


## Janela liberada sem passar por `forget` (queue_free direto, nos testes) sai do registro.
func _prune() -> void:
	for s in windows.keys():
		var c = windows[s]
		if not is_instance_valid(c) or c.is_queued_for_deletion():
			windows.erase(s)


## Primeira janela aberta que satisfaz `pred` (ou null).
func find(pred: Callable) -> Control:
	for c in windows.values():
		if is_instance_valid(c) and pred.call(c):
			return c
	return null


## Põe `c` no `side`, fechando quem estava lá. `opener` = a janela que pediu esta (companheira).
func put(c: Control, side: String, opener: Control = null) -> void:
	var old: Control = windows.get(side)
	if old != null and is_instance_valid(old):
		close_window(old)
	windows[side] = c
	if opener != null:
		_companion[c] = opener


## Tira `c` do registro e fecha a companheira que ela abriu.
func forget(c: Control) -> void:
	for s in windows.keys():
		if windows[s] == c:
			windows.erase(s)
	_companion.erase(c)
	for comp in _companion.keys():
		if _companion[comp] == c:
			_companion.erase(comp)
			if is_instance_valid(comp) and has(comp):
				close_window(comp)


## Fecha a janela pelo caminho dela (emite `closed`).
static func close_window(c: Control) -> void:
	if not is_instance_valid(c) or c.is_queued_for_deletion():
		return
	if c.has_method("_close"):
		c._close()
	elif c.has_method("close"):
		c.close()
	else:
		c.emit_signal("closed")
		c.queue_free()


func close_all() -> void:
	for c in windows.values().duplicate():
		close_window(c)


func _unhandled_input(event: InputEvent) -> void:
	if windows.is_empty() or world == null or not event is InputEventKey:
		return
	for action in HOTKEYS:
		if event.is_action_pressed(action):
			get_viewport().set_input_as_handled()
			world.toggle_window(action)
			return
