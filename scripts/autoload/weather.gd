extends Node
## Clima do mundo: sol, chuva, neve e ventos fortes. Por enquanto só visual (sem efeito no jogo).
## O cronograma sai do relógio (WeatherRules): todos os jogadores e o servidor veem o mesmo clima
## sem rede. Este autoload só guarda o estado atual; quem desenha é o WeatherFX da cena
## (scripts/world/weather_fx.gd), presente em Valdoria e na praça.
##
## Depuração: `--weather=neve,sol` força uma sequência de climas (sol, chuva, neve, vento), cada um
## por `--weather-step=60` segundos, e o último fica; o primeiro já começa assentado (chão coberto,
## encharcado...). Ex.: `--weather=neve,sol --weather-step=10` mostra a neve derretendo.

signal changed(kind: int)

## Clima atual (WeatherRules.Kind) e intensidades suavizadas: rain/snow (caindo), wind, cloud,
## e o chão: wet (água/poças) e cover (neve acumulada), todos 0..1.
var kind := WeatherRules.Kind.SUN
var state := WeatherRules.new_state()
var wind_dir := Vector2(1, 0)
var gust := 0.5
## Fase do vento: acumula a força do vento ao longo do tempo. Os shaders somam isto ao TIME para o
## balanço acelerar quando venta, sem saltos (TIME × força faria a fase pular a cada rajada).
var phase := 0.0
## WeatherFX ativo na cena (null fora de Valdoria/praça: aí nada de clima visual, nem na capa).
var fx: Node = null

var _forced: Array = []
var _forced_step := 60.0
var _forced_t0 := 0.0
var _clock := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--weather="):
			for n in a.substr(10).split(",", false):
				var i := WeatherRules.NAMES.find(n.strip_edges().to_lower())
				if i >= 0:
					_forced.append(i)
				else:
					push_warning("--weather: clima desconhecido '%s' (use sol, chuva, neve, vento)" % n)
		elif a.begins_with("--weather-step="):
			_forced_step = maxf(5.0, a.substr(15).to_float())
	_clock = _now()
	if _forced.is_empty():
		# reconstrói os últimos 40 min do relógio: quem entra agora vê as poças da chuva de antes
		WeatherRules.simulate(state, _clock - 2400.0, _clock)
	else:
		_forced_t0 = _clock
		# o primeiro clima forçado já começa assentado
		var first: int = _forced[0]
		WeatherRules.simulate(state, 0.0, 240.0, 5.0, func(_t: float) -> int: return first)
	kind = _kind_at(_clock)
	wind_dir = WeatherRules.wind_dir_at(_clock)
	gust = WeatherRules.gust_at(_clock)


func _process(delta: float) -> void:
	_clock += delta
	var k := _kind_at(_clock)
	if k != kind:
		kind = k
		changed.emit(k)
	WeatherRules.blend_toward(state, kind, delta)
	WeatherRules.step_ground(state, delta)
	wind_dir = WeatherRules.wind_dir_at(_clock)
	gust = WeatherRules.gust_at(_clock)
	phase = fmod(phase + delta * wind_now(), 10000.0)


func _now() -> float:
	return Time.get_unix_time_from_system()


func _kind_at(t: float) -> int:
	if _forced.is_empty():
		return WeatherRules.kind_at(t)
	var i := mini(int(floor((t - _forced_t0) / _forced_step)), _forced.size() - 1)
	return _forced[i]   # o último clima da lista fica


## Nome do clima atual ("sol", "chuva", "neve", "vento").
func kind_name() -> String:
	return WeatherRules.NAMES[kind]


## Força do vento agora, com a rajada (0..~1.3).
func wind_now() -> float:
	return float(state.wind) * (0.7 + 0.6 * gust)


## Vento para efeitos de cena (capa, capim): 0 onde não há WeatherFX.
func visual_wind() -> float:
	return wind_now() if is_instance_valid(fx) else 0.0
