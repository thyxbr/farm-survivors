class_name ItemTooltip
extends PanelContainer
## Dica flutuante de item: nome na cor da raridade, atributos, efeito e comparação já calculada
## com o que está equipado (verde = melhora, vermelho = piora), como nos ARPGs.

const STAT_LABELS := {"dmg": ["Dano do ataque", false], "def": ["Defesa", false], "hp": ["Vida máxima", false],
	"mp": ["Mana máxima", false], "spell": ["Poder mágico", false], "crit": ["Crítico", true],
	"speed": ["Velocidade", true], "cdr": ["Recarga reduzida", true], "leech": ["Roubo de vida", true]}

var _owner_slot: ItemSlot
var _text: RichTextLabel


func _ready() -> void:
	top_level = true
	visible = false
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UITheme.frame_box(Color(0.04, 0.035, 0.035, 0.97), UITheme.GOLD_DIM, 14)
	add_theme_stylebox_override("panel", sb)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size.x = 330
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_theme_font_size_override("normal_font_size", 16)
	_text.add_theme_font_size_override("bold_font_size", 16)
	_text.add_theme_font_override("bold_font", UITheme.serif())
	add_child(_text)


func show_for(slot: ItemSlot) -> void:
	_owner_slot = slot
	var id := slot.item_id
	var rc := ItemDB.rarity_color(id)
	(get_theme_stylebox("panel") as StyleBoxFlat).border_color = rc.darkened(0.15) if ItemDB.is_equippable(id) else UITheme.GOLD_DIM
	_text.text = build_text(id, slot.context)
	_text.size = Vector2.ZERO
	reset_size()
	visible = true
	_follow()


func hide_for(slot: ItemSlot) -> void:
	if _owner_slot == slot:
		visible = false
		_owner_slot = null


func _process(_d: float) -> void:
	if visible:
		if _owner_slot == null or not is_instance_valid(_owner_slot) or not _owner_slot.is_visible_in_tree():
			visible = false
			return
		_follow()


func _follow() -> void:
	var vp := get_viewport_rect().size
	var m := get_viewport().get_mouse_position()
	var s := get_combined_minimum_size()
	var p := m + Vector2(22, 18)
	if p.x + s.x > vp.x - 8:
		p.x = m.x - s.x - 18
	if p.y + s.y > vp.y - 8:
		p.y = vp.y - s.y - 8
	global_position = p.max(Vector2(8, 8))


static func _hex(c: Color) -> String:
	return c.to_html(false)


