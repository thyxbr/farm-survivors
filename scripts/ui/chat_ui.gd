extends CanvasLayer
## Chat do multiplayer (canto inferior esquerdo).
##   [Enter] abre a caixa de texto · [Enter] envia · [Esc] cancela.
## As mensagens novas aparecem por alguns segundos e somem; com a caixa aberta, o histórico fica
## visível. Enquanto digita, o personagem fica parado (as teclas vão para o texto, não para o jogo).
## Funciona também com as cartas da Horda abertas (dá para combinar a build com o grupo).

const UI_CARDS := preload("res://scripts/ui/survival_ui.gd")
const MAX_LINES := 50
const VISIBLE_LINES := 7
const FADE_AFTER := 9.0
const WIDTH := 440.0

var world: Node
var _root: Control
var _panel: PanelContainer
var _scroll: ScrollContainer
var _log: VBoxContainer
var _entry: LineEdit
var _hint: Label
var _open := false
var _lines: Array = []   # [{"node": Control, "t": float}]


func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.get_theme()
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 18
	_panel.offset_right = 18 + WIDTH
	_panel.offset_top = -250
	_panel.offset_bottom = -150
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(v)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.custom_minimum_size = Vector2(WIDTH - 20, 0)
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_scroll)
	_log = VBoxContainer.new()
	_log.add_theme_constant_override("separation", 2)
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_log)
	_entry = LineEdit.new()
	_entry.placeholder_text = "Mensagem para todos..."
	_entry.max_length = Network.CHAT_MAX
	_entry.custom_minimum_size = Vector2(WIDTH - 20, 34)
	_entry.context_menu_enabled = false
	_entry.text_submitted.connect(_on_submit)
	v.add_child(_entry)
	_hint = UITheme.outlined("[Enter] chat", 13, Color(0.75, 0.72, 0.65, 0.7), 3)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_hint)
	_set_open(false)
	Network.chat_received.connect(_on_message)
	Social.whisper.connect(_on_whisper)
	Network.players_changed.connect(_refresh_hint)
	_refresh_hint()


func is_open() -> bool:
	return _open


## Abre a caixa de texto já com `text` (ex.: "/w Ana " pelo botão Sussurrar da aba Amigos).
func open_with(text: String) -> void:
	if not _can_open():
		return
	_set_open(true)
	_entry.text = text
	_entry.caret_column = text.length()


func _refresh_hint() -> void:
	if _hint:
		_hint.text = "[Enter] chat  ·  %d online" % Network.players.size()


## O chat pode abrir com o jogo livre ou com as cartas da Horda na tela; outras janelas usam o Enter.
func _can_open() -> bool:
	if world == null:
		return true
	var m: Control = world.get("modal")
	return m == null or m.get_script() == UI_CARDS


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: Key = event.keycode
	if _open:
		if k == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_set_open(false)
		return
	if (k == KEY_ENTER or k == KEY_KP_ENTER) and _can_open():
		get_viewport().set_input_as_handled()
		_set_open(true)


func _on_submit(text: String) -> void:
	var t := text.strip_edges()
	if t.begins_with("/"):
		_run_command(t)
	elif t != "":
		Network.send_chat(t)
	_set_open(false)


