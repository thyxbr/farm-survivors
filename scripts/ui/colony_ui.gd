extends Control
## Janelas da Defesa da Cidade.
## mode = "building": menu da construção (melhorar, reparar, demolir; prefeitura: economia e impostos;
##                    quartel: recrutar e dispensar soldados).
## mode = "trade":    trocas com a caravana do evento do dia (ColonyData.TRADES).
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
var _train_bar: ProgressBar
var _train_shown := 0   # tamanho da fila quando a janela foi montada
var _busy_bar: ProgressBar   # progresso da era/pesquisa desta construção


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
	if colony and colony.role == "client" and mode in ["building", "trade"]:
		colony.net_changed.connect(_on_net_changed)


func _on_net_changed() -> void:
	_refresh = true


func _process(_delta: float) -> void:
	if mode == "trade" and colony.events.active != "caravan":
		_close()   # a caravana partiu (anoiteceu)
		return
	if _refresh:
		_refresh = false
		if building != null and (not is_instance_valid(building) or building.dead):
			_close()
			return
		_rebuild()
	elif _busy_bar != null and is_instance_valid(_busy_bar):
		if building == null or not colony.busy_t.has(building.net_id):
			_rebuild()   # a era/pesquisa terminou
		else:
			_busy_bar.value = float(colony.busy_t[building.net_id][1])
	elif _train_bar != null and is_instance_valid(_train_bar):
		if colony.train_queue != _train_shown:
			_rebuild()   # a fila andou
		else:
			_train_bar.value = colony.train_t


func _rebuild() -> void:
	for c in _box.get_children():
		c.queue_free()
	_train_bar = null
	_busy_bar = null
	var keep_msg := _msg.text if _msg else ""
	if mode == "defeat":
		_build_defeat()
	elif mode == "results":
		_build_results()
	elif mode == "trade":
		_build_trade()
	else:
		_build_building()
	_msg = UITheme.label(keep_msg, 15, UITheme.BAD)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_msg)
	if mode in ["building", "trade"]:
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
	if b.is_core:
		pass   # a prefeitura sobe de nível avançando de era (seção abaixo)
	elif b.level < ColonyData.MAX_LEVEL:
		var cost := colony.upgrade_cost(b)
		var up := UITheme.button("Melhorar p/ nível %d — %s" % [b.level + 1, ColonyData.cost_text(cost)], func() -> void: _act(colony.upgrade(b)))
		up.disabled = colony.missing(cost) != "" or b.level >= colony.era()
		h.add_child(up)
		if b.level >= colony.era():
			h.add_child(UITheme.label("(exige a era %s)" % ColonyData.ERA_ROMAN[b.level + 1], 14, UITheme.BAD))
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

	if colony.busy_t.has(b.net_id):
		var act: String = colony.busy_t[b.net_id][0]
		var bh := _row()
		bh.add_child(UITheme.label("Avançando para a era %s" % ColonyData.ERAS[b.level + 1].name if act == "era"
			else "Pesquisando: %s" % ColonyData.TECHS[act].name, 15, UITheme.GOLD))
		_busy_bar = UITheme.bar(UITheme.GOLD, 200, 14)
		_busy_bar.max_value = ColonyData.ERA_TIME if act == "era" else ColonyData.TECH_TIME
		_busy_bar.value = float(colony.busy_t[b.net_id][1])
		bh.add_child(_busy_bar)
		if colony.phase != "day":
			bh.add_child(UITheme.label("(só avança de dia)", 13, UITheme.DIM))
	match b.kind:
		"town_hall":
			_build_era()
			_build_hall()
		"barracks":
			_build_barracks()
	_build_techs(b)


## Prefeitura: avançar de era, com os requisitos que faltam em vermelho.
func _build_era() -> void:
	var e := colony.era()
	_box.add_child(UITheme.section("Era %s" % ColonyData.ERAS[e].name, 18))
	if e >= ColonyData.MAX_LEVEL:
		_box.add_child(_line("A cidade está na última era.", UITheme.DIM, 14))
		return
	var cost := ColonyData.era_cost(e + 1, colony.team_size)
	var req := colony.era_requirements(e + 1)
	var h := _row()
	var btn := UITheme.button("Avançar para a era %s — %s" % [ColonyData.ERA_ROMAN[e + 1], ColonyData.cost_text(cost)],
		func() -> void: _act(colony.advance_era()))
	btn.disabled = req != "" or colony.missing(cost) != "" or colony.busy_t.has(building.net_id) or colony.phase != "day"
	h.add_child(btn)
	if req != "":
		_box.add_child(_line(req, UITheme.BAD, 14))
	_box.add_child(_line("Leva %d s de dia; enquanto isso a prefeitura não treina aldeões." % int(ColonyData.ERA_TIME), UITheme.DIM, 13))


