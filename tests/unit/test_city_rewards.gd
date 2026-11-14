extends RefCounted
## RewardRules.city_by_account: o resumo do fim da Defesa em grupo soma o acumulado de cada peer por conta
## (Ecos pelas noites em que a conta esteve na cidade).

var _bt: BalanceTables


func _tables() -> BalanceTables:
	if _bt == null:
		_bt = BalanceTables.load_dir("res://data/balance")
	return _bt


func test_late_joiner_has_fewer_nights() -> void:
	var rewards := {
		10: {"account": 1, "gold": 50, "xp": 90, "items": [], "nights": 3},
		11: {"account": 2, "gold": 15, "xp": 30, "items": [], "nights": 1},   # entrou no meio
	}
	var by := RewardRules.city_by_account(rewards)
	T.eq(by.size(), 2, "uma linha por conta")
	T.eq(by[1].nights, 3, "quem começou viu as 3 noites")
	T.eq(by[2].nights, 1, "quem entrou no meio só a noite em que esteve")
	T.eq(by[2].peers, [11], "peer da conta 2")
	T.eq(RewardRules.ecos(_tables(), "city", by[2].nights), RewardRules.ecos(_tables(), "city", 1),
		"Ecos do atrasado pelas noites dele")


func test_two_peers_same_account_are_summed() -> void:
	# caiu no meio (peer 20) e voltou (peer 21): uma conta só, noites, ouro, XP e itens somados
	var rewards := {
		20: {"account": 5, "gold": 15, "xp": 30, "items": ["health_potion"], "nights": 1},
		21: {"account": 5, "gold": 21, "xp": 55, "items": ["health_potion", "iron_sword"], "nights": 2},
	}
	var by := RewardRules.city_by_account(rewards)
	T.eq(by.size(), 1, "uma conta")
	T.eq(by[5].nights, 3, "noites somadas")
	T.eq(by[5].gold, 36, "ouro somado")
	T.eq(by[5].xp, 85, "XP somado")
	T.eq(by[5].items, {"health_potion": 2, "iron_sword": 1}, "itens contados")
	var peers: Array = by[5].peers
	peers.sort()
	T.eq(peers, [20, 21], "os dois peers recebem o resultado")


func test_dropped_before_dawn_counts_zero() -> void:
	# caiu antes do primeiro amanhecer: a conta fecha a partida com 0 noites (0 Ecos)
	var by := RewardRules.city_by_account({30: {"account": 7, "gold": 0, "xp": 0, "items": [], "nights": 0}})
	T.eq(by[7].nights, 0, "nenhuma noite")
	T.eq(RewardRules.ecos(_tables(), "city", by[7].nights), 0, "0 Ecos")


func test_no_account_is_skipped() -> void:
	var by := RewardRules.city_by_account({40: {"account": 0, "gold": 5, "xp": 5, "items": [], "nights": 2}})
	T.ok(by.is_empty(), "peer sem conta fica de fora")
