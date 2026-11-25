class_name SkillStrip
extends VBoxContainer
## Habilidades de um kit como ícones (arte pintada; sem arte, o desenho do IconPainter) em ordem de tecla,
## com a caixa de detalhe da habilidade sob o mouse ou clicada. Tela de criação de herói.

const SLOT := 58.0
var slots: Array[ItemSlot] = []
var _ids: Array[String] = []
var _row: HBoxContainer
var _title: Label
var _meta: Label
var _desc: Label


func _init() -> void:
	add_theme_constant_override("separation", 10)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 10)
	add_child(_row)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UITheme.kit_inset(10))
	add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	box.add_child(v)
	_title = UITheme.label("", 16, UITheme.TEXT)
	v.add_child(_title)
	_meta = UITheme.label("", 13, UITheme.GOLD_DIM)
	v.add_child(_meta)
	_desc = UITheme.label("", 14, UITheme.DIM)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size.x = 560
	v.add_child(_desc)


## Mostra o kit da classe de arma `weapon_class` ("sword", "bow", "staff", "scepter").
## Ids das habilidades mostradas, na ordem da barra.
func kit_ids() -> Array[String]:
	return _ids


## `offhand` é o tipo da mão secundária ("shield", "two_handed"; "" = nenhuma), como em ItemDB.kit.
func show_kit(weapon_class: String, offhand := "") -> void:
	for s in slots:
		s.queue_free()
	slots.clear()
	_ids = ItemDB.kit(weapon_class, offhand)
	for i in _ids.size():
		var a: Dictionary = ItemDB.ABILITIES[_ids[i]]
		var s := ItemSlot.new(SLOT)
		s.icon_tex = ItemSlot.skill_art(_ids[i])
		s.icon_kind = str(a.get("icon", ""))
		s.key_text = str(a.slot)
		if int(a.get("level", 1)) > 1:
			s.info_text = "Nv %d" % int(a.level)
		if a.get("ultimate", false):
			s.border_override = UITheme.GOLD
		s.mouse_entered.connect(_show.bind(i))
		s.clicked.connect(func(_s: ItemSlot) -> void: _show(i))
		_row.add_child(s)
		slots.append(s)
	_show(0)


## Texto do detalhe mostrado (testes).
func detail_text() -> String:
	return "%s | %s | %s" % [_title.text, _meta.text, _desc.text]


func _show(i: int) -> void:
	if i < 0 or i >= _ids.size():
		_title.text = ""
		_meta.text = ""
		_desc.text = ""
		return
	for j in slots.size():
		slots[j].selected = j == i
		slots[j].queue_redraw()
	var a: Dictionary = ItemDB.ABILITIES[_ids[i]]
	var ult: bool = a.get("ultimate", false)
	_title.text = str(a.name)
	_title.add_theme_color_override("font_color", UITheme.GOLD if ult else UITheme.TEXT)
	var lv := int(a.get("level", 1))
	var parts := ["Tecla %s" % str(a.slot), "libera no nível %d" % lv if lv > 1 else "desde o nível 1"]
	if ult:
		parts.append("ultimate")
	else:
		parts.append("recarga %s s" % str(a.get("cooldown", 0)).replace(".", ","))
	if int(a.get("cost", 0)) > 0:
		parts.append("%d de mana" % int(a.cost))
	_meta.text = " · ".join(parts)
	_desc.text = str(a.get("desc", ""))