## Pesquisas feitas nesta construção: comprada, bloqueada pela era ou com preço.
func _build_techs(b: ColonyBuilding) -> void:
	var list: Array = []
	for t in ColonyData.TECH_ORDER:
		if ColonyData.TECHS[t].at == b.kind:
			list.append(t)
	if list.is_empty():
		return
	_box.add_child(UITheme.section("Pesquisas", 18))
	for t in list:
		var d: Dictionary = ColonyData.TECHS[t]
		var h := _row()
		var info := UITheme.label("%s — %s" % [d.name, d.desc], 15)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		if colony.has_tech(t):
			h.add_child(UITheme.label("Pesquisada", 14, UITheme.GOOD))
		elif colony.era() < int(d.era):
			h.add_child(UITheme.label("Exige a era %s" % ColonyData.ERA_ROMAN[int(d.era)], 14, UITheme.BAD))
		else:
			var btn := UITheme.button("Pesquisar — %s" % ColonyData.cost_text(d.cost), func() -> void: _act(colony.research(t)))
			btn.disabled = colony.tech_block(t) != "" or colony.missing(d.cost) != ""
			h.add_child(btn)


func _stats(b: ColonyBuilding) -> String:
	var lv := b.level
	match b.kind:
		"town_hall":
			return "Abriga %d moradores · rende %d ouro por dia." % [int(b.data.pop) + 4 * (lv - 1), int(b.data.gold) * lv]
		"house":
			return "Abriga %d moradores." % (int(b.data.pop) + 3 * (lv - 1))
		"farm":
			return "Produz %d comida por dia (com %d aldeões)." % [int(round(b.data.food * ColonyData.level_mult(lv, 0.5) * colony.mult("food"))), colony.crew_for(b.kind)]
		"market":
			return "Rende %d ouro por dia (com %d aldeões)." % [int(round(b.data.gold * ColonyData.level_mult(lv, 0.5))), colony.crew_for(b.kind)]
		"barracks":
			return "Aloja %d soldados." % (int(b.data.army) + 3 * (lv - 1))
		"spikes":
			return "%d de dano por segundo em quem pisa." % int(b.data.dps * ColonyData.level_mult(lv, 0.5))
	if ColonyData.is_tower(b.kind):
		return "Ocupa %d aldeão · alcance %d m · dano %d · um disparo a cada %.1f s." % [int(b.data.crew), int(b.tower_range()), int(b.tower_damage()), b.tower_rate()]
	return ""


