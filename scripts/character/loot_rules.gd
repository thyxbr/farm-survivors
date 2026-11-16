class_name LootRules
extends RefCounted
## Sorteio do que um inimigo deixa cair (o que antes ficava em Enemy.drop_loot + o ouro de Enemy._die).
## Puro: não cria nós; quem chama decide se vira pickup no chão ou vai direto para o personagem.


## {"gold": int, "items": {id: qty}}. Tipo desconhecido não dá nada.
## Mesma ordem de sorteio do original: ouro primeiro, depois um randf() por entrada de loot.
## Com `char_class`, cada arma sorteada vira uma da classe (adapt_weapon), sorteada DEPOIS de todo o loot
## original para não mudar a sequência do RNG de quem não passa classe.
static func roll(bt: BalanceTables, kind: String, rng: RandomNumberGenerator, char_class := "") -> Dictionary:
	var out := {"gold": 0, "items": {}}
	var t: Dictionary = bt.get_table("enemies").get(kind, {})
	if t.is_empty():
		return out
	var g: Array = t.get("gold", [0, 0])
	out.gold = rng.randi_range(int(g[0]), int(g[1]))
	for entry in t.get("loot", []):
		if rng.randf() < float(entry[1]):
			out.items[entry[0]] = int(out.items.get(entry[0], 0)) + 1
	if char_class != "":
		var adapted := {}
		for id in out.items:
			var to := adapt_weapon(bt, id, char_class, rng)
			adapted[to] = int(adapted.get(to, 0)) + int(out.items[id])
		out.items = adapted
	return out


## Troca uma arma sorteada por outra da classe do jogador, de mesma raridade (sorteio uniforme).
## Fica como está: item que não é arma, arma nomeada (`named`), arma que já é da classe, classe vazia/desconhecida
## ou nenhuma candidata na raridade.
static func adapt_weapon(bt: BalanceTables, id: String, char_class: String, rng: RandomNumberGenerator) -> String:
	var items: Dictionary = bt.get_table("items")
	var it: Dictionary = items.get(id, {})
	if it.get("type", "") != "weapon" or it.get("named", false):
		return id
	var want := CharRules.class_weapon(bt, char_class)
	if want == "" or it.get("class", "sword") == want:
		return id
	var pool: Array = []
	for cid in items:
		var c: Dictionary = items[cid]
		if c.get("type", "") == "weapon" and c.get("class", "sword") == want and not c.get("named", false) 				and c.get("rarity", "common") == it.get("rarity", "common"):
			pool.append(cid)
	if pool.is_empty():
		return id
	pool.sort()  # ordem estável: a mesma semente dá o mesmo resultado
	return pool[rng.randi() % pool.size()]
