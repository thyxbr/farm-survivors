class_name BestiaryRules
extends RefCounted
## Bestiário: cada abate de um monstro conta na entrada dele, e a entrada vai revelando informações em três
## estágios (comportamento e espólio comum; regiões e espólio incomum; espólio raro). O espólio mais raro que a
## última faixa fica secreto até cair para o jogador. Completar uma família inteira libera um título.
## Inspirado no Bestiário do Tibia (docs/PESQUISA_BESTIARIO.md); números em data/balance/bestiary.json.
## Regras puras (sem autoload): o servidor/solo grava em CharState.bestiary pelo CharRules.kill.
##
## Entrada gravada: kind -> {"n": abates, "a": [regiões onde matou], "d": [itens da tabela que já caíram]}.

const MAX_AREAS := 16
const MAX_DROPS := 64
## Estágio que o item secreto "pede" (nunca chega pelo contador; só por ter caído).
const SECRET := 4
const C_INFO := Color(0.85, 0.75, 1.0)
const C_DONE := Color(1.0, 0.85, 0.4)


static func _t(bt: BalanceTables) -> Dictionary:
	return bt.get_table("bestiary")


## Famílias na ordem da tabela: id -> {"name", "kinds"}.
static func families(bt: BalanceTables) -> Dictionary:
	return _t(bt).get("families", {})


## Família do monstro ("" = fora do bestiário: invocações, sombras, monstros só da Horda).
static func family_of(bt: BalanceTables, kind: String) -> String:
	var fams := families(bt)
	for f in fams:
		if kind in fams[f].get("kinds", []):
			return str(f)
	return ""


static func listed(bt: BalanceTables, kind: String) -> bool:
	return family_of(bt, kind) != "" and bt.get_table("enemies").has(kind)


## Todos os monstros do bestiário, na ordem das famílias.
static func all_kinds(bt: BalanceTables) -> Array:
	var out: Array = []
	var enemies := bt.get_table("enemies")
	var fams := families(bt)
	for f in fams:
		for k in fams[f].get("kinds", []):
			if enemies.has(k) and not k in out:
				out.append(k)
	return out


## Classe do monstro: chefe, elite, forte ou comum ("bestiary_class" no enemies.json sobrepõe).
static func class_of(bt: BalanceTables, kind: String) -> String:
	var e: Dictionary = bt.get_table("enemies").get(kind, {})
	var classes: Dictionary = _t(bt).get("classes", {})
	var forced := str(e.get("bestiary_class", ""))
	if classes.has(forced):
		return forced
	if e.get("boss", false):
		return "chefe"
	if e.get("elite", false):
		return "elite"
	if float(e.get("hp", 0)) >= float(_t(bt).get("forte_hp", 120)):
		return "forte"
	return "comum"


static func class_label(bt: BalanceTables, kind: String) -> String:
	var c := class_of(bt, kind)
	return str(_t(bt).get("classes", {}).get(c, {}).get("name", c))


## Abates para os estágios 1, 2 e 3.
static func steps(bt: BalanceTables, kind: String) -> Array:
	var st: Array = _t(bt).get("classes", {}).get(class_of(bt, kind), {}).get("steps", [10, 50, 150])
	return st


## Pontos de caçador que a entrada completa vale (moeda das Marcas, numa fase seguinte).
static func points(bt: BalanceTables, kind: String) -> int:
	return int(_t(bt).get("classes", {}).get(class_of(bt, kind), {}).get("points", 0))


## Estágio alcançado com `kills` abates: 0 (nenhum ainda) a 3 (completo).
static func stage(bt: BalanceTables, kind: String, kills: int) -> int:
	var st := steps(bt, kind)
	var out := 0
	for i in st.size():
		if kills >= int(st[i]):
			out = i + 1
	return out


## Abates que faltam para o próximo estágio (0 = completo).
static func next_goal(bt: BalanceTables, kind: String, kills: int) -> int:
	for need in steps(bt, kind):
		if kills < int(need):
			return int(need)
	return 0


static func kills_of(bestiary: Dictionary, kind: String) -> int:
	var e = bestiary.get(kind)
	return int(e.get("n", 0)) if e is Dictionary else 0


## Estágio que revela um item de espólio com essa chance (1..3), ou SECRET.
static func loot_band(bt: BalanceTables, chance: float) -> int:
	for b in _t(bt).get("loot_bands", []):
		if chance >= float(b[0]):
			return int(b[1])
	return SECRET


## Espólio da tabela do monstro, do mais comum ao mais raro:
## [{"id", "chance", "band", "shown"}]; `shown` = o estágio já revela ou o item já caiu para o jogador.
static func loot_view(bt: BalanceTables, kind: String, entry: Dictionary) -> Array:
	var st := stage(bt, kind, int(entry.get("n", 0)))
	var seen: Array = entry.get("d", [])
	var out: Array = []
	for row in bt.get_table("enemies").get(kind, {}).get("loot", []):
		var id := str(row[0])
		var ch := float(row[1])
		var band := loot_band(bt, ch)
		out.append({"id": id, "chance": ch, "band": band, "shown": band <= st or id in seen})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.chance > b.chance)
	return out


