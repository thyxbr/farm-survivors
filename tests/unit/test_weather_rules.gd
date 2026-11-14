extends RefCounted
## WeatherRules: cronograma do clima pelo relógio e acúmulo de água e neve no chão.


func test_schedule_is_deterministic() -> void:
	for i in 50:
		var t := 1_800_000_000.0 + i * 977.0
		T.eq(WeatherRules.kind_at(t), WeatherRules.kind_at(t), "mesmo instante, mesmo clima")
	T.eq(WeatherRules.kind_at(1_800_000_000.0), WeatherRules.kind_at(1_800_000_000.0 + 1.0), "mesmo trecho")


func test_all_kinds_show_up_and_change_often() -> void:
	var seen := {}
	var repeats := 0
	var prev := -1
	for i in 400:
		var k := WeatherRules.kind_of_segment(4_000_000 + i)
		seen[k] = seen.get(k, 0) + 1
		if k == prev:
			repeats += 1
		prev = k
	T.eq(seen.size(), 4, "sol, chuva, neve e vento aparecem")
	T.ok(seen[WeatherRules.Kind.SUN] > seen[WeatherRules.Kind.SNOW], "sol é o mais comum")
	T.ok(repeats < 80, "o clima troca com frequência (repetiu %d de 400)" % repeats)


func test_rain_makes_puddles_then_dries() -> void:
	var s := WeatherRules.new_state()
	WeatherRules.simulate(s, 0.0, 180.0, 5.0, func(_t: float) -> int: return WeatherRules.Kind.RAIN)
	T.ok(s.wet > 0.9, "chuva encharca o chão (wet=%.2f)" % s.wet)
	WeatherRules.simulate(s, 0.0, 60.0, 5.0, func(_t: float) -> int: return WeatherRules.Kind.SUN)
	T.ok(s.wet > 0.3, "logo depois da chuva ainda há poças (wet=%.2f)" % s.wet)
	WeatherRules.simulate(s, 0.0, 70.0, 5.0, func(_t: float) -> int: return WeatherRules.Kind.SUN)
	T.eq(s.wet, 0.0, "com sol o chão seca em ~2 min")


func test_puddles_do_not_last_through_other_weathers() -> void:
	# chuva, depois 1 min de cada: sol, neve, sol, vento. As poças não podem sobreviver a tudo isso.
	var s := WeatherRules.new_state()
	WeatherRules.simulate(s, 0.0, 240.0, 5.0, func(_t: float) -> int: return WeatherRules.Kind.RAIN)
	for k in [WeatherRules.Kind.SUN, WeatherRules.Kind.SNOW]:
		WeatherRules.simulate(s, 0.0, 60.0, 5.0, func(_t: float) -> int: return k)
	T.ok(s.wet < 0.12, "neve depois da chuva some com as poças (wet=%.2f)" % s.wet)
	for k in [WeatherRules.Kind.SUN, WeatherRules.Kind.WIND]:
		WeatherRules.simulate(s, 0.0, 60.0, 5.0, func(_t: float) -> int: return k)
	T.eq(s.wet, 0.0, "chão seco no fim")


func test_snow_covers_then_melts_into_water() -> void:
	var s := WeatherRules.new_state()
	WeatherRules.simulate(s, 0.0, 240.0, 5.0, func(_t: float) -> int: return WeatherRules.Kind.SNOW)
	T.eq(s.cover, 1.0, "neve cobre o chão")
	WeatherRules.simulate(s, 0.0, 60.0, 5.0, func(_t: float) -> int: return WeatherRules.Kind.SUN)
	T.ok(s.cover > 0.0 and s.cover < 1.0, "derrete aos poucos (cover=%.2f)" % s.cover)
	T.ok(s.wet > 0.05 and s.wet < 0.3, "neve derretida deixa o chão úmido, sem poças grandes (wet=%.2f)" % s.wet)
	WeatherRules.simulate(s, 0.0, 180.0, 5.0, func(_t: float) -> int: return WeatherRules.Kind.SUN)
	T.eq(s.cover, 0.0, "com sol a neve some")


func test_wind_blends_in_gradually() -> void:
	var s := WeatherRules.new_state()
	WeatherRules.blend_toward(s, WeatherRules.Kind.WIND, 5.0)
	T.ok(s.wind > 0.12 and s.wind < 1.0, "vento sobe aos poucos")
	WeatherRules.simulate(s, 0.0, 60.0, 5.0, func(_t: float) -> int: return WeatherRules.Kind.WIND)
	T.eq(s.wind, 1.0, "vento forte")
	T.eq(s.rain, 0.0, "sem chuva")


func test_wind_dir_is_unit_and_smooth() -> void:
	var a := WeatherRules.wind_dir_at(1000.0)
	var b := WeatherRules.wind_dir_at(1001.0)
	T.ok(absf(a.length() - 1.0) < 0.001, "unitário")
	T.ok(a.distance_to(b) < 0.05, "gira devagar")
