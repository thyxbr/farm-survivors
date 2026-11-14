class_name CharRules
extends RefCounted
## Regras do personagem, puras: o servidor dedicado e o cliente solo rodam exatamente o mesmo código.
## Portadas do antigo autoload Game (mesma lógica e mesmos textos). Sem autoload: as tabelas chegam
## por injeção (BalanceTables) e os números de regra vêm de bt.get_table("rules").
##
## Toda operação: static func <op>(s: CharState, bt: BalanceTables, ...) -> {"ok", "err", "events"}.
## Só muta `s` se ok. Eventos: {"t":"notify","text","color"}, {"t":"level_up","level"},
## {"t":"looted","id","qty"}, {"t":"quest"}, {"t":"farm"}. Em falha os avisos também vêm em events
## (para o cliente mostrar o mesmo texto de antes), mas o estado fica intacto.
## Vida/mana (cura, buff, teto do máximo) são do cliente: as regras não mexem em hp/mp.

## Espaços de equipamento (mesma ordem de ItemDB.SLOTS).
const SLOTS := ["head", "amulet", "armor", "hands", "weapon", "offhand", "ring", "feet"]
const CLASS_NAMES := {"sword": "Espada", "staff": "Cajado", "bow": "Arco"}

const C_GOLD := Color(1, 0.85, 0.3)
const C_BAD := Color(1, 0.5, 0.5)
const C_QUEST := Color(1.0, 0.8, 0.35)
const C_FARM := Color(0.8, 1.0, 0.6)
## Teto de toda quantidade escolhida pelo cliente (compra, vezes de cozinhar): evita estouro de
## int64 em preço*qty e laço gigante de add_item em item não empilhável no servidor.
const MAX_COUNT := 99


# ================================================================ apoio
static func _ok(events: Array = []) -> Dictionary:
	return {"ok": true, "err": "", "events": events}


static func _fail(err: String, events: Array = []) -> Dictionary:
	return {"ok": false, "err": err, "events": events}


## true se `n` é um int entre 1 e MAX_COUNT (contagem vinda do cliente).
static func _valid_count(n) -> bool:
	return typeof(n) == TYPE_INT and n >= 1 and n <= MAX_COUNT


static func _notify(text: String, color: Color) -> Dictionary:
	return {"t": "notify", "text": text, "color": color}


static func _rules(bt: BalanceTables) -> Dictionary:
	return bt.get_table("rules")


static func _farm_rules(bt: BalanceTables) -> Dictionary:
	return _rules(bt).get("farm", {})


static func _item(bt: BalanceTables, id: String) -> Dictionary:
	return bt.get_table("items").get(id, {})


static func empty_equipment() -> Dictionary:
	var e := {}
	for slot in SLOTS:
		e[slot] = ""
	return e


static func slot_of(bt: BalanceTables, id: String) -> String:
	var it := _item(bt, id)
	match it.get("type", ""):
		"weapon":
			return "weapon"
		"armor":
			return "armor"
		"gear":
			return it.get("slot", "")
	return ""


static func weapon_class(bt: BalanceTables, id: String) -> String:
	return _item(bt, id).get("class", "sword") if id != "" else "sword"


static func rarity_of(bt: BalanceTables, id: String) -> String:
	return _item(bt, id).get("rarity", "common")


static func rarity_color(bt: BalanceTables, id: String) -> Color:
	return bt.get_table("rarity").get(rarity_of(bt, id), {}).get("color", Color.WHITE)


## Soma de um bônus ("hp", "mp", "str"...) dos itens equipados.
static func gear(s: CharState, bt: BalanceTables, k: String) -> float:
	var v := 0.0
	for slot in s.equipment:
		if s.equipment[slot] != "":
			v += float(_item(bt, s.equipment[slot]).get("stats", {}).get(k, 0.0))
	return v


## Vida/mana máximas sem bônus temporários (Horda, comida): só para o personagem novo nascer cheio.
## O combate continua calculando o máximo de verdade no cliente.
static func base_max_hp(s: CharState, bt: BalanceTables) -> float:
	return 60.0 + (int(s.attributes.vit) + int(gear(s, bt, "vit"))) * 10.0 + (s.level - 1) * 8.0 + gear(s, bt, "hp")