## Comandos locais (começam com "/"): não vão para o servidor; a resposta aparece só para quem digitou.
##   /clima sol|chuva|neve|vento  força o clima nesta máquina · /clima auto  volta ao clima de todos
##   /hora 21 | 6:30  fixa a hora do dia nesta máquina · /hora auto  volta ao relógio do mundo
##   /w NOME msg  sussurro (mensagem só para ele) · /r msg  responde o último sussurro · /amigo NOME  pede amizade
##   /admin  liga/desliga o modo admin (recursos infinitos; só contas de administrador)
##   /item ID [quantidade]  põe um item na mochila (só com o modo admin ligado)
##   /grupo NOME  convida para o grupo · /grupo sair · /grupo expulsar NOME (estes vão ao servidor, pelo Party)
func _run_command(t: String) -> void:
	# sussurro: o texto vai como foi digitado (o resto dos comandos é sem diferenciar maiúsculas)
	var raw := t.substr(1).split(" ", false)
	var c0: String = raw[0].to_lower() if raw.size() > 0 else ""
	if c0 in ["w", "m", "sussurrar", "msg"]:
		if raw.size() < 3:
			_on_message("", "Uso: /w NOME mensagem (só para quem está online) · /r mensagem responde o último")
		else:
			Social.send_whisper(raw[1], " ".join(raw.slice(2)))
		return
	if c0 in ["r", "responder"]:
		if Social.last_whisper_from == "" or raw.size() < 2:
			_on_message("", "Ninguém sussurrou para você ainda. Use /w NOME mensagem.")
		else:
			Social.send_whisper(Social.last_whisper_from, " ".join(raw.slice(1)))
		return
	var parts := t.substr(1).to_lower().split(" ", false)
	var cmd: String = parts[0] if parts.size() > 0 else ""
	var arg: String = parts[1] if parts.size() > 1 else ""
	match cmd:
		"admin":
			if not Game.can_admin():
				_on_message("", "Só administradores podem usar o modo admin.")
				return
			if arg in ["on", "ligar", "liga"]:
				Econ.set_admin(true)
			elif arg in ["off", "desligar", "desliga"]:
				Econ.set_admin(false)
			else:
				Game.toggle_admin()
		"item", "dar":
			if arg == "":
				_on_message("", "Use /item ID [quantidade], com o modo admin ligado. Ex.: /item archmage_robe")
				return
			Econ.admin_give(arg, maxi(1, int(parts[2])) if parts.size() > 2 else 1)
		"clima", "weather":
			if arg == "auto":
				Weather.release()
				_on_message("", "Clima de volta ao normal (%s)." % WeatherRules.NAMES[WeatherRules.kind_at(Time.get_unix_time_from_system())])
				return
			var i := WeatherRules.NAMES.find(arg)
			if i < 0:
				_on_message("", "Uso: /clima sol | chuva | neve | vento | auto  (agora: %s%s)"
						% [Weather.kind_name(), ", forçado" if Weather.is_forced() else ""])
				return
			Weather.force(i)
			_on_message("", "Clima forçado: %s (só para você). /clima auto volta ao normal." % arg)
		"hora", "time":
			if arg == "auto":
				DayNightFX.forced_hour = -1.0
				_on_message("", "Hora de volta ao relógio do mundo (%s)." % DayNightRules.hour_text(DayNightFX.current_hour()))
				return
			var h := DayNightRules.parse_hour(arg)
			if h < 0.0:
				_on_message("", "Uso: /hora 21 | 6:30 | auto  (agora: %s%s)"
						% [DayNightRules.hour_text(DayNightFX.current_hour()), ", fixa" if DayNightFX.forced_hour >= 0.0 else ""])
				return
			DayNightFX.forced_hour = h
			_on_message("", "Hora fixada em %s (só para você). /hora auto volta ao normal." % DayNightRules.hour_text(h))
		"grupo", "party", "convidar", "invite":
			var who: String = parts[2] if parts.size() > 2 else ""
			if arg in ["sair", "leave"] and cmd in ["grupo", "party"]:
				Party.request_leave()
			elif arg in ["expulsar", "kick"] and cmd in ["grupo", "party"]:
				var peer := _peer_named(who)
				if peer == 0:
					_on_message("", "Uso: /grupo expulsar NOME")
				else:
					Party.request_kick(peer)
			elif arg != "":
				Party.request_invite_name(arg)
			else:
				_on_message("", "Uso: /grupo NOME (convida) · /grupo sair · /grupo expulsar NOME · [P] painel do grupo")
		"amigo", "friend", "add":
			if arg == "":
				_on_message("", "Uso: /amigo NOME (pede amizade) · [O] abre a aba Amigos")
			else:
				Social.request_add(arg)
		_:
			_on_message("", "Comando desconhecido: /%s  (comandos: /clima, /hora, /grupo, /amigo, /w, /r)" % cmd)


