class_name WeatherRules
extends RefCounted
## Regras puras do clima (sem cena nem autoload): qual clima vale em cada instante e como o chão
## acumula água e neve. O cronograma sai só do relógio (hora Unix): servidor e clientes chegam ao
## mesmo clima sem trocar nada pela rede. Por enquanto o clima é só visual; quando vierem mecânicas,
## o servidor consulta estas mesmas funções.

enum Kind { SUN, RAIN, SNOW, WIND }
const NAMES := ["sol", "chuva", "neve", "vento"]
## Cada clima dura um trecho fixo do relógio.
const SEGMENT := 420.0
## Peso de sorteio de cada clima (sol, chuva, neve, vento).
const WEIGHTS := [40, 25, 17, 18]
const SEED := 7349

## Intensidades-alvo de cada clima: chuva caindo, neve caindo, vento e nuvens (0..1).
const TARGETS := {
	Kind.SUN: {"rain": 0.0, "snow": 0.0, "wind": 0.12, "cloud": 0.0},
	Kind.RAIN: {"rain": 1.0, "snow": 0.0, "wind": 0.35, "cloud": 1.0},
	Kind.SNOW: {"rain": 0.0, "snow": 1.0, "wind": 0.2, "cloud": 0.75},
	Kind.WIND: {"rain": 0.0, "snow": 0.0, "wind": 1.0, "cloud": 0.3},
}
## Segundos para uma intensidade ir de 0 a 1 (a troca de clima é gradual).
const BLEND := 30.0

## Chão: segundos para encharcar com chuva forte / cobrir de neve com neve forte.
const WET_FILL := 60.0
const SNOW_FILL := 100.0
## Derretimento (segundos para derreter tudo): sempre, com sol pleno e com chuva.
const MELT_BASE := 900.0
const MELT_SUN := 90.0
const MELT_RAIN := 60.0
## Secagem (segundos para secar tudo): sempre, com sol pleno e com vento forte. Somadas, um chão
## encharcado seca em ~1,5 min de sol e ~1 min de vento forte (as poças somem um pouco antes).
const DRY_BASE := 400.0
const DRY_SUN := 150.0
const DRY_WIND := 90.0
## Enquanto neva a água do chão congela/some sob a neve (segundos para sumir toda).
const DRY_SNOW := 80.0
## Fração da neve derretida que vira água no chão: o degelo deixa o chão úmido, com poucas poças.
const MELT_TO_WATER := 0.6


## Clima no instante t (segundos Unix).
static func kind_at(t: float, seed_value := SEED) -> int:
	return kind_of_segment(segment_of(t), seed_value)


static func segment_of(t: float) -> int:
	return int(floor(t / SEGMENT))


## Sorteio do trecho i. Se repetir o clima do trecho anterior, sorteia de novo uma vez:
## o tempo muda com mais frequência, mas ainda pode repetir.
static func kind_of_segment(i: int, seed_value := SEED) -> int:
	var k := _roll(i, seed_value, 0)
	if k == _roll(i - 1, seed_value, 0):
		k = _roll(i, seed_value, 1)
	return k


static func _roll(i: int, seed_value: int, salt: int) -> int:
	var total := 0
	for w in WEIGHTS:
		total += w
	var r := _hash(i * 3 + salt * 7919 + seed_value * 104729) % total
	for k in WEIGHTS.size():
		r -= WEIGHTS[k]
		if r < 0:
			return k
	return Kind.SUN


## Hash inteiro estável (o mesmo em qualquer máquina), sempre >= 0.
static func _hash(x: int) -> int:
	x = x & 0xFFFFFFFF
	x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0xFFFFFFFF
	x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0xFFFFFFFF
	return x ^ (x >> 16)


## Direção do vento (vetor xz unitário) no instante t: gira devagar, sem saltos.
static func wind_dir_at(t: float) -> Vector2:
	var a := 0.7 + 0.6 * sin(t / 500.0) + 0.3 * sin(t / 170.0 + 1.3)
	return Vector2(cos(a), sin(a))


## Rajada (0..1) no instante t: o vento forte pulsa em vez de soprar constante.
static func gust_at(t: float) -> float:
	var g := 0.5 + 0.3 * sin(t * 0.6) * sin(t * 0.23 + 1.0) + 0.2 * sin(t * 0.9 + 0.4)
	return clampf(g, 0.0, 1.0)


## Aproxima as intensidades atuais (rain, snow, wind, cloud) das do clima `kind`.
static func blend_toward(s: Dictionary, kind: int, dt: float) -> void:
	var tgt: Dictionary = TARGETS[kind]
	for k in tgt:
		s[k] = move_toward(s[k], tgt[k], dt / BLEND)


## Um passo do chão. `s` tem as intensidades atuais e o estado do chão (wet, cover), que é atualizado.
## Neve cobre o chão enquanto neva; sem neve ela derrete (rápido com sol e com chuva) e vira água.
## Chuva encharca e forma poças; sem chuva o chão seca (mais rápido com sol e vento).
static func step_ground(s: Dictionary, dt: float) -> void:
	var sun := 1.0 - float(s.cloud)
	var cover: float = s.cover
	var wet: float = s.wet
	cover += float(s.snow) * dt / SNOW_FILL
	var melt := 0.0
	if s.snow < 0.3:
		melt = minf(cover, dt * (1.0 / MELT_BASE + sun / MELT_SUN + float(s.rain) / MELT_RAIN))
	cover -= melt
	wet += float(s.rain) * dt / WET_FILL + melt * MELT_TO_WATER
	# sob a neve o chão quase não seca: a água do degelo fica e seca depois que a neve some
	var under := 1.0 - 0.85 * clampf(cover, 0.0, 1.0)
	var dry := dt * ((1.0 / DRY_BASE + sun / DRY_SUN + float(s.wind) / DRY_WIND) * under
			+ float(s.snow) / DRY_SNOW) * (1.0 - float(s.rain))
	wet -= dry
	s.cover = clampf(cover, 0.0, 1.0)
	s.wet = clampf(wet, 0.0, 1.0)


## Estado inicial (tudo calmo e seco).
static func new_state() -> Dictionary:
	return {"rain": 0.0, "snow": 0.0, "wind": 0.12, "cloud": 0.0, "wet": 0.0, "cover": 0.0}


## Avança o estado `s` de t0 até t1 seguindo o cronograma (passos de `step` segundos).
## `kind_fn` (opcional) troca o cronograma do relógio por outro (clima forçado na depuração).
static func simulate(s: Dictionary, t0: float, t1: float, step := 5.0, kind_fn := Callable()) -> void:
	var t := t0
	while t < t1:
		var dt := minf(step, t1 - t)
		var k: int = kind_fn.call(t) if kind_fn.is_valid() else kind_at(t)
		blend_toward(s, k, dt)
		step_ground(s, dt)
		t += dt
