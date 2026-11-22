extends Control
## Caldeirão da Horta, no formato da forja (StationKit): à esquerda os pratos (ícone, efeito curto, quantos
## dá para fazer); à direita o escolhido, com o efeito, quantos já tenho e os ingredientes tenho/preciso.
## Comidas dão bônus temporários; come-se com Q (troca com T), inclusive no meio da Horda.

signal closed

## Janela lateral da esquerda (WindowDock), com o inventário aberto ao lado.
var dock_side := "left"
var wants_inventory := true

var kitchen: Node = null
var cook_btn: Button
var max_btn: Button
var tooltip: ItemTooltip
var _rows := {}           # receita -> linha (StationKit.row)
var _sel := ""
var _head: Dictionary
var _chips: HBoxContainer
var _mats: GridContainer
var _pantry: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := UITheme.dock_panel(self)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	v.add_child(StationKit.header("Caldeirão da Horta"))
	v.add_child(UITheme.label("Comidas dão bônus temporários. Coma com Q (troque com T), inclusive no meio da Horda.", 15, UITheme.DIM))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	v.add_child(h)
	var list := StationKit.list_panel("Pratos", null, Vector2(380, 400))
	h.add_child(list.panel)
	for r in ItemDB.RECIPE_ORDER:
		var row := StationKit.row(r, ItemDB.get_item(r).name, _short_effect(r), select_recipe.bind(r), func() -> void: _cook(1))
		list.rows.add_child(row.btn)
		_rows[r] = row
	var det := StationKit.detail_panel(460)
	h.add_child(det.panel)
	tooltip = ItemTooltip.new()
	tooltip.paper = true
	_head = StationKit.detail_head(det.box, tooltip, 112)
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 8)
	det.box.add_child(_chips)
	det.box.add_child(UITheme.section("Ingredientes", 18))
	_mats = StationKit.materials_grid()
	det.box.add_child(_mats)
	det.box.add_child(UITheme.spacer())
	_pantry = UITheme.label("", 14, UITheme.DIM)
	_pantry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pantry.custom_minimum_size.x = 420
	det.box.add_child(_pantry)
	cook_btn = UITheme.primary(UITheme.button("Cozinhar", func() -> void: _cook(1)))
	max_btn = UITheme.button("Cozinhar tudo", func() -> void: _cook(99))
	v.add_child(UITheme.footer(UITheme.label("Duplo clique no prato cozinha um", 14, UITheme.DIM),
		[max_btn, cook_btn, UITheme.button("Sair", _close)]))
	add_child(tooltip)
	Game.inventory_changed.connect(_refresh)
	Econ.done.connect(_on_econ_done)
	_sel = ItemDB.RECIPE_ORDER[0]
	for r in ItemDB.RECIPE_ORDER:
		if Game.can_cook(r) > 0:
			_sel = r
			break
	_refresh()


## Efeito em uma linha curta, para a lista (o detalhe mostra o texto inteiro).
static func _short_effect(r: String) -> String:
	var t := ItemDB.food_effect_text(r).split("\n")[0]
	return t if t.length() <= 46 else t.substr(0, 44) + "…"


## Escolhe o prato (os testes usam; as linhas chamam a mesma coisa).
func select_recipe(r: String) -> void:
	_sel = r
	_refresh()


func _refresh() -> void:
	if not is_inside_tree():
		return
	for r in _rows:
		var n := Game.can_cook(r)
		var tag := ("x%d" % n) if n > 0 else ("Nv %d" % _need(r) if not _level_ok(r) else "")
		StationKit.set_row(_rows[r], r == _sel, n > 0, ItemDB.get_item(r).get("color", UITheme.TEXT), tag)
	_update_info()


## Nível de Culinária que o prato pede (recipes.json "level").
static func _need(r: String) -> int:
	return maxi(1, int(CraftRules.recipe(Balance.tables, r).get("level", 1)))


static func _level_ok(r: String) -> bool:
	return Game.prof_level("cooking") >= _need(r)


func _update_info() -> void:
	StationKit.clear(_chips)
	StationKit.clear(_mats)
	if _sel == "":
		return
	var it := ItemDB.get_item(_sel)
	var have := Game.count_item(_sel)
	var n := Game.can_cook(_sel)
	(_head.slot as ItemSlot).set_state(_sel, have)
	_head.title.text = it.name
	_head.title.add_theme_color_override("font_color", it.get("color", UITheme.GOLD))
	_head.sub.text = it.desc
	_head.stats.text = ItemDB.food_effect_text(_sel)
	_chips.add_child(StationKit.chip("x%d" % n, "Dá para fazer", UITheme.GOOD, n > 0))
	_chips.add_child(StationKit.chip("x%d" % have, "Na mochila", UITheme.GOLD, have > 0))
	var ing: Dictionary = ItemDB.RECIPES[_sel]
	for id in ing:
		_mats.add_child(StationKit.material(id, ItemDB.get_item(id).name, Game.count_item(id), int(ing[id]), tooltip))
	var pantry: Array[String] = []
	for crop in ItemDB.CROP_ORDER:
		var k := Game.count_item(crop)
		if k > 0:
			pantry.append("%s x%d" % [ItemDB.CROPS[crop].name, k])
	_pantry.text = "Despensa: " + (", ".join(pantry) if not pantry.is_empty() else "vazia — plante e colha na horta!")
	_pantry.remove_theme_color_override("font_color")
	if not _level_ok(_sel):
		_pantry.text = "Pede Culinária nível %d (você: %d).\n" % [_need(_sel), Game.prof_level("cooking")] + _pantry.text
		_pantry.add_theme_color_override("font_color", UITheme.BAD)
	cook_btn.disabled = n <= 0
	max_btn.disabled = n <= 1
	max_btn.text = "Cozinhar tudo (%d)" % n if n > 1 else "Cozinhar tudo"


func _cook(times: int) -> void:
	if _sel != "":
		Game.cook(_sel, times)


## O Econ confirmou: quantas saíram vem no evento "looted" da receita.
func _on_econ_done(op: String, args: Array, ok: bool, _err: String, events: Array) -> void:
	if op != "cook" or not ok or args.is_empty():
		return
	var r := str(args[0])
	var n := 0
	for e in events:
		if e.get("t") == "looted" and e.get("id") == r:
			n += int(e.get("qty", 0))
	if n <= 0:
		return
	Sfx.play("cook", 0.1)
	var it := ItemDB.get_item(r)
	Game.notify.emit("Cozinhou %s%s!" % [it.name, " x%d" % n if n > 1 else ""], it.get("color", UITheme.GOLD))
	if kitchen and kitchen.has_method("celebrate"):
		kitchen.celebrate(it.get("color", Color(1, 0.6, 0.2)))


func _close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_close()
