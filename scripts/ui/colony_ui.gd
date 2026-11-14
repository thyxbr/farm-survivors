extends Control
## Janelas da Defesa da Cidade.
## mode = "building": menu da construção (melhorar, reparar, demolir; prefeitura: economia e impostos;
##                    quartel: recrutar e dispensar soldados).
## mode = "defeat":   a prefeitura caiu.
## mode = "results":  fim da partida em grupo (noites, abates e recompensas do personagem).

signal closed

var mode := "building"
var building: ColonyBuilding
var colony: Colony
var world: Node

var results := {}

var _box: VBoxContainer
var _msg: Label
var _refresh := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := UITheme.centered_panel(self, 0.55)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	_box.custom_minimum_size = Vector2(560, 0)
	p.add_child(_box)
	_rebuild()
	# em grupo o estado chega do servidor: a janela se atualiza sozinha
	if colony and colony.role == "client" and mode == "building":
		colony.net_changed.connect(_on_net_changed)


func _on_net_changed() -> void:
	_refresh = true


func _process(_delta: float) -> void:
	if _refresh:
		_refresh = false
		if building != null and (not is_instance_valid(building) or building.dead):
			_close()
			return
		_rebuild()


func _rebuild() -> void:
	for c in _box.get_children():
		c.queue_free()
	var keep_msg := _msg.text if _msg else ""
	if mode == "defeat":
		_build_defeat()
	elif mode == "results":
		_build_results()
	else:
		_build_building()
	_msg = UITheme.label(keep_msg, 15, UITheme.BAD)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_msg)
	if mode == "building":
		var close := UITheme.button("Fechar  [Esc]", _close)
		_box.add_child(close)
		close.grab_focus.call_deferred()


func _title(t: String, c := UITheme.GOLD) -> Label:
	var l := UITheme.heading(t, 30, c)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _line(t: String, c := UITheme.TEXT, size := 16) -> Label:
	var l := UITheme.label(t, size, c)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 540
	return l


func _row() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	_box.add_child(h)
	return h


func _act(err: String) -> void:
	if err != "":
		_msg.text = err
		_msg.add_theme_color_override("font_color", UITheme.BAD)
		Sfx.play("click", 0.0, -6.0)
	else:
		_msg.text = ""
	if building != null and (not is_instance_valid(building) or building.dead):
		_close()
		return
	_rebuild()


# ================================================================ construção
func _build_building() -> void:
	var b := building
	var d := b.data
	_box.add_child(_title("%s  ·  Nível %d" % [d.name, b.level]))
	_box.add_child(_line(d.desc, UITheme.DIM, 15))
	var hp := UITheme.bar(UITheme.HP, 540, 14)
	hp.max_value = b.max_hp
	hp.value = b.hp
	_box.add_child(hp)
	_box.add_child(_line("Vida %d / %d" % [int(b.hp), int(b.max_hp)], UITheme.TEXT, 14))
	_box.add_child(_line(_stats(b), UITheme.TEXT, 15))

	var h := _row()
	if b.level < ColonyData.MAX_LEVEL:
		var cost := colony.upgrade_cost(b)
		var up := UITheme.button("Melhorar p/ nível %d — %s" % [b.level + 1, ColonyData.cost_text(cost)], func() -> void: _act(colony.upgrade(b)))
		up.disabled = colony.missing(cost) != ""
		h.add_child(up)
	else:
		h.add_child(UITheme.label("Nível máximo", 15, UITheme.DIM))
	var rc := colony.repair_cost(b)
	if not rc.is_empty():
		var rep := UITheme.button("Reparar — %s" % ColonyData.cost_text(rc), func() -> void: _act(colony.repair(b)))
		rep.disabled = colony.missing(rc) != ""
		h.add_child(rep)
	if not b.is_core:
		h.add_child(UITheme.button("Demolir (+%s)" % ColonyData.cost_text(colony.refund_of(b)), func() -> void:
			colony.demolish(b)
			_close()))

	match b.kind:
		"town_hall":
			_build_hall()
		"barracks":
			_build_barracks()


