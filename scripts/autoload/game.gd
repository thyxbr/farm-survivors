extends Node
## Estado global do jogo: o ESPELHO do personagem (atributos, inventário, missões, horta) mais o que é só
## do cliente (vida/mana do combate, bônus de comida e da Horda, configurações).
##
## Quem muda o personagem é o CharacterService, sempre pelo autoload Econ: offline o serviço local
## (user://solo_character.json) responde na hora; online o servidor responde com o estado completo. As funções
## abaixo que "mudam" algo (buy, equip, plant...) só fazem o pedido; o estado e os sinais chegam por
## apply_state/apply_events. As propriedades e os sinais continuam os mesmos para a UI e o combate.

signal stats_changed
signal inventory_changed
signal quests_changed
signal bestiary_changed
signal ranked_up(rank: String)   # promoção na guilda (cartão "PROMOÇÃO")
signal notify(text: String, color: Color)
signal leveled_up(new_level: int)
signal food_eaten(id: String)
signal farm_changed
signal item_looted(id: String, qty: int)
## Ouro de um abate que entrou direto no inventário (o HUD mostra "+N ouro").
signal gold_looted(amount: int)
## O encanto da arma equipada mudou (encantou no ferreiro ou trocou de arma).
signal enchant_changed
signal kit_changed   # a classe da arma equipada mudou (ou o escudo entrou/saiu: troca a habilidade 1 da espada)

const SETTINGS_PATH := "user://settings.cfg"
## Desafio da Horda ligado? Desligado por enquanto: sem portal na vila, o servidor recusa a fila e os testes
## da Horda (smoke --smoke-part=horda, _test_horde do net_test, portal no teste da vila) são pulados.
const HORDE_ENABLED := false
const WORLD_SCENE := "res://scenes/world.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const CHAR_CREATE_SCENE := "res://scenes/char_create.tscn"

var settings := {"mouse_sensitivity": 0.25, "master_volume": 0.8, "music_volume": 0.45, "sfx_volume": 0.9,
	"ambience_volume": 0.7, "fullscreen": false, "invert_y": false,
	"player_name": "", "server_address": "", "keep_logged": true, "toon": true, "toon_outline": true,
	"cam_zoom": 4.0}

# ---- espelho do personagem (escrito só por apply_state)
var level := 1
const FURY_MAX := CharState.FURY_MAX
var fury := 0.0   # fúria 0..100: enche lutando, zera ao usar a ultimate, não esvazia com o tempo
var xp := 0
var gold := 0
var stat_points := 0
var attributes := {"str": 5, "int": 5, "vit": 5, "agi": 5}
var inventory: Array = []   # [{"id": String, "qty": int}]
var equipment := empty_equipment()
var quests := {}            # id -> {"state": "active"|"ready"|"done", "progress": int}
var flags := {}
var kills := 0
## Bestiário (BestiaryRules): kind -> {"n", "a", "d"}.
var bestiary := {}
## Ecos (moeda permanente das partidas) e passivas permanentes {id: nível}.
var ecos := 0
var passives := {}
## {"unlocked": int, "plots": [{"crop", "growth" 0..1 em "t", "t" unix s, "watered", "fert"}]}
## O crescimento corre pelo relógio: leia plot_growth(i), não plots[i].growth.
var farm := {}

# ---- do cliente
var hp := 100.0
var mp := 50.0
var stamina := 100.0
var spawn_position = null   # Vector3 a aplicar ao carregar o mundo
var spawn_yaw := 0.0
## Bônus temporários do Desafio da Horda (zerados ao fim da partida).
var run_mods := {}

# ---- horta e comida
const FARM_PLOTS := 12
const FARM_START_PLOTS := 6
const EAT_COOLDOWN := 3.0
## Bônus de buffs ativos (somados aos run_mods em mod()). Valem na vila e na Horda.
var buff_mods := {}
var buffs := {}             # id em buffs.json (comida ou habilidade) -> segundos restantes
var eat_cooldown := 0.0
var selected_food := ""
## Bônus das passivas permanentes (CharRules.meta_mods), recalculados em apply_state e somados em mod().
var meta_mods := {}
## Talentos aprendidos {id: nível} (espelho do personagem; a aba Talentos lê daqui).
var talents := {}
## Profissões ({id: {"lv", "xp", "done"}}) e receitas aprendidas por pergaminho (espelho do CharState).
var professions := {}
var recipes: Array = []
## Bônus dos talentos da classe (CharRules.talent_mods), recalculados em apply_state e somados em mod().
var talent_mods := {}
## Encantamentos por tipo de arma (espelho de CharState.enchants): id -> {"el", "lv"}.
var enchants := {}
## Classe fixa e corpo do personagem (espelho de CharState; "" = save antigo).
var char_class := ""
var body := ""
var hair := ""           ## penteado (HairStyles; "" = padrão do corpo)
## Escolha automática de classe (testes e demos) mandada e ainda sem resposta (online ela é assíncrona).
var _auto_class_pending := false
## Só o net_test: não escolhe a classe sozinho (testa a recusa do servidor a personagem sem classe).
var skip_auto_class := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Interpolação de física só onde se pede (jogadores e inimigos): o resto do jogo mexe em
	# posições por quadro (tweens, efeitos) e tremeria se fosse interpolado.
	get_tree().root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_setup_input()
	load_settings()
	reset_run_mods()
	# personagem novo só no espelho: o de verdade chega do save solo (Econ.start_solo) ou do servidor
	apply_state(CharState.new_character(Balance.tables).to_dict(), true)
	_debug_screenshot()
	if "--dbg" in OS.get_cmdline_user_args():
		get_tree().root.add_child.call_deferred(load("res://tests/debug_dialogue.gd").new())
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--monster-glb="):
			# `--monster-glb=wolf:wolf_ia`: troca o GLB de um modelo de monstro (ex.: o lobo gerado por IA, mesmos pivôs)
			var mg := a.substr(14).split(":")
			EnemyModel.swap[mg[0]] = "res://assets/models/%s.glb" % mg[1]
		elif a.begins_with("--nettest="):
			get_tree().root.add_child.call_deferred(load("res://tests/net_test.gd").new())
		elif a.begins_with("--groupdemo="):
			# demonstração do Grito do Bastião em grupo, com servidor local (tools/party_group_demo.gd)
			get_tree().root.add_child.call_deferred(load("res://tools/party_group_demo.gd").new())
		elif a.begins_with("--atlasshot="):
			get_tree().root.add_child.call_deferred(load("res://tools/atlas_shot.gd").new())
		elif a.begins_with("--teleportshot="):
			get_tree().root.add_child.call_deferred(load("res://tools/teleport_shot.gd").new())
	if "--tauntdemo" in OS.get_cmdline_user_args():
		# demonstração do Círculo da Provocação Sombria (use com --weapon=iron_sword: personagem descartável)
		get_tree().root.add_child.call_deferred(load("res://tools/taunt_demo.gd").new())
	if "--hammerdemo" in OS.get_cmdline_user_args():
		# demonstração do Martelo de Energia (use com --weapon=iron_sword: personagem descartável)
		get_tree().root.add_child.call_deferred(load("res://tools/hammer_demo.gd").new())
	if "--rallydemo" in OS.get_cmdline_user_args():
		# demonstração do Grito do Bastião (use com --weapon=iron_sword: personagem descartável)
		get_tree().root.add_child.call_deferred(load("res://tools/party_shield_demo.gd").new())
	if "--earthquakedemo" in OS.get_cmdline_user_args():
		# demonstração do Terremoto Devastador (use com --weapon=iron_sword: personagem descartável)
		get_tree().root.add_child.call_deferred(load("res://tools/earthquake_demo.gd").new())
	if "--supremedemo" in OS.get_cmdline_user_args():
		# demonstração da Lâmina Suprema (use com --weapon=eclipse_greatsword: personagem descartável)
		get_tree().root.add_child.call_deferred(load("res://tools/supreme_game_demo.gd").new())
	if "--dragdemo" in OS.get_cmdline_user_args():
		# demonstração do Corte do Abismo (use com --weapon=iron_zweihander: personagem descartável)
		get_tree().root.add_child.call_deferred(load("res://tools/drag_slash_demo.gd").new())
	if "--spindemo" in OS.get_cmdline_user_args():
		# demonstração do Ciclone de Aço (use com --weapon=iron_zweihander: personagem descartável)
		get_tree().root.add_child.call_deferred(load("res://tools/spin_demo.gd").new())
	if "--darkcombodemo" in OS.get_cmdline_user_args():
		# demonstração da Dança do Abismo (use com --weapon=iron_zweihander: personagem descartável)
		get_tree().root.add_child.call_deferred(load("res://tools/dark_combo_demo.gd").new())
	if "--flamedemo" in OS.get_cmdline_user_args():
		# demonstração da Canalização de Fogo (use com --weapon=apprentice_staff: personagem descartável)
		get_tree().root.add_child.call_deferred(load("res://tools/flame_demo.gd").new())
	if "--smoketest" in OS.get_cmdline_user_args():
		# o Econ usa user://smoketest_solo.json, apagado no início
		get_tree().root.add_child.call_deferred(load("res://tests/smoke_test.gd").new())
	if "--vilatest" in OS.get_cmdline_user_args():
		# o Econ usa user://vilatest_solo.json, apagado no início
		get_tree().root.add_child.call_deferred(load("res://tests/vila_test.gd").new())


