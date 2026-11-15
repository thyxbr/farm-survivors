extends RefCounted
## DayNightRules: hora do jogo pelo relógio, noite, sol e lua, e o acender das luzes da cidade.


func test_hour_follows_the_clock() -> void:
	T.eq(DayNightRules.hour_at(0.0), 0.0, "começo do dia")
	T.ok(absf(DayNightRules.hour_at(DayNightRules.DAY_LENGTH * 0.5) - 12.0) < 0.001, "meio do dia é meio-dia")
	T.ok(absf(DayNightRules.hour_at(DayNightRules.DAY_LENGTH * 3.25) - 6.0) < 0.001, "repete a cada dia")
	var t := 1_800_000_123.0
	T.eq(DayNightRules.hour_at(t), DayNightRules.hour_at(t), "mesmo instante, mesma hora")


func test_noon_is_day_and_midnight_is_night() -> void:
	T.eq(DayNightRules.night(12.0), 0.0, "meio-dia sem noite")
	T.eq(DayNightRules.night(0.0), 1.0, "meia-noite é noite fechada")
	T.eq(DayNightRules.night(23.0), 1.0, "23h é noite")
	T.eq(DayNightRules.sun(12.0), 1.0, "sol cheio ao meio-dia")
	T.eq(DayNightRules.sun(0.0), 0.0, "sem sol à meia-noite")
	T.eq(DayNightRules.moon(0.0), 1.0, "lua à meia-noite")
	T.eq(DayNightRules.moon(12.0), 0.0, "sem lua ao meio-dia")


func test_dusk_is_gradual() -> void:
	var prev := -1.0
	for i in 40:
		var h := DayNightRules.SUNSET - 1.5 + i * 0.075
		var n := DayNightRules.night(h)
		T.ok(n >= prev, "a noite só aumenta no fim da tarde (%.2fh)" % h)
		prev = n
	var mid := DayNightRules.night(DayNightRules.SUNSET)
	T.ok(mid > 0.3 and mid < 0.7, "no pôr do sol é meio a meio (%.2f)" % mid)


func test_sun_and_moon_never_overlap() -> void:
	# a direção da luz troca de sol para lua no escuro: os dois nunca brilham juntos
	for i in 480:
		var h := i * 0.05
		T.ok(DayNightRules.sun(h) == 0.0 or DayNightRules.moon(h) == 0.0, "sol e lua juntos às %.2fh" % h)


func test_sun_crosses_the_sky() -> void:
	var dawn := DayNightRules.sun_rotation(DayNightRules.SUNRISE)
	var noon := DayNightRules.sun_rotation(12.5)
	var dusk := DayNightRules.sun_rotation(DayNightRules.SUNSET)
	T.ok(-noon.x > -dawn.x and -noon.x > -dusk.x, "sol mais alto ao meio-dia")
	T.ok(dusk.y > dawn.y, "o sol anda de um lado ao outro")
	T.ok(-noon.x < 60.0, "nunca a pino (a sombra desenhada precisa de ângulo)")


func test_lamps_light_up_at_night_one_by_one() -> void:
	T.eq(DayNightRules.lamp_on(0.0, 0.5), 0.0, "apagado de dia")
	T.eq(DayNightRules.lamp_on(1.0, 0.0), 1.0, "aceso à noite")
	T.eq(DayNightRules.lamp_on(1.0, 1.0), 1.0, "o mais atrasado também acende")
	T.ok(DayNightRules.lamp_on(0.4, 0.0) > DayNightRules.lamp_on(0.4, 1.0), "uns acendem antes dos outros")


func test_parse_hour() -> void:
	T.eq(DayNightRules.parse_hour("21"), 21.0, "hora cheia")
	T.ok(absf(DayNightRules.parse_hour("6:30") - 6.5) < 0.001, "com minutos")
	T.ok(absf(DayNightRules.parse_hour("18h") - 18.0) < 0.001, "com h")
	T.eq(DayNightRules.parse_hour("25"), -1.0, "fora do dia")
	T.eq(DayNightRules.parse_hour("noite"), -1.0, "texto")
	T.eq(DayNightRules.hour_text(21.5), "21:30", "texto da hora")


func test_hour_matches_the_season_clock() -> void:
	# a hora do HUD (SeasonRules.clock_at) e a luz (DayNightRules) saem da mesma conta
	for i in 30:
		var t := 1_800_000_000.0 + i * 377.0
		var c := SeasonRules.clock_at(t)
		var h := DayNightRules.hour_at(t)
		T.eq(floori(h), int(c.hour), "mesma hora em t=%d" % int(t))


func test_seasons_change_the_day() -> void:
	var summer := DayNightRules.day_of(SeasonRules.Kind.SUMMER)
	var winter := DayNightRules.day_of(SeasonRules.Kind.WINTER)
	var spring := DayNightRules.day_of(SeasonRules.Kind.SPRING)
	T.eq(spring.sunrise, DayNightRules.SUNRISE, "primavera é o dia de sempre")
	T.ok(summer.sunset - summer.sunrise > winter.sunset - winter.sunrise, "dia de verão mais longo que o de inverno")
	T.ok(summer.peak > winter.peak, "sol mais alto no verão")
	for k in 4:
		var d := DayNightRules.day_of(k)
		T.ok(d.peak < 60.0, "nunca a pino (estação %d)" % k)
		T.ok(d.sunrise < 12.0 and d.sunset > 12.0, "meio-dia é dia (estação %d)" % k)
		T.ok(DayNightRules.night(0.5, d.sunrise, d.sunset) == 1.0, "meia-noite é noite (estação %d)" % k)
		for i in 480:
			var h := i * 0.05
			T.ok(DayNightRules.sun(h, d.sunrise, d.sunset) == 0.0 or DayNightRules.moon(h, d.sunrise, d.sunset) == 0.0,
					"sol e lua juntos às %.2fh (estação %d)" % [h, k])
	# 18h: ainda dia no verão, já noite no inverno
	T.eq(DayNightRules.night(18.5, summer.sunrise, summer.sunset), 0.0, "18h30 de verão ainda é dia")
	T.ok(DayNightRules.night(18.5, winter.sunrise, winter.sunset) > 0.9, "18h30 de inverno já é noite")
	var noon_s := DayNightRules.sun_rotation(12.75, summer.sunrise, summer.sunset, summer.peak)
	var noon_w := DayNightRules.sun_rotation(12.125, winter.sunrise, winter.sunset, winter.peak)
	T.ok(-noon_s.x > -noon_w.x, "ao meio-dia o sol de verão está mais alto")


func test_season_change_blends_the_day() -> void:
	var half := DayNightRules.day_for([0.0, 0.0, 0.5, 0.5])
	var autumn := DayNightRules.day_of(SeasonRules.Kind.AUTUMN)
	var winter := DayNightRules.day_of(SeasonRules.Kind.WINTER)
	T.ok(absf(half.sunset - (autumn.sunset + winter.sunset) * 0.5) < 0.001, "na virada, o pôr do sol fica no meio")
	T.eq(DayNightRules.day_for([0.0, 0.0, 0.0, 0.0]).sunrise, DayNightRules.SUNRISE, "sem pesos, vale a primavera")
	# os pesos do relógio somam 1 o tempo todo, inclusive na virada
	var L := SeasonRules.LENGTH
	for i in 60:
		var t := 1_800_000_000.0 + i * L / 30.0 + (i % 3) * 7.0
		var sum := 0.0
		for w in SeasonRules.weights_at(t):
			sum += w
		T.ok(absf(sum - 1.0) < 0.001, "pesos somam 1 (t=%.0f)" % t)
