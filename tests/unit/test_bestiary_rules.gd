extends RefCounted
## Bestiário (BestiaryRules): classes, estágios por abate, espólio revelado por estágio ou por ter caído,
## família completa (título), gravação pelo CharRules.kill e leitura de save.

var _bt: BalanceTables


func _tables() -> BalanceTables:
	if _bt == null:
		_bt = BalanceTables.load_dir("res://data/balance")
	return _bt


func _kill(s: CharState, kind: String, times: int, area := "", drops := {}) -> Array:
	var ev: Array = []
	for i in times:
		ev.append_array(CharRules.kill(s, _tables(), kind, 0, 0, 0, area, drops).events)
	return ev


func test_classes() -> void:
	var bt := _tables()
	T.eq(BestiaryRules.class_of(bt, "slime"), "comum", "slime é comum")
	T.eq(BestiaryRules.class_of(bt, "goblin_bruto"), "forte", "bruto é forte (vida alta)")
	T.eq(BestiaryRules.class_of(bt, "goblin_dourado"), "elite", "dourado é elite")
	T.eq(BestiaryRules.class_of(bt, "lich"), "chefe", "lich é chefe")
	T.ok(not BestiaryRules.listed(bt, "sombra_arauto"), "sombra do arauto fica fora")
	T.ok(not BestiaryRules.listed(bt, "broto_espinheiro"), "invocação fica fora")


func test_every_listed_kind_exists_once() -> void:
	var bt := _tables()
	var seen := {}
	for f in BestiaryRules.families(bt):
		for k in BestiaryRules.families(bt)[f].kinds:
			T.ok(bt.get_table("enemies").has(k), "%s existe em enemies.json" % k)
			T.ok(not seen.has(k), "%s só em uma família" % k)
			seen[k] = true


func test_stages() -> void:
	var bt := _tables()
	T.eq(BestiaryRules.stage(bt, "slime", 0), 0, "sem abate")
	T.eq(BestiaryRules.stage(bt, "slime", 9), 0, "9 slimes ainda não")
	T.eq(BestiaryRules.stage(bt, "slime", 10), 1, "10 slimes: estágio 1")
	T.eq(BestiaryRules.stage(bt, "slime", 50), 2, "50: estágio 2")
	T.eq(BestiaryRules.stage(bt, "slime", 150), 3, "150: completo")
	T.eq(BestiaryRules.next_goal(bt, "slime", 12), 50, "próximo alvo")
	T.eq(BestiaryRules.next_goal(bt, "slime", 500), 0, "completo não tem alvo")
	T.eq(BestiaryRules.stage(bt, "lich", 1), 1, "chefe: o primeiro abate já revela o estágio 1")


func test_kill_records_and_notifies() -> void:
	var bt := _tables()
	var s := CharState.new_character(bt)
	var ev := _kill(s, "slime", 1, "campos_norte")
	T.eq(BestiaryRules.kills_of(s.bestiary, "slime"), 1, "abate contado")
	T.eq(s.bestiary.slime.a, ["campos_norte"], "região guardada")
	T.ok(ev.any(func(e): return str(e.get("text", "")).contains("nova criatura")), "aviso de criatura nova")
	ev = _kill(s, "slime", 9, "campos_norte")
	T.eq(s.bestiary.slime.a, ["campos_norte"], "região sem repetir")
	T.ok(ev.any(func(e): return str(e.get("text", "")).contains("estágio 1")), "aviso do estágio 1")
	_kill(s, "sombra_arauto", 3)
	T.ok(not s.bestiary.has("sombra_arauto"), "fora do bestiário não conta")


