class_name AdminRules
extends RefCounted
## Modo admin, regras puras (servidor e solo rodam o mesmo código; ver CharRules).
## Ligado, o personagem fica com recursos "infinitos": antes de cada operação o ouro, os Ecos e os
## itens empilháveis de recurso (materiais, essências, sementes, colheita, comida, poções) voltam ao teto,
## então comprar, encantar, cozinhar, plantar e comprar passiva nunca falta nada.
## Ligado, o personagem também fica com tudo no máximo, para poder fazer qualquer coisa: nível máximo
## (com os pontos de atributo e de talento dos níveis que pulou), todas as profissões no nível máximo,
## todas as receitas conhecidas (CraftRules.knows) e qualquer rank da Guilda liberado
## (CharRules.rank_at_least); CharRules.equip também não cobra o nível do item.
## Ao ligar, guarda o que o personagem tinha em s.flags["admin"]; ao desligar, devolve exatamente
## isso (o que foi comprado/encantado/desbloqueado enquanto ligado fica). Nível, XP, atributos, pontos,
## talentos e profissões voltam ao que eram: o que foi distribuído no nível máximo não fica.
## Quem pode ligar é decidido fora daqui: no solo qualquer um; online, com OPEN_TO_ALL qualquer conta,
## senão só contas em ADMIN_USERS.

## Por enquanto todo mundo pode ligar o modo admin online. false = só contas em ADMIN_USERS.
const OPEN_TO_ALL := true

const FLAG := "admin"
const GOLD := 9999999
const ECOS := 999999
const ITEM_QTY := 999
## Tipos de item que contam como recurso (os empilháveis desses tipos são enchidos).
const RESOURCE_TYPES := ["material", "seed", "crop", "food", "consumable"]
## "Dar item": peças que não empilham entram no máximo esta quantidade por pedido (cada uma ocupa um espaço).
const GIVE_MAX_LOOSE := 10


static func is_on(s: CharState) -> bool:
	return s.flags.get(FLAG) is Dictionary


## Ids dos itens de recurso, em ordem estável.
static func resource_ids(bt: BalanceTables) -> Array:
	var items: Dictionary = bt.get_table("items")
	var out := []
	for id in items:
		var it = items[id]
		if it is Dictionary and str(it.get("type", "")) in RESOURCE_TYPES and bool(it.get("stack", false)):
			out.append(str(id))
	out.sort()
	return out


## Põe ouro, Ecos e recursos no teto (só se estiver ligado). true se mudou algo.
static func top_up(s: CharState, bt: BalanceTables) -> bool:
	if not is_on(s):
		return false
	# modo admin ligado antes de existir o nível máximo: guarda a progressão agora e sobe
	var changed: bool = not s.flags[FLAG].has("level")
	if changed:
		_max_out(s, bt)
	changed = changed or s.gold != GOLD or s.ecos != ECOS
	s.gold = GOLD
	s.ecos = ECOS
	for id in resource_ids(bt):
		if _set_count(s, bt, id, ITEM_QTY):
			changed = true
	return changed


## Liga ou desliga. Ligar guarda o que havia e enche; desligar devolve o que havia.
static func set_on(s: CharState, bt: BalanceTables, on: bool) -> Dictionary:
	if on == is_on(s):
		return CharRules._ok([CharRules._notify(
				"Modo admin já está %s." % ("ligado" if on else "desligado"), CharRules.C_GUILD)])
	if on:
		var snap := {"gold": s.gold, "ecos": s.ecos, "items": {}}
		for id in resource_ids(bt):
			var n := CharRules.count_item(s, id)
			if n > 0:
				snap.items[id] = n
		s.flags[FLAG] = snap
		top_up(s, bt)
		return CharRules._ok([
				CharRules._notify("Modo admin LIGADO: tudo no máximo e recursos infinitos.", CharRules.C_GOLD),
				{"t": "level_up", "level": s.level}])
	var snap: Dictionary = s.flags[FLAG]
	s.flags.erase(FLAG)
	s.gold = maxi(0, int(snap.get("gold", 0)))
	s.ecos = maxi(0, int(snap.get("ecos", 0)))
	var had: Dictionary = snap.get("items", {}) if snap.get("items") is Dictionary else {}
	for id in resource_ids(bt):
		_set_count(s, bt, id, maxi(0, int(had.get(id, 0))))
	_restore_progress(s, bt, snap)
	return CharRules._ok([CharRules._notify("Modo admin desligado: nível e recursos de volta ao que eram.", CharRules.C_GUILD)])


