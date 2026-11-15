class_name FriendStore
extends RefCounted
## Amigos das contas, no banco (tabela `friends`, migração v6). Sem autoload: roda no teste unitário.
##
## Pedido de amizade: quem pede fica com "out", quem recebe com "in"; aceitar vira "accepted" dos dois lados.
## Pedir para quem já tinha pedido para você aceita na hora. Recusar, cancelar e desfazer apagam as duas
## linhas. Os métodos que mudam algo devolvem {"ok", "err", "id"} (id = a outra conta; err em `explain`).

const MAX_FRIENDS := 50

var _db: Db


func _init(db: Db) -> void:
	_db = db


## Pede amizade a `name` (nome da conta, sem diferenciar maiúsculas).
func request(from: int, name: String) -> Dictionary:
	var rows := _db.query("SELECT id FROM accounts WHERE username = ?", [name.strip_edges()])
	if rows.is_empty():
		return _fail("sem_conta")
	var to := int(rows[0].id)
	if to == from:
		return _fail("voce_mesmo", to)
	var st := state(from, to)
	if st == "accepted":
		return _fail("ja_amigos", to)
	if st == "out":
		return _fail("pedido_pendente", to)
	if st == "in":
		return accept(from, to)
	if _count(from) >= MAX_FRIENDS or _count(to) >= MAX_FRIENDS:
		return _fail("limite", to)
	var now := int(Time.get_unix_time_from_system())
	var ok := _db.transaction(func():
		return _db.exec("INSERT INTO friends(account_id, friend_id, state, since) VALUES(?,?,?,?)", [from, to, "out", now]) \
			and _db.exec("INSERT INTO friends(account_id, friend_id, state, since) VALUES(?,?,?,?)", [to, from, "in", now]))
	return {"ok": ok, "err": "" if ok else "banco", "id": to, "accepted": false}


## Aceita o pedido que `other` mandou para `me`.
func accept(me: int, other: int) -> Dictionary:
	if state(me, other) != "in":
		return _fail("sem_pedido", other)
	var now := int(Time.get_unix_time_from_system())
	var ok := _db.transaction(func():
		return _db.exec("UPDATE friends SET state = 'accepted', since = ? WHERE account_id = ? AND friend_id = ?", [now, me, other]) \
			and _db.exec("UPDATE friends SET state = 'accepted', since = ? WHERE account_id = ? AND friend_id = ?", [now, other, me]))
	return {"ok": ok, "err": "" if ok else "banco", "id": other, "accepted": true}


## Recusa um pedido recebido, cancela um enviado ou desfaz a amizade (apaga os dois lados).
func remove(me: int, other: int) -> Dictionary:
	if state(me, other) == "":
		return _fail("sem_relacao", other)
	var ok := _db.transaction(func():
		return _db.exec("DELETE FROM friends WHERE account_id = ? AND friend_id = ?", [me, other]) \
			and _db.exec("DELETE FROM friends WHERE account_id = ? AND friend_id = ?", [other, me]))
	return {"ok": ok, "err": "" if ok else "banco", "id": other}


## "accepted", "out", "in" ou "" (nenhuma relação) do ponto de vista de `me`.
func state(me: int, other: int) -> String:
	var rows := _db.query("SELECT state FROM friends WHERE account_id = ? AND friend_id = ?", [me, other])
	return str(rows[0].state) if not rows.is_empty() else ""


## Amigos e pedidos de `me`: [{"id", "name", "state", "since", "last_login"}], por nome.
func list(me: int) -> Array:
	var out: Array = []
	for r in _db.query("SELECT f.friend_id AS id, a.username AS name, f.state AS state, f.since AS since, "
			+ "COALESCE(a.last_login, 0) AS last_login FROM friends f JOIN accounts a ON a.id = f.friend_id "
			+ "WHERE f.account_id = ? ORDER BY a.username COLLATE NOCASE", [me]):
		out.append({"id": int(r.id), "name": str(r.name), "state": str(r.state), "since": int(r.since),
			"last_login": int(r.last_login)})
	return out


## Contas amigas (aceitas) de `me`.
func friend_ids(me: int) -> Array:
	var out: Array = []
	for r in _db.query("SELECT friend_id FROM friends WHERE account_id = ? AND state = 'accepted'", [me]):
		out.append(int(r.friend_id))
	return out


func _count(me: int) -> int:
	var rows := _db.query("SELECT COUNT(*) AS n FROM friends WHERE account_id = ?", [me])
	return int(rows[0].n) if not rows.is_empty() else 0


static func _fail(err: String, id := 0) -> Dictionary:
	return {"ok": false, "err": err, "id": id}


static func explain(err: String) -> String:
	match err:
		"sem_conta": return "Não existe jogador com esse nome."
		"voce_mesmo": return "Você não pode adicionar a si mesmo."
		"ja_amigos": return "Vocês já são amigos."
		"pedido_pendente": return "O pedido de amizade já foi enviado: falta ele aceitar."
		"limite": return "Limite de %d amigos e pedidos atingido." % MAX_FRIENDS
		"sem_pedido": return "Esse pedido de amizade não existe mais."
		"sem_relacao": return "Esse jogador não está na sua lista."
		"banco": return "Não foi possível salvar agora. Tente de novo."
	return err
