extends RefCounted
## Tabelas de melhorias do Desafio da Horda: armas automáticas, passivas (cartas de nível)
## e bênçãos (fim de rodada). "add" soma valores em Game.run_mods.

const MAX_LEVEL := 5

const WEAPONS := {
	"fogo": {"name": "Orbe de Fogo", "color": Color(1.0, 0.5, 0.15), "desc": [
		"Dispara bolas de fogo no inimigo mais próximo.",
		"+30% de dano e recarga menor.",
		"+1 bola de fogo por disparo.",
		"+30% de dano e recarga menor.",
		"+1 bola de fogo e dano maior.",
	]},
	"laminas": {"name": "Lâminas Orbitais", "color": Color(0.6, 0.8, 1.0), "desc": [
		"Duas lâminas giram ao seu redor cortando quem encostar.",
		"+1 lâmina.",
		"+25% de dano e raio maior.",
		"+1 lâmina e giro mais rápido.",
		"+1 lâmina e +25% de dano.",
	]},
	"raio": {"name": "Relâmpago", "color": Color(0.55, 0.85, 1.0), "desc": [
		"Raios caem sobre inimigos próximos.",
		"+1 alvo por descarga.",
		"+30% de dano e recarga menor.",
		"+1 alvo por descarga.",
		"+2 alvos e +30% de dano.",
	]},
	"aura": {"name": "Aura Gélida", "color": Color(0.5, 0.9, 1.0), "desc": [
		"Um círculo de gelo fere e congela quem chega perto.",
		"Raio maior e +30% de dano.",
		"Raio maior e +30% de dano.",
		"Raio maior e lentidão mais forte.",
		"Raio maior e +40% de dano.",
	]},
}

const PASSIVES := {
	"poder": {"name": "Poder", "color": Color(1, 0.4, 0.3), "desc": "+10% de dano (armas, espada e magias).", "add": {"damage": 0.10}},
	"celeridade": {"name": "Celeridade", "color": Color(1, 0.85, 0.3), "desc": "−8% de recarga das armas automáticas.", "add": {"cooldown": -0.08}},
	"vigor": {"name": "Vigor", "color": Color(0.9, 0.25, 0.3), "desc": "+15% de vida máxima.", "add": {"max_hp": 0.15}},
	"botas": {"name": "Botas Velozes", "color": Color(0.5, 1, 0.5), "desc": "+8% de velocidade de movimento.", "add": {"speed": 0.08}},
	"ima": {"name": "Ímã", "color": Color(0.4, 0.7, 1), "desc": "+35% de raio de coleta de gemas.", "add": {"magnet": 0.35}},
	"alcance": {"name": "Alcance", "color": Color(0.8, 0.6, 1), "desc": "+12% de área das armas.", "add": {"area": 0.12}},
	"armadura": {"name": "Armadura", "color": Color(0.7, 0.7, 0.75), "desc": "+3 de defesa.", "add": {"defense": 3.0}},
	"regeneracao": {"name": "Regeneração", "color": Color(0.4, 1, 0.5), "desc": "+0,6 de vida por segundo.", "add": {"regen": 0.6}},
}

const BLESSINGS := {
	"furia": {"name": "Bênção da Fúria", "color": Color(1, 0.35, 0.2), "desc": "+20% de dano.", "add": {"damage": 0.2}},
	"vida": {"name": "Bênção da Vida", "color": Color(1, 0.3, 0.4), "desc": "+20 de vida máxima e cura total.", "add": {"max_hp_flat": 20.0}, "heal": true},
	"sabedoria": {"name": "Bênção da Sabedoria", "color": Color(0.4, 0.8, 1), "desc": "+25% de XP das gemas.", "add": {"xp": 0.25}},
	"sorte": {"name": "Bênção da Sorte", "color": Color(0.5, 1, 0.4), "desc": "+8% de chance de crítico.", "add": {"crit": 0.08}},
	"sangue": {"name": "Sede de Sangue", "color": Color(0.8, 0.1, 0.15), "desc": "Cada abate cura 1 de vida.", "add": {"lifesteal": 1.0}},
	"vento": {"name": "Bênção do Vento", "color": Color(0.7, 1, 0.9), "desc": "+10% de velocidade e −10% de recarga.", "add": {"speed": 0.1, "cooldown": -0.1}},
	"ouro": {"name": "Bênção do Ouro", "color": Color(1, 0.85, 0.3), "desc": "+50% de ouro das moedas.", "add": {"gold": 0.5}},
}


## Combos em grupo: quando um jogador tem a arma "a" e um colega PERTO tem a "b" (ou o contrário),
## os ataques dessas armas disparam o efeito do combo (recarga própria). Tudo é calculado por quem
## dispara; os outros veem o efeito pelo evento "combo".
##   shape "area": dano em volta do ponto · "chain": salta entre inimigos · "strikes": raios em volta.
const COMBO_RANGE := 14.0
const COMBO_COOLDOWN := 3.0
const COMBOS := {
	"choque": {"name": "Choque Térmico", "a": "fogo", "b": "aura", "color": Color(1.0, 0.75, 0.6),
		"shape": "area", "radius": 3.2, "dmg": 30.0, "slow": 1.0,
		"desc": "Fogo em inimigo congelado: explosão de vapor em área."},
	"plasma": {"name": "Plasma", "a": "fogo", "b": "raio", "color": Color(1.0, 0.55, 0.9),
		"shape": "chain", "n": 4, "radius": 6.0, "dmg": 26.0, "slow": 0.0,
		"desc": "Descarga de plasma salta entre 4 inimigos."},
	"brasas": {"name": "Ciclone de Brasas", "a": "fogo", "b": "laminas", "color": Color(1.0, 0.6, 0.2),
		"shape": "area", "radius": 4.0, "dmg": 24.0, "slow": 0.0,
		"desc": "Lâminas em chamas: anel de fogo em volta do alvo."},
	"tempestade": {"name": "Tempestade Gélida", "a": "raio", "b": "aura", "color": Color(0.6, 0.85, 1.0),
		"shape": "strikes", "n": 3, "radius": 7.0, "dmg": 24.0, "slow": 1.5,
		"desc": "3 raios de gelo caem perto do alvo e deixam lento."},
	"eletro": {"name": "Lâminas Elétricas", "a": "raio", "b": "laminas", "color": Color(0.85, 0.95, 0.4),
		"shape": "chain", "n": 3, "radius": 6.0, "dmg": 22.0, "slow": 0.0,
		"desc": "Cada corte eletrifica e salta para mais 3 inimigos."},
	"nevasca": {"name": "Nevasca Cortante", "a": "laminas", "b": "aura", "color": Color(0.75, 0.95, 1.0),
		"shape": "area", "radius": 3.5, "dmg": 20.0, "slow": 1.5,
		"desc": "Estilhaços de gelo em área que deixam lento."},
}

## Maldições de rodada (a partir da rodada 6, nas rodadas sem chefe): deixam cada rodada diferente.
const AFFIX_FROM := 6
const AFFIXES := {
	"frenesi": {"name": "Frenesi", "desc": "inimigos 20% mais rápidos", "speed": 1.2},
	"couraca": {"name": "Couraça", "desc": "inimigos com +35% de vida", "hp": 1.35},
	"enxame": {"name": "Enxame", "desc": "+50% de inimigos, com menos vida", "rate": 1.5, "hp": 0.75},
	"furia": {"name": "Fúria", "desc": "inimigos causam +25% de dano", "dmg": 1.25},
	"elite": {"name": "Caçada", "desc": "elites aparecem 3x mais", "elite": 3.0},
}


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
