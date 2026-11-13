extends Node
## Estado global do jogo: atributos, inventário, missões, configurações e save/load.

signal stats_changed
signal inventory_changed
signal quests_changed
signal notify(text: String, color: Color)
signal leveled_up(new_level: int)
signal food_eaten(id: String)
signal farm_changed
signal item_looted(id: String, qty: int)

var save_path := "user://savegame.json"
const SETTINGS_PATH := "user://settings.cfg"
const WORLD_SCENE := "res://scenes/world.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"

var settings := {"mouse_sensitivity": 0.25, "master_volume": 0.8, "fullscreen": false, "invert_y": false,
	"player_name": "", "server_address": ""}

var level := 1
var xp := 0
var gold := 0
var stat_points := 0
var attributes := {"str": 5, "int": 5, "vit": 5, "agi": 5}
var hp := 100.0
var mp := 50.0
var stamina := 100.0
var inventory: Array = []   # [{"id": String, "qty": int}]
var equipment := empty_equipment()
var quests := {}            # id -> {"state": "active"|"ready"|"done", "progress": int}
var flags := {}
var kills := 0
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
## {"unlocked": int, "plots": [{"crop": String, "growth": float 0..1, "watered": bool, "fert": bool}]}
var farm := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	load_settings()
	reset_run_mods()
	new_game()
	_debug_screenshot()
	if "--dbg" in OS.get_cmdline_user_args():
		get_tree().root.add_child.call_deferred(load("res://tests/debug_dialogue.gd").new())
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--nettest="):
			get_tree().root.add_child.call_deferred(load("res://tests/net_test.gd").new())
	if "--smoketest" in OS.get_cmdline_user_args():
		save_path = "user://smoketest_save.json"
		get_tree().root.add_child.call_deferred(load("res://tests/smoke_test.gd").new())


## Depuração: `godot -- --shot=shot.png [--delay=4]` salva um screenshot e fecha.
## `--survival` (com ou sem --shot) começa direto no Desafio da Horda.
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
	# `--farmdemo` enche a horta com culturas em vários estágios (para screenshots)
	if "--farmdemo" in OS.get_cmdline_user_args():
		farm.unlocked = FARM_PLOTS - 2
		for i in farm.unlocked:
			farm.plots[i] = {"crop": ItemDB.CROP_ORDER[i % 6], "growth": [1.0, 0.7, 0.35][i / 4 % 3] if i < 8 else 1.0,
				"watered": i % 2 == 0, "fert": false}
		for r in ItemDB.RECIPE_ORDER:
			add_item(r, 2, true)
		food_buffs = {"spicy_soup": 30.0, "garden_salad": 4.0}
		_recalc_food_mods()
		for a in OS.get_cmdline_user_args():   # --farmdemo --ui=cook|plant abre o menu
			if a.begins_with("--ui="):
				await get_tree().create_timer(1.0).timeout
				var w = get_tree().current_scene
				if a == "--ui=cook":
					w.open_cooking()
				else:
					w.open_plant_menu(10)
	# `--geardemo` dá um punhado dos equipamentos novos (para screenshots do inventário e da loja)
	# `--weapon=<id>` equipa uma arma; `--ui=inv|char|quests|shop` abre a tela (sem --farmdemo)
	var args := OS.get_cmdline_user_args()
	if "--geardemo" in args:
		level = 6
		gold = 1450
		stat_points = 3
		for id in ["frost_brand", "ember_staff", "elven_bow", "storm_bow", "dragonfang", "knight_shield", "arcane_orb",
				"hunter_quiver", "iron_helm", "mage_robe", "royal_plate", "iron_gauntlets", "swift_boots", "vampire_ring",
				"sage_amulet", "goblin_cleaver", "guardian_greatsword"]:
			add_item(id, 1, true)
		for id in ["knight_helm", "chain_mail", "archer_bracers", "iron_greaves", "life_amulet", "strength_ring"]:
			add_item(id, 1, true)
			equip(id)
		add_item("slime_gel", 7, true)
		add_item("goblin_ear", 3, true)
		add_item("spicy_soup", 2, true)
		quests = {"slimes": {"state": "done", "progress": 5}, "goblins": {"state": "active", "progress": 2}}
		hp = max_hp() * 0.62
	for a in args:
		if a.begins_with("--weapon="):
			add_item(a.substr(9), 1, true)
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


