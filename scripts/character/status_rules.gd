class_name StatusRules
extends RefCounted
## Status elementais (efeito do elemento que fica no alvo por um tempo): queimadura, lentidão/congelamento e
## veneno. Regras puras (sem autoload): o cliente rola a chance com elas e o servidor confere e limita.
## Números em data/balance/enchant.json ("effects": "chance" por nível, "ticks", "secs", "freeze_*").
##
## Chance final = chance da arma × (1 − resistência do alvo). No monstro a resistência vem do % do Bestiário
## (afinidade 75 = 25% de resistência; fraqueza não aumenta a chance; imune = 100%). Com 100% o efeito nunca
## pega, e se a rolagem teria pego aparece "Resistiu".

## Bits do bitmask de efeitos ativos (snapshot de inimigo e StatusAura). 16/32/64 ficam para raio, sombra e
## sagrado (entrega 2).
const BITS := {"fogo": 1, "gelo": 2, "veneno": 4, "congelado": 8}
## Elementos que deixam status no alvo nesta versão.
const STATUS_ELEMENTS := ["fogo", "gelo", "veneno"]
## Maior acerto que o servidor aceita (o mesmo corte de Network._hit_enemy).
const MAX_HIT := 5000.0


static func _fx(bt: BalanceTables, el: String) -> Dictionary:
	if bt == null or not (el in STATUS_ELEMENTS):
		return {}
	var fx = bt.get_table("enchant").get("effects", {}).get(el, {})
	return fx if fx is Dictionary else {}


static func _max_of(arr) -> float:
	var m := 0.0
	if arr is Array:
		for v in arr:
			if (v is float or v is int) and is_finite(float(v)):
				m = maxf(m, float(v))
	return m


## Resistência (0..1) de um monstro `kind` a `el`, a partir do % do Bestiário.
static func enemy_resist(bt: BalanceTables, kind: String, el: String) -> float:
	return clampf(1.0 - BestiaryRules.element_pct(bt, kind, el) / 100.0, 0.0, 1.0)


## Chance que sobra depois da resistência.
static func final_chance(base: float, resist: float) -> float:
	return maxf(0.0, base) * (1.0 - clampf(resist, 0.0, 1.0))


## Resultado de uma rolagem `r` (0..1): "applied", "resisted" (só quando a resistência é total e a base teria
## pego) ou "none".
static func roll(base: float, resist: float, r: float) -> String:
	if r < final_chance(base, resist):
		return "applied"
	if resist >= 1.0 and r < base:
		return "resisted"
	return "none"


## Chance base do status de `el` no nível `level` do encanto (0 sem encanto ou elemento sem status).
static func chance(bt: BalanceTables, el: String, level: int) -> float:
	var arr = _fx(bt, el).get("chance", [])
	if level <= 0 or not (arr is Array) or arr.is_empty():
		return 0.0
	return float(arr[mini(level, arr.size()) - 1])


## Quantos pulsos de dano o efeito dá ao longo da duração (0 para gelo, que não dá dano).
static func ticks(bt: BalanceTables, el: String) -> int:
	return int(_fx(bt, el).get("ticks", 0))


## Reaplicar o mesmo efeito: não empilha; fica a força maior e o tempo maior.
static func renew(cur: Dictionary, power: float, secs: float) -> Dictionary:
	return {"power": maxf(float(cur.get("power", 0.0)), power), "timer": maxf(float(cur.get("timer", 0.0)), secs)}


## Congela? `stacks` acúmulos de gelo dentro da lentidão; `protected` = chefe ou elite; `cd_left` = recarga.
static func should_freeze(stacks: int, need: int, protected: bool, cd_left: float) -> bool:
	return not protected and cd_left <= 0.0 and need > 0 and stacks >= need


## Força (dano total do efeito) que o servidor aceita: até MAX_HIT × maior fração da tabela. Gelo e elemento
## sem status: 0.
static func cap_power(bt: BalanceTables, el: String, power: float) -> float:
	if el == "gelo" or not is_finite(power):
		return 0.0
	return clampf(power, 0.0, MAX_HIT * _max_of(_fx(bt, el).get("values", [])))


## Duração que o servidor aceita: "secs" da tabela (gelo: maior "values", que são segundos de lentidão).
static func cap_secs(bt: BalanceTables, el: String, secs: float) -> float:
	if not is_finite(secs):
		return 0.0
	var fx := _fx(bt, el)
	var top := _max_of(fx.get("values", [])) if el == "gelo" else float(fx.get("secs", 0.0))
	return clampf(secs, 0.0, top)
