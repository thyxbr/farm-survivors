class_name ItemIconModels
extends RefCounted
## Tabela item -> modelo 3D do ícone, para os itens que o cavaleiro não veste (poções, comida, colheitas,
## sementes, materiais, anéis, amuletos, orbe, aljava). Um modelo por família (assets/models/items/*.glb,
## gerados por tools/blender/item_icons.py); a cor vem do item. Script puro, sem autoload: recebe as
## tabelas de itens e de culturas (ItemDB.ITEMS e ItemDB.CROPS no jogo, BalanceTables nos testes).
## Quem fotografa é o ItemIcons.

const DIR := "res://assets/models/items/"

## Materiais do GLB que recebem a cor do item (os outros ficam como saíram do Blender).
const TINT := "i_tint"              # a cor do item
const TINT_DARK := "i_tint_dark"    # a mesma cor, mais escura (sombra pintada, casca, fundo)
const TINT_LIGHT := "i_tint_light"  # a mesma cor, mais clara (brilho pintado, miolo)
const TINT_GLOW := "i_tint_glow"    # a cor do item com brilho próprio (orbe, cristal, brasa)

## Espaços cuja peça é montada no cavaleiro (ItemIcons usa o modelo de equipamento).
const WORN_SLOTS := ["head", "armor", "hands", "feet"]

const POTION_HP := Color(0.9, 0.15, 0.18)
const POTION_MP := Color(0.25, 0.4, 1.0)

## Item com modelo e cor próprios: id -> [modelo, cor]. Cor ausente (null) = a cor do item.
const BY_ID := {
	"bread": ["bread", null],
	"mint_tea": ["cup", null],
	"pumpkin_pie": ["pie", null],
	"valdoria_feast": ["feast", null],
	"wheat": ["wheat", null],
	"carrot": ["carrot", null],
	"tomato": ["tomato", null],
	"pepper": ["pepper", null],
	"mint": ["mint", null],
	"pumpkin": ["pumpkin", null],
	"slime_gel": ["gel", Color(0.35, 0.9, 0.4)],
	"goblin_ear": ["ear", Color(0.45, 0.6, 0.25)],
	"bone_shard": ["bone", Color(0.9, 0.87, 0.76)],
	"goblin_crown": ["crown", Color(0.92, 0.72, 0.3)],
	"iron_ore": ["ore", Color(0.62, 0.66, 0.74)],
	"arcane_crystal": ["crystal", Color(0.62, 0.42, 1.0)],
	"ember_core": ["core", Color(1.0, 0.42, 0.08)],
	"frost_drop": ["drop", Color(0.5, 0.85, 1.0)],
	"thunder_totem": ["totem", Color(1.0, 0.86, 0.25)],
	"toxic_gland": ["gland", Color(0.55, 0.85, 0.2)],
	"golden_dust": ["dust", Color(1.0, 0.8, 0.25)],
	"shadow_fang": ["fang", Color(0.42, 0.3, 0.6)],
	"champion_badge": ["badge", Color(0.92, 0.72, 0.3)],
}

## Modelo por espaço de equipamento que não aparece no cavaleiro.
const BY_SLOT := {"ring": "ring", "amulet": "amulet"}
## Mão secundária: depende da arma que o item exige (o escudo, de espada, é peça do cavaleiro).
const BY_NEEDS := {"staff": "orb", "bow": "quiver"}
## Modelo por tipo, para o que não está em BY_ID (item novo ganha ícone sem mexer aqui).
const BY_TYPE := {"consumable": "potion", "food": "bowl", "seed": "seed_bag", "crop": "tomato", "material": "gel"}


## De onde a câmera olha a peça (o ItemIcons enquadra pelos vértices, então nada corta nem some).
const VIEW_FRONT := Vector3(0.38, 0.42, 1.0)     # peça em pé: de frente, em três quartos
const VIEW_TOP := Vector3(0.3, 0.95, 1.0)        # peça baixa e larga (prato, torta, monte): mais de cima
const LOW_MODELS := ["bowl", "pie", "feast", "dust", "bread"]


## Verdadeiro se o ícone do item sai do modelo de equipamento (arma, armadura, elmo, luvas, botas, escudo).
static func is_gear(item: Dictionary) -> bool:
	match item.get("type", ""):
		"weapon", "armor":
			return true
		"gear":
			var slot: String = item.get("slot", "")
			return slot in WORN_SLOTS or (slot == "offhand" and item.get("needs", "") == "sword")
	return false


## Modelo, cor e ponto de vista do ícone: {"model": caminho do GLB, "tint": Color, "view": Vector3}. Vazio para id desconhecido e para
## item de equipamento (ver is_gear).
static func spec(id: String, items: Dictionary, crops: Dictionary) -> Dictionary:
	var item: Dictionary = items.get(id, {})
	if item.is_empty() or is_gear(item):
		return {}
	var model := ""
	var tint: Variant = null
	if BY_ID.has(id):
		model = BY_ID[id][0]
		tint = BY_ID[id][1]
	else:
		match item.get("type", ""):
			"gear":
				var slot: String = item.get("slot", "")
				model = BY_NEEDS.get(item.get("needs", ""), "") if slot == "offhand" else BY_SLOT.get(slot, "")
			var type:
				model = BY_TYPE.get(type, "")
	if model == "":
		return {}
	if tint == null:
		tint = _color(id, item, crops)
	return {"model": DIR + model + ".glb", "tint": tint, "view": VIEW_TOP if model in LOW_MODELS else VIEW_FRONT}


## Cor do item quando a tabela BY_ID não fixa uma: a do próprio item, a da cultura, a do efeito da poção.
static func _color(id: String, item: Dictionary, crops: Dictionary) -> Color:
	if item.has("color"):
		return item.color
	match item.get("type", ""):
		"consumable":
			return POTION_HP if item.has("heal_hp") else POTION_MP
		"seed":
			return crops.get(item.get("crop", ""), {}).get("color", Color(0.6, 0.8, 0.3))
		"crop":
			return crops.get(id, {}).get("color", Color(0.6, 0.8, 0.3))
	return Color(0.7, 0.7, 0.7)
