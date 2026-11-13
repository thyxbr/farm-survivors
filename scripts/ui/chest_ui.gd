extends Control
## Janela do baú da cidade em grupo: mostra o seu saque (só você vê o seu), com a dica de cada item
## comparando com o equipado. Clique (ou clique direito / duplo clique) pega um item, "Pegar tudo" pega
## o resto. O que você não pegar fica no baú; se sair da cidade antes, vai para a mochila mesmo assim.

signal closed

const SLOT := 72.0
const COLS := 5

var world: Node
var chest: Node3D
var items: Array = []
var loaded := false

var tooltip: ItemTooltip
var grid: GridContainer
var info: Label
var title: Label
var sub: Label
var take_all: Button
var _pending := {}   # índice -> true (pedido mandado, esperando o servidor)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	var p := UITheme.centered_panel(self, 0.45)
	p.custom_minimum_size = Vector2(560, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	title = UITheme.heading("Baú da noite %d" % int(chest.get("night") if chest else 0), 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	sub = UITheme.label("Abrindo…", 15, UITheme.DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(HSeparator.new())
	var inset := PanelContainer.new()
	inset.add_theme_stylebox_override("panel", UITheme.inset_box(16))
	v.add_child(inset)
	var center := CenterContainer.new()
	center.custom_minimum_size = Vector2(COLS * (SLOT + 8), SLOT * 2 + 24)
	inset.add_child(center)
	grid = GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	center.add_child(grid)
	info = UITheme.label("Clique num item para pegar. Passe o mouse para comparar com o equipado.", 14, UITheme.DIM)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(info)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	take_all = UITheme.button("Pegar tudo", take_everything, 180)
	take_all.disabled = true
	foot.add_child(take_all)
	foot.add_child(UITheme.keycap("E", 13))
	foot.add_child(UITheme.button("Fechar", _close, 140))
	v.add_child(foot)
	tooltip = ItemTooltip.new()
	add_child(tooltip)
	_refresh()


## O servidor mandou o conteúdo (ou o que sobrou depois de pegar algo).
func set_items(list: Array) -> void:
	items = list.duplicate()
	loaded = true
	_pending.clear()
	_refresh()


func _refresh() -> void:
	if not is_inside_tree():
		return
	tooltip.visible = false
	for c in grid.get_children():
		c.queue_free()
	for i in items.size():
		var id := str(items[i])
		var s := ItemSlot.new(SLOT)
		s.set_state(id, 1)
		s.context = "loot"
		s.index = i
		s.tooltip = tooltip
		s.dim = _pending.has(i)
		s.clicked.connect(_take_slot)
		s.right_clicked.connect(_take_slot)
		s.double_clicked.connect(_take_slot)
		grid.add_child(s)
	var n := items.size()
	while n < COLS:
		var e := ItemSlot.new(SLOT)
		e.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(e)
		n += 1
	take_all.disabled = not loaded or items.is_empty() or _pending.size() >= items.size()
	if not loaded:
		sub.text = "Abrindo…"
	elif items.is_empty():
		sub.text = "Vazio — você já pegou tudo."
		sub.add_theme_color_override("font_color", UITheme.DIM)
		info.text = "Os itens foram para a sua mochila (I)."
	else:
		var best := ""
		for id in items:
			if best == "" or ItemDB.RARITY[ItemDB.rarity_of(str(id))].rank > ItemDB.RARITY[best].rank:
				best = ItemDB.rarity_of(str(id))
		sub.text = "%d item(ns) para você · melhor: %s" % [items.size(), ItemDB.RARITY[best].name]
		sub.add_theme_color_override("font_color", ItemDB.RARITY[best].color)


func _take_slot(s: ItemSlot) -> void:
	take(s.index)


func take(i: int) -> void:
	if not loaded or i < 0 or i >= items.size() or _pending.has(i):
		return
	_pending[i] = true
	Lobby.city_chest_take(int(chest.chest_id), i, str(items[i]))
	Sfx.play("pickup", 0.05)
	_refresh()


func take_everything() -> void:
	if not loaded or items.is_empty():
		return
	for i in items.size():
		_pending[i] = true
	Lobby.city_chest_take(int(chest.chest_id), -1, "")
	Sfx.play("coin", 0.05)
	_refresh()


func _close() -> void:
	if chest and is_instance_valid(chest):
		chest.close_lid()
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_close()
