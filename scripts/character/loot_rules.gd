class_name LootRules
extends RefCounted
## Sorteio do que um inimigo deixa cair (o que antes ficava em Enemy.drop_loot + o ouro de Enemy._die).
## Puro: não cria nós; quem chama decide se vira pickup no chão ou vai direto para o personagem.


## {"gold": int, "items": {id: qty}}. Tipo desconhecido não dá nada.
## Mesma ordem de sorteio do original: ouro primeiro, depois um randf() por entrada de loot.
## Com `level` > 0 (monstro de Valdoria): o ouro vai pela curva do nível (ProgressionRules.enemy_mults) e,
## depois do loot da tabela, vem um sorteio de equipamento pela janela de nível (gear_drop do progression.json:
## `chance`; `elite.gear_chance` se `elite`; `boss_chance` se o tipo é chefe). Sem nível nada disso roda e a
## sequência do RNG é a de sempre.
## Com `char_class`, cada arma sorteada vira uma da classe (adapt_weapon), sorteada DEPOIS de todo o resto
## para não mudar a sequência do RNG de quem não passa classe.
## `extra`: linhas [item, chance] a mais (loot de dungeon: DungeonRules.extra_loot), sorteadas depois do resto.
## Por último, os itens caçados de progression.json "chase_drops" (ver o fim da função).
static func roll(bt: BalanceTables, kind: String, rng: RandomNumberGenerator, char_class := "",
		level := 0, elite := false, extra: Array = []) -> Dictionary:
	var out := {"gold": 0, "items": {}}
	var t: Dictionary = bt.get_table("enemies").get(kind, {})
	if t.is_empty():
		return out
	var g: Array = t.get("gold", [0, 0])
	out.gold = rng.randi_range(int(g[0]), int(g[1]))
	if level > 0:
		out.gold = int(round(float(out.gold) * float(ProgressionRules.enemy_mults(bt, kind, level).gold)))
	for entry in t.get("loot", []):
		if rng.randf() < float(entry[1]):
			out.items[entry[0]] = int(out.items.get(entry[0], 0)) + 1
	if level > 0:
		var id := _roll_gear(bt, level, elite, bool(t.get("boss", false)), rng)
		if id != "":
			out.items[id] = int(out.items.get(id, 0)) + 1
		# couro da camada do nível (material da Couraria e das essências): progression.json "tier_drop"
		var td: Dictionary = bt.get_table("progression").get("tier_drop", {})
		if not td.is_empty() and rng.randf() < float(td.get("chance", 0.0)):
			var hide := "hide_t%d" % ProgressionRules.tier_of(bt, level)
			if bt.get_table("items").has(hide):
				var q := int(td.get("boss_qty", 1)) if bool(t.get("boss", false)) else (int(td.get("elite_qty", 1)) if elite else 1)
				out.items[hide] = int(out.items.get(hide, 0)) + maxi(q, 1)
	for entry in extra:
		if rng.randf() < float(entry[1]):
			out.items[entry[0]] = int(out.items.get(entry[0], 0)) + 1
	if char_class != "":
		var adapted := {}
		for id in out.items:
			var to := adapt_weapon(bt, id, char_class, rng, level)
			adapted[to] = int(adapted.get(to, 0)) + int(out.items[id])
		out.items = adapted
	# itens caçados (progression.json "chase_drops": o Rei dos Ventos): só em monstro de Valdoria do nível pedido,
	# elite ou chefe quando a linha pede; sorteados por último (não mexem na sequência de quem não se qualifica)
	# e fora da troca por classe (cai como é, para qualquer um)
	if level > 0:
		for c in bt.get_table("progression").get("chase_drops", []):
			if level < int(c.get("min_level", 0)):
				continue
			if bool(c.get("elite", false)) and not (elite or bool(t.get("boss", false)) or bool(t.get("elite", false))):
				continue
			if rng.randf() < float(c.get("chance", 0.0)):
				var cid := str(c.get("item", ""))
				out.items[cid] = int(out.items.get(cid, 0)) + 1
	return out


