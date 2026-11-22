extends RefCounted
## PartyShieldRules: contas puras do Grito do Bastião (quem do grupo recebe o buff, defesa com o bônus percentual,
## intervalo do servidor, relógio da sprite sheet e órbita dos escudos). O kit (tecla 5 com escudo), o buff entrando e
## saindo do personagem, o visual e o HUD ficam no teste de fumaça (precisam dos autoloads).


func _cfg() -> PartyShieldConfig:
	return load("res://assets/vfx/party_shield/party_shield_config.tres")


func test_defense_with_percent() -> void:
	T.ok(absf((PartyShieldRules.defense_with(20.0, 0.0)) - (20.0)) <= 0.0001, "sem bônus: a mesma defesa")
	T.ok(absf((PartyShieldRules.defense_with(20.0, 0.25)) - (25.0)) <= 0.0001, "+25% de 20 = 25")
	T.ok(absf((PartyShieldRules.defense_with(20.0 + 6.0, 0.25)) - (32.5)) <= 0.0001, "fixo entra antes do percentual")
	T.ok(absf((PartyShieldRules.defense_with(10.0, -5.0)) - (0.5)) <= 0.0001, "percentual negativo nunca zera nem inverte")
	T.ok(absf((PartyShieldRules.defense_with(0.0, 0.25)) - (0.0)) <= 0.0001, "percentual de zero é zero")


func test_targets_party_in_zone_and_radius() -> void:
	var pos := {1: Vector3(0, 0, 0), 2: Vector3(10, 5, 0), 3: Vector3(40, 0, 0), 4: Vector3(3, 0, 3), 5: Vector3(1, 0, 1)}
	var zone := [1, 2, 3, 4]   # 5 está em outra zona
	var party := [2, 1, 3, 5]
	var got := PartyShieldRules.targets(1, party, zone, pos, 30.0)
	T.eq(got, [1, 2], "o herói primeiro; o 2 (perto, a altura não conta) entra; o 3 (longe) e o 5 (outra zona) não")
	T.ok(not 4 in got, "quem está perto mas não é do grupo não recebe")


func test_targets_alone_or_unknown_position() -> void:
	T.eq(PartyShieldRules.targets(7, [], [7, 8], {7: Vector3.ZERO, 8: Vector3(1, 0, 0)}, 30.0), [7],
		"sem grupo: só o herói")
	T.eq(PartyShieldRules.targets(7, [7, 8], [7, 8], {8: Vector3(1, 0, 0)}, 30.0), [7],
		"sem a posição do herói: só ele (ninguém de longe por engano)")
	T.eq(PartyShieldRules.targets(7, [7, 8, 8], [7, 8], {7: Vector3.ZERO, 8: Vector3(1, 0, 0)}, 30.0), [7, 8],
		"sem repetir")
	T.eq(PartyShieldRules.targets(7, [7, 8], [7, 8], {7: Vector3.ZERO, 8: Vector3(30, 0, 0)}, 30.0), [7, 8],
		"na borda do raio ainda recebe")


func test_has_kit() -> void:
	T.ok(PartyShieldRules.has_kit("sword", "sword"), "espada + escudo de espada")
	T.ok(not PartyShieldRules.has_kit("sword", ""), "espada sem escudo")
	T.ok(not PartyShieldRules.has_kit("bow", "sword"), "arco não")
	T.ok(not PartyShieldRules.has_kit("staff", ""), "cajado não")


func test_min_interval_under_real_cooldown() -> void:
	var cfg := _cfg()
	var buff_time := 15.0
	var mi := PartyShieldRules.min_interval(cfg.cooldown, buff_time)
	# a menor recarga possível no cliente: max(recarga x 0,4, buff + 4) (Game.ability_cooldown)
	var client_min := maxf(cfg.cooldown * 0.4, buff_time + 4.0)
	T.ok(mi < client_min, "o servidor nunca recusa um uso legítimo (%.1f < %.1f)" % [mi, client_min])
	T.ok(mi > client_min - 1.0, "mas barra spam (folga pequena)")
	T.ok(PartyShieldRules.interval_ok(-INF, 0.0, cfg.cooldown, buff_time), "primeiro uso sempre vale")
	T.ok(not PartyShieldRules.interval_ok(100.0, 101.0, cfg.cooldown, buff_time), "logo depois não")
	T.ok(PartyShieldRules.interval_ok(100.0, 100.0 + client_min, cfg.cooldown, buff_time), "depois da recarga vale")


