extends Control
## Doran, o ferreiro: encantar a arma equipada. Um painel só: a arma (com o brilho do nível que vem),
## os seis elementos, o custo e o que o jogador já tem. O pedido vai por Econ.request("enchant"):
## online o servidor decide, no solo o serviço local; o painel só redesenha quando o estado muda.
## Regras e números: EnchantRules + data/balance/enchant.json.

signal closed

## Erros do serviço -> aviso para o jogador.
const ERRORS := {
	"sem_ouro": "Ouro insuficiente.",
	"sem_ecos": "Ecos insuficientes.",
	"sem_material": "Faltam materiais.",
	"nivel_maximo": "Esta arma já está no nível máximo.",
	"sem_arma": "Equipe uma arma primeiro.",
	"sem_tabela": "Encantamento indisponível neste servidor.",
	"elemento_invalido": "Elemento desconhecido.",
}
const ECOS_COLOR := Color(0.6, 0.85, 1.0)

## Elemento escolhido no painel.
var selected := ""
var enchant_button: Button
## Ferreiro que abriu o painel (bate na bigorna quando o encanto sai); pode ser null.
var smith: Node = null

var _title: Label
var _next: Label
var _elements: HBoxContainer
var _costs: VBoxContainer
var _missing: Label
var _notice: Label
var _preview: CharPreview
var _pending := false
var _weapon := ""
var _rows: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	var p := UITheme.centered_panel(self, 0.55)
	p.custom_minimum_size = Vector2(860, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	_title = UITheme.heading("", 28)
	v.add_child(_title)
	v.add_child(UITheme.label("\"Traga o que a mata dá e eu ponho na lâmina.\"", 15, UITheme.DIM))
	v.add_child(HSeparator.new())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	v.add_child(body)
	_preview = CharPreview.new(Vector2(240, 320))
	body.add_child(_preview)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	right.add_child(UITheme.label("Elemento", 15, UITheme.DIM))
	_elements = HBoxContainer.new()
	_elements.add_theme_constant_override("separation", 6)
	right.add_child(_elements)
	_next = UITheme.label("", 17, UITheme.TEXT)
	_next.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_next)
	_costs = VBoxContainer.new()
	_costs.add_theme_constant_override("separation", 3)
	right.add_child(_costs)
	_missing = UITheme.label("", 15, UITheme.BAD)
	_missing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_missing)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	_notice = UITheme.label("", 15, UITheme.DIM)
	_notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_notice)
	enchant_button = UITheme.button("Encantar", _on_enchant, 160)
	foot.add_child(enchant_button)
	foot.add_child(UITheme.keycap("E", 13))
	foot.add_child(UITheme.button("Fechar", _close, 120))
	v.add_child(foot)
	Econ.result.connect(_on_result)
	Game.enchant_changed.connect(_refresh)
	Game.inventory_changed.connect(_refresh)
	Balance.changed.connect(_on_balance)
	_refresh()


func _table() -> Dictionary:
	return Balance.tables.get_table("enchant")


## Escolhe o elemento (os testes usam; os botões chamam a mesma coisa).
func select(element: String) -> void:
	selected = element
	_refresh()


## Linhas do custo atual: [{"id", "name", "need", "have", "ok"}]; ouro = id "", Ecos = id "$ecos".
func cost_rows() -> Array:
	return _rows


## Tudo o que o painel está dizendo em texto (título, próximo nível, o que falta e o aviso).
func status_text() -> String:
	return "\n".join([_title.text, _next.text, _missing.text, _notice.text])


func _mirror() -> CharState:
	# as regras são puras e pedem um CharState: monta um com o que o Game espelha
	var s := CharState.new()
	s.gold = Game.gold
	s.ecos = Game.ecos
	s.inventory = Game.inventory
	s.equipment = Game.equipment
	s.enchants = Game.enchants
	return s


func _refresh() -> void:
	if not is_inside_tree():
		return
	var t := _table()
	var elements: Dictionary = t.get("elements", {})
	var wid: String = Game.equipment.weapon
	var cur := Game.weapon_enchant()
	if wid != _weapon:      # arma trocada com o painel aberto: recomeça no elemento dela
		_weapon = wid
		selected = ""
	if selected == "" or not elements.has(selected):
		selected = cur.el if elements.has(cur.el) else (str(elements.keys()[0]) if not elements.is_empty() else "")
	_rows = []
	for c in _elements.get_children():
		c.queue_free()
	for c in _costs.get_children():
		c.queue_free()
	_missing.text = ""
	_next.text = ""
	var wname: String = ItemDB.get_item(wid).get("name", "") if wid != "" else ""
	_title.text = "Encantar"
	if wname != "":
		_title.text = "Encantar: %s" % wname
		if cur.lv > 0:
			_title.text += " +%d (%s)" % [cur.lv, elements.get(cur.el, {}).get("name", cur.el)]
	if elements.is_empty() or t.get("levels", []).is_empty():
		_block(ERRORS["sem_tabela"])
		return
	if wid == "":
		_block(ERRORS["sem_arma"])
		return
	for el in elements:
		_element_button(str(el), elements[el], cur)
	var c := EnchantRules.cost(_mirror(), Balance.tables, selected)
	var sel_name: String = elements[selected].get("name", selected)
	var show_lv: int = cur.lv
	if not c.ok:
		_next.text = ERRORS.get(c.err, "Não é possível encantar (%s)." % c.err)
		enchant_button.text = "Nível máximo" if c.err == "nivel_maximo" else "Encantar"
		enchant_button.disabled = true
	else:
		show_lv = int(c.to)
		var dmg: Array = t.get("damage", [])
		var effect: String = elements[selected].get("effect", "")
		if c.kind == "swap":
			_next.text = "Trocar para %s (mantém +%d)" % [sel_name, cur.lv]
		else:
			_next.text = "Próximo nível: %s +%d   ·   Dano +%d%% → +%d%%" % [sel_name, c.to,
				_pct(dmg, cur.lv), _pct(dmg, int(c.to))]
		if effect != "":
			_next.text += "\nEfeito: %s" % effect
		_build_costs(c, t)
		var can := true
		for r in _rows:
			can = can and r.ok
		enchant_button.text = "Trocar" if c.kind == "swap" else "Encantar"
		enchant_button.disabled = _pending or not can
	_preview.show_enchant(selected, show_lv)