# ---------------------------------------------------------------- novo jogo
func new_game() -> void:
	reset_run_mods()
	level = 1
	xp = 0
	gold = 25
	stat_points = 0
	attributes = {"str": 5, "int": 5, "vit": 5, "agi": 5}
	inventory = []
	equipment = empty_equipment()
	equipment.weapon = "wooden_sword"
	quests = {}
	flags = {}
	kills = 0
	spawn_position = null
	spawn_yaw = 0.0
	farm = default_farm()
	clear_food(true)
	add_item("health_potion", 3, true)
	add_item("mana_potion", 1, true)
	add_item("seed_carrot", 4, true)
	add_item("seed_wheat", 4, true)
	add_item("bread", 1, true)
	# kit inicial para experimentar as três classes de arma
	add_item("apprentice_staff", 1, true)
	add_item("short_bow", 1, true)
	add_item("leather_cap", 1, true)
	hp = max_hp()
	mp = max_mp()
	stamina = max_stamina()


func start_new_game() -> void:
	new_game()
	get_tree().paused = false
	get_tree().change_scene_to_file(WORLD_SCENE)


func go_to_menu() -> void:
	if Network.is_online():
		Network.autosave()
		Network.leave()
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
	return int(60 * pow(level, 1.55))


func add_xp(amount: int) -> void:
	xp += amount
	notify.emit("+%d XP" % amount, Color(0.6, 0.85, 1.0))
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		stat_points += 3
		hp = max_hp()
		mp = max_mp()
		notify.emit("Nível %d! +3 pontos de atributo (C)" % level, Color(1.0, 0.85, 0.3))
		for id in ItemDB.SPELLS:
			if ItemDB.SPELLS[id].level == level:
				notify.emit("Nova magia: %s [%s]" % [ItemDB.SPELLS[id].name, ItemDB.SPELLS[id].key], Color(0.75, 0.55, 1.0))
		leveled_up.emit(level)
	stats_changed.emit()


func add_gold(amount: int) -> void:
	gold += amount
	stats_changed.emit()


func spend_point(attr: String) -> void:
	if stat_points <= 0:
		return
	var old_hp := max_hp()
	var old_mp := max_mp()
	stat_points -= 1
	attributes[attr] += 1
	hp += max_hp() - old_hp
	mp += max_mp() - old_mp
	stats_changed.emit()


func knows_spell(id: String) -> bool:
	return level >= ItemDB.SPELLS[id].level


# ---------------------------------------------------------------- inventário
func add_item(id: String, qty := 1, silent := false) -> void:
	if ItemDB.is_stackable(id):
		for slot in inventory:
			if slot.id == id:
				slot.qty += qty
				_after_item_added(id, qty, silent)
				return
		inventory.append({"id": id, "qty": qty})
	else:
		for i in qty:
			inventory.append({"id": id, "qty": 1})
	_after_item_added(id, qty, silent)


func _after_item_added(id: String, qty: int, silent: bool) -> void:
	if not silent:
		item_looted.emit(id, qty)   # o HUD mostra um aviso com ícone e cor da raridade
	inventory_changed.emit()


## Ordena a mochila: equipamentos primeiro (mais raros antes), depois consumíveis e o resto.
func sort_inventory() -> void:
	inventory.sort_custom(_inv_less)
	inventory_changed.emit()