## Equipamento que pode cair de monstro: nem nomeado (chefe), nem só de craft, nem variante de qualidade.
static func droppable(item: Dictionary, id: String) -> bool:
	return not item.get("named", false) and not item.get("craft", false) and ItemQuality.base(id) == id


## Equipamentos que um monstro de `level` pode deixar: equipáveis não nomeados com nível de item em
## [level + window[0], level + window[1]] (gear_drop.window), em ordem alfabética (mesma semente, mesmo resultado).
static func gear_pool(bt: BalanceTables, level: int) -> Array:
	var w: Array = bt.get_table("progression").get("gear_drop", {}).get("window", [-3, 1])
	var lo := level + int(w[0])
	var hi := level + int(w[1])
	var items: Dictionary = bt.get_table("items")
	var pool: Array = []
	for id in items:
		if CharRules.slot_of(bt, id) == "" or not droppable(items[id], id):
			continue
		var lv := CharRules.item_level(bt, id)
		if lv >= lo and lv <= hi:
			pool.append(id)
	pool.sort()
	return pool


## Um sorteio de equipamento pelo nível: passa na chance, escolhe a raridade pelo rarity_weight entre as que
## têm candidata na janela e depois o item (uniforme). "" = não caiu nada.
static func _roll_gear(bt: BalanceTables, level: int, elite: bool, boss: bool, rng: RandomNumberGenerator) -> String:
	var prog: Dictionary = bt.get_table("progression")
	var gd: Dictionary = prog.get("gear_drop", {})
	var chance := float(gd.get("chance", 0.0))
	if boss:
		chance = float(gd.get("boss_chance", chance))
	elif elite:
		chance = float(prog.get("elite", {}).get("gear_chance", chance))
	if rng.randf() >= chance:
		return ""
	var items: Dictionary = bt.get_table("items")
	var by_rarity := {}
	for id in gear_pool(bt, level):
		var r: String = items[id].get("rarity", "common")
		if not by_rarity.has(r):
			by_rarity[r] = []
		by_rarity[r].append(id)
	var weights: Dictionary = gd.get("rarity_weight", {})
	var rarities: Array = []
	var total := 0.0
	for r in by_rarity:
		if float(weights.get(r, 0.0)) > 0.0:
			rarities.append(r)
	rarities.sort()  # ordem estável
	for r in rarities:
		total += float(weights[r])
	if rarities.is_empty():
		return ""
	var pick := rng.randf() * total
	var chosen: String = rarities[rarities.size() - 1]
	for r in rarities:
		pick -= float(weights[r])
		if pick < 0.0:
			chosen = r
			break
	var cands: Array = by_rarity[chosen]
	return cands[rng.randi() % cands.size()]


## Troca uma arma sorteada por outra da classe do jogador, de mesma raridade (sorteio uniforme).
## Fica como está: item que não é arma, arma nomeada (`named`), arma que já é da classe, classe vazia/desconhecida
## ou nenhuma candidata na raridade. Com `level` > 0 só vale candidata dentro da janela de nível do gear_drop
## (sem nenhuma, a arma original fica).
static func adapt_weapon(bt: BalanceTables, id: String, char_class: String, rng: RandomNumberGenerator,
		level := 0) -> String:
	var items: Dictionary = bt.get_table("items")
	var it: Dictionary = items.get(id, {})
	if it.get("type", "") != "weapon" or it.get("named", false):
		return id
	var want := CharRules.class_weapon(bt, char_class)
	if want == "" or it.get("class", "sword") == want:
		return id
	var window: Array = gear_pool(bt, level) if level > 0 else []
	var pool: Array = []
	for cid in items:
		var c: Dictionary = items[cid]
		if c.get("type", "") == "weapon" and c.get("class", "sword") == want and droppable(c, cid) 				and c.get("rarity", "common") == it.get("rarity", "common") and (level <= 0 or cid in window):
			pool.append(cid)
	if pool.is_empty():
		return id
	pool.sort()  # ordem estável: a mesma semente dá o mesmo resultado
	return pool[rng.randi() % pool.size()]
