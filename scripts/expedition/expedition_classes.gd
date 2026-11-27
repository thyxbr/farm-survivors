class_name ExpeditionClasses
extends RefCounted
## Identidade de combate das classes na expedição (puro: sem cena, sem autoload; testado à parte).
##
## Cada classe pode ter, só enquanto a expedição dura:
##   - uma PASSIVA de classe: run_mods que o modo da expedição soma em toda conta (_sync_mods), antes das bênçãos;
##   - BÊNÇÃOS DE CLASSE: entradas de ExpeditionUpgrades.DATA com "class" (só saem para essa classe), "style"
##     (estilo de build, mostrado na carta) e "needs" (só saem com uma dessas habilidades já levada dos altares).
## Tudo passa pelo mesmo caminho das bênçãos comuns: ExpeditionRun.modifiers -> _sync_mods -> Game.run_mods, que a
## volta à Guilda (vitória, derrota, abandono, menu) zera. Nada disso é salvo no personagem.
##
## TANK (Fase E): guardião de linha de frente. Começa só com a maça e o bloqueio do escudo (botão direito) e a
## passiva Linha de Frente; os altares trazem o kit do escudo (Égide, Terremoto, Provocação, Martelo, Grito) e as
## bênçãos do Tank empurram a build para um de quatro estilos:
##   defesa   — aguentar a horda (Linha de Frente mais forte, regeneração);
##   escudo   — bloqueio e Égide (mais fôlego no bloqueio, Égide mais dura, Égide que explode o que segurou);
##   controle — prender e atordoar (Provocação e atordoamentos mais longos);
##   ataque   — bater com o que aguenta (dano pela defesa, cura por abate).
##
## GUERREIRO (o Lutador; Fase E, etapa 2): pressão constante. Começa só com o combo da espada e a passiva Ímpeto
## (ExpeditionMomentum): cada golpe que acerta e cada abate dão um acúmulo, e cada acúmulo dá dano e velocidade; parar
## de atacar esvazia. As bênçãos do Guerreiro levam a build para um de quatro estilos:
##   agressivo  — mais Ímpeto e mais dano por acúmulo, embalo que dura mais;
##   veloz      — velocidade por acúmulo, fôlego a cada ganho, Investida que embala;
##   resistente — cura e menos dano recebido enquanto pressiona (nunca o que o Tank segura parado);
##   explosivo  — crítico por acúmulo e o 3º golpe do combo com Ímpeto cheio solta tudo numa explosão.

const TANK := "tank"
const WARRIOR := "warrior"

## Passiva Linha de Frente: inimigos (vivos) a até CROWD_RADIUS m contam, até CROWD_MAX deles; cada um corta
## `crowd_guard` do dano recebido; o corte total nunca passa de CROWD_CAP (soma com a defesa por multiplicação).
const CROWD_RADIUS := 4.0
const CROWD_MAX := 5
const CROWD_CAP := 0.40
## A partir de quantos inimigos perto a passiva solta faíscas azuis no golpe (para o jogador perceber que ela age).
const CROWD_FX_MIN := 2

## Estilhaços da Égide: raio da explosão (m) e empurrão (m/s) quando a Égide se desfaz ou quebra.
const BURST_RADIUS := 4.5
const BURST_PUSH := 7.0
## A explosão só sai se a Égide segurou pelo menos isto (evita estalo à toa ao soltar logo a tecla).
const BURST_MIN_ABSORBED := 5.0

## Passiva de cada classe na expedição. "add": chaves de Game.run_mods (ExpeditionUpgrades.RUN_MOD_KEYS).
const PASSIVES := {
	TANK: {
		"name": "Linha de Frente",
		"desc": "Cada inimigo a até 4 m corta 4% do dano que você recebe (até 5: -20%). Segure o botão direito para bloquear com o escudo.",
		"add": {"crowd_guard": 0.04},
	},
	WARRIOR: {
		"name": "Ímpeto",
		"desc": "Cada golpe que acerta e cada abate dão 1 de Ímpeto (até 5): +3% de dano e +1,5% de velocidade por acúmulo. Fique 2,5 s sem acertar e ele se esvai.",
		"add": {"momentum_max": 5.0, "momentum_dmg": 0.03, "momentum_speed": 0.015},
	},
}

## Estilos de build (campo "style" das bênçãos de classe) -> nome mostrado na carta.
const STYLES := {
	"defesa": "Defesa",
	"escudo": "Escudo",
	"controle": "Controle",
	"ataque": "Ataque",
	"agressivo": "Agressivo",
	"veloz": "Veloz",
	"resistente": "Resistente",
	"explosivo": "Explosivo",
}

## Nome de cada classe com identidade (para a carta: "Tank · Escudo").
const CLASS_NAMES := {TANK: "Tank", WARRIOR: "Guerreiro"}

## Tetos do que o Ímpeto dá com todos os acúmulos e bênçãos (pressão forte, mas sem virar imortal nem um tiro só).
const MOMENTUM_DMG_CAP := 0.40      ## dano a mais
const MOMENTUM_SPEED_CAP := 0.25    ## velocidade a mais
const MOMENTUM_CRIT_CAP := 0.20     ## chance de crítico a mais
const MOMENTUM_GUARD_CAP := 0.20    ## corte no dano recebido (o Tank chega a 40% parado na horda)
## Explosão de Ímpeto (3º golpe do combo com o Ímpeto cheio): raio (m), empurrão (m/s) e o mínimo de acúmulos.
const MOMENTUM_BURST_RADIUS := 3.5
const MOMENTUM_BURST_PUSH := 6.0
const MOMENTUM_BURST_MIN := 3
## Cura por ganho de Ímpeto nunca passa disto (por ganho), com qualquer bênção.
const MOMENTUM_HEAL_CAP := 3.0