func _inv_less(a: Dictionary, b: Dictionary) -> bool:
	var cat_rank := {"equip": 0, "use": 1, "misc": 2}
	var ca: int = cat_rank[ItemDB.category(a.id)]
	var cb: int = cat_rank[ItemDB.category(b.id)]
	if ca != cb:
		return ca < cb
	var ra: int = ItemDB.RARITY[ItemDB.rarity_of(a.id)].rank
	var rb: int = ItemDB.RARITY[ItemDB.rarity_of(b.id)].rank
	if ra != rb:
		return ra > rb
	var sa := ItemDB.slot_of(a.id)
	var sb := ItemDB.slot_of(b.id)
	if sa != sb:
		return sa < sb
	return str(ItemDB.get_item(a.id).name) < str(ItemDB.get_item(b.id).name)


func count_item(id: String) -> int:
	var n := 0
	for slot in inventory:
		if slot.id == id:
			n += slot.qty
	return n


func remove_item(id: String, qty := 1) -> bool:
	if count_item(id) < qty:
		return false
	var i := inventory.size() - 1
	while i >= 0 and qty > 0:
		var slot = inventory[i]
		if slot.id == id:
			var take: int = min(qty, slot.qty)
			slot.qty -= take
			qty -= take
			if slot.qty <= 0:
				inventory.remove_at(i)
		i -= 1
	inventory_changed.emit()
	return true


func use_item(id: String) -> bool:
	var it := ItemDB.get_item(id)
	if it.is_empty() or count_item(id) <= 0:
		return false
	match it.type:
		"consumable":
			if it.has("heal_hp"):
				if hp >= max_hp():
					notify.emit("Vida já está cheia.", Color(1, 0.7, 0.6))
					return false
				hp = min(max_hp(), hp + it.heal_hp)
			if it.has("heal_mp"):
				if mp >= max_mp():
					notify.emit("Mana já está cheia.", Color(1, 0.7, 0.6))
					return false
				mp = min(max_mp(), mp + it.heal_mp)
			remove_item(id, 1)
			stats_changed.emit()
			return true
		"weapon", "armor", "gear":
			return equip(id)
		"food", "crop":
			return eat(id)
		"seed":
			notify.emit("Plante na Horta, ao sul da vila.", Color(0.8, 1.0, 0.6))
	return false


func equip(id: String) -> bool:
	var slot_name := ItemDB.slot_of(id)
	if slot_name == "" or count_item(id) <= 0:
		return false
	var it := ItemDB.get_item(id)
	# mão secundária precisa combinar com a classe da arma (escudo-espada, orbe-cajado, aljava-arco)
	if slot_name == "offhand" and it.has("needs") and it.needs != weapon_class():
		notify.emit("%s exige %s." % [it.name, ItemDB.CLASS_NAMES[it.needs].to_lower()], Color(1, 0.6, 0.5))
		return false
	var old_hp := max_hp()
	var old_mp := max_mp()
	remove_item(id, 1)
	if equipment[slot_name] != "":
		add_item(equipment[slot_name], 1, true)
	equipment[slot_name] = id
	# trocou de classe de arma: a mão secundária incompatível volta para a mochila
	if slot_name == "weapon" and equipment.offhand != "":
		var off := ItemDB.get_item(equipment.offhand)
		if off.has("needs") and off.needs != weapon_class():
			add_item(equipment.offhand, 1, true)
			notify.emit("%s guardado (exige %s)." % [off.name, ItemDB.CLASS_NAMES[off.needs].to_lower()], Color(0.85, 0.8, 0.65))
			equipment.offhand = ""
	_clamp_vitals(old_hp, old_mp)
	notify.emit("Equipado: %s" % it.name, ItemDB.rarity_color(id))
	inventory_changed.emit()
	stats_changed.emit()
	return true


func unequip(slot_name: String) -> void:
	if equipment.get(slot_name, "") == "":
		return
	var old_hp := max_hp()
	var old_mp := max_mp()
	add_item(equipment[slot_name], 1, true)
	equipment[slot_name] = ""
	_clamp_vitals(old_hp, old_mp)
	inventory_changed.emit()
	stats_changed.emit()


