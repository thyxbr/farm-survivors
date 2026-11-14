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
## Ecos: moeda permanente, ganha ao fim das partidas. Passivas permanentes: id -> nível (>= 1).
var ecos := 0
var passives := {}


## Personagem novo: mesmos valores do antigo Game.new_game.
static func new_character(bt: BalanceTables) -> CharState:
	var s := CharState.new()
	s.gold = 25
	s.equipment = CharRules.empty_equipment()
	s.equipment["weapon"] = "azure_edge"
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
		"ecos": ecos, "passives": passives.duplicate(true),
	}


## Inverso de to_dict; aceita o que volta do JSON (todo número como float).
## Valida valores, não só formatos: o dicionário pode vir de save adulterado ou da rede.
## Campo de tipo errado volta ao padrão sem erro de execução; números fora da faixa são
## limitados (nível ≥ 1, ouro/xp/pontos/abates ≥ 0, atributos só str/int/vit/agi e ≥ 1).
## Com `bt`, também descarta ids desconhecidos (itens, equipamento no espaço errado, missões,
## culturas) e normaliza a horta pelas regras; sem `bt` só tipos e faixas são conferidos.
## Canteiro sem "t" (save antigo) volta a crescer a partir de agora.
static func from_dict(d, bt: BalanceTables = null) -> CharState:
	var s := CharState.new()
	if not (d is Dictionary):
		d = {}
	var items: Dictionary = bt.get_table("items") if bt != null else {}
	var quest_t: Dictionary = bt.get_table("quests") if bt != null else {}
	s.level = maxi(1, _int(d.get("level"), 1))
	s.xp = maxi(0, _int(d.get("xp"), 0))
	s.gold = maxi(0, _int(d.get("gold"), 0))
	s.stat_points = maxi(0, _int(d.get("stat_points"), 0))
	s.kills = maxi(0, _int(d.get("kills"), 0))
	var attrs = d.get("attributes")
	for k in s.attributes:
		if attrs is Dictionary:
			s.attributes[k] = maxi(1, _int(attrs.get(k), 5))
	var inv = d.get("inventory")
	if inv is Array:
		for slot in inv:
			if not (slot is Dictionary) or not (slot.get("id") is String):
				continue
			var id: String = slot.id
			var qty := _int(slot.get("qty"), 0)
			if id == "" or qty < 1 or (bt != null and not items.has(id)):
				continue
			if bt != null and not items[id].get("stack", false):
				qty = 1   # item não empilhável ocupa um espaço por unidade
			s.inventory.append({"id": id, "qty": qty})
	s.equipment = CharRules.empty_equipment()
	var eq = d.get("equipment")
	if eq is Dictionary:
		for k in s.equipment:
			var v = eq.get(k)
			if v is String and (bt == null or CharRules.slot_of(bt, v) == k):
				s.equipment[k] = v
	var qs = d.get("quests")
	if qs is Dictionary:
		for id in qs:
			var q = qs[id]
			if not (id is String) or not (q is Dictionary) or (bt != null and not quest_t.has(id)):
				continue
			var st = q.get("state")
			if not (st is String and st in ["active", "ready", "done"]):   # "none" = sem entrada
				continue
			s.quests[id] = {"state": st, "progress": maxi(0, _int(q.get("progress"), 0))}
	var fl = d.get("flags")
	s.flags = fl.duplicate(true) if fl is Dictionary else {}
	s.farm = _parse_farm(d.get("farm"), bt)
	s.hp = maxf(0.0, _float(d.get("hp"), 0.0))
	s.mp = maxf(0.0, _float(d.get("mp"), 0.0))
	var p = d.get("world_pos")
	if p is Array and p.size() == 3 and _num(p[0]) and _num(p[1]) and _num(p[2]):
		s.world_pos = Vector3(float(p[0]), float(p[1]), float(p[2]))
	elif p is Vector3 and p.is_finite():
		s.world_pos = p
	s.world_yaw = _float(d.get("world_yaw"), 0.0)
	s.ecos = maxi(0, _int(d.get("ecos"), 0))
	var ps = d.get("passives")
	if ps is Dictionary:
		var pt: Dictionary = bt.get_table("meta_passives").get("passives", {}) if bt != null else {}
		for id in ps:
			var lv := _int(ps[id], 0)
			if not (id is String) or lv < 1 or (bt != null and not pt.has(id)):
				continue
			if bt != null:
				lv = mini(lv, pt[id].get("cost", []).size())
				if lv < 1:
					continue
			s.passives[id] = lv
	return s


## Número finito (int ou float)?
static func _num(v) -> bool:
	return v is int or (v is float and is_finite(v))


static func _int(v, def: int) -> int:
	if v is int:
		return v
	if v is float and is_finite(v) and absf(v) < 9.0e18:
		return int(v)
	return def


static func _float(v, def: float) -> float:
	return float(v) if _num(v) else def


static func _parse_farm(data, bt: BalanceTables) -> Dictionary:
	var out := {"unlocked": 0, "plots": []}
	if data is Dictionary:
		out.unlocked = maxi(0, _int(data.get("unlocked"), 0))
		var plots = data.get("plots")
		if plots is Array:
			var now := Time.get_unix_time_from_system()
			for p in plots:
				out.plots.append(CharRules.sanitize_plot(p, now))
	if bt != null:
		var tmp := CharState.new()
		tmp.farm = out
		CharRules._ensure_farm(tmp, bt)
		out = tmp.farm
	return out