static func base_max_mp(s: CharState, bt: BalanceTables) -> float:
	return 25.0 + (int(s.attributes.int) + int(gear(s, bt, "int"))) * 6.0 + (s.level - 1) * 3.0 + gear(s, bt, "mp")


# ================================================================ inventário
static func count_item(s: CharState, id: String) -> int:
	var n := 0
	for slot in s.inventory:
		if slot.id == id:
			n += int(slot.qty)
	return n


## Põe na mochila (empilha se o item for "stack"). Sem checagem: quem chama já validou.
static func add_item(s: CharState, bt: BalanceTables, id: String, qty := 1) -> void:
	if _item(bt, id).get("stack", false):
		for slot in s.inventory:
			if slot.id == id:
				slot.qty += qty
				return
		s.inventory.append({"id": id, "qty": qty})
	else:
		for i in qty:
			s.inventory.append({"id": id, "qty": 1})


static func remove_item(s: CharState, id: String, qty := 1) -> bool:
	if count_item(s, id) < qty:
		return false
	var i := s.inventory.size() - 1
	while i >= 0 and qty > 0:
		var slot: Dictionary = s.inventory[i]
		if slot.id == id:
			var take: int = mini(qty, int(slot.qty))
			slot.qty -= take
			qty -= take
			if slot.qty <= 0:
				s.inventory.remove_at(i)
		i -= 1
	return true


## Ordena a mochila: equipamentos primeiro (mais raros antes), depois consumíveis e o resto.
static func sort_inventory(s: CharState, bt: BalanceTables) -> Dictionary:
	s.inventory.sort_custom(func(a, b): return _inv_less(bt, a, b))
	return _ok()


static func _category(bt: BalanceTables, id: String) -> int:
	var t: String = _item(bt, id).get("type", "")
	if t in ["weapon", "armor", "gear"]:
		return 0
	if t in ["consumable", "food", "crop"]:
		return 1
	return 2


static func _inv_less(bt: BalanceTables, a: Dictionary, b: Dictionary) -> bool:
	var ca := _category(bt, a.id)
	var cb := _category(bt, b.id)
	if ca != cb:
		return ca < cb
	var rar := bt.get_table("rarity")
	var ra := int(rar.get(rarity_of(bt, a.id), {}).get("rank", 0))
	var rb := int(rar.get(rarity_of(bt, b.id), {}).get("rank", 0))
	if ra != rb:
		return ra > rb
	var sa := slot_of(bt, a.id)
	var sb := slot_of(bt, b.id)
	if sa != sb:
		return sa < sb
	return str(_item(bt, a.id).get("name", a.id)) < str(_item(bt, b.id).get("name", b.id))


# ================================================================ XP e ouro
static func xp_to_next(level: int, bt: BalanceTables) -> int:
	var c: Dictionary = _rules(bt).get("xp_curve", {})
	return int(float(c.base) * pow(level, float(c.exp)))


## Soma XP e sobe de nível quantas vezes der (eventos em `ev`).
static func _add_xp(s: CharState, bt: BalanceTables, amount: int, ev: Array) -> void:
	if amount <= 0:
		return
	s.xp += amount
	ev.append(_notify("+%d XP" % amount, Color(0.6, 0.85, 1.0)))
	var pts := int(_rules(bt).get("points_per_level", 3))
	var spells := bt.get_table("spells")
	while s.xp >= xp_to_next(s.level, bt):
		s.xp -= xp_to_next(s.level, bt)
		s.level += 1
		s.stat_points += pts
		ev.append(_notify("Nível %d! +%d pontos de atributo (C)" % [s.level, pts], Color(1.0, 0.85, 0.3)))
		for id in spells:
			if int(spells[id].get("level", 0)) == s.level:
				ev.append(_notify("Nova magia: %s [%s]" % [spells[id].name, spells[id].key], Color(0.75, 0.55, 1.0)))
		ev.append({"t": "level_up", "level": s.level})


## Recompensa direta (coleta de loot, prêmio da Horda...): ouro, XP e itens.
static func grant(s: CharState, bt: BalanceTables, gold: int, xp: int, items: Dictionary) -> Dictionary:
	if gold < 0 or xp < 0:
		return _fail("valor_invalido")
	var items_t := bt.get_table("items")
	for id in items:
		if not items_t.has(id):
			return _fail("item_invalido")
		if int(items[id]) <= 0:
			return _fail("valor_invalido")
	var ev: Array = []
	s.gold += gold
	_add_xp(s, bt, xp, ev)
	for id in items:
		add_item(s, bt, id, int(items[id]))
		ev.append({"t": "looted", "id": id, "qty": int(items[id])})
	return _ok(ev)


