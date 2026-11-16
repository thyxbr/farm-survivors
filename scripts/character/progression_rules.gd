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
