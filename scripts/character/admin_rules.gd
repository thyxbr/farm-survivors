class_name AdminRules
extends RefCounted
## Modo admin, regras puras (servidor e solo rodam o mesmo código; ver CharRules).
## Ligado, o personagem fica com recursos "infinitos": antes de cada operação o ouro, os Ecos e os
## itens empilháveis de recurso (materiais, essências, sementes, colheita, comida, poções) voltam ao teto,
## então comprar, encantar, cozinhar, plantar e comprar passiva nunca falta nada.
## Ao ligar, guarda o que o personagem tinha em s.flags["admin"]; ao desligar, devolve exatamente
## isso (o que foi comprado/encantado/desbloqueado enquanto ligado fica).
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
	var changed := s.gold != GOLD or s.ecos != ECOS
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
		return CharRules._ok([CharRules._notify("Modo admin LIGADO: recursos infinitos.", CharRules.C_GOLD)])
	var snap: Dictionary = s.flags[FLAG]
	s.flags.erase(FLAG)
	s.gold = maxi(0, int(snap.get("gold", 0)))
	s.ecos = maxi(0, int(snap.get("ecos", 0)))
	var had: Dictionary = snap.get("items", {}) if snap.get("items") is Dictionary else {}
	for id in resource_ids(bt):
		_set_count(s, bt, id, maxi(0, int(had.get(id, 0))))
	return CharRules._ok([CharRules._notify("Modo admin desligado: recursos de volta ao que eram.", CharRules.C_GUILD)])


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
