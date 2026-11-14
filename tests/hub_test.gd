extends Node
## Teste automatizado da praça (solo). Rode com:
##   godot --headless --path . res://scenes/hub.tscn -- --hubtest
## Imprime PASS/FAIL para cada verificação e encerra com código 0 (ok) ou 1 (falhas).
## Usa um personagem solo novo num banco só dele (user://hubtest_solo.db, apagado no início), como o --colonytest.
## Confere: os 9 pontos da praça, Ecos do fim de partida, passiva e doação pelo Econ.request, o rótulo da
## Forja, os painéis abrindo e fechando, os emotes (e a réplica ignorando índice fora da lista) e o caminho
## portal → Horda → de volta à praça.

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("PASS  ", what)
	else:
		fails += 1
		print("FAIL  ", what)


func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, true).timeout


func _wait_until(cond: Callable, max_t: float) -> bool:
	var t := 0.0
	while not cond.call() and t < max_t:
		await wait(0.1)
		t += 0.1
	return cond.call()


func _hub() -> Node:
	var s := get_tree().current_scene
	return s if s != null and s.get("role") == "hub" else null


func _point(hub: Node, kind: String, building := "") -> Node:
	for p in hub.points:
		if p.kind == kind and p.building_id == building:
			return p
	return null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await wait(0.8)
	var hub := _hub()
	check(hub != null and hub.player != null, "praça carregada com o cavaleiro")
	if hub == null:
		_finish()
		return
	var fresh := CharState.new_character(Balance.tables)
	check(Econ.ensure_solo() and Game.ecos == 0 and Game.passives.is_empty() and Game.gold == fresh.gold,
		"personagem solo novo (Ecos %d)" % Game.ecos)

	# --- os 9 pontos interagíveis
	check(hub.points.size() == 9, "praça monta os 9 pontos (%d)" % hub.points.size())
	var interactable := 0
	for p in hub.points:
		if p.is_in_group("interactable") and p.interact_prompt() != "":
			interactable += 1
	check(interactable == 9, "os 9 pontos são interagíveis com texto de [E] (%d)" % interactable)
	for b in ["forja", "muralha", "celeiro"]:
		check(_point(hub, "building", b) != null, "ponto da construção %s" % b)
	check(hub.player.build_lock and hub.player.peaceful, "cavaleiro da praça não ataca")

	# --- Ecos do fim de partida (solo: CharacterService local)
	var got := Econ.run_finish(Econ.run_start("horde"), "horde", 10, 0, 0, {})
	check(got == 50 and Game.ecos == 50, "Horda até a rodada 10 dá 50 Ecos (%d, saldo %d)" % [got, Game.ecos])

	# --- painel do Mestre Orin acompanha Ecos que chegam com ele aberto (Econ.done)
	hub.open_point_panel(_point(hub, "passive_master"))
	var orin: Control = hub.modal
	check(orin != null and orin.get("ecos_label") != null, "painel do Mestre Orin abre")
	var extra := RewardRules.ecos(Balance.tables, "horde", 40)
	Econ.run_finish(Econ.run_start("horde"), "horde", 40, 0, 0, {})
	check(Game.ecos == 50 + extra and orin.ecos_label.text.contains(str(Game.ecos)),
		"painel aberto mostra os Ecos novos (%s)" % orin.ecos_label.text)

	# --- passiva pelo Econ.request
	var e0 := Game.ecos
	var cost := int(Balance.tables.get_table("meta_passives").passives.poder.cost[0])
	var dmg0 := Game.mod("damage")
	Econ.request("buy_passive", ["poder"])
	check(Game.ecos == e0 - cost and int(Game.passives.get("poder", 0)) == 1,
		"passiva Poder comprada (Ecos %d → %d, nível %d)" % [e0, Game.ecos, int(Game.passives.get("poder", 0))])
	check(is_equal_approx(Game.mod("damage"), dmg0 + 0.03), "Poder 1 soma 3%% de dano (%.2f → %.2f)" % [dmg0, Game.mod("damage")])
	await wait(0.1)
	check(orin.ecos_label.text.contains(str(Game.ecos)), "painel redesenha depois da compra (%s)" % orin.ecos_label.text)
	orin._close()
	await wait(0.1)
	check(hub.modal == null and not get_tree().paused, "painel do Mestre Orin fecha e a praça volta")

	# --- doação pelo Econ.request: sobe a Forja, a placa mostra o nível novo
	var forge_cost := int(Balance.tables.get_table("base_buildings").buildings.forja.levels[0].cost)
	var forge := _point(hub, "building", "forja")
	check(forge != null and forge._label.text.contains("nível 0"), "placa da Forja no nível 0 (%s)" % forge._label.text)
	e0 = Game.ecos
	Econ.request("donate", ["forja", forge_cost])
	check(Game.ecos == e0 - forge_cost, "doação desconta os Ecos (%d → %d)" % [e0, Game.ecos])
	var entry: Dictionary = Hub.base.get("forja", {})
	check(int(entry.get("level", 0)) == 1 and BaseRules.total_invested(Balance.tables, "forja", entry) == forge_cost,
		"Hub.base: Forja no nível 1 (%s)" % str(entry))
	check(forge._label.text.contains("nível 1"), "placa da Forja mostra o nível novo (%s)" % forge._label.text)
	var donors: Array = entry.get("donors", [])
	check(donors.size() == 1 and donors[0].name == Hub.SOLO_NAME and int(donors[0].amount) == forge_cost,
		"doador do solo aparece como \"%s\" (%s)" % [Hub.SOLO_NAME, str(donors)])
	check(is_equal_approx(float(Hub.base_bonus().get("horde_damage", 0.0)),
		float(Balance.tables.get_table("base_buildings").buildings.forja.levels[0].bonus.horde_damage)),
		"bônus da Forja vale no solo (%s)" % str(Hub.base_bonus()))
	var rec: Dictionary = Hub.records.get("horde", {})
	check(int(rec.get("reached", 0)) == 40 and rec.get("names", []) == [Hub.SOLO_NAME],
		"recorde da Horda na praça (%s)" % str(rec))

	# --- cada painel abre e fecha
	for p in hub.points:
		if p.kind == "road":
			continue
		hub.open_point_panel(p)
		var ui: Control = hub.modal
		var label := "%s%s" % [p.kind, (" " + p.building_id) if p.building_id != "" else ""]
		check(ui != null and ui.is_inside_tree(), "painel abre: %s" % label)
		if ui == null:
			continue
		await wait(0.1)
		ui._close()
		await wait(0.1)
		check(hub.modal == null and not get_tree().paused, "painel fecha: %s" % label)

	# --- painel da construção acompanha Ecos que chegam com ele aberto
	hub.open_point_panel(_point(hub, "building", "muralha"))
	var wall: Control = hub.modal
	Econ.run_finish(Econ.run_start("horde"), "horde", 5, 0, 0, {})
	check(wall != null and wall.ecos_label.text.contains(str(Game.ecos)), "painel da construção mostra os Ecos novos (%s)" % wall.ecos_label.text)
	wall._close()
	await wait(0.1)

	# --- emotes
	for k in KnightEmotes.KINDS:
		var pose: Dictionary = KnightEmotes.pose(k, 0.8)
		check(not pose.is_empty() and pose != KnightAnim.idle_pose(0.8), "pose do emote %s" % k)
	check(KnightEmotes.KINDS.size() == 3, "3 emotes (%s)" % str(KnightEmotes.KINDS))
	await _wait_until(func() -> bool: return hub.player.is_on_floor(), 3.0)
	hub.player.play_emote("acenar")
	check(hub.player.emote == "acenar", "jogador acena (%s)" % hub.player.emote)
	hub.player.play_emote("dancar")
	check(hub.player.emote == "acenar", "emote desconhecido é ignorado")
	# réplica: índice pela rede; -1 cancela, fora da lista é ignorado
	var rp: Player = preload("res://scripts/player/player.gd").new()
	rp.remote = true
	rp.display_name = "Réplica"
	rp.position = Vector3(3, 0.5, 10)
	hub.add_child(rp)
	await wait(0.1)
	check(rp.name_tag != null and rp.name_tag.text == "Réplica", "réplica com o nome em cima")
	rp.play_remote_event("emote", Vector3(2, 0, 0), Vector3.ZERO)
	check(rp.emote == "sentar", "réplica senta pelo índice (%s)" % rp.emote)
	rp.play_remote_event("emote", Vector3(99, 0, 0), Vector3.ZERO)
	check(rp.emote == "sentar", "índice fora da lista é ignorado pela réplica (%s)" % rp.emote)
	rp.play_remote_event("emote", Vector3(-1, 0, 0), Vector3.ZERO)
	check(rp.emote == "", "índice -1 cancela o emote da réplica")
	rp.queue_free()

	# --- portal → Horda em Valdoria → de volta à praça
	var ecos_before := Game.ecos
	Hub.go_horde()
	var in_world: bool = await _wait_until(func() -> bool:
		var s := get_tree().current_scene
		return s != null and s.get("survival") != null and s.get("role") == null, 15.0)
	check(in_world, "portal leva à Horda em Valdoria")
	if in_world:
		var w: Node = get_tree().current_scene
		var sv = w.survival
		check(sv.return_to_hub, "partida do portal volta para a praça")
		await wait(1.5)
		var rounds: int = sv.rounds_cleared
		sv.end_run("retreat")
		check(await _wait_until(func() -> bool: return w.modal != null and w.modal.get("mode") == "results", 3.0),
			"resultados ao se retirar")
		await wait(0.6)
		if w.modal != null:
			w.modal._finish()
		check(await _wait_until(func() -> bool: return _hub() != null and _hub().player != null, 15.0),
			"voltou para a praça depois da Horda")
		check(Game.ecos == ecos_before + RewardRules.ecos(Balance.tables, "horde", rounds),
			"Ecos da partida do portal (%d → %d)" % [ecos_before, Game.ecos])
		check(not Hub.horde_return and not Hub.pending_horde, "pedido de Horda da praça consumido")
	_finish()


func _finish() -> void:
	print("HUBTEST %s (%d falhas)" % ["OK" if fails == 0 else "FALHOU", fails])
	get_tree().paused = false
	get_tree().quit(1 if fails > 0 else 0)
