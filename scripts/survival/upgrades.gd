extends RefCounted
## Tabelas de melhorias do Desafio da Horda: armas automáticas, passivas (cartas de nível)
## e bênçãos (fim de rodada). "add" soma valores em Game.run_mods. As tabelas vêm de
## data/balance/horde.json (autoload Balance).

const MAX_LEVEL := 5

static var WEAPONS: Dictionary = {}

static var PASSIVES: Dictionary = {}

static var BLESSINGS: Dictionary = {}


## Combos em grupo: quando um jogador tem a arma "a" e um colega PERTO tem a "b" (ou o contrário),
## os ataques dessas armas disparam o efeito do combo (recarga própria). Tudo é calculado por quem
## dispara; os outros veem o efeito pelo evento "combo".
##   shape "area": dano em volta do ponto · "chain": salta entre inimigos · "strikes": raios em volta.
const COMBO_RANGE := 14.0
const COMBO_COOLDOWN := 3.0
static var COMBOS: Dictionary = {}

## Combo formado pelas armas x e y (ordem livre); "" se não houver.
static func combo_for(x: String, y: String) -> String:
	if x == y:
		return ""
	for id in COMBOS:
		var c: Dictionary = COMBOS[id]
		if (c.a == x and c.b == y) or (c.a == y and c.b == x):
			return id
	return ""


## Cartas de subida de nível: armas novas/melhorias e passivas que ainda não chegaram ao máximo.
## team_weapons: armas dos colegas (as que formariam um combo novo aparecem mais).
static func roll_level_choices(weapon_levels: Dictionary, passive_levels: Dictionary, n := 3, team_weapons := {}) -> Array:
	var pool: Array = []
	for id in WEAPONS:
		var lv: int = weapon_levels.get(id, 0)
		if lv < MAX_LEVEL:
			# armas que o jogador já tem aparecem com mais frequência
			var w := 1.6 if lv > 0 else 1.0
			if lv == 0:
				for other in team_weapons:
					if combo_for(id, other) != "":
						w = 1.9
			pool.append({"type": "weapon", "id": id, "w": w})
	for id in PASSIVES:
		if passive_levels.get(id, 0) < MAX_LEVEL:
			pool.append({"type": "passive", "id": id, "w": 1.0})
	var out: Array = []
	while out.size() < n and not pool.is_empty():
		var total := 0.0
		for p in pool:
			total += p.w
		var r := randf() * total
		for i in pool.size():
			r -= pool[i].w
			if r <= 0.0 or i == pool.size() - 1:
				out.append({"type": pool[i].type, "id": pool[i].id})
				pool.remove_at(i)
				break
	if out.is_empty():
		out.append({"type": "heal", "id": "heal"})
	return out


static func roll_blessings(n := 3) -> Array:
	var ids := BLESSINGS.keys()
	ids.shuffle()
	var out: Array = []
	for i in min(n, ids.size()):
		out.append({"type": "blessing", "id": ids[i]})
	return out


## Texto exibido na carta: {"name", "level", "desc", "color"}.
static func describe(choice: Dictionary, weapon_levels: Dictionary, passive_levels: Dictionary, blessing_counts: Dictionary) -> Dictionary:
	match choice.type:
		"weapon":
			var w: Dictionary = WEAPONS[choice.id]
			var lv: int = weapon_levels.get(choice.id, 0)
			return {"name": w.name, "level": "Nova arma!" if lv == 0 else "Nv %d → %d" % [lv, lv + 1],
				"desc": w.desc[lv], "color": w.color}
		"passive":
			var p: Dictionary = PASSIVES[choice.id]
			var lv: int = passive_levels.get(choice.id, 0)
			return {"name": p.name, "level": "Novo!" if lv == 0 else "Nv %d → %d" % [lv, lv + 1],
				"desc": p.desc, "color": p.color}
		"blessing":
			var b: Dictionary = BLESSINGS[choice.id]
			var n: int = blessing_counts.get(choice.id, 0)
			return {"name": b.name, "level": "Bênção" if n == 0 else "Bênção ×%d" % (n + 1),
				"desc": b.desc, "color": b.color}
	return {"name": "Poção Restauradora", "level": "", "desc": "Recupera 40% da vida.", "color": Color(1, 0.4, 0.4)}
