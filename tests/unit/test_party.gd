extends RefCounted
## Grupos do multiplayer: PartyBook (convite, aceitar, sair, expulsar, líder) e PartyRules.kill_rewards
## (XP dividido entre o grupo na zona; abate e missão só para quem está perto do combate).


func _pair() -> PartyBook:
	var b := PartyBook.new()
	b.invite(1, 2)
	b.accept(2)
	return b


func test_invite_accept_creates_party_with_inviter_as_leader() -> void:
	var b := PartyBook.new()
	T.eq(b.invite(1, 2), "", "convite aceito")
	T.ok(not b.in_party(1), "ninguém em grupo antes de aceitar")
	T.eq(b.accept(2), "", "aceitou")
	T.eq(b.members(1), [1, 2], "grupo com os dois")
	T.eq(b.members(2), [1, 2], "o mesmo grupo visto pelo convidado")
	T.eq(b.leader(2), 1, "quem convidou lidera")


func test_only_leader_invites_and_party_has_a_cap() -> void:
	var b := _pair()
	T.eq(b.invite(2, 3), "nao_lider", "membro comum não convida")
	T.eq(b.invite(1, 3), "", "líder convida")
	T.eq(b.accept(3), "", "3 entrou")
	b.invite(1, 4)
	b.accept(4)
	T.eq(b.members(1).size(), PartyBook.MAX_MEMBERS, "grupo cheio")
	T.eq(b.invite(1, 5), "cheio", "não passa do máximo")


func test_cannot_invite_someone_in_another_party_or_twice() -> void:
	var b := _pair()
	b.invite(3, 4)
	T.eq(b.invite(5, 4), "convite_pendente", "um convite por vez")
	b.accept(4)
	T.eq(b.invite(1, 3), "ja_em_grupo", "3 já tem grupo")
	T.eq(b.invite(1, 2), "ja_no_seu_grupo", "2 já é do grupo")
	T.eq(b.invite(1, 1), "voce_mesmo", "a si mesmo não")


func test_decline_and_expiry() -> void:
	var b := PartyBook.new()
	b.invite(1, 2)
	T.eq(b.decline(2), 1, "recusou o convite de 1")
	T.eq(b.accept(2), "sem_convite", "nada para aceitar")
	b.invite(1, 2)
	T.eq(b.tick(PartyBook.INVITE_TIME + 1.0), [2], "o convite expira")
	T.eq(b.accept(2), "sem_convite", "expirado")


func test_leader_leaving_passes_lead_and_two_member_party_dissolves() -> void:
	var b := _pair()
	b.invite(1, 3)
	b.accept(3)
	T.eq(b.leave(1), "", "líder saiu")
	T.eq(b.leader(2), 2, "liderança passa para o próximo")
	T.eq(b.members(3), [2, 3], "os dois ficam")
	b.leave(3)
	T.ok(not b.in_party(2), "grupo de um só se desfaz")
	T.eq(b.parties.size(), 0, "sem grupos")


func test_kick_only_by_leader() -> void:
	var b := _pair()
	b.invite(1, 3)
	b.accept(3)
	T.eq(b.kick(2, 3), "nao_lider", "membro não expulsa")
	T.eq(b.kick(1, 3), "", "líder expulsa")
	T.eq(b.members(1), [1, 2], "3 saiu")
	T.eq(b.kick(1, 9), "fora_do_grupo", "quem não é do grupo")


func test_drop_clears_party_and_invites() -> void:
	var b := _pair()
	b.invite(1, 3)
	b.drop(1)
	T.ok(not b.in_party(2), "grupo de dois se desfez")
	T.ok(not b.invites.has(3), "o convite de quem saiu some")


func test_solo_kill_keeps_full_xp() -> void:
	var r := PartyRules.kill_rewards(30, [1], {}, {1: Vector3.ZERO}, {1: "world"}, Vector3.ZERO, "world")
	T.eq(r, {1: {"xp": 30, "kill": true, "loot": true}}, "sem grupo: tudo para quem matou")


func test_party_splits_xp_and_far_member_gets_no_quest_credit() -> void:
	var teams := {1: [1, 2, 3], 2: [1, 2, 3], 3: [1, 2, 3]}
	var pos := {1: Vector3(0, 0, 0), 2: Vector3(10, 5, 10), 3: Vector3(300, 0, 0)}
	var zones := {1: "world", 2: "world", 3: "world"}
	var r := PartyRules.kill_rewards(30, [1], teams, pos, zones, Vector3(2, 0, 0), "world")
	T.eq(r.size(), 3, "os três recebem XP")
	T.eq(r[1].xp, 10, "XP dividido em 3")
	T.eq(r[2].xp, 10, "XP dividido em 3")
	T.ok(r[1].kill and r[1].loot, "quem matou conta o abate e sorteia loot")
	T.ok(r[2].kill and not r[2].loot, "perto: conta o abate (missão), sem loot próprio")
	T.ok(not r[3].kill, "longe: não conta na missão")
	T.eq(r[3].xp, 10, "longe ainda divide o XP")


func test_party_member_in_other_zone_is_left_out_and_rounding_up() -> void:
	var teams := {1: [1, 2, 3], 2: [1, 2, 3], 3: [1, 2, 3]}
	var zones := {1: "world", 2: "world", 3: "city"}
	var pos := {1: Vector3.ZERO, 2: Vector3(1, 0, 0), 3: Vector3.ZERO}
	var r := PartyRules.kill_rewards(25, [1], teams, pos, zones, Vector3.ZERO, "world")
	T.ok(not r.has(3), "quem está na cidade fica de fora")
	T.eq(r[1].xp, 13, "25 entre 2, arredondado para cima")


func test_two_hitters_same_party_share_one_pool() -> void:
	var teams := {1: [1, 2], 2: [1, 2]}
	var pos := {1: Vector3.ZERO, 2: Vector3.ZERO, 5: Vector3.ZERO}
	var zones := {1: "world", 2: "world", 5: "world"}
	var r := PartyRules.kill_rewards(40, [1, 2, 5], teams, pos, zones, Vector3.ZERO, "world")
	T.eq(r[1].xp, 20, "um pote só para o grupo")
	T.eq(r[2].xp, 20, "um pote só para o grupo")
	T.ok(r[1].loot and r[2].loot, "os dois acertaram: os dois sorteiam loot")
	T.eq(r[5], {"xp": 40, "kill": true, "loot": true}, "quem está fora do grupo ganha o XP inteiro")


func test_unknown_position_counts_as_far() -> void:
	T.ok(not PartyRules.near(null, Vector3.ZERO), "sem posição = longe")
	T.ok(not PartyRules.near(Vector3.INF, Vector3.ZERO), "posição infinita = longe")
	T.ok(PartyRules.near(Vector3(PartyRules.SHARE_RANGE - 1, 50, 0), Vector3.ZERO), "altura não conta")
