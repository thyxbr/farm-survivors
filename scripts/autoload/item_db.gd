extends Node
## Banco de dados de itens, magias e missões (dados puros).

const ITEMS := {
	"wooden_sword": {"name": "Espada de Madeira", "type": "weapon", "damage": 6, "price": 10,
		"color": Color(0.55, 0.38, 0.2), "desc": "Uma espada de treino. Melhor que nada."},
	"iron_sword": {"name": "Espada de Ferro", "type": "weapon", "damage": 12, "price": 60,
		"color": Color(0.8, 0.82, 0.86), "desc": "Lâmina confiável forjada na vila."},
	"knight_blade": {"name": "Lâmina do Cavaleiro", "type": "weapon", "damage": 20, "price": 150,
		"color": Color(0.6, 0.8, 1.0), "desc": "Aço temperado com runas azuladas."},
	"goblin_cleaver": {"name": "Cutelo do Rei Goblin", "type": "weapon", "damage": 30, "price": 220,
		"color": Color(0.9, 0.35, 0.15), "desc": "Pesado, brutal e ainda quente de batalha."},
	"leather_armor": {"name": "Armadura de Couro", "type": "armor", "defense": 3, "price": 40,
		"desc": "Couro curtido. Leve e flexível."},
	"chain_mail": {"name": "Cota de Malha", "type": "armor", "defense": 7, "price": 120,
		"desc": "Anéis de aço entrelaçados."},
	"royal_plate": {"name": "Placas Reais", "type": "armor", "defense": 12, "price": 300,
		"desc": "Armadura de placas digna de um herói."},
	"health_potion": {"name": "Poção de Vida", "type": "consumable", "heal_hp": 60, "price": 15,
		"stack": true, "desc": "Restaura 60 de vida."},
	"mana_potion": {"name": "Poção de Mana", "type": "consumable", "heal_mp": 40, "price": 15,
		"stack": true, "desc": "Restaura 40 de mana."},
	"slime_gel": {"name": "Gel de Slime", "type": "material", "price": 4, "stack": true,
		"desc": "Gosmento. Os mercadores pagam por isso."},
	"goblin_ear": {"name": "Orelha de Goblin", "type": "material", "price": 8, "stack": true,
		"desc": "Prova de caça. Eca."},
	"goblin_crown": {"name": "Coroa do Rei Goblin", "type": "material", "price": 150, "stack": true,
		"desc": "Ouro sujo, mas ainda é ouro."},

	# ---------------------------------------------------------------- horta: sementes
	"seed_carrot": {"name": "Semente de Cenoura", "type": "seed", "crop": "carrot", "price": 4, "stack": true,
		"desc": "Cresce rápido. Base de ensopados e saladas."},
	"seed_wheat": {"name": "Semente de Trigo", "type": "seed", "crop": "wheat", "price": 4, "stack": true,
		"desc": "Rende bastante. Vira pão e massa de torta."},
	"seed_tomato": {"name": "Semente de Tomate", "type": "seed", "crop": "tomato", "price": 6, "stack": true,
		"desc": "Suculento. Vai bem em sopas."},
	"seed_pepper": {"name": "Semente de Pimenta-de-Fogo", "type": "seed", "crop": "pepper", "price": 10, "stack": true,
		"desc": "Dizem que um goblin chorou só de cheirar."},
	"seed_mint": {"name": "Semente de Menta Gélida", "type": "seed", "crop": "mint", "price": 10, "stack": true,
		"desc": "Folhas que brilham frias ao luar."},
	"seed_pumpkin": {"name": "Semente de Abóbora", "type": "seed", "crop": "pumpkin", "price": 14, "stack": true,
		"desc": "Demora, mas cresce enorme."},

	# ---------------------------------------------------------------- horta: colheitas (comíveis cruas)
	"carrot": {"name": "Cenoura", "type": "crop", "price": 6, "stack": true, "raw_hp": 12,
		"desc": "Crocante. Crua cura 12 de vida."},
	"wheat": {"name": "Trigo", "type": "crop", "price": 5, "stack": true,
		"desc": "Não dá para comer assim. Leve ao caldeirão."},
	"tomato": {"name": "Tomate", "type": "crop", "price": 8, "stack": true, "raw_hp": 15,
		"desc": "Cru cura 15 de vida."},
	"pepper": {"name": "Pimenta-de-Fogo", "type": "crop", "price": 12, "stack": true, "raw_hp": 5,
		"desc": "Crua cura 5 de vida... e queima a língua."},
	"mint": {"name": "Menta Gélida", "type": "crop", "price": 12, "stack": true, "raw_mp": 15,
		"desc": "Mastigar restaura 15 de mana."},
	"pumpkin": {"name": "Abóbora", "type": "crop", "price": 24, "stack": true, "raw_hp": 30,
		"desc": "Enorme. Crua cura 30 de vida."},

	# ---------------------------------------------------------------- horta: comidas (caldeirão)
	"bread": {"name": "Pão Rústico", "type": "food", "price": 18, "stack": true, "heal_hp": 35,
		"buff": {"name": "Barriga Cheia", "time": 60.0, "add": {"regen": 1.5}, "desc": "+1,5 de vida por segundo"},
		"color": Color(0.9, 0.7, 0.4), "desc": "Simples e honesto."},
	"carrot_stew": {"name": "Ensopado de Cenoura", "type": "food", "price": 30, "stack": true, "heal_hp": 60,
		"buff": {"name": "Vigor da Horta", "time": 90.0, "add": {"max_hp_flat": 30.0, "defense": 2.0}, "desc": "+30 de vida máxima e +2 de defesa"},
		"color": Color(1.0, 0.55, 0.2), "desc": "Receita da avó do Bram."},
	"spicy_soup": {"name": "Sopa Picante", "type": "food", "price": 40, "stack": true, "heal_hp": 30,
		"buff": {"name": "Fúria Picante", "time": 45.0, "add": {"damage": 0.3}, "desc": "+30% de dano"},
		"color": Color(1.0, 0.3, 0.15), "desc": "Esquenta o sangue."},
	"dragon_chili": {"name": "Chili do Dragão", "type": "food", "price": 45, "stack": true, "heal_hp": 20,
		"special": "fire_nova",
		"buff": {"name": "Bafo de Dragão", "time": 30.0, "add": {"damage": 0.2, "crit": 0.1}, "desc": "+20% de dano e +10% de crítico"},
		"color": Color(1.0, 0.4, 0.05), "desc": "Ao comer: explosão de fogo ao seu redor!"},
	"mint_tea": {"name": "Chá de Menta Gélida", "type": "food", "price": 30, "stack": true, "heal_mp": 40,
		"special": "frost_nova",
		"buff": {"name": "Mente Fresca", "time": 60.0, "add": {"cooldown": -0.2, "speed": 0.1}, "desc": "−20% de recarga e +10% de velocidade"},
		"color": Color(0.5, 0.95, 1.0), "desc": "Ao comer: congela os inimigos próximos."},
	"garden_salad": {"name": "Salada da Horta", "type": "food", "price": 36, "stack": true, "heal_hp": 40,
		"buff": {"name": "Olhos de Águia", "time": 90.0, "add": {"xp": 0.3, "magnet": 0.6}, "desc": "+30% de XP das gemas e +60% de raio de coleta"},
		"color": Color(0.5, 1.0, 0.45), "desc": "Fresquinha. Ótima para subir de nível na Horda."},
	"pumpkin_pie": {"name": "Torta de Abóbora", "type": "food", "price": 55, "stack": true, "heal_hp": 120,
		"buff": {"name": "Casca Dura", "time": 90.0, "add": {"defense": 5.0, "lifesteal": 2.0}, "desc": "+5 de defesa e cada abate cura 2"},
		"color": Color(1.0, 0.6, 0.15), "desc": "Pesada, quentinha e reconfortante."},
	"valdoria_feast": {"name": "Banquete de Valdoria", "type": "food", "price": 120, "stack": true, "heal_full": true,
		"buff": {"name": "Banquete do Herói", "time": 120.0,
			"add": {"damage": 0.25, "max_hp_flat": 40.0, "speed": 0.12, "gold": 0.4, "cooldown": -0.15},
			"desc": "+25% de dano, +40 de vida máx., +12% de velocidade, −15% de recarga, +40% de ouro"},
		"color": Color(1.0, 0.85, 0.3), "desc": "Cura total. Um prato digno de lenda."},
}