## Depuração: `godot -- --shot=shot.png [--delay=4]` salva um screenshot e fecha.
## `--survival` (com ou sem --shot) começa direto no Desafio da Horda.
## `--autoswing` (no jogador local) emenda golpes básicos sem parar, com fôlego cheio; com `--shots=` fotografa o combo.
## `--cam=graus,dist` gira a câmera em volta do jogador e muda a distância (ex.: `--cam=180,2.2`
## olha o personagem de frente, de perto) — útil para conferir luz e modelo.
## `--farmdemo`/`--geardemo`/`--weapon=` usam um personagem novo num arquivo à parte (user://demo_solo.json,
## apagado a cada vez): não mexem no save solo.
func _debug_screenshot() -> void:
	var path := ""
	var delay := 4.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			path = a.substr(7)
		elif a.begins_with("--delay="):
			delay = float(a.substr(8))
		elif a.begins_with("--at="):  # --at=x,z,yaw
			var v := a.substr(5).split(",")
			spawn_position = Vector3(float(v[0]), 0.5, float(v[1]))
			spawn_yaw = float(v[2]) if v.size() > 2 else 0.0
	var args := OS.get_cmdline_user_args()
	var demo := "--farmdemo" in args or "--geardemo" in args or "--enchantdemo" in args or "--introdemo" in args
	for a in args:
		demo = demo or a.begins_with("--weapon=")
	if demo:
		var at = spawn_position
		Econ.start_scratch_solo("user://demo_solo.json")
		if at != null:
			spawn_position = at
	# `--enchantdemo` dá ouro e materiais e deixa a arma em Fogo +2 (para capturas do painel do ferreiro);
	# com `--ui=enchant` abre o painel; com `--enchantstrike` o Doran dá o golpe de encanto na hora da captura
	if "--enchantdemo" in args:
		Econ.grant(600, 0, {"iron_ore": 30, "arcane_crystal": 3, "ember_core": 14, "frost_drop": 5}, "demo", true)
		# com `--weapon=`, a arma pedida entra antes: o encanto é por arma e vale para a que está na mão
		for a in args:
			if a.begins_with("--weapon=") and count_item(a.substr(9)) == 0 and equipment.weapon != a.substr(9):
				Econ.grant(0, 0, {a.substr(9): 1}, "demo", true)
				equip(a.substr(9))
		Econ.request("enchant", ["fogo"])
		Econ.request("enchant", ["fogo"])
		# `--enchantrich`: material de sobra para subir até +5 e trocar de elemento à vontade no Doran
		if "--enchantrich" in args:
			Econ.grant(6000, 0, {"iron_ore": 90, "arcane_crystal": 40, "champion_badge": 3, "ember_core": 40,
				"frost_drop": 40, "thunder_totem": 40, "toxic_gland": 40, "golden_dust": 40, "shadow_fang": 40}, "demo", true)
			Econ.demo_ecos(120)
			# `--enchant-as=raio,4` (com --enchantrich): troca o encanto da arma para esse elemento e nível
			for a in args:
				if a.begins_with("--enchant-as="):
					var want := a.substr(13).split(",")
					for i in 8:
						var cur := weapon_enchant()
						if cur.el == want[0] and cur.lv >= int(want[1]):
							break
						Econ.request("enchant", [want[0]])
	# `--levelupfx`: toca a subida de nível um pouco antes da captura (conferir o efeito)
	if "--levelupfx" in args:
		get_tree().create_timer(maxf(delay - 0.05, 0.1)).timeout.connect(func() -> void:
			for p in get_tree().get_nodes_in_group("player"):
				if p.has_method("_on_level_up") and not p.get("remote"):
					p._on_level_up(level))
	if "--enchantstrike" in args:
		get_tree().create_timer(maxf(delay - 0.15, 0.1)).timeout.connect(func() -> void:
			for n in get_tree().get_nodes_in_group("interactable"):
				if n.get("npc_id") == "blacksmith":
					n.enchant_strike(Color(1.0, 0.42, 0.08)))
	# `--gatherdemo=<s>`: perto de um veio/árvore (use --at=), aperta F <s> segundos antes da captura;
	# `--gathertool=<id>` põe essa ferramenta na mochila antes (a melhor do tipo é a que vai para a mão)
	for a in args:
		if a.begins_with("--gathertool=") and ItemDB.ITEMS.has(a.substr(13)):
			Econ.grant(0, 0, {a.substr(13): 1}, "demo", true)
	for a in args:
		if a.begins_with("--gatherdemo="):
			get_tree().create_timer(maxf(delay - float(a.substr(13)), 0.1)).timeout.connect(func() -> void:
				var pl = get_tree().get_first_node_in_group("player")
				var n = GatherAction.nearest(pl) if pl else null
				if n:
					pl.start_gather(n))
	# `--farmdemo` enche a horta com culturas em vários estágios (para screenshots)
	if "--farmdemo" in args:
		var now := Econ.now()
		farm.unlocked = FARM_PLOTS - 2
		for i in farm.unlocked:
			farm.plots[i] = {"crop": ItemDB.CROP_ORDER[i % 6], "growth": [1.0, 0.7, 0.35][i / 4 % 3] if i < 8 else 1.0,
				"t": now, "watered": i % 2 == 0, "fert": false}
		var dishes := {}
		for r in ItemDB.RECIPE_ORDER:
			dishes[r] = 2
		Econ.grant(0, 0, dishes, "demo", true)
		buffs = {"food_warm": 30.0, "food_eagle": 4.0}
		_recalc_buff_mods()
		for a in args:   # --farmdemo --ui=cook|plant abre o menu
			if a.begins_with("--ui="):
				await get_tree().create_timer(1.0).timeout
				var w = get_tree().current_scene
				if a == "--ui=cook":
					w.open_cooking()
				else:
					w.open_plant_menu(10)
	# `--geardemo` dá um punhado dos equipamentos novos (para screenshots do inventário e da loja)
	# `--weapon=<id>` equipa uma arma; `--ui=inv|char|talents|quests|shop` abre a tela (sem --farmdemo)
	if "--geardemo" in args:
		var gear_ids := {}
		for id in ["frost_brand", "ember_staff", "elven_bow", "storm_bow", "dragonfang", "knight_shield", "arcane_orb",
				"hunter_quiver", "iron_helm", "mage_robe", "royal_plate", "iron_gauntlets", "swift_boots", "vampire_ring",
				"sage_amulet", "sc_novice_scepter", "sc_dawn_scepter", "sc_blessed_scepter", "sc_seraph_scepter", "sc_halo_scepter", "goblin_cleaver", "guardian_greatsword", "iron_zweihander", "highland_claymore", "ember_flamberge", "eclipse_greatsword", "royal_wings", "titan_cleaver", "rose_flame", "knight_helm", "chain_mail", "archer_bracers",
				"iron_greaves", "life_amulet", "strength_ring", "traveler_cape"]:
			gear_ids[id] = 1
		gear_ids["slime_gel"] = 7
		gear_ids["goblin_ear"] = 3
		gear_ids["spicy_soup"] = 2
		# um de cada família de ícone sem modelo de equipamento (poção, semente, colheita, prato, material)
		for id in ["health_potion", "mana_potion", "wind_ring", "seed_carrot", "seed_mint", "carrot", "wheat", "tomato",
				"pepper", "mint", "pumpkin", "bread", "mint_tea", "pumpkin_pie", "valdoria_feast", "bone_shard",
				"goblin_crown", "iron_ore", "arcane_crystal", "ember_core", "frost_drop", "thunder_totem", "toxic_gland",
				"golden_dust", "shadow_fang", "champion_badge"]:
			gear_ids[id] = 1 + gear_ids.size() % 4 if ItemDB.is_stackable(id) else 1
		# nível 6 com 3 pontos sobrando: XP dos níveis 1→6 menos 3 níveis de pontos já gastos não existe;
		# a demo só mostra a tela, então ajusta o espelho direto depois da concessão
		Econ.grant(1425, 0, gear_ids, "demo", true)
		for id in ["knight_helm", "chain_mail", "archer_bracers", "iron_greaves", "life_amulet", "strength_ring"]:
			equip(id)
		level = 6
		stat_points = 3
		quests = {"slimes": {"state": "done", "progress": 5}, "goblins": {"state": "active", "progress": 2}}
		hp = max_hp() * 0.62
	for a in args:
		if a.begins_with("--weapon=") and equipment.weapon != a.substr(9):
			Econ.grant(0, 0, {a.substr(9): 1}, "demo", true)
			equip(a.substr(9))
		# `--equip=id,id,...` veste peças (capturas de armaduras; com `--body=f`, do corpo feminino);
		# `-espaço` tira a peça do espaço (ex.: `--equip=-head,-armor,-hands,-feet` = sem armadura)
		elif a.begins_with("--equip="):
			for id in a.substr(8).split(",", false):
				if id.begins_with("-"):
					unequip(id.substr(1))
				else:
					Econ.grant(0, 0, {id: 1}, "demo", true)
					equip(id)
		# `--talents=id,id,...` aprende um nível de cada (repetir o id = mais níveis), para capturas da aba Talentos
		# (sobe o personagem da demo ao nível 6 de verdade, para ter os 5 pontos)
		# `--level=N` sobe o personagem da demo ao nível N de verdade (com `--weapon=`: testar as habilidades
		# de nível alto, ex.: `--weapon=sc_novice_scepter --level=8`)
		elif a.begins_with("--level=") and demo:
			var xp_lv := 0
			for lv in range(1, clampi(int(a.substr(8)), 1, 60)):
				xp_lv += CharRules.xp_to_next(lv, Balance.tables)
			Econ.grant(0, xp_lv, {}, "demo", true)
		# `--bestiary=tipo:abates[:item],...` preenche o espelho do bestiário (só a tela, para capturas da aba B;
		# `item` = espólio secreto que já caiu)
		elif a.begins_with("--bestiary=") and demo:
			for part in a.substr(11).split(",", false):
				var bits := part.split(":")
				bestiary[bits[0]] = {"n": int(bits[1]) if bits.size() > 1 else 1, "a": ["campos_norte", "toca_goblins"],
					"d": [bits[2]] if bits.size() > 2 else []}
			bestiary_changed.emit()
		elif a.begins_with("--talents="):
			var xp_need := 0
			for lv in range(1, 6):
				xp_need += CharRules.xp_to_next(lv, Balance.tables)
			Econ.grant(0, xp_need, {}, "demo", true)
			for id in a.substr(10).split(",", false):
				learn_talent(id)
	if "--farmdemo" not in args:
		for a in args:
			if a.begins_with("--ui="):
				await get_tree().create_timer(1.0).timeout
				var w = get_tree().current_scene
				# várias janelas de uma vez: --ui=char,inv
				for ui_name in a.substr(5).split(",", false):
					await _open_debug_ui(w, ui_name, args)
				# `--tip=<n>` (com o inventário aberto): abre a dica do espaço n da mochila, presa ao lado dele,
				# para a captura; `--shift` abre também a ficha do equipado ao lado (como segurar Shift)
				var inv: Control = w.dock.at("right") if w.get("dock") else null
				for t in args:
					if t.begins_with("--tip=") and inv != null and inv.get("bag_slots") != null:
						await get_tree().create_timer(0.5).timeout
						var slot: ItemSlot = inv.bag_slots[clampi(int(t.substr(6)), 0, inv.bag_slots.size() - 1)]
						if slot.item_id != "":
							var tip: ItemTooltip = inv.tooltip
							tip.show_for(slot)
							tip.set_process(false)   # não segue o ponteiro (que pode nem estar na janela)
							var r := slot.get_global_rect()
							tip.global_position = Vector2(r.position.x - tip.get_combined_minimum_size().x - 8, r.position.y)
							if "--shift" in args:
								tip._update_compare(true)

	# `--survival` começa direto no Desafio da Horda (com ou sem screenshot)
	if "--survival" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.3).timeout
		var w = get_tree().current_scene
		if w and w.has_method("start_survival"):
			w.start_survival()
	if path == "":
		return
	if "--talk" in OS.get_cmdline_user_args():
		await get_tree().create_timer(delay * 0.5).timeout
		for n in get_tree().get_nodes_in_group("interactable"):
			if n.npc_id == "elder":
				n.interact(null)
	var cam := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cam="):
			cam = a.substr(6)
	if cam != "":
		await get_tree().create_timer(maxf(delay - 1.0, 0.1), true).timeout
		var pl = get_tree().get_first_node_in_group("player")
		if pl and pl.get("cam_yaw"):
			var c := cam.split(",")
			pl.cam_yaw.rotation.y += deg_to_rad(float(c[0]))
			if c.size() > 1:
				pl.cam_dist_override = float(c[1])
				pl._cam_dist = float(c[1])
		delay = 1.0
	await get_tree().create_timer(delay, true).timeout
	# `--shots=N[,intervalo]`: N capturas seguidas (shot_00.png, shot_01.png...), para ver um golpe quadro a quadro
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			var sp := a.substr(8).split(",")
			var gap := float(sp[1]) if sp.size() > 1 else 0.06
			for i in int(sp[0]):
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(path.get_basename() + "_%02d.png" % i)
				await get_tree().create_timer(gap, true).timeout
			get_tree().quit()
			return
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(path)
	if err != OK:
		printerr("Screenshot não salvo em '%s' (pasta sem permissão de escrita?). Use um caminho dentro do projeto, ex.: --shot=shot.png" % path)
	get_tree().quit()