func _stats(b: ColonyBuilding) -> String:
	var lv := b.level
	match b.kind:
		"town_hall":
			return "Abriga %d moradores · rende %d ouro por dia." % [int(b.data.pop) + 4 * (lv - 1), int(b.data.gold) * lv]
		"house":
			return "Abriga %d moradores." % (int(b.data.pop) + 3 * (lv - 1))
		"farm":
			return "Produz %d comida por dia (com %d trabalhadores)." % [int(round(b.data.food * ColonyData.level_mult(lv, 0.5))), b.data.workers]
		"market":
			return "Rende %d ouro por dia (com %d trabalhadores)." % [int(round(b.data.gold * ColonyData.level_mult(lv, 0.5))), b.data.workers]
		"barracks":
			return "Aloja %d soldados." % (int(b.data.army) + 3 * (lv - 1))
		"spikes":
			return "%d de dano por segundo em quem pisa." % int(b.data.dps * ColonyData.level_mult(lv, 0.5))
	if ColonyData.is_tower(b.kind):
		return "Alcance %d m · dano %d · um disparo a cada %.1f s." % [int(b.tower_range()), int(b.tower_damage()), b.tower_rate()]
	return ""


func _build_hall() -> void:
	var f := colony.forecast()
	_box.add_child(UITheme.section("Economia — previsão para o amanhecer", 18))
	_box.add_child(_line("Impostos: %d moradores × %d = +%d ouro" % [colony.citizens, ColonyData.TAX[colony.tax_level], f.tax]))
	_box.add_child(_line("Comércio (mercados): +%d ouro   ·   Prefeitura: +%d ouro" % [f.trade, f.hall]))
	_box.add_child(_line("Salários do exército: −%d ouro" % f.salaries, UITheme.BAD if f.salaries > 0 else UITheme.TEXT))
	if colony.is_coop():
		_box.add_child(_line("Manutenção das torres e quartéis: −%d ouro" % f.upkeep, UITheme.BAD if f.upkeep > 0 else UITheme.TEXT))
	_box.add_child(_line("Saldo do dia: %+d ouro   (cofre%s: %d)" % [f.gold_net, " de todos" if colony.is_coop() else "", colony.get_gold()],
		UITheme.GOOD if f.gold_net >= 0 else UITheme.BAD))
	_box.add_child(_line("Comida: +%d colhida, −%d consumida = %+d   (estoque: %d)" % [f.food_in, f.food_out, f.food_net, colony.food],
		UITheme.GOOD if f.food_net >= 0 else UITheme.BAD))
	if f.workers > colony.citizens:
		_box.add_child(_line("Faltam trabalhadores: %d vagas e %d moradores — fazendas e mercados rendem %d%%." %
			[f.workers, colony.citizens, int(f.eff * 100)], Color(1, 0.75, 0.45), 14))
	_box.add_child(_line("Moradores: %d / %d. Imposto alto rende mais, mas a cidade cresce devagar." % [colony.citizens, colony.pop_cap()], UITheme.DIM, 14))
	if colony.is_coop():
		_box.add_child(_line("Em grupo cada cópia de uma construção custa mais, mercados além do %dº rendem menos e torres pedem manutenção." % ColonyData.MARKET_FREE,
			UITheme.DIM, 14))
	var h := _row()
	h.add_child(UITheme.label("Imposto:", 16))
	for i in 3:
		var btn := UITheme.button("%s (%d/morador, +%d/dia)" % [ColonyData.TAX_NAMES[i], ColonyData.TAX[i], ColonyData.GROWTH[i]],
			func() -> void:
				colony.set_tax(i)
				Sfx.play("click", 0.0)
				_act(""))
		btn.disabled = colony.tax_level == i
		h.add_child(btn)
	var h2 := _row()
	var rac := colony.repair_all_cost()
	var rep := UITheme.button("Reparar tudo — %s" % (ColonyData.cost_text(rac) if not rac.is_empty() else "nada a reparar"), func() -> void: _act(colony.repair_all()))
	rep.disabled = rac.is_empty() or colony.missing(rac) != ""
	h2.add_child(rep)
	if colony.phase == "day" and colony.is_coop():
		h2.add_child(UITheme.button("Votar pela noite (%d/%d)" % [colony.night_votes(), colony.votes_needed()], func() -> void:
			colony.start_night()
			_close()))
	elif colony.phase == "day":
		h2.add_child(UITheme.button("Chamar a noite agora", func() -> void:
			colony.start_night()
			_close()))
		h2.add_child(UITheme.button("Salvar cidade", func() -> void:
			if world.save_colony():
				_msg.text = "Cidade salva."
				_msg.add_theme_color_override("font_color", UITheme.GOOD)))


