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


## Defesa da Cidade em grupo: soma os acumulados da partida
## (peer -> {"account", "gold", "xp", "items": [ids], "nights"}) por conta:
## conta -> {"gold", "xp", "items": {id: n}, "nights", "peers": [peers]}. Quem caiu e voltou tem dois peers
## da mesma conta (as noites somam); quem entrou no meio tem só as noites em que esteve. Contas <= 0 ficam
## de fora. Usada pelo Lobby no fim da partida (servidor).
static func city_by_account(rewards: Dictionary) -> Dictionary:
	var by_account := {}
	for pid in rewards:
		var r: Dictionary = rewards[pid]
		var account := int(r.get("account", 0))
		if account <= 0:
			continue
		if not by_account.has(account):
			by_account[account] = {"gold": 0, "xp": 0, "items": {}, "nights": 0, "peers": []}
		var t: Dictionary = by_account[account]
		t.gold += int(r.get("gold", 0))
		t.xp += int(r.get("xp", 0))
		t.nights += int(r.get("nights", 0))
		t.peers.append(pid)
		for id in r.get("items", []):
			t.items[id] = int(t.items.get(id, 0)) + 1
	return by_account
