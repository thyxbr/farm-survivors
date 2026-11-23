class_name BestiaryPanel
extends VBoxContainer
## Aba Bestiário do menu do herói (tecla B), no molde da Cyclopedia do Tibia:
## - Grade: cartões de 5 em 5 colunas, paginados, com filtro por família. Cada cartão tem o nome (ou
##   "Desconhecida"), o retrato 3D do monstro (MonsterPortraits; silhueta escura enquanto não foi abatido) e o
##   estágio "x / 3" ou o ✓ da entrada completa.
## - Ficha (clique num cartão conhecido): retrato grande, abates numa régua de 3 segmentos (um por estágio),
##   atributos no nível de referência, habilidades e regiões (estágio 2) e o espólio em fileiras por raridade,
##   com "?" no que ainda não foi revelado (BestiaryRules).
## Só lê Game.bestiary; quem grava é o CharRules.kill (servidor/solo).

const COLS := 5
const ROWS_PER_PAGE := 3
const CARD := Vector2(172, 168)
const PORTRAIT := 104.0
const BIG := 190.0
const INK_GOOD := Color(0.1, 0.4, 0.12)
const INK_GOLD := Color(0.45, 0.27, 0.02)
const SILHOUETTE := Color(0.16, 0.11, 0.07, 0.9)
## Espaços por fileira de espólio (o resto fica vazio, como na Cyclopedia).
const LOOT_SLOTS := 15
static var _sil_mat: ShaderMaterial
const STARS := {"comum": 1, "forte": 2, "elite": 3, "chefe": 4}
const BAND_NAMES := ["", "Comum", "Incomum", "Raro", "Muito raro"]
## Habilidade especial -> texto (campos do enemies.json que mudam o jeito de lutar).
const SHOTS := {"bolt": "Lança esferas sombrias de longe", "ice": "Cospe estilhaços de gelo", "acid": "Cospe ácido"}

var tooltip: ItemTooltip
var _family := ""            # filtro ("" = todas)
var _page := 0
var _sel := ""               # "" = grade; senão a ficha do tipo
var _body: VBoxContainer
var _filters: HBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_body)
	refresh()


func refresh() -> void:
	if _body == null:
		return
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	if _sel != "" and BestiaryRules.kills_of(Game.bestiary, _sel) > 0:
		_build_entry(_sel)
	else:
		_sel = ""
		_build_grid()


# ================================================================ grade
func _kinds() -> Array:
	var bt: BalanceTables = Balance.tables
	if _family == "":
		return BestiaryRules.all_kinds(bt)
	return BestiaryRules.families(bt).get(_family, {}).get("kinds", []).filter(
		func(k): return bt.get_table("enemies").has(k))


func _build_grid() -> void:
	var bt: BalanceTables = Balance.tables
	var sum := BestiaryRules.summary(bt, Game.bestiary)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	var info := UITheme.ink("%d de %d criaturas conhecidas   ·   %d completas   ·   %d pontos de caçador"
		% [sum.known, sum.total, sum.complete, sum.points], 16, UITheme.INK_DIM)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(info)
	_body.add_child(head)
	# filtro por família
	_filters = HBoxContainer.new()
	_filters.add_theme_constant_override("separation", 4)
	var group := ButtonGroup.new()
	_filters.add_child(_filter_button("Todas", "", group))
	for f in BestiaryRules.families(bt):
		var kinds: Array = BestiaryRules.families(bt)[f].kinds
		var done := kinds.filter(func(k): return BestiaryRules.stage(bt, k, BestiaryRules.kills_of(Game.bestiary, k)) >= 3).size()
		_filters.add_child(_filter_button("%s %d/%d" % [BestiaryRules.families(bt)[f].name, done, kinds.size()], str(f), group))
	_body.add_child(_filters)
	# cartões da página
	var kinds := _kinds()
	var per := COLS * ROWS_PER_PAGE
	var pages := maxi(1, ceili(kinds.size() / float(per)))
	_page = clampi(_page, 0, pages - 1)
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for i in range(_page * per, mini(kinds.size(), (_page + 1) * per)):
		grid.add_child(_card(kinds[i]))
	# a grade guarda a altura de 3 fileiras: a janela não pula de tamanho entre páginas
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(COLS * (CARD.x + 10), ROWS_PER_PAGE * (CARD.y + 10))
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.add_child(grid)
	_body.add_child(holder)
	# paginação
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 14)
	var prev := Button.new()
	prev.text = "◀"
	prev.disabled = _page <= 0
	prev.custom_minimum_size = Vector2(44, 34)
	prev.pressed.connect(func() -> void: _page -= 1; refresh())
	var next := Button.new()
	next.text = "▶"
	next.disabled = _page >= pages - 1
	next.custom_minimum_size = Vector2(44, 34)
	next.pressed.connect(func() -> void: _page += 1; refresh())
	var lbl := UITheme.ink("%d / %d" % [_page + 1, pages], 17, UITheme.INK, true)
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nav.add_child(prev)
	nav.add_child(lbl)
	nav.add_child(next)
	_body.add_child(nav)


