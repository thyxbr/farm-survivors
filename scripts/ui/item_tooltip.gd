class_name ItemTooltip
extends PanelContainer
## Dica flutuante de item: nome na cor da raridade, atributos, efeito e comparação já calculada
## com o que está equipado (verde = melhora, vermelho = piora), como nos ARPGs.
## Segurando Shift sobre um item equipável, a ficha do item equipado naquele espaço abre ao lado
## (`_cmp`), para ler os dois inteiros lado a lado.

const STAT_LABELS := {"dmg": ["Dano do ataque", false], "def": ["Defesa", false], "hp": ["Vida máxima", false],
	"mp": ["Mana máxima", false], "spell": ["Poder mágico", false], "crit": ["Crítico", true],
	"speed": ["Velocidade", true], "cdr": ["Recarga reduzida", true], "leech": ["Roubo de vida", true]}

## Folha de papel com texto a tinta, para as telas do livro; desligado, o painel escuro de sempre
## (loja, HUD). Ligar antes de entrar na árvore.
var paper := false

var _owner_slot: ItemSlot
var _text: RichTextLabel
## Ficha do item equipado (Shift), filha que não entra no layout do painel (top_level).
var _cmp: PanelContainer
var _cmp_text: RichTextLabel
var _cmp_id := ""


func _ready() -> void:
	top_level = true
	visible = false
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb: StyleBox = UITheme.kit_panel(14)
	if paper:
		sb = UITheme.small_frame(6)
	add_theme_stylebox_override("panel", sb)
	_text = _make_text()
	add_child(_text)
	_cmp = PanelContainer.new()
	_cmp.top_level = true
	_cmp.visible = false
	_cmp.z_index = 100
	_cmp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cmp.add_theme_stylebox_override("panel", sb.duplicate())
	_cmp_text = _make_text()
	_cmp.add_child(_cmp_text)
	add_child(_cmp)


func _make_text() -> RichTextLabel:
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.scroll_active = false
	t.custom_minimum_size.x = 330
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_theme_font_size_override("normal_font_size", 16)
	t.add_theme_font_size_override("bold_font_size", 16)
	t.add_theme_font_override("bold_font", UITheme.serif())
	if paper:
		# a Garamond é menor: 2 px a mais, como em UITheme.ink()
		t.add_theme_font_size_override("normal_font_size", 18)
		t.add_theme_font_size_override("italics_font_size", 18)
		t.add_theme_font_override("normal_font", UITheme.body())
		var slanted := FontVariation.new()   # a Garamond embutida não tem itálico: inclina a normal
		slanted.base_font = UITheme.body()
		slanted.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.2, 1), Vector2.ZERO)
		t.add_theme_font_override("italics_font", slanted)
		t.add_theme_color_override("default_color", UITheme.INK)
	return t


func show_for(slot: ItemSlot) -> void:
	_owner_slot = slot
	var id := slot.item_id
	var rc := ItemDB.rarity_color(id)
	var border := rc.darkened(0.15) if ItemDB.is_equippable(id) else UITheme.GOLD_DIM
	if paper:
		border = _rarity_ink(id) if ItemDB.is_equippable(id) else UITheme.INK
	var box := get_theme_stylebox("panel") as StyleBoxFlat
	if box:
		box.border_color = border
	_text.text = build_text(id, slot.context, paper)
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
	_update_compare(Input.is_key_pressed(KEY_SHIFT))


## Item equipado no espaço do item da dica, quando vale comparar (vazio se não há o que comparar).
static func compare_target(id: String, context: String) -> String:
	var slot := ItemDB.slot_of(id)
	if slot == "" or context == "equip":
		return ""
	var cur := str(Game.equipment.get(slot, ""))
	return cur if cur != id else ""


