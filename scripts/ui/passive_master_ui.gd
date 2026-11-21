extends Control
## Mestre Orin: passivas permanentes compradas com Ecos, em cartões de duas colunas: ícone, nome, os
## níveis como marcas cheias/vazias, o efeito de agora e o do próximo nível, o custo e o botão. A compra vai pelo Econ.request("buy_passive"): online o
## servidor decide, no solo o serviço local; o painel só redesenha quando o resultado chega.

signal closed

## Janela lateral da esquerda (WindowDock).
var dock_side := "left"

## Erros do serviço -> aviso para o jogador.
const ERRORS := {
	"sem_ecos": "Ecos insuficientes.",
	"nivel_maximo": "Esta passiva já está no nível máximo.",
	"passiva_invalida": "Passiva desconhecida.",
}
## Modificador -> [texto, tipo]; "pct" mostra % (valor * 100), "flat" inteiro, "tick" uma casa decimal.
const FMT := {
	"damage": ["de dano", "pct"], "max_hp": ["de vida máxima", "pct"], "defense": ["de defesa", "flat"],
	"regen": ["de vida por segundo", "tick"], "cooldown": ["de recarga", "pct"], "magnet": ["de alcance de coleta", "pct"],
	"area": ["de área", "pct"], "speed": ["de velocidade", "pct"],
}

## Desenho de cada modificador (IconPainter) e a cor dele.
const ICONS := {"damage": ["fury", Color(0.85, 0.3, 0.15)], "max_hp": ["potion", Color(0.85, 0.15, 0.15)],
	"defense": ["shield", Color(0.55, 0.45, 0.3)], "regen": ["heal", Color(0.3, 0.75, 0.35)],
	"cooldown": ["frost", Color(0.35, 0.7, 0.95)], "magnet": ["ring", Color(0.9, 0.7, 0.2)],
	"area": ["radiant", Color(0.95, 0.75, 0.25)], "speed": ["boot", Color(0.4, 0.65, 0.3)]}

var ecos_label: Label
var rows: GridContainer
var notice: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	var p := UITheme.dock_panel(self)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var top := HBoxContainer.new()
	var title := VBoxContainer.new()
	title.add_child(UITheme.heading("Mestre Orin", 30))
	title.add_child(UITheme.label("\"Os Ecos que você traz das batalhas viram força que fica com você.\"", 15, UITheme.DIM))
	top.add_child(title)
	top.add_child(UITheme.spacer())
	ecos_label = UITheme.heading("", 24, Color(0.6, 0.85, 1.0))
	ecos_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(ecos_label)
	v.add_child(top)
	v.add_child(HSeparator.new())
	rows = GridContainer.new()
	rows.columns = 2
	rows.add_theme_constant_override("h_separation", 10)
	rows.add_theme_constant_override("v_separation", 10)
	v.add_child(rows)
	notice = UITheme.label("Ecos vêm do fim das partidas da Horda e da Defesa.", 15, UITheme.DIM)
	v.add_child(UITheme.footer(notice, [UITheme.button("Sair", _close)]))
	Econ.result.connect(_on_result)
	Econ.done.connect(_on_done)
	_refresh()


## Texto do efeito num nível: "+6% de dano".
static func effect_text(add: Dictionary, level: int) -> String:
	var parts: Array[String] = []
	for k in add:
		var f: Array = FMT.get(k, [k, "flat"])
		var val := float(add[k]) * level
		match f[1]:
			"pct":
				parts.append("%+d%% %s" % [roundi(val * 100.0), f[0]])
			"tick":
				parts.append(("%+.1f %s" % [val, f[0]]).replace(".", ","))
			_:
				parts.append("%+d %s" % [roundi(val), f[0]])
	return ", ".join(parts)


func _refresh() -> void:
	if not is_inside_tree():
		return
	ecos_label.text = "✦ %d Ecos" % Game.ecos
	for c in rows.get_children():
		c.queue_free()
	var table: Dictionary = Balance.tables.get_table("meta_passives").get("passives", {})
	for id in table:
		_row(str(id), table[id])


func _row(id: String, def: Dictionary) -> void:
	var costs: Array = def.get("cost", [])
	var level := int(Game.passives.get(id, 0))
	var maxed := level >= costs.size()
	var add: Dictionary = def.get("add", {})
	var col: Color = def.get("color", UITheme.GOLD)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UITheme.kit_inset(10))
	box.custom_minimum_size.x = 420
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	box.add_child(h)
	var ic := ItemSlot.new(56)
	var key: String = str(add.keys()[0]) if not add.is_empty() else ""
	var icon: Array = ICONS.get(key, ["orb", col])
	ic.icon_kind = icon[0]
	ic.icon_color = icon[1]
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(ic)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var top := HBoxContainer.new()
	var name_l := UITheme.heading(str(def.get("name", id)), 19, col)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_l)
	# níveis como marcas: cheias até o atual
	var pips := ""
	for i in costs.size():
		pips += "◆" if i < level else "◇"
	top.add_child(UITheme.label(pips, 16, UITheme.GOLD))
	v.add_child(top)
	v.add_child(UITheme.label("Agora: %s" % (effect_text(add, level) if level > 0 else "nada"), 15, UITheme.TEXT))
	v.add_child(UITheme.label("Próximo: %s" % ("nível máximo" if maxed else effect_text(add, level + 1)), 15,
		UITheme.DIM if maxed else UITheme.GOOD))
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	var cost := 0 if maxed else int(costs[level])
	var cl := UITheme.label("" if maxed else "✦ %d Ecos" % cost, 15,
		Color(0.6, 0.85, 1.0) if Game.ecos >= cost else UITheme.BAD)
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(cl)
	var b := UITheme.button("Aprender" if level == 0 else "Melhorar", func() -> void: Econ.request("buy_passive", [id]), 110)
	b.custom_minimum_size.y = 32
	b.disabled = maxed or Game.ecos < cost
	foot.add_child(b)
	v.add_child(foot)
	rows.add_child(box)


func _on_result(op: String, ok: bool, err: String) -> void:
	if op != "buy_passive":
		return
	if ok:
		Sfx.play("coin")
		notice.text = "Passiva fortalecida."
		notice.add_theme_color_override("font_color", UITheme.GOOD)
	else:
		notice.text = ERRORS.get(err, "Não deu certo (%s)." % err)
		notice.add_theme_color_override("font_color", UITheme.BAD)
	_refresh()


## Qualquer outro estado novo (Ecos chegando por push do servidor no fim de uma partida, Ecos de teste):
## o saldo e os botões acompanham com o painel aberto. A compra já redesenha em _on_result.
func _on_done(op: String, _args: Array, _ok: bool, _err: String, _events: Array) -> void:
	if op != "buy_passive":
		_refresh()


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_close()
