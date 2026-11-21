class_name TalentPanel
extends HBoxContainer
## Aba Talentos do menu do herói.
## Esquerda: pontos livres, onde redistribuir (Lina, na Guilda) e as habilidades da classe numa grade de 4
## colunas (como a barra de atalhos; cresce em linhas quando o kit passar de 4), com o detalhe da escolhida
## embaixo. Direita: os 3 ramos da classe em colunas, cada uma com um estandarte na cor do ramo, uma régua
## que enche com os pontos e marca onde abrem as linhas (3 e 6), e os talentos em cartões clicáveis
## (medalhão com os níveis em losangos, x/3, nome e o efeito).
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
## Bônus -> [texto, formato] para escrever o efeito de um talento num nível ("pct" = valor x 100 em %).
const FMT := {
	"damage": ["de dano", "pct"], "crit": ["de chance de crítico", "pct"], "lifesteal": ["de roubo de vida", "pctflat"],
	"defense": ["de defesa", "flat"], "max_hp": ["de vida máxima", "pct"], "regen": ["de vida por segundo", "flat"],
	"speed": ["de velocidade", "pct"], "cooldown": ["de recarga", "pct"], "mp_pct": ["de mana máxima", "pct"],
	"mp_regen": ["de mana por segundo", "flat"], "heal_power": ["de poder de cura", "pct"], "magnet": ["de alcance de coleta", "pct"],
	"gold": ["de ouro", "pct"], "ally_radius": ["de área de aliados", "pct"], "nova_stun": ["s de atordoamento", "sec"],
}
const FURY := Color(0.62, 0.16, 0.08)
const INK_GOOD := Color(0.1, 0.4, 0.12)
## Largura útil do nome do talento no cartão (coluna de um terço da página direita).
const NAME_W := 124.0

## id do talento -> cartão clicável (Button), rótulo "x/3" e medalhão (os testes leem daqui).
var buttons := {}
var level_labels := {}
var slots := {}
var points_label: Label
var reset_label: Label
## Habilidade aberta no detalhe (clique na grade troca).
var selected_ability := ""

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
			v.size_flags_stretch_ratio = 0.62   # habilidades numa coluna mais estreita que a árvore
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
	var n := Game.talent_points()
	var col := UITheme.INK_RED if n > 0 else UITheme.INK_DIM
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 10)
	points_label = UITheme.ink(str(n), 40, col, true)
	chip.add_child(points_label)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", -4)
	pv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pv.add_child(UITheme.ink("ponto livre" if n == 1 else "pontos livres", 18, col, true))
	pv.add_child(UITheme.ink("%d gastos de %d" % [maxi(0, Game.level - 1 - n), _tree_max()], 14, UITheme.INK_DIM))
	chip.add_child(pv)
	lv.add_child(chip)
	var cost := Game.talent_reset_cost()
	reset_label = UITheme.ink("Redistribuir: fale com a Lina, na Guilda (%s)." % ("grátis até o nível 5" if cost == 0 else "%d de ouro" % cost), 14, UITheme.INK_DIM)
	reset_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(reset_label)
	if Game.char_class == "":
		var none := UITheme.ink("Escolha uma classe para abrir a árvore de talentos.", 16, UITheme.INK_DIM)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lv.add_child(none)
		return
	lv.add_child(_gap(4))
	_abilities(lv)


func _tree_max() -> int:
	var n := 0
	for b in _branches():
		for t in b.get("talents", []):
			n += int(t.max)
	return n


## Habilidades da classe numa grade de 4 colunas (tecla no canto, nome embaixo; as que ainda não sabe dizem
## o nível) e o detalhe da escolhida embaixo: recarga ou custo, descrição e o talento que a melhora.
func _abilities(lv: VBoxContainer) -> void:
	lv.add_child(UITheme.ink_section("Habilidades", 20))
	var kit: Array = Game.ability_kit()
	if kit.is_empty():
		return
	if not selected_ability in kit:
		selected_ability = kit[0]
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	lv.add_child(grid)
	for id: String in kit:
		grid.add_child(_ability_slot(id, kit.size() > 4))
	lv.add_child(_gap(2))
	lv.add_child(_divider())
	lv.add_child(_ability_detail(selected_ability))


func _ability_slot(id: String, small: bool) -> Control:
	var sp: Dictionary = ItemDB.ABILITIES[id]
	var known := Game.knows_ability(id)
	var on := id == selected_ability
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	var s := ItemSlot.new(62 if small else 68)
	s.paper = true
	s.icon_kind = sp.icon
	s.icon_tex = ItemSlot.skill_art(id)
	s.key_text = str(sp.slot)
	s.dim = not known
	s.selected = on
	s.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	s.tooltip_text = "%s\n%s" % [sp.name, sp.desc]
	s.gui_input.connect(_on_ability_input.bind(id))
	v.add_child(s)
	var text: String = str(sp.name) if known else "nível %d" % int(sp.level)
	var nm := UITheme.ink(text, _fit(text, 14, 88.0), UITheme.INK if on else (UITheme.INK_DIM if known else UITheme.INK_RED), true)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nm)
	var mark := ColorRect.new()   # traço embaixo da escolhida (vazio nas outras, para alinhar)
	mark.color = UITheme.INK_RED if on else Color(0, 0, 0, 0)
	mark.custom_minimum_size = Vector2(40, 3)
	mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(mark)
	return v


