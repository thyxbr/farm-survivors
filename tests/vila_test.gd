extends Node
## Teste automatizado da vila de Valdoria (solo), o ponto de chegada desde que a praça da cidade saiu. Rode com:
##   godot --headless --path . res://scenes/world.tscn -- --vilatest
## Imprime PASS/FAIL para cada verificação e encerra com código 0 (ok) ou 1 (falhas).
## Usa um personagem solo novo num arquivo só dele (user://vilatest_solo.json, apagado no início).
## Confere: os bairros novos (casas variadas, pintadas), o Mestre Orin e o quadro de recordes (os pontos que
## vieram da praça), Ecos do fim de partida, passiva pelo Econ.request, o quadro de recordes, os painéis abrindo e
## fechando, o Papai Noel e os quatro eventos de Natal (presentes, ladrões, ceia e entregas), a réplica com
## emotes, a Horda pelo portal da vila (arena num mapa à parte, volta à vila na frente do portal) e a tela de
## carregamento.

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


func _vila() -> Node:
	var s := get_tree().current_scene
	return s if s != null and s.get("role") == null and s.get("points") != null and s.get("built") else null


## Texto do saldo no painel do Mestre Orin (passive_master_ui).
func _ecos_text() -> String:
	return "✦ %d Ecos" % Game.ecos


func _point(w: Node, kind: String) -> Node:
	for p in w.points:
		if p.kind == kind:
			return p
	return null


