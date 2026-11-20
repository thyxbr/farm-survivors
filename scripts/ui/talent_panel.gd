class_name TalentPanel
extends HBoxContainer
## Aba Talentos do menu do herói: à esquerda os pontos livres, onde redistribuir (Lina, na Guilda) e as
## habilidades da classe; à direita os 3 ramos da classe
## em colunas, cada talento um cartão com ícone na cor do ramo, nível x/3 e o botão "+".
## O pedido vai por Game.learn_talent (Econ: no solo o serviço local, online o servidor decide); a aba só
## redesenha quando o estado volta (refresh). Regras: CharRules (talentos) + data/balance/talents.json.

## Cor de cada ramo (tinta sobre o papel); o ícone usa a mesma cor, mais viva.
const BRANCH_COLORS := {
	"warrior_fury": Color(0.62, 0.16, 0.08), "warrior_wall": Color(0.2, 0.3, 0.52), "warrior_storm": Color(0.35, 0.2, 0.55),
	"archer_precision": Color(0.55, 0.38, 0.05), "archer_hunter": Color(0.2, 0.4, 0.15), "archer_wind": Color(0.1, 0.4, 0.45),
	"mage_fire": Color(0.66, 0.2, 0.05), "mage_frost": Color(0.12, 0.33, 0.6), "mage_arcane": Color(0.42, 0.18, 0.58),
	"healer_light": Color(0.58, 0.42, 0.04), "healer_protection": Color(0.18, 0.32, 0.56), "healer_grace": Color(0.14, 0.45, 0.25),
}
## Desenho do ícone pela chave de bônus (IconPainter); "ability_*" usa o ícone da habilidade.
const STAT_ICONS := {
	"crit": "focus", "lifesteal": "fury", "defense": "shield", "max_hp": "chest", "regen": "heal",
	"speed": "boot", "cooldown": "orb", "mp_pct": "potion", "mp_regen": "orb", "heal_power": "heal",
	"nova_stun": "frost", "magnet": "ring", "gold": "ring", "ally_radius": "heal",
}
const WEAPON_ICONS := {"warrior": "sword", "archer": "bow", "mage": "staff", "healer": "staff"}
const INK_GOOD := Color(0.1, 0.4, 0.12)
const ICON := 50.0
## Largura útil do nome dentro do cartão (coluna de um terço da página menos as margens).
const NAME_W := 160.0

## id do talento -> botão "+", rótulo "x/3" e o ícone (os testes leem daqui).
var buttons := {}
var level_labels := {}
var slots := {}
var points_label: Label
var reset_label: Label

var _left: VBoxContainer
var _right: VBoxContainer


func _init() -> void:
	add_theme_constant_override("separation", int(BookLayout.COL_GAP))
	for i in 2:
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 8)
		add_child(v)
		if i == 0:
			_left = v
		else:
			_right = v


func refresh() -> void:
	_clear(_left)
	_clear(_right)
	buttons.clear()
	level_labels.clear()
	slots.clear()
	_build_left()
	_build_right()


