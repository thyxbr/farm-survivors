extends Node
## Despeja as tabelas de balanceamento do jogo em JSON (stdout), para a skill balance-check.
## Roda como cena (assim os autoloads Game/Network existem e os scripts compilam). Da raiz do projeto,
## depois de um --import se a pasta for nova:
##   godot --headless --path . res://.claude/skills/balance-check/dump_data.tscn
## Saída: uma linha "BALANCE_JSON " seguida do JSON. Não altera nada no projeto.

const SOURCES := {
	"item_db": "res://scripts/autoload/item_db.gd",
	"enemy": "res://scripts/enemies/enemy.gd",
	"upgrades": "res://scripts/survival/upgrades.gd",
	"horde_events": "res://scripts/survival/horde_events.gd",
	"colony_data": "res://scripts/colony/colony_data.gd",
	"game": "res://scripts/autoload/game.gd",
}


func _ready() -> void:
	var out := {}
	for key in SOURCES:
		var script: Script = load(SOURCES[key])
		if script == null:
			out[key] = {"_erro": "não carregou " + SOURCES[key]}
			continue
		var consts := {}
		var map: Dictionary = script.get_script_constant_map()
		for c in map:
			var v = map[c]
			if v is Dictionary or v is Array or v is int or v is float or v is String:
				consts[c] = _plain(v)
		out[key] = consts
	print("BALANCE_JSON ", JSON.stringify(out))
	get_tree().quit(0)


## Converte Color/Vector/objetos em texto, para o JSON ficar legível.
func _plain(v):
	if v is Dictionary:
		var d := {}
		for k in v:
			d[str(k)] = _plain(v[k])
		return d
	if v is Array:
		var a := []
		for x in v:
			a.append(_plain(x))
		return a
	if v is Color:
		return "#" + v.to_html(false)
	if v is Vector2 or v is Vector3:
		return str(v)
	if v is Object:
		return "<%s>" % v.get_class()
	return v