# ---------------------------------------------------------------- input
func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "dodge": [KEY_CTRL, KEY_ALT],
		"interact": [KEY_E], "spell_1": [KEY_1], "spell_2": [KEY_2], "spell_3": [KEY_3], "spell_4": [KEY_4], "spell_5": [KEY_5],
		"potion": [KEY_R], "mana_potion": [KEY_F], "gather": [KEY_F], "inventory": [KEY_I, KEY_TAB], "character": [KEY_C],
		"talents": [KEY_K], "quest_log": [KEY_J], "professions": [KEY_L], "bestiary": [KEY_B], "pause": [KEY_ESCAPE], "quicksave": [KEY_F5], "quickload": [KEY_F9],
		"eat": [KEY_Q], "food_next": [KEY_T], "world_map": [KEY_M], "party": [KEY_P], "friends": [KEY_O],
		# emotes (acenar, comemorar, sentar): eram as teclas 1–3 da praça; na vila 1–4 são magias
		"emote_1": [KEY_7], "emote_2": [KEY_8], "emote_3": [KEY_9],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	# "aim" divide o botão direito com a esquiva: com arco ele mira (o jogador ignora a esquiva desse clique)
	var mouse := {"attack": MOUSE_BUTTON_LEFT, "dodge": MOUSE_BUTTON_RIGHT, "aim": MOUSE_BUTTON_RIGHT}
	for action in mouse:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var mb := InputEventMouseButton.new()
		mb.button_index = mouse[action]
		InputMap.action_add_event(action, mb)



# ---------------------------------------------------------------- jogo solo
## "Novo jogo": apaga o personagem solo (o menu pergunta antes) e começa na vila com um novo.
func start_new_game() -> void:
	reset_run_mods()
	Econ.reset_solo()
	spawn_position = null
	get_tree().paused = false
	go_to_world()


## "Continuar": o personagem do save solo, de volta a Valdoria onde ele estava.
func continue_game() -> bool:
	if not Econ.has_solo() or not Econ.start_solo():
		notify.emit("Nenhum jogo salvo.", Color(1, 0.5, 0.5))
		return false
	reset_run_mods()
	get_tree().paused = false
	go_to_world()
	return true


## Entrada no jogo (novo jogo, continuar, login aceito): personagem sem classe passa antes pela tela de
## criação. Uma escolha automática dos testes ainda no ar (online) é esperada antes de decidir.
func go_to_world() -> void:
	while char_class == "" and _auto_class_pending:
		await Econ.done
	Loading.go(entry_scene())