## Com Shift, abre ao lado a ficha do item equipado; sem Shift (ou sem dica), fecha.
func _update_compare(shift: bool) -> void:
	var want := ""
	if shift and visible and _owner_slot != null and is_instance_valid(_owner_slot):
		want = compare_target(_owner_slot.item_id, _owner_slot.context)
	if want == "":
		_cmp.visible = false
		_cmp_id = ""
		return
	if want != _cmp_id:
		_cmp_id = want
		var border := _rarity_ink(want) if paper else ItemDB.rarity_color(want).darkened(0.15)
		var box := _cmp.get_theme_stylebox("panel") as StyleBoxFlat
		if box:
			box.border_color = border
		var head := "[color=#%s]EQUIPADO[/color]\n" % _hex(_palette(paper).dim)
		_cmp_text.text = head + build_text(want, "worn", paper)
		_cmp_text.size = Vector2.ZERO
		_cmp.reset_size()
	_cmp.visible = true
	_place_compare()


## A ficha do equipado fica do lado de fora da dica (esquerda se couber, senão direita), alinhada no topo.
func _place_compare() -> void:
	var vp := get_viewport_rect().size
	var s := _cmp.get_combined_minimum_size()
	var me := Rect2(global_position, size.max(get_combined_minimum_size()))
	var x := me.position.x - s.x - 8
	if x < 8:
		x = me.end.x + 8
	var y := clampf(me.position.y, 8, maxf(8, vp.y - s.y - 8))
	_cmp.global_position = Vector2(x, y)


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


## Cor da raridade escurecida para ler sobre papel; o comum (branco) vira tinta.
static func _rarity_ink(id: String) -> Color:
	var rar: Dictionary = ItemDB.RARITY[ItemDB.rarity_of(id)]
	return UITheme.on_paper(rar.color) if rar.rank > 0 else UITheme.INK


## Cores do texto: as claras do tema escuro ou, com `paper`, as mesmas ideias a tinta.
static func _palette(paper: bool) -> Dictionary:
	if paper:
		return {"dim": UITheme.INK_DIM, "good": Color(0.1, 0.4, 0.12), "bad": UITheme.INK_RED,
			"stat": Color(0.12, 0.25, 0.52), "fx": Color(0.05, 0.36, 0.42), "desc": UITheme.INK_DIM,
			"rule": Color(UITheme.INK, 0.45), "gold": Color(0.45, 0.27, 0.02)}
	return {"dim": UITheme.DIM, "good": UITheme.GOOD, "bad": UITheme.BAD, "stat": Color(0.55, 0.75, 1.0),
		"fx": Color(0.5, 0.95, 1.0), "desc": Color(0.78, 0.72, 0.58), "rule": UITheme.GOLD_DIM, "gold": UITheme.GOLD}


