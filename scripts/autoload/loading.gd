extends CanvasLayer
## Tela de carregamento: cobre as trocas de cena do cliente e só abre quando o mundo novo está pronto.
##
## `Loading.go(cena)` entra no lugar de `get_tree().change_scene_to_file(cena)`:
##   escurece → troca a cena → espera o mundo montar, alguns quadros desenhados (os primeiros travam
##   compilando shaders) e, em Valdoria online, o primeiro snapshot de inimigos → clareia.
## Enquanto cobre (`covering`), o jogador fica sem controle e imune (player.gd); ao abrir ganha GRACE
## segundos de imunidade, para não nascer apanhando no meio dos monstros.
## Em headless (testes e servidor dedicado) a troca é direta; `force` liga a tela num teste.

const FADE_IN := 0.15
const FADE_OUT := 0.4
const MIN_TIME := 0.7      # tempo mínimo coberto: sem isso a tela só pisca
const MIN_FRAMES := 6      # quadros da cena nova desenhados por baixo antes de abrir
const NET_WAIT := 1.5      # online: espera o primeiro snapshot de inimigos até aqui
const MAX_WAIT := 15.0     # teto: abre de qualquer jeito
const GRACE := 2.0         # imunidade depois que a tela abre

const NAMES := {
	"res://scenes/world.tscn": "Viajando para Valdoria…",
	"res://scenes/main_menu.tscn": "Voltando ao menu…",
}
const TIPS := [
	"Esquivar (Ctrl) deixa você imune por um instante.",
	"Segure Shift para correr.",
	"R e F bebem as poções.",
	"Plante e cozinhe na Horta, saindo pelo portão sul da vila.",
	"O Ancião Bram, na praça da vila, tem missões para você.",
	"As teclas 1 a 3 usam as habilidades da arma; a 4, a ultimate.",
	"I abre o inventário e C, a ficha do personagem.",
	"O Mestre Orin, ao lado do portal da vila, troca Ecos por passivas permanentes.",
]

## A tela está cobrindo o jogo (o jogador fica travado e imune).
var covering := false
## Testes: usa a tela mesmo em headless.
var force := false

## Fração montada do mundo (0–1); -1 = a cena não informa (sem barra, só o anel girando).
var progress := -1.0

var _seq := 0
var _root: Control
var _dest: Label
var _tip: Label
var _spinner: Control
var _spin := 0.0
var _fade: Tween


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false
	_root.modulate.a = 0.0


## Troca de cena coberta pela tela de carregamento.
func go(path: String) -> void:
	var tree := get_tree()
	if DisplayServer.get_name() == "headless" and not force:
		tree.change_scene_to_file(path)
		return
	_seq += 1
	var seq := _seq
	_dest.text = NAMES.get(path, "Carregando…")
	_tip.text = TIPS[randi() % TIPS.size()]
	progress = -1.0
	covering = true
	_root.visible = true
	_root.mouse_filter = Control.MOUSE_FILTER_STOP   # nenhum clique passa para o jogo coberto
	if _root.modulate.a < 1.0:
		_fade_to(1.0, FADE_IN)
		await _fade.finished
		if seq != _seq:
			return
	# um quadro com a tela cheia desenhada antes de a troca travar o jogo
	await tree.process_frame
	if seq != _seq:
		return

	var old := tree.current_scene
	var snaps := Network.snapshots_received
	var t0 := Time.get_ticks_msec()
	if tree.change_scene_to_file(path) != OK:
		_open(seq)
		return
	# a troca acontece no fim do quadro: espera a cena nova entrar
	while tree.current_scene == null or (is_instance_valid(old) and tree.current_scene == old):
		await tree.process_frame
		if seq != _seq:
			return
		if _elapsed(t0) > MAX_WAIT:
			break
	var scene := tree.current_scene
	# Valdoria monta o mapa em etapas (world.gd): espera terminar
	while is_instance_valid(scene) and scene.get("built") == false and _elapsed(t0) < MAX_WAIT:
		await tree.process_frame
		if seq != _seq:
			return
	var t_ready := Time.get_ticks_msec()
	var frames := 0
	while _elapsed(t0) < MAX_WAIT:
		await tree.process_frame
		if seq != _seq:
			return
		frames += 1
		if frames < MIN_FRAMES or _elapsed(t0) < MIN_TIME:
			continue
		if _waiting_enemies(scene) and Network.snapshots_received == snaps and _elapsed(t_ready) < NET_WAIT:
			continue
		break
	_open(seq)


## Valdoria online: os inimigos chegam do servidor depois que a cena monta.
func _waiting_enemies(scene: Node) -> bool:
	return Network.is_client() and is_instance_valid(scene) and scene.get("player") != null \
		and scene.get("role") == null


func _elapsed(since_msec: int) -> float:
	return (Time.get_ticks_msec() - since_msec) / 1000.0


func _open(seq: int) -> void:
	var p := _player()
	if p != null:
		p.invuln = maxf(p.invuln, GRACE)
	covering = false
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_to(0.0, FADE_OUT)
	await _fade.finished
	if seq == _seq:
		_root.visible = false


## A cena que monta o mundo em etapas informa quanto já fez (a barra aparece a partir da primeira chamada).
func set_progress(frac: float) -> void:
	progress = clampf(frac, 0.0, 1.0)


func _fade_to(alpha: float, time: float) -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade.tween_property(_root, "modulate:a", alpha, time)


func _player() -> Player:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var p = scene.get("player")
	return p if p is Player and is_instance_valid(p) else null


## Coberto, nenhuma tecla chega aos menus e atalhos da cena (_unhandled_input).
func _input(_event: InputEvent) -> void:
	if covering:
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _root.visible:
		return
	_spin += delta
	_spinner.queue_redraw()


# ---------------------------------------------------------------- visual
func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	add_child(_root)

	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.03, 0.03)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 14)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var title := Label.new()
	title.text = "Ecos de Valdoria"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UITheme.serif())
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	center.add_child(title)

	_dest = Label.new()
	_dest.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dest.add_theme_font_size_override("font_size", 26)
	_dest.add_theme_color_override("font_color", UITheme.TEXT)
	center.add_child(_dest)

	_spinner = Control.new()
	_spinner.custom_minimum_size = Vector2(0, 110)
	_spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spinner.draw.connect(_draw_spinner)
	center.add_child(_spinner)

	_tip = Label.new()
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.add_theme_font_size_override("font_size", 20)
	_tip.add_theme_color_override("font_color", UITheme.DIM)
	_tip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_tip.offset_top = -90.0
	_tip.offset_bottom = -50.0
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_tip)


## Anel dourado girando: um arco claro correndo sobre um aro apagado.
func _draw_spinner() -> void:
	var c := Vector2(_spinner.size.x * 0.5, 36.0)
	var r := 22.0
	_spinner.draw_arc(c, r, 0.0, TAU, 48, Color(UITheme.GOLD_DIM, 0.35), 3.0, true)
	var a := _spin * 4.0
	_spinner.draw_arc(c, r, a, a + TAU * 0.3, 24, UITheme.GOLD, 3.0, true)
	if progress >= 0.0:
		var bar := Rect2(c.x - 160.0, c.y + r + 22.0, 320.0, 6.0)
		_spinner.draw_rect(bar, Color(UITheme.GOLD_DIM, 0.35))
		_spinner.draw_rect(Rect2(bar.position, Vector2(bar.size.x * progress, bar.size.y)), UITheme.GOLD)
