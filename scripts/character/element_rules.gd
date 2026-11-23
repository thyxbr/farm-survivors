class_name ElementRules
extends RefCounted
## Afinidades elementais no combate: quanto do dano um monstro leva conforme o elemento do golpe. O número é o
## mesmo da ficha do Bestiário (BestiaryRules.element_pct, campo "elements" de data/balance/enemies.json).
## Regras puras (sem autoload): o solo e o servidor chamam mult() dentro de Enemy.take_damage.
##
## Um golpe leva uma "mistura" de elementos: um nome ("fogo") ou um dicionário de pesos ({"fisico": 0.8,
## "fogo": 0.2}). O multiplicador é a média dos % de cada parte, pelos pesos, dividida por 100.
## De onde vem o elemento de cada fonte de dano:
##   - golpe e flecha: físico; faísca do cajado: o elemento do cajado (fogo, gelo ou arcano); esfera do cetro e
##     Lança de Luz: sagrado. Arma encantada: o golpe continua no elemento base e a fatia que o encantamento
##     soma ao dano (enchant.json "damage") vai no elemento dele (weapon_mix).
##   - magias e habilidades: o elemento delas (Canalização de Fogo e Chuva de Meteoros fogo, Nova Gélida gelo,
##     Julgamento de Luz sagrado; as da espada e do arco são físicas).
##   - efeitos: queimadura fogo, corrente raio.
## "arcano" (faísca do cajado comum, Martelo de Energia) não tem afinidade: vale 100% em todo monstro.

const NEUTRAL := "arcano"
## Diferença mínima do neutro para o número de dano ganhar a dica (um encanto fraco num monstro pouco fraco
## mexe 1% no golpe: não vale um "Fraco!" na tela).
const HINT_MIN := 0.05
const C_WEAK := Color(1.0, 0.55, 0.25)
const C_RESIST := Color(0.66, 0.72, 0.82)
const C_IMMUNE := Color(0.62, 0.62, 0.66)


## Nome de elemento que o combate aceita (os da ficha e o arcano).
static func known(element: String) -> bool:
	return element == NEUTRAL or element in BestiaryRules.ELEMENTS


## Mistura normalizada {elemento: peso}, só com elementos conhecidos e pesos positivos. Um nome vira {nome: 1};
## o que sobrar vazio (nada, lixo vindo da rede) vira físico.
static func mix_of(element) -> Dictionary:
	var out := {}
	if element is String or element is StringName:
		if known(str(element)):
			out[str(element)] = 1.0
	elif element is Dictionary:
		for k in element:
			var w = element[k]
			if (k is String or k is StringName) and known(str(k)) and (w is float or w is int) \
					and is_finite(float(w)) and float(w) > 0.0:
				out[str(k)] = float(out.get(str(k), 0.0)) + float(w)
	if out.is_empty():
		out["fisico"] = 1.0
	return out


## Multiplicador do dano de `element` (nome ou mistura) num monstro `kind`: 1.0 neutro, 0 imune.
static func mult(bt: BalanceTables, kind: String, element) -> float:
	var mix := mix_of(element)
	var total := 0.0
	var acc := 0.0
	for el in mix:
		var w: float = mix[el]
		total += w
		acc += w * float(BestiaryRules.element_pct(bt, kind, el))
	return acc / total / 100.0 if total > 0.0 else 1.0


## Mistura do golpe de uma arma: `base` com a fatia do encantamento no elemento dele. `bonus` é o que o
## encanto soma ao multiplicador de dano (Game.enchant_damage) e `damage_mod` o multiplicador inteiro
## (Game.mod("damage"), que já inclui o bônus): a fatia é bonus / damage_mod. Sem encanto devolve `base`.
static func weapon_mix(base: String, enchant_el: String, bonus: float, damage_mod: float):
	if enchant_el == "" or enchant_el == base or not known(enchant_el) or bonus <= 0.0:
		return base
	var share := clampf(bonus / maxf(damage_mod, 0.01), 0.0, 1.0)
	return {base: 1.0 - share, enchant_el: share}


## Dica do número de dano: "Imune", "Fraco!", "Resistiu" ou "" (perto do neutro).
static func hint(m: float) -> String:
	if m <= 0.0:
		return "Imune"
	if m >= 1.0 + HINT_MIN:
		return "Fraco!"
	if m <= 1.0 - HINT_MIN:
		return "Resistiu"
	return ""


## Cor do número de dano para a dica (`normal` quando não há dica).
static func hint_color(m: float, normal: Color) -> Color:
	match hint(m):
		"Imune":
			return C_IMMUNE
		"Fraco!":
			return C_WEAK
		"Resistiu":
			return C_RESIST
	return normal


## Elemento base de um projétil do jogador: `kind` do projétil, `staff` = elemento do som do cajado
## (Sfx.staff_element: "fire", "frost" ou "arcane") e `fx` do item/habilidade.
static func projectile_element(kind: String, staff: String, fx: String) -> String:
	if fx == "glacial":
		return "gelo"   # Flecha Glacial
	match kind:
		"bolt":
			match staff:
				"fire":
					return "fogo"
				"frost":
					return "gelo"
			return NEUTRAL
		"light_orb", "holy_lance":
			return "sagrado"
	return "fisico"