func _peer_named(n: String) -> int:
	for pid in Network.players:
		if str(Network.players[pid].name).to_lower() == n.to_lower():
			return pid
	return 0


func _set_open(on: bool) -> void:
	_open = on
	var sb := UITheme._box(Color(0.03, 0.03, 0.04, 0.78), UITheme.GOLD_DIM, 1, 8, 10, 8) if on \
		else UITheme._box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 8, 10, 8)
	_panel.add_theme_stylebox_override("panel", sb)
	_entry.visible = on
	_hint.visible = not on
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if on else ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS if on else Control.MOUSE_FILTER_IGNORE
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	var p: Player = world.get("player") if world else null
	if p:
		p.chat_typing = on
	if on:
		_entry.text = ""
		_entry.grab_focus()
	else:
		_entry.release_focus()
	_layout()


## Sussurro: "de Ana" (recebido) ou "para Ana" (o eco do que eu mandei), em lilás.
func _on_whisper(from: String, to: String, text: String, incoming: bool) -> void:
	var who := ("de %s" % from) if incoming else ("para %s" % to)
	_add_line("[b][color=#e3a6ff]%s:[/color][/b] [color=#f1dcff]%s[/color]" % [who.replace("[", "[lb]"), text.replace("[", "[lb]")])


func _on_message(from: String, text: String) -> void:
	var safe := text.replace("[", "[lb]")
	if from == "":
		_add_line("[color=#ffb070]%s[/color]" % safe)
	else:
		var mine := from == Network.my_name
		var col := "#9fd2ff" if mine else _name_color(from)
		_add_line("[b][color=%s]%s:[/color][/b] [color=#f0ebe0]%s[/color]" % [col, from.replace("[", "[lb]"), safe])


func _add_line(bbcode: String) -> void:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WIDTH - 24
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("normal_font_size", 17)
	l.add_theme_font_size_override("bold_font_size", 17)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.text = bbcode
	_log.add_child(l)
	_lines.append({"node": l, "t": 0.0})
	while _lines.size() > MAX_LINES:
		var old: Dictionary = _lines.pop_front()
		if is_instance_valid(old.node):
			old.node.queue_free()
	if not _open:
		Sfx.play("click", 0.05, -8.0)
	_layout()
	_scroll_to_end.call_deferred()


## Cor estável por nome (cada jogador sempre com a mesma cor).
func _name_color(n: String) -> String:
	var hues := ["#ffd27a", "#a6f0a0", "#f5a0d0", "#c8b0ff", "#ffb38a", "#8ee6e0", "#f0e68c", "#ff9f9f"]
	return hues[abs(n.hash()) % hues.size()]


func _layout() -> void:
	var shown := 0
	for i in range(_lines.size() - 1, -1, -1):
		var e: Dictionary = _lines[i]
		var n: Control = e.node
		if not is_instance_valid(n):
			continue
		if _open:
			n.visible = true
			n.modulate.a = 1.0
		else:
			n.visible = shown < VISIBLE_LINES and e.t < FADE_AFTER + 1.0
			if n.visible:
				shown += 1
	_fit_scroll()


func _fit_scroll() -> void:
	var content := _log.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = 230.0 if _open else minf(content, 420.0)


func _scroll_to_end() -> void:
	if _scroll:
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _process(delta: float) -> void:
	if _open:
		# a janela da Horda pode ter aberto por cima: o texto continua com o foco
		var p: Player = world.get("player") if world else null
		if p:
			p.chat_typing = true
		if not _entry.has_focus():
			_entry.grab_focus()
		return
	_fit_scroll()
	var changed := false
	for e in _lines:
		e.t += delta
		var n: Control = e.node
		if not is_instance_valid(n) or not n.visible:
			continue
		if e.t > FADE_AFTER:
			n.modulate.a = clampf(1.0 - (e.t - FADE_AFTER), 0.0, 1.0)
			if n.modulate.a <= 0.0:
				changed = true
	if changed:
		_layout()