## Culturas da horta. "time" = segundos para crescer sem regar (regada cresce 2x mais rápido).
const CROPS := {
	"carrot": {"name": "Cenoura", "seed": "seed_carrot", "time": 40.0, "yield": [2, 3], "color": Color(1.0, 0.5, 0.1)},
	"wheat": {"name": "Trigo", "seed": "seed_wheat", "time": 50.0, "yield": [3, 4], "color": Color(0.95, 0.8, 0.3)},
	"tomato": {"name": "Tomate", "seed": "seed_tomato", "time": 65.0, "yield": [2, 4], "color": Color(0.9, 0.12, 0.08)},
	"pepper": {"name": "Pimenta-de-Fogo", "seed": "seed_pepper", "time": 80.0, "yield": [2, 3], "color": Color(1.0, 0.22, 0.04)},
	"mint": {"name": "Menta Gélida", "seed": "seed_mint", "time": 80.0, "yield": [2, 3], "color": Color(0.45, 0.95, 1.0)},
	"pumpkin": {"name": "Abóbora", "seed": "seed_pumpkin", "time": 110.0, "yield": [1, 2], "color": Color(1.0, 0.52, 0.08)},
}
const CROP_ORDER := ["carrot", "wheat", "tomato", "pepper", "mint", "pumpkin"]

