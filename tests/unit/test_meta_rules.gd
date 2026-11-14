extends RefCounted
## Ecos, passivas permanentes e base compartilhada: regras puras com as tabelas reais.

var _bt: BalanceTables


func _tables() -> BalanceTables:
	if _bt == null:
		_bt = BalanceTables.load_dir("res://data/balance")
	return _bt


func _blank(ecos := 0) -> CharState:
	var s := CharState.new_character(_tables())
	s.ecos = ecos
	return s


func test_ecos_curve() -> void:
	var bt := _tables()
	T.eq(RewardRules.ecos(bt, "horde", 10), 50, "horde 10 rodadas")
	T.eq(RewardRules.ecos(bt, "city", 5), 45, "city 5 noites")
	T.eq(RewardRules.ecos(bt, "city", 0), 0, "nada alcançado")
	T.eq(RewardRules.ecos(bt, "xyz", 9), 0, "modo desconhecido")


func test_buy_passive_levels_and_cost() -> void:
	var bt := _tables()
	var s := _blank(100)
	var r := CharRules.buy_passive(s, bt, "poder")
	T.ok(r.ok, "compra nível 1")
	T.eq(s.ecos, 75, "custou 25")
	T.eq(s.passives["poder"], 1, "nível 1")
	T.ok(CharRules.buy_passive(s, bt, "poder").ok, "compra nível 2")
	T.eq(s.ecos, 30, "custou 45")
	T.eq(s.passives["poder"], 2, "nível 2")
	var before := s.to_dict()
	r = CharRules.buy_passive(s, bt, "poder")
	T.ok(not r.ok and r.err == "sem_ecos", "sem Ecos para o nível 3")
	T.eq(s.to_dict(), before, "estado intacto")


func test_buy_passive_max_and_invalid() -> void:
	var bt := _tables()
	var s := _blank(1000)
	s.passives["poder"] = 5
	var r := CharRules.buy_passive(s, bt, "poder")
	T.ok(not r.ok and r.err == "nivel_maximo", "nível máximo")
	r = CharRules.buy_passive(s, bt, "nada")
	T.ok(not r.ok and r.err == "passiva_invalida", "id inválido")
	T.eq(s.ecos, 1000, "nada cobrado")


func test_meta_mods_sum() -> void:
	var m := CharRules.meta_mods(_tables(), {"poder": 2, "armadura": 3})
	T.ok(absf(m.damage - 0.06) < 0.0001, "dano 2 níveis")
	T.eq(m.defense, 3, "defesa 3 níveis")


func test_donate_overflow_levels_up() -> void:
	var r := BaseRules.donate({"level": 0, "fund": 100}, _tables(), "forja", 300)
	T.ok(r.ok, "doou")
	T.eq(r.used, 300, "usou tudo")
	T.eq(r.level, 2, "subiu dois níveis")
	T.eq(r.fund, 30, "sobra no fundo")
	T.eq(r.leveled, 2, "leveled")


func test_donate_capped_at_max() -> void:
	var bt := _tables()
	var r := BaseRules.donate({"level": 4, "fund": 900}, bt, "forja", 500)
	T.ok(r.ok, "doou")
	T.eq(r.used, 100, "só o que falta")
	T.eq(r.level, 5, "nível máximo")
	T.eq(r.fund, 0, "fundo zerado")
	r = BaseRules.donate({"level": 5, "fund": 0}, bt, "forja", 10)
	T.ok(not r.ok and r.err == "nivel_maximo", "já no máximo")


func test_donate_invalid() -> void:
	var bt := _tables()
	var e := {"level": 0, "fund": 0}
	T.eq(BaseRules.donate(e, bt, "forja", 0).err, "valor_invalido", "zero")
	T.eq(BaseRules.donate(e, bt, "forja", -5).err, "valor_invalido", "negativo")
	T.eq(BaseRules.donate(e, bt, "torre", 10).err, "construcao_invalida", "id inválido")
	T.eq(e, {"level": 0, "fund": 0}, "entrada original intacta")
	# a falha devolve o nível e o fundo atuais, não zeros
	var f := BaseRules.donate({"level": 2, "fund": 70}, bt, "forja", 0)
	T.ok(not f.ok and f.level == 2 and f.fund == 70 and f.used == 0, "falha ecoa nível/fundo (%s)" % str(f))
	var m := BaseRules.donate({"level": 5, "fund": 0}, bt, "forja", 10)
	T.eq([m.err, m.level, m.fund], ["nivel_maximo", 5, 0], "no máximo ecoa o nível")


func test_bonus_and_total() -> void:
	var bt := _tables()
	var st := BaseRules.empty_state(bt)
	T.eq(st.size(), 3, "três construções")
	st["forja"]["level"] = 2
	st["celeiro"]["level"] = 1
	var b := BaseRules.bonus(bt, st)
	T.ok(absf(b.horde_damage - 0.08) < 0.0001, "dano da forja nível 2")
	T.eq(b.city_gold, 40, "ouro do celeiro")
	T.eq(b.city_food, 6, "comida do celeiro")
	T.ok(not b.has("hall_hp"), "muralha sem bônus")
	T.eq(BaseRules.total_invested(bt, "forja", {"level": 2, "fund": 30}), 400, "investido")


func test_state_roundtrip_ecos_passives() -> void:
	var bt := _tables()
	var s := _blank(77)
	s.passives = {"poder": 3, "vigor": 1}
	var s2 := CharState.from_dict(s.to_dict(), bt)
	T.eq(s2.ecos, 77, "ecos")
	T.eq(s2.passives, {"poder": 3, "vigor": 1}, "passivas")
	var d := s.to_dict()
	d.passives = {"poder": 9, "fantasma": 2, "vigor": 0}
	d.ecos = -4
	var s3 := CharState.from_dict(d, bt)
	T.eq(s3.passives, {"poder": 5}, "saneadas")
	T.eq(s3.ecos, 0, "ecos >= 0")
