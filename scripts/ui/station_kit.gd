class_name StationKit
extends RefCounted
## Peças das telas de estação no formato da forja (CraftingUI): à esquerda uma lista de linhas com ícone,
## nome e uma etiqueta (x3, "nível", preço); à direita o detalhe, com o ícone grande, título, subtítulo,
## plaquinhas de números e a grade de materiais "tenho / preciso". Horta, caldeirão e encantamento montam
## com isto, para as quatro bancadas terem a mesma cara. Tudo é montado no tema escuro e a janela lateral
## converte para tinta (PaperInk).

const ROW_H := 58.0
const C_LOCK := Color(0.5, 0.48, 0.44)


## Quadro de seção (vira o quadro rebaixado do pergaminho).
static func inset(margin := 14) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.kit_inset(margin))
	return p


## Cabeçalho da janela: o nome da estação à esquerda e, à direita, o que a tela quiser (ouro, profissão).
static func header(title: String, right: Control = null) -> HBoxContainer:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 24)
	var name_l := UITheme.heading(title, 30)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_l)
	if right != null:
		right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(right)
	return head


## Coluna da lista: título de seção (com `extra` ao lado, ex. um filtro) e as linhas rolando.
## Devolve {"panel", "rows", "scroll"}.
static func list_panel(title: String, extra: Control = null, min_size := Vector2(400, 420)) -> Dictionary:
	var panel := inset()
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	panel.add_child(lv)
	var lh := HBoxContainer.new()
	var sec := UITheme.section(title)
	sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lh.add_child(sec)
	if extra != null:
		lh.add_child(extra)
	lv.add_child(lh)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = min_size
	lv.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	return {"panel": panel, "rows": rows, "scroll": scroll}


## Linha da lista: ícone (item `item_id`, ou desenho `icon_kind` na cor `icon_color`), nome, subtítulo e
## etiqueta à direita. Clique escolhe; duplo clique faz a ação. Devolve {"btn", "name", "sub", "tag", "slot"}.
static func row(item_id: String, title: String, sub: String, on_select: Callable, on_double := Callable(),
		icon_kind := "", icon_color := Color.WHITE) -> Dictionary:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, ROW_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(on_select)
	if on_double.is_valid():
		b.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.double_click and e.button_index == MOUSE_BUTTON_LEFT:
				on_select.call()
				on_double.call())
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 8
	hb.offset_right = -10
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	var slot := ItemSlot.new(44)
	slot.model_icon = true
	slot.item_id = item_id
	slot.icon_kind = icon_kind
	slot.icon_color = icon_color
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(slot)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(tv)
	var name_l := UITheme.label(title, 16)
	name_l.clip_text = true
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(name_l)
	var sub_l := UITheme.label(sub, 13, UITheme.DIM)
	sub_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(sub_l)
	var tag := UITheme.label("", 15, UITheme.GOOD)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(tag)
	return {"btn": b, "name": name_l, "sub": sub_l, "tag": tag, "slot": slot}


## Estado de uma linha: escolhida, possível (nome na cor `col`) ou apagada, e a etiqueta.
static func set_row(r: Dictionary, chosen: bool, can: bool, col: Color, tag: String, tag_col := UITheme.GOOD) -> void:
	(r.btn as Button).set_pressed_no_signal(chosen)
	(r.name as Label).add_theme_color_override("font_color", col if can else C_LOCK)
	(r.slot as ItemSlot).dim = not can
	(r.slot as ItemSlot).queue_redraw()
	(r.tag as Label).text = tag
	(r.tag as Label).add_theme_color_override("font_color", tag_col if can else C_LOCK)


## Coluna do detalhe. Devolve {"panel", "box"}.
static func detail_panel(width := 520.0) -> Dictionary:
	var panel := inset()
	var rv := VBoxContainer.new()
	rv.custom_minimum_size = Vector2(width, 0)
	rv.add_theme_constant_override("separation", 10)
	panel.add_child(rv)
	return {"panel": panel, "box": rv}


## Topo do detalhe: ícone grande e, ao lado, título, subtítulo e uma linha de números.
## Devolve {"slot", "title", "sub", "stats"}.
static func detail_head(box: Control, tooltip: ItemTooltip, size := 132.0) -> Dictionary:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	box.add_child(top)
	var slot := ItemSlot.new(size)
	slot.model_icon = true
	slot.tooltip = tooltip
	slot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(slot)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 3)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tv)
	var title := UITheme.heading("", 24)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(title)
	var sub := UITheme.label("", 15, UITheme.DIM)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(sub)
	var stats := UITheme.label("", 16, Color(0.72, 0.85, 1.0))
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(stats)
	return {"slot": slot, "title": title, "sub": sub, "stats": stats}


## Plaquinha "100% · Sucesso": número grande em cima, legenda embaixo; `on` apaga quando falso.
static func chip(value: String, caption: String, col: Color, on := true) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UITheme.inset_box(10)
	sb.border_color = Color(col, 0.55 if on else 0.15)
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -2)
	p.add_child(vb)
	var big := UITheme.heading(value, 22, col if on else C_LOCK)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(big)
	var l := UITheme.label(caption, 13, UITheme.DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(l)
	return p


## Grade de materiais com duas colunas.
static func materials_grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 8)
	return g


## Um material: ícone (com dica), nome e tenho/preciso em verde ou vermelho. `id` "" = ouro, "$ecos" = Ecos.
static func material(id: String, title: String, have: int, need: int, tooltip: ItemTooltip) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.custom_minimum_size.x = 245
	var slot := ItemSlot.new(50)
	slot.model_icon = true
	if id == "":
		slot.icon_kind = "orb"
		slot.icon_color = Color(1.0, 0.8, 0.25)
	elif id == "$ecos":
		slot.icon_kind = "orb"
		slot.icon_color = Color(0.55, 0.85, 1.0)
	else:
		slot.item_id = id
		slot.tooltip = tooltip
	slot.dim = have < need
	hb.add_child(slot)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(vb)
	var n := UITheme.label(title, 15)
	n.clip_text = true
	n.custom_minimum_size.x = 180
	vb.add_child(n)
	vb.add_child(UITheme.label("%d / %d" % [have, need], 15, UITheme.GOOD if have >= need else UITheme.BAD))
	return hb


## Esvazia um contêiner na hora (queue_free sozinho deixaria o conteúdo velho até o fim do quadro).
static func clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