func entry_scene() -> String:
	return CHAR_CREATE_SCENE if char_class == "" else WORLD_SCENE


## Personagem de antes das classes (tem progresso): a tela de criação diz "Escolha sua classe".
## O kit inicial (poções, sementes, pão, capuz) não conta; nível, XP, peça equipada ou arma na mochila
## contam (personagem novo nunca tem arma antes da escolha).
func is_old_character() -> bool:
	if level > 1 or xp > 0:
		return true
	for k in equipment:
		if str(equipment[k]) != "" and not (k in ItemDB.TOOL_SLOTS):   # picareta e machado vêm com o personagem
			return true
	for slot in inventory:
		if ItemDB.slot_of(str(slot.id)) == "weapon":
			return true
	return false


## A arma pode ser equipada pela classe do personagem (itens que não são arma: sempre).
func can_wield(id: String) -> bool:
	if CharRules.slot_of(Balance.tables, id) != "weapon":
		return true
	return CharRules.weapon_class(Balance.tables, id) == CharRules.class_weapon(Balance.tables, char_class)


## Nome da classe de personagem que usa a arma ("Arqueiro" para um arco).
func weapon_owner(id: String) -> String:
	return CharRules.class_of_weapon_name(Balance.tables, CharRules.weapon_class(Balance.tables, id))


func go_to_menu() -> void:
	if Network.is_online():
		Network.autosave()
		Network.leave()
	else:
		var w := get_tree().current_scene
		var p = w.get("player") if w != null and w.get("role") == null else null
		if p is Player and is_instance_valid(p) and not p.dead and not run_mods.get("active", false):
			Econ.report_vitals(p.global_position, p.model.rotation.y)
	reset_run_mods()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Loading.go(MENU_SCENE)


## Online: volta à seleção de personagem sem passar pelo menu nem pelo login (salva, reconecta com o
## mesmo token e a fogueira abre com a lista que o servidor mandar). Fora do online vai ao menu.
func go_to_char_select() -> void:
	if not Network.is_client():
		go_to_menu()
		return
	Network.autosave()
	reset_run_mods()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not Network.rejoin():
		Network.last_error = "Não deu para voltar à seleção de personagem. Entre de novo."
		Loading.go(MENU_SCENE)
		return
	# a seleção abre vazia sob a tela de carregamento; a lista chega em seguida (char_list_changed).
	# Se a conexão falhar, a própria seleção volta ao menu com o aviso (char_select._on_lost).
	Loading.go(Network.CHAR_SELECT_SCENE)


# ---------------------------------------------------------------- bônus da horda
func reset_run_mods() -> void:
	run_mods = {
		"active": false, "damage": 1.0, "max_hp": 1.0, "max_hp_flat": 0.0, "speed": 1.0,
		"defense": 0.0, "regen": 0.0, "crit": 0.0, "cooldown": 1.0, "area": 1.0, "magnet": 1.0,
		"xp": 1.0, "gold": 1.0, "lifesteal": 0.0,
	}


func damage_mult() -> float:
	return mod("damage")


## Valor efetivo de um bônus: Desafio da Horda + comida + passivas permanentes.
func mod(k: String) -> float:
	return float(run_mods.get(k, 0.0)) + float(buff_mods.get(k, 0.0)) + float(meta_mods.get(k, 0.0)) + float(talent_mods.get(k, 0.0)) 		+ (enchant_damage(equipment.weapon) if k == "damage" else 0.0)


# ---------------------------------------------------------------- encantamento
## Encanto de uma arma do personagem: {"el", "lv"}; sem encanto = {"el": "", "lv": 0}.
## O encanto é do tipo de arma: "iron_sword@fina~urso" usa o de "iron_sword" (igual a EnchantRules.of,
## que o servidor usa; sem isso a arma craftada ficava sem brilho e sem bônus só para o próprio jogador).
func enchant_of(weapon_id: String) -> Dictionary:
	var e = enchants.get(ItemQuality.base(weapon_id))
	if e is Dictionary and int(e.get("lv", 0)) > 0:
		return {"el": str(e.get("el", "")), "lv": int(e.lv)}
	return {"el": "", "lv": 0}


## Encanto da arma equipada.
func weapon_enchant() -> Dictionary:
	return enchant_of(equipment.weapon)


## Bônus de dano (fração) do encanto de uma arma. Calculado na hora (e não guardado) para a
## prévia de "se equipar" do inventário já contar o encanto da outra arma.
func enchant_damage(weapon_id: String) -> float:
	var lv: int = enchant_of(weapon_id).lv
	var dmg: Array = Balance.tables.get_table("enchant").get("damage", [])
	if lv <= 0 or dmg.is_empty():
		return 0.0
	return float(dmg[mini(lv, dmg.size()) - 1])


## Efeito do elemento da arma equipada (EnchantRules.effect); {} sem encanto.
func weapon_effect() -> Dictionary:
	var e := weapon_enchant()
	return EnchantRules.effect(Balance.tables, e.el, e.lv)


## "Fogo +2 · +10% de dano" ("" se a arma não tem encanto).
func enchant_text(weapon_id: String) -> String:
	var e := enchant_of(weapon_id)
	if e.lv <= 0:
		return ""
	var name: String = Balance.tables.get_table("enchant").get("elements", {}).get(e.el, {}).get("name", e.el)
	return "%s +%d · +%d%% de dano" % [name, e.lv, int(round(enchant_damage(weapon_id) * 100.0))]


# ---------------------------------------------------------------- atributos derivados
static func empty_equipment() -> Dictionary:
	var e := {}
	for s in ItemDB.SLOTS:
		e[s] = ""
	return e


func weapon_damage() -> int:
	return ItemDB.get_item(equipment.weapon).get("damage", 2) if equipment.weapon != "" else 2


func weapon_class() -> String:
	return ItemDB.weapon_class(equipment.weapon)


## Nome da classe do personagem (tabela `classes`: "Guerreiro", "Healer"...); sem classe ainda, "Sem classe".
## Nome do herói como os outros veem: online é o do personagem (o servidor manda no _accepted);
## offline, o nome digitado no menu. "" se não houver nenhum.
func hero_name() -> String:
	if Network.is_online() and Network.my_name != "":
		return Network.my_name
	return str(settings.get("player_name", ""))


## Título escolhido pelo personagem, já com o nome ("" = sem título).
func hero_title() -> String:
	return TitleRules.label(TitleRules.current(level, flags))


func class_display_name() -> String:
	var row = Balance.tables.get_table("classes").get(char_class, {})
	return str(row.get("name", char_class)) if row is Dictionary and char_class != "" else "Sem classe"


## Soma da defesa de todas as peças equipadas.
func armor_defense() -> int:
	var d := 0
	for s in equipment:
		if equipment[s] != "":
			d += int(ItemDB.get_item(equipment[s]).get("defense", 0))
	return d


## Soma de um bônus ("str", "crit", "hp"...) de todos os itens equipados.
func gear(k: String) -> float:
	var v := 0.0
	for s in equipment:
		if equipment[s] != "":
			v += float(ItemDB.item_stats(equipment[s]).get(k, 0.0))
	return v


## Atributo efetivo: pontos distribuídos + bônus dos itens.
func attr(a: String) -> int:
	return int(attributes[a]) + int(gear(a))


func max_hp() -> float:
	return (60.0 + attr("vit") * 10.0 + (level - 1) * 8.0 + gear("hp")) * mod("max_hp") + mod("max_hp_flat")


func max_mp() -> float:
	return (25.0 + attr("int") * 6.0 + (level - 1) * 3.0 + gear("mp")) * (1.0 + float(talent_mods.get("mp_pct", 0.0)))


func max_stamina() -> float:
	return 70.0 + attr("agi") * 2.5


## Dano do ataque básico conforme a classe da arma (espada FOR, cajado INT, arco AGI): CharRules.basic_damage.
func melee_damage() -> float:
	var attrs := {}
	for a in attributes:
		attrs[a] = attr(a)
	return CharRules.basic_damage(weapon_class(), attrs, weapon_damage(), gear("spell")) * mod("damage")


func spell_power() -> float:
	return attr("int") * 1.0 + gear("spell")


## Vida da Cura (CharRules.heal_for: 30 + 4 x poder mágico, mais o bônus de cura do cetro).
func heal_amount() -> float:
	return CharRules.heal_for(spell_power(), Balance.tables, str(equipment.weapon)) * (1.0 + float(talent_mods.get("heal_power", 0.0)))


