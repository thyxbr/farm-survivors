extends Control
## Mestre Orin: passivas permanentes compradas com Ecos. Uma linha por passiva de meta_passives
## (nível n/máx, efeito atual -> próximo, custo). A compra vai pelo Econ.request("buy_passive"): online o
## servidor decide, no solo o serviço local; o painel só redesenha quando o resultado chega.

signal closed

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

var ecos_label: Label
var rows: VBoxContainer
var notice: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	var p := UITheme.centered_panel(self, 0.55)
	p.custom_minimum_size = Vector2(900, 0)
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
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	v.add_child(rows)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	notice = UITheme.label("Ecos vêm do fim das partidas da Horda e da Defesa.", 15, UITheme.DIM)
	notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(notice)
	foot.add_child(UITheme.keycap("E", 13))
	foot.add_child(UITheme.button("Sair", _close, 140))
	v.add_child(foot)
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
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UITheme.inset_box(8))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	box.add_child(h)
	var name_l := UITheme.heading(str(def.get("name", id)), 20, def.get("color", UITheme.GOLD))
	name_l.custom_minimum_size.x = 170
	h.add_child(name_l)
	var lv := UITheme.label("%d/%d" % [level, costs.size()], 18, UITheme.TEXT)
	lv.custom_minimum_size.x = 50
	h.add_child(lv)
	var eff := UITheme.label("%s → %s" % [effect_text(add, level) if level > 0 else "nada",
		"máximo" if maxed else effect_text(add, level + 1)], 16, UITheme.TEXT)
	eff.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(eff)
	var cost := 0 if maxed else int(costs[level])
	var cl := UITheme.label("Nível máximo" if maxed else "%d Ecos" % cost, 16,
		UITheme.DIM if maxed else (Color(0.6, 0.85, 1.0) if Game.ecos >= cost else UITheme.BAD))
	cl.custom_minimum_size.x = 100
	h.add_child(cl)
	var b := UITheme.button("Aprender" if level == 0 else "Melhorar", func() -> void: Econ.request("buy_passive", [id]), 120)
	b.disabled = maxed or Game.ecos < cost
	h.add_child(b)
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