## Vida/mana acompanham o ganho de máximo e nunca passam do novo máximo.
func _clamp_vitals(old_hp: float, old_mp: float) -> void:
	if max_hp() > old_hp:
		hp += max_hp() - old_hp
	if max_mp() > old_mp:
		mp += max_mp() - old_mp
	hp = min(hp, max_hp())
	mp = min(mp, max_mp())


func buy(id: String) -> bool:
	var price: int = ItemDB.get_item(id).price
	if gold < price:
		notify.emit("Ouro insuficiente.", Color(1, 0.5, 0.5))
		return false
	gold -= price
	add_item(id)
	stats_changed.emit()
	return true


func sell(id: String) -> bool:
	if not remove_item(id, 1):
		return false
	var value := int(ceil(ItemDB.get_item(id).price * 0.5))
	add_gold(value)
	notify.emit("Vendido por %d ouro" % value, Color(1, 0.85, 0.3))
	return true


# ---------------------------------------------------------------- missões
func quest_state(id: String) -> String:
	return quests[id].state if quests.has(id) else "none"


func start_quest(id: String) -> void:
	quests[id] = {"state": "active", "progress": 0}
	notify.emit("Nova missão: %s" % ItemDB.QUESTS[id].name, Color(1.0, 0.8, 0.35))
	quests_changed.emit()


func complete_quest(id: String) -> void:
	var q: Dictionary = ItemDB.QUESTS[id]
	quests[id].state = "done"
	notify.emit("Missão concluída: %s" % q.name, Color(1.0, 0.8, 0.35))
	add_gold(q.reward_gold)
	notify.emit("+%d ouro" % q.reward_gold, Color(1, 0.85, 0.3))
	for item in q.reward_items:
		add_item(item, q.reward_items[item])
	add_xp(q.reward_xp)
	quests_changed.emit()


func on_enemy_killed(kind: String, xp_reward: int) -> void:
	kills += 1
	if float(food_mods.get("lifesteal", 0.0)) > 0.0 and hp > 0.0:
		hp = min(max_hp(), hp + float(food_mods.lifesteal))
	add_xp(xp_reward)
	for id in quests:
		var q: Dictionary = ItemDB.QUESTS[id]
		if quests[id].state == "active" and q.target == kind:
			quests[id].progress += 1
			if quests[id].progress >= q.count:
				quests[id].state = "ready"
				notify.emit("%s: volte para %s" % [q.name, q.giver], Color(1.0, 0.8, 0.35))
			else:
				notify.emit("%s %d/%d" % [q.name, quests[id].progress, q.count], Color(1.0, 0.9, 0.6))
	quests_changed.emit()


# ---------------------------------------------------------------- save / load
func has_save() -> bool:
	return FileAccess.file_exists(save_path)


func save_game(pos: Vector3, yaw: float) -> bool:
	if run_mods.active:
		notify.emit("Não é possível salvar durante o desafio.", Color(1, 0.6, 0.5))
		return false
	var data := {
		"version": 1, "level": level, "xp": xp, "gold": gold, "stat_points": stat_points,
		"attributes": attributes, "hp": hp, "mp": mp, "inventory": inventory, "equipment": equipment,
		"quests": quests, "flags": flags, "kills": kills, "farm": farm,
		"pos": [pos.x, pos.y, pos.z], "yaw": yaw,
		"time": Time.get_datetime_string_from_system(false, true),
	}
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		notify.emit("Falha ao salvar!", Color(1, 0.4, 0.4))
		return false
	f.store_string(JSON.stringify(data, "\t"))
	notify.emit("Jogo salvo.", Color(0.7, 1.0, 0.7))
	return true


func save_info() -> String:
	if not has_save():
		return ""
	var data = _read_save()
	if data == null:
		return ""
	return "Nível %d — %s" % [int(data.level), data.get("time", "")]


func _read_save():
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return null
	var data = JSON.parse_string(f.get_as_text())
	return data if data is Dictionary else null


func load_game() -> bool:
	if not load_character():
		return false
	get_tree().paused = false
	get_tree().change_scene_to_file(WORLD_SCENE)
	return true