func _build_hall() -> void:
	var f := colony.forecast()
	_box.add_child(UITheme.section("Economia — previsão para o amanhecer", 18))
	_box.add_child(_line("Impostos: %d moradores × %d = +%d ouro" % [colony.citizens, ColonyData.TAX[colony.tax_level], f.tax]))
	_box.add_child(_line("Comércio (mercados): +%d ouro   ·   Prefeitura: +%d ouro" % [f.trade, f.hall]))
	_box.add_child(_line("Salários do exército: −%d ouro" % f.salaries, UITheme.BAD if f.salaries > 0 else UITheme.TEXT))
	if colony.is_coop():
		_box.add_child(_line("Manutenção das torres e quartéis: −%d ouro" % f.upkeep, UITheme.BAD if f.upkeep > 0 else UITheme.TEXT))
	_box.add_child(_line("Saldo do dia: %+d ouro   (%s: %d)" % [f.gold_net, "cofre de todos" if colony.is_coop() else "caixa da cidade", colony.get_gold()],
		UITheme.GOOD if f.gold_net >= 0 else UITheme.BAD))
	_box.add_child(_line("Comida: +%d colhida, −%d consumida = %+d   (estoque: %d)" % [f.food_in, f.food_out, f.food_net, colony.food],
		UITheme.GOOD if f.food_net >= 0 else UITheme.BAD))
	if f.workers > colony.citizens:
		_box.add_child(_line("Faltam aldeões: %d vagas e %d aldeões — fazendas e mercados rendem %d%% e as torres atiram mais devagar." %
			[f.workers, colony.citizens, int(f.eff * 100)], Color(1, 0.75, 0.45), 14))
	_box.add_child(_line("Aldeões: %d / %d (%d livres, %d ocupados). Eles não nascem sozinhos: treine mais aqui." %
		[colony.citizens, colony.pop_cap(), colony.free_villagers(), colony.busy()], UITheme.DIM, 14))
	var tr := _row()
	var train := UITheme.button("Treinar aldeão — %s" % ColonyData.cost_text(ColonyData.VILLAGER_COST), func() -> void: _act(colony.train_villager()))
	train.disabled = colony.citizens + colony.train_queue >= colony.pop_cap() or colony.missing(ColonyData.VILLAGER_COST) != ""
	tr.add_child(train)
	if colony.train_queue > 0:
		tr.add_child(UITheme.label("Na fila: %d" % colony.train_queue, 15, UITheme.GOLD))
		_train_bar = UITheme.bar(UITheme.GOLD, 200, 14)
		_train_bar.max_value = ColonyData.VILLAGER_TIME
		_train_bar.value = colony.train_t
		tr.add_child(_train_bar)
		_train_shown = colony.train_queue
		if colony.phase != "day":
			tr.add_child(UITheme.label("(só treina de dia)", 13, UITheme.DIM))
	if colony.is_coop():
		_box.add_child(_line("Em grupo cada cópia de uma construção custa mais, mercados além do %dº rendem menos e torres pedem manutenção." % ColonyData.MARKET_FREE,
			UITheme.DIM, 14))
	var h := _row()
	h.add_child(UITheme.label("Imposto:", 16))
	for i in 3:
		var btn := UITheme.button("%s (%d/aldeão)" % [ColonyData.TAX_NAMES[i], ColonyData.TAX[i]],
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
	_box.add_child(UITheme.section("Recrutar — exército %d / %d · aldeões livres %d" %
		[colony.soldier_count(), colony.army_cap(), colony.free_villagers()], 18))
	for id in ColonyData.UNIT_ORDER:
		var u: Dictionary = ColonyData.UNITS[id]
		var h := _row()
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		h.add_child(info)
		info.add_child(UITheme.label("%s — %s" % [u.name, u.desc], 16))
		var need_era := int(u.get("needs_era", 1))
		var era_txt := " · exige era %s" % ColonyData.ERA_ROMAN[need_era] if need_era > 1 else ""
		info.add_child(UITheme.label("Vida %d · dano %d · %s · salário %d/dia%s" % [u.hp, int(u.damage),
			"à distância" if u.get("ranged", false) else "corpo a corpo", u.salary, era_txt], 13, UITheme.DIM))
		info.add_child(UITheme.label("Custo: %s" % ColonyData.cost_text(ColonyData.cost_from(u.cost)), 13, UITheme.DIM))
		var btn := UITheme.button("Recrutar", func() -> void: _act(colony.recruit(id)))
		btn.custom_minimum_size.x = 170
		btn.disabled = colony.missing(ColonyData.cost_from(u.cost)) != "" or colony.era() < need_era
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
	var rw: Dictionary = world.get("last_run") if world != null and world.get("last_run") is Dictionary else {}
	if int(rw.get("gold", 0)) > 0 or int(rw.get("xp", 0)) > 0:
		_box.add_child(_line("Seu personagem ficou com: +%d ouro · +%d XP (recompensas das noites). O caixa da cidade se perdeu." %
			[int(rw.gold), int(rw.xp)], UITheme.GOLD, 16))
	_box.add_child(UITheme.button("Nova cidade", func() -> void: Game.start_colony(false)))
	var load_btn := UITheme.button("Carregar o último save", func() -> void: Game.start_colony(true))
	load_btn.disabled = not Game.has_colony_save()
	_box.add_child(load_btn)
	_box.add_child(UITheme.button("Menu principal", func() -> void: Game.go_to_menu()))


# ================================================================ caravana
func _build_trade() -> void:
	_box.add_child(_title("Caravana de mercadores"))
	_box.add_child(_line("Trocas com o cofre da cidade. A caravana parte ao anoitecer.", UITheme.DIM, 15))
	var stock: Array[String] = []
	for r in ColonyData.RESOURCES:
		if r != "food":
			stock.append("%s %d" % [ColonyData.RES_NAMES[r], colony.amount(r)])
	_box.add_child(_line("No cofre: " + "  ·  ".join(stock), UITheme.TEXT, 15))
	for i in ColonyData.TRADES.size():
		var give: Dictionary = ColonyData.TRADES[i][0]
		var take: Dictionary = ColonyData.TRADES[i][1]
		var btn := UITheme.button("Dar %s  →  receber %s" % [ColonyData.cost_text(give), ColonyData.cost_text(take)],
			func() -> void: _act(colony.trade(i)))
		btn.disabled = colony.missing(give) != ""
		_box.add_child(btn)


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
	if mode in ["building", "trade"] and (event.is_action_pressed("pause") or event.is_action_pressed("interact")):
		get_viewport().set_input_as_handled()
		_close()
