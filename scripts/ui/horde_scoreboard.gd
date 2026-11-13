extends CanvasLayer
## Placar do Desafio da Horda: aparece enquanto Tab está pressionado (também por cima das cartas, para
## escolher pensando nos combos). Uma linha por jogador: nível, dano, abates, quedas, combos e a build
## em ícones; embaixo, os combos que você forma com o grupo.

const UPG := preload("res://scripts/survival/upgrades.gd")
const COLS := ["Jogador", "Nv", "Dano", "Abates", "Quedas", "Combos", "Build"]

var survival: Node
## Testes: força o placar aberto sem a tecla.
var force_open := false
var _root: Control
var _title: Label
var _grid: GridContainer
var _combos: VBoxContainer
var _refresh := 0.0


func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.get_theme()
	add_child(_root)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme._box(Color(0.03, 0.028, 0.03, 0.9), Color(0.55, 0.43, 0.75, 0.7), 1, 10, 26, 20))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	_title = UITheme.outlined("", 17, Color(0.85, 0.7, 1.0), 4)
	v.add_child(_title)
	_grid = GridContainer.new()
	_grid.columns = COLS.size()
	_grid.add_theme_constant_override("h_separation", 26)
	_grid.add_theme_constant_override("v_separation", 16)
	v.add_child(_grid)
	_combos = VBoxContainer.new()
	_combos.add_theme_constant_override("separation", 6)
	v.add_child(_combos)
	visible = false


func is_open() -> bool:
	return visible


func _process(delta: float) -> void:
	var want: bool = force_open or (Input.is_physical_key_pressed(KEY_TAB) and survival != null and survival.phase != "over"
		and DisplayServer.window_is_focused())
	if want != visible:
		visible = want
		_refresh = 0.0
	if not visible:
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.4
		rebuild()


func rebuild() -> void:
	if survival == null:
		return
	_title.text = "Desafio da Horda  ·  Rodada %d  ·  %d:%02d  ·  %d abates do grupo" % [survival.round_num,
		int(survival.elapsed) / 60, int(survival.elapsed) % 60, survival.kills]
	for c in _grid.get_children():
		c.queue_free()
	for h in COLS:
		_grid.add_child(UITheme.outlined(h, 12, UITheme.DIM, 3))
	var rows: Array = survival.scoreboard_rows()
	var top_dmg := 0.0
	for r in rows:
		top_dmg = maxf(top_dmg, r.dmg)
	for r in rows:
		var b: Dictionary = r.build
		var col := Color(1, 0.9, 0.6) if r.me else UITheme.TEXT
		var nm := ("☠ " if r.dead else "") + str(r.name)
		var nl := UITheme.outlined(nm, 15, col if not r.dead else UITheme.BAD, 3)
		_grid.add_child(nl)
		_grid.add_child(UITheme.outlined(str(int(b.get("lv", 1))), 15, Color(0.6, 0.85, 1.0), 3))
		var dl := UITheme.outlined(_num(r.dmg), 15, Color(1, 0.75, 0.4) if r.dmg >= top_dmg and top_dmg > 0 and rows.size() > 1 else col, 3)
		_grid.add_child(dl)
		_grid.add_child(UITheme.outlined(str(r.kills), 15, col, 3))
		_grid.add_child(UITheme.outlined(str(r.falls), 15, UITheme.BAD if r.falls > 0 else col, 3))
		_grid.add_child(UITheme.outlined(str(int(b.get("c", 0))), 15, Color(0.85, 0.7, 1.0), 3))
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 8)
		var wrow := HBoxContainer.new()
		wrow.add_theme_constant_override("separation", 8)
		var xrow := HBoxContainer.new()
		xrow.add_theme_constant_override("separation", 7)
		cell.add_child(wrow)
		cell.add_child(xrow)
		HordeIcon.fill_build(wrow, xrow, b.get("w", {}), b.get("p", {}), b.get("b", {}), 34, 24)
		if wrow.get_child_count() == 0:
			wrow.add_child(UITheme.label("—", 13, UITheme.DIM))
		_grid.add_child(cell)
	for c in _grid.get_children():
		_ignore(c)
	# combos do jogador local
	for c in _combos.get_children():
		c.queue_free()
	var active: Dictionary = survival.active_combos
	if survival.role == "client" and survival.team.size() > 1:
		_combos.add_child(UITheme.outlined("COMBOS (fique a até %d m do colega)" % int(UPG.COMBO_RANGE), 12, UITheme.DIM, 3))
		if active.is_empty():
			_combos.add_child(UITheme.label("Nenhum ainda: pegue uma arma que combine com a de um colega.", 13, UITheme.DIM))
		for cid in active:
			var c: Dictionary = UPG.COMBOS[cid]
			var a: Dictionary = active[cid]
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 10)
			var ic := HordeIcon.new(26, "combo", cid)
			ic.dim = not a.near
			h.add_child(ic)
			var txt := "%s com %s — %s%s" % [c.name, a.partner, c.desc, "" if a.near else "  (longe)"]
			h.add_child(UITheme.outlined(txt, 13, c.color if a.near else UITheme.DIM, 3))
			_combos.add_child(h)
		_combos.add_child(UITheme.label(_pairs_text(), 12, UITheme.DIM))
	for c in _combos.get_children():
		_ignore(c)


## Lista curta de todos os pares possíveis (para o grupo combinar as escolhas).
static func _pairs_text() -> String:
	var parts: Array[String] = []
	for cid in UPG.COMBOS:
		var c: Dictionary = UPG.COMBOS[cid]
		parts.append("%s + %s" % [UPG.WEAPONS[c.a].name.get_slice(" ", 0), UPG.WEAPONS[c.b].name.get_slice(" ", 0)])
	return "Pares: " + "  ·  ".join(parts)


static func _num(v: float) -> String:
	if v >= 10000.0:
		return "%.1fk" % (v / 1000.0)
	return str(int(round(v)))


func _ignore(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore(c)
