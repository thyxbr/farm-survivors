extends RefCounted
## BookLayout: medidas do livro e a regra "cabe na página".


func test_room() -> void:
	T.eq(BookLayout.content_room(), Vector2(1232, 676), "área das duas páginas")
	T.eq(BookLayout.page_room(), Vector2(574, 676), "área de uma página")


func test_fits() -> void:
	T.ok(BookLayout.fits(Vector2(1232, 676)), "do tamanho exato cabe")
	T.ok(not BookLayout.fits(Vector2(1233, 100)), "1 px mais largo não cabe")
	T.ok(not BookLayout.fits(Vector2(100, 677)), "1 px mais alto não cabe")


func test_scale() -> void:
	T.eq(BookLayout.scale_for(Vector2(1600, 900)), 1.0, "tela de projeto: sem escala")
	T.eq(BookLayout.scale_for(Vector2(3840, 2160)), 1.0, "tela grande não amplia")
	T.ok(is_equal_approx(BookLayout.scale_for(Vector2(1280, 720)), 688.0 / 800.0), "720p encolhe pela altura")
	T.ok(is_equal_approx(BookLayout.scale_for(Vector2(1000, 900)), 968.0 / 1408.0), "janela estreita encolhe pela largura")
	T.ok(BookLayout.scale_for(Vector2(0, 0)) > 0.0, "janela minimizada não zera a escala")