func _on_ability_input(e: InputEvent, id: String) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and id != selected_ability:
		selected_ability = id
		refresh.call_deferred()


func _ability_detail(id: String) -> Control:
	var sp: Dictionary = ItemDB.ABILITIES[id]
	var known := Game.knows_ability(id)
	var ult: bool = sp.ultimate
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	v.add_child(top)
	var nm := UITheme.ink(str(sp.name), 24, (FURY if ult else UITheme.INK) if known else UITheme.INK_DIM, true)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	top.add_child(nm)
	var tag := ""
	var tag_col := UITheme.INK_DIM
	if not known:
		tag = "nível %d" % int(sp.level)
		tag_col = UITheme.INK_RED
	elif ult:
		tag = "ultimate"
		tag_col = FURY
	else:
		tag = "%ss" % _num(snappedf(float(sp.cooldown) * Game.cooldown_mult(), 0.1)).replace(".", ",")
		if int(sp.cost) > 0:
			tag = "%d MP · %s" % [int(sp.cost), tag]
	top.add_child(_chip(tag, tag_col))
	var desc := str(sp.desc).trim_prefix("Ultimate: ")
	var d := UITheme.ink(desc.left(1).to_upper() + desc.substr(1), 16, UITheme.INK if known else UITheme.INK_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	var boost := _boosting_talent(id)
	if not boost.is_empty():
		var t: Dictionary = boost.t
		var bc: Color = BRANCH_COLORS.get(boost.b.id, UITheme.INK)
		var l := int(Game.talents.get(t.id, 0))
		var bl := UITheme.ink("▲ Melhora com %s (%d/%d)" % [t.name, l, int(t.max)], 14, bc if l > 0 else Color(bc, 0.75))
		bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(bl)
	return v


## Talento da classe que mexe na habilidade (chave "ability_*:<id>"), com o ramo; {} se nenhum.
func _boosting_talent(ability_id: String) -> Dictionary:
	for b in _branches():
		for t in b.get("talents", []):
			for k: String in t.get("add", {}):
				if k.begins_with("ability_") and k.get_slice(":", 1) == ability_id:
					return {"t": t, "b": b}
	return {}


# ================================================================ página direita
func _build_right() -> void:
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right.add_child(cols)
	for b in _branches():
		cols.add_child(_branch_column(b))


func _branches() -> Array:
	return Balance.tables.get_table("talents").get(Game.char_class, {}).get("branches", [])


func _branch_column(b: Dictionary) -> Control:
	var color: Color = BRANCH_COLORS.get(b.id, UITheme.INK)
	var pts := 0
	for t in b.get("talents", []):
		pts += int(Game.talents.get(t.id, 0))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	var ban := Banner.new()
	ban.col = color
	ban.title = str(b.name)
	ban.sub = "%d %s" % [pts, "ponto" if pts == 1 else "pontos"]
	v.add_child(ban)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(h)
	var g := Gauge.new()
	g.col = color
	g.pts = pts
	g.top = CharRules.row_requirement(3) + 3
	g.tooltip_text = "%d pontos neste ramo: a linha 2 abre com %d, a linha 3 com %d" % [pts, CharRules.row_requirement(2), CharRules.row_requirement(3)]
	h.add_child(g)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 8)
	h.add_child(rows)
	for t in b.get("talents", []):
		rows.add_child(_talent_card(t, color, pts))
	return v


