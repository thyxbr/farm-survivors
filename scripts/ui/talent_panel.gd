class_name TalentPanel
extends HBoxContainer
## Aba Talentos do menu do herói (abertura do livro): página esquerda com os pontos livres, como a árvore
## abre, os bônus em vigor e onde redistribuir (Lina, na Guilda); página direita com os 3 ramos da classe
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
	if Game.char_class == "":
		var none := UITheme.ink("Escolha uma classe para abrir a árvore de talentos.", 16, UITheme.INK_DIM)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lv.add_child(none)
	lv.add_child(_gap(2))
	lv.add_child(UITheme.ink_section("Como funciona", 20))
	var how := UITheme.ink("Três ramos, três linhas cada. A linha 2 abre com 3 pontos gastos no ramo; a linha 3, com 6. "
		+ "Cada talento vai até 3/3 e vale na hora.", 15)
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(how)
	lv.add_child(_gap(2))
	lv.add_child(UITheme.ink_section("Em vigor", 20))
	var any := false
	for d in CharRules.talent_defs(Balance.tables, Game.char_class):
		var lvl := int(Game.talents.get(d.id, 0))
		if lvl <= 0:
			continue
		any = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var strip := ColorRect.new()
		strip.color = BRANCH_COLORS.get(d.branch, UITheme.INK)
		strip.custom_minimum_size = Vector2(4, 0)
		row.add_child(strip)
		row.add_child(UITheme.ink("%s %d/%d" % [d.name, lvl, int(d.max)], 15, UITheme.INK, true))
		var dl := UITheme.ink(str(d.desc), 13, UITheme.INK_DIM)
		dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		dl.clip_text = true
		dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dl)
		lv.add_child(row)
	if not any:
		lv.add_child(UITheme.ink("Nenhum talento aprendido ainda.", 15, UITheme.INK_DIM))
	lv.add_child(_gap(2))
	lv.add_child(UITheme.ink_section("Redistribuir", 20))
	var cost := Game.talent_reset_cost()
	var price := "grátis até o nível 5" if cost == 0 else "%d de ouro (50 × nível)" % cost
	reset_label = UITheme.ink("Fale com a Lina, na Guilda, para devolver todos os pontos e escolher de novo. Custo agora: %s." % price, 15)
	reset_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(reset_label)


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
	var line := ColorRect.new()
	line.color = Color(color, 0.7)
	line.custom_minimum_size = Vector2(0, 2)
	v.add_child(line)
	for t in b.get("talents", []):
		v.add_child(_talent_card(t, color, in_branch))
	return v


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
