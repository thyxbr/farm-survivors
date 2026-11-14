class_name BaseRules
extends RefCounted
## Base compartilhada do servidor: construções que sobem de nível com doações em Ecos.
## Pura (sem autoload). Estado = {id: {"level": int, "fund": int}}; os custos e bônus vêm de
## data/balance/base_buildings.json. levels[i].cost = Ecos para ir do nível i ao i+1 e
## levels[i].bonus = bônus TOTAL no nível i+1 (não soma com os anteriores); nível 0 = sem bônus.


static func _buildings(bt: BalanceTables) -> Dictionary:
	return bt.get_table("base_buildings").get("buildings", {})


static func empty_state(bt: BalanceTables) -> Dictionary:
	var out := {}
	for id in _buildings(bt):
		out[id] = {"level": 0, "fund": 0}
	return out


## Falha devolve o nível e o fundo atuais da construção (nada mudou), não zeros.
static func _fail(err: String, entry: Dictionary = {}) -> Dictionary:
	return {"ok": false, "err": err, "used": 0, "level": maxi(0, int(entry.get("level", 0))),
		"fund": maxi(0, int(entry.get("fund", 0))), "leveled": 0}


## Doa `amount` Ecos à construção. Não muda `entry`: devolve o novo nível/fundo. `used` é o que
## foi aceito (nunca passa do que falta até o nível máximo); o fundo que enche um nível sobe o
## nível e o resto fica no fundo, podendo subir vários de uma vez.
static func donate(entry: Dictionary, bt: BalanceTables, building_id: String, amount: int) -> Dictionary:
	var b: Dictionary = _buildings(bt).get(building_id, {})
	if b.is_empty():
		return _fail("construcao_invalida", entry)
	if amount <= 0:
		return _fail("valor_invalido", entry)
	var levels: Array = b.get("levels", [])
	var level := clampi(int(entry.get("level", 0)), 0, levels.size())
	var fund := maxi(0, int(entry.get("fund", 0)))
	if level >= levels.size():
		return _fail("nivel_maximo", entry)
	var remaining := -fund
	for i in range(level, levels.size()):
		remaining += int(levels[i].cost)
	var used := mini(amount, maxi(0, remaining))
	fund += used
	var leveled := 0
	while level < levels.size() and fund >= int(levels[level].cost):
		fund -= int(levels[level].cost)
		level += 1
		leveled += 1
	return {"ok": true, "err": "", "used": used, "level": level, "fund": fund, "leveled": leveled}


## Soma dos bônus do nível atual de cada construção.
static func bonus(bt: BalanceTables, state: Dictionary) -> Dictionary:
	var out := {}
	var all := _buildings(bt)
	for id in state:
		if not all.has(id):
			continue
		var levels: Array = all[id].get("levels", [])
		var lv := clampi(int(state[id].get("level", 0)), 0, levels.size())
		if lv <= 0:
			continue
		var bn: Dictionary = levels[lv - 1].get("bonus", {})
		for k in bn:
			out[k] = out.get(k, 0) + bn[k]
	return out


## Ecos já investidos: custos dos níveis subidos + o fundo (para devolver se a construção sair).
static func total_invested(bt: BalanceTables, building_id: String, entry: Dictionary) -> int:
	var levels: Array = _buildings(bt).get(building_id, {}).get("levels", [])
	var lv := clampi(int(entry.get("level", 0)), 0, levels.size())
	var total := maxi(0, int(entry.get("fund", 0)))
	for i in lv:
		total += int(levels[i].cost)
	return total
