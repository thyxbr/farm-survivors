class_name SeasonRules
extends RefCounted
## Regras puras das estações e da hora do jogo (sem cena nem autoload). Como o clima (WeatherRules),
## tudo sai do relógio: a estação e a hora valem o mesmo para todos que olharem o mesmo instante.
## No multiplayer o relógio é o do servidor (o autoload Weather recebe a diferença ao entrar), então
## o contador até a próxima estação e a hora do jogo batem entre os jogadores.
##
## Cada estação dura LENGTH segundos reais e tem DAYS_PER_SEASON dias do jogo. A ordem é primavera,
## verão, outono, inverno, e o ano recomeça. O outono muda o visual (folhas, capim, luz e clima com mais
## chuva e vento) e todas mudam o dia e a noite (DayNightRules.SEASONS: duração do dia, altura do sol, luar).

enum Kind { SPRING, SUMMER, AUTUMN, WINTER }
const NAMES := ["primavera", "verão", "outono", "inverno"]
const TITLES := ["Primavera", "Verão", "Outono", "Inverno"]
## Cor de cada estação no HUD.
const COLORS := [Color(0.62, 0.9, 0.55), Color(1.0, 0.85, 0.35), Color(1.0, 0.58, 0.25), Color(0.7, 0.86, 1.0)]

## Duração de uma estação em segundos reais (17 min).
const LENGTH := 1020.0
## Dias do jogo em cada estação: um dia do jogo dura LENGTH / DAYS_PER_SEASON (8,5 min reais).
const DAYS_PER_SEASON := 2
## Segundos (reais) que a troca de visual leva de uma estação para a outra.
const BLEND := 45.0


## Estação no instante t (segundos Unix).
static func kind_at(t: float) -> int:
	return posmod(index_of(t), 4)


## Número da estação desde a época Unix (cresce 1 a cada troca).
static func index_of(t: float) -> int:
	return int(floor(t / LENGTH))


## Segundos reais até a próxima estação.
static func time_left(t: float) -> float:
	return LENGTH - fposmod(t, LENGTH)


static func next_kind(kind: int) -> int:
	return (kind + 1) % 4


## Fração (0..1) da estação `kind` no instante t, com a troca suave: entra nos últimos BLEND/2
## segundos da estação anterior e sai nos primeiros BLEND/2 da seguinte.
static func weight_at(t: float, kind: int) -> float:
	var into := fposmod(t, LENGTH)   # segundos desde o começo da estação atual
	var cur := kind_at(t)
	var half := BLEND * 0.5
	# perto do começo: mistura com a anterior; perto do fim: mistura com a próxima
	if into < half:
		var a := 0.5 + 0.5 * into / half   # 0,5 na virada, 1 depois de half
		return a if cur == kind else (1.0 - a if posmod(cur - 1, 4) == kind else 0.0)
	var left := LENGTH - into
	if left < half:
		var b := 0.5 + 0.5 * left / half
		return b if cur == kind else (1.0 - b if next_kind(cur) == kind else 0.0)
	return 1.0 if cur == kind else 0.0


## Peso (0..1) de cada estação no instante t, na ordem de Kind (somam 1; na troca, duas se misturam).
static func weights_at(t: float) -> Array:
	var w := [0.0, 0.0, 0.0, 0.0]
	for k in 4:
		w[k] = weight_at(t, k)
	return w


## Hora do jogo no instante t: {"day": dia dentro da estação (1..DAYS_PER_SEASON), "hour", "minute"}.
static func clock_at(t: float) -> Dictionary:
	var day_len := LENGTH / DAYS_PER_SEASON
	var into_day := fposmod(t, day_len) / day_len   # 0..1 do dia
	var minutes := int(floor(into_day * 1440.0))
	return {
		"day": int(floor(fposmod(t, LENGTH) / day_len)) + 1,
		"hour": floori(minutes / 60.0),
		"minute": minutes % 60,
	}


## "HH:MM" da hora do jogo.
static func clock_text(t: float) -> String:
	var c := clock_at(t)
	return "%02d:%02d" % [c.hour, c.minute]


## "m:ss" de uma duração em segundos.
static func countdown_text(secs: float) -> String:
	var s := int(ceil(maxf(secs, 0.0)))
	return "%d:%02d" % [floori(s / 60.0), s % 60]