## Escala dos atributos: o que vem da AGI tem retorno decrescente (soft_bonus) e o total de pontos +
## equipamento tem teto. Bônus temporários e de talento (mod) somam por cima do teto.
const AGI_SPEED_CAP := 0.40    # bônus máximo de velocidade vindo da AGI
const AGI_SPEED_HALF := 50.0   # pontos de AGI acima de 5 que dão metade desse bônus
const SPEED_MAX := 1.45        # teto de velocidade de pontos + equipamento
const AGI_CRIT_CAP := 0.25     # crítico máximo vindo da AGI
const AGI_CRIT_HALF := 60.0
const CRIT_MAX := 0.60         # teto de crítico de pontos + equipamento
const DAMAGE_REDUCTION_MAX := 0.80   # a defesa nunca corta mais que isso do dano recebido
const DEFENSE_K_BASE := 10.0   # K da redução de dano = isto + nível (ver damage_taken_mult)


## Bônus com retorno decrescente: 0 em x = 0, metade de `cap` em x = `half`, tende a `cap`.
static func soft_bonus(x: float, cap: float, half: float) -> float:
	x = maxf(x, 0.0)
	return cap * x / (x + half)


func crit_chance() -> float:
	var base := minf(CRIT_MAX, 0.08 + soft_bonus(attr("agi") - 5, AGI_CRIT_CAP, AGI_CRIT_HALF) + gear("crit"))
	return clampf(base + mod("crit"), 0.0, 1.0)


func cooldown_mult() -> float:
	# buff e talento "cooldown" são frações negativas (o mod("cooldown") das cartas da Horda é outra conta)
	return clampf(1.0 - gear("cdr") + float(buff_mods.get("cooldown", 0.0)) + float(talent_mods.get("cooldown", 0.0)), 0.4, 1.0)


## Recarga final de uma habilidade. Se ela dá um buff próprio, a recarga nunca fica abaixo da duração do
## buff + 4 s: redução de recarga (equipamento, talento, o próprio buff) não deixa mantê-lo o tempo todo.
func ability_cooldown(ability_id: String, base: float, mult: float) -> float:
	var cd := base * mult
	var buff_id := "scepter_feast" if ability_id == "scepter_ult" else ability_id
	if ability_id == "sword_fury_great":   # a Fúria Picante na tecla 5 da montante: o mesmo buff
		buff_id = "sword_fury"
	if ItemDB.BUFFS.has(buff_id) or ability_id == "scepter_ult":
		cd = maxf(cd, buff_duration(buff_id) + 4.0)
	return cd


## Segundos a mais que o talento dá à habilidade `ability_id` (chave "ability_time:<id>").
func ability_time_bonus(ability_id: String) -> float:
	return float(talent_mods.get("ability_time:" + ability_id, 0.0))


## Multiplicador de dano do talento da habilidade `ability_id` (chave "ability_dmg:<id>"): 1 + bônus.
func ability_dmg_mult(ability_id: String) -> float:
	return 1.0 + float(talent_mods.get("ability_dmg:" + ability_id, 0.0))


## Duração do buff `buff_id` para quem o conjurou: o tempo de buffs.json + o bônus de talento da habilidade
## (o buff do Banquete, scepter_feast, vem da habilidade scepter_ult; os demais têm o mesmo id).
func buff_duration(buff_id: String) -> float:
	var ability_id := "scepter_ult" if buff_id == "scepter_feast" else buff_id
	return float(ItemDB.BUFFS.get(buff_id, {}).get("time", 0.0)) + ability_time_bonus(ability_id)


## Defesa total: a fixa (armadura, VIT e bônus "defense") vezes 1 + os bônus percentuais "defense_pct" (o Bastião de
## Escudos dá os dois). Os buffs entram por mod(): buff_mods é refeito do zero a cada buff que entra ou sai
## (_recalc_buff_mods), então o bônus nunca fica preso depois que o buff acaba, morre ou é limpo.
func defense() -> float:
	return PartyShieldRules.defense_with(armor_defense() + attr("vit") * 0.25 + mod("defense"), mod("defense_pct"))


## Fração do dano que passa pela defesa: redução = defesa / (defesa + K), K = DEFENSE_K_BASE + nível do
## personagem, com teto de redução. O K cresce com o nível para a defesa não saturar no fim do jogo (com
## 50 / (50 + 4 x defesa) fixo, o equipamento lendário sozinho já cortava 79% do golpe do chefe final).
## Usa o nível do jogador e não o do atacante: o dano chega sem o atacante, e as áreas têm o nível de quem caça nelas.
func damage_taken_mult() -> float:
	var d := maxf(defense(), 0.0)
	var k := DEFENSE_K_BASE + float(maxi(level, 1))
	return maxf(1.0 - DAMAGE_REDUCTION_MAX, k / (k + d))


## Vida e mana recuperadas por segundo fora dos bônus de talento/horda.
func hp_regen() -> float:
	return 0.3 + attr("vit") * 0.02 + mod("regen")


func mp_regen() -> float:
	return (0.8 + attr("int") * 0.06) * (1.0 + float(talent_mods.get("mp_regen", 0.0)))


func speed_multiplier() -> float:
	var base := minf(SPEED_MAX, 1.0 + soft_bonus(attr("agi") - 5, AGI_SPEED_CAP, AGI_SPEED_HALF) + gear("speed"))
	return base * mod("speed")


## Números principais do personagem (para a tela de personagem e comparações).
func stat_snapshot() -> Dictionary:
	return {"dmg": melee_damage(), "def": defense(), "hp": max_hp(), "mp": max_mp(), "spell": spell_power(),
		"crit": crit_chance(), "speed": speed_multiplier(), "cdr": 1.0 - cooldown_mult(), "leech": gear("leech")}


## Quanto cada número muda se equipar `id` (simula a troca sem emitir sinais).
func preview_equip(id: String) -> Dictionary:
	var slot_name := ItemDB.slot_of(id)
	if slot_name == "":
		return {}
	var before := stat_snapshot()
	var saved := equipment.duplicate()
	equipment[slot_name] = id
	if slot_name == "weapon" and equipment.offhand != "":
		var off := ItemDB.get_item(equipment.offhand)
		if off.has("needs") and off.needs != weapon_class():
			equipment.offhand = ""
	var after := stat_snapshot()
	equipment = saved
	var out := {}
	for k in before:
		out[k] = after[k] - before[k]
	return out


## Roubo de vida dos itens: cura uma fração do dano causado.
func on_damage_dealt(amount: float, target_max_hp := 100.0, with_fury := true) -> void:
	if with_fury:
		add_fury_from_damage(amount, target_max_hp)
	var l := gear("leech")
	if l > 0.0 and hp > 0.0:
		hp = min(max_hp(), hp + amount * l)




func xp_to_next() -> int:
	return CharRules.xp_to_next(level, Balance.tables)


func knows_spell(id: String) -> bool:
	return level >= ItemDB.SPELLS[id].level


## Fúria ganha por um golpe: proporcional ao dano em relação à vida do alvo.
static func fury_gain(amount: float, target_max_hp: float) -> float:
	return clampf(amount / maxf(1.0, target_max_hp) * 50.0, 0.5, 6.0)


## Só enche a fúria, sem roubo de vida: usado pelas magias (o roubo de vida é do corpo a corpo).
func add_fury_from_damage(amount: float, target_max_hp := 100.0) -> void:
	add_fury(fury_gain(amount, target_max_hp))


func add_fury(amount: float) -> void:
	fury = clampf(fury + amount, 0.0, FURY_MAX)
	stats_changed.emit()


func fury_full() -> bool:
	return fury >= FURY_MAX


## Habilidades ainda "Em breve" (fases seguintes) não são anunciadas.
func ability_implemented(id: String) -> bool:
	return bool(ItemDB.ABILITIES[id].ready)


func knows_ability(id: String) -> bool:
	return level >= ItemDB.ABILITIES[id].level


## Habilidades da arma equipada (slots 1..5, em ordem).
func ability_kit() -> Array[String]:
	return ItemDB.kit(CharRules.class_weapon(Balance.tables, char_class), offhand_kind())


