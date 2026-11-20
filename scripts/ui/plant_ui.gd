extends Control
## Horta, no formato da forja (StationKit): à esquerda as sementes (ícone, tempo e rendimento, quantas
## tenho ou o preço); à direita a escolhida, com o tempo, a colheita, quantas sementes e em que pratos vai.
## "Plantar" abre uma janelinha de confirmação (ActionModal) com o que vai acontecer e o custo de comprar a
## semente que faltar; "Plantar em todos" faz o mesmo para todos os canteiros vazios.

signal closed

## Janela lateral da esquerda (WindowDock), com o inventário aberto ao lado.
var dock_side := "left"
var wants_inventory := true

var plot_index := 0
var plant_btn: Button
var all_btn: Button
var tooltip: ItemTooltip
var gold_label: Label
var _rows := {}           # cultura -> linha (StationKit.row)
var _sel := ""
var _head: Dictionary     # StationKit.detail_head
var _chips: HBoxContainer
var _uses: GridContainer
var _note: Label
## "Plantar em todos" em andamento: {"crop", "queue" (canteiros a pedir), "ok"} ({} = nenhum).
var _batch := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := UITheme.dock_panel(self)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	gold_label = UITheme.heading("", 22, Color(1, 0.84, 0.35))
	v.add_child(StationKit.header("Canteiro %d" % (plot_index + 1), gold_label))
	v.add_child(UITheme.label("Regue depois de plantar: cresce 2x mais rápido e rende +1.", 15, UITheme.DIM))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	v.add_child(h)
	var list := StationKit.list_panel("Sementes", null, Vector2(380, 380))
	h.add_child(list.panel)
	for crop in ItemDB.CROP_ORDER:
		var c: Dictionary = ItemDB.CROPS[crop]
		var r := StationKit.row(c.seed, c.name, "Cresce em %ds · rende %d–%d" % [int(c.time), c.yield[0], c.yield[1]],
			select_crop.bind(crop), _plant_here)
		list.rows.add_child(r.btn)
		_rows[crop] = r
	var det := StationKit.detail_panel(460)
	h.add_child(det.panel)
	tooltip = ItemTooltip.new()
	tooltip.paper = true
	_head = StationKit.detail_head(det.box, tooltip, 112)
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 8)
	det.box.add_child(_chips)
	det.box.add_child(UITheme.section("Usada em", 18))
	_uses = StationKit.materials_grid()
	det.box.add_child(_uses)
	det.box.add_child(UITheme.spacer())
	_note = UITheme.label("", 15, UITheme.DIM)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size.x = 420
	det.box.add_child(_note)
	plant_btn = UITheme.primary(UITheme.button("Plantar", _plant_here))
	all_btn = UITheme.button("Plantar em todos", _plant_all)
	v.add_child(UITheme.footer(UITheme.label("Duplo clique na semente planta neste canteiro", 14, UITheme.DIM),
		[UITheme.button("Comprar 5", _buy5), all_btn, plant_btn, UITheme.button("Sair", _close)]))
	add_child(tooltip)
	Game.inventory_changed.connect(_refresh)
	Game.stats_changed.connect(_refresh)
	Econ.done.connect(_on_econ_done)
	# começa na semente que o jogador tem (ou na primeira)
	_sel = ItemDB.CROP_ORDER[0]
	for crop in ItemDB.CROP_ORDER:
		if Game.count_item(ItemDB.CROPS[crop].seed) > 0:
			_sel = crop
			break
	_refresh()


## Escolhe a semente (os testes usam; as linhas chamam a mesma coisa).
func select_crop(crop: String) -> void:
	_sel = crop
	_refresh()


func _refresh() -> void:
	if not is_inside_tree():
		return
	gold_label.text = "◆ %d ouro" % Game.gold
	for crop in _rows:
		var c: Dictionary = ItemDB.CROPS[crop]
		var n := Game.count_item(c.seed)
		var price: int = ItemDB.get_item(c.seed).price
		var can := n > 0 or Game.gold >= price
		StationKit.set_row(_rows[crop], crop == _sel, can, c.color.lightened(0.35),
			("x%d" % n) if n > 0 else "%d◆" % price, UITheme.GOOD if n > 0 else UITheme.GOLD)
	_update_info()


