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
signal notify(text: String, color: Color)
signal leveled_up(new_level: int)
signal food_eaten(id: String)
signal farm_changed
signal item_looted(id: String, qty: int)

const SETTINGS_PATH := "user://settings.cfg"
const WORLD_SCENE := "res://scenes/world.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const COLONY_SCENE := "res://scenes/colony.tscn"

## Defesa da Cidade solo: save da cidade (a partida em andamento, com o caixa dela). O personagem é o do
## save solo: a cidade não tem personagem próprio.
var colony_save_path := "user://colony_save.json"
## true = a cena da cidade carrega o save em vez de começar do zero.
var colony_continue := false

var settings := {"mouse_sensitivity": 0.25, "master_volume": 0.8, "fullscreen": false, "invert_y": false,
	"player_name": "", "server_address": ""}

# ---- espelho do personagem (escrito só por apply_state)
var level := 1
var xp := 0
var gold := 0
var stat_points := 0
var attributes := {"str": 5, "int": 5, "vit": 5, "agi": 5}
var inventory: Array = []   # [{"id": String, "qty": int}]
var equipment := empty_equipment()
var quests := {}            # id -> {"state": "active"|"ready"|"done", "progress": int}
var flags := {}
var kills := 0
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
## Bônus de comida ativos (somados aos run_mods em mod()). Valem na vila e na Horda.
var food_mods := {}
var food_buffs := {}        # id da comida -> segundos restantes
var eat_cooldown := 0.0
var selected_food := ""


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
		if a.begins_with("--nettest="):
			get_tree().root.add_child.call_deferred(load("res://tests/net_test.gd").new())
	if "--colonytest" in OS.get_cmdline_user_args():
		colony_save_path = "user://colonytest_save.json"   # o Econ usa user://colonytest_solo.json, apagado no início
		get_tree().root.add_child.call_deferred(load("res://tests/colony_test.gd").new())
	if "--smoketest" in OS.get_cmdline_user_args():
		# o Econ usa user://smoketest_solo.json, apagado no início
		get_tree().root.add_child.call_deferred(load("res://tests/smoke_test.gd").new())


## Depuração: `godot -- --shot=shot.png [--delay=4]` salva um screenshot e fecha.
## `--survival` (com ou sem --shot) começa direto no Desafio da Horda.
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
	var demo := "--farmdemo" in args or "--geardemo" in args
	for a in args:
		demo = demo or a.begins_with("--weapon=")
	if demo:
		var at = spawn_position
		Econ.start_scratch_solo("user://demo_solo.json")
		if at != null:
			spawn_position = at
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
		food_buffs = {"spicy_soup": 30.0, "garden_salad": 4.0}
		_recalc_food_mods()
		for a in args:   # --farmdemo --ui=cook|plant abre o menu
			if a.begins_with("--ui="):
				await get_tree().create_timer(1.0).timeout
				var w = get_tree().current_scene
				if a == "--ui=cook":
					w.open_cooking()
				else:
					w.open_plant_menu(10)
	# `--geardemo` dá um punhado dos equipamentos novos (para screenshots do inventário e da loja)
	# `--weapon=<id>` equipa uma arma; `--ui=inv|char|quests|shop` abre a tela (sem --farmdemo)
	if "--geardemo" in args:
		var gear_ids := {}
		for id in ["frost_brand", "ember_staff", "elven_bow", "storm_bow", "dragonfang", "knight_shield", "arcane_orb",
				"hunter_quiver", "iron_helm", "mage_robe", "royal_plate", "iron_gauntlets", "swift_boots", "vampire_ring",
				"sage_amulet", "goblin_cleaver", "guardian_greatsword", "royal_wings", "titan_cleaver", "rose_flame", "knight_helm", "chain_mail", "archer_bracers",
				"iron_greaves", "life_amulet", "strength_ring"]:
			gear_ids[id] = 1
		gear_ids["slime_gel"] = 7
		gear_ids["goblin_ear"] = 3
		gear_ids["spicy_soup"] = 2
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
		if a.begins_with("--weapon="):
			Econ.grant(0, 0, {a.substr(9): 1}, "demo", true)
			equip(a.substr(9))
	if "--farmdemo" not in args:
		for a in args:
			if a.begins_with("--ui="):
				await get_tree().create_timer(1.0).timeout
				var w = get_tree().current_scene
				match a.substr(5):
					"inv":
						w._open_menu(0)
					"char":
						w._open_menu(1)
					"quests":
						w._open_menu(2)
					"shop":
						w.open_shop()
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
				pl.spring.spring_length = float(c[1])
		delay = 1.0
	await get_tree().create_timer(delay, true).timeout
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
		"interact": [KEY_E], "spell_1": [KEY_1], "spell_2": [KEY_2], "spell_3": [KEY_3],
		"potion": [KEY_R], "mana_potion": [KEY_F], "inventory": [KEY_I, KEY_TAB], "character": [KEY_C],
		"quest_log": [KEY_J], "pause": [KEY_ESCAPE], "quicksave": [KEY_F5], "quickload": [KEY_F9],
		"eat": [KEY_Q], "food_next": [KEY_T],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	var mouse := {"attack": MOUSE_BUTTON_LEFT, "dodge": MOUSE_BUTTON_RIGHT}
	for action in mouse:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var mb := InputEventMouseButton.new()
		mb.button_index = mouse[action]
		InputMap.action_add_event(action, mb)



