class_name ProgressionRules
extends RefCounted
## Curvas de progressão (XP por nível, atributos de monstro por nível, camadas de 10 níveis).
## Pura: só lê data/balance/progression.json (e `ref_level` do enemies.json) por BalanceTables.


static func _prog(bt: BalanceTables) -> Dictionary:
	return bt.get_table("progression")


static func max_level(bt: BalanceTables) -> int:
	return int(_prog(bt).get("max_level", 50))


## XP para sair de `level` para o próximo: base × level^exp × multiplicador tardio. No nível máximo, 0.
static func xp_to_next(bt: BalanceTables, level: int) -> int:
	if level >= max_level(bt):
		return 0
	var c: Dictionary = _prog(bt).get("xp_curve", {})
	var late: Dictionary = c.get("late", {})
	var mult := float(late.get(str(level), 1.0))
	return int(float(c.get("base", 60)) * pow(float(maxi(level, 1)), float(c.get("exp", 1.55))) * mult)


## `level` se > 0; senão o `ref_level` do tipo (padrão 1).
static func enemy_level(bt: BalanceTables, kind: String, level: int) -> int:
	if level > 0:
		return level
	var t: Dictionary = bt.get_table("enemies").get(kind, {})
	return maxi(int(t.get("ref_level", 1)), 1)


static func _curve(bt: BalanceTables, stat: String, level: int) -> float:
	var c: Dictionary = _prog(bt).get("enemy_curves", {}).get(stat, {})
	return pow(1.0 + float(c.get("rate", 0.0)) * float(maxi(level, 1) - 1), float(c.get("exp", 1.0)))


## Multiplicadores {"hp","dmg","xp","gold"} = curva(L) / curva(ref_level). Sem nível (<= 0): tudo 1.0.
static func enemy_mults(bt: BalanceTables, kind: String, level: int) -> Dictionary:
	var out := {"hp": 1.0, "dmg": 1.0, "xp": 1.0, "gold": 1.0}
	if level <= 0:
		return out
	var ref := enemy_level(bt, kind, 0)
	for stat in out:
		var base := _curve(bt, stat, ref)
		out[stat] = _curve(bt, stat, level) / base if base > 0.0 else 1.0
	return out


## Ajuste de XP pela diferença (nível do monstro − nível do jogador), pela tabela xp_diff.
static func xp_diff_mult(bt: BalanceTables, enemy_level: int, player_level: int) -> float:
	var diff := enemy_level - player_level
	for row in _prog(bt).get("xp_diff", []):
		if diff >= int(row[0]) and diff <= int(row[1]):
			return float(row[2])
	return 1.0


## Camada 1..N (a cada tier_size níveis), usada pelo loot e pela tinta do monstro.
static func tier_of(bt: BalanceTables, level: int) -> int:
	var p := _prog(bt)
	var size := maxi(int(p.get("tier_size", 10)), 1)
	var n := maxi(p.get("tiers", []).size(), 1)
	return clampi((maxi(level, 1) - 1) / size + 1, 1, n)


## Nível de quem nasce num ponto: sorteio em [level, max(level, level_max)] e, se elite, + elite.level_bonus.
## Ponto sem nível (level <= 0) continua sem nível (Horda e cidade).
static func spawn_level(bt: BalanceTables, level: int, level_max: int, elite: bool, rng: RandomNumberGenerator) -> int:
	if level <= 0:
		return 0
	var l := rng.randi_range(level, maxi(level, level_max))
	if elite:
		l += int(_prog(bt).get("elite", {}).get("level_bonus", 0))
	return l


# ================================================================ simulador de ritmo
# Contas do tools/progression_sim.gd e do tests/unit/test_progression_pacing.gd. Os números do jogador
# (atributos iniciais, pontos por nível, armas) vêm das tabelas; os do simulador do bloco `sim` do progression.json.

static func _sim(bt: BalanceTables) -> Dictionary:
	return _prog(bt).get("sim", {})


## Vida do monstro comum de referência (sim.ref_enemy, padrão goblin) no nível `level`.
static func sim_enemy_hp(bt: BalanceTables, level: int) -> float:
	var kind := str(_sim(bt).get("ref_enemy", "goblin"))
	var t: Dictionary = bt.get_table("enemies").get(kind, {})
	return float(t.get("hp", 0.0)) * float(enemy_mults(bt, kind, level).hp)


## XP que o monstro de referência dá no nível `level` (mesma conta de Enemy.xp_reward).
static func sim_enemy_xp(bt: BalanceTables, level: int) -> int:
	var kind := str(_sim(bt).get("ref_enemy", "goblin"))
	var t: Dictionary = bt.get_table("enemies").get(kind, {})
	return roundi(float(t.get("xp", 0)) * float(enemy_mults(bt, kind, level).xp))


## Atributos de uma build focada no nível `level`: os iniciais do CharState e todos os pontos
## (rules.points_per_level por nível) no atributo da classe.
static func sim_attrs(bt: BalanceTables, char_class: String, level: int) -> Dictionary:
	var attrs: Dictionary = CharState.new().attributes.duplicate()
	var main := str(bt.get_table("classes").get(char_class, {}).get("attr", "str"))
	var pts := int(bt.get_table("rules").get("points_per_level", 3))
	attrs[main] = int(attrs.get(main, 0)) + (maxi(level, 1) - 1) * pts
	return attrs


