extends CanvasLayer
## HUD da praça: bem mais simples que o de Valdoria (não há combate). Mostra Ecos e ouro no canto,
## a dica de interação do ponto mais perto, a linha de emotes e os avisos (Game.notify).

var player: Player

var root: Control
var _ecos: Label
var _gold: Label
var _prompt_box: HBoxContainer
var _prompt: Label
var _feed: VBoxContainer


func _ready() -> void:
	layer = 5
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)

	# --- canto superior direito: Ecos e ouro
	var purse := PanelContainer.new()
	purse.add_theme_stylebox_override("panel", UITheme._box(Color(0.03, 0.025, 0.02, 0.6), UITheme.GOLD_DIM, 1, 6, 14, 6))
	purse.anchor_left = 1.0
	purse.anchor_right = 1.0
	purse.offset_left = -300
	purse.offset_right = -16
	purse.offset_top = 16
	purse.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	purse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(purse)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	h.alignment = BoxContainer.ALIGNMENT_END
	purse.add_child(h)
	_ecos = UITheme.outlined("", 20, Color(0.6, 0.85, 1.0), 4)
	h.add_child(_ecos)
	_gold = UITheme.outlined("", 20, Color(1, 0.85, 0.35), 4)
	h.add_child(_gold)

	# --- título da praça (canto superior esquerdo)
	var title := UITheme.outlined("Praça de Valdoria", 30, UITheme.GOLD, 8)
	title.position = Vector2(22, 14)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title)

	# --- dica de interação (embaixo, no centro)
	_prompt_box = HBoxContainer.new()
	_prompt_box.add_theme_constant_override("separation", 8)
	_prompt_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_prompt_box.add_child(UITheme.keycap("E", 13))
	_prompt = UITheme.outlined("", 18, Color(1, 0.95, 0.78), 5)
	_prompt_box.add_child(_prompt)
	_prompt_box.anchor_left = 0.5
	_prompt_box.anchor_right = 0.5
	_prompt_box.anchor_top = 1.0
	_prompt_box.anchor_bottom = 1.0
	_prompt_box.offset_left = -350
	_prompt_box.offset_right = 350
	_prompt_box.offset_top = -120
	_prompt_box.offset_bottom = -90
	_prompt_box.visible = false
	for c in _prompt_box.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_prompt_box)

	# --- emotes e chat (rodapé)
	var keys := UITheme.outlined("[1] Acenar  ·  [2] Comemorar  ·  [3] Sentar  ·  [Enter] Chat", 15,
		Color(0.85, 0.82, 0.74, 0.85), 4)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keys.anchor_left = 0.5
	keys.anchor_right = 0.5
	keys.anchor_top = 1.0
	keys.anchor_bottom = 1.0
	keys.offset_left = -350
	keys.offset_right = 350
	keys.offset_top = -44
	keys.offset_bottom = -20
	keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(keys)

	# --- avisos (esquerda, no meio da tela; o canto inferior esquerdo é do chat)
	_feed = VBoxContainer.new()
	_feed.add_theme_constant_override("separation", 4)
	_feed.anchor_top = 0.5
	_feed.anchor_bottom = 0.5
	_feed.offset_left = 16
	_feed.offset_right = 520
	_feed.offset_top = -150
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_feed)

	Game.notify.connect(_on_notify)
	Game.stats_changed.connect(_refresh)
	Game.inventory_changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if Game.notify.is_connected(_on_notify):
		Game.notify.disconnect(_on_notify)


func _refresh() -> void:
	_ecos.text = "✦ %d Ecos" % Game.ecos
	_gold.text = "◆ %d ouro" % Game.gold


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		_prompt_box.visible = false
		return
	var t := player.interact_target
	_prompt_box.visible = t != null and t.has_method("interact_prompt") and not player.dead
	if _prompt_box.visible:
		_prompt.text = t.interact_prompt()


func _on_notify(text: String, color: Color) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme._box(Color(0.03, 0.025, 0.02, 0.45), Color(0, 0, 0, 0), 0, 4, 8, 2))
	var l := UITheme.outlined(text, 15, color, 4)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 480
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_feed.add_child(p)
	while _feed.get_child_count() > 5:
		_feed.get_child(0).free()
	var tw := p.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(p, "modulate:a", 0.0, 1.0)
	tw.tween_callback(p.queue_free)
