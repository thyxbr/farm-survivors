class_name ItemSlot
extends Control
## Espaço quadrado com ícone: usado na mochila, no boneco de equipamento, na loja e na barra de ações.
## Moldura na cor da raridade, quantidade, tecla de atalho, recarga radial e arrastar/soltar.

signal clicked(slot: ItemSlot)
signal right_clicked(slot: ItemSlot)
signal double_clicked(slot: ItemSlot)

var item_id := "":
	set(v):
		item_id = v
		queue_redraw()
## Ícone sem item (magias do HUD) e ícone "fantasma" de espaço vazio.
var icon_kind := ""
var icon_color := Color.WHITE
var ghost_kind := ""
var qty := 0
var key_text := ""
var info_text := ""
var label_text := ""      # texto pequeno embaixo do espaço vazio (ex.: "Cabeça")
var cooldown := 0.0       # 0..1 (fração restante)
var cooldown_text := ""
var selected := false
var dim := false
var border_override := Color(0, 0, 0, 0)
var drop_hint := false
## Contexto para a dica e para arrastar: "bag", "equip", "buy", "sell".
var context := ""
var index := -1
var slot_name := ""
var tooltip: ItemTooltip
var drag_source := ""
var drop_handler: Callable
## Barra de ações do HUD (variante B): mais margem em volta do ícone, tecla num selo no canto superior
## esquerdo e o texto (custo, quantidade) num selo embaixo, os dois fora do desenho.
var badges := false
var _hover := false


func _init(sz := 64.0) -> void:
	custom_minimum_size = Vector2(sz, sz)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_enter)
	mouse_exited.connect(_on_exit)


func set_state(id: String, q := 0) -> void:
	item_id = id
	qty = q
	queue_redraw()


func _on_enter() -> void:
	_hover = true
	queue_redraw()
	if tooltip and item_id != "":
		tooltip.show_for(self)


func _on_exit() -> void:
	_hover = false
	queue_redraw()
	if tooltip:
		tooltip.hide_for(self)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.double_click:
				double_clicked.emit(self)
			else:
				clicked.emit(self)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			right_clicked.emit(self)


# ------------------------------------------------------------------ arrastar e soltar
func _get_drag_data(_at: Vector2) -> Variant:
	if drag_source == "" or item_id == "":
		return null
	var prev := ItemSlot.new(size.x)
	prev.item_id = item_id
	prev.qty = qty
	prev.modulate.a = 0.85
	var holder := Control.new()
	holder.add_child(prev)
	prev.position = -size * 0.5
	set_drag_preview(holder)
	if tooltip:
		tooltip.hide_for(self)
	return {"source": drag_source, "id": item_id, "index": index, "slot": slot_name}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	var ok: bool = data is Dictionary and drop_handler.is_valid() and drop_handler.call(self, data, false)
	if ok != drop_hint:
		drop_hint = ok
		queue_redraw()
	return ok