static func build_text(id: String, context := "bag") -> String:
	var it := ItemDB.get_item(id)
	if it.is_empty():
		return ""
	var rar: Dictionary = ItemDB.RARITY[ItemDB.rarity_of(id)]
	var rc := _hex(rar.color)
	var dim := _hex(UITheme.DIM)
	var good := _hex(UITheme.GOOD)
	var bad := _hex(UITheme.BAD)
	var t := "[font_size=22][b][color=#%s]%s[/color][/b][/font_size]\n" % [rc, it.name]
	var slot := ItemDB.slot_of(id)
	if slot != "":
		var kind: String = ItemDB.CLASS_NAMES[ItemDB.weapon_class(id)] if slot == "weapon" else ItemDB.SLOT_NAMES[slot]
		t += "[color=#%s]%s · %s[/color]\n" % [rc, rar.name, kind]
		if it.has("damage"):
			t += "[font_size=26]%d[/font_size] [color=#%s]Dano[/color]\n" % [it.damage, dim]
			t += "[color=#%s]%s[/color]\n" % [dim, ItemDB.CLASS_HINT[ItemDB.weapon_class(id)]]
			var ench := Game.enchant_of(id)
			if ench.lv > 0:   # encanto do ferreiro, na cor do elemento
				var ec: Color = EnchantFX.ELEMENTS.get(ench.el, {}).get("color", Color.WHITE)
				t += "[color=#%s]✦ %s[/color]\n" % [_hex(ec), Game.enchant_text(id)]
		if it.get("defense", 0) > 0:
			t += "[font_size=26]%d[/font_size] [color=#%s]Defesa[/color]\n" % [it.defense, dim]
		var st := ItemDB.item_stats(id)
		for k in ItemDB.STAT_ORDER:
			if st.has(k):
				t += "[color=#%s]%s[/color]\n" % [_hex(Color(0.55, 0.75, 1.0)), ItemDB.format_stat(k, float(st[k]))]
		if it.has("fx"):
			t += "[color=#%s]✦ %s[/color]\n" % [_hex(Color(0.5, 0.95, 1.0)), ItemDB.FX_NAMES[it.fx]]
		if it.has("needs"):
			var ok: bool = Game.weapon_class() == it.needs
			t += "[color=#%s]Exige: %s[/color]\n" % [good if ok else bad, ItemDB.CLASS_NAMES[it.needs]]
	else:
		var lines := ItemDB.item_summary(id).split("\n")
		for i in range(1, lines.size() - 2):
			t += "%s\n" % lines[i]
	t += "[i][color=#%s]%s[/color][/i]\n" % [_hex(Color(0.78, 0.72, 0.58)), it.desc]

	# comparação calculada com o equipado
	if slot != "" and context != "equip":
		var cur: String = Game.equipment.get(slot, "")
		t += "[color=#%s]━━━━━━━━━━━━━━━━━━━━[/color]\n" % _hex(UITheme.GOLD_DIM)
		if cur == id:
			t += "[color=#%s]Igual ao equipado.[/color]\n" % dim
		else:
			t += "[color=#%s]Se equipar%s:[/color]\n" % [dim, (" (no lugar de %s)" % ItemDB.get_item(cur).name) if cur != "" else ""]
			var d := Game.preview_equip(id)
			var any := false
			for k in STAT_LABELS:
				var v: float = d.get(k, 0.0)
				if abs(v) < 0.005:
					continue
				any = true
				var pct: bool = STAT_LABELS[k][1]
				var txt := ("%+d%%" % int(round(v * 100))) if pct else ("%+.0f" % v)
				t += "  [color=#%s]%s %s[/color]\n" % [good if v > 0 else bad, txt, STAT_LABELS[k][0]]
			if not any:
				t += "  [color=#%s]Nenhuma mudança nos números.[/color]\n" % dim
			if slot == "weapon" and ItemDB.weapon_class(id) != Game.weapon_class():
				t += "  [color=#%s]Muda o ataque para %s[/color]\n" % [_hex(UITheme.GOLD), ItemDB.CLASS_NAMES[ItemDB.weapon_class(id)].to_lower()]

	# preço e dicas
	var price: int = it.price
	match context:
		"buy":
			t += "[color=#%s]Preço: %d ◆[/color]\n" % [_hex(UITheme.GOLD) if Game.gold >= price else bad, price]
			t += "[color=#%s]Clique direito ou duplo clique: comprar[/color]" % dim
		"sell":
			t += "[color=#%s]Vende por: %d ◆[/color]\n" % [_hex(UITheme.GOLD), int(ceil(price * 0.5))]
			t += "[color=#%s]Clique direito ou duplo clique: vender[/color]" % dim
		"equip":
			t += "[color=#%s]Valor: %d ◆[/color]\n" % [dim, price]
			t += "[color=#%s]Clique direito: remover · arraste para a mochila[/color]" % dim
		_:
			t += "[color=#%s]Valor: %d ◆[/color]\n" % [dim, price]
			if slot != "":
				t += "[color=#%s]Clique direito: equipar · arraste para o boneco[/color]" % dim
			elif Game.is_edible(id) or it.type == "consumable":
				t += "[color=#%s]Clique direito: usar[/color]" % dim
	return t.strip_edges()
