extends Control
## Menu de plantio de um canteiro vazio: escolher semente, plantar aqui ou em todos os vazios.
## Se faltar semente, compra na hora (sementeira da horta).

signal closed

var plot_index := 0
var seed_list: ItemList
var info: Label
var gold_label: Label
var plant_btn: Button
var all_btn: Button
## "Plantar em todos" em andamento: {"crop", "queue" (canteiros a pedir), "ok"} ({} = nenhum).
var _batch := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := UITheme.centered_panel(self, 0.45)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	var top := HBoxContainer.new()
	top.add_child(UITheme.label("Canteiro %d — Plantar" % (plot_index + 1), 28, UITheme.GOLD))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	gold_label = UITheme.label("", 22, Color(1, 0.85, 0.35))
	top.add_child(gold_label)
	v.add_child(top)
	v.add_child(UITheme.label("Regue depois de plantar: cresce 2x mais rápido e rende +1.", 16, UITheme.DIM))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	v.add_child(h)
	seed_list = ItemList.new()
	seed_list.custom_minimum_size = Vector2(470, 300)
	seed_list.item_selected.connect(func(_i: int) -> void: _update_info())
	seed_list.item_activated.connect(func(_i: int) -> void: _plant_here())
	h.add_child(seed_list)
	info = UITheme.label("", 16)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(380, 300)
	h.add_child(info)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	plant_btn = UITheme.button("Plantar aqui", _plant_here, 230)
	all_btn = UITheme.button("Plantar em todos os vazios", _plant_all, 290)
	btns.add_child(plant_btn)
	btns.add_child(all_btn)
	btns.add_child(UITheme.button("Comprar 5", _buy5, 140))
	btns.add_child(UITheme.button("Sair", _close, 120))
	v.add_child(btns)
	v.add_child(UITheme.label("Duplo clique planta · E ou Esc fecha", 14, UITheme.DIM))

	Game.inventory_changed.connect(_refresh)
	Game.stats_changed.connect(_refresh)
	Econ.done.connect(_on_econ_done)
	_refresh()
	# começa na semente que o jogador tem (ou na primeira)
	var pick := 0
	for i in ItemDB.CROP_ORDER.size():
		if Game.count_item(ItemDB.CROPS[ItemDB.CROP_ORDER[i]].seed) > 0:
			pick = i
			break
	seed_list.select(pick)
	seed_list.grab_focus.call_deferred()
	_update_info()


func _selected_crop() -> String:
	var sel := seed_list.get_selected_items()
	return ItemDB.CROP_ORDER[sel[0]] if not sel.is_empty() else ""


func _refresh() -> void:
	gold_label.text = "◆ %d ouro" % Game.gold
	var sel := seed_list.get_selected_items()
	seed_list.clear()
	for crop in ItemDB.CROP_ORDER:
		var c: Dictionary = ItemDB.CROPS[crop]
		var seed_it := ItemDB.get_item(c.seed)
		var n := Game.count_item(c.seed)
		var txt := "%s   %s" % [c.name, ("x%d" % n) if n > 0 else "(%d ouro)" % seed_it.price]
		seed_list.add_item(txt)
		var idx := seed_list.item_count - 1
		seed_list.set_item_tooltip_enabled(idx, false)
		if n > 0:
			seed_list.set_item_custom_fg_color(idx, c.color.lightened(0.35))
		elif Game.gold < seed_it.price:
			seed_list.set_item_custom_fg_color(idx, Color(0.55, 0.45, 0.45))
		else:
			seed_list.set_item_custom_fg_color(idx, UITheme.DIM)
	if not sel.is_empty():
		seed_list.select(sel[0])
	_update_info()


func _update_info() -> void:
	var crop := _selected_crop()
	if crop == "":
		return
	var c: Dictionary = ItemDB.CROPS[crop]
	var seed_it := ItemDB.get_item(c.seed)
	var n := Game.count_item(c.seed)
	var uses: Array[String] = []
	for r in ItemDB.RECIPE_ORDER:
		if ItemDB.RECIPES[r].has(crop):
			uses.append(ItemDB.get_item(r).name)
	info.text = "%s\n%s\n\nCresce em %ds (regado: %ds)\nRende %d–%d por colheita\nSementes: %d   ·   Preço: %d ouro\n\nUsada em: %s" % [
		c.name, seed_it.desc, int(c.time), int(c.time / 2.0), c.yield[0], c.yield[1], n, seed_it.price,
		", ".join(uses) if not uses.is_empty() else "—"]
	plant_btn.text = "Plantar aqui" if n > 0 else "Comprar e plantar (%d)" % seed_it.price
	var empties := _empty_plots()
	all_btn.text = "Plantar em todos os vazios (%d)" % empties.size()
	all_btn.disabled = empties.size() <= 1


func _empty_plots() -> Array[int]:
	var out: Array[int] = []
	for i in Game.FARM_PLOTS:
		if Game.plot_state(i) == "empty":
			out.append(i)
	return out


func _plant_here() -> void:
	var crop := _selected_crop()
	if crop == "":
		return
	Game.plant(plot_index, crop, true)   # fecha quando o Econ confirmar


## Planta a semente escolhida em todos os canteiros vazios, comprando o que faltar.
## Um pedido por vez: o próximo só sai quando o anterior é confirmado; a primeira recusa (ex.: acabou
## o ouro) ou a queda da conexão (Econ responde "sem_conexao") encerra o lote — nunca fica travado.
func _plant_all() -> void:
	var crop := _selected_crop()
	if crop == "" or not _batch.is_empty():
		return
	var order := _empty_plots()
	order.erase(plot_index)
	order.push_front(plot_index)
	_batch = {"crop": crop, "queue": order, "ok": 0}
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
	var crop := _selected_crop()
	if crop == "":
		return
	Game.buy(ItemDB.CROPS[crop].seed, 5)


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
