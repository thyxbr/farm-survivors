extends Node
## Auto update do cliente Windows a partir do GitHub Releases.
##
## O CI publica, a cada versão nova, uma release com o zip do jogo e um `latest.json`:
##   {"version": "0.3.0", "url": ".../EcosDeValdoria-v0.3.0-windows.zip", "sha256": "...", "size": 123, "exe": "EcosDeValdoria.exe"}
## O link `releases/latest/download/latest.json` sempre aponta para a release mais nova.
##
## Fluxo: check() lê o manifesto → se a versão for maior, emite `state_changed` com AVAILABLE →
## install() baixa o zip ao lado do exe, confere o SHA-256, extrai o exe novo como `.new`,
## renomeia o exe em uso para `.old` (o Windows deixa renomear um exe aberto, só não sobrescrever),
## coloca o novo no lugar, abre o jogo de novo e fecha este. Na próxima abertura o `.old` é apagado.
##
## Com o jogo aberto, procura de novo a cada CHECK_INTERVAL segundos; se achar versão nova durante a partida,
## mostra um aviso no topo da tela (a instalação fica no menu de pausa, que salva antes de reabrir).
##
## Só funciona no jogo exportado para Windows; no editor, no servidor e nos testes headless fica desligado.
## Para testar com outro manifesto: `EcosDeValdoria.exe -- --update-manifest=http://127.0.0.1:8000/latest.json`
## (`--update-now` instala sem esperar o clique no botão; `--update-interval=30` muda o intervalo em segundos).

signal state_changed(state: int)
signal progress(fraction: float)

enum State { DISABLED, IDLE, CHECKING, UP_TO_DATE, AVAILABLE, DOWNLOADING, INSTALLING, FAILED }

const REPO := "thyxbr/farm-survivors"
const MANIFEST_URL := "https://github.com/" + REPO + "/releases/latest/download/latest.json"
const RELEASES_PAGE := "https://github.com/" + REPO + "/releases/latest"
const CHECK_TIMEOUT := 15.0
## De quanto em quanto tempo procura de novo com o jogo aberto.
const CHECK_INTERVAL := 300.0
## Quanto tempo o aviso de versão nova fica na tela durante a partida.
const TOAST_TIME := 15.0

var state := State.DISABLED
## Versão oferecida pelo manifesto (vazia até a checagem terminar).
var latest_version := ""
## Mensagem para mostrar ao jogador quando algo falha.
var error := ""
## A pasta do jogo não aceita gravação (ex.: Arquivos de Programas): só dá para baixar manualmente.
var manual_only := false

var _manifest := {}
var _manifest_url := MANIFEST_URL
var _http: HTTPRequest
var _zip_path := ""
var _interval := CHECK_INTERVAL
var _toast: CanvasLayer
var _toast_label: Label
var _toast_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--update-manifest="):
			_manifest_url = a.substr(18)
		elif a.begins_with("--update-interval="):
			_interval = maxf(a.substr(18).to_float(), 5.0)
	state_changed.connect(_on_state_for_toast)
	if not is_supported():
		return
	state = State.IDLE
	_cleanup_leftovers()
	var t := Timer.new()
	t.wait_time = _interval
	t.autostart = true
	t.timeout.connect(recheck)
	add_child(t)


## Procura de novo, menos quando já há versão nova conhecida ou algo em andamento.
## Chamado pelo timer e sempre que o menu principal abre (ex.: depois de cair do servidor que reiniciou).
func recheck() -> void:
	if state in [State.IDLE, State.UP_TO_DATE] or (state == State.FAILED and not has_newer()):
		check()


## Só o jogo exportado para Windows, com tela, se atualiza sozinho.
func is_supported() -> bool:
	return OS.has_feature("template") and OS.get_name() == "Windows" \
		and DisplayServer.get_name() != "headless" and not ("--server" in OS.get_cmdline_user_args())


func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0"))


## Compara versões "1.2.3" número a número. Retorna 1 se a > b, -1 se a < b, 0 se iguais.
static func compare_versions(a: String, b: String) -> int:
	var pa := a.strip_edges().trim_prefix("v").split(".")
	var pb := b.strip_edges().trim_prefix("v").split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := pa[i].to_int() if i < pa.size() else 0
		var y := pb[i].to_int() if i < pb.size() else 0
		if x != y:
			return 1 if x > y else -1
	return 0