## Tipo da mão secundária que muda o kit: "shield" com uma espada E um escudo nas mãos; "two_handed" com a montante
## (as duas mãos na espada: a Lâmina Suprema no lugar do Turbilhão); senão "".
func offhand_kind() -> String:
	if equipment.get("weapon", "") == "" or weapon_class() != "sword":
		return ""
	if ItemDB.is_two_handed(equipment.get("weapon", "")):
		return "two_handed"
	var off: String = equipment.get("offhand", "")
	if off != "" and ItemDB.get_item(off).get("needs", "") == "sword":
		return "shield"
	return ""


# ---------------------------------------------------------------- modo admin
## Recursos infinitos ligados (AdminRules; o estado vem do servidor/solo em flags["admin"]).
func admin_mode() -> bool:
	return flags.get("admin") is Dictionary


## Pode ligar o modo admin: no solo sempre; online se liberado para todos ou conta de administrador
## (o servidor confere de novo).
func can_admin() -> bool:
	return not Network.is_online() or AdminRules.OPEN_TO_ALL or Auth.is_admin


func toggle_admin() -> void:
	Econ.set_admin(not admin_mode())


# ---------------------------------------------------------------- pedidos ao Econ
## Ganhos: só offline (online quem concede é o servidor; ver Econ.grant).
func add_xp(amount: int) -> void:
	Econ.grant(0, amount, {}, "xp")


func add_gold(amount: int) -> void:
	Econ.grant(amount, 0, {}, "gold")


func add_item(id: String, qty := 1, silent := false) -> void:
	Econ.grant(0, 0, {id: qty}, "item", silent)


func spend_point(attr_id: String) -> void:
	Econ.request("spend_point", [attr_id])


## Escolhe o título mostrado acima do nome ("" tira). O servidor/solo confere se está liberado.
func set_title(id: String) -> void:
	Econ.request("set_title", [id])


func sort_inventory() -> void:
	Econ.request("sort_inventory")


## Descartar 1 unidade (botão da mochila).
func discard(id: String) -> void:
	Econ.request("discard", [id])


func equip(id: String) -> void:
	Econ.request("equip", [id])


func unequip(slot_name: String) -> void:
	if equipment.get(slot_name, "") != "":
		Econ.request("unequip", [slot_name])


func buy(id: String, qty := 1) -> void:
	Econ.request("buy", [id, qty] if qty != 1 else [id])


func sell(id: String) -> void:
	Econ.request("sell", [id])


func start_quest(id: String) -> void:
	Econ.request("start_quest", [id])


func complete_quest(id: String) -> void:
	Econ.request("complete_quest", [id])


## Missão de coletar/visitar: o ponto `index` dela foi feito (presente achado, casa visitada).
func quest_mark(id: String, index: int) -> void:
	Econ.request("quest_mark", [id, index])


## Pontos já feitos de uma missão de coletar/visitar.
func quest_got(id: String) -> Array:
	return quests[id].get("got", []) if quests.has(id) else []
## Promoção na guilda (as regras conferem pontos e missões).
func rank_up() -> void:
	Econ.request("rank_up")


## Aprende um nível do talento (as regras conferem pontos, linha e máximo).
func learn_talent(id: String) -> void:
	Econ.request("learn_talent", [id])


## Devolve todos os pontos de talento (na Lina, da Guilda; cobra talent_reset_cost()).
func reset_talents() -> void:
	Econ.request("reset_talents")


## Aviso único da migração da progressão (flags.prog_notice): devolve true uma vez e pede ao
## servidor/solo que limpe a marca. O espelho limpa já, para não repetir antes da resposta.
func take_prog_notice() -> bool:
	if not flags.get("prog_notice", false):
		return false
	flags.erase("prog_notice")
	Econ.request("ack_prog_notice")
	return true


## Pontos de talento livres no espelho: 1 por nível a partir do 2, menos os gastos (CharRules.talent_points).
func talent_points() -> int:
	var spent := 0
	for id in talents:
		spent += int(talents[id])
	return maxi(0, level - 1 - spent)


## Ouro para redistribuir os talentos agora (espelho de CharRules.reset_cost).
## Ouro para viajar até o mapa `region`: "coach" (cocheiro, em conta) ou "map" (mapa-mundi, caro). -1 = inválido.
func travel_cost(region: String, mode: String) -> int:
	return CharRules.travel_cost(Balance.tables, region, mode)


func talent_reset_cost() -> int:
	return 0 if level <= 5 else 50 * level


## Rank na guilda ("D" a "S") e pontos de guilda (espelho do personagem).
func rank() -> String:
	return str(flags.get("rank", "D"))


## Rank que vale nas travas (carruagem, dungeons, missões, mapa): com o modo admin ligado qualquer rank
## serve, igual a CharRules.rank_at_least no servidor. O rank de verdade (rank()) não muda e é o que aparece.
func access_rank() -> String:
	return str(StoryRules.RANKS.back()) if admin_mode() else rank()


func guild_points() -> int:
	return int(flags.get("guild_pts", 0))


## Abate: a cura da comida (roubo de vida) é do combate, do cliente; XP e missão são do Econ.
func on_enemy_killed(kind: String, xp_reward: int, enemy_level := 0, area := "", drops := {}) -> void:
	kill_lifesteal()
	Econ.kill(kind, xp_reward, enemy_level, area, drops)


## Roubo de vida da comida ao abater (combate é do cliente; online o abate em si é do servidor).
func kill_lifesteal() -> void:
	var ls := float(buff_mods.get("lifesteal", 0.0)) + float(talent_mods.get("lifesteal", 0.0))
	if ls > 0.0 and hp > 0.0:
		hp = min(max_hp(), hp + ls)


## Renascer na vila: o ouro perdido é calculado pelas regras.
func death_penalty() -> void:
	Econ.request("death_penalty")


# ---------------------------------------------------------------- inventário (leitura)
func count_item(id: String) -> int:
	var n := 0
	for slot in inventory:
		if slot.id == id:
			n += slot.qty
	return n


## Usa um item da mochila. true = pedido feito (a cura/comida vale quando o Econ confirmar).
## A checagem "vida já está cheia" continua aqui, antes de pedir.
func use_item(id: String) -> bool:
	var it := ItemDB.get_item(id)
	if it.is_empty() or count_item(id) <= 0:
		return false
	match it.type:
		"consumable":
			if it.has("heal_hp") and hp >= max_hp():
				notify.emit("Vida já está cheia.", Color(1, 0.7, 0.6))
				return false
			if it.has("heal_mp") and mp >= max_mp():
				notify.emit("Mana já está cheia.", Color(1, 0.7, 0.6))
				return false
			Econ.request("consume", [id])
			return true
		"weapon", "armor", "gear", "tool":
			equip(id)
			return true
		"food", "crop":
			return eat(id)
		"seed":
			notify.emit("Plante na Horta, ao sul da vila.", Color(0.8, 1.0, 0.6))
		"scroll":
			Econ.request("consume", [id])   # aprende a receita (CraftRules.learn)
			return true
	return false


## Vida/mana acompanham o ganho de máximo e nunca passam do novo máximo.
func _clamp_vitals(old_hp: float, old_mp: float) -> void:
	if max_hp() > old_hp:
		hp += max_hp() - old_hp
	if max_mp() > old_mp:
		mp += max_mp() - old_mp
	hp = min(hp, max_hp())
	mp = min(mp, max_mp())


# ---------------------------------------------------------------- missões (leitura)
func quest_state(id: String) -> String:
	return quests[id].state if quests.has(id) else "none"


# ---------------------------------------------------------------- configurações
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for k in settings:
			settings[k] = cfg.get_value("settings", k, settings[k])
	apply_settings()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in settings:
		cfg.set_value("settings", k, settings[k])
	cfg.save(SETTINGS_PATH)
	ToonLook.reload_settings()   # estilo desenhado e contorno: lidos do arquivo, valem para o que for criado depois
	apply_settings()


## Bus de áudio (default_bus_layout.tres) -> chave do volume em settings.
const VOLUME_BUSES := {"Master": "master_volume", "Music": "music_volume", "SFX": "sfx_volume",
	"Ambience": "ambience_volume"}


func apply_settings() -> void:
	for bus in VOLUME_BUSES:
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0:
			var v := float(settings[VOLUME_BUSES[bus]])
			AudioServer.set_bus_volume_db(idx, linear_to_db(max(0.0001, v)))
			AudioServer.set_bus_mute(idx, v <= 0.0)
	if settings.fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


# ================================================================ comida
func is_edible(id: String) -> bool:
	var it := ItemDB.get_item(id)
	return it.get("type", "") == "food" or it.has("raw_hp") or it.has("raw_mp")


