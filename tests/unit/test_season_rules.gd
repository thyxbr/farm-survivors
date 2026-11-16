extends RefCounted
## SeasonRules: estações pelo relógio (17 min cada), hora do jogo e efeito do outono no clima.

const L := SeasonRules.LENGTH


func test_seasons_cycle_in_order_every_17_minutes() -> void:
	T.eq(L, 1020.0, "17 minutos por estação")
	var base := floorf(1_800_000_000.0 / (4.0 * L)) * 4.0 * L   # começo de uma primavera
	T.eq(SeasonRules.kind_at(base + 1.0), SeasonRules.Kind.SPRING, "primavera")
	T.eq(SeasonRules.kind_at(base + L + 1.0), SeasonRules.Kind.SUMMER, "verão")
	T.eq(SeasonRules.kind_at(base + 2.0 * L + 1.0), SeasonRules.Kind.AUTUMN, "outono")
	T.eq(SeasonRules.kind_at(base + 3.0 * L + 1.0), SeasonRules.Kind.WINTER, "inverno")
	T.eq(SeasonRules.kind_at(base + 4.0 * L + 1.0), SeasonRules.Kind.SPRING, "o ano recomeça")


func test_same_instant_same_season_and_countdown() -> void:
	# dois jogadores olhando o mesmo relógio (o do servidor) veem a mesma coisa
	var t := 1_800_000_123.4
	T.eq(SeasonRules.kind_at(t), SeasonRules.kind_at(t), "mesma estação")
	T.eq(SeasonRules.countdown_text(SeasonRules.time_left(t)), SeasonRules.countdown_text(SeasonRules.time_left(t)), "mesmo contador")
	T.eq(SeasonRules.clock_text(t), SeasonRules.clock_text(t), "mesma hora")


func test_time_left_counts_down_to_the_switch() -> void:
	var start := floorf(1_800_000_000.0 / L) * L
	T.ok(absf(SeasonRules.time_left(start + 1.0) - (L - 1.0)) < 0.01, "logo depois da troca falta quase tudo")
	T.ok(absf(SeasonRules.time_left(start + L - 5.0) - 5.0) < 0.01, "faltam 5 s")
	T.eq(SeasonRules.countdown_text(65.2), "1:06", "contador m:ss arredonda para cima")
	T.eq(SeasonRules.countdown_text(0.0), "0:00", "zero")


func test_game_clock_runs_two_days_per_season() -> void:
	var start := floorf(1_800_000_000.0 / L) * L
	var c := SeasonRules.clock_at(start + 1.0)
	T.eq(c.day, 1, "começa no dia 1")
	T.eq(c.hour, 0, "à meia-noite")
	var half_day := L / SeasonRules.DAYS_PER_SEASON * 0.5
	c = SeasonRules.clock_at(start + half_day + 0.1)
	T.eq(c.hour, 12, "meio do dia = meio-dia")
	c = SeasonRules.clock_at(start + L - 1.0)
	T.eq(c.day, SeasonRules.DAYS_PER_SEASON, "último dia da estação")
	T.eq(SeasonRules.clock_text(start + half_day + 0.1), "12:00", "texto HH:MM")


func test_autumn_weight_blends_at_the_edges() -> void:
	var base := floorf(1_800_000_000.0 / (4.0 * L)) * 4.0 * L
	var a0 := base + 2.0 * L   # começo do outono
	T.eq(SeasonRules.weight_at(a0 + L * 0.5, SeasonRules.Kind.AUTUMN), 1.0, "meio do outono: outono pleno")
	T.eq(SeasonRules.weight_at(base + L * 0.5, SeasonRules.Kind.AUTUMN), 0.0, "meio da primavera: nada de outono")
	var at := SeasonRules.weight_at(a0 + 0.01, SeasonRules.Kind.AUTUMN)
	T.ok(at > 0.45 and at < 0.55, "na virada o outono vale ~metade (%.2f)" % at)
	var before := SeasonRules.weight_at(a0 - 0.01, SeasonRules.Kind.AUTUMN)
	T.ok(absf(before - at) < 0.01, "sem salto na virada")
	var leaving := SeasonRules.weight_at(a0 + L - 1.0, SeasonRules.Kind.AUTUMN)
	T.ok(leaving > 0.5 and leaving < 0.6, "saindo para o inverno (%.2f)" % leaving)
	# a soma das estações é sempre 1
	for i in 40:
		var t := base + i * 77.7
		var sum := 0.0
		for k in 4:
			sum += SeasonRules.weight_at(t, k)
		T.ok(absf(sum - 1.0) < 0.001, "pesos somam 1 em t+%d" % (i * 77))


func test_autumn_brings_more_rain_and_wind_less_snow() -> void:
	var counts := {SeasonRules.Kind.AUTUMN: [0, 0, 0, 0], -1: [0, 0, 0, 0]}
	for i in 6000:
		var seg := 4_000_000 + i
		var autumn := SeasonRules.kind_at(seg * WeatherRules.SEGMENT) == SeasonRules.Kind.AUTUMN
		counts[SeasonRules.Kind.AUTUMN if autumn else -1][WeatherRules.kind_of_segment(seg)] += 1
	var a: Array = counts[SeasonRules.Kind.AUTUMN]
	var o: Array = counts[-1]
	var an := float(a[0] + a[1] + a[2] + a[3])
	var on := float(o[0] + o[1] + o[2] + o[3])
	T.ok(an > 500.0, "trechos de outono suficientes (%d)" % an)
	T.ok(a[WeatherRules.Kind.RAIN] / an > o[WeatherRules.Kind.RAIN] / on, "outono chove mais")
	T.ok(a[WeatherRules.Kind.WIND] / an > o[WeatherRules.Kind.WIND] / on, "outono venta mais")
	T.ok(a[WeatherRules.Kind.SNOW] / an < o[WeatherRules.Kind.SNOW] / on * 0.5, "outono quase não neva")


func test_no_snow_in_spring_or_summer_and_snows_in_winter() -> void:
	var winter_snow := 0
	var winter_n := 0
	# um instante a cada 60 s por ~6 anos do jogo (cobre os trechos que atravessam a virada)
	for i in 30000:
		var t := 1_800_000_000.0 + i * 61.0
		var season := SeasonRules.kind_at(t)
		var k := WeatherRules.kind_at(t)
		if season == SeasonRules.Kind.SPRING or season == SeasonRules.Kind.SUMMER:
			if k == WeatherRules.Kind.SNOW:
				T.ok(false, "nevou na %s em t=%d" % [SeasonRules.NAMES[season], int(t)])
				return
		elif season == SeasonRules.Kind.WINTER:
			winter_n += 1
			if k == WeatherRules.Kind.SNOW:
				winter_snow += 1
	T.ok(true, "primavera e verão sem neve")
	T.ok(winter_snow > winter_n * 0.25, "o inverno neva bastante (%d de %d)" % [winter_snow, winter_n])