func _update_info() -> void:
	StationKit.clear(_chips)
	StationKit.clear(_uses)
	if _sel == "":
		return
	var c: Dictionary = ItemDB.CROPS[_sel]
	var seed_it := ItemDB.get_item(c.seed)
	var n := Game.count_item(c.seed)
	(_head.slot as ItemSlot).set_state(c.seed, n)
	_head.title.text = c.name
	_head.title.add_theme_color_override("font_color", c.color.lightened(0.35))
	_head.sub.text = seed_it.desc
	_head.stats.text = "Semente: %d ouro" % seed_it.price
	_chips.add_child(StationKit.chip("%ds" % int(c.time), "Cresce (regada: %ds)" % int(c.time / 2.0), Color(0.55, 0.85, 1.0)))
	_chips.add_child(StationKit.chip("%d–%d" % [c.yield[0], c.yield[1]], "Por colheita", Color(0.6, 1.0, 0.5)))
	_chips.add_child(StationKit.chip("x%d" % n, "Sementes", UITheme.GOLD, n > 0))
	var any := false
	for r in ItemDB.RECIPE_ORDER:
		if ItemDB.RECIPES[r].has(_sel):
			any = true
			_uses.add_child(StationKit.material(r, ItemDB.get_item(r).name, Game.count_item(_sel), int(ItemDB.RECIPES[r][_sel]), tooltip))
	if not any:
		_uses.add_child(UITheme.label("Nenhum prato ainda.", 15, UITheme.DIM))
	var price: int = seed_it.price
	_note.text = "" if n > 0 else ("Sem sementes: plantar compra uma por %d ouro." % price if Game.gold >= price
		else "Sem sementes e sem ouro para comprar (%d)." % price)
	plant_btn.disabled = n <= 0 and Game.gold < price
	var empties := _empty_plots()
	all_btn.text = "Plantar em todos (%d)" % empties.size()
	all_btn.disabled = empties.size() <= 1


func _empty_plots() -> Array[int]:
	var out: Array[int] = []
	for i in Game.FARM_PLOTS:
		if Game.plot_state(i) == "empty":
			out.append(i)
	return out


## Confirmação antes de plantar (a janelinha mostra tempo, colheita e o custo da semente que faltar).
func _plant_here() -> void:
	if _sel == "" or plant_btn.disabled:
		return
	var c: Dictionary = ItemDB.CROPS[_sel]
	var n := Game.count_item(c.seed)
	var lines := [[c.name, c.color], ["Cresce em %ds (regada: %ds) · rende %d–%d" % [int(c.time), int(c.time / 2.0),
		c.yield[0], c.yield[1]], UITheme.DIM]]
	if n <= 0:
		lines.append(["Compra 1 semente por %d ouro" % ItemDB.get_item(c.seed).price, UITheme.GOLD])
	ActionModal.open(self, "Plantar no canteiro %d" % (plot_index + 1), c.seed, lines, "Plantar", plant_now, n)


## Planta a semente escolhida neste canteiro (sem perguntar; a janela fecha quando o Econ confirmar).
func plant_now() -> void:
	if _sel != "":
		Game.plant(plot_index, _sel, true)


## Confirmação de plantar em todos os canteiros vazios, com quantas sementes faltam comprar.
func _plant_all() -> void:
	if _sel == "" or not _batch.is_empty() or all_btn.disabled:
		return
	var c: Dictionary = ItemDB.CROPS[_sel]
	var k := _empty_plots().size()
	var n := Game.count_item(c.seed)
	var lines := [["%d canteiros vazios" % k, UITheme.TEXT]]
	if n < k:
		lines.append(["Compra %d sementes por %d ouro" % [k - n, (k - n) * int(ItemDB.get_item(c.seed).price)], UITheme.GOLD])
	ActionModal.open(self, "Plantar %s em todos" % c.name, c.seed, lines, "Plantar %d" % k, plant_all_now, n)


## Planta em todos os canteiros vazios, comprando o que faltar. Um pedido por vez: o próximo só sai quando
## o anterior é confirmado; a primeira recusa (ex.: acabou o ouro) ou a queda da conexão encerra o lote.
func plant_all_now() -> void:
	if _sel == "" or not _batch.is_empty():
		return
	var order := _empty_plots()
	order.erase(plot_index)
	order.push_front(plot_index)
	_batch = {"crop": _sel, "queue": order, "ok": 0}
	_plant_next()


func _plant_next() -> void:
	if _batch.queue.is_empty():
		_finish_batch()
		return
	var i: int = _batch.queue.pop_front()
	Game.plant(i, _batch.crop, true)


func _finish_batch() -> void:
	var b := _batch
	_batch = {}
	if b.ok > 0:
		Sfx.play("plant", 0.1)
		Game.notify.emit("%d canteiros de %s plantados." % [b.ok, ItemDB.CROPS[b.crop].name], Color(0.8, 1.0, 0.6))
		_close()


func _buy5() -> void:
	if _sel != "":
		Game.buy(ItemDB.CROPS[_sel].seed, 5)


func _on_econ_done(op: String, args: Array, ok: bool, _err: String, _events: Array) -> void:
	match op:
		"plant":
			if not _batch.is_empty():
				if ok:
					_batch.ok += 1
					_plant_next()
				else:
					_finish_batch()
			elif ok and not args.is_empty() and args[0] == plot_index:
				Sfx.play("plant", 0.1)
				_close()
		"buy":
			if ok:
				Sfx.play("coin")


func _close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_close()