func _filter_button(text: String, fam: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.button_pressed = fam == _family
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	b.custom_minimum_size.y = 30
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void: _family = fam; _page = 0; refresh())
	return b


## Cartão: nome no topo, retrato no meio, estágio embaixo. Desconhecido = silhueta e "?".
func _card(kind: String) -> Control:
	var bt: BalanceTables = Balance.tables
	var n := BestiaryRules.kills_of(Game.bestiary, kind)
	var st := BestiaryRules.stage(bt, kind, n)
	var known := n > 0
	var p := PanelContainer.new()
	p.custom_minimum_size = CARD
	p.add_theme_stylebox_override("panel", UITheme.ink_inset(6))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var label := UITheme.ink(str(bt.get_table("enemies")[kind].get("name", kind)) if known else "Desconhecida", 15,
		UITheme.INK if known else UITheme.INK_DIM, true)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(label)
	var pic := _portrait(kind, PORTRAIT, not known)
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(pic)
	var foot: Label
	if not known:
		foot = UITheme.ink("?", 18, UITheme.INK_DIM, true)
	elif st >= 3:
		foot = UITheme.ink("✓ completa", 16, INK_GOOD, true)
	else:
		foot = UITheme.ink("%d / 3" % st, 17, UITheme.INK, true)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(foot)
	if known:
		p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		p.tooltip_text = "%d abates — clique para ver a ficha" % n
		p.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_sel = kind
				refresh.call_deferred())
	else:
		p.tooltip_text = "Derrote esta criatura para registrá-la."
	return p


## Retrato do monstro (silhueta = escurecido); enquanto o retrato 3D não chega, um quadro vazio com "?".
func _portrait(kind: String, size: float, dark: bool) -> Control:
	var box := CenterContainer.new()
	box.custom_minimum_size = Vector2(size, size)
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(size, size)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if dark:
		tr.material = _silhouette()
	box.add_child(tr)
	var tex := MonsterPortraits.portrait(kind, func() -> void:
		if is_instance_valid(tr):
			tr.texture = MonsterPortraits.portrait(kind, Callable()))
	tr.texture = tex
	return box


## Silhueta: só o contorno do retrato (alfa), pintado de tinta escura.
static func _silhouette() -> ShaderMaterial:
	if _sil_mat == null:
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\nuniform vec4 ink : source_color;\n" \
			+ "void fragment() { COLOR = vec4(ink.rgb, texture(TEXTURE, UV).a * ink.a); }"
		_sil_mat = ShaderMaterial.new()
		_sil_mat.shader = sh
		_sil_mat.set_shader_parameter("ink", SILHOUETTE)
	return _sil_mat


