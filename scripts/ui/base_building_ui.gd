extends Control
## Construção da base compartilhada (Forja, Muralha, Celeiro): nível, fundo até o próximo nível, efeito
## atual e do próximo, maiores doadores e botões de doação em Ecos. Atualiza com Hub.changed (online o
## servidor avisa todo mundo; no solo o Econ pede o refresh).

signal closed

const ERRORS := {
	"sem_ecos": "Ecos insuficientes.",
	"nivel_maximo": "A construção já está no nível máximo.",
	"valor_invalido": "Valor inválido.",
	"construcao_invalida": "Construção desconhecida.",
}
## Bônus -> [texto, tipo]; "pct" mostra % (valor * 100), "flat" inteiro.
const FMT := {
	"horde_damage": ["de dano na Horda", "pct"], "hall_hp": ["de vida do salão da cidade", "pct"],
	"city_gold": ["de ouro por noite", "flat"], "city_food": ["de comida por noite", "flat"],
}

var building_id := ""
var title_label: Label
var ecos_label: Label
var body: VBoxContainer
var notice: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	var p := UITheme.centered_panel(self, 0.55)
	p.custom_minimum_size = Vector2(720, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var top := HBoxContainer.new()
	title_label = UITheme.heading("", 30)
	top.add_child(title_label)
	top.add_child(UITheme.spacer())
	ecos_label = UITheme.heading("", 24, Color(0.6, 0.85, 1.0))
	ecos_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(ecos_label)
	v.add_child(top)
	v.add_child(HSeparator.new())
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	v.add_child(body)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	notice = UITheme.label("Toda doação vale para o servidor inteiro.", 15, UITheme.DIM)
	notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(notice)
	foot.add_child(UITheme.keycap("E", 13))
	foot.add_child(UITheme.button("Sair", _close, 140))
	v.add_child(foot)
	Hub.changed.connect(_refresh)
	Econ.result.connect(_on_result)
	_refresh()


func _def() -> Dictionary:
	return Balance.tables.get_table("base_buildings").get("buildings", {}).get(building_id, {})


static func bonus_text(bonus: Dictionary) -> String:
	var parts: Array[String] = []
	for k in bonus:
		var f: Array = FMT.get(k, [k, "flat"])
		var val := float(bonus[k])
		if f[1] == "pct":
			parts.append("%+d%% %s" % [roundi(val * 100.0), f[0]])
		else:
			parts.append("%+d %s" % [roundi(val), f[0]])
	return ", ".join(parts)


func _refresh() -> void:
	if not is_inside_tree():
		return
	var def := _def()
	var levels: Array = def.get("levels", [])
	var entry: Dictionary = Hub.base.get(building_id, {})
	var level := clampi(int(entry.get("level", 0)), 0, levels.size())
	var fund := int(entry.get("fund", 0))
	title_label.text = "%s — nível %d/%d" % [def.get("name", building_id), level, levels.size()]
	ecos_label.text = "✦ %d Ecos" % Game.ecos
	for c in body.get_children():
		c.queue_free()
	body.add_child(UITheme.label(str(def.get("desc", "")), 16, UITheme.DIM))
	var maxed := level >= levels.size()
	var cur := bonus_text(levels[level - 1].get("bonus", {})) if level > 0 else "nenhum"
	body.add_child(UITheme.label("Efeito atual: %s" % cur, 18, UITheme.TEXT))
	if maxed:
		body.add_child(UITheme.heading("Nível máximo", 22, UITheme.GOOD))
	else:
		var need := int(levels[level].cost)
		body.add_child(UITheme.label("Próximo nível: %s" % bonus_text(levels[level].get("bonus", {})), 18, UITheme.TEXT))
		var bar := UITheme.bar(Color(0.45, 0.7, 1.0), 640, 22)
		bar.max_value = need
		bar.value = fund
		body.add_child(bar)
		body.add_child(UITheme.label("Fundo: %d / %d Ecos" % [fund, need], 16, UITheme.TEXT))
	body.add_child(UITheme.section("Maiores doadores"))
	var donors: Array = entry.get("donors", [])
	if donors.is_empty():
		body.add_child(UITheme.label("Ninguém doou ainda.", 15, UITheme.DIM))
	for i in mini(donors.size(), 5):
		body.add_child(UITheme.label("%d. %s — %d Ecos" % [i + 1, donors[i].get("name", "?"), int(donors[i].get("amount", 0))], 16, UITheme.TEXT))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	for n in [10, 50]:
		var b := UITheme.button("Doar %d" % n, func() -> void: Econ.request("donate", [building_id, n]), 130)
		b.disabled = maxed or Game.ecos < n
		h.add_child(b)
	var all := UITheme.button("Doar tudo", func() -> void: Econ.request("donate", [building_id, Game.ecos]), 150)
	all.disabled = maxed or Game.ecos <= 0
	h.add_child(all)
	body.add_child(h)


func _on_result(op: String, ok: bool, err: String) -> void:
	if op != "donate":
		return
	if ok:
		Sfx.play("coin")
		notice.text = "Obrigado pela doação!"
		notice.add_theme_color_override("font_color", UITheme.GOOD)
	else:
		notice.text = ERRORS.get(err, "Não deu certo (%s)." % err)
		notice.add_theme_color_override("font_color", UITheme.BAD)
	_refresh()


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_close()