## Abate: XP, contagem de abates e progresso de missão.
static func kill(s: CharState, bt: BalanceTables, kind: String, xp: int) -> Dictionary:
	if xp < 0:
		return _fail("valor_invalido")
	var ev: Array = []
	s.kills += 1
	# chefe derrotado (o Rei Goblin): o mundo deixa de gerá-lo, como fazia Enemy._die
	if bt.get_table("enemies").get(kind, {}).get("boss", false):
		s.flags["king_dead"] = true
	_add_xp(s, bt, xp, ev)
	var qt := bt.get_table("quests")
	var changed := false
	for id in s.quests:
		if not qt.has(id):
			continue
		var q: Dictionary = qt[id]
		if s.quests[id].state == "active" and q.target == kind:
			s.quests[id].progress += 1
			changed = true
			if s.quests[id].progress >= int(q.count):
				s.quests[id].state = "ready"
				ev.append(_notify("%s: volte para %s" % [q.name, q.giver], C_QUEST))
			else:
				ev.append(_notify("%s %d/%d" % [q.name, s.quests[id].progress, q.count], Color(1.0, 0.9, 0.6)))
	if changed:
		ev.append({"t": "quest"})
	return _ok(ev)


static func spend_point(s: CharState, bt: BalanceTables, attr: String) -> Dictionary:
	if not s.attributes.has(attr):
		return _fail("atributo_invalido")
	if s.stat_points <= 0:
		return _fail("sem_pontos")
	s.stat_points -= 1
	s.attributes[attr] += 1
	return _ok()


# ================================================================ loja
## Compra `qty` (padrão 1) de um item da loja ou de uma semente da horta.
static func buy(s: CharState, bt: BalanceTables, id: String, qty = 1) -> Dictionary:
	if not _valid_count(qty):
		return _fail("args")
	if not _sold_in_shop(bt, id):
		return _fail("nao_vende")
	var price: int = int(_item(bt, id).get("price", 0)) * qty
	if s.gold < price:
		var txt := "Ouro insuficiente." if qty == 1 else "Ouro insuficiente (%d)." % price
		return _fail("ouro_insuficiente", [_notify(txt, C_BAD)])
	s.gold -= price
	add_item(s, bt, id, qty)
	return _ok([{"t": "looted", "id": id, "qty": qty}])


static func _sold_in_shop(bt: BalanceTables, id: String) -> bool:
	if not bt.get_table("items").has(id):
		return false
	if id in bt.get_table("shop").get("stock", []):
		return true
	var crops := bt.get_table("crops")
	for c in crops:
		if crops[c].get("seed", "") == id:
			return true
	return false


## Jogar fora 1 unidade (botão "Descartar" da mochila). Só tira do próprio jogador.
static func discard(s: CharState, bt: BalanceTables, id: String) -> Dictionary:
	if _item(bt, id).is_empty():
		return _fail("item_invalido")
	if count_item(s, id) <= 0:
		return _fail("sem_item")
	remove_item(s, id, 1)
	return _ok()


## Renascer na vila custa uma fração do ouro (rules.death_gold_loss, padrão 10%). Pedido pelo próprio
## cliente ao renascer: só tira dele, então não há o que forjar.
static func death_penalty(s: CharState, bt: BalanceTables) -> Dictionary:
	var lost := int(s.gold * float(_rules(bt).get("death_gold_loss", 0.1)))
	if lost <= 0:
		return _ok()
	s.gold -= lost
	return _ok([_notify("Você perdeu %d ouro." % lost, Color(1, 0.6, 0.5))])


static func sell(s: CharState, bt: BalanceTables, id: String) -> Dictionary:
	var it := _item(bt, id)
	if it.is_empty():
		return _fail("item_invalido")
	if count_item(s, id) <= 0:
		return _fail("sem_item")
	remove_item(s, id, 1)
	var value := int(ceil(float(it.get("price", 0)) * float(_rules(bt).get("sell_ratio", 0.5))))
	s.gold += value
	return _ok([_notify("Vendido por %d ouro" % value, C_GOLD)])


