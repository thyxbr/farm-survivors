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
}

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
	lines.append(it.desc)
	lines.append("Valor: %d ouro" % it.price)
	return "\n".join(lines)
