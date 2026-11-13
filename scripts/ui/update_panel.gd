extends VBoxContainer
## Aviso de versão nova: texto, barra de download e botão "Atualizar agora".
## Usado no menu principal e no menu de pausa. Fica invisível enquanto não há nada a mostrar.

## Chamado antes de instalar (ex.: salvar a partida), já que o jogo fecha e reabre sozinho.
var before_install := Callable()

var _label: Label
var _bar: ProgressBar
var _btn: Button


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_label = UITheme.label("", 17)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size.x = 300
	add_child(_label)
	_bar = ProgressBar.new()
	_bar.max_value = 1.0
	_bar.custom_minimum_size.y = 14
	_bar.show_percentage = false
	add_child(_bar)
	_btn = UITheme.button("Atualizar agora", _on_pressed)
	add_child(_btn)
	Updater.state_changed.connect(_refresh)
	Updater.progress.connect(_on_progress)
	_refresh(Updater.state)


func _on_progress(f: float) -> void:
	_bar.value = f


func _on_pressed() -> void:
	Sfx.play("click", 0.0)
	if Updater.can_install():
		if before_install.is_valid():
			before_install.call()
		Updater.install()
	else:
		Updater.open_releases_page()


func _refresh(s: int) -> void:
	var S := Updater.State
	visible = s in [S.AVAILABLE, S.DOWNLOADING, S.INSTALLING] or (s == S.FAILED and Updater.has_newer())
	_bar.visible = s in [S.DOWNLOADING, S.INSTALLING]
	_btn.visible = s in [S.AVAILABLE, S.FAILED]
	_label.add_theme_color_override("font_color", UITheme.TEXT)
	match s:
		S.AVAILABLE:
			_label.text = "Nova versão disponível: v%s (você tem v%s)." % [Updater.latest_version, Updater.current_version()]
			_btn.text = "Atualizar agora"
		S.DOWNLOADING:
			_label.text = "Baixando v%s..." % Updater.latest_version
		S.INSTALLING:
			_label.text = "Instalando... o jogo vai reabrir sozinho."
		S.FAILED:
			_label.text = Updater.error
			_label.add_theme_color_override("font_color", Color(1, 0.6, 0.5))
			_btn.text = "Tentar de novo" if Updater.can_install() else "Abrir página de download"