## O manifesto já informou uma versão maior que esta.
func has_newer() -> bool:
	return latest_version != "" and compare_versions(latest_version, current_version()) > 0


## Pergunta ao GitHub qual é a versão mais nova. Pode ser chamado de novo (ex.: servidor recusou a versão).
func check() -> void:
	if state in [State.DISABLED, State.CHECKING, State.DOWNLOADING, State.INSTALLING]:
		return
	_set_state(State.CHECKING)
	_new_http()
	_http.timeout = CHECK_TIMEOUT
	_http.request_completed.connect(_on_manifest, CONNECT_ONE_SHOT)
	var err := _http.request(_manifest_url)
	if err != OK:
		_fail("Não foi possível procurar atualizações (erro %d)." % err)


func _on_manifest(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("Não foi possível procurar atualizações (HTTP %d, resultado %d)." % [code, result])
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Dictionary and data.has("version") and data.has("url") and data.has("sha256")):
		_fail("O manifesto de atualização veio em um formato inesperado.")
		return
	_manifest = data
	latest_version = str(data.version)
	if has_newer():
		print("[update] versão nova disponível: %s (esta: %s)" % [latest_version, current_version()])
		_set_state(State.AVAILABLE)
		if "--update-now" in OS.get_cmdline_user_args():
			install()
	else:
		_set_state(State.UP_TO_DATE)


## Baixa e instala a versão do manifesto. No fim o jogo reabre sozinho.
func install() -> void:
	if not can_install():
		return
	var dir := OS.get_executable_path().get_base_dir()
	if not _dir_writable(dir):
		manual_only = true
		_fail("Sem permissão para gravar em %s. Baixe a versão nova manualmente." % dir)
		return
	_zip_path = dir.path_join("EcosDeValdoria-update.zip")
	DirAccess.remove_absolute(_zip_path)
	_set_state(State.DOWNLOADING)
	_new_http()
	_http.download_file = _zip_path
	_http.request_completed.connect(_on_downloaded, CONNECT_ONE_SHOT)
	var err := _http.request(str(_manifest.url))
	if err != OK:
		_fail("Não foi possível baixar a atualização (erro %d)." % err)


## Há uma versão nova conhecida (também depois de um download que falhou, para tentar de novo).
func can_install() -> bool:
	if manual_only:
		return false
	return state == State.AVAILABLE or (state == State.FAILED and not _manifest.is_empty() and has_newer())


func _process(_delta: float) -> void:
	if state == State.DOWNLOADING and _http:
		var total := _http.get_body_size()
		if total <= 0:
			total = int(_manifest.get("size", 0))
		if total > 0:
			progress.emit(clampf(float(_http.get_downloaded_bytes()) / total, 0.0, 1.0))


func _on_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		DirAccess.remove_absolute(_zip_path)
		_fail("O download da atualização falhou (HTTP %d, resultado %d)." % [code, result])
		return
	progress.emit(1.0)
	_set_state(State.INSTALLING)
	# deixa a tela mostrar "Instalando..." antes do trabalho pesado (hash + extração travam um instante)
	await get_tree().process_frame
	await get_tree().process_frame
	var err_msg := _apply_update()
	if err_msg != "":
		_fail(err_msg)