# ================================================================ ficha
func _build_entry(kind: String) -> void:
	var bt: BalanceTables = Balance.tables
	var e: Dictionary = bt.get_table("enemies").get(kind, {})
	var entry: Dictionary = Game.bestiary.get(kind, {})
	var n := int(entry.get("n", 0))
	var st := BestiaryRules.stage(bt, kind, n)
	var cls := BestiaryRules.class_of(bt, kind)
	var fam := BestiaryRules.family_of(bt, kind)
	# barra do topo: voltar, nome, família e classe, anterior/próxima conhecida
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var back := Button.new()
	back.text = "◀ Voltar"
	back.custom_minimum_size = Vector2(110, 34)
	back.pressed.connect(func() -> void: _sel = ""; refresh())
	top.add_child(back)
	var title := UITheme.ink(str(e.get("name", kind)), 28, UITheme.INK, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var known: Array = BestiaryRules.all_kinds(bt).filter(func(k): return BestiaryRules.kills_of(Game.bestiary, k) > 0)
	var at := known.find(kind)
	for step in [-1, 1]:
		var b := Button.new()
		b.text = "◀" if step < 0 else "▶"
		b.custom_minimum_size = Vector2(44, 34)
		b.disabled = known.size() <= 1
		b.tooltip_text = "Criatura conhecida anterior" if step < 0 else "Próxima criatura conhecida"
		b.pressed.connect(func() -> void: _sel = known[posmod(at + step, known.size())]; refresh())
		top.add_child(b)
	_body.add_child(top)
	_body.add_child(UITheme.ink("%s  ·  %s  ·  %s" % [BestiaryRules.families(bt).get(fam, {}).get("name", fam),
		BestiaryRules.class_label(bt, kind), ["Desconhecida", "Estágio 1 de 3", "Estágio 2 de 3", "Entrada completa"][st]],
		15, INK_GOOD if st >= 3 else INK_GOLD))
	# linha principal: retrato | abates + atributos | habilidades + regiões
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UITheme.ink_inset(8))
	frame.add_child(_portrait(kind, BIG, false))
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(frame)
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 6)
	mid.custom_minimum_size.x = 330
	mid.add_child(UITheme.ink_section("Abates: %d" % n, 18))
	mid.add_child(_kill_bar(bt, kind, n, st))
	var goal := BestiaryRules.next_goal(bt, kind, n)
	mid.add_child(UITheme.ink("faltam %d para o estágio %d" % [goal - n, st + 1] if goal > 0 else "todas as informações reveladas",
		14, UITheme.INK_DIM if goal > 0 else INK_GOOD))
	mid.add_child(_stats(bt, kind, e, st, cls))
	row.add_child(mid)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_child(UITheme.ink_section("Habilidades", 18))
	side.add_child(_text_box(_abilities(bt, kind, e) if st >= 2 else "", "Revelado no estágio 2"))
	side.add_child(UITheme.ink_section("Onde encontrar", 18))
	var regions: Dictionary = bt.get_table("regions")
	var names: Array = []
	for a in entry.get("a", []):
		names.append("• " + str(regions.get(a, {}).get("name", a)))
	side.add_child(_text_box(("\n".join(names) if not names.is_empty() else "Fora das regiões com nome do mapa.")
		if st >= 2 else "", "Revelado no estágio 2"))
	row.add_child(side)
	_body.add_child(row)
	# elementos (estágio 2, como as resistências da Cyclopedia)
	_body.add_child(UITheme.ink_section("Elementos", 18))
	_body.add_child(_elements(bt, kind, st >= 2))
	# espólio por raridade
	_body.add_child(UITheme.ink_section("Espólio", 18))
	var view := BestiaryRules.loot_view(bt, kind, entry)
	var table := GridContainer.new()
	table.columns = 2
	table.add_theme_constant_override("h_separation", 14)
	table.add_theme_constant_override("v_separation", 6)
	for band in [1, 2, 3, BestiaryRules.SECRET]:
		var rows: Array = view.filter(func(r): return int(r.band) == band)
		var lbl := UITheme.ink(BAND_NAMES[band] + ":", 16, UITheme.INK, true)
		lbl.custom_minimum_size.x = 120
		lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		table.add_child(lbl)
		var slots := HBoxContainer.new()
		slots.add_theme_constant_override("separation", 6)
		for r in rows:
			slots.add_child(_loot_slot(r))
		# completa a fileira com espaços vazios, como na Cyclopedia
		for i in maxi(0, LOOT_SLOTS - rows.size()):
			slots.add_child(_empty_slot())
		table.add_child(slots)
	_body.add_child(table)
	if st >= 3:
		var gold: Array = e.get("gold", [0, 0])
		var g := UITheme.ink("Também deixa %d a %d de ouro (mais nos níveis altos) e equipamento do nível da região."
			% [int(gold[0]), int(gold[1])], 14, UITheme.INK_DIM)
		g.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(g)