## Cartão do talento: o próprio cartão é o botão (clique gasta 1 ponto). Medalhão com os níveis, x/3, nome
## e o efeito (por nível enquanto está em 0).
func _talent_card(t: Dictionary, color: Color, pts: int) -> Control:
	var id: String = t.id
	var lvl := int(Game.talents.get(id, 0))
	var mx := int(t.max)
	var need := CharRules.row_requirement(int(t.row))
	var locked := pts < need
	var full := lvl >= mx
	var card := Button.new()
	card.custom_minimum_size.y = 132
	card.focus_mode = Control.FOCUS_NONE
	var base := UITheme._box(Color(color, 0.08 if lvl > 0 else 0.0), Color(color, 0.6) if lvl > 0 else Color(UITheme.INK, 0.2), 1, 5, 6, 5)
	var hover := UITheme._box(Color(color, 0.14), Color(color, 0.9), 2, 5, 6, 5)
	for s in ["normal", "disabled", "focus"]:
		card.add_theme_stylebox_override(s, base)
	card.add_theme_stylebox_override("hover", hover)
	card.add_theme_stylebox_override("pressed", hover)
	card.disabled = locked or full or Game.talent_points() <= 0
	card.mouse_default_cursor_shape = Control.CURSOR_ARROW if card.disabled else Control.CURSOR_POINTING_HAND
	card.tooltip_text = _tip(t, lvl, locked, need)
	card.pressed.connect(Game.learn_talent.bind(id))
	buttons[id] = card
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 6)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	v.add_child(top)
	var icon := TalentIcon.new()
	icon.setup(_icon(t), color, lvl, mx, locked, 44.0)
	top.add_child(icon)
	slots[id] = icon
	var lv_l := UITheme.ink("%d/%d" % [lvl, mx], 22, INK_GOOD if full else (color if lvl > 0 else UITheme.INK_DIM), true)
	lv_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(lv_l)
	level_labels[id] = lv_l
	var nm := UITheme.ink(str(t.name), _fit(str(t.name), 15, NAME_W), UITheme.INK if not locked else UITheme.INK_DIM, true)
	nm.clip_text = true
	v.add_child(nm)
	var d := UITheme.ink(_effect(t, maxi(lvl, 1)) + ("" if lvl > 0 else " por nível"), 13, UITheme.INK_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	for c: Control in [top, nm, d, lv_l]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return card


func _tip(t: Dictionary, lvl: int, locked: bool, need: int) -> String:
	var lines: Array[String] = ["%s (%d/%d)" % [t.name, lvl, int(t.max)], str(t.desc)]
	if lvl > 0:
		lines.append("Agora: " + _effect(t, lvl))
	if lvl < int(t.max):
		lines.append("Próximo nível: " + _effect(t, lvl + 1))
	if locked:
		lines.append("Linha %d: abre com %d pontos gastos neste ramo." % [int(t.row), need])
	elif lvl >= int(t.max):
		lines.append("Completo.")
	elif Game.talent_points() <= 0:
		lines.append("Sem pontos livres: cada nível dá 1.")
	else:
		lines.append("Clique para gastar 1 ponto.")
	return "\n".join(lines)


## Efeito do talento com `lvl` níveis ("+8% de dano", "+4 s de Fúria Picante").
func _effect(t: Dictionary, lvl: int) -> String:
	var parts: Array[String] = []
	for k: String in t.get("add", {}):
		var v: float = float(t.add[k]) * lvl
		if k.begins_with("ability_"):
			var ab_name := str(ItemDB.ABILITIES.get(k.get_slice(":", 1), {}).get("name", "habilidade"))
			if k.begins_with("ability_time"):
				parts.append("+%s s de %s" % [_num(v), ab_name])
			else:
				parts.append("+%d%% de dano de %s" % [roundi(v * 100), ab_name])
			continue
		var f: Array = FMT.get(k, [k, "flat"])
		var sgn := "+" if v >= 0 else "−"
		match f[1]:
			"pct": parts.append("%s%d%% %s" % [sgn, roundi(absf(v) * 100), f[0]])
			"pctflat": parts.append("%s%s%% %s" % [sgn, _num(absf(v)), f[0]])
			"sec": parts.append("%s%s%s" % [sgn, _num(absf(v)), f[0]])
			_: parts.append("%s%s %s" % [sgn, _num(absf(v)), f[0]])
	return ", ".join(parts) if parts.size() > 0 else str(t.desc)


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


# ================================================================ peças
static func _num(v: float) -> String:
	return str(roundi(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v


## Maior fonte (até `fs`) em que `text` cabe em `w` px.
static func _fit(text: String, fs: int, w: float) -> int:
	while fs > 11 and UITheme.serif().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w:
		fs -= 1
	return fs


static func _chip(text: String, c: Color) -> Control:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UITheme._box(Color(c, 0.1), Color(c, 0.55), 1, 9, 8, 1))
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pc.add_child(UITheme.ink(text, 13, c, true))
	return pc


static func _divider() -> Control:
	var c := ColorRect.new()
	c.color = Color(UITheme.INK, 0.18)
	c.custom_minimum_size = Vector2(0, 1)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _clear(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


## Medalhão do talento: aro na cor do ramo, o ícone no meio, cadeado quando a linha não abriu e os níveis
## como losangos embaixo (cheios até o nível atual).
class TalentIcon extends Control:
	var kind := "orb"
	var col := Color.WHITE
	var lvl := 0
	var mx := 3
	var dim := false
	var d := 44.0

	func setup(k: String, c: Color, l: int, m: int, locked: bool, dia: float) -> void:
		kind = k
		col = c
		lvl = l
		mx = m
		dim = locked
		d = dia
		custom_minimum_size = Vector2(dia + 8, dia + 16)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, d * 0.5 + 2)
		var r := d * 0.5
		var ring := col if lvl > 0 else (Color(UITheme.INK, 0.35) if dim else Color(UITheme.INK, 0.6))
		draw_circle(c, r, ring.darkened(0.25))
		var fill := Color(0.86, 0.78, 0.62) if not dim else Color(0.78, 0.72, 0.6)
		if lvl > 0:
			fill = fill.lerp(col, 0.18)
		draw_circle(c, r - (5 if lvl > 0 else 3), fill)
		if lvl >= mx:
			draw_arc(c, r - 7, 0, TAU, 48, Color(0.75, 0.55, 0.15), 1.5, true)
		var ir := Rect2(c - Vector2(r, r) * 0.6, Vector2(r, r) * 1.2)
		IconPainter.draw(self, kind, col.lightened(0.25) if not dim else Color(0.55, 0.5, 0.45), ir, dim)
		if dim:
			var p := c + Vector2(r * 0.62, r * 0.62)
			var s := r * 0.3
			draw_circle(p, s * 1.25, Color(0.86, 0.78, 0.62))
			draw_arc(p - Vector2(0, s * 0.3), s * 0.45, PI, TAU, 12, UITheme.INK, 2.0, true)
			draw_rect(Rect2(p - Vector2(s * 0.65, s * 0.25), Vector2(s * 1.3, s * 0.9)), UITheme.INK)
		var y := c.y + r + 4
		for i in mx:
			var x := c.x + (i - (mx - 1) * 0.5) * 13.0
			var pts := PackedVector2Array([Vector2(x, y - 5), Vector2(x + 5, y), Vector2(x, y + 5), Vector2(x - 5, y)])
			draw_colored_polygon(pts, col if i < lvl else Color(0.9, 0.84, 0.7))
			pts.append(pts[0])
			draw_polyline(pts, UITheme.INK if i < lvl else Color(UITheme.INK, 0.5), 1.2, true)


## Estandarte de tecido na cor do ramo, com a ponta em rabo de andorinha, o nome e os pontos do ramo.
class Banner extends Control:
	var col := Color.WHITE
	var title := ""
	var sub := ""

	func _init() -> void:
		custom_minimum_size = Vector2(0, 74)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(-4, 0, w + 8, 6), Color(0.35, 0.22, 0.1))   # haste
		var cloth := PackedVector2Array([Vector2(4, 6), Vector2(w - 4, 6), Vector2(w - 4, h), Vector2(w * 0.5, h - 14), Vector2(4, h)])
		draw_colored_polygon(cloth, col.darkened(0.05))
		var ol := cloth.duplicate()
		ol.append(cloth[0])
		draw_polyline(ol, col.darkened(0.5), 2.0, true)
		draw_line(Vector2(10, 12), Vector2(w - 10, 12), Color(1, 0.85, 0.5, 0.6), 1.5)
		var f := UITheme.serif()
		var fs := TalentPanel._fit(title, 22, w - 16)
		var tw := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2((w - tw) * 0.5, 36), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UITheme.ON_LEATHER)
		var sw := f.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(f, Vector2((w - sw) * 0.5, 54), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(UITheme.ON_LEATHER, 0.85))


