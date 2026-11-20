extends Control
## Doran, o ferreiro: encantar a arma equipada, no formato da forja (StationKit): à esquerda os seis
## elementos (o atual com o nível); à direita a arma, o que o próximo nível faz e o custo tenho/preciso. O pedido vai por Econ.request("enchant"):
## online o servidor decide, no solo o serviço local; o painel só redesenha quando o estado muda.
## Regras e números: EnchantRules + data/balance/enchant.json.

signal closed

## Janela lateral da esquerda (WindowDock), com o inventário aberto ao lado.
var dock_side := "left"
var wants_inventory := true

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

## Desenho de cada elemento na lista (IconPainter).
const ELEMENT_ICONS := {"fogo": "fireball", "gelo": "frost", "raio": "orb", "veneno": "potion", "sagrado": "radiant",
	"sombra": "orb"}

var tooltip: ItemTooltip
var _title: Label
var _next: Label
var _rows_box: VBoxContainer
var _el_rows := {}        # elemento -> linha (StationKit.row)
var _head: Dictionary
var _chips: HBoxContainer
var _costs: GridContainer
var _missing: Label
var _notice: Label
var _pending := false
## O herói segurando a arma com o brilho do nível que vem (no lugar do ícone da arma).
var _preview: CharPreview
var _weapon := ""
var _rows: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	var p := UITheme.dock_panel(self)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	var head := StationKit.header("")
	_title = head.get_child(0)
	v.add_child(head)
	v.add_child(UITheme.label("\"Traga o que a mata dá e eu ponho na lâmina.\"", 15, UITheme.DIM))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	v.add_child(h)
	var list := StationKit.list_panel("Elementos", null, Vector2(340, 380))
	h.add_child(list.panel)
	_rows_box = list.rows
	var det := StationKit.detail_panel(460)
	h.add_child(det.panel)
	tooltip = ItemTooltip.new()
	tooltip.paper = true
	_head = StationKit.detail_head(det.box, tooltip, 112)
	_next = _head.stats
	var top: Control = (_head.slot as ItemSlot).get_parent()
	(_head.slot as ItemSlot).visible = false
	_preview = CharPreview.new(Vector2(170, 220))
	top.add_child(_preview)
	top.move_child(_preview, 0)
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 8)
	det.box.add_child(_chips)
	det.box.add_child(UITheme.section("Custo", 18))
	_costs = StationKit.materials_grid()
	det.box.add_child(_costs)
	det.box.add_child(UITheme.spacer())
	_missing = UITheme.label("", 15, UITheme.BAD)
	_missing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_missing.custom_minimum_size.x = 420
	det.box.add_child(_missing)
	_notice = UITheme.label("", 15, UITheme.DIM)
	enchant_button = UITheme.primary(UITheme.button("Encantar", _on_enchant))
	v.add_child(UITheme.footer(_notice, [enchant_button, UITheme.button("Sair", _close)]))
	add_child(tooltip)
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
	StationKit.clear(_chips)
	StationKit.clear(_costs)
	_missing.text = ""
	_next.text = ""
	(_head.slot as ItemSlot).set_state(wid)
	_head.title.text = ""
	_head.sub.text = ""
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
	_build_rows(elements, cur)
	var c := EnchantRules.cost(_mirror(), Balance.tables, selected)
	var sel_name: String = elements[selected].get("name", selected)
	var show_lv: int = cur.lv
	if not c.ok:
		_next.text = ERRORS.get(c.err, "Não é possível encantar (%s)." % c.err)
		enchant_button.text = "Nível máximo" if c.err == "nivel_maximo" else "Encantar"
		enchant_button.disabled = true
	else:
		var dmg: Array = t.get("damage", [])
		var effect: String = EnchantRules.effect_text(Balance.tables, selected, int(c.to))
		if effect == "":
			effect = elements[selected].get("effect", "")
		show_lv = int(c.to)
		var col: Color = EnchantFX.ELEMENTS.get(selected, {}).get("color", UITheme.GOLD)
		_head.title.text = "%s +%d" % [sel_name, int(c.to)]
		_head.title.add_theme_color_override("font_color", col)
		_head.sub.text = effect
		if c.kind == "swap":
			_next.text = "Trocar para %s (mantém +%d)" % [sel_name, cur.lv]
		else:
			_next.text = "Próximo nível: %s +%d" % [sel_name, c.to]
		_chips.add_child(StationKit.chip("+%d%%" % _pct(dmg, int(c.to)), "Dano (hoje +%d%%)" % _pct(dmg, cur.lv), col))
		_chips.add_child(StationKit.chip("+%d" % int(c.to), "Nível", UITheme.GOLD))
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


## Uma linha por elemento (desenho na cor dele); o elemento atual da arma mostra o nível.
func _build_rows(elements: Dictionary, cur: Dictionary) -> void:
	if _el_rows.is_empty() or _el_rows.size() != elements.size():
		StationKit.clear(_rows_box)
		_el_rows.clear()
		for el in elements:
			var col: Color = EnchantFX.ELEMENTS.get(el, {}).get("color", UITheme.GOLD)
			var def: Dictionary = elements[el]
			var r := StationKit.row("", str(def.get("name", el)), str(def.get("effect", "")), select.bind(str(el)),
				Callable(), ELEMENT_ICONS.get(el, "orb"), col)
			_rows_box.add_child(r.btn)
			_el_rows[el] = r
	for el in _el_rows:
		var col: Color = EnchantFX.ELEMENTS.get(el, {}).get("color", UITheme.GOLD)
		var lv: int = cur.lv if el == cur.el else 0
		StationKit.set_row(_el_rows[el], el == selected, true, col, "+%d" % lv if lv > 0 else "", col)


func _build_costs(c: Dictionary, t: Dictionary) -> void:
	_rows.append({"id": "", "name": "Ouro", "need": int(c.gold), "have": Game.gold, "ok": Game.gold >= int(c.gold)})
	if int(c.ecos) > 0:
		_rows.append({"id": "$ecos", "name": "Ecos", "need": int(c.ecos), "have": Game.ecos, "ok": Game.ecos >= int(c.ecos)})
	for id in c.items:
		var have := Game.count_item(id)
		_rows.append({"id": id, "name": ItemDB.get_item(id).get("name", id), "need": int(c.items[id]), "have": have,
			"ok": have >= int(c.items[id])})
	var sources: Dictionary = t.get("sources", {})
	var lacking: Array[String] = []
	for r in _rows:
		_costs.add_child(StationKit.material(r.id, r.name, r.have, r.need, tooltip))
		if not r.ok:
			var line := "Falta: %d %s" % [r.need - r.have, r.name]
			if sources.has(r.id):
				line += " (%s)" % sources[r.id]
			elif r.id == "$ecos":
				line += " (vêm do fim das partidas da Horda e da Defesa)"
			lacking.append(line)
	_missing.text = "\n".join(lacking)


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