## Confere, extrai e troca o executável. Retorna "" se deu certo (e o jogo já está reabrindo).
func _apply_update() -> String:
	var expected := str(_manifest.sha256).to_lower()
	var got := FileAccess.get_sha256(_zip_path).to_lower()
	if got != expected:
		DirAccess.remove_absolute(_zip_path)
		return "O arquivo baixado está corrompido (hash não confere). Tente de novo."

	var exe := OS.get_executable_path()
	var new_exe := exe + ".new"
	var old_exe := exe + ".old"
	var zip := ZIPReader.new()
	if zip.open(_zip_path) != OK:
		return "Não foi possível abrir o zip da atualização."
	var inner := _find_exe(zip.get_files(), str(_manifest.get("exe", exe.get_file())))
	if inner == "":
		zip.close()
		return "O zip da atualização não tem o executável do jogo."
	var bytes := zip.read_file(inner)
	zip.close()
	DirAccess.remove_absolute(_zip_path)
	if bytes.is_empty():
		return "O executável dentro do zip está vazio."
	var f := FileAccess.open(new_exe, FileAccess.WRITE)
	if f == null:
		return "Não foi possível gravar a atualização (erro %d)." % FileAccess.get_open_error()
	f.store_buffer(bytes)
	f.close()
	bytes = PackedByteArray()

	DirAccess.remove_absolute(old_exe)
	var err := DirAccess.rename_absolute(exe, old_exe)
	if err != OK:
		DirAccess.remove_absolute(new_exe)
		return "Não foi possível trocar o executável (erro %d). Feche outras cópias do jogo e tente de novo." % err
	err = DirAccess.rename_absolute(new_exe, exe)
	if err != OK:
		DirAccess.rename_absolute(old_exe, exe)   # devolve o exe antigo
		DirAccess.remove_absolute(new_exe)
		return "Não foi possível instalar o executável novo (erro %d)." % err

	print("[update] instalado %s; reabrindo o jogo" % latest_version)
	# get_cmdline_args() não inclui o que vem depois de "--": repassa os dois
	var args := OS.get_cmdline_args()
	var user_args := OS.get_cmdline_user_args()
	if not user_args.is_empty():
		args.append("--")
		args.append_array(user_args)
	var pid := OS.create_process(exe, args)
	if pid <= 0:
		return "Atualização instalada, mas o jogo não reabriu sozinho. Abra-o de novo."
	get_tree().quit()
	return ""


## Acha o exe no zip (na raiz ou numa subpasta).
func _find_exe(files: PackedStringArray, exe_name: String) -> String:
	for p in files:
		if p.get_file().to_lower() == exe_name.to_lower():
			return p
	for p in files:
		if p.to_lower().ends_with(".exe") and not p.to_lower().ends_with(".console.exe"):
			return p
	return ""


func open_releases_page() -> void:
	OS.shell_open(RELEASES_PAGE)


func _cleanup_leftovers() -> void:
	var exe := OS.get_executable_path()
	for p in [exe + ".old", exe + ".new", exe.get_base_dir().path_join("EcosDeValdoria-update.zip")]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _dir_writable(dir: String) -> bool:
	var probe := dir.path_join(".update-probe")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.close()
	DirAccess.remove_absolute(probe)
	return true


func _new_http() -> void:
	if _http:
		_http.cancel_request()
		_http.queue_free()
	_http = HTTPRequest.new()
	_http.use_threads = true
	add_child(_http)


func _fail(msg: String) -> void:
	error = msg
	printerr("[update] " + msg)
	_set_state(State.FAILED)


func _set_state(s: State) -> void:
	state = s
	state_changed.emit(s)


# ---------------------------------------------------------------- aviso durante a partida
## O menu principal tem o próprio aviso; nas outras cenas aparece este, no topo da tela.
func _on_state_for_toast(s: int) -> void:
	if s != State.AVAILABLE:
		_hide_toast()
		return
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path == ProjectSettings.get_setting("application/run/main_scene", ""):
		return
	_show_toast("Nova versão disponível: v%s (você tem v%s).
Aperte Esc e escolha \"Atualizar agora\" — o jogo salva e reabre sozinho." 		% [latest_version, current_version()])


func _show_toast(text: String) -> void:
	if _toast == null:
		_toast = CanvasLayer.new()
		_toast.layer = 90
		add_child(_toast)
		var root := Control.new()
		root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.theme = UITheme.get_theme()
		_toast.add_child(root)
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", UITheme.frame_box(UITheme.BG, UITheme.GOLD, 14))
		box.anchor_left = 0.5
		box.anchor_right = 0.5
		box.offset_top = 18
		box.grow_horizontal = Control.GROW_DIRECTION_BOTH
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(box)
		_toast_label = UITheme.label("", 18)
		_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(_toast_label)
	_toast_label.text = text
	var box := _toast_label.get_parent() as Control
	box.modulate.a = 1.0
	_toast.visible = true
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(TOAST_TIME)
	_toast_tween.tween_property(box, "modulate:a", 0.0, 1.0)
	_toast_tween.tween_callback(func() -> void: _toast.visible = false)


func _hide_toast() -> void:
	if _toast_tween:
		_toast_tween.kill()
	if _toast:
		_toast.visible = false