# ---------------------------------------------------------------- jogo solo
## "Novo jogo": apaga o personagem solo (o menu pergunta antes) e entra em Valdoria com um novo.
func start_new_game() -> void:
	reset_run_mods()
	Econ.reset_solo()
	get_tree().paused = false
	get_tree().change_scene_to_file(WORLD_SCENE)


## "Continuar": o personagem do save solo.
func continue_game() -> bool:
	if not Econ.has_solo() or not Econ.start_solo():
		notify.emit("Nenhum jogo salvo.", Color(1, 0.5, 0.5))
		return false
	reset_run_mods()
	get_tree().paused = false
	get_tree().change_scene_to_file(WORLD_SCENE)
	return true


## Defesa da Cidade solo: cont = continuar a cidade salva (senão começa uma nova). O personagem é sempre o
## do save solo (a cena o carrega); a cidade tem caixa próprio (Colony.treasury).
func start_colony(cont: bool) -> void:
	colony_continue = cont and has_colony_save()
	reset_run_mods()
	get_tree().paused = false
	get_tree().change_scene_to_file(COLONY_SCENE)


func has_colony_save() -> bool:
	return FileAccess.file_exists(colony_save_path)


func colony_save_info() -> String:
	var f := FileAccess.open(colony_save_path, FileAccess.READ)
	if f == null:
		return ""
	var data = JSON.parse_string(f.get_as_text())
	if not data is Dictionary:
		return ""
	return "Dia %d — %s" % [int(data.get("day", 1)), data.get("time", "")]


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
	get_tree().change_scene_to_file(MENU_SCENE)


# ---------------------------------------------------------------- bônus da horda
func reset_run_mods() -> void:
	run_mods = {
		"active": false, "damage": 1.0, "max_hp": 1.0, "max_hp_flat": 0.0, "speed": 1.0,
		"defense": 0.0, "regen": 0.0, "crit": 0.0, "cooldown": 1.0, "area": 1.0, "magnet": 1.0,
		"xp": 1.0, "gold": 1.0, "lifesteal": 0.0,
	}


func damage_mult() -> float:
	return mod("damage")


## Valor efetivo de um bônus: Desafio da Horda + comida.
func mod(k: String) -> float:
	return float(run_mods.get(k, 0.0)) + float(food_mods.get(k, 0.0))


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
	return 25.0 + attr("int") * 6.0 + (level - 1) * 3.0 + gear("mp")


func max_stamina() -> float:
	return 70.0 + attr("agi") * 5.0


## Dano do ataque básico conforme a classe da arma (espada FOR, cajado INT, arco AGI).
func melee_damage() -> float:
	match weapon_class():
		"staff":
			return (weapon_damage() + attr("int") * 1.4 + gear("spell") * 0.5) * mod("damage")
		"bow":
			return (weapon_damage() + attr("agi") * 1.5 + attr("str") * 0.3) * mod("damage")
	return (weapon_damage() + attr("str") * 1.6) * mod("damage")


