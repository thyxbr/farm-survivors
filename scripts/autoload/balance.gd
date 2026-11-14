extends Node
## Autoload das tabelas de balanceamento. Carrega data/balance/*.json e repovoa as `static var`
## de ItemDB, ColonyData, UPG, Enemy e HordeEvents, que antes eram `const`. Fica ANTES do
## ItemDB em project.godot. O resto do código continua lendo ItemDB.ITEMS, Enemy.TYPES etc.
## BalanceTables é uma classe pura (sem autoload) para as regras poderem ser testadas sozinhas;
## este nó só guarda a instância do jogo e avisa quando as tabelas trocam (`changed`).

# preload dos scripts (e não dos nomes de autoload): o ItemDB ainda nem existe quando este _init roda
const _ITEM_DB := preload("res://scripts/autoload/item_db.gd")
const _COLONY := preload("res://scripts/colony/colony_data.gd")
const _UPG := preload("res://scripts/survival/upgrades.gd")
const _ENEMY := preload("res://scripts/enemies/enemy.gd")
const _EVENTS := preload("res://scripts/survival/horde_events.gd")

const DIR := "res://data/balance"

signal changed(names: Array)

var tables: BalanceTables
## true = as tabelas em uso vieram do servidor (o solo volta às da versão com reload_local()).
var from_server := false


func _init() -> void:
	# antes de qualquer _ready: ItemDB e os demais já encontram as tabelas preenchidas
	tables = BalanceTables.load_dir(DIR)
	_populate()


## Troca as tabelas (ex.: servidor mandando balanceamento novo) e repovoa as static var.
func apply(d: Dictionary, server := false) -> void:
	tables = BalanceTables.from_dict(d)
	from_server = server
	_populate()
	changed.emit(d.keys())


## Volta às tabelas que vêm com a versão (res://data/balance).
func reload_local() -> void:
	tables = BalanceTables.load_dir(DIR)
	from_server = false
	_populate()
	changed.emit(tables.to_dict().keys())


func _populate() -> void:
	var t := tables
	_ITEM_DB.ITEMS = t.get_table("items")
	_ITEM_DB.CROPS = t.get_table("crops")
	_ITEM_DB.RECIPES = t.get_table("recipes")
	_ITEM_DB.SPELLS = t.get_table("spells")
	_ITEM_DB.QUESTS = t.get_table("quests")
	_ITEM_DB.SHOP_STOCK = t.get_table("shop").get("stock", [])
	_ITEM_DB.RARITY = t.get_table("rarity")
	_ENEMY.TYPES = t.get_table("enemies")
	var h := t.get_table("horde")
	_UPG.WEAPONS = h.get("weapons", {})
	_UPG.PASSIVES = h.get("passives", {})
	_UPG.BLESSINGS = h.get("blessings", {})
	_UPG.COMBOS = h.get("combos", {})
	var ev := t.get_table("horde_events")
	_EVENTS.EVENTS = ev.get("events", {})
	_EVENTS.HUNT = ev.get("hunt", {})
	var c := t.get_table("colony")
	_COLONY.BUILDINGS = c.get("buildings", {})
	_COLONY.UNITS = c.get("units", {})
	_COLONY.ANIMALS = c.get("animals", {})
	_COLONY.WAVE_COSTS = c.get("wave_costs", {})
	_COLONY.COST_GROWTH = c.get("cost_growth", {})
	_COLONY.UPKEEP = c.get("upkeep", {})
	_COLONY.AFFIXES = c.get("affixes", {})
	_COLONY.NIGHT_MODS = c.get("night_mods", {})