## Elementos de dano, na ordem da ficha: o físico e os seis dos encantamentos (enchant.json).
const ELEMENTS := ["fisico", "fogo", "gelo", "raio", "veneno", "sagrado", "sombra"]
const ELEMENT_NAMES := {"fisico": "Físico", "fogo": "Fogo", "gelo": "Gelo", "raio": "Raio", "veneno": "Veneno",
	"sagrado": "Sagrado", "sombra": "Sombra"}


## % do dano de `element` que o monstro recebe (enemies.json "elements"; sem entrada = 100, neutro).
## < 100 resiste, > 100 é fraco, 0 é imune. O combate pode usar `element_pct / 100.0` como multiplicador.
static func element_pct(bt: BalanceTables, kind: String, element: String) -> int:
	var el = bt.get_table("enemies").get(kind, {}).get("elements", {})
	return maxi(0, int(el.get(element, 100))) if el is Dictionary else 100


## Texto curto da afinidade: "Imune", "Resiste", "Neutro" ou "Fraco".
static func element_word(pct: int) -> String:
	if pct <= 0:
		return "Imune"
	if pct < 100:
		return "Resiste"
	if pct > 100:
		return "Fraco"
	return "Neutro"


## Resumo: {"known", "complete", "total", "points"}.
static func summary(bt: BalanceTables, bestiary: Dictionary) -> Dictionary:
	var out := {"known": 0, "complete": 0, "total": 0, "points": 0}
	for k in all_kinds(bt):
		out.total += 1
		var n := kills_of(bestiary, k)
		if n > 0:
			out.known += 1
		if stage(bt, k, n) >= 3:
			out.complete += 1
			out.points += points(bt, k)
	return out


## A família está completa (todas as entradas no estágio 3)?
static func family_complete(bt: BalanceTables, bestiary: Dictionary, fam: String) -> bool:
	var kinds: Array = families(bt).get(fam, {}).get("kinds", [])
	if kinds.is_empty():
		return false
	for k in kinds:
		if stage(bt, k, kills_of(bestiary, k)) < 3:
			return false
	return true


static func _enemy_name(bt: BalanceTables, kind: String) -> String:
	return str(bt.get_table("enemies").get(kind, {}).get("name", kind))


## Um abate de `kind` (em `area`, com o espólio `drops` {id: qtd} sorteado para este jogador). Acrescenta os
## avisos em `ev`. Monstro fora do bestiário não conta. Família completa grava flags["bst_<família>"] (título);
## tudo completo, flags["bst_all"].
static func record(s: CharState, bt: BalanceTables, kind: String, area: String, drops: Dictionary, ev: Array) -> void:
	if not listed(bt, kind):
		return
	var e: Dictionary = s.bestiary.get(kind, {})
	var n := int(e.get("n", 0))
	var areas: Array = e.get("a", [])
	var seen: Array = e.get("d", [])
	var before := stage(bt, kind, n)
	n += 1
	if area != "" and not area in areas and areas.size() < MAX_AREAS:
		areas.append(area)
	var who := _enemy_name(bt, kind)
	var items := bt.get_table("items")
	for row in bt.get_table("enemies").get(kind, {}).get("loot", []):
		var id := str(row[0])
		if drops.has(id) and not id in seen and seen.size() < MAX_DROPS:
			seen.append(id)
			if loot_band(bt, float(row[1])) > stage(bt, kind, n):
				ev.append({"t": "notify", "text": "Bestiário: espólio raro de %s descoberto — %s!"
					% [who, items.get(id, {}).get("name", id)], "color": C_DONE})
	s.bestiary[kind] = {"n": n, "a": areas, "d": seen}
	var after := stage(bt, kind, n)
	if after >= 3 and before < 3:
		ev.append({"t": "notify", "text": "Bestiário completo: %s!" % who, "color": C_DONE})
		var fam := family_of(bt, kind)
		if family_complete(bt, s.bestiary, fam) and not s.flags.get("bst_" + fam, false):
			s.flags["bst_" + fam] = true
			ev.append({"t": "notify", "text": "Família completa no Bestiário: %s! Novo título liberado."
				% families(bt)[fam].get("name", fam), "color": C_DONE})
			var all_done := true
			for f in families(bt):
				if not s.flags.get("bst_" + str(f), false):
					all_done = false
			if all_done:
				s.flags["bst_all"] = true
	elif after > before:
		ev.append({"t": "notify", "text": "Bestiário: %s — estágio %d de 3 (B)" % [who, after], "color": C_INFO})
	elif n == 1:
		ev.append({"t": "notify", "text": "Bestiário: nova criatura — %s (B)" % who, "color": C_INFO})


## Bestiário vindo de save ou da rede: só monstros do bestiário (com `bt`), abates >= 0, regiões e itens como
## texto sem repetição e com limite. Sem `bt`, só formato.
static func parse(data, bt: BalanceTables) -> Dictionary:
	var out := {}
	if not (data is Dictionary):
		return out
	for kind in data:
		var e = data[kind]
		if not (kind is String) or not (e is Dictionary) or (bt != null and not listed(bt, kind)):
			continue
		var n = e.get("n")
		var count := int(n) if (n is int or n is float) else 0
		if count <= 0:
			continue
		out[kind] = {"n": count, "a": _strings(e.get("a"), MAX_AREAS), "d": _strings(e.get("d"), MAX_DROPS)}
	return out


static func _strings(v, limit: int) -> Array:
	var out: Array = []
	if v is Array:
		for x in v:
			if x is String and x != "" and not x in out and out.size() < limit:
				out.append(x)
	return out