static func has_identity(cls: String) -> bool:
	return PASSIVES.has(cls)


## Passiva da classe ({} se a classe não tem uma).
static func passive(cls: String) -> Dictionary:
	return PASSIVES.get(cls, {})


## run_mods que a passiva da classe soma ({} sem passiva).
static func passive_mods(cls: String) -> Dictionary:
	return (PASSIVES.get(cls, {}) as Dictionary).get("add", {})


## `base` (run_mods) com a passiva da classe somada por cima. Não mexe em `base`.
static func apply_passive(base: Dictionary, cls: String) -> Dictionary:
	var out := base.duplicate()
	var add := passive_mods(cls)
	for k in add:
		out[k] = float(out.get(k, 0.0)) + float(add[k])
	return out


## Linha de Frente: multiplicador do dano recebido com `n` inimigos perto e `per` de corte por inimigo.
## 1.0 sem ninguém perto (ou sem a passiva); nunca abaixo de 1 - CROWD_CAP.
static func crowd_mult(n: int, per: float) -> float:
	if n <= 0 or per <= 0.0 or not is_finite(per):
		return 1.0
	return 1.0 - minf(CROWD_CAP, per * float(mini(n, CROWD_MAX)))


## Escudo do bloqueio com as bênçãos de escudo: `block_add` a mais de dano segurado e `guard_add` a menos de
## fôlego gasto (ShieldRules ainda aplica os tetos dele: 95% e 60%). Não mexe em `it`.
static func block_item(it: Dictionary, block_add: float, guard_add: float) -> Dictionary:
	if block_add <= 0.0 and guard_add <= 0.0:
		return it
	var out := it.duplicate()
	out["block"] = float(it.get("block", ShieldRules.DEFAULT_BLOCK)) + maxf(block_add, 0.0)
	out["guard"] = float(it.get("guard", 0.0)) + maxf(guard_add, 0.0)
	return out


## Estilhaços da Égide: dano da explosão para `absorbed` de dano segurado e `frac` da bênção. 0 sem a bênção ou
## se a Égide quase não segurou nada.
static func burst_damage(absorbed: float, frac: float) -> float:
	if frac <= 0.0 or absorbed < BURST_MIN_ABSORBED:
		return 0.0
	return absorbed * frac


## Revide do Bastião: multiplicador de dano a somar (`per` por ponto de defesa).
static func guard_damage_bonus(defense: float, per: float) -> float:
	if per <= 0.0:
		return 0.0
	return maxf(defense, 0.0) * per


## Texto do estilo na carta: "Tank · Escudo" ("" para bênção comum).
static func style_text(cls: String, style: String) -> String:
	if cls == "":
		return ""
	var n := str(CLASS_NAMES.get(cls, cls.capitalize()))
	return n + (" · " + str(STYLES[style]) if STYLES.has(style) else "")


# ---------------------------------------------------------------- Ímpeto (Guerreiro)
static func _per(stacks: int, per: float) -> float:
	if stacks <= 0 or per <= 0.0 or not is_finite(per):
		return 0.0
	return float(stacks) * per


## Dano a mais (soma no multiplicador de dano, como as bênçãos) com `stacks` de Ímpeto e `per` por acúmulo.
static func momentum_damage(stacks: int, per: float) -> float:
	return minf(MOMENTUM_DMG_CAP, _per(stacks, per))


## Multiplicador de velocidade de movimento (1.0 sem Ímpeto).
static func momentum_speed(stacks: int, per: float) -> float:
	return 1.0 + minf(MOMENTUM_SPEED_CAP, _per(stacks, per))


## Chance de crítico a mais (Brecha).
static func momentum_crit(stacks: int, per: float) -> float:
	return minf(MOMENTUM_CRIT_CAP, _per(stacks, per))


## Multiplicador do dano recebido (Couraça do Embalo; 1.0 sem a bênção).
static func momentum_guard(stacks: int, per: float) -> float:
	return 1.0 - minf(MOMENTUM_GUARD_CAP, _per(stacks, per))


## Vida curada por ganho de Ímpeto (Sangue em Brasa).
static func momentum_heal(gained: int, per: float) -> float:
	if gained <= 0 or per <= 0.0 or not is_finite(per):
		return 0.0
	return minf(MOMENTUM_HEAL_CAP, per) * float(gained)


## Explosão de Ímpeto: dano em volta para o dano corpo a corpo `melee`, `frac` da bênção e `stacks` gastos
## (proporcional ao quanto estava cheio, contra o teto base 5). 0 sem a bênção ou com pouco Ímpeto.
static func momentum_burst(melee: float, frac: float, stacks: int) -> float:
	if frac <= 0.0 or not is_finite(frac) or stacks < MOMENTUM_BURST_MIN or melee <= 0.0:
		return 0.0
	return melee * frac * minf(float(stacks) / 5.0, 1.4)
