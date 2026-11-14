extends RefCounted
## Tema de papel: todo controle usado nas telas do livro tem estilo próprio e texto a tinta.


func test_paper_theme_covers_controls() -> void:
	var t := UITheme.paper_theme()
	for pair in [["normal", "Button"], ["panel", "ItemList"], ["selected", "ItemList"], ["panel", "TabContainer"],
			["tab_selected", "TabContainer"], ["background", "ProgressBar"], ["slider", "HSlider"],
			["normal", "LineEdit"], ["focus", "LineEdit"], ["normal", "OptionButton"], ["panel", "PopupMenu"],
			["panel", "TooltipPanel"]]:
		T.ok(t.has_stylebox(pair[0], pair[1]), "estilo %s de %s" % pair)


func test_paper_text_is_ink() -> void:
	var t := UITheme.paper_theme()
	for type in ["Label", "Button", "ItemList", "LineEdit", "CheckBox", "OptionButton", "PopupMenu", "TooltipLabel"]:
		T.eq(t.get_color("font_color", type), UITheme.INK, "texto de %s é tinta" % type)
	T.eq(t.get_color("default_color", "RichTextLabel"), UITheme.INK, "texto rico é tinta")


func test_paper_theme_leaves_dark_theme_alone() -> void:
	T.eq(UITheme.get_theme().get_color("font_color", "Label"), UITheme.TEXT, "tema escuro continua claro")


func test_fonts_are_bundled() -> void:
	var title := UITheme.serif()
	T.ok(title is FontVariation and (title as FontVariation).base_font is FontFile, "título usa a fonte embutida (em peso 600), não a do sistema")
	T.ok(UITheme.body() is FontFile, "texto usa a fonte embutida")


func test_font_fallback() -> void:
	var f := UITheme._load_font("res://assets/fonts/nao_existe.ttf", ["Georgia", "serif"])
	T.ok(f is SystemFont, "fonte ausente cai na do sistema sem erro")
