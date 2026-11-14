class_name RewardRules
extends RefCounted
## Recompensa em Ecos (moeda permanente) pelo desempenho numa partida. Pura: os números
## vêm de data/balance/rewards.json, nada fixo aqui.


## Ecos de uma partida: `per` por rodada/noite alcançada + `bonus` a cada `bonus_every`.
## `reached <= 0` ou modo desconhecido (ou tabela malformada) dão 0.
static func ecos(bt: BalanceTables, mode: String, reached: int) -> int:
	var cfg: Dictionary = bt.get_table("rewards").get("ecos", {}).get(mode, {})
	if reached <= 0 or cfg.is_empty():
		return 0
	var every := int(cfg.get("bonus_every", 0))
	var bonus_n := reached / every if every > 0 else 0
	return maxi(0, int(cfg.get("per", 0)) * reached + int(cfg.get("bonus", 0)) * bonus_n)