## Lê o save para a memória sem trocar de cena (usado também ao entrar no multiplayer).
func load_character() -> bool:
	var data = _read_save()
	if data == null:
		notify.emit("Nenhum jogo salvo.", Color(1, 0.5, 0.5))
		return false
	reset_run_mods()
	level = int(data.level)
	xp = int(data.xp)
	gold = int(data.gold)
	stat_points = int(data.stat_points)
	attributes = {}
	for k in data.attributes:
		attributes[k] = int(data.attributes[k])
	inventory = []
	for slot in data.inventory:
		inventory.append({"id": str(slot.id), "qty": int(slot.qty)})
	equipment = empty_equipment()
	for s in equipment:
		var v := str(data.equipment.get(s, ""))
		equipment[s] = v if ItemDB.ITEMS.has(v) else ""
	quests = {}
	for id in data.quests:
		quests[id] = {"state": str(data.quests[id].state), "progress": int(data.quests[id].progress)}
	flags = data.flags
	kills = int(data.get("kills", 0))
	farm = _parse_farm(data.get("farm", null))
	clear_food(true)
	hp = float(data.hp)
	mp = float(data.mp)
	stamina = max_stamina()
	spawn_position = Vector3(data.pos[0], data.pos[1], data.pos[2])
	spawn_yaw = float(data.get("yaw", 0.0))
	return true


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


## Come uma comida (buff + cura) ou uma colheita crua (cura pequena).
func eat(id: String) -> bool:
	var it := ItemDB.get_item(id)
	if it.is_empty() or count_item(id) <= 0 or not is_edible(id):
		return false
	if eat_cooldown > 0.0:
		notify.emit("Ainda mastigando... (%.1fs)" % eat_cooldown, Color(1, 0.8, 0.55))
		return false
	var old_max := max_hp()
	remove_item(id, 1)
	if it.has("buff"):
		food_buffs[id] = float(it.buff.time)
		_recalc_food_mods()
		if max_hp() > old_max:
			hp += max_hp() - old_max
	if it.get("heal_full", false):
		hp = max_hp()
	hp = min(max_hp(), hp + float(it.get("heal_hp", 0)) + float(it.get("raw_hp", 0)))
	mp = min(max_mp(), mp + float(it.get("heal_mp", 0)) + float(it.get("raw_mp", 0)))
	eat_cooldown = EAT_COOLDOWN if it.type == "food" else 1.0
	if it.has("buff"):
		notify.emit("%s: %s (%ds)" % [it.name, it.buff.name, int(it.buff.time)], it.get("color", Color(1, 0.85, 0.4)))
	else:
		notify.emit("Comeu %s" % it.name, Color(0.85, 1.0, 0.7))
	food_eaten.emit(id)
	stats_changed.emit()
	return true


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


func cook(recipe: String, times := 1) -> int:
	var n: int = min(times, can_cook(recipe))
	if n <= 0:
		notify.emit("Faltam ingredientes.", Color(1, 0.6, 0.5))
		return 0
	var ing: Dictionary = ItemDB.RECIPES[recipe]
	for id in ing:
		remove_item(id, int(ing[id]) * n)
	add_item(recipe, n)
	if selected_food == "":
		selected_food = recipe
	return n


# ================================================================ horta
func default_farm() -> Dictionary:
	var plots: Array = []
	for i in FARM_PLOTS:
		plots.append(_empty_plot())
	return {"unlocked": FARM_START_PLOTS, "plots": plots}


func _empty_plot() -> Dictionary:
	return {"crop": "", "growth": 0.0, "watered": false, "fert": false}


func _parse_farm(data) -> Dictionary:
	var f := default_farm()
	if not (data is Dictionary):
		return f
	f.unlocked = clampi(int(data.get("unlocked", FARM_START_PLOTS)), FARM_START_PLOTS, FARM_PLOTS)
	var plots = data.get("plots", [])
	for i in min(FARM_PLOTS, plots.size()):
		var p = plots[i]
		var crop := str(p.get("crop", ""))
		if crop != "" and not ItemDB.CROPS.has(crop):
			crop = ""
		f.plots[i] = {"crop": crop, "growth": clampf(float(p.get("growth", 0.0)), 0.0, 1.0),
			"watered": bool(p.get("watered", false)), "fert": bool(p.get("fert", false))}
	return f