func _pct(dmg: Array, lv: int) -> int:
	if lv <= 0 or dmg.is_empty():
		return 0
	return int(round(float(dmg[mini(lv, dmg.size()) - 1]) * 100.0))


## Painel sem nada a fazer (sem arma, sem tabela): só a mensagem.
func _block(text: String) -> void:
	_next.text = text
	enchant_button.text = "Encantar"
	enchant_button.disabled = true
	_preview.show_enchant("", 0)


func _element_button(el: String, def: Dictionary, cur: Dictionary) -> void:
	var color: Color = EnchantFX.ELEMENTS.get(el, {}).get("color", UITheme.GOLD)
	var b := UITheme.button(str(def.get("name", el)), func() -> void: select(el), 92)
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", color.lightened(0.3))
	if el == selected:
		b.add_theme_stylebox_override("normal", UITheme.frame_box(Color(color.r, color.g, color.b, 0.22), color, 6))
	if el == cur.el and cur.lv > 0:
		b.text = "%s +%d" % [def.get("name", el), cur.lv]
	_elements.add_child(b)


func _build_costs(c: Dictionary, t: Dictionary) -> void:
	_rows.append({"id": "", "name": "Ouro", "need": int(c.gold), "have": Game.gold, "ok": Game.gold >= int(c.gold)})
	if int(c.ecos) > 0:
		_rows.append({"id": "$ecos", "name": "Ecos", "need": int(c.ecos), "have": Game.ecos, "ok": Game.ecos >= int(c.ecos)})
	for id in c.items:
		var have := Game.count_item(id)
		_rows.append({"id": id, "name": ItemDB.get_item(id).get("name", id), "need": int(c.items[id]), "have": have,
			"ok": have >= int(c.items[id])})
	var head := HBoxContainer.new()
	head.add_child(_cell("Custo", 230, UITheme.DIM))
	head.add_child(_cell("Precisa", 80, UITheme.DIM))
	head.add_child(_cell("Você tem", 90, UITheme.DIM))
	_costs.add_child(head)
	var sources: Dictionary = t.get("sources", {})
	var lacking: Array[String] = []
	for r in _rows:
		var h := HBoxContainer.new()
		var col: Color = UITheme.TEXT
		if r.id == "":
			col = UITheme.GOLD
		elif r.id == "$ecos":
			col = ECOS_COLOR
		h.add_child(_cell(r.name, 230, col))
		h.add_child(_cell(str(r.need), 80, UITheme.TEXT))
		h.add_child(_cell(str(r.have), 90, UITheme.GOOD if r.ok else UITheme.BAD))
		h.add_child(_cell("✓" if r.ok else "✗", 30, UITheme.GOOD if r.ok else UITheme.BAD))
		_costs.add_child(h)
		if not r.ok:
			var line := "Falta: %d %s" % [r.need - r.have, r.name]
			if sources.has(r.id):
				line += " (%s)" % sources[r.id]
			elif r.id == "$ecos":
				line += " (vêm do fim das partidas da Horda e da Defesa)"
			lacking.append(line)
	_missing.text = "\n".join(lacking)


func _cell(text: String, w: float, color: Color) -> Label:
	var l := UITheme.label(text, 16, color)
	l.custom_minimum_size.x = w
	return l


func _on_enchant() -> void:
	if _pending or enchant_button.disabled:
		return
	_pending = true
	enchant_button.disabled = true
	Econ.request("enchant", [selected])


func _on_result(op: String, ok: bool, err: String) -> void:
	if op != "enchant":
		return
	_pending = false
	if ok:
		var e := Game.weapon_enchant()
		var color: Color = EnchantFX.ELEMENTS.get(e.el, {}).get("color", UITheme.GOLD)
		_notice.text = "A lâmina aceitou o encanto."
		_notice.add_theme_color_override("font_color", color)
		if smith != null and is_instance_valid(smith) and smith.has_method("enchant_strike"):
			smith.enchant_strike(color)
		else:
			Sfx.play("coin")
	else:
		_notice.text = ERRORS.get(err, "Não deu certo (%s)." % err)
		_notice.add_theme_color_override("font_color", UITheme.BAD)
	_refresh()


func _on_balance(_names: Array) -> void:
	_refresh()


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_close()
