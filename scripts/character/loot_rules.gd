class_name LootRules
extends RefCounted
## Sorteio do que um inimigo deixa cair (o que antes ficava em Enemy.drop_loot + o ouro de Enemy._die).
## Puro: não cria nós; quem chama decide se vira pickup no chão ou vai direto para o personagem.


## {"gold": int, "items": {id: qty}}. Tipo desconhecido não dá nada.
## Mesma ordem de sorteio do original: ouro primeiro, depois um randf() por entrada de loot.
static func roll(bt: BalanceTables, kind: String, rng: RandomNumberGenerator) -> Dictionary:
	var out := {"gold": 0, "items": {}}
	var t: Dictionary = bt.get_table("enemies").get(kind, {})
	if t.is_empty():
		return out
	var g: Array = t.get("gold", [0, 0])
	out.gold = rng.randi_range(int(g[0]), int(g[1]))
	for entry in t.get("loot", []):
		if rng.randf() < float(entry[1]):
			out.items[entry[0]] = int(out.items.get(entry[0], 0)) + 1
	return out