func _drop_data(_at: Vector2, data: Variant) -> void:
	drop_hint = false
	queue_redraw()
	drop_handler.call(self, data, true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and drop_hint:
		drop_hint = false
		queue_redraw()


# ------------------------------------------------------------------ desenho
func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var has_item := item_id != ""
	var rc := ItemDB.rarity_color(item_id) if has_item else UITheme.GOLD_DIM
	if border_override.a > 0.0:
		rc = border_override
	# fundo
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.055, 0.05, 0.92)
	bg.set_corner_radius_all(4)
	bg.border_color = rc.darkened(0.25) if has_item or icon_kind != "" else Color(0.3, 0.26, 0.2, 0.7)
	bg.set_border_width_all(1)
	if selected:
		bg.border_color = Color(1, 0.88, 0.5)
		bg.set_border_width_all(2)
	elif drop_hint:
		bg.border_color = UITheme.GOOD
		bg.set_border_width_all(2)
	elif _hover:
		bg.border_color = bg.border_color.lightened(0.35)
	draw_style_box(bg, r)
	if has_item:
		# brilho interno e cantos na cor da raridade (leitura rápida, como nas lojas de ARPG)
		var rank: int = ItemDB.RARITY[ItemDB.rarity_of(item_id)].rank
		if rank > 0:
			draw_rect(r.grow(-3), Color(rc.r, rc.g, rc.b, 0.07 + rank * 0.03))
		var c := minf(size.x * 0.15, 9.0)
		for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
			var o := Vector2(corner.x * size.x, corner.y * size.y)
			var dx := c if corner.x == 0 else -c
			var dy := c if corner.y == 0 else -c
			draw_colored_polygon(PackedVector2Array([o, o + Vector2(dx, 0), o + Vector2(0, dy)]), Color(rc.r, rc.g, rc.b, 0.95))
	if selected:
		draw_rect(r.grow(-2), Color(1, 0.85, 0.4, 0.08))
	# ícone
	var inset := size.x * (0.17 if badges else 0.14)
	var ir := r.grow(-inset)
	if has_item:
		IconPainter.draw(self, IconPainter.kind_for(item_id), IconPainter.color_for(item_id), ir)
	elif icon_kind != "":
		IconPainter.draw(self, icon_kind, icon_color, ir)
	elif ghost_kind != "":
		IconPainter.draw(self, ghost_kind, Color(1, 1, 1, 0.1), ir, true)
	if dim:
		draw_rect(r.grow(-1), Color(0, 0, 0, 0.55))
	# recarga radial (fatia escura que diminui no sentido horário)
	if cooldown > 0.0:
		var c := r.get_center()
		var rad := size.length() * 0.5
		var pts := PackedVector2Array([c])
		var n := 24
		for i in n + 1:
			var a := -PI / 2.0 + TAU * (1.0 - cooldown) + TAU * cooldown * float(i) / n
			pts.append(c + Vector2(cos(a), sin(a)) * rad)
		var clip := Rect2(r.grow(-1))
		for i in pts.size():
			pts[i] = pts[i].clamp(clip.position, clip.end)
		# triângulos soltos (draw_primitive não triangula, então pontos colados na borda não dão erro)
		var shade := Color(0, 0, 0, 0.62)
		var cols := PackedColorArray([shade, shade, shade])
		for i in range(1, pts.size() - 1):
			draw_primitive(PackedVector2Array([pts[0], pts[i], pts[i + 1]]), cols, PackedVector2Array())
	var font := ThemeDB.fallback_font
	# textos encolhem junto com espaços pequenos (barra de ações compacta)
	var k := clampf(size.x / 58.0, 0.72, 1.0)
	if cooldown_text != "":
		_text(font, cooldown_text, Vector2(0, size.y * 0.5 + 7 * k), int(20 * k), Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	if badges:
		if key_text != "":
			var kw := maxf(15.0, font.get_string_size(key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 8.0)
			HordeIcon.badge(self, key_text, Vector2(-6 + kw, 8), Color(0.63, 0.52, 0.38), Color(1, 0.95, 0.84))
		var t := info_text if info_text != "" else (str(qty) if qty > 1 else "")
		if t != "":
			HordeIcon.badge(self, t, Vector2(size.x * 0.5, size.y + 8), Color(0.36, 0.29, 0.2), Color(0.93, 0.93, 0.93), 9, 13.0, true)
		return
	if key_text != "":
		var kfs := int(13 * k)
		var kw := font.get_string_size(key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, kfs).x + 6
		var kr := Rect2(Vector2(2, 2), Vector2(maxf(kw, 14), kfs + 3))
		var ks := StyleBoxFlat.new()
		ks.bg_color = Color(0.12, 0.1, 0.08, 0.9)
		ks.border_color = Color(0.5, 0.43, 0.32)
		ks.set_border_width_all(1)
		ks.set_corner_radius_all(3)
		draw_style_box(ks, kr)
		draw_string(font, Vector2(kr.position.x, kr.position.y + kfs), key_text, HORIZONTAL_ALIGNMENT_CENTER, kr.size.x, kfs, Color(1, 0.95, 0.8))
	if qty > 1:
		_text(font, str(qty), Vector2(-4, size.y - 4), int(15 * k), Color(1, 1, 1), HORIZONTAL_ALIGNMENT_RIGHT)
	if info_text != "":
		_text(font, info_text, Vector2(0, size.y - 3), int(12 * k), Color(0.85, 0.85, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	if label_text != "" and not has_item:
		_text(font, label_text, Vector2(0, size.y - 5), 11, Color(0.6, 0.56, 0.48, 0.8), HORIZONTAL_ALIGNMENT_CENTER)


func _text(font: Font, t: String, pos: Vector2, fs: int, col: Color, align: HorizontalAlignment) -> void:
	var w := size.x
	var p := Vector2(0, pos.y)
	if align == HORIZONTAL_ALIGNMENT_RIGHT:
		p.x = pos.x
	draw_string_outline(font, p, t, align, w, fs, 4, Color(0, 0, 0, 0.95))
	draw_string(font, p, t, align, w, fs, col)