## `paper` troca as cores claras por tinta (dica dentro do livro).
static func build_text(id: String, context := "bag", paper := false) -> String:
	var it := ItemDB.get_item(id)
	if it.is_empty():
		return ""
	var pal := _palette(paper)
	var rar: Dictionary = ItemDB.RARITY[ItemDB.rarity_of(id)]
	var rc := _hex(_rarity_ink(id) if paper else rar.color)
	var dim := _hex(pal.dim)
	var good := _hex(pal.good)
	var bad := _hex(pal.bad)
	var gold := _hex(pal.gold)
	var t := "[font_size=22][b][color=#%s]%s[/color][/b][/font_size]\n" % [rc, it.name]
	var slot := ItemDB.slot_of(id)
	if slot != "":
		var kind: String = ItemDB.CLASS_NAMES[ItemDB.weapon_class(id)] if slot == "weapon" else ItemDB.SLOT_NAMES[slot]
		if ItemDB.is_two_handed(id):
			kind = "Montante"
		t += "[color=#%s]%s · %s[/color]\n" % [rc, rar.name, kind]
		var need := int(it.get("level", 1))
		t += "[color=#%s]Nível %d[/color]\n" % [good if Game.level >= need else bad, need]
		if it.has("damage"):
			t += "[font_size=26]%d[/font_size] [color=#%s]Dano[/color]\n" % [it.damage, dim]
			t += "[color=#%s]%s[/color]\n" % [dim, ItemDB.TWO_HAND_HINT if ItemDB.is_two_handed(id) else ItemDB.CLASS_HINT[ItemDB.weapon_class(id)]]
			if ItemDB.is_two_handed(id):
				t += "[color=#%s]Duas mãos: a mão secundária fica vazia[/color]\n" % _hex(pal.fx)
			if not Game.can_wield(id):
				t += "[color=#%s]Arma de %s: sua classe não equipa.[/color]\n" % [bad, Game.weapon_owner(id)]
			var ench := Game.enchant_of(id)
			if ench.lv > 0:   # encanto do ferreiro, na cor do elemento
				var ec: Color = EnchantFX.ELEMENTS.get(ench.el, {}).get("color", Color.WHITE)
				if paper:
					ec = UITheme.on_paper(ec)
				t += "[color=#%s]✦ %s[/color]\n" % [_hex(ec), Game.enchant_text(id)]
		if it.get("defense", 0) > 0:
			t += "[font_size=26]%d[/font_size] [color=#%s]Defesa[/color]\n" % [it.defense, dim]
		var st := ItemDB.item_stats(id)
		for k in ItemDB.STAT_ORDER:
			if st.has(k):
				t += "[color=#%s]%s[/color]\n" % [_hex(pal.stat), ItemDB.format_stat(k, float(st[k]))]
		if it.has("affix"):   # bônus sorteado no craft (já somado nos atributos acima)
			t += "[color=#%s]✦ Bônus de ofício: %s[/color]\n" % [_hex(pal.fx), ItemDB.format_stat(str(it.affix_stat), float(it.affix_value))]
		if it.has("fx"):
			t += "[color=#%s]✦ %s[/color]\n" % [_hex(pal.fx), ItemDB.FX_NAMES[it.fx]]
		if it.has("needs"):
			var ok: bool = Game.weapon_class() == it.needs
			t += "[color=#%s]Exige: %s[/color]\n" % [good if ok else bad, ItemDB.CLASS_NAMES[it.needs]]
	else:
		var lines := ItemDB.item_summary(id).split("\n")
		for i in range(1, lines.size() - 2):
			t += "%s\n" % lines[i]
	t += "[i][color=#%s]%s[/color][/i]\n" % [_hex(pal.desc), it.desc]

	# comparação calculada com o equipado ("worn" é a própria ficha do equipado, aberta com Shift)
	if slot != "" and context not in ["equip", "worn"] and Game.can_wield(id):
		var cur: String = Game.equipment.get(slot, "")
		t += "[color=#%s]━━━━━━━━━━━━━━━━━━━━[/color]\n" % _hex(pal.rule)
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
				t += "  [color=#%s]Muda o ataque para %s[/color]\n" % [gold, ItemDB.CLASS_NAMES[ItemDB.weapon_class(id)].to_lower()]
			if cur != "":
				t += "[color=#%s]Segure Shift para ver o equipado ao lado[/color]\n" % dim

	# preço e dicas
	var price: int = it.price
	match context:
		"buy":
			t += "[color=#%s]Preço: %d ◆[/color]\n" % [gold if Game.gold >= price else bad, price]
			t += "[color=#%s]Clique direito ou duplo clique: comprar[/color]" % dim
		"sell":
			t += "[color=#%s]Vende por: %d ◆[/color]\n" % [gold, int(ceil(price * 0.5))]
			t += "[color=#%s]Clique direito ou duplo clique: vender[/color]" % dim
		"equip":
			t += "[color=#%s]Valor: %d ◆[/color]\n" % [dim, price]
			t += "[color=#%s]Clique direito: remover · arraste para a mochila[/color]" % dim
		"worn":
			t += "[color=#%s]Valor: %d ◆[/color]" % [dim, price]
		"admin":
			t += "[color=#%s]id: %s[/color]
" % [dim, id]
			t += "[color=#%s]Clique: adicionar à mochila[/color]" % dim
		_:
			t += "[color=#%s]Valor: %d ◆[/color]\n" % [dim, price]
			if slot != "" and Game.can_wield(id):
				t += "[color=#%s]Clique direito: equipar · arraste para o boneco[/color]" % dim
			elif Game.is_edible(id) or it.type == "consumable":
				t += "[color=#%s]Clique direito: usar[/color]" % dim
	return t.strip_edges()