# ================================================================ equipamento
static func equip(s: CharState, bt: BalanceTables, id: String) -> Dictionary:
	var slot_name := slot_of(bt, id)
	if slot_name == "":
		return _fail("nao_equipavel")
	if count_item(s, id) <= 0:
		return _fail("sem_item")
	var it := _item(bt, id)
	# mão secundária precisa combinar com a classe da arma (escudo-espada, orbe-cajado, aljava-arco)
	if slot_name == "offhand" and it.has("needs") and it.needs != weapon_class(bt, s.equipment.weapon):
		return _fail("exige_classe", [_notify("%s exige %s." % [it.name, str(CLASS_NAMES.get(it.needs, it.needs)).to_lower()],
			Color(1, 0.6, 0.5))])
	var ev: Array = []
	remove_item(s, id, 1)
	if s.equipment[slot_name] != "":
		add_item(s, bt, s.equipment[slot_name], 1)
	s.equipment[slot_name] = id
	# trocou de classe de arma: a mão secundária incompatível volta para a mochila
	if slot_name == "weapon" and s.equipment.offhand != "":
		var off := _item(bt, s.equipment.offhand)
		if off.has("needs") and off.needs != weapon_class(bt, s.equipment.weapon):
			add_item(s, bt, s.equipment.offhand, 1)
			ev.append(_notify("%s guardado (exige %s)." % [off.name, str(CLASS_NAMES.get(off.needs, off.needs)).to_lower()],
				Color(0.85, 0.8, 0.65)))
			s.equipment.offhand = ""
	ev.append(_notify("Equipado: %s" % it.name, rarity_color(bt, id)))
	return _ok(ev)


static func unequip(s: CharState, bt: BalanceTables, slot_name: String) -> Dictionary:
	if not s.equipment.has(slot_name):
		return _fail("slot_invalido")
	if s.equipment[slot_name] == "":
		return _fail("slot_vazio")
	add_item(s, bt, s.equipment[slot_name], 1)
	s.equipment[slot_name] = ""
	return _ok()


# ================================================================ consumo e caldeirão
## Tira 1 poção/comida/colheita da mochila. Cura, buff e recarga de comer ficam no cliente;
## o aviso de comida sai daqui para manter o texto num lugar só.
static func consume(s: CharState, bt: BalanceTables, id: String) -> Dictionary:
	var it := _item(bt, id)
	if it.is_empty():
		return _fail("item_invalido")
	var t: String = it.get("type", "")
	var edible := t == "food" or it.has("raw_hp") or it.has("raw_mp")
	if t != "consumable" and not edible:
		return _fail("nao_consumivel")
	if count_item(s, id) <= 0:
		return _fail("sem_item")
	remove_item(s, id, 1)
	var ev: Array = []
	if t != "consumable":
		if it.has("buff"):
			ev.append(_notify("%s: %s (%ds)" % [it.name, it.buff.name, int(it.buff.time)], it.get("color", Color(1, 0.85, 0.4))))
		else:
			ev.append(_notify("Comeu %s" % it.name, Color(0.85, 1.0, 0.7)))
	return _ok(ev)


static func can_cook(s: CharState, bt: BalanceTables, recipe: String) -> int:
	var ing: Dictionary = bt.get_table("recipes").get(recipe, {})
	if ing.is_empty():
		return 0
	var n := 999
	for id in ing:
		n = mini(n, count_item(s, id) / int(ing[id]))
	return n


## Cozinha até `times` vezes (o que os ingredientes deixarem). Resultado traz "n" = quantas.
static func cook(s: CharState, bt: BalanceTables, recipe: String, times = 1) -> Dictionary:
	if not _valid_count(times):
		return _fail("args")
	var ing: Dictionary = bt.get_table("recipes").get(recipe, {})
	if ing.is_empty():
		return _fail("receita_invalida")
	var n: int = mini(times, can_cook(s, bt, recipe))
	if n <= 0:
		var r := _fail("faltam_ingredientes", [_notify("Faltam ingredientes.", Color(1, 0.6, 0.5))])
		r["n"] = 0
		return r
	for id in ing:
		remove_item(s, id, int(ing[id]) * n)
	add_item(s, bt, recipe, n)
	var res := _ok([{"t": "looted", "id": recipe, "qty": n}])
	res["n"] = n
	return res