# ================================================================ página esquerda
func _build_left() -> void:
	var lv := _left
	var cls_name: String = Game.class_display_name() if Game.char_class != "" else "Sem classe"
	var title := UITheme.ink("Talentos · %s" % cls_name, 30, UITheme.INK, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.clip_text = true
	lv.add_child(title)
	# pontos livres no topo, em quadro de tinta vermelha quando há o que gastar
	var n := Game.talent_points()
	var chip := PanelContainer.new()
	var col := UITheme.INK_RED if n > 0 else UITheme.INK_DIM
	chip.add_theme_stylebox_override("panel", UITheme._box(Color(col, 0.08), col, 1, 6, 14, 6))
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 12)
	chip.add_child(ch)
	var big := UITheme.ink(str(n), 34, col, true)
	big.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ch.add_child(big)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", -2)
	pv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	points_label = UITheme.ink("%d %s" % [n, "ponto livre" if n == 1 else "pontos livres"], 18, col, true)
	pv.add_child(points_label)
	var spent := maxi(0, Game.level - 1 - n)
	pv.add_child(UITheme.ink("%d gastos · 1 ponto por nível a partir do 2" % spent, 14, UITheme.INK_DIM))
	ch.add_child(pv)
	lv.add_child(chip)
	var cost := Game.talent_reset_cost()
	var price := "grátis até o nível 5" if cost == 0 else "%d de ouro" % cost
	reset_label = UITheme.ink("Redistribuir: fale com a Lina, na Guilda (%s)." % price, 14, UITheme.INK_DIM)
	reset_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(reset_label)
	if Game.char_class == "":
		var none := UITheme.ink("Escolha uma classe para abrir a árvore de talentos.", 16, UITheme.INK_DIM)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lv.add_child(none)
		return
	lv.add_child(_gap(4))
	_abilities(lv)


## Habilidades da classe (ícone com a tecla, custo e recarga, descrição; as que ainda não sabe dizem o nível).
func _abilities(lv: VBoxContainer) -> void:
	lv.add_child(UITheme.ink_section("Habilidades", 20))
	for id in Game.ability_kit():
		var sp: Dictionary = ItemDB.ABILITIES[id]
		var known := Game.knows_ability(id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var s := ItemSlot.new(50)
		s.paper = true
		s.icon_kind = sp.icon
		s.icon_tex = ItemSlot.skill_art(id)
		s.key_text = str(sp.slot)
		s.dim = not known
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(s)
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_theme_constant_override("separation", 0)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		head.add_child(UITheme.ink(sp.name, 17, UITheme.INK if known else UITheme.INK_DIM, true))
		head.add_child(UITheme.spacer())
		var meta := "%s · %s" % [("%d MP" % sp.cost) if sp.cost > 0 else "sem custo",
			"ultimate (fúria)" if sp.ultimate else "recarga %.1fs" % (sp.cooldown * Game.cooldown_mult())]
		head.add_child(UITheme.ink(meta, 14, UITheme.INK_DIM))
		tv.add_child(head)
		var d := UITheme.ink(sp.desc, 14, UITheme.INK if known else UITheme.INK_DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tv.add_child(d)
		if not known:
			tv.add_child(UITheme.ink("Aprende no nível %d" % sp.level, 13, UITheme.INK_RED))
		row.add_child(tv)
		lv.add_child(row)


# ================================================================ página direita
func _build_right() -> void:
	var tree: Dictionary = Balance.tables.get_table("talents").get(Game.char_class, {})
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 10)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right.add_child(cols)
	for b in tree.get("branches", []):
		cols.add_child(_branch_column(b))


func _branch_column(b: Dictionary) -> Control:
	var color: Color = BRANCH_COLORS.get(b.id, UITheme.INK)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	var name_l := UITheme.ink(str(b.name), 22, color, true)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_l)
	var in_branch := 0
	for t in b.get("talents", []):
		in_branch += int(Game.talents.get(t.id, 0))
	var pl := UITheme.ink("%d %s no ramo" % [in_branch, "ponto" if in_branch == 1 else "pontos"], 13, UITheme.INK_DIM)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(pl)
	# barra do ramo: pontos gastos até abrir a última linha
	var top_need := CharRules.row_requirement(3)
	var bar := UITheme.ink_bar(color, 0, 6)
	bar.max_value = maxi(top_need, 1)
	bar.value = mini(in_branch, top_need)
	bar.tooltip_text = "%d de %d pontos para abrir a última linha do ramo" % [mini(in_branch, top_need), top_need]
	v.add_child(bar)
	var first := true
	for t in b.get("talents", []):
		if not first:
			v.add_child(_connector(color, in_branch >= CharRules.row_requirement(int(t.row))))
		first = false
		v.add_child(_talent_card(t, color, in_branch))
	return v


