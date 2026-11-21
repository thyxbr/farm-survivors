class_name ForgeRules
extends RefCounted
## Habilidades do Forjador Rúnico (chefe das Galerias Profundas): qual golpe vem agora, a Martelada em cone, as
## faixas de metal derretido que ela deixa, o Respiro da Fornalha (em volta dele), o Escudo Rúnico (imune até o
## grupo quebrar as 3 runas da sala) e o Superaquecimento da fase 2 (mais rápido, mas leva mais dano).
## Puro: sem autoloads (roda no runner de unitários). O servidor e o cliente chegam aos mesmos pontos pela
## direção/semente que vai no snapshot.

## Martelada: cone de CONE_LEN m à frente, CONE_HALF graus para cada lado; quem está colado nele (CONE_NEAR m)
## leva de qualquer jeito, menos pelas costas. O martelo bate HAMMER_T s depois do aviso.
const CONE_LEN := 9.0
const CONE_HALF := 36.0
const CONE_NEAR := 2.2
const HAMMER_T := 1.25
const HAMMER_DUR := 2.4
## Ele para e bate quando o alvo está a até HAMMER_RANGE m (dentro do cone, com folga para o alvo recuar).
const HAMMER_RANGE := 6.5
## Metal derretido: TRAILS faixas em leque dentro do cone (TRAILS_HOT superaquecido), de TRAIL_START m dele até a
## ponta do cone, com TRAIL_HALF m para cada lado; ficam TRAIL_LIFE s e queimam a cada TRAIL_TICK s quem pisa.
const TRAILS := 3
const TRAILS_HOT := 5
const TRAIL_START := 2.0
const TRAIL_HALF := 0.8
const TRAIL_LIFE := 6.0
const TRAIL_LIFE_HOT := 8.0
const TRAIL_TICK := 0.5
## Dano de cada tique da faixa, como fração do dano do chefe.
const TRAIL_DMG := 0.3
## Respiro da Fornalha: a cada VENT_EVERY golpes, se o alvo está a até VENT_R m, labaredas saem pelas frestas e
## queimam todos em volta dele (pune quem fica colado nas costas, onde o martelo não chega).
const VENT_EVERY := 3
const VENT_R := 5.5
const VENT_T := 1.1
const VENT_DUR := 2.0
## Escudo Rúnico: o primeiro quando a vida cai a SHIELD_FIRST; os seguintes SHIELD_CD s depois de o anterior cair.
## Nascem RUNES runas a RUNE_MIN..RUNE_MAX m do centro da sala.
const SHIELD_FIRST := 0.8
const SHIELD_CD := 30.0
const SHIELD_T := 1.3
const SHIELD_DUR := 2.2
const RUNES := 3
const RUNE_MIN := 9.0
const RUNE_MAX := 12.0
## Fase 2 (abaixo de OVERHEAT_HP da vida): os golpes levam OVERHEAT_TIME do tempo normal e ele leva
## OVERHEAT_TAKEN vezes o dano.
const OVERHEAT_HP := 0.5
const OVERHEAT_TIME := 0.72
const OVERHEAT_TAKEN := 1.3
## Bit de `flags` do snapshot que diz "com o escudo de pé" (acima do ponto/semente, bits 2..17; cabe em float32).
const SHIELD_FLAG := 1 << 18


## O golpe da vez. `n` = golpes já dados na luta; `want_shield` = está na hora do Escudo Rúnico.
static func attack(n: int, dist: float, want_shield: bool) -> String:
	if want_shield:
		return "rune_shield"
	if n % VENT_EVERY == VENT_EVERY - 1 and dist <= VENT_R:
		return "vent"
	return "hammer"


## Está na hora de erguer o escudo? `hp_frac` = vida/vida máxima; `shields` = escudos já erguidos na luta;
## `since_fall` = segundos desde que o último caiu.
static func should_shield(hp_frac: float, shields: int, since_fall: float, shielded: bool) -> bool:
	if shielded:
		return false
	if shields == 0:
		return hp_frac <= SHIELD_FIRST
	return since_fall >= SHIELD_CD


## O escudo cai quando não sobra runa viva.
static func shield_down(runes_alive: int) -> bool:
	return runes_alive <= 0


## Dano que ele leva de um acerto de `amount`: nada com o escudo de pé, mais quando superaquecido.
static func taken(amount: float, shielded: bool, overheated: bool) -> float:
	if shielded:
		return 0.0
	return amount * (OVERHEAT_TAKEN if overheated else 1.0)


## Quanto dura cada tempo de golpe (aviso, duração): menor quando superaquecido.
static func time_scale(overheated: bool) -> float:
	return OVERHEAT_TIME if overheated else 1.0


static func _flat(v: Vector3) -> Vector3:
	var d := Vector3(v.x, 0.0, v.z)
	return d.normalized() if d.length() > 0.001 else Vector3.FORWARD


## `p` leva a Martelada dada de `origin` na direção `dir`?
static func in_cone(origin: Vector3, dir: Vector3, p: Vector3) -> bool:
	var v := Vector3(p.x - origin.x, 0.0, p.z - origin.z)
	var dist := v.length()
	if dist > CONE_LEN:
		return false
	if dist < 0.05:
		return true
	var c := v.dot(_flat(dir)) / dist
	if dist <= CONE_NEAR:
		return c > 0.0   # colado nele: basta estar do lado da frente
	return c >= cos(deg_to_rad(CONE_HALF))


## Direções das faixas de metal derretido (no plano, normalizadas), em leque dentro do cone.
static func trail_dirs(dir: Vector3, overheated: bool) -> Array:
	var d := _flat(dir)
	var n := TRAILS_HOT if overheated else TRAILS
	var span := CONE_HALF - 6.0   # as faixas de fora ficam um pouco para dentro da borda do cone
	var out := []
	for i in n:
		var a := lerpf(-span, span, float(i) / float(n - 1))
		out.append(d.rotated(Vector3.UP, deg_to_rad(a)))
	return out


## Comprimento de uma faixa e o seu centro (ela vai de TRAIL_START m até a ponta do cone).
static func trail_len() -> float:
	return CONE_LEN - TRAIL_START


static func trail_center(origin: Vector3, dir: Vector3) -> Vector3:
	return origin + _flat(dir) * (TRAIL_START + trail_len() / 2.0)


## `p` está pisando na faixa que sai de `origin` na direção `dir`?
static func in_trail(origin: Vector3, dir: Vector3, p: Vector3) -> bool:
	var d := _flat(dir)
	var v := Vector3(p.x - origin.x, 0.0, p.z - origin.z)
	var along := v.dot(d)
	if along < TRAIL_START or along > CONE_LEN:
		return false
	return (v - d * along).length() <= TRAIL_HALF


static func trail_life(overheated: bool) -> float:
	return TRAIL_LIFE_HOT if overheated else TRAIL_LIFE


## Onde nascem as runas do escudo: em volta de `center` (o centro da luta), uma para cada lado e uma à frente
## (`facing` = de onde vem o grupo), com o ângulo e a distância sorteados pela semente.
static func rune_points(seed: int, center: Vector3, facing: Vector3, n: int = RUNES) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var f := _flat(facing)
	var out := []
	for i in n:
		var a := 0.0
		if n > 1:
			a = lerpf(-90.0, 90.0, float(i) / float(n - 1))
		a += rng.randf_range(-12.0, 12.0)
		var d := rng.randf_range(RUNE_MIN, RUNE_MAX)
		var v := f.rotated(Vector3.UP, deg_to_rad(a)) * d
		out.append(Vector3(center.x + v.x, center.y, center.z + v.z))
	return out
