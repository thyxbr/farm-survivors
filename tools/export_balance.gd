extends SceneTree
## Uso único: lê as `const` de balanceamento do código (antes de virarem `static var`) e grava
## data/balance/*.json + o snapshot do teste (tests/unit/fixtures/balance_snapshot.res).
##   godot --headless --path . -s tools/export_balance.gd
## Depois da migração as tabelas moram nos JSON; este script serve de registro de onde vieram.

const OUT := "res://data/balance"
const SNAPSHOT := "res://tests/unit/fixtures/balance_snapshot.res"

const IDB := preload("res://scripts/autoload/item_db.gd")
const COL := preload("res://scripts/colony/colony_data.gd")
const UPG := preload("res://scripts/survival/upgrades.gd")
const ENM := preload("res://scripts/enemies/enemy.gd")
const EVT := preload("res://scripts/survival/horde_events.gd")


func _init() -> void:
	var tables := {
		"items": IDB.ITEMS,
		"crops": IDB.CROPS,
		"recipes": IDB.RECIPES,
		"spells": IDB.SPELLS,
		"quests": IDB.QUESTS,
		"shop": {"stock": IDB.SHOP_STOCK},
		"rarity": IDB.RARITY,
		"enemies": ENM.TYPES,
		"horde": {"weapons": UPG.WEAPONS, "passives": UPG.PASSIVES, "blessings": UPG.BLESSINGS, "combos": UPG.COMBOS},
		"horde_events": {"events": EVT.EVENTS, "hunt": EVT.HUNT},
		"colony": {"buildings": COL.BUILDINGS, "units": COL.UNITS, "animals": COL.ANIMALS,
			"wave_costs": COL.WAVE_COSTS, "cost_growth": COL.COST_GROWTH, "upkeep": COL.UPKEEP,
			"affixes": COL.AFFIXES, "night_mods": COL.NIGHT_MODS},
		# números soltos que hoje vivem espalhados em game.gd
		"rules": {"sell_ratio": 0.5, "xp_curve": {"base": 60, "exp": 1.55}, "points_per_level": 3,
			"farm": {"plots": 12, "start": 6, "unlock_base": 30, "unlock_step": 15, "fert_bonus": 0.4,
				"water_mult": 2, "bonus_chance": 0.12, "seed_back": 0.35}},
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SNAPSHOT.get_base_dir()))
	for n in tables:
		var f := FileAccess.open("%s/%s.json" % [OUT, n], FileAccess.WRITE)
		f.store_string(_compact(JSON.stringify(BalanceTables.encode(tables[n]), "\t", false)) + "\n")
		f.close()
	var snap := FileAccess.open(SNAPSHOT, FileAccess.WRITE)
	snap.store_buffer(var_to_bytes(tables))
	snap.close()
	print("exportadas %d tabelas" % tables.size())
	quit(0)


## O stringify bonito põe cada número de um vetor/array numa linha; junta arrays de valores simples.
func _compact(txt: String) -> String:
	var re := RegEx.new()
	re.compile(r"\[\s*([^\[\]{}]*?)\s*\]")
	var ws := RegEx.new()
	ws.compile(r",\s+")
	var out := ""
	var last := 0
	for m in re.search_all(txt):
		out += txt.substr(last, m.get_start() - last)
		out += "[" + ws.sub(m.get_string(1), ", ", true) + "]"
		last = m.get_end()
	return out + txt.substr(last)
