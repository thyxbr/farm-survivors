extends Node
## Clima do mundo: sol, chuva, neve e ventos fortes. Por enquanto só visual (sem efeito no jogo).
## O cronograma sai do relógio (WeatherRules): todos os jogadores e o servidor veem o mesmo clima
## sem rede. Este autoload só guarda o estado atual; quem desenha é o WeatherFX da cena
## (scripts/world/weather_fx.gd), presente em Valdoria e na praça.
##
## Estações (SeasonRules): primavera, verão, outono e inverno giram a cada 17 min reais, com uma hora
## do jogo própria. Também saem do relógio; no multiplayer o relógio é o do servidor (_server_clock,
## mandado ao entrar), então estação, contador e hora batem para todos os jogadores.
##
## Depuração: `--season=outono` fixa a estação. `--clock-offset=3600` adianta o relógio deste processo
## (simula um PC com a hora errada: o cliente deve seguir o servidor mesmo assim). `--weather=neve,sol` força uma sequência de climas (sol, chuva, neve, vento), cada um
## por `--weather-step=60` segundos, e o último fica; o primeiro já começa assentado (chão coberto,
## encharcado...). Ex.: `--weather=neve,sol --weather-step=10` mostra a neve derretendo.
## No jogo, o comando de chat `/clima neve` força um clima (só para quem digitou) e `/clima auto` volta.

signal changed(kind: int)
signal season_changed(kind: int)

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

## Estação atual (SeasonRules.Kind) e quanto do visual de outono vale agora (0..1, troca suave).
var season := SeasonRules.Kind.SPRING
var autumn := 0.0

var _forced_season := -1
## Diferença entre o relógio do servidor e o deste computador (0 jogando sozinho).
var _offset := 0.0
## O cliente já recebeu o relógio do servidor (volta a false ao sair).
var synced := false
var _skew := 0.0
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
		elif a.begins_with("--clock-offset="):
			_skew = a.substr(15).to_float()
		elif a.begins_with("--season="):
			_forced_season = SeasonRules.NAMES.find(a.substr(9).strip_edges().to_lower().replace("verao", "verão"))
			if _forced_season < 0:
				push_warning("--season: estação desconhecida '%s' (use primavera, verão, outono, inverno)" % a.substr(9))
	_clock = _now()
	_rebuild()


## Reconstrói o estado a partir do relógio (ao abrir o jogo e quando o relógio do servidor chega).
func _rebuild() -> void:
	state = WeatherRules.new_state()
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
	season = _season_at(_clock)
	autumn = _autumn_at(_clock)


func _process(delta: float) -> void:
	# lido do relógio a cada quadro (não somando delta): quadros lentos não atrasam a estação e o
	# contador, que precisam bater entre os jogadores
	_clock = _now()
	var k := _kind_at(_clock)
	if k != kind:
		kind = k
		changed.emit(k)
	WeatherRules.blend_toward(state, kind, delta)
	WeatherRules.step_ground(state, delta)
	wind_dir = WeatherRules.wind_dir_at(_clock)
	gust = WeatherRules.gust_at(_clock)
	phase = fmod(phase + delta * wind_now(), 10000.0)
	var se := _season_at(_clock)
	if se != season:
		season = se
		season_changed.emit(se)
	autumn = _autumn_at(_clock)


func _now() -> float:
	return _sys() + _offset


## Relógio deste computador (com o --clock-offset de depuração).
func _sys() -> float:
	return Time.get_unix_time_from_system() + _skew


## Relógio do mundo (segundos Unix; no multiplayer, o do servidor).
func now() -> float:
	return _clock


# ---------------------------------------------------------------- relógio do servidor
## Servidor: manda o seu relógio ao jogador que acabou de entrar (antes do _accepted).
func server_send_clock(peer: int) -> void:
	_server_clock.rpc_id(peer, _sys())


@rpc("authority", "call_remote", "reliable")
func _server_clock(t: float) -> void:
	# o relógio veio com meio caminho de atraso
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet != null and enet.get_peer(1) != null:
		t += enet.get_peer(1).get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) * 0.0005
	set_server_time(t)


## Acerta o relógio pelo do servidor (t = hora Unix do servidor agora).
func set_server_time(t: float) -> void:
	_offset = t - _sys()
	synced = true
	_resync()


## Saiu do servidor: volta ao relógio deste computador.
func clear_server_time() -> void:
	synced = false
	if _offset != 0.0:
		_offset = 0.0
		_resync()


func _resync() -> void:
	var c := _now()
	var jump := absf(c - _clock)
	_clock = c
	if jump > 20.0 and _forced.is_empty():
		_rebuild()   # o chão (poças, neve) passa a seguir o relógio novo
	# kind e season acompanham no próximo _process (avisos de troca saem normalmente)


func _season_at(t: float) -> int:
	return _forced_season if _forced_season >= 0 else SeasonRules.kind_at(t)


func _autumn_at(t: float) -> float:
	if _forced_season >= 0:
		return 1.0 if _forced_season == SeasonRules.Kind.AUTUMN else 0.0
	return SeasonRules.weight_at(t, SeasonRules.Kind.AUTUMN)


## Peso (0..1) de cada estação agora, na ordem de SeasonRules.Kind (na troca, duas se misturam).
func season_weights() -> Array:
	if _forced_season >= 0:
		var w := [0.0, 0.0, 0.0, 0.0]
		w[_forced_season] = 1.0
		return w
	return SeasonRules.weights_at(_clock)


## Nome da estação atual ("primavera", "verão", "outono", "inverno").
func season_name() -> String:
	return SeasonRules.NAMES[season]


## Segundos reais até a próxima estação.
func season_left() -> float:
	return SeasonRules.time_left(_clock)


## Hora do jogo ({"day", "hour", "minute"}).
func game_clock() -> Dictionary:
	return SeasonRules.clock_at(_clock)


## Força um clima (WeatherRules.Kind) só nesta máquina, até chamar `release()`. A troca é gradual,
## como uma troca normal. Usado pelo comando de chat `/clima`.
func force(k: int) -> void:
	_forced = [k]
	_forced_t0 = _clock
	_refresh_kind()


## Volta ao cronograma do relógio (o mesmo clima de todos).
func release() -> void:
	_forced = []
	_refresh_kind()


func _refresh_kind() -> void:
	var k := _kind_at(_clock)
	if k != kind:
		kind = k
		changed.emit(k)


func is_forced() -> bool:
	return not _forced.is_empty()


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
