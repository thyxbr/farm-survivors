class_name DayNightRules
extends RefCounted
## Regras puras do dia e da noite (sem cena nem autoload). Como o clima, tudo sai do relógio: a hora do
## jogo vale o mesmo para todos que olharem o mesmo instante (no multiplayer o relógio do Weather é
## acertado pelo do servidor). Quem desenha é o DayNightFX (scripts/world/day_night_fx.gd).
##
## Um dia do jogo dura DAY_LENGTH segundos reais. O valor e a conta da hora são os mesmos do relógio das
## estações (SeasonRules: LENGTH / DAYS_PER_SEASON), para a hora do HUD bater com a luz.
##
## A estação muda o dia (SEASONS): no verão o sol nasce cedo, se põe tarde e sobe mais; no inverno o dia
## é curto, o sol fica baixo e a noite é longa e mais clara (luar na neve). As funções recebem o dia da
## estação (`day_for`); sem ele valem o nascer e o pôr de SUNRISE e SUNSET (a primavera).

## Duração de um dia do jogo em segundos reais (8,5 min).
const DAY_LENGTH := SeasonRules.LENGTH / SeasonRules.DAYS_PER_SEASON
## Nascer e pôr do sol (hora do jogo). A luz cheia vai de SUNRISE + 1 a SUNSET - 1; a noite fechada,
## de SUNSET + 1 a SUNRISE - 1 (umas 8 h do jogo, menos de 3 min reais).
const SUNRISE := 5.5
const SUNSET := 19.5
## Altura do sol ao meio-dia (graus) na primavera.
const PEAK := 55.0

## Dia de cada estação (SeasonRules.Kind): nascer, pôr, altura do sol ao meio-dia (graus) e força do
## luar (× o da primavera). A noite fechada vai de ~5 h do jogo no verão a ~12 h no inverno.
const SEASONS := [
	{"sunrise": SUNRISE, "sunset": SUNSET, "peak": PEAK, "moon": 1.0},   # primavera
	{"sunrise": 4.75, "sunset": 20.75, "peak": 58.0, "moon": 1.1},      # verão: noite curta, sol alto
	{"sunrise": 6.0, "sunset": 18.75, "peak": 46.0, "moon": 0.9},       # outono
	{"sunrise": 6.75, "sunset": 17.5, "peak": 38.0, "moon": 1.3},       # inverno: noite longa, sol baixo
]


## Dia do jogo para os pesos de cada estação (SeasonRules.weights_at: na troca, duas se misturam).
static func day_for(weights: Array) -> Dictionary:
	var d := {"sunrise": 0.0, "sunset": 0.0, "peak": 0.0, "moon": 0.0}
	var total := 0.0
	for k in SEASONS.size():
		var w: float = weights[k] if k < weights.size() else 0.0
		if w <= 0.0:
			continue
		total += w
		for key in d:
			d[key] += float(SEASONS[k][key]) * w
	if total <= 0.0:
		return (SEASONS[0] as Dictionary).duplicate()
	for key in d:
		d[key] /= total
	return d


## Dia da estação `kind` (sem mistura).
static func day_of(kind: int) -> Dictionary:
	return (SEASONS[posmod(kind, SEASONS.size())] as Dictionary).duplicate()


## Hora do jogo (0..24, com fração) no instante t (segundos Unix).
static func hour_at(t: float) -> float:
	return fposmod(t, DAY_LENGTH) / DAY_LENGTH * 24.0


## Quanto é noite (0 = dia claro, 1 = noite fechada), com o crepúsculo suave.
static func night(hour: float, rise := SUNRISE, fall := SUNSET) -> float:
	var h := fposmod(hour, 24.0)
	if h < 12.0:
		return 1.0 - smoothstep(rise - 0.75, rise + 0.75, h)
	return smoothstep(fall - 0.75, fall + 0.75, h)


## Força do sol (0..1): só entre o nascer e o pôr, subindo e descendo na primeira e na última hora.
static func sun(hour: float, rise := SUNRISE, fall := SUNSET) -> float:
	var h := fposmod(hour, 24.0)
	return smoothstep(rise, rise + 1.0, h) * (1.0 - smoothstep(fall - 1.0, fall, h))


## Força da lua (0..1): a luz da noite, que entra quando o sol já sumiu (a direção troca no escuro).
static func moon(hour: float, rise := SUNRISE, fall := SUNSET) -> float:
	var h := fposmod(hour, 24.0)
	if h < 12.0:
		return 1.0 - smoothstep(rise - 1.0, rise, h)
	return smoothstep(fall, fall + 1.0, h)


## Luz dourada do começo e do fim do dia (0..1), no pico perto do nascer e do pôr do sol.
static func golden(hour: float, rise := SUNRISE, fall := SUNSET) -> float:
	var h := fposmod(hour, 24.0)
	var morning := 1.0 - absf(h - (rise + 0.6)) / 1.6
	var evening := 1.0 - absf(h - (fall - 0.6)) / 1.6
	return clampf(maxf(morning, evening), 0.0, 1.0)


## Avanço do sol no céu (0 no nascer, 0,5 ao meio-dia, 1 no pôr). Fora do dia fica preso nas pontas.
static func sun_progress(hour: float, rise := SUNRISE, fall := SUNSET) -> float:
	return clampf((fposmod(hour, 24.0) - rise) / (fall - rise), 0.0, 1.0)


## Rotação do sol (graus, como em DirectionalLight3D.rotation_degrees): baixo e quente nas pontas do dia,
## a `peak` graus ao meio-dia (55° na primavera), cruzando de leste a oeste. Ao meio-dia bate com o sol
## fixo de antes (-45°, -35°) o bastante para a luz desenhada (docs/ESTILO_TOON.md) continuar valendo.
static func sun_rotation(hour: float, rise := SUNRISE, fall := SUNSET, peak := PEAK) -> Vector3:
	var p := sun_progress(hour, rise, fall)
	var elevation := 18.0 + (peak - 18.0) * sin(p * PI)
	return Vector3(-elevation, lerpf(-95.0, 25.0, p), 0.0)


## Rotação da lua: fixa, alta e do lado oposto ao sol da tarde (a sombra da noite não fica andando).
const MOON_ROTATION := Vector3(-52.0, 150.0, 0.0)


## Uma luz da cidade acende quando a noite passa do seu limiar (0..1). Cada lampião tem um limiar um
## pouco diferente (`offset` 0..1) para as luzes não acenderem todas no mesmo quadro.
static func lamp_on(night_amount: float, offset: float) -> float:
	var at := 0.25 + 0.3 * clampf(offset, 0.0, 1.0)
	return smoothstep(at, at + 0.12, night_amount)


## "HH:MM" da hora (0..24).
static func hour_text(hour: float) -> String:
	var minutes := int(floor(fposmod(hour, 24.0) * 60.0))
	return "%02d:%02d" % [floori(minutes / 60.0), minutes % 60]


## Lê "21", "21:30" ou "21.5" como hora do jogo; -1 se não for uma hora válida.
static func parse_hour(s: String) -> float:
	s = s.strip_edges().replace("h", ":")
	if s.ends_with(":"):
		s = s.trim_suffix(":")
	var h := -1.0
	if ":" in s:
		var p := s.split(":")
		if p.size() == 2 and p[0].is_valid_int() and (p[1] == "" or p[1].is_valid_int()):
			h = p[0].to_int() + (p[1].to_int() if p[1] != "" else 0) / 60.0
	elif s.is_valid_float():
		h = s.to_float()
	return h if h >= 0.0 and h < 24.0 else -1.0
