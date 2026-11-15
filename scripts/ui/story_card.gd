class_name StoryCard
extends CanvasLayer
## Cartão de título de episódio, no estilo dos "eyecatch" de anime: uma faixa escura entra na diagonal,
## "EPISÓDIO N" em dourado e o título grande por cima, segura uns segundos e sai. Aparece quando uma missão
## que abre capítulo (quests.json, "chapter") é aceita e, no fim da história, o cartão de encerramento.
## Fica na fila enquanto houver uma janela aberta (o diálogo que aceitou a missão) e toca quando ela fecha.

const HOLD := 2.8
const SLIDE := 0.45

var world: Node
var _queue: Array = []        # [kicker, título]
var _playing := false
var _last := {}               # cópia de Game.quests, para achar os capítulos que acabaram de começar
var band: Control
var kicker: Label
var title: Label


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	band = Band.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.anchor_left = 0.0
	band.anchor_right = 1.0
	band.anchor_top = 0.5
	band.anchor_bottom = 0.5
	band.offset_top = -95
	band.offset_bottom = 95
	band.visible = false
	root.add_child(band)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	band.add_child(v)
	kicker = UITheme.outlined("", 22, UITheme.GOLD, 5)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(kicker)
	title = UITheme.outlined("", 52, Color(1, 0.97, 0.9), 10)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UITheme.serif())
	v.add_child(title)
	_last = Game.quests.duplicate(true)
	Game.quests_changed.connect(_on_quests)
	Game.ranked_up.connect(enqueue_rank)


func _on_quests() -> void:
	var qt: Dictionary = ItemDB.QUESTS
	for id in StoryRules.new_chapters(qt, _last, Game.quests):
		var ch: Dictionary = qt[id].chapter
		var n := int(ch.get("n", 0))
		enqueue("EPISÓDIO %d" % n if n > 0 else "EPISÓDIO", str(ch.get("title", "")))
	_last = Game.quests.duplicate(true)


func enqueue(top: String, text: String) -> void:
	_queue.append([top, text])


## O cartão do fim da história.
func enqueue_end(kicker := "") -> void:
	enqueue(kicker if kicker != "" else "FIM DO PRIMEIRO ARCO", "Obrigado por jogar!")


## Promoção na guilda (Game.ranked_up).
func enqueue_rank(rank: String) -> void:
	var title := ""
	for r in Balance.tables.get_table("guild").get("ranks", []):
		if r.id == rank:
			title = str(r.get("title", ""))
	enqueue("PROMOÇÃO NA GUILDA", "Rank %s · %s" % [rank, title])


func _process(_delta: float) -> void:
	# com uma janela aberta (diálogo, menu) o cartão em curso some, para não cobrir o texto
	band.modulate.a = 0.0 if world and world.get("modal") != null else 1.0
	if _playing or _queue.is_empty():
		return
	if world and world.get("modal") != null:
		return
	_play(_queue.pop_front())


func _play(card: Array) -> void:
	_playing = true
	kicker.text = card[0]
	title.text = card[1]
	band.visible = true
	band.modulate.a = 1.0
	var w := get_viewport().get_visible_rect().size.x
	band.position.x = -w
	kicker.modulate.a = 0.0
	title.modulate.a = 0.0
	Sfx.play("levelup", -4.0)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(band, "position:x", 0.0, SLIDE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(kicker, "modulate:a", 1.0, 0.25)
	tw.tween_property(title, "modulate:a", 1.0, 0.35)
	tw.tween_interval(HOLD)
	tw.tween_property(band, "position:x", w, SLIDE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(_done)


func _done() -> void:
	band.visible = false
	_playing = false


## Faixa diagonal escura com filetes dourados (desenhada, sem textura).
class Band extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var slant := 40.0
		var body := PackedVector2Array([Vector2(0, slant), Vector2(w, 0), Vector2(w, h - slant), Vector2(0, h)])
		draw_colored_polygon(body, Color(0.04, 0.03, 0.05, 0.88))
		draw_line(Vector2(0, slant + 6), Vector2(w, 6), UITheme.GOLD, 2.0, true)
		draw_line(Vector2(0, h - 6), Vector2(w, h - slant - 6), UITheme.GOLD, 2.0, true)
		# um risco vermelho atravessando (o "corte" do eyecatch)
		draw_line(Vector2(w * 0.08, h - 14), Vector2(w * 0.3, slant * 0.5 + 10), Color(0.85, 0.2, 0.2, 0.55), 3.0, true)
