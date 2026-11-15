extends RefCounted
## FriendStore: pedido, aceitar, pedido cruzado, recusar/desfazer e a lista, com SQLite de verdade em user://.

const PATH := "user://test_friends.db"


func _fresh() -> Array:
	Db.remove_files(PATH)
	var db := Db.open(PATH)
	Migrations.apply(db)
	var ids := []
	for n in ["Ana", "Beto", "Caio"]:
		db.exec("INSERT INTO accounts(username, pass_hash, pass_salt, created_at, last_login) VALUES(?,?,?,?,?)", [n, "h", "s", 1, 100])
		ids.append(db.last_id())
	return [db, FriendStore.new(db), ids]


func test_request_then_accept() -> void:
	var f: Array = _fresh()
	var fs: FriendStore = f[1]
	var ana: int = f[2][0]
	var beto: int = f[2][1]
	var r := fs.request(ana, "beto")
	T.ok(r.ok and r.id == beto and not r.accepted, "pedido pelo nome, sem diferenciar maiúsculas")
	T.eq(fs.state(ana, beto), "out", "Ana mandou")
	T.eq(fs.state(beto, ana), "in", "Beto recebeu")
	T.eq(fs.request(ana, "Beto").err, "pedido_pendente", "pedido repetido")
	T.ok(fs.accept(beto, ana).ok, "Beto aceita")
	T.eq(fs.state(ana, beto), "accepted", "amigos dos dois lados")
	T.eq(fs.friend_ids(ana), [beto], "amigos da Ana")
	T.eq(fs.request(ana, "Beto").err, "ja_amigos", "já são amigos")
	f[0].close()


func test_crossed_request_accepts() -> void:
	var f: Array = _fresh()
	var fs: FriendStore = f[1]
	var ana: int = f[2][0]
	var beto: int = f[2][1]
	fs.request(ana, "Beto")
	var r := fs.request(beto, "Ana")
	T.ok(r.ok and r.accepted, "pedir de volta aceita na hora")
	T.eq(fs.state(beto, ana), "accepted", "amigos")
	f[0].close()


func test_errors() -> void:
	var f: Array = _fresh()
	var fs: FriendStore = f[1]
	var ana: int = f[2][0]
	var beto: int = f[2][1]
	T.eq(fs.request(ana, "Zé").err, "sem_conta", "nome que não existe")
	T.eq(fs.request(ana, "ana").err, "voce_mesmo", "a si mesmo")
	T.eq(fs.accept(ana, beto).err, "sem_pedido", "aceitar sem pedido")
	fs.request(ana, "Beto")
	T.eq(fs.accept(ana, beto).err, "sem_pedido", "quem pediu não aceita o próprio pedido")
	T.eq(fs.remove(ana, f[2][2]).err, "sem_relacao", "remover quem não está na lista")
	f[0].close()


func test_remove_clears_both_sides_and_list_shape() -> void:
	var f: Array = _fresh()
	var fs: FriendStore = f[1]
	var ana: int = f[2][0]
	var beto: int = f[2][1]
	var caio: int = f[2][2]
	fs.request(ana, "Beto")
	fs.accept(beto, ana)
	fs.request(caio, "Ana")
	var l := fs.list(ana)
	T.eq(l.size(), 2, "um amigo e um pedido recebido")
	T.eq(l[0].name, "Beto", "ordem por nome")
	T.eq(l[0].state, "accepted", "Beto amigo")
	T.eq(l[1].state, "in", "pedido do Caio")
	T.eq(l[1].last_login, 100, "último acesso")
	T.ok(fs.remove(ana, caio).ok, "recusa o pedido")
	T.eq(fs.state(caio, ana), "", "o pedido some dos dois lados")
	T.ok(fs.remove(beto, ana).ok, "desfaz a amizade")
	T.eq(fs.list(ana), [], "lista vazia")
	f[0].close()