## Régua vertical do ramo: enche com os pontos e marca 3 e 6 (onde abrem as linhas 2 e 3), cada marco uma
## bolinha numerada que se pinta na cor do ramo quando a linha abre.
class Gauge extends Control:
	var col := Color.WHITE
	var pts := 0
	var top := 9

	func _init() -> void:
		custom_minimum_size = Vector2(26, 0)
		size_flags_vertical = Control.SIZE_EXPAND_FILL

	func _draw() -> void:
		var x := 8.0
		var h := size.y - 10
		draw_rect(Rect2(x - 4, 4, 8, h), Color(UITheme.INK, 0.12))
		draw_rect(Rect2(x - 4, 4, 8, h * clampf(float(pts) / top, 0, 1)), col)
		draw_rect(Rect2(x - 4, 4, 8, h), Color(UITheme.INK, 0.6), false, 1.0)
		for m: int in [CharRules.row_requirement(2), CharRules.row_requirement(3)]:
			var y: float = 4 + h * float(m) / top
			var ok := pts >= m
			draw_line(Vector2(x - 6, y), Vector2(x + 6, y), UITheme.INK, 2.0)
			draw_circle(Vector2(x + 13, y), 7.5, col if ok else Color(0.86, 0.78, 0.62))
			draw_arc(Vector2(x + 13, y), 7.5, 0, TAU, 20, UITheme.INK, 1.2, true)
			draw_string(UITheme.serif(), Vector2(x + 9.5, y + 5), str(m), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.ON_LEATHER if ok else UITheme.INK)