func _event_points(w: Node, kind: String) -> Array:
	return w.get_children().filter(func(n) -> bool: return n is ChristmasEventPoint and n.kind == kind)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _wait_until(func() -> bool: return _vila() != null and _vila().player != null, 20.0)
	await wait(0.5)
	var w := _vila()
	check(w != null and w.player != null, "vila carregada com o cavaleiro")
	if w == null:
		_finish()
		return
	var fresh := CharState.new_character(Balance.tables)
	check(Econ.ensure_solo() and Game.ecos == 0 and Game.passives.is_empty() and Game.gold == fresh.gold,
		"personagem solo novo (Ecos %d)" % Game.ecos)

	# --- bairros novos: casas de seis modelos, pintadas com as paletas
	var models := {}
	var tinted := 0
	for n in w.get_children():
		var src := str(n.scene_file_path)
		if src.begins_with("res://assets/models/house"):
			models[src.get_file().get_basename()] = true
			for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
				var any := false
				for s in mi.mesh.get_surface_count():
					if mi.get_surface_override_material(s) != null:
						any = true
				if any:
					tinted += 1
					break
	check(models.size() == 6, "seis modelos de casa na vila (%s)" % str(models.keys()))
	check(tinted >= VillageLayout.HOUSES.size(), "casas pintadas com as paletas (%d)" % tinted)

	# --- os pontos que vieram da praça: Mestre Orin e o quadro de recordes (sem mesa de guerra nem base)
	check(w.points.size() == 2, "vila monta o Orin e o quadro de recordes (%d)" % w.points.size())
	var interactable := 0
	for p in w.points:
		if p.is_in_group("interactable") and p.interact_prompt() != "":
			interactable += 1
	check(interactable == 2, "os 2 pontos são interagíveis com texto de [E] (%d)" % interactable)
	check(_point(w, "passive_master") != null and _point(w, "records") != null, "Orin e recordes na vila")
	check(not ResourceLoader.exists("res://scenes/colony.tscn"), "sem a Defesa da Cidade")
	# Orin (elder.glb) parado no idle, não em pose T; o cajado na mão
	var om: Node3D = _point(w, "passive_master").model
	var oaps := om.find_children("*", "AnimationPlayer")
	var oap: AnimationPlayer = oaps[0] if oaps.size() > 0 else null
	check(oap != null and oap.is_playing() and oap.current_animation == "mixamo/idle",
		"Mestre Orin toca o idle (%s)" % [oap.current_animation if oap else "sem AnimationPlayer"])
	var staff: Node = om.find_child("Staff", true, false)
	check(staff != null and staff.get_parent() is BoneAttachment3D and staff.get_parent().bone_name == "LeftHand",
		"cajado do Mestre Orin preso à mão esquerda")

	# --- Ecos do fim de partida (solo: CharacterService local)
	var got := Econ.run_finish(Econ.run_start("horde"), "horde", 10, 0, 0, {})
	check(got == 50 and Game.ecos == 50, "Horda até a rodada 10 dá 50 Ecos (%d, saldo %d)" % [got, Game.ecos])

	# --- painel do Mestre Orin acompanha Ecos que chegam com ele aberto (Econ.done)
	w.open_point_panel(_point(w, "passive_master"))
	var orin: Control = w.modal
	check(orin != null and orin.get("ecos_label") != null, "painel do Mestre Orin abre")
	var extra := RewardRules.ecos(Balance.tables, "horde", 40)
	Econ.run_finish(Econ.run_start("horde"), "horde", 40, 0, 0, {})
	check(Game.ecos == 50 + extra and orin.ecos_label.text == _ecos_text(),
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
	check(orin.ecos_label.text == _ecos_text(), "painel redesenha depois da compra (%s)" % orin.ecos_label.text)
	orin._close()
	await wait(0.1)
	check(w.modal == null and not get_tree().paused, "painel do Mestre Orin fecha e a vila volta")

	var rec: Dictionary = Hub.records.get("horde", {})
	check(int(rec.get("reached", 0)) == 40 and rec.get("names", []) == [Hub.SOLO_NAME],
		"recorde da Horda no quadro da vila (%s)" % str(rec))
	var board := _point(w, "records")
	check(board != null and board._label.text.begins_with("Horda: rodada 40"), "quadro mostra o recorde (%s)" % board._label.text)

	# --- cada painel abre e fecha
	for p in w.points:
		w.open_point_panel(p)
		var ui: Control = w.modal
		var label := str(p.kind)
		check(ui != null and ui.is_inside_tree(), "painel abre: %s" % label)
		if ui == null:
			continue
		await wait(0.1)
		ui._close()
		await wait(0.1)
		check(w.modal == null and not get_tree().paused, "painel fecha: %s" % label)

	await _christmas(w)

	# --- réplica: emotes pelo índice da rede; -1 cancela, fora da lista é ignorado
	for k in KnightEmotes.KINDS:
		var pose: Dictionary = KnightEmotes.pose(k, 0.8)
		check(not pose.is_empty() and pose != KnightAnim.idle_pose(0.8), "pose do emote %s" % k)
	var rp: Player = preload("res://scripts/player/player.gd").new()
	rp.remote = true
	rp.display_name = "Réplica"
	rp.position = Vector3(3, 0.5, 10)
	w.add_child(rp)
	await wait(0.1)
	check(rp.name_tag != null and rp.name_tag.text == "Réplica", "réplica com o nome em cima")
	rp.play_remote_event("emote", Vector3(2, 0, 0), Vector3.ZERO)
	check(rp.emote == "sentar", "réplica senta pelo índice (%s)" % rp.emote)
	rp.play_remote_event("emote", Vector3(99, 0, 0), Vector3.ZERO)
	check(rp.emote == "sentar", "índice fora da lista é ignorado pela réplica (%s)" % rp.emote)
	rp.play_remote_event("emote", Vector3(-1, 0, 0), Vector3.ZERO)
	check(rp.emote == "", "índice -1 cancela o emote da réplica")
	rp.queue_free()

	# --- portal da vila → Horda → de volta à vila, sem trocar de cena
	var ecos_before := Game.ecos
	w.start_survival()
	check(w.survival != null, "portal da vila abre o Desafio da Horda")
	if w.survival != null:
		var sv = w.survival
		await wait(1.5)
		var rounds: int = sv.rounds_cleared
		sv.end_run("retreat")
		check(await _wait_until(func() -> bool: return w.modal != null and w.modal.get("mode") == "results", 3.0),
			"resultados ao se retirar")
		await wait(0.6)
		if w.modal != null:
			w.modal._finish()
		check(await _wait_until(func() -> bool: return not is_instance_valid(w.survival) and w.modal == null, 5.0),
			"volta para a vila depois da Horda")
		check(get_tree().current_scene == w, "a Horda não troca de cena")
		check(w.player.global_position.distance_to(w.HORDE_RETURN) < 3.0, "volta na frente do portal da vila")
		check(Game.ecos == ecos_before + RewardRules.ecos(Balance.tables, "horde", rounds),
			"Ecos da partida do portal (%d → %d)" % [ecos_before, Game.ecos])
	await _loading_screen()
	_finish()


## Papai Noel e os quatro eventos de Natal.
func _christmas(w: Node) -> void:
	var santa: Node = w.get("santa")
	check(santa != null and santa is Santa, "Papai Noel na vila")
	if santa == null:
		return
	check(santa.anim != null and santa.anim.is_playing() and santa.anim.current_animation == "mixamo/idle",
		"Papai Noel toca o idle do Bram, não fica em pose T (%s)" % [santa.anim.current_animation if santa.anim else "-"])
	var cane: Node = santa.model.find_child("Staff", true, false)
	check(cane != null and cane.get_parent() is BoneAttachment3D, "bengala doce presa à mão do Noel")
	check(santa.marker.text == "!", "marcador azul de evento novo (%s)" % santa.marker.text)
	var offer: Array = santa._build_dialogue()
	var last: Dictionary = offer[offer.size() - 1] if not offer.is_empty() else {}
	check(last.has("choices") and str(last.choices[0].text) == str(ItemDB.QUESTS.natal_presentes.talk.accept),
		"Noel oferece o primeiro evento pelo roteiro em dados (%d páginas)" % offer.size())

	# Presentes Espalhados
	var gifts := _event_points(w, "gift")
	check(gifts.size() == 8 and gifts.all(func(g) -> bool: return not g.visible),
		"8 presentes no vale, escondidos antes de aceitar (%d)" % gifts.size())
	Game.start_quest("natal_presentes")
	await wait(0.1)
	check(Game.quest_state("natal_presentes") == "active", "Presentes Espalhados aceito")
	check(gifts.all(func(g) -> bool: return g.visible and g.is_in_group("interactable")), "presentes aparecem")
	gifts[0].interact(w.player)
	await wait(0.1)
	check(int(Game.quests.natal_presentes.progress) == 1 and Game.quest_got("natal_presentes") == [0],
		"pegar um presente conta 1 (%s)" % str(Game.quest_got("natal_presentes")))
	check(not gifts[0].visible and not gifts[0].is_in_group("interactable"), "presente pego some")
	Game.quest_mark("natal_presentes", 0)
	check(int(Game.quests.natal_presentes.progress) == 1, "o mesmo presente não conta de novo")
	for i in range(1, 8):
		gifts[i].interact(w.player)
	await wait(0.1)
	check(Game.quest_state("natal_presentes") == "ready", "8 presentes: volte ao Noel")
	santa._update_marker()
	check(santa.marker.text == "?", "marcador \"?\" com evento pronto (%s)" % santa.marker.text)
	var gold := Game.gold
	var pages: Array = santa._build_dialogue()
	var reward_page: Dictionary = {}
	for pg in pages:
		if pg.has("on_show"):
			reward_page = pg
	check(not reward_page.is_empty(), "Noel agradece e entrega a recompensa")
	if not reward_page.is_empty():
		(reward_page.on_show as Callable).call()
	var reward := int(ItemDB.QUESTS.natal_presentes.reward_gold)
	check(Game.quest_state("natal_presentes") == "done" and Game.gold == gold + reward,
		"Presentes Espalhados concluído (+%d ouro)" % (Game.gold - gold))

	# Ladrões de Natal: qualquer goblin conta, a cadeia do Bram não se mexe
	Game.start_quest("natal_ladroes")
	Game.on_enemy_killed("goblin_arqueiro", 0)
	Game.on_enemy_killed("goblin_bombardeiro", 0)
	Game.on_enemy_killed("slime", 0)
	check(int(Game.quests.natal_ladroes.progress) == 2, "goblins de tipos diferentes contam (%d)" % int(Game.quests.natal_ladroes.progress))
	Game.start_quest("goblins")
	check(Game.quest_state("goblins") == "none", "eventos não destravam a história")

	# A Ceia do Noel: entrega com os pratos na mochila
	Game.start_quest("natal_ceia")
	Game.complete_quest("natal_ceia")
	check(Game.quest_state("natal_ceia") == "active", "ceia sem os pratos não conclui")
	var need: Dictionary = ItemDB.QUESTS.natal_ceia.deliver
	var had := {}
	for item in need:
		had[item] = Game.count_item(item)
	Econ.grant(0, 0, need, "vilatest", true)
	santa._update_marker()
	check(santa.marker.text == "?", "Noel vê os pratos na mochila (%s)" % santa.marker.text)
	Game.complete_quest("natal_ceia")
	check(Game.quest_state("natal_ceia") == "done", "ceia entregue")
	for item in need:
		check(Game.count_item(item) == had[item], "%s: só o pedido sai da mochila (%d)" % [item, Game.count_item(item)])

	# Entregas na Vila: estrelas nas 6 portas
	var doors := _event_points(w, "door")
	check(doors.size() == 6 and doors.all(func(d) -> bool: return not d.visible), "6 portas de entrega escondidas")
	Game.start_quest("natal_entregas")
	await wait(0.1)
	check(doors.all(func(d) -> bool: return d.visible), "estrelas aparecem nas portas")
	for d in doors:
		d.interact(w.player)
	await wait(0.1)
	check(Game.quest_state("natal_entregas") == "ready", "6 presentes entregues: volte ao Noel")
	Game.complete_quest("natal_entregas")
	check(Game.quest_state("natal_entregas") == "done", "Entregas na Vila concluído")


## Tela de carregamento (ligada à força: em headless a troca de cena é direta): cobre a volta a Valdoria,
## o cavaleiro fica imune enquanto ela cobre e ainda um pouco depois que abre.
func _loading_screen() -> void:
	if _vila() == null:
		return
	Loading.force = true
	var before := get_tree().current_scene
	Loading.go(Game.WORLD_SCENE)
	check(Loading.covering, "tela de carregamento cobre a troca de cena")
	var arrived: bool = await _wait_until(func() -> bool:
		var s := get_tree().current_scene
		return s != null and s != before and s.get("role") == null and s.get("player") != null and s.get("built"), 20.0)
	check(arrived, "Valdoria montada por trás da tela")
	check(arrived and is_equal_approx(Loading.progress, 1.0),
		"mapa montado em etapas com a barra em 100%% (%.2f)" % Loading.progress)
	if arrived:
		var p: Player = get_tree().current_scene.player
		check(Loading.covering, "tela ainda cobre com Valdoria recém-montada")
		var hp := Game.hp
		p.take_damage(50.0, p.global_position + Vector3(1, 0, 0))
		check(Game.hp == hp, "golpe durante o carregamento não tira vida")
		check(await _wait_until(func() -> bool: return not Loading.covering, 12.0), "tela abre com o mundo pronto")
		check(p.invuln > 1.0, "imunidade curta depois que a tela abre (%.1f s)" % p.invuln)
		check(await _wait_until(func() -> bool: return not Loading._root.visible, 3.0), "tela some depois de abrir")
	Loading.force = false


func _finish() -> void:
	print("VILATEST %s (%d falhas)" % ["OK" if fails == 0 else "FALHOU", fails])
	get_tree().paused = false
	get_tree().quit(1 if fails > 0 else 0)