# ================================================================ missões
static func quest_state(s: CharState, id: String) -> String:
	return s.quests[id].state if s.quests.has(id) else "none"


## Cadeia de missões = ordem das chaves em quests.json.
static func start_quest(s: CharState, bt: BalanceTables, id: String) -> Dictionary:
	var qt := bt.get_table("quests")
	if not qt.has(id):
		return _fail("missao_invalida")
	if quest_state(s, id) != "none":
		return _fail("missao_indisponivel")
	var order: Array = qt.keys()
	var i := order.find(id)
	if i > 0 and quest_state(s, order[i - 1]) != "done":
		return _fail("missao_indisponivel")
	s.quests[id] = {"state": "active", "progress": 0}
	return _ok([_notify("Nova missão: %s" % qt[id].name, C_QUEST), {"t": "quest"}])


static func complete_quest(s: CharState, bt: BalanceTables, id: String) -> Dictionary:
	var qt := bt.get_table("quests")
	if not qt.has(id):
		return _fail("missao_invalida")
	if quest_state(s, id) != "ready":
		return _fail("missao_nao_pronta")
	var q: Dictionary = qt[id]
	var ev: Array = []
	s.quests[id].state = "done"
	ev.append(_notify("Missão concluída: %s" % q.name, C_QUEST))
	s.gold += int(q.reward_gold)
	ev.append(_notify("+%d ouro" % int(q.reward_gold), C_GOLD))
	for item in q.reward_items:
		add_item(s, bt, item, int(q.reward_items[item]))
		ev.append({"t": "looted", "id": item, "qty": int(q.reward_items[item])})
	_add_xp(s, bt, int(q.reward_xp), ev)
	ev.append({"t": "quest"})
	return _ok(ev)


# ================================================================ horta (por relógio)
static func default_farm(bt: BalanceTables) -> Dictionary:
	var fr := _farm_rules(bt)
	var plots: Array = []
	for i in int(fr.get("plots", 12)):
		plots.append(_empty_plot())
	return {"unlocked": int(fr.get("start", 6)), "plots": plots}


static func _empty_plot() -> Dictionary:
	return {"crop": "", "growth": 0.0, "t": 0.0, "watered": false, "fert": false}


## Canteiro de fonte não confiável -> canteiro bem formado (tipo errado vira o padrão).
## `now` = "t" para canteiro sem relógio (save antigo).
static func sanitize_plot(p, now: float) -> Dictionary:
	if not (p is Dictionary):
		return _empty_plot()
	var crop = p.get("crop")
	var g = p.get("growth")
	var t = p.get("t")
	return {"crop": crop if crop is String else "",
		"growth": clampf(float(g), 0.0, 1.0) if (g is int or (g is float and is_finite(g))) else 0.0,
		"t": float(t) if (t is int or (t is float and is_finite(t))) else now,
		"watered": p.get("watered") is bool and p.watered, "fert": p.get("fert") is bool and p.fert}


## Ajusta uma horta vinda de save (número de canteiros, faixa de abertos, cultura desconhecida).
static func _ensure_farm(s: CharState, bt: BalanceTables) -> void:
	var fr := _farm_rules(bt)
	var total := int(fr.get("plots", 12))
	if not (s.farm.get("plots") is Array):
		s.farm = default_farm(bt)
		return
	while s.farm.plots.size() < total:
		s.farm.plots.append(_empty_plot())
	if s.farm.plots.size() > total:
		s.farm.plots.resize(total)
	var u = s.farm.get("unlocked")
	s.farm.unlocked = clampi(u if u is int else (int(u) if u is float and is_finite(u) and absf(u) < 1e9 else 0),
		int(fr.get("start", 6)), total)
	var crops := bt.get_table("crops")
	var now := Time.get_unix_time_from_system()
	for i in total:
		var p := sanitize_plot(s.farm.plots[i], now)
		if p.crop != "" and not crops.has(p.crop):
			p = _empty_plot()
		s.farm.plots[i] = p


## Roda uma op da horta sobre a horta normalizada; se a op falhar, devolve a horta como estava
## (a normalização também é mutação: só vale se a op deu certo).
static func _farm_op(s: CharState, bt: BalanceTables, op: Callable) -> Dictionary:
	var backup: Dictionary = s.farm.duplicate(true)
	_ensure_farm(s, bt)
	var r: Dictionary = op.call()
	if not r.ok:
		s.farm = backup
	return r