## Guarda nível, XP, pontos, atributos, talentos, rank e profissões no que foi guardado ao ligar e leva o
## personagem ao nível máximo, com os pontos de atributo dos níveis pulados (os de talento são calculados
## do nível), e todas as profissões ao nível máximo.
static func _max_out(s: CharState, bt: BalanceTables) -> void:
	var snap: Dictionary = s.flags[FLAG]
	snap["level"] = s.level
	snap["xp"] = s.xp
	snap["stat_points"] = s.stat_points
	snap["attributes"] = s.attributes.duplicate(true)
	snap["talents"] = s.talents.duplicate(true)
	snap["rank"] = CharRules.rank_index(bt, CharRules.rank_of(s))
	var profs := {}
	for id in s.professions:
		profs[id] = {"lv": int(s.professions[id].get("lv", 1)), "xp": int(s.professions[id].get("xp", 0))}
	snap["professions"] = profs
	for id in CraftRules.professions(bt):
		var e := CraftRules._entry(s, str(id))
		e.lv = CraftRules.max_level(bt)
		e.xp = 0
	var top := ProgressionRules.max_level(bt)
	if s.level < top:
		s.stat_points += (top - s.level) * int(CharRules._rules(bt).get("points_per_level", 3))
		s.level = top
	s.xp = 0


## Devolve a progressão guardada por _max_out. Os pontos de atributo de promoções da guilda ganhas
## com o modo ligado continuam (a promoção fica); o resto volta exatamente ao que era.
static func _restore_progress(s: CharState, bt: BalanceTables, snap: Dictionary) -> void:
	if not snap.has("level"):
		return
	s.level = clampi(int(snap.level), 1, ProgressionRules.max_level(bt))
	s.xp = maxi(0, int(snap.get("xp", 0)))
	s.stat_points = maxi(0, int(snap.get("stat_points", 0)))
	var all_ranks := CharRules.ranks(bt)
	var now := mini(CharRules.rank_index(bt, CharRules.rank_of(s)), all_ranks.size() - 1)
	for i in range(int(snap.get("rank", now)) + 1, now + 1):
		s.stat_points += int(all_ranks[i].get("stat_points", 0))
	var attrs = snap.get("attributes")
	if attrs is Dictionary:
		for k in s.attributes:
			s.attributes[k] = maxi(1, int(attrs.get(k, s.attributes[k])))
	var tal = snap.get("talents")
	s.talents = {}
	if tal is Dictionary:
		for id in tal:
			s.talents[str(id)] = int(tal[id])
	# profissões: nível e XP de antes; as receitas já feitas uma vez ("done") continuam
	var profs: Dictionary = snap.get("professions", {}) if snap.get("professions") is Dictionary else {}
	for id in s.professions.keys():
		var e: Dictionary = s.professions[id]
		if profs.get(id) is Dictionary:
			e.lv = clampi(int(profs[id].get("lv", 1)), 1, CraftRules.max_level(bt))
			e.xp = maxi(0, int(profs[id].get("xp", 0)))
		elif e.get("done", []).is_empty():
			s.professions.erase(id)
		else:
			e.lv = 1
			e.xp = 0


## Põe `qty` de um item qualquer na mochila (menu "Adicionar item" e /item). Só com o modo admin ligado.
## Enquanto ligado, CharRules.equip também não cobra o nível do item, para dar para testar a peça.
static func give(s: CharState, bt: BalanceTables, id: String, qty: int) -> Dictionary:
	if not is_on(s):
		return CharRules._fail("sem_admin", [CharRules._notify("Ligue o modo admin para adicionar itens.", CharRules.C_BAD)])
	var it = bt.get_table("items").get(id)
	if not (it is Dictionary):
		return CharRules._fail("item_desconhecido", [CharRules._notify("Item desconhecido: %s" % id, CharRules.C_BAD)])
	var n := clampi(qty, 1, ITEM_QTY if bool(it.get("stack", false)) else GIVE_MAX_LOOSE)
	CharRules.add_item(s, bt, id, n)
	return CharRules._ok([{"t": "looted", "id": id, "qty": n}])


## Deixa exatamente `n` de `id` na mochila. true se mudou.
static func _set_count(s: CharState, bt: BalanceTables, id: String, n: int) -> bool:
	var have := CharRules.count_item(s, id)
	if have == n:
		return false
	if have < n:
		CharRules.add_item(s, bt, id, n - have)
	else:
		CharRules.remove_item(s, id, have - n)
	return true