func test_sheet_frames() -> void:
	T.ok(absf((PartyShieldRules.form_frame(0.0, 2.0)) - (1.0)) <= 0.0001, "formação começa no quadro 1")
	T.ok(absf((PartyShieldRules.form_frame(2.0, 2.0)) - (18.0)) <= 0.0001, "e termina no 18")
	T.ok(absf((PartyShieldRules.form_frame(9.0, 2.0)) - (18.0)) <= 0.0001, "não passa do fim")
	for f in [PartyShieldRules.FORM_FIRST, PartyShieldRules.FORM_LAST]:
		T.ok(f >= 0 and f < 64, "quadro %d dentro da sheet 8x8" % f)


func test_cast_speed() -> void:
	T.ok(absf(PartyShieldRules.cast_time(1.0) - PartyShieldRules.CLIP_END) < 0.0001, "1x = o clipe inteiro")
	T.ok(absf(PartyShieldRules.cast_time(2.0) - PartyShieldRules.CLIP_END / 2.0) < 0.0001, "2x = metade do tempo")
	T.ok(PartyShieldRules.cast_time(0.0) > 0.0 and is_finite(PartyShieldRules.cast_time(0.0)), "velocidade zero não trava")
	var cfg := _cfg()
	T.ok(cfg.cast_speed > 1.0 and PartyShieldRules.cast_time(cfg.cast_speed) < 1.8,
		"a animação do buff é mais rápida que o clipe (%.2f s)" % PartyShieldRules.cast_time(cfg.cast_speed))
	T.eq(cfg.shield_count, 5, "5 escudos pequenos girando")


func test_sheet_frames_have_art() -> void:
	# a sheet realinhada (tools/party_shield_sheet_bake.gd): os quadros usados têm brilho, os de fora são pretos
	var img: Image = (load("res://assets/vfx/party_shield/party_shield_sheet.png") as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	T.eq(img.get_size(), Vector2i(1024, 1024), "8 x 8 quadros de 128 px")
	var lum := func(f: int) -> float:
		var s := 0.0
		for y in range(0, 128, 4):
			for x in range(0, 128, 4):
				var c := img.get_pixel((f % 8) * 128 + x, (f / 8) * 128 + y)
				s += maxf(c.r, maxf(c.g, c.b))
		return s
	for f in [5, 12, 18, 24, 31, 39, 48]:
		T.ok(lum.call(f) > 20.0, "quadro %d tem arte (%.0f)" % [f, lum.call(f)])
	for f in [0, 20, 44, 62]:
		T.ok(lum.call(f) < 3.0, "quadro %d vazio é preto (%.1f)" % [f, lum.call(f)])


func test_shield_orbit() -> void:
	var n := 5
	var r := 0.8
	var a := PartyShieldRules.shield_offset(0, n, 0.0, r, 1.5, 0.0)
	var b := PartyShieldRules.shield_offset(1, n, 0.0, r, 1.5, 0.0)
	T.ok(absf((Vector2(a.x, a.z).length()) - (r)) <= 0.0001, "no raio da órbita")
	T.ok(absf((Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z))) - (TAU / n)) <= 0.0001, "espaçados por igual")
	var later := PartyShieldRules.shield_offset(0, n, 1.0, r, 1.5, 0.0)
	T.ok(absf((Vector2(a.x, a.z).angle_to(Vector2(later.x, later.z))) - (1.5)) <= 0.0001, "giram a `speed` rad/s")
	for t in [0.0, 0.3, 2.0]:
		T.ok(absf(PartyShieldRules.shield_offset(2, n, t, r, 1.5, 0.07).y) <= 0.0701, "sobe e desce no máximo `bob`")


func test_config_defaults_sane() -> void:
	var cfg := _cfg()
	T.ok(cfg.radius >= 10.0, "o grupo inteiro por perto recebe (%.0f m)" % cfg.radius)
	T.ok(cfg.shield_count >= 3 and cfg.shield_size < 0.4, "escudos pequenos (do tamanho da mão), alguns")
	T.ok(cfg.aura_fade_in > 0.1 and cfg.aura_fade_out > 0.1, "a aura acende e apaga devagar")
	T.ok(PartyShieldRules.SHOUT_AT < PartyShieldRules.CLIP_END, "o grito sai antes do buff")