## Come uma comida (buff + cura) ou uma colheita crua (cura pequena). true = pedido feito; a cura e o
## bônus valem quando o Econ confirmar que tirou o item (no solo, antes desta função voltar).
func eat(id: String) -> bool:
	var it := ItemDB.get_item(id)
	if it.is_empty() or count_item(id) <= 0 or not is_edible(id):
		return false
	if eat_cooldown > 0.0:
		notify.emit("Ainda mastigando... (%.1fs)" % eat_cooldown, Color(1, 0.8, 0.55))
		return false
	# a recarga começa no pedido (evita comer duas vezes enquanto a resposta não chega)
	eat_cooldown = EAT_COOLDOWN if it.type == "food" else 1.0
	Econ.request("consume", [id])
	return true


## O Econ confirmou: bônus e cura da comida (o aviso com o nome veio nos eventos).
func _apply_food(id: String) -> void:
	var it := ItemDB.get_item(id)
	var old_max := max_hp()
	if it.has("buff"):
		add_buff(str(it.buff))
		if max_hp() > old_max:
			hp += max_hp() - old_max
	if it.get("heal_full", false):
		hp = max_hp()
	hp = min(max_hp(), hp + float(it.get("heal_hp", 0)) + float(it.get("raw_hp", 0)))
	mp = min(max_mp(), mp + float(it.get("heal_mp", 0)) + float(it.get("raw_mp", 0)))
	food_eaten.emit(id)
	stats_changed.emit()


## O Econ confirmou a poção.
func _apply_potion(id: String) -> void:
	var it := ItemDB.get_item(id)
	if it.has("heal_hp"):
		hp = min(max_hp(), hp + float(it.heal_hp))
	if it.has("heal_mp"):
		mp = min(max_mp(), mp + float(it.heal_mp))
	stats_changed.emit()


func eat_selected() -> bool:
	ensure_selected_food()
	if selected_food == "":
		notify.emit("Sem comida! Cozinhe no Caldeirão da Horta.", Color(1, 0.7, 0.55))
		return false
	return eat(selected_food)


## Comidas da mochila na ordem das receitas (só pratos do caldeirão).
func food_in_bag() -> Array[String]:
	var out: Array[String] = []
	for id in ItemDB.RECIPE_ORDER:
		if count_item(id) > 0:
			out.append(id)
	return out


func ensure_selected_food() -> void:
	var foods := food_in_bag()
	if selected_food == "" or not foods.has(selected_food):
		selected_food = foods[0] if not foods.is_empty() else ""


func cycle_food() -> void:
	var foods := food_in_bag()
	if foods.is_empty():
		selected_food = ""
		notify.emit("Sem comida na mochila.", Color(1, 0.7, 0.55))
		return
	var i := foods.find(selected_food)
	selected_food = foods[(i + 1) % foods.size()]
	notify.emit("Comida: %s x%d" % [ItemDB.get_item(selected_food).name, count_item(selected_food)], Color(1, 0.85, 0.5))
	inventory_changed.emit()


## Liga o buff `id` (de buffs.json) por `secs` (negativo = o `time` da tabela); se já está ativo, renova.
func add_buff(id: String, secs := -1.0) -> void:
	var row: Dictionary = ItemDB.BUFFS.get(id, {})
	if row.is_empty():
		return
	buffs[id] = float(row.time) if secs < 0.0 else secs
	_recalc_buff_mods()
	stats_changed.emit()


func has_buff(id: String) -> bool:
	return buffs.has(id)


func tick_buffs(delta: float) -> void:
	eat_cooldown = max(0.0, eat_cooldown - delta)
	if buffs.is_empty():
		return
	var expired: Array = []
	for id in buffs:
		buffs[id] -= delta
		if buffs[id] <= 0.0:
			expired.append(id)
	if expired.is_empty():
		return
	for id in expired:
		buffs.erase(id)
		notify.emit("%s acabou." % ItemDB.BUFFS.get(id, {}).get("name", id), Color(0.75, 0.7, 0.6))
	_recalc_buff_mods()
	hp = min(hp, max_hp())
	stats_changed.emit()


func clear_buffs(silent := false) -> void:
	var had := not buffs.is_empty()
	buffs = {}
	eat_cooldown = 0.0
	_recalc_buff_mods()
	if had and not silent:
		notify.emit("Os efeitos de comida e habilidades se perderam.", Color(0.8, 0.7, 0.6))


func _recalc_buff_mods() -> void:
	buff_mods = {}
	for id in buffs:
		var add: Dictionary = ItemDB.BUFFS.get(id, {}).get("add", {})
		for k in add:
			buff_mods[k] = float(buff_mods.get(k, 0.0)) + float(add[k])


# ================================================================ caldeirão
func can_cook(recipe: String) -> int:
	var n := 999
	var ing: Dictionary = ItemDB.RECIPES[recipe]
	for id in ing:
		n = min(n, count_item(id) / int(ing[id]))
	return n


## Cozinha até `times` vezes. Quantas saíram: o evento "looted" da resposta (ver cooking_ui).
func cook(recipe: String, times := 1) -> void:
	Econ.request("cook", [recipe, clampi(times, 1, CharRules.MAX_COUNT)])


# ================================================================ profissões e craft
func prof_level(prof: String) -> int:
	return int(professions.get(prof, {}).get("lv", 1))


func prof_xp(prof: String) -> int:
	return int(professions.get(prof, {}).get("xp", 0))


func prof_name(prof: String) -> String:
	return str(CraftRules.professions(Balance.tables).get(prof, {}).get("name", prof))


## Estado do personagem do jeito que as regras puras leem (para CraftRules.can_craft etc. na tela).
func char_state() -> CharState:
	var s := CharState.new()
	s.gold = gold
	s.level = level
	s.inventory = inventory
	s.professions = professions
	s.recipes = recipes
	return s


## Fabrica até `times` vezes na estação (o servidor decide; a resposta traz os itens e a XP).
func craft(recipe: String, times := 1) -> void:
	Econ.request("craft", [recipe, clampi(times, 1, CharRules.MAX_COUNT)])


# ================================================================ horta (o crescimento corre pelo relógio)
## Crescimento do canteiro agora (0..1).
func plot_growth(i: int) -> float:
	if i < 0 or i >= farm.get("plots", []).size():
		return 0.0
	return CharRules.farm_growth(farm.plots[i], Balance.tables, Econ.now())


func plot_state(i: int) -> String:
	if i < 0 or i >= farm.get("plots", []).size():
		return "locked"
	if i >= int(farm.unlocked):
		return "locked"
	var p: Dictionary = farm.plots[i]
	if p.crop == "":
		return "empty"
	return "ready" if plot_growth(i) >= 1.0 else "growing"


func unlock_cost() -> int:
	var fr: Dictionary = Balance.tables.get_table("rules").get("farm", {})
	return int(fr.get("unlock_base", 30)) + int(fr.get("unlock_step", 15)) * (int(farm.get("unlocked", 0)) - int(fr.get("start", 6)))


func unlock_next_plot() -> void:
	Econ.request("unlock_plot")


## Planta no canteiro i. Se faltar semente e buy_missing, compra uma.
func plant(i: int, crop: String, buy_missing := false) -> void:
	Econ.request("plant", [i, crop, buy_missing])


func water(i: int) -> void:
	Econ.request("water", [i])


## Adubo de gel de slime: +40% de crescimento na hora (uma vez por plantio).
func fertilize(i: int) -> void:
	Econ.request("fertilize", [i])


## Colhe o canteiro i. O que saiu chega no evento "harvest" (Econ.done).
func harvest(i: int) -> void:
	Econ.request("harvest", [i])


# ================================================================ classe (atalho dos testes e demos)
## Personagem sem classe: o servidor recusa tudo até a escolha (a tela de criação é a de verdade).
## Testes e demos pulam a tela: `--class=<id>` e `--body=m|f` escolhem; sem eles, --smoketest, --vilatest,
## --nettest= e as demos (--farmdemo/--geardemo/--enchantdemo/--weapon=) pedem guerreiro/m (ou a classe da
## arma de `--weapon=`). Chamado por Econ logo depois de carregar o personagem inteiro (solo ou servidor).
func auto_choose_class() -> void:
	if char_class != "" or skip_auto_class:
		return
	var pick := harness_class(OS.get_cmdline_user_args())
	if pick[0] != "":
		_auto_class_pending = true
		Econ.request("choose_class", pick)


