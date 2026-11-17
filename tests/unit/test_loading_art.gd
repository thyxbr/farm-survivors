extends RefCounted
## Toda cena da tela de carregamento tem imagem existente e texto; o sorteio nunca repete a anterior.


func test_every_scene_has_image_and_text() -> void:
	T.ok(LoadingArt.SCENES.size() >= 5, "ao menos 5 ilustrações (%d)" % LoadingArt.SCENES.size())
	for s in LoadingArt.SCENES:
		T.ok(ResourceLoader.exists(LoadingArt.image_path(s)), "imagem %s existe" % s["image"])
		T.ok(str(s["title"]) != "" and str(s["text"]).length() > 40, "cena %s tem título e história" % s["image"])


func test_pick_never_repeats_last() -> void:
	var n := LoadingArt.SCENES.size()
	for last in n:
		var seen := {}
		for roll in n * 3:
			var i := LoadingArt.pick(last, roll)
			T.ok(i >= 0 and i < n and i != last, "sorteio depois de %d deu %d" % [last, i])
			seen[i] = true
		T.ok(seen.size() == n - 1, "depois de %d todas as outras cenas podem sair" % last)
	T.ok(LoadingArt.pick(-1, 7) >= 0 and LoadingArt.pick(-1, 7) < n, "primeira vez sorteia qualquer uma")