## {"id", "damage"}: a arma da classe (não nomeada, nível de item <= `level`) que dá o maior ataque básico,
## com os bônus de atributo e de magia da própria arma e o sim.talent_damage. Sem arma: id "".
static func sim_best_weapon(bt: BalanceTables, char_class: String, level: int) -> Dictionary:
	var wclass := CharRules.class_weapon(bt, char_class)
	var base := sim_attrs(bt, char_class, level)
	var talent := 1.0 + float(_sim(bt).get("talent_damage", 0.0))
	var best := {"id": "", "damage": 0.0}
	var items: Dictionary = bt.get_table("items")
	var ids := items.keys()
	ids.sort()  # empate: sempre o mesmo id
	for id in ids:
		var it: Dictionary = items[id]
		if it.get("type", "") != "weapon" or it.get("named", false) or CharRules.weapon_class(bt, id) != wclass:
			continue
		if CharRules.item_level(bt, id) > level:
			continue
		var st: Dictionary = it.get("stats", {})
		var attrs := base.duplicate()
		for a in attrs:
			attrs[a] = int(attrs[a]) + int(st.get(a, 0))
		var dmg := CharRules.basic_damage(wclass, attrs, float(it.get("damage", 0)), float(st.get("spell", 0.0))) * talent
		if dmg > float(best.damage):
			best = {"id": id, "damage": dmg}
	return best


## Golpes de ataque básico para a build focada da classe matar o monstro comum de referência do mesmo nível.
static func sim_hits(bt: BalanceTables, char_class: String, level: int) -> int:
	var dmg := float(sim_best_weapon(bt, char_class, level).damage)
	if dmg <= 0.0:
		return 999
	return maxi(1, ceili(sim_enemy_hp(bt, level) / dmg - 0.000001))


static func _sim_bands(bt: BalanceTables) -> Array:
	return _sim(bt).get("bands", [[1, 10], [10, 20], [20, 35], [35, 45], [45, 50]])


## Fração da XP da faixa de `level` (sim.bands) que as missões de verdade dão: soma do reward_xp das missões
## (quests.json) com nível na faixa ÷ XP para atravessar a faixa, no máximo quest_xp_share. Missões de evento
## sazonal (`event`, ex.: Natal) não contam: só existem parte do ano. Nível fora das faixas: quest_xp_share.
static func sim_quest_share(bt: BalanceTables, level: int) -> float:
	var cap := float(_prog(bt).get("quest_xp_share", 0.0))
	for band in _sim_bands(bt):
		var lo := int(band[0])
		var hi := int(band[1])
		if level < lo or level >= hi:
			continue
		var need := 0
		for l in range(lo, hi):
			need += xp_to_next(bt, l)
		var got := 0
		var quests: Dictionary = bt.get_table("quests")
		for id in quests:
			if quests[id].has("event"):
				continue
			var ql := int(quests[id].get("level", 1))
			if ql >= lo and ql < hi:
				got += int(quests[id].get("reward_xp", 0))
		return minf(float(got) / float(maxi(need, 1)), cap)
	return cap


## Minutos para sair de `level` caçando o monstro de referência do mesmo nível: a parte da XP que as missões da
## faixa não dão (1 − sim_quest_share), em abates de sim.ref_class (golpes × attack_interval + downtime_per_kill).
static func sim_minutes(bt: BalanceTables, level: int) -> float:
	var need := float(xp_to_next(bt, level)) * (1.0 - sim_quest_share(bt, level))
	var xp := maxi(sim_enemy_xp(bt, level), 1)
	var s := _sim(bt)
	var per_kill := float(sim_hits(bt, str(s.get("ref_class", "warrior")), level)) * float(s.get("attack_interval", 1.0)) \
		+ float(s.get("downtime_per_kill", 0.0))
	return need / float(xp) * per_kill / 60.0


## Horas por faixa de nível {"1-10": h, ...} (sim.bands: [de, até], soma os níveis de..até-1).
static func sim_hours(bt: BalanceTables) -> Dictionary:
	var out := {}
	for band in _sim_bands(bt):
		var total := 0.0
		for l in range(int(band[0]), int(band[1])):
			total += sim_minutes(bt, l)
		out["%d-%d" % [int(band[0]), int(band[1])]] = total / 60.0
	return out


## Média de itens por morte de `kind` no ref_level (LootRules.roll com nível, equipamento incluído),
## em `n` sorteios com a semente `seed_value` (sempre o mesmo resultado).
static func sim_items_per_kill(bt: BalanceTables, kind: String, n: int, seed_value: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var level := enemy_level(bt, kind, 0)
	var total := 0
	for i in n:
		var items: Dictionary = LootRules.roll(bt, kind, rng, "", level).items
		for id in items:
			total += int(items[id])
	return float(total) / float(maxi(n, 1))