func plot_state(i: int) -> String:
	if i >= farm.unlocked:
		return "locked"
	var p: Dictionary = farm.plots[i]
	if p.crop == "":
		return "empty"
	return "ready" if p.growth >= 1.0 else "growing"


func unlock_cost() -> int:
	return 30 + 15 * (farm.unlocked - FARM_START_PLOTS)


func unlock_next_plot() -> bool:
	if farm.unlocked >= FARM_PLOTS:
		return false
	var cost := unlock_cost()
	if gold < cost:
		notify.emit("Ouro insuficiente (%d)." % cost, Color(1, 0.5, 0.5))
		return false
	gold -= cost
	farm.unlocked += 1
	notify.emit("Novo canteiro preparado!", Color(0.8, 1.0, 0.6))
	stats_changed.emit()
	farm_changed.emit()
	return true


## Planta no canteiro i. Se faltar semente e buy_missing, compra uma.
func plant(i: int, crop: String, buy_missing := false) -> bool:
	if plot_state(i) != "empty":
		return false
	var seed: String = ItemDB.CROPS[crop].seed
	if count_item(seed) <= 0:
		if not buy_missing:
			return false
		var price: int = ItemDB.get_item(seed).price
		if gold < price:
			notify.emit("Ouro insuficiente para a semente.", Color(1, 0.5, 0.5))
			return false
		gold -= price
		stats_changed.emit()
	else:
		remove_item(seed, 1)
	farm.plots[i] = {"crop": crop, "growth": 0.0, "watered": false, "fert": false}
	farm_changed.emit()
	return true


func water(i: int) -> bool:
	if plot_state(i) != "growing" or farm.plots[i].watered:
		return false
	farm.plots[i].watered = true
	farm_changed.emit()
	return true


## Adubo de gel de slime: +40% de crescimento na hora (uma vez por plantio).
func fertilize(i: int) -> bool:
	if plot_state(i) != "growing" or farm.plots[i].fert or count_item("slime_gel") <= 0:
		return false
	remove_item("slime_gel", 1)
	farm.plots[i].fert = true
	farm.plots[i].growth = min(1.0, farm.plots[i].growth + 0.4)
	farm_changed.emit()
	return true


## Avança o crescimento. Retorna true no quadro em que a planta fica pronta.
func grow_plot(i: int, delta: float) -> bool:
	if plot_state(i) != "growing":
		return false
	var p: Dictionary = farm.plots[i]
	var t: float = ItemDB.CROPS[p.crop].time
	p.growth = min(1.0, p.growth + delta / t * (2.0 if p.watered else 1.0))
	return p.growth >= 1.0


## Colhe o canteiro i: {"crop", "qty", "bonus", "seed"} ou {} se não estiver pronto.
func harvest(i: int) -> Dictionary:
	if plot_state(i) != "ready":
		return {}
	var p: Dictionary = farm.plots[i]
	var c: Dictionary = ItemDB.CROPS[p.crop]
	var qty := randi_range(c.yield[0], c.yield[1]) + (1 if p.watered else 0)
	var bonus := randf() < 0.12
	if bonus:
		qty *= 2
	var got_seed := randf() < 0.35
	add_item(p.crop, qty, true)
	if got_seed:
		add_item(c.seed, 1, true)
	var res := {"crop": p.crop, "qty": qty, "bonus": bonus, "seed": got_seed}
	farm.plots[i] = _empty_plot()
	var txt := "+%d %s" % [qty, c.name]
	if bonus:
		txt = "Colheita farta! " + txt
	if got_seed:
		txt += " (+1 semente)"
	notify.emit(txt, Color(0.85, 1.0, 0.55))
	farm_changed.emit()
	return res
