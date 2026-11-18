class_name GatherRules
extends RefCounted
## Ferramentas de coleta (picaretas e machados) e maestria, regras puras: o cliente usa para a barra de progresso
## e o ritmo dos golpes, o servidor (CharRules.gather) para conferir a ferramenta. Sem autoload: recebe a tabela
## de itens (ItemDB.ITEMS no jogo, bt.get_table("items") nas regras e nos testes).
##
## Cada nó de coleta tem uma resistência (`tough`, em data/balance/world_nodes.json) e um nível mínimo de ferramenta
## (`tier`). Cada golpe tira `power` da ferramenta × bônus de maestria; o nó cede quando a soma passa da
## resistência. Maestria = o nível da profissão de coleta do nó (Mineração para picareta, Lenhador para machado):
## sobe coletando e deixa cada golpe mais forte e mais rápido.

const TOOL_OF_PROF := {"mining": "pickaxe", "woodcutting": "axe"}
const TOOL_NAMES := {"pickaxe": "picareta", "axe": "machado"}

## Força extra por nível de maestria acima do 1 (nível 50: +98%).
const MASTERY_POWER := 0.02
## Ritmo: segundos por golpe com ferramenta de nível 1 e maestria 1; cada nível de ferramenta e de maestria encurta.
const SWING_BASE := 1.0
const SWING_PER_TIER := 0.05
const SWING_PER_MASTERY := 0.004
const SWING_MIN := 0.55


## Tipo de ferramenta que a profissão pede ("pickaxe", "axe" ou "" se a profissão não usa ferramenta).
static func tool_kind(prof: String) -> String:
	return TOOL_OF_PROF.get(prof, "")


static func is_tool_item(items: Dictionary, id: String) -> bool:
	return str(items.get(id, {}).get("type", "")) == "tool"


## Nível da ferramenta (1 = pedra ... 5 = astral); 0 se não é ferramenta.
static func tier(items: Dictionary, id: String) -> int:
	return int(items[id].get("tier", 1)) if is_tool_item(items, id) else 0


## A melhor ferramenta do tipo `kind` no inventário ([{"id", "qty"}]); "" se não tem nenhuma.
static func best_tool(items: Dictionary, inventory: Array, kind: String) -> String:
	var best := ""
	var best_tier := 0
	for slot in inventory:
		var id := str(slot.get("id", ""))
		if not is_tool_item(items, id) or str(items[id].get("tool", "")) != kind:
			continue
		var t := tier(items, id)
		if t > best_tier:
			best_tier = t
			best = id
	return best


## Multiplicador de força da maestria (nível da profissão de coleta).
static func mastery_mult(level: int) -> float:
	return 1.0 + MASTERY_POWER * float(maxi(level, 1) - 1)


## Quanto um golpe tira da resistência do nó.
static func hit_power(items: Dictionary, tool_id: String, mastery: int) -> float:
	if not is_tool_item(items, tool_id):
		return 0.0
	return float(items[tool_id].get("power", 1.0)) * mastery_mult(mastery)


## Golpes para o nó ceder.
static func strikes(tough: float, power: float) -> int:
	if power <= 0.0:
		return 0
	return maxi(1, ceili(tough / power - 0.0001))


## Segundos de cada golpe (o ciclo inteiro da animação).
static func swing_time(tool_tier: int, mastery: int) -> float:
	var t := SWING_BASE * (1.0 - SWING_PER_TIER * float(maxi(tool_tier, 1) - 1)) \
		* (1.0 - SWING_PER_MASTERY * float(maxi(mastery, 1) - 1))
	return maxf(SWING_MIN, t)


## A ferramenta `tool_id` serve para o nó? {"ok", "err"}: "sem_ferramenta" (não tem do tipo certo) ou
## "ferramenta_fraca" (o nível dela não chega no `need_tier` do nó).
static func check(items: Dictionary, tool_id: String, kind: String, need_tier: int) -> Dictionary:
	if kind == "":
		return {"ok": true, "err": ""}
	if tool_id == "" or not is_tool_item(items, tool_id) or str(items[tool_id].get("tool", "")) != kind:
		return {"ok": false, "err": "sem_ferramenta"}
	if tier(items, tool_id) < need_tier:
		return {"ok": false, "err": "ferramenta_fraca"}
	return {"ok": true, "err": ""}


## Nome do nível mínimo de ferramenta, para avisos ("Precisa de picareta de Ferro ou melhor").
static func tier_name(items: Dictionary, kind: String, need_tier: int) -> String:
	for id in items:
		if is_tool_item(items, id) and str(items[id].get("tool", "")) == kind and int(items[id].get("tier", 0)) == need_tier:
			return str(items[id].get("name", id))
	return "%s nível %d" % [TOOL_NAMES.get(kind, kind), need_tier]


## Aviso para o jogador quando a ferramenta não serve (check() recusou).
static func refusal_text(items: Dictionary, err: String, kind: String, need_tier: int) -> String:
	if err == "sem_ferramenta":
		return "Precisa de um%s %s (o mercador vende as de pedra)." % ["a" if kind == "pickaxe" else "", TOOL_NAMES.get(kind, kind)]
	return "Precisa de %s ou melhor." % tier_name(items, kind, need_tier)
