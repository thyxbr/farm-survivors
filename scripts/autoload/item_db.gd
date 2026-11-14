extends Node
## Banco de dados de itens, magias e missões (dados puros).
## As tabelas (ITEMS, CROPS, RECIPES, SPELLS, QUESTS, SHOP_STOCK, RARITY) moram em data/balance/*.json
## e são preenchidas pelo autoload Balance antes de qualquer _ready; aqui só ficam as `static var`.
## Campos de item (items.json): "class" sword (combo corpo a corpo, escala com FOR) · staff (projéteis
## mágicos, escala com INT) · bow (segure para tensionar e solte, escala com AGI); "shape" muda o modelo 3D;
## "stats" = bônus do item (ver STAT_NAMES); "fx" = efeito ao acertar (slow, splash, pierce, multishot).

static var ITEMS: Dictionary = {}

## Culturas da horta. "time" = segundos para crescer sem regar (regada cresce 2x mais rápido).
static var CROPS: Dictionary = {}
const CROP_ORDER := ["carrot", "wheat", "tomato", "pepper", "mint", "pumpkin"]

## Receitas do caldeirão: comida -> ingredientes.
static var RECIPES: Dictionary = {}
const RECIPE_ORDER := ["bread", "carrot_stew", "spicy_soup", "dragon_chili", "mint_tea", "garden_salad", "pumpkin_pie", "valdoria_feast"]

static var SPELLS: Dictionary = {}

static var QUESTS: Dictionary = {}

static var SHOP_STOCK: Array = []

# ---------------------------------------------------------------- equipamento
## Espaços de equipamento na ordem do "boneco" (esquerda de cima para baixo, depois direita).
const SLOTS := ["head", "amulet", "armor", "hands", "weapon", "offhand", "ring", "feet"]
const SLOT_NAMES := {"weapon": "Arma", "offhand": "Mão secundária", "head": "Cabeça", "armor": "Peito",
	"hands": "Mãos", "feet": "Pés", "amulet": "Amuleto", "ring": "Anel"}
const CLASS_NAMES := {"sword": "Espada", "staff": "Cajado", "bow": "Arco"}
const CLASS_HINT := {"sword": "Combo de 3 golpes · escala com Força",
	"staff": "Projéteis arcanos · escala com Inteligência",
	"bow": "Segure para tensionar, solte para atirar · escala com Agilidade"}
const FX_NAMES := {"slow": "Golpes deixam o alvo lento", "splash": "Projéteis explodem em área",
	"pierce": "Flechas perfuram inimigos", "multishot": "Disparo tensionado: 3 flechas"}

static var RARITY: Dictionary = {}

## Bônus que os itens podem dar. [nome, formato] (formato "%" multiplica por 100).
const STAT_NAMES := {
	"str": ["Força", ""], "int": ["Inteligência", ""], "vit": ["Vitalidade", ""], "agi": ["Agilidade", ""],
	"hp": ["Vida máxima", ""], "mp": ["Mana máxima", ""], "spell": ["Poder mágico", ""],
	"crit": ["Chance de crítico", "%"], "speed": ["Velocidade", "%"], "cdr": ["Recarga de magias", "-%"],
	"leech": ["Roubo de vida", "%"],
}
const STAT_ORDER := ["str", "int", "vit", "agi", "hp", "mp", "spell", "crit", "speed", "cdr", "leech"]


func get_item(id: String) -> Dictionary:
	return ITEMS.get(id, {})


func is_stackable(id: String) -> bool:
	return get_item(id).get("stack", false)


## Espaço de equipamento do item ("" se não for equipável).
func slot_of(id: String) -> String:
	var it := get_item(id)
	match it.get("type", ""):
		"weapon":
			return "weapon"
		"armor":
			return "armor"
		"gear":
			return it.get("slot", "")
	return ""


func is_equippable(id: String) -> bool:
	return slot_of(id) != ""


func weapon_class(id: String) -> String:
	return get_item(id).get("class", "sword") if id != "" else "sword"


func rarity_of(id: String) -> String:
	var it := get_item(id)
	if it.has("rarity"):
		return it.rarity
	return "common"


func rarity_color(id: String) -> Color:
	return RARITY[rarity_of(id)].color


func item_stats(id: String) -> Dictionary:
	return get_item(id).get("stats", {})


func format_stat(k: String, v: float, signed := true) -> String:
	var fmt: String = STAT_NAMES[k][1]
	var nm: String = STAT_NAMES[k][0]
	if fmt == "%":
		return "%s%d%% %s" % ["+" if signed and v >= 0 else "", int(round(v * 100)), nm]
	if fmt == "-%":
		return "%s%d%% %s" % ["−" if v >= 0 else "+", int(round(abs(v) * 100)), nm]
	return "%s%d %s" % ["+" if signed and v >= 0 else "", int(round(v)), nm]


## Categoria usada pelos filtros do inventário e da loja.
func category(id: String) -> String:
	var t: String = get_item(id).get("type", "")
	if t in ["weapon", "armor", "gear"]:
		return "equip"
	if t in ["consumable", "food", "crop"]:
		return "use"
	return "misc"


## Pontuação simples para ordenar e comparar itens.
func power_score(id: String) -> float:
	var it := get_item(id)
	var s := float(it.get("damage", 0)) * 1.5 + float(it.get("defense", 0)) * 2.0
	var st := item_stats(id)
	for k in st:
		var v := float(st[k])
		s += v * (100.0 if STAT_NAMES[k][1] != "" else (0.25 if k in ["hp", "mp"] else 1.0))
	return s


func item_summary(id: String) -> String:
	var it := get_item(id)
	if it.is_empty():
		return ""
	var lines: Array[String] = [it.name]
	match it.type:
		"weapon":
			lines.append("%s — Dano %d" % [CLASS_NAMES[weapon_class(id)], it.damage])
			var ench: String = Game.enchant_text(id)
			if ench != "":
				lines.append(ench)
		"armor", "gear":
			lines.append("%s — Defesa %d" % [SLOT_NAMES[slot_of(id)], it.get("defense", 0)])
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
	var st := item_stats(id)
	for k in STAT_ORDER:
		if st.has(k):
			lines.append(format_stat(k, float(st[k])))
	if it.has("fx"):
		lines.append(FX_NAMES[it.fx])
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