## Crescimento de um canteiro no instante `now` (unix s). O cliente usa a mesma função para desenhar.
static func farm_growth(p: Dictionary, bt: BalanceTables, now: float) -> float:
	if str(p.get("crop", "")) == "":
		return 0.0
	var c: Dictionary = bt.get_table("crops").get(p.crop, {})
	var time := float(c.get("time", 1.0))
	var mult := float(_farm_rules(bt).get("water_mult", 2)) if p.get("watered", false) else 1.0
	var dt := maxf(0.0, now - float(p.get("t", now)))
	return minf(1.0, float(p.get("growth", 0.0)) + dt / time * mult)


static func plot_state(s: CharState, bt: BalanceTables, i: int, now: float) -> String:
	if i < 0 or i >= s.farm.plots.size():
		return "invalid"
	if i >= int(s.farm.unlocked):
		return "locked"
	var p: Dictionary = s.farm.plots[i]
	if p.crop == "":
		return "empty"
	return "ready" if farm_growth(p, bt, now) >= 1.0 else "growing"


## Grava no canteiro o crescimento até `now` (antes de mudar rega/adubo).
static func _settle(p: Dictionary, bt: BalanceTables, now: float) -> void:
	p.growth = farm_growth(p, bt, now)
	# relógio voltou para trás: não recua `t` (senão o mesmo intervalo contaria duas vezes)
	p.t = maxf(float(p.t), now)


static func _plot_err(st: String) -> String:
	match st:
		"invalid":
			return "canteiro_invalido"
		"locked":
			return "canteiro_trancado"
		"empty":
			return "canteiro_vazio"
		"ready":
			return "ja_pronto"
	return "canteiro_ocupado"


static func unlock_cost(s: CharState, bt: BalanceTables) -> int:
	var fr := _farm_rules(bt)
	return int(fr.unlock_base) + int(fr.unlock_step) * (int(s.farm.unlocked) - int(fr.start))


static func unlock_plot(s: CharState, bt: BalanceTables) -> Dictionary:
	return _farm_op(s, bt, func(): return _unlock_plot(s, bt))


static func _unlock_plot(s: CharState, bt: BalanceTables) -> Dictionary:
	if int(s.farm.unlocked) >= s.farm.plots.size():
		return _fail("horta_cheia")
	var cost := unlock_cost(s, bt)
	if s.gold < cost:
		return _fail("ouro_insuficiente", [_notify("Ouro insuficiente (%d)." % cost, C_BAD)])
	s.gold -= cost
	s.farm.unlocked += 1
	return _ok([_notify("Novo canteiro preparado!", C_FARM), {"t": "farm"}])


## Planta no canteiro i. Se faltar semente e buy_missing, compra uma.
static func plant(s: CharState, bt: BalanceTables, i: int, crop: String, buy_missing: bool, now: float) -> Dictionary:
	return _farm_op(s, bt, func(): return _plant(s, bt, i, crop, buy_missing, now))


static func _plant(s: CharState, bt: BalanceTables, i: int, crop: String, buy_missing: bool, now: float) -> Dictionary:
	var crops := bt.get_table("crops")
	if not crops.has(crop):
		return _fail("cultura_invalida")
	var st := plot_state(s, bt, i, now)
	if st != "empty":
		return _fail(_plot_err(st) if st != "growing" else "canteiro_ocupado")
	var seed_id: String = crops[crop].seed
	if count_item(s, seed_id) <= 0:
		if not buy_missing:
			return _fail("sem_semente")
		var price := int(_item(bt, seed_id).get("price", 0))
		if s.gold < price:
			return _fail("ouro_insuficiente", [_notify("Ouro insuficiente para a semente.", C_BAD)])
		s.gold -= price
	else:
		remove_item(s, seed_id, 1)
	s.farm.plots[i] = {"crop": crop, "growth": 0.0, "t": now, "watered": false, "fert": false}
	return _ok([{"t": "farm"}])


static func water(s: CharState, bt: BalanceTables, i: int, now: float) -> Dictionary:
	return _farm_op(s, bt, func(): return _water(s, bt, i, now))


