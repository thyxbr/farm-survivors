extends RefCounted
## MusicRules: qual música e qual ambiente tocam em cada situação.


func test_menu_and_unknown_scene() -> void:
	T.eq(MusicRules.track({"scene": "menu"}), "menu", "menu principal")
	T.eq(MusicRules.track({}), "", "sem cena: silêncio")
	T.eq(MusicRules.ambience({"scene": "menu"}), "", "menu sem ambiente")


func test_world_areas() -> void:
	T.eq(MusicRules.track({"scene": "world", "pos": Vector3(0, 0, 6)}), "village", "spawn da vila")
	T.eq(MusicRules.track({"scene": "world", "pos": Vector3(0, 0, 36)}), "village", "horta conta como vila")
	T.eq(MusicRules.track({"scene": "world", "pos": Vector3(0, 0, -17)}), "village", "cerca norte ainda é vila")
	T.eq(MusicRules.track({"scene": "world", "pos": Vector3(-35, 0, 4)}), "village", "canto oeste da cerca é vila")
	T.eq(MusicRules.track({"scene": "world", "pos": Vector3(-12, 0, -30)}), "wild", "campos das slimes já são mata")
	T.eq(MusicRules.track({"scene": "world", "pos": Vector3(-36, 0, 36)}), "wild", "Ninho de Slimes é mata")
	T.eq(MusicRules.track({"scene": "world", "pos": Vector3(86, 0, 0)}), "wild", "acampamento goblin é mata")
	T.eq(MusicRules.track({"scene": "world", "pos": Vector3(0, 0, -100)}), "ruins", "ruínas do Rei Goblin")
	T.eq(MusicRules.ambience({"scene": "world"}), "day", "mundo aberto com pássaros e vento")


func test_priorities() -> void:
	var horde := {"scene": "world", "horde": true, "pos": Vector3(0, 0, -1000)}
	T.eq(MusicRules.track(horde), "horde", "horda")
	T.eq(MusicRules.ambience(horde), "", "horda sem ambiente")
	horde.boss_near = true
	T.eq(MusicRules.track(horde), "boss", "chefe vence a horda")
	horde.dead = true
	T.eq(MusicRules.track(horde), "game_over", "morte vence tudo")


func test_every_track_file_exists() -> void:
	for id in MusicRules.TRACKS:
		for f in MusicRules.TRACKS[id]:
			T.ok(ResourceLoader.exists("res://assets/audio/music/%s.ogg" % f), "música %s/%s existe" % [id, f])
	for id in MusicRules.AMBIENCES:
		T.ok(ResourceLoader.exists("res://assets/audio/ambience/%s.ogg" % MusicRules.AMBIENCES[id]), "ambiente %s existe" % id)