## [classe, corpo, penteado] que os argumentos de teste pedem (classe "" = nenhuma: mostra a tela de criação).
static func harness_class(args: PackedStringArray) -> Array:
	var cls := ""
	var bd := "m"
	var hr := ""
	var harness := false
	var weapon := ""
	for a in args:
		if a.begins_with("--class="):
			cls = a.substr(8)
		elif a.begins_with("--body="):
			bd = a.substr(7)
		elif a.begins_with("--hair="):   # penteado (capturas): `--body=f --hair=f_marias`
			hr = a.substr(7)
		elif a.begins_with("--weapon="):
			weapon = a.substr(9)
			harness = true
		elif a in ["--smoketest", "--vilatest", "--farmdemo", "--geardemo", "--enchantdemo", "--introdemo"] or a.begins_with("--nettest=") \
				or a.begins_with("--groupdemo="):
			harness = true
	if cls == "" and weapon != "":
		var wc := CharRules.weapon_class(Balance.tables, weapon)
		for id in CharRules.CLASS_IDS:
			if CharRules.class_weapon(Balance.tables, id) == wc:
				cls = id
	if cls == "" and harness:
		cls = "warrior"
	return [cls, bd, hr if HairStyles.valid(bd, hr) else ""]


## `--ui=craft[:forge|leather|alchemy]` abre a bancada com materiais e a profissão no nível de `--prof=N`
## (só o espelho: serve para capturas da tela). `--recipe=<id>` escolhe a receita; `--craftanim=work|ok|fail`
## mostra a animação nessa fase, com um desfecho de mentira.
func _craft_demo(w: Node, station: String, args: PackedStringArray) -> void:
	Econ.grant(900, 0, {"iron_ore": 14, "oak_log": 3, "essence_t2": 5, "copper_ore": 9, "pine_log": 4, "essence_t1": 6,
		"silver_ore": 6, "silverbirch_log": 1, "essence_t3": 2, "hide_t1": 8, "hide_t2": 5, "mint": 3, "slime_gel": 4}, "demo", true)
	var prof := str(Balance.tables.get_table("professions").get("stations", {}).get(station, {}).get("prof", ""))
	var rid := ""
	var fx := ""
	for a in args:
		if a.begins_with("--prof="):
			professions[prof] = {"lv": int(a.substr(7)), "xp": 40, "done": []}
		elif a.begins_with("--recipe="):
			rid = a.substr(9)
		elif a.begins_with("--craftanim="):
			fx = a.substr(12)
	w.open_crafting(station)
	var ui := w.modal as CraftingUI
	if ui == null:
		return
	if rid != "":
		ui._select(rid)
		ui._scroll_to_selected.call_deferred()
	if fx != "":
		var out: String = ui._out(ui._sel)
		ui.anim.start(out, station)
		if fx == "ok":
			ui.anim.resolve([[ItemQuality.make(out, "fina", "aguia" if CraftRules.has_affix(Balance.tables, ui._sel) else ""), 1]], 0, {})
		elif fx == "fail":
			ui.anim.resolve([], 1, {"iron_ore": 3, "essence_t2": 1})


# ================================================================ espelho
## Estado vindo do CharacterService (solo ou servidor). `full` = também vida, mana e posição
## (carga do personagem); senão o combate continua dono de vida/mana e só o teto do máximo é ajustado.
func apply_state(d: Dictionary, full := false) -> void:
	var s := CharState.from_dict(d, Balance.tables)
	var old_hp := max_hp()
	var old_mp := max_mp()
	var old_class := weapon_class()
	var old_off := offhand_kind()
	var quests_before := quests
	var bestiary_before := bestiary
	var farm_before := farm
	var enchant_before := weapon_enchant()
	level = s.level
	xp = s.xp
	gold = s.gold
	stat_points = s.stat_points
	attributes = s.attributes
	inventory = s.inventory
	equipment = s.equipment
	quests = s.quests
	flags = s.flags
	kills = s.kills
	bestiary = s.bestiary
	farm = s.farm
	ecos = s.ecos
	passives = s.passives
	meta_mods = CharRules.meta_mods(Balance.tables, passives)
	talents = s.talents
	talent_mods = CharRules.talent_mods(Balance.tables, s)
	professions = s.professions
	recipes = s.recipes
	enchants = s.enchants
	char_class = s.char_class
	body = s.body
	hair = s.hair
	if full:
		reset_run_mods()
		clear_buffs(true)
		hp = s.hp if s.hp > 0.0 else max_hp()
		mp = s.mp
		fury = s.fury
		hp = minf(hp, max_hp())
		mp = minf(mp, max_mp())
		stamina = max_stamina()
		spawn_position = s.world_pos
		spawn_yaw = s.world_yaw
	else:
		_clamp_vitals(old_hp, old_mp)
	if selected_food != "" and count_item(selected_food) <= 0:
		ensure_selected_food()
	stats_changed.emit()
	inventory_changed.emit()
	if weapon_enchant() != enchant_before:
		enchant_changed.emit()
	if weapon_class() != old_class or offhand_kind() != old_off:
		kit_changed.emit()
	if quests != quests_before:
		quests_changed.emit()
	if farm != farm_before:
		farm_changed.emit()
	if bestiary != bestiary_before:
		bestiary_changed.emit()


## Eventos das regras: avisos, nível, itens ganhos (os sinais que a UI já escuta).
func apply_events(events: Array) -> void:
	for e in events:
		if not (e is Dictionary):
			continue
		match e.get("t", ""):
			"notify":
				notify.emit(str(e.get("text", "")), e.get("color", Color.WHITE))
			"level_up":
				hp = max_hp()
				mp = max_mp()
				leveled_up.emit(int(e.get("level", level)))
				stats_changed.emit()
			"looted":
				item_looted.emit(str(e.get("id", "")), int(e.get("qty", 1)))
			"quest":
				quests_changed.emit()
			"rank":
				ranked_up.emit(str(e.get("rank", "")))
			"farm":
				farm_changed.emit()


## O que o cliente faz depois que uma op é confirmada (cura de poção/comida, comida selecionada).
func after_op(op: String, args: Array, ok: bool, _events: Array) -> void:
	match op:
		"choose_class":
			_auto_class_pending = false
		"consume":
			var id := str(args[0]) if not args.is_empty() else ""
			if not ok:
				if is_edible(id):
					eat_cooldown = 0.0   # não comeu: libera a recarga
				return
			if is_edible(id):
				_apply_food(id)
			else:
				_apply_potion(id)
		"cook":
			if ok and selected_food == "" and not args.is_empty():
				selected_food = str(args[0])


## Abre a tela `ui_name` de `--ui=` (para capturas).
func _open_debug_ui(w: Node, ui_name: String, args: PackedStringArray) -> void:
	match ui_name:
		"inv":
			w._open_menu(0)
		"char":
			w._open_menu(1)
		"talents":
			w._open_menu(2)
		"quests":
			w._open_menu(3)
		"bestiary":   # `--bestiary-sel=<tipo>` abre a ficha da criatura; `--bestiary-page=<n>`, a página da grade
			w._open_menu(5)
			await get_tree().process_frame
			var bp: BestiaryPanel = w.modal.bestiary_panel if w.modal and w.modal.get("bestiary_panel") else null
			for a in args:
				if bp != null and a.begins_with("--bestiary-sel="):
					bp._sel = a.substr(15)
					bp.refresh()
				elif bp != null and a.begins_with("--bestiary-page="):
					bp._page = int(a.substr(16))
					bp.refresh()
		"tools":
			w._open_menu(0)
			await get_tree().process_frame
			if w.modal:
				w.modal._set_side_tab("tools")
		"shop":
			w.open_shop()
		"plant":
			w.open_plant_menu(0)
		"plant_ok":   # a janelinha de confirmação de plantar
			w.open_plant_menu(0)
			await get_tree().process_frame
			if w.modal and w.modal.has_method("_plant_here"):
				w.modal._plant_here()
		"cook":
			w.open_cooking()
		"prof":
			w._open_menu(4)
		"orin":
			w.open_modal(load("res://scripts/ui/passive_master_ui.gd").new())
		"map":
			w.open_world_map()
		"party":
			w.open_world_map(1)
		"friends":
			w.open_world_map(2)
		"enchant":
			for n in get_tree().get_nodes_in_group("interactable"):
				if n.get("npc_id") == "blacksmith":
					w.open_enchant(n)
		"craft", "craft:forge", "craft:leather", "craft:alchemy":
			_craft_demo(w, ui_name.get_slice(":", 1) if ":" in ui_name else "forge", args)