static func _water(s: CharState, bt: BalanceTables, i: int, now: float) -> Dictionary:
	var st := plot_state(s, bt, i, now)
	if st != "growing":
		return _fail(_plot_err(st))
	var p: Dictionary = s.farm.plots[i]
	if p.watered:
		return _fail("ja_regado")
	_settle(p, bt, now)
	p.watered = true
	return _ok([{"t": "farm"}])


## Adubo de gel de slime: +fert_bonus de crescimento na hora (uma vez por plantio).
static func fertilize(s: CharState, bt: BalanceTables, i: int, now: float) -> Dictionary:
	return _farm_op(s, bt, func(): return _fertilize(s, bt, i, now))


static func _fertilize(s: CharState, bt: BalanceTables, i: int, now: float) -> Dictionary:
	var st := plot_state(s, bt, i, now)
	if st != "growing":
		return _fail(_plot_err(st))
	var p: Dictionary = s.farm.plots[i]
	if p.fert:
		return _fail("ja_adubado")
	if count_item(s, "slime_gel") <= 0:
		return _fail("sem_adubo")
	remove_item(s, "slime_gel", 1)
	_settle(p, bt, now)
	p.fert = true
	p.growth = minf(1.0, float(p.growth) + float(_farm_rules(bt).get("fert_bonus", 0.4)))
	return _ok([{"t": "farm"}])


## Colhe o canteiro i. O resultado traz "harvest" = {"crop", "qty", "bonus", "seed"}.
static func harvest(s: CharState, bt: BalanceTables, i: int, now: float, rng: RandomNumberGenerator) -> Dictionary:
	return _farm_op(s, bt, func(): return _harvest(s, bt, i, now, rng))


static func _harvest(s: CharState, bt: BalanceTables, i: int, now: float, rng: RandomNumberGenerator) -> Dictionary:
	var st := plot_state(s, bt, i, now)
	if st != "ready":
		return _fail("nao_pronto" if st == "growing" else _plot_err(st))
	var fr := _farm_rules(bt)
	var p: Dictionary = s.farm.plots[i]
	var c: Dictionary = bt.get_table("crops")[p.crop]
	var qty := rng.randi_range(int(c.yield[0]), int(c.yield[1])) + (1 if p.watered else 0)
	var bonus := rng.randf() < float(fr.get("bonus_chance", 0.12))
	if bonus:
		qty *= 2
	var got_seed := rng.randf() < float(fr.get("seed_back", 0.35))
	add_item(s, bt, p.crop, qty)
	if got_seed:
		add_item(s, bt, c.seed, 1)
	var res := {"crop": p.crop, "qty": qty, "bonus": bonus, "seed": got_seed}
	s.farm.plots[i] = _empty_plot()
	var txt := "+%d %s" % [qty, c.name]
	if bonus:
		txt = "Colheita farta! " + txt
	if got_seed:
		txt += " (+1 semente)"
	var out := _ok([_notify(txt, Color(0.85, 1.0, 0.55)), {"t": "farm"}])
	out["harvest"] = res
	return out


# ================================================================ passivas permanentes (Ecos)
## Compra o próximo nível de uma passiva permanente com Ecos. O custo do nível N é cost[N-1].
static func buy_passive(s: CharState, bt: BalanceTables, id: String) -> Dictionary:
	var def: Dictionary = bt.get_table("meta_passives").get("passives", {}).get(id, {})
	if def.is_empty():
		return _fail("passiva_invalida")
	var costs: Array = def.get("cost", [])
	var level := int(s.passives.get(id, 0))
	if level >= costs.size():
		return _fail("nivel_maximo")
	var cost := int(costs[level])
	if s.ecos < cost:
		return _fail("sem_ecos")
	s.ecos -= cost
	s.passives[id] = level + 1
	return _ok([{"t": "passive", "id": id, "level": level + 1}])


## Bônus das passivas permanentes: modificador -> soma de (add * nível). Id desconhecido é ignorado.
static func meta_mods(bt: BalanceTables, passives: Dictionary) -> Dictionary:
	var out := {}
	var table: Dictionary = bt.get_table("meta_passives").get("passives", {})
	for id in passives:
		if not table.has(id):
			continue
		var add: Dictionary = table[id].get("add", {})
		for k in add:
			out[k] = out.get(k, 0.0) + float(add[k]) * int(passives[id])
	return out
