extends RefCounted
## Todo som listado em Sfx.FILES tem arquivo em assets/audio/sfx (um nome errado vira silêncio no jogo).

const SFX := preload("res://scripts/autoload/sfx.gd")


func test_every_sfx_file_exists() -> void:
	for sound in SFX.FILES:
		for f in SFX.FILES[sound]:
			T.ok(ResourceLoader.exists(SFX.SFX_DIR % f), "som %s: %s existe" % [sound, f])


func test_weapon_sounds_are_listed() -> void:
	for k in ["sword_swing", "sword_swing_heavy", "sword_hit", "sword_hit_flesh", "sword_hit_heavy", "staff_wind",
			"bow_draw", "bow_full", "bow_shot", "arrow_hit", "chop_wood", "chop_stone", "punch", "punch_hit"]:
		T.ok(SFX.FILES.has(k), "som de arma %s" % k)
	for el in ["arcane", "fire", "frost"]:
		T.ok(SFX.FILES.has(el + "_cast") and SFX.FILES.has(el + "_hit"), "cajado de %s tem disparo e impacto" % el)
