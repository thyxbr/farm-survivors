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
	"quest_log": ["left", 3], "professions": ["left", 4], "bestiary": ["left", 5], "party": ["left", -1], "friends": ["left", -2]}

var world: Node
var windows := {}            # "left"/"right" -> Control
var _companion := {}         # janela aberta junto -> janela que a abriu
## Onde o jogador deixou cada tipo de janela (arrastando): ela reabre lá.
var _spots := {}             # tipo da janela -> posição


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("window_dock")


## Painel visível de uma janela (o que o jogador arrasta), ou null.
static func frame_of(c: Control) -> Control:
	if not is_instance_valid(c):
		return null
	var b = c.get("book")
	if b is BookWindow:
		return b.frame()
	if c.has_meta("_dock_frame"):
		return c.get_meta("_dock_frame")
	return null


## Janela que ficou por cima de outra (arrastada ou recém-aberta) encosta ao lado dela, do lado mais perto
## de onde está; se não cabe de nenhum lado, empurra a outra. Nada sai da tela.
func resolve(moved: Control) -> void:
	if not is_instance_valid(moved) or not moved.is_inside_tree():
		return
	_resolve(moved)
	for c in windows.values():   # guarda onde cada janela ficou
		var f := frame_of(c)
		if f != null and f.has_meta("_user_pos"):
			_spots[kind_of(c)] = f.get_meta("_user_pos")


static func kind_of(c: Control) -> String:
	return "%s:%s" % [c.get_script().resource_path if c.get_script() else c.get_class(), str(c.get("mode"))]


## Janela recém-aberta: volta para onde o jogador a deixou da última vez e, se cobrir outra, desencavala.
func settle(c: Control) -> void:
	var f := frame_of(c)
	if f == null:
		return
	if _spots.has(kind_of(c)):
		f.set_meta("_user_pos", _spots[kind_of(c)])
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(f) and f.is_inside_tree():
		_resolve(f)


func _resolve(moved: Control) -> void:
	var area := moved.get_viewport_rect().size
	for c in windows.values():
		var other := frame_of(c)
		if other == null or other == moved or not other.is_visible_in_tree():
			continue
		var a := moved.get_global_rect()
		var b := other.get_global_rect()
		if not a.grow(-1.0).intersects(b):
			continue
		var spot = _beside(a, b, area)
		if spot != null:
			_place(moved, spot)
		else:
			spot = _beside(b, a, area)
			if spot != null:
				_place(other, spot)


## Posição para o retângulo `a` ao lado de `b` (esquerda ou direita, a mais perto), ou null se não cabe.
static func _beside(a: Rect2, b: Rect2, area: Vector2) -> Variant:
	var gap := 8.0
	var opts: Array = []
	var left := b.position.x - gap - a.size.x
	var right := b.end.x + gap
	if left >= 0.0:
		opts.append(Vector2(left, a.position.y))
	if right + a.size.x <= area.x:
		opts.append(Vector2(right, a.position.y))
	if opts.is_empty():
		return null
	opts.sort_custom(func(p: Vector2, q: Vector2) -> bool:
		return absf(p.x - a.position.x) < absf(q.x - a.position.x))
	return opts[0]


static func _place(frame: Control, global_pos: Vector2) -> void:
	var parent_pos := (frame.get_parent() as Control).global_position
	frame.set_meta("_user_pos", global_pos - parent_pos)
	frame.position = (global_pos - parent_pos).round()


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