## Afinidade de cada elemento: nome, régua (0 a 200% do dano, com a marca do neutro no meio) e o número;
## verde = fraqueza (bom para o jogador), vermelho = resistência. Antes do estágio 2 tudo fica "?".
const EL_COLORS := {"fisico": Color(0.55, 0.5, 0.45)}
const C_WEAK := Color(0.12, 0.48, 0.14)
const C_RESIST := Color(0.62, 0.14, 0.08)


func _elements(bt: BalanceTables, kind: String, shown: bool) -> Control:
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 16)
	g.add_theme_constant_override("v_separation", 6)
	for el in BestiaryRules.ELEMENTS:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 6)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var col: Color = EL_COLORS.get(el, EnchantFX.ELEMENTS.get(el, {}).get("color", UITheme.INK))
		var dot := ColorRect.new()
		dot.color = col.darkened(0.15)
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(dot)
		var name_l := UITheme.ink(BestiaryRules.ELEMENT_NAMES[el], 15, UITheme.INK)
		name_l.custom_minimum_size.x = 62
		cell.add_child(name_l)
		var pct := BestiaryRules.element_pct(bt, kind, el)
		var bar := UITheme.ink_bar(col.darkened(0.1), 0, 14)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.custom_minimum_size.x = 70
		bar.show_percentage = false
		bar.max_value = 200
		bar.value = pct if shown else 0
		var mark := ColorRect.new()   # o neutro (100%)
		mark.color = Color(UITheme.INK.r, UITheme.INK.g, UITheme.INK.b, 0.55)
		mark.anchor_left = 0.5
		mark.anchor_right = 0.5
		mark.anchor_bottom = 1.0
		mark.offset_left = -1
		mark.offset_right = 1
		bar.add_child(mark)
		cell.add_child(bar)
		var txt := "?"
		var tc := UITheme.INK_DIM
		if shown:
			txt = "%d%%" % pct
			tc = C_WEAK if pct > 100 else (C_RESIST if pct < 100 else UITheme.INK)
			cell.tooltip_text = "%s: %s (recebe %d%% do dano)" % [BestiaryRules.ELEMENT_NAMES[el], BestiaryRules.element_word(pct), pct]
		else:
			cell.tooltip_text = "Revelado no estágio 2"
		var v := UITheme.ink(txt, 15, tc, true)
		v.custom_minimum_size.x = 46
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cell.add_child(v)
		g.add_child(cell)
	return g


## Régua de abates em 3 segmentos, um por estágio; cada um enche entre o alvo anterior e o dele.
func _kill_bar(bt: BalanceTables, kind: String, n: int, st: int) -> Control:
	var steps := BestiaryRules.steps(bt, kind)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	var prev := 0
	for i in steps.size():
		var need := int(steps[i])
		var seg := UITheme.ink_bar(UITheme.XP if i < st or st >= 3 else Color(0.75, 0.6, 0.25), 0, 22)
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.max_value = need - prev
		seg.value = clampi(n - prev, 0, need - prev)
		seg.show_percentage = false
		seg.tooltip_text = "Estágio %d: %d abates" % [i + 1, need]
		var cap := UITheme.ink(str(need), 12, UITheme.INK_DIM)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		seg.add_child(cap)
		h.add_child(seg)
		prev = need
	return h


