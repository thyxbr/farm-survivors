extends RefCounted
## PickupRegistry: loot no chão do servidor (dono, coleta única, validade e distância).

var _t := [1000.0]


func _reg() -> PickupRegistry:
	_t[0] = 1000.0
	return PickupRegistry.new(func() -> float: return _t[0])


func test_claim_ok_returns_contents() -> void:
	var r := _reg()
	var id := r.spawn(7, "world", Vector3(10, 0, 10), 12, {"slime_gel": 2})
	T.ok(id > 0, "net_id positivo")
	var c := r.claim(id, 7, Vector3(11, 0, 10))
	T.eq(c.ok, true, "pegou")
	T.eq(c.gold, 12, "ouro")
	T.eq(c.items, {"slime_gel": 2}, "itens")


func test_ids_are_unique() -> void:
	var r := _reg()
	var a := r.spawn(7, "world", Vector3.ZERO, 1, {})
	var b := r.spawn(7, "world", Vector3.ZERO, 1, {})
	T.ok(a != b, "ids diferentes")


func test_wrong_owner() -> void:
	var r := _reg()
	var id := r.spawn(7, "world", Vector3.ZERO, 5, {})
	var c := r.claim(id, 8, Vector3.ZERO)
	T.eq(c.ok, false, "outro jogador não pega")
	T.eq(c.err, "dono", "erro dono")
	T.eq(r.claim(id, 7, Vector3.ZERO).ok, true, "o dono ainda pega")


func test_claim_twice() -> void:
	var r := _reg()
	var id := r.spawn(7, "world", Vector3.ZERO, 5, {})
	T.eq(r.claim(id, 7, Vector3.ZERO).ok, true, "1ª coleta")
	var c := r.claim(id, 7, Vector3.ZERO)
	T.eq(c.ok, false, "2ª coleta recusada")
	T.eq(c.err, "pego", "erro pego")
	T.eq(r.claim(9999, 7, Vector3.ZERO).err, "pego", "id desconhecido também é pego")


func test_expired_with_injected_clock() -> void:
	var r := _reg()
	var id := r.spawn(7, "world", Vector3.ZERO, 5, {}, 10.0)
	_t[0] += 9.0
	var keep := r.spawn(7, "world", Vector3.ZERO, 1, {}, 10.0)
	_t[0] += 2.0   # 11 s depois do primeiro, 2 s depois do segundo
	var c := r.claim(id, 7, Vector3.ZERO)
	T.eq(c.ok, false, "expirado recusado")
	T.eq(c.err, "expirou", "erro expirou")
	T.eq(r.claim(keep, 7, Vector3.ZERO).ok, true, "o outro ainda vale")
	# expirado some no purge
	var old := r.spawn(7, "world", Vector3.ZERO, 5, {}, 1.0)
	_t[0] += 5.0
	T.eq(r.purge_expired(), 1, "purge remove o expirado")
	T.eq(r.claim(old, 7, Vector3.ZERO).err, "pego", "depois do purge não existe mais")


func test_too_far() -> void:
	var r := _reg()
	var id := r.spawn(7, "world", Vector3(0, 0, 0), 5, {})
	var c := r.claim(id, 7, Vector3(5, 0, 0))
	T.eq(c.ok, false, "a 5 m não pega")
	T.eq(c.err, "longe", "erro longe")
	T.eq(r.claim(id, 7, Vector3(3.9, 0, 0)).ok, true, "a 3,9 m pega (continua no chão depois do longe)")
	var far := r.spawn(7, "world", Vector3.ZERO, 5, {})
	T.eq(r.claim(far, 7, Vector3.INF).err, "longe", "sem posição conhecida = longe")


func test_drop_peer() -> void:
	var r := _reg()
	var a := r.spawn(7, "world", Vector3.ZERO, 5, {})
	var b := r.spawn(7, "horde", Vector3.ZERO, 5, {})
	var c := r.spawn(8, "world", Vector3.ZERO, 5, {})
	r.drop_peer(7, "horde")
	T.eq(r.claim(b, 7, Vector3.ZERO).err, "pego", "drop_peer com zona tira só a zona")
	r.drop_peer(7)
	T.eq(r.claim(a, 7, Vector3.ZERO).err, "pego", "drop_peer tira os do peer")
	T.eq(r.claim(c, 8, Vector3.ZERO).ok, true, "os dos outros ficam")
	T.eq(r.size(), 0, "vazio")


func test_zone_of() -> void:
	var r := _reg()
	var id := r.spawn(7, "horde", Vector3.ZERO, 5, {})
	T.eq(r.zone_of(id), "horde", "zona do pickup")
	T.eq(r.zone_of(12345), "", "zona de id desconhecido")


func test_claim_pickup_is_not_client_op() -> void:
	T.ok(not ("claim_pickup" in CharacterService.CLIENT_OPS), "claim_pickup fora de CLIENT_OPS (RPC própria)")


## Concessão falhou depois do claim (erro no banco): o pickup volta igual e pode ser pego de novo.
func test_restore_after_failed_grant() -> void:
	var r := _reg()
	var id := r.spawn(7, "horde", Vector3(1, 0, 1), 9, {"slime_gel": 1}, 30.0)
	var c := r.claim(id, 7, Vector3(1, 0, 1))
	T.eq(c.ok, true, "claim")
	T.eq(r.claim(id, 7, Vector3(1, 0, 1)).err, "pego", "fora do registro depois do claim")
	r.restore(id, c.entry)
	T.eq(r.zone_of(id), "horde", "voltou com a zona")
	T.eq(r.claim(id, 8, Vector3(1, 0, 1)).err, "dono", "voltou com o dono")
	var again := r.claim(id, 7, Vector3(1, 0, 1))
	T.ok(again.ok and again.gold == 9 and again.items == {"slime_gel": 1}, "pego de novo com o mesmo conteúdo")
	r.restore(id, c.entry)
	_t[0] += 31.0
	T.eq(r.claim(id, 7, Vector3(1, 0, 1)).err, "expirou", "mantém a validade original")
