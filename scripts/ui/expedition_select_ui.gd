extends Control
## Seleção de expedição da Guilda: lista as expedições de ExpeditionDefs (na ordem de ExpeditionDefs.ORDER), mostra
## a ficha da escolhida (rank, bioma, salas, bênçãos, chefe) e começa pelo fluxo de sempre
## (world.start_expedition). Aberta pelo portal das expedições na vila (expedition_portal.gd, action "enter").
## Bioma novo aparece aqui sozinho quando entra em ExpeditionDefs; nada nesta tela muda.

signal closed

var world: Node
## Expedição marcada na lista.
var selected := ""
var _list: VBoxContainer
var _details: VBoxContainer
var _start_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := UITheme.centered_panel(self, 0.6)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.custom_minimum_size = Vector2(760, 0)
	p.add_child(v)
	var title := UITheme.heading("Quadro de Expedições da Guilda", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := UITheme.label("Escolha um destino. O que for conquistado lá dentro fica lá dentro: as bênçãos somem na volta.",
		16, UITheme.DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(sub)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	v.add_child(row)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.custom_minimum_size = Vector2(240, 0)
	row.add_child(_list)
	var info := PanelContainer.new()
	info.add_theme_stylebox_override("panel", UITheme.inset_box(16))
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.custom_minimum_size = Vector2(480, 260)
	row.add_child(info)
	_details = VBoxContainer.new()
	_details.add_theme_constant_override("separation", 8)
	info.add_child(_details)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	v.add_child(buttons)
	_start_btn = UITheme.button("Partir em expedição", start_selected, 260)
	buttons.add_child(_start_btn)
	buttons.add_child(UITheme.button("Fechar  (Esc)", _close, 160))

	var ids := ExpeditionDefs.ids()
	for id in ids:
		var b := UITheme.button("%s   ·   Rank %s" % [ExpeditionDefs.display_name(id), str(ExpeditionDefs.get_def(id).get("rank", "?"))],
			select.bind(id), 240)
		b.toggle_mode = true
		b.set_meta("expedition", id)
		_list.add_child(b)
	select(selected if ExpeditionDefs.has(selected) else (ids[0] if not ids.is_empty() else ""))
	_start_btn.grab_focus.call_deferred()


## Marca a expedição `id` e mostra a ficha dela.
func select(id: String) -> void:
	selected = id
	for b in _list.get_children():
		(b as Button).set_pressed_no_signal(str(b.get_meta("expedition", "")) == id)
	for c in _details.get_children():
		c.queue_free()
	_start_btn.disabled = id == ""
	if id == "":
		_details.add_child(UITheme.label("Nenhuma expedição disponível.", 18, UITheme.DIM))
		return
	for line in details_lines(id):
		var l := UITheme.label(str(line[0]), int(line[1]), line[2])
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_details.add_child(l)


## Linhas da ficha: [texto, tamanho, cor]. Separado para os testes lerem o conteúdo.
static func details_lines(id: String) -> Array:
	var d := ExpeditionDefs.get_def(id)
	var fights := ExpeditionDefs.clear_rooms(d).filter(
		func(r: String) -> bool: return ExpeditionDefs.kind_of(d, r) != "boss").size()
	var out: Array = []
	out.append([ExpeditionDefs.display_name(id), 26, UITheme.GOLD])
	out.append(["Rank %s   ·   Expedição solo" % str(d.get("rank", "?")), 16, UITheme.TEXT])
	if str(d.get("desc", "")) != "":
		out.append([str(d.desc), 16, UITheme.DIM])
	out.append(["Salas: %d  (%d de combate)" % [ExpeditionDefs.rooms(d).size(), fights], 16, UITheme.TEXT])
	out.append(["Bênçãos no caminho: %d  (escolha 1 de %d ao limpar a sala)" % [ExpeditionDefs.reward_rooms(d).size(),
		ExpeditionUpgrades.CHOICES], 16, UITheme.TEXT])
	out.append(["Chefe: %s" % str(d.get("boss", "?")), 16, Color(1, 0.6, 0.45)])
	out.append(["Cair ou abandonar leva de volta à Guilda, sem multa de ouro.", 14, UITheme.DIM])
	return out


## Começa a expedição marcada pelo fluxo de sempre (fecha esta tela antes: o mundo só abre uma janela por vez).
func start_selected() -> void:
	if selected == "" or world == null or is_queued_for_deletion():
		return
	var id := selected
	var w := world
	_close()
	w.call_deferred("start_expedition", id)


func _close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_close()
