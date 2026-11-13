extends Node
## Estado global do jogo: atributos, inventário, missões, configurações e save/load.

signal stats_changed
signal inventory_changed
signal quests_changed
signal notify(text: String, color: Color)
signal leveled_up(new_level: int)

var save_path := "user://savegame.json"
const SETTINGS_PATH := "user://settings.cfg"
const WORLD_SCENE := "res://scenes/world.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"

var settings := {"mouse_sensitivity": 0.25, "master_volume": 0.8, "fullscreen": false, "invert_y": false}

var level := 1
var xp := 0
var gold := 0
var stat_points := 0
var attributes := {"str": 5, "int": 5, "vit": 5, "agi": 5}
var hp := 100.0
var mp := 50.0
var stamina := 100.0
var inventory: Array = []   # [{"id": String, "qty": int}]
var equipment := {"weapon": "", "armor": ""}
var quests := {}            # id -> {"state": "active"|"ready"|"done", "progress": int}
var flags := {}
var kills := 0
var spawn_position = null   # Vector3 a aplicar ao carregar o mundo
var spawn_yaw := 0.0
## Bônus temporários do Desafio da Horda (zerados ao fim da partida).
var run_mods := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	load_settings()
	reset_run_mods()
	new_game()
	_debug_screenshot()
	if "--dbg" in OS.get_cmdline_user_args():
		get_tree().root.add_child.call_deferred(load("res://tests/debug_dialogue.gd").new())
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
	equipment = {"weapon": "wooden_sword", "armor": ""}
	quests = {}
	flags = {}
	kills = 0
	spawn_position = null
	spawn_yaw = 0.0
	add_item("health_potion", 3, true)
	add_item("mana_potion", 1, true)
	hp = max_hp()
	mp = max_mp()
	stamina = max_stamina()


func start_new_game() -> void:
	new_game()
	get_tree().paused = false
	get_tree().change_scene_to_file(WORLD_SCENE)


func go_to_menu() -> void:
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
	return run_mods.damage


# ---------------------------------------------------------------- atributos derivados
func weapon_damage() -> int:
	return ItemDB.get_item(equipment.weapon).get("damage", 2) if equipment.weapon != "" else 2


func armor_defense() -> int:
	return ItemDB.get_item(equipment.armor).get("defense", 0) if equipment.armor != "" else 0


func max_hp() -> float:
	return (60.0 + attributes.vit * 10.0 + (level - 1) * 8.0) * run_mods.max_hp + run_mods.max_hp_flat


func max_mp() -> float:
	return 25.0 + attributes.int * 6.0 + (level - 1) * 3.0


func max_stamina() -> float:
	return 70.0 + attributes.agi * 5.0


func melee_damage() -> float:
	return (weapon_damage() + attributes.str * 1.6) * run_mods.damage


func spell_power() -> float:
	return attributes.int * 1.0


func defense() -> float:
	return armor_defense() + attributes.vit * 0.4 + run_mods.defense


func speed_multiplier() -> float:
	return (1.0 + (attributes.agi - 5) * 0.015) * run_mods.speed


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
		var txt := "+ %s" % ItemDB.get_item(id).name
		if qty > 1:
			txt += " x%d" % qty
		notify.emit(txt, Color(0.85, 1.0, 0.7))
	inventory_changed.emit()


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
		"weapon", "armor":
			equip(id)
			return true
	return false


func equip(id: String) -> void:
	var slot_name: String = ItemDB.get_item(id).type
	if not remove_item(id, 1):
		return
	if equipment[slot_name] != "":
		add_item(equipment[slot_name], 1, true)
	equipment[slot_name] = id
	notify.emit("Equipado: %s" % ItemDB.get_item(id).name, Color(0.9, 0.9, 0.6))
	inventory_changed.emit()
	stats_changed.emit()


func unequip(slot_name: String) -> void:
	if equipment[slot_name] == "":
		return
	add_item(equipment[slot_name], 1, true)
	equipment[slot_name] = ""
	inventory_changed.emit()
	stats_changed.emit()


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
		"quests": quests, "flags": flags, "kills": kills,
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
	equipment = {"weapon": str(data.equipment.weapon), "armor": str(data.equipment.armor)}
	quests = {}
	for id in data.quests:
		quests[id] = {"state": str(data.quests[id].state), "progress": int(data.quests[id].progress)}
	flags = data.flags
	kills = int(data.get("kills", 0))
	hp = float(data.hp)
	mp = float(data.mp)
	stamina = max_stamina()
	spawn_position = Vector3(data.pos[0], data.pos[1], data.pos[2])
	spawn_yaw = float(data.get("yaw", 0.0))
	get_tree().paused = false
	get_tree().change_scene_to_file(WORLD_SCENE)
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
