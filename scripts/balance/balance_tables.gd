class_name BalanceTables
extends RefCounted
## Tabelas de balanceamento (itens, inimigos, colônia...) carregadas de JSON.
## Classe pura, sem autoload: as regras do jogo recebem uma instância (injeção) e os testes
## unitários montam a sua com from_dict(). O autoload Balance só guarda a instância do jogo.
##
## JSON não tem Color/Vector: eles viajam como {"$c":[r,g,b,a]}, {"$v2":[x,y]} e {"$v3":[x,y,z]}.
## O parser do Godot devolve todo número como float; float inteiro volta a ser int (ver decode).

## Nome de cada tabela = nome do arquivo em data/balance/<nome>.json.
const NAMES := ["items", "crops", "recipes", "spells", "quests", "shop", "rarity", "enemies",
	"horde", "horde_events", "colony", "rules", "rewards", "meta_passives", "base_buildings"]

## Tag -> quantidade de componentes numéricos esperada ([min, max]).
const _TAGS := {"$c": [3, 4], "$v2": [2, 2], "$v3": [3, 3]}

## As tabelas guardadas aqui, e as que to_dict()/from_dict()/set_table() trocam, estão sempre
## DECODIFICADAS (Color, Vector, int de verdade). Para mandar pela rede ou gravar em JSON o
## chamador faz BalanceTables.encode(to_dict()) -> JSON.stringify; ao receber, JSON.parse_string
## -> BalanceTables.decode(...) -> from_dict(). from_dict NÃO decodifica.
var _tables := {}


static func load_dir(path: String) -> BalanceTables:
	var bt := BalanceTables.new()
	for n in NAMES:
		var file := "%s/%s.json" % [path.trim_suffix("/"), n]
		var f := FileAccess.open(file, FileAccess.READ)
		if f == null:
			push_error("Balance: não consegui abrir %s" % file)
			bt._tables[n] = {}
			continue
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			bt._tables[n] = decode(parsed)
		else:
			push_error("Balance: JSON inválido em %s" % file)
			bt._tables[n] = {}
	return bt


## Recebe tabelas já decodificadas (ver nota acima) ({nome: Dictionary}); copia fundo para não compartilhar estado.
static func from_dict(d: Dictionary) -> BalanceTables:
	var bt := BalanceTables.new()
	for n in d:
		bt._tables[n] = (d[n] as Dictionary).duplicate(true)
	return bt


func to_dict() -> Dictionary:
	return _tables.duplicate(true)


func get_table(name: String) -> Dictionary:
	return _tables.get(name, {})


func set_table(name: String, data: Dictionary) -> void:
	_tables[name] = data


## JSON -> valores do jogo: {"$c":..} vira Color, {"$v2":..} Vector2, {"$v3":..} Vector3 e
## float inteiro vira int (o parser do Godot só conhece float; preços e vida são int no código).
static func decode(v: Variant) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			if v.size() == 1:
				for tag in _TAGS:
					if v.has(tag):
						return _decode_tag(tag, v[tag], v)
			var out := {}
			for k in v:
				out[k] = decode(v[k])
			return out
		TYPE_ARRAY:
			var out := []
			for x in v:
				out.append(decode(x))
			return out
		TYPE_FLOAT:
			if is_finite(v) and v == floorf(v) and absf(v) < 9007199254740992.0:
				return int(v)
			return v
	return v


## Valores do jogo -> JSON (inverso de decode). Componentes arredondados a 4 casas para o
## arquivo ficar legível (0.55 em vez de 0.550000011920929); o float32 de volta é o mesmo.
static func encode(v: Variant) -> Variant:
	match typeof(v):
		TYPE_COLOR:
			return {"$c": [_r(v.r), _r(v.g), _r(v.b), _r(v.a)]}
		TYPE_VECTOR2:
			return {"$v2": [_r(v.x), _r(v.y)]}
		TYPE_VECTOR3:
			return {"$v3": [_r(v.x), _r(v.y), _r(v.z)]}
		TYPE_DICTIONARY:
			var out := {}
			for k in v:
				out[k] = encode(v[k])
			return out
		TYPE_ARRAY:
			var out := []
			for x in v:
				out.append(encode(x))
			return out
	return v


static func _r(x: float) -> float:
	return snappedf(x, 0.0001)


## Tag malformada (tamanho ou tipo errado) não derruba o jogo: avisa e devolve o valor cru.
static func _decode_tag(tag: String, raw: Variant, whole: Dictionary) -> Variant:
	var n: Array = _TAGS[tag]
	if not (raw is Array) or raw.size() < n[0] or raw.size() > n[1]:
		push_error("Balance: tag %s malformada: %s" % [tag, var_to_str(raw)])
		return whole
	for x in raw:
		if not (x is float or x is int):
			push_error("Balance: tag %s com valor não numérico: %s" % [tag, var_to_str(raw)])
			return whole
	match tag:
		"$c":
			return Color(raw[0], raw[1], raw[2], raw[3] if raw.size() > 3 else 1.0)
		"$v2":
			return Vector2(raw[0], raw[1])
	return Vector3(raw[0], raw[1], raw[2])