func spell_power() -> float:
	return attr("int") * 1.0 + gear("spell")


func crit_chance() -> float:
	return 0.08 + attr("agi") * 0.004 + gear("crit") + mod("crit")


func cooldown_mult() -> float:
	return clampf(1.0 - gear("cdr"), 0.4, 1.0)


func defense() -> float:
	return armor_defense() + attr("vit") * 0.4 + mod("defense")


func speed_multiplier() -> float:
	return (1.0 + (attr("agi") - 5) * 0.015 + gear("speed")) * mod("speed")


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
func on_damage_dealt(amount: float) -> void:
	var l := gear("leech")
	if l > 0.0 and hp > 0.0:
		hp = min(max_hp(), hp + amount * l)




func xp_to_next() -> int:
	return CharRules.xp_to_next(level, Balance.tables)


func knows_spell(id: String) -> bool:
	return level >= ItemDB.SPELLS[id].level


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


## Abate: a cura da comida (roubo de vida) é do combate, do cliente; XP e missão são do Econ.
func on_enemy_killed(kind: String, xp_reward: int) -> void:
	kill_lifesteal()
	Econ.kill(kind, xp_reward)


## Roubo de vida da comida ao abater (combate é do cliente; online o abate em si é do servidor).
func kill_lifesteal() -> void:
	if float(food_mods.get("lifesteal", 0.0)) > 0.0 and hp > 0.0:
		hp = min(max_hp(), hp + float(food_mods.lifesteal))


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
		"weapon", "armor", "gear":
			equip(id)
			return true
		"food", "crop":
			return eat(id)
		"seed":
			notify.emit("Plante na Horta, ao sul da vila.", Color(0.8, 1.0, 0.6))
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
	apply_settings()


func apply_settings() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(max(0.0001, float(settings.master_volume))))
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
		food_buffs[id] = float(it.buff.time)
		_recalc_food_mods()
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


func tick_food(delta: float) -> void:
	eat_cooldown = max(0.0, eat_cooldown - delta)
	if food_buffs.is_empty():
		return
	var expired: Array = []
	for id in food_buffs:
		food_buffs[id] -= delta
		if food_buffs[id] <= 0.0:
			expired.append(id)
	if expired.is_empty():
		return
	for id in expired:
		food_buffs.erase(id)
		notify.emit("%s acabou." % ItemDB.get_item(id).buff.name, Color(0.75, 0.7, 0.6))
	_recalc_food_mods()
	hp = min(hp, max_hp())
	stats_changed.emit()


func clear_food(silent := false) -> void:
	var had := not food_buffs.is_empty()
	food_buffs = {}
	eat_cooldown = 0.0
	_recalc_food_mods()
	if had and not silent:
		notify.emit("Os efeitos da comida se perderam.", Color(0.8, 0.7, 0.6))


func _recalc_food_mods() -> void:
	food_mods = {}
	for id in food_buffs:
		var add: Dictionary = ItemDB.get_item(id).buff.add
		for k in add:
			food_mods[k] = float(food_mods.get(k, 0.0)) + float(add[k])


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


# ================================================================ espelho
## Estado vindo do CharacterService (solo ou servidor). `full` = também vida, mana e posição
## (carga do personagem); senão o combate continua dono de vida/mana e só o teto do máximo é ajustado.
func apply_state(d: Dictionary, full := false) -> void:
	var s := CharState.from_dict(d, Balance.tables)
	var old_hp := max_hp()
	var old_mp := max_mp()
	var quests_before := quests
	var farm_before := farm
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
	farm = s.farm
	if full:
		reset_run_mods()
		clear_food(true)
		hp = s.hp if s.hp > 0.0 else max_hp()
		mp = s.mp
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
	if quests != quests_before:
		quests_changed.emit()
	if farm != farm_before:
		farm_changed.emit()


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
			"farm":
				farm_changed.emit()


## O que o cliente faz depois que uma op é confirmada (cura de poção/comida, comida selecionada).
func after_op(op: String, args: Array, ok: bool, _events: Array) -> void:
	match op:
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
