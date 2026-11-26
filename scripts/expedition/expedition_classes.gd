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

const TANK := "tank"

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
}

## Estilos de build (campo "style" das bênçãos de classe) -> nome mostrado na carta.
const STYLES := {
	"defesa": "Defesa",
	"escudo": "Escudo",
	"controle": "Controle",
	"ataque": "Ataque",
}

## Nome de cada classe com identidade (para a carta: "Tank · Escudo").
const CLASS_NAMES := {TANK: "Tank"}


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
