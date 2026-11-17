class_name DungeonRules
extends RefCounted
## Dungeons compartilhadas (puro, sem autoload): quantos monstros cada ponto mantém com N jogadores dentro, o
## ritmo de volta, a volta do chefe e o loot extra de cada dungeon. Números em data/balance/progression.json
## ("dungeons"): per_player, max_mult, respawn_per_player, boss_respawn (minutos) e loot.<id>.monster/.boss.
## A base de cada dungeon é ajustada para UM jogador bem equipado; o per_player só aumenta monstros e ritmo.


static func _t(bt: BalanceTables) -> Dictionary:
	return bt.get_table("progression").get("dungeons", {})


## Monstros que um ponto de `base` mantém com `players` dentro (mínimo 1): base × (1 + per_player × (n − 1)),
## arredondado para cima, até base × max_mult.
static func population(bt: BalanceTables, base: int, players: int) -> int:
	var t := _t(bt)
	var n := maxi(players, 1)
	var want := ceili(base * (1.0 + float(t.get("per_player", 0.0)) * (n - 1)))
	return mini(want, max_population(bt, base))


## O máximo que um ponto chega a ter (quantas entradas o mundo cria para ele).
static func max_population(bt: BalanceTables, base: int) -> int:
	return maxi(base, ceili(base * float(_t(bt).get("max_mult", 1.0))))


## Segundos até voltar: o chefe volta em boss_respawn minutos; os outros mais rápido com mais gente.
static func respawn(bt: BalanceTables, base_respawn: float, players: int, boss: bool) -> float:
	var t := _t(bt)
	if boss:
		return float(t.get("boss_respawn", 10.0)) * 60.0
	return base_respawn / (1.0 + float(t.get("respawn_per_player", 0.0)) * (maxi(players, 1) - 1))


## Linhas de loot extra ([item, chance]) de quem morre na dungeon.
static func extra_loot(bt: BalanceTables, dungeon: String, boss: bool) -> Array:
	return _t(bt).get("loot", {}).get(dungeon, {}).get("boss" if boss else "monster", [])


## Quantos dos jogadores (posições) estão dentro da dungeon.
static func players_in(dungeon: String, positions: Array) -> int:
	var n := 0
	for p in positions:
		if p is Vector3 and Regions.region_at(p) == dungeon:
			n += 1
	return n