## Atributos no nível de referência do monstro (os do mapa sobem com o nível da região). "?" antes do estágio 1.
func _stats(bt: BalanceTables, kind: String, e: Dictionary, st: int, cls: String) -> Control:
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 4)
	var lv := ProgressionRules.enemy_level(bt, kind, 0)
	var stars := "★".repeat(STARS.get(cls, 1)) + "☆".repeat(4 - STARS.get(cls, 1))
	var spd := float(e.get("speed", 4.0))
	var pace := "Lenta" if spd < 3.2 else ("Rápida" if spd > 4.6 else "Normal")
	var style := "Corpo a corpo"
	if str(e.get("shot", "")) != "" or str(e.get("ai", "")) == "ranged":
		style = "À distância"
	var cells := [
		["Perigo", stars, true], ["Pontos", str(BestiaryRules.points(bt, kind)), true],
		["Vida", str(int(e.get("hp", 0))), false], ["Dano", str(int(e.get("damage", 0))), false],
		["XP", str(int(e.get("xp", 0))), false], ["Nível base", str(lv), false],
		["Ataque", style, false], ["Velocidade", pace, false],
	]
	for c in cells:
		g.add_child(UITheme.ink(str(c[0]), 15, UITheme.INK_DIM))
		g.add_child(UITheme.ink(str(c[1]) if c[2] or st >= 1 else "?", 16, INK_GOLD if c[0] == "Perigo" else UITheme.INK, true))
	return g


func _abilities(bt: BalanceTables, kind: String, e: Dictionary) -> String:
	var out: Array = []
	var enemies := bt.get_table("enemies")
	var shot := str(e.get("shot", ""))
	if shot != "":
		out.append(SHOTS.get(shot, "Ataca de longe"))
	elif str(e.get("ai", "")) == "ranged":
		out.append("Ataca de longe")
	if e.has("split"):
		out.append("Ao morrer, se divide em %d filhotes" % int(e.split[1]))
	if e.has("summon"):
		out.append("Chama reforços: %s" % enemies.get(str(e.summon), {}).get("name", e.summon))
	if e.has("heal_radius"):
		out.append("Cura os aliados por perto")
	if e.has("slam_every") and str(e.get("slam_fx", "")) == "lightning":
		out.append("Chama um raio sobre si a cada %d ataques: onda de choque em área" % int(e.slam_every))
	elif e.has("slam_every"):
		out.append("Golpe pesado em área a cada %d ataques" % int(e.slam_every))
	if e.has("blast") and not e.has("throw_cd"):
		out.append("Explode em área")
	if e.has("throw_cd"):
		out.append("Arremessa bombas")
	if e.has("death_blast"):
		out.append("Explode ao morrer")
	if e.has("chill_venom"):
		out.append("Veneno que deixa lento")
	elif e.has("chill"):
		out.append("Golpes gelados deixam lento")
	if e.has("web_cd"):
		out.append("Prende com teia")
	if e.has("tongue_cd"):
		out.append("Puxa com a língua")
	if e.has("dig_max"):
		out.append("Cava e surge debaixo da terra")
	if e.has("howl_cd"):
		out.append("Uiva e chama a matilha")
	if e.get("boss", false) and out.is_empty():
		out.append("Chefe com ataques próprios: observe antes de avançar")
	if out.is_empty():
		out.append("Nada fora do comum")
	return "\n".join(out.map(func(s): return "• " + s))


## Quadro rebaixado com texto; vazio = "?" e a dica de quando revela.
func _text_box(text: String, locked: String) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.ink_inset(8))
	p.custom_minimum_size.y = 72
	var l := UITheme.ink(text if text != "" else "?  " + locked, 15, UITheme.INK if text != "" else UITheme.INK_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(l)
	return p


func _loot_slot(r: Dictionary) -> Control:
	if r.shown:
		var s := ItemSlot.new(46)
		s.paper = true
		s.set_state(r.id, 0)
		s.context = "reward"
		s.tooltip = tooltip
		return s
	var q := PanelContainer.new()
	q.custom_minimum_size = Vector2(46, 46)
	q.add_theme_stylebox_override("panel", UITheme.ink_inset(2))
	var lq := UITheme.ink("?", 24, UITheme.INK_DIM, true)
	lq.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lq.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	q.add_child(lq)
	q.tooltip_text = "Revelado no estágio %d" % int(r.band) if int(r.band) <= 3 \
		else "Muito raro: só aparece aqui depois de cair para você"
	return q


func _empty_slot() -> Control:
	var q := Panel.new()
	q.custom_minimum_size = Vector2(46, 46)
	q.add_theme_stylebox_override("panel", UITheme.ink_inset(2))
	q.modulate.a = 0.45
	q.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return q