## Receitas do caldeirão: comida -> ingredientes.
const RECIPES := {
	"bread": {"wheat": 2},
	"carrot_stew": {"carrot": 2, "tomato": 1},
	"spicy_soup": {"tomato": 2, "pepper": 1},
	"dragon_chili": {"pepper": 2, "carrot": 1},
	"mint_tea": {"mint": 2},
	"garden_salad": {"carrot": 1, "tomato": 1, "mint": 1},
	"pumpkin_pie": {"pumpkin": 1, "wheat": 2},
	"valdoria_feast": {"pumpkin": 1, "pepper": 1, "mint": 1, "wheat": 1, "tomato": 1},
}
const RECIPE_ORDER := ["bread", "carrot_stew", "spicy_soup", "dragon_chili", "mint_tea", "garden_salad", "pumpkin_pie", "valdoria_feast"]

const SPELLS := {
	"fireball": {"name": "Bola de Fogo", "key": "1", "cost": 12, "level": 1, "cooldown": 0.9,
		"desc": "Projétil flamejante. Dano = 18 + INT x 2.5"},
	"heal": {"name": "Cura", "key": "2", "cost": 20, "level": 2, "cooldown": 4.0,
		"desc": "Restaura 30 + INT x 4 de vida."},
	"frost_nova": {"name": "Nova Gélida", "key": "3", "cost": 28, "level": 4, "cooldown": 7.0,
		"desc": "Explosão de gelo ao redor: dano e lentidão."},
}

const QUESTS := {
	"slimes": {
		"name": "Praga Gosmenta",
		"giver": "Ancião Bram",
		"desc": "Os slimes estão devorando as plantações ao norte da vila. Derrote 5 deles.",
		"target": "slime", "count": 5,
		"reward_xp": 120, "reward_gold": 50, "reward_items": {"health_potion": 3},
	},
	"goblins": {
		"name": "Batedores Goblins",
		"giver": "Ancião Bram",
		"desc": "Goblins acamparam na floresta a leste. Derrote 4 batedores.",
		"target": "goblin", "count": 4,
		"reward_xp": 250, "reward_gold": 80, "reward_items": {"chain_mail": 1},
	},
	"goblin_king": {
		"name": "O Rei das Ruínas",
		"giver": "Ancião Bram",
		"desc": "O Rei Goblin comanda tudo das ruínas antigas ao norte. Acabe com ele.",
		"target": "goblin_king", "count": 1,
		"reward_xp": 600, "reward_gold": 300, "reward_items": {"royal_plate": 1},
	},
}

const SHOP_STOCK := ["health_potion", "mana_potion", "iron_sword", "knight_blade", "leather_armor", "chain_mail"]


func get_item(id: String) -> Dictionary:
	return ITEMS.get(id, {})


func is_stackable(id: String) -> bool:
	return get_item(id).get("stack", false)


func item_summary(id: String) -> String:
	var it := get_item(id)
	if it.is_empty():
		return ""
	var lines: Array[String] = [it.name]
	match it.type:
		"weapon":
			lines.append("Arma — Dano %d" % it.damage)
		"armor":
			lines.append("Armadura — Defesa %d" % it.defense)
		"consumable":
			lines.append("Consumível")
		"material":
			lines.append("Material")
		"seed":
			var c: Dictionary = CROPS[it.crop]
			lines.append("Semente — %ds para crescer (regada: %ds) · rende %d–%d" % [
				int(c.time), int(c.time / 2.0), c.yield[0], c.yield[1]])
		"crop":
			lines.append("Colheita — ingrediente do caldeirão")
			var uses: Array[String] = []
			for r in RECIPE_ORDER:
				if RECIPES[r].has(id):
					uses.append(ITEMS[r].name)
			if not uses.is_empty():
				lines.append("Receitas: " + ", ".join(uses))
		"food":
			lines.append("Comida [Q] — " + food_effect_text(id))
	lines.append(it.desc)
	lines.append("Valor: %d ouro" % it.price)
	return "\n".join(lines)


## "Cura 60 · Vigor da Horta (90s): +30 de vida máxima..."
func food_effect_text(id: String) -> String:
	var it := get_item(id)
	var parts: Array[String] = []
	if it.get("heal_full", false):
		parts.append("Cura total")
	elif it.has("heal_hp"):
		parts.append("Cura %d" % it.heal_hp)
	if it.has("heal_mp"):
		parts.append("+%d mana" % it.heal_mp)
	var txt := " · ".join(parts)
	if it.has("buff"):
		var b: Dictionary = it.buff
		txt += ("\n" if txt != "" else "") + "%s (%ds): %s" % [b.name, int(b.time), b.desc]
	return txt
