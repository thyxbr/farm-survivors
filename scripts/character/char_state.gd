class_name CharState
extends RefCounted
## Estado persistente de um personagem (o que o servidor guarda e o cliente espelha).
## Classe pura: sem autoload. As regras que mudam este estado moram em CharRules.
## hp/mp são do combate (cliente); aqui ficam só para salvar e restaurar.

var level := 1
var xp := 0
var gold := 0
var stat_points := 0
var attributes := {"str": 5, "int": 5, "vit": 5, "agi": 5}
var inventory: Array = []   # [{"id": String, "qty": int}]
var equipment := {}         # espaço -> id ("" = vazio), ver CharRules.SLOTS
var quests := {}            # id -> {"state": "active"|"ready"|"done", "progress": int}
var flags := {}
## {"unlocked": int, "plots": [{"crop", "growth" 0..1, "t" unix s, "watered", "fert"}]}
var farm := {}
var hp := 0.0
var mp := 0.0
## null = ponto de nascimento padrão do mundo.
var world_pos: Variant = null
var world_yaw := 0.0
var kills := 0


## Personagem novo: mesmos valores do antigo Game.new_game.
static func new_character(bt: BalanceTables) -> CharState:
	var s := CharState.new()
	s.gold = 25
	s.equipment = CharRules.empty_equipment()
	s.equipment["weapon"] = "wooden_sword"
	s.farm = CharRules.default_farm(bt)
	for e in [["health_potion", 3], ["mana_potion", 1], ["seed_carrot", 4], ["seed_wheat", 4], ["bread", 1],
			# kit inicial para experimentar as três classes de arma
			["apprentice_staff", 1], ["short_bow", 1], ["leather_cap", 1]]:
		CharRules.add_item(s, bt, e[0], e[1])
	s.hp = CharRules.base_max_hp(s, bt)
	s.mp = CharRules.base_max_mp(s, bt)
	return s


## Dicionário pronto para JSON (posição vira [x, y, z]).
func to_dict() -> Dictionary:
	return {
		"level": level, "xp": xp, "gold": gold, "stat_points": stat_points,
		"attributes": attributes.duplicate(true), "inventory": inventory.duplicate(true),
		"equipment": equipment.duplicate(true), "quests": quests.duplicate(true), "flags": flags.duplicate(true),
		"farm": farm.duplicate(true), "hp": hp, "mp": mp,
		"world_pos": [world_pos.x, world_pos.y, world_pos.z] if world_pos is Vector3 else null,
		"world_yaw": world_yaw, "kills": kills,
	}


## Inverso de to_dict; aceita o que volta do JSON (todo número como float).
## Canteiro sem "t" (save antigo) volta a crescer a partir de agora.
static func from_dict(d: Dictionary) -> CharState:
	var s := CharState.new()
	s.level = int(d.get("level", 1))
	s.xp = int(d.get("xp", 0))
	s.gold = int(d.get("gold", 0))
	s.stat_points = int(d.get("stat_points", 0))
	var attrs = d.get("attributes", {})
	if attrs is Dictionary:
		for k in attrs:
			s.attributes[str(k)] = int(attrs[k])
	var inv = d.get("inventory", [])
	if inv is Array:
		for slot in inv:
			if slot is Dictionary and int(slot.get("qty", 0)) > 0:
				s.inventory.append({"id": str(slot.get("id", "")), "qty": int(slot.qty)})
	s.equipment = CharRules.empty_equipment()
	var eq = d.get("equipment", {})
	if eq is Dictionary:
		for k in s.equipment:
			s.equipment[k] = str(eq.get(k, ""))
	var qs = d.get("quests", {})
	if qs is Dictionary:
		for id in qs:
			var q = qs[id]
			if q is Dictionary:
				s.quests[str(id)] = {"state": str(q.get("state", "active")), "progress": int(q.get("progress", 0))}
	var fl = d.get("flags", {})
	s.flags = fl.duplicate(true) if fl is Dictionary else {}
	s.farm = _parse_farm(d.get("farm", null))
	s.hp = float(d.get("hp", 0.0))
	s.mp = float(d.get("mp", 0.0))
	var p = d.get("world_pos", null)
	if p is Array and p.size() == 3:
		s.world_pos = Vector3(float(p[0]), float(p[1]), float(p[2]))
	elif p is Vector3:
		s.world_pos = p
	s.world_yaw = float(d.get("world_yaw", 0.0))
	s.kills = int(d.get("kills", 0))
	return s


static func _parse_farm(data) -> Dictionary:
	var out := {"unlocked": 0, "plots": []}
	if not (data is Dictionary):
		return out
	out.unlocked = int(data.get("unlocked", 0))
	var now := Time.get_unix_time_from_system()
	var plots = data.get("plots", [])
	if plots is Array:
		for p in plots:
			if not (p is Dictionary):
				p = {}
			out.plots.append({"crop": str(p.get("crop", "")), "growth": clampf(float(p.get("growth", 0.0)), 0.0, 1.0),
				"t": float(p.get("t", now)), "watered": bool(p.get("watered", false)), "fert": bool(p.get("fert", false))})
	return out