func _build_barracks() -> void:
	_box.add_child(UITheme.section("Recrutar — exército %d / %d · moradores livres %d" %
		[colony.soldier_count(), colony.army_cap(), colony.citizens], 18))
	for id in ColonyData.UNIT_ORDER:
		var u: Dictionary = ColonyData.UNITS[id]
		var h := _row()
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		h.add_child(info)
		info.add_child(UITheme.label("%s — %s" % [u.name, u.desc], 16))
		info.add_child(UITheme.label("Vida %d · dano %d · %s · salário %d/dia" % [u.hp, int(u.damage),
			"à distância" if u.get("ranged", false) else "corpo a corpo", u.salary], 13, UITheme.DIM))
		var btn := UITheme.button("Recrutar — %d" % u.cost, func() -> void: _act(colony.recruit(id)))
		btn.custom_minimum_size.x = 170
		btn.disabled = colony.get_gold() < int(u.cost) or colony.barracks_level() < int(u.get("needs_level", 1))
		h.add_child(btn)
	var counts := {}
	for s in colony.soldiers():
		counts[s.unit] = counts.get(s.unit, 0) + 1
	if not counts.is_empty():
		var parts: Array[String] = []
		for id in counts:
			parts.append("%d %s" % [counts[id], ColonyData.UNITS[id].name])
		_box.add_child(_line("No exército: " + ", ".join(parts) + ".", UITheme.TEXT, 15))
		var h2 := _row()
		h2.add_child(UITheme.button("Dispensar um soldado (vira morador)", func() -> void:
			var list := colony.soldiers()
			if not list.is_empty():
				colony.dismiss(list[list.size() - 1])
			_act("")))
	_box.add_child(_line("G: o exército segue você (bom para caçar) · V: muda o ponto de reunião para onde você está.", UITheme.DIM, 13))


# ================================================================ derrota
func _build_defeat() -> void:
	_box.add_child(_title("A cidade caiu", UITheme.BAD))
	_box.add_child(_line("Os monstros derrubaram a prefeitura no dia %d." % colony.day, UITheme.TEXT, 18))
	_box.add_child(_line("Monstros abatidos pela cidade: %d" % colony.total_kills, UITheme.DIM))
	_box.add_child(UITheme.button("Nova cidade", func() -> void: Game.start_colony(false)))
	var load_btn := UITheme.button("Carregar o último save", func() -> void: Game.start_colony(true))
	load_btn.disabled = not Game.has_colony_save()
	_box.add_child(load_btn)
	_box.add_child(UITheme.button("Menu principal", func() -> void: Game.go_to_menu()))


# ================================================================ fim da partida em grupo
func _build_results() -> void:
	var fell: bool = results.get("reason", "") == "defeat"
	_box.add_child(_title("A cidade caiu" if fell else "Partida encerrada", UITheme.BAD if fell else UITheme.GOLD))
	var nights := int(results.get("nights", 0))
	_box.add_child(_line("O grupo resistiu a %d noite(s) · %d monstros abatidos." % [nights, int(results.get("kills", 0))], UITheme.TEXT, 18))
	var names: Array = results.get("names", [])
	if not names.is_empty():
		_box.add_child(_line("Defensores: " + ", ".join(names), UITheme.DIM, 15))
	_box.add_child(UITheme.section("Suas recompensas (já estão no seu personagem)", 18))
	_box.add_child(_line("+%d ouro   ·   +%d XP" % [int(results.get("gold", 0)), int(results.get("xp", 0))], UITheme.GOLD, 17))
	var items: Array = results.get("items", [])
	var names_i: Array[String] = []
	for id in items:
		if ItemDB.ITEMS.has(str(id)) and str(id) != "health_potion":
			names_i.append(ItemDB.ITEMS[str(id)].name)
	if not names_i.is_empty():
		_box.add_child(_line("Baús: " + ", ".join(names_i), UITheme.GOOD, 16))
	elif nights < ColonyData.BOSS_EVERY:
		_box.add_child(_line("Sobreviva a %d noites para abrir o primeiro baú de equipamento." % ColonyData.BOSS_EVERY, UITheme.DIM, 14))
	var rec := int(results.get("record", 0))
	if rec > 0:
		_box.add_child(_line("Recorde do servidor: %d noite(s)%s" % [rec, " — novo recorde!" if rec == nights and nights > 0 else ""], UITheme.DIM, 15))
	_box.add_child(UITheme.button("Voltar ao salão", func() -> void: Lobby.go_lobby()))


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if mode == "building" and (event.is_action_pressed("pause") or event.is_action_pressed("interact")):
		get_viewport().set_input_as_handled()
		_close()