func test_loot_revealed_by_stage_and_by_drop() -> void:
	var bt := _tables()
	var s := CharState.new_character(bt)
	# slime: gel 0.4 (estágio 1), sementes/poções < 0.05 (secretas)
	_kill(s, "slime", 1)
	var view := BestiaryRules.loot_view(bt, "slime", s.bestiary.slime)
	T.ok(view.all(func(r): return not r.shown), "estágio 0: nada revelado")
	_kill(s, "slime", 9)
	view = BestiaryRules.loot_view(bt, "slime", s.bestiary.slime)
	T.ok(view[0].id == "slime_gel" and view[0].shown, "estágio 1 revela o gel (comum)")
	var potion: Dictionary = view.filter(func(r): return r.id == "mana_potion")[0]
	T.eq(potion.band, BestiaryRules.SECRET, "poção de mana (3%) é secreta")
	T.ok(not potion.shown, "secreta escondida")
	var ev := _kill(s, "slime", 1, "", {"mana_potion": 1, "iron_sword": 1})
	T.ok("mana_potion" in s.bestiary.slime.d, "drop secreto registrado")
	T.ok(not "iron_sword" in s.bestiary.slime.d, "item fora da tabela não entra")
	T.ok(ev.any(func(e): return str(e.get("text", "")).contains("espólio raro")), "aviso do espólio raro")
	view = BestiaryRules.loot_view(bt, "slime", s.bestiary.slime)
	T.ok(view.filter(func(r): return r.id == "mana_potion")[0].shown, "depois de cair, aparece")
	_kill(s, "slime", 140)
	view = BestiaryRules.loot_view(bt, "slime", s.bestiary.slime)
	T.ok(not view.filter(func(r): return r.id == "health_potion")[0].shown, "completo não revela o secreto que não caiu")


func test_family_title() -> void:
	var bt := _tables()
	var s := CharState.new_character(bt)
	var kinds: Array = BestiaryRules.families(bt).mortos.kinds
	for k in kinds.slice(0, kinds.size() - 1):
		_kill(s, k, 200)
	T.ok(not s.flags.get("bst_mortos", false), "falta um")
	T.ok(not TitleRules.is_unlocked("exorcista", s.level, s.flags), "título bloqueado")
	var ev := _kill(s, kinds.back(), 200)
	T.ok(s.flags.get("bst_mortos", false), "família completa")
	T.ok(TitleRules.is_unlocked("exorcista", s.level, s.flags), "título liberado")
	T.ok(ev.any(func(e): return str(e.get("text", "")).contains("Família completa")), "aviso da família")
	var sum := BestiaryRules.summary(bt, s.bestiary)
	T.eq(sum.complete, kinds.size(), "resumo conta as completas")
	T.ok(sum.points > 0, "pontos de caçador somados")


func test_save_roundtrip_and_parse() -> void:
	var bt := _tables()
	var s := CharState.new_character(bt)
	_kill(s, "goblin", 12, "toca_goblins", {"goblin_ear": 1})
	var back := CharState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())), bt)
	T.eq(back.bestiary, s.bestiary, "volta igual do JSON")
	var bad := BestiaryRules.parse({"goblin": {"n": -3}, "nao_existe": {"n": 5}, "slime": {"n": 4.0, "a": [1, "x", "x"], "d": "no"}, 7: {}}, bt)
	T.eq(bad, {"slime": {"n": 4, "a": ["x"], "d": []}}, "save adulterado limpo")


func test_loot_roll_keeps_table_ids() -> void:
	var bt := _tables()
	var rng := RandomNumberGenerator.new()
	for seed in 40:
		rng.seed = seed
		var loot := LootRules.roll(bt, "esqueleto_cavaleiro", rng, "mage")
		for id in loot.rolled:
			var in_table := false
			for row in bt.get_table("enemies").esqueleto_cavaleiro.loot:
				in_table = in_table or row[0] == id
			T.ok(in_table, "rolled só tem ids da tabela (%s)" % id)


func test_elements() -> void:
	var bt := _tables()
	T.eq(BestiaryRules.element_pct(bt, "esqueleto", "sagrado"), 150, "morto-vivo fraco a sagrado")
	T.eq(BestiaryRules.element_pct(bt, "esqueleto", "sombra"), 0, "imune a sombra")
	T.eq(BestiaryRules.element_pct(bt, "goblin", "gelo"), 100, "sem entrada = neutro")
	T.eq(BestiaryRules.element_pct(bt, "nao_existe", "fogo"), 100, "tipo desconhecido = neutro")
	T.eq(BestiaryRules.element_word(0), "Imune", "imune")
	T.eq(BestiaryRules.element_word(75), "Resiste", "resiste")
	T.eq(BestiaryRules.element_word(125), "Fraco", "fraco")
	for k in BestiaryRules.all_kinds(bt):
		var el: Dictionary = bt.get_table("enemies")[k].get("elements", {})
		T.ok(not el.is_empty(), "%s tem afinidades" % k)
		for e in el:
			T.ok(e in BestiaryRules.ELEMENTS, "%s: elemento %s conhecido" % [k, e])