## Traço vertical entre dois talentos do ramo (a árvore): cheio na cor do ramo quando a linha de baixo já
## abriu, apagado quando ainda falta ponto.
func _connector(color: Color, open: bool) -> Control:
	var c := CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := ColorRect.new()
	line.color = Color(color, 0.85) if open else Color(UITheme.INK, 0.2)
	line.custom_minimum_size = Vector2(4, 10)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(line)
	return c


func _talent_card(t: Dictionary, color: Color, in_branch: int) -> Control:
	var id: String = t.id
	var lvl := int(Game.talents.get(id, 0))
	var mx := int(t.max)
	var need := CharRules.row_requirement(int(t.row))
	var locked := in_branch < need
	var full := lvl >= mx
	var card := PanelContainer.new()
	var border := Color(color, 0.85) if lvl > 0 else Color(UITheme.INK, 0.35)
	card.add_theme_stylebox_override("panel", UITheme._box(Color(color, 0.07 if lvl > 0 else 0.03), border, 2 if lvl > 0 else 1, 5, 8, 6))
	card.tooltip_text = _tip(t, lvl, locked, need)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	card.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	v.add_child(top)
	var s := ItemSlot.new(ICON)
	s.paper = true
	s.icon_kind = _icon(t)
	s.icon_color = color.lightened(0.25)
	s.dim = locked
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(s)
	slots[id] = s
	var lv_col := INK_GOOD if full else (UITheme.INK_DIM if locked else UITheme.INK)
	var lv_l := UITheme.ink("%d/%d" % [lvl, mx], 22, lv_col, true)
	lv_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(lv_l)
	level_labels[id] = lv_l
	var plus := UITheme.button("+", Game.learn_talent.bind(id), 36)
	plus.custom_minimum_size.y = 36
	plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plus.disabled = locked or full or Game.talent_points() <= 0
	plus.tooltip_text = card.tooltip_text
	top.add_child(plus)
	buttons[id] = plus
	var nm := UITheme.ink(str(t.name), _name_size(str(t.name)), UITheme.INK if not locked else UITheme.INK_DIM, true)
	nm.clip_text = true
	nm.custom_minimum_size.y = 26   # nome encolhido não desalinha os cartões da linha
	v.add_child(nm)
	var sub := UITheme.ink(str(t.desc), 13, UITheme.INK_DIM)
	if locked:
		sub = UITheme.ink("Abre com %d pontos no ramo" % need, 13, UITheme.INK_RED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size.y = 34
	v.add_child(sub)
	return card


## Fonte do nome do talento: 16, encolhendo até caber na coluna (nomes longos como "Guarda Duradoura").
func _name_size(text: String) -> int:
	var fs := 16
	while fs > 12 and UITheme.serif().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > NAME_W:
		fs -= 1
	return fs


func _tip(t: Dictionary, lvl: int, locked: bool, need: int) -> String:
	var lines: Array[String] = ["%s (%d/%d)" % [t.name, lvl, int(t.max)], str(t.desc)]
	if locked:
		lines.append("Linha %d: abre com %d pontos gastos neste ramo." % [int(t.row), need])
	elif lvl >= int(t.max):
		lines.append("Completo.")
	elif Game.talent_points() <= 0:
		lines.append("Sem pontos livres: cada nível dá 1.")
	else:
		lines.append("Clique em + para gastar 1 ponto.")
	return "\n".join(lines)


func _icon(t: Dictionary) -> String:
	for k: String in t.get("add", {}):
		if k.begins_with("ability_"):
			var ab: Dictionary = ItemDB.ABILITIES.get(k.get_slice(":", 1), {})
			return str(ab.get("icon", "orb"))
		if k == "damage":
			return WEAPON_ICONS.get(Game.char_class, "sword")
		if STAT_ICONS.has(k):
			return STAT_ICONS[k]
	return "orb"


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _clear(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
