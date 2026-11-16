extends Control
## Créditos (menu principal). A lista de áudio espelha assets/audio/CREDITS.md: as obras CC-BY exigem
## o crédito visível no jogo.

signal closed

const AUDIO := [
	["Música", [
		"\"Asami's Journey\" (Contemplative Fantasy Vol. 2) — YannZ (CC-BY 4.0)",
		"Town Theme RPG — cynicmusic (CC0)",
		"Squirrel Village — SoManyWhales (CC-BY 4.0)",
		"Deck the Halls — Dizzy Crow (Daniel Michel) (CC-BY 4.0)",
		"\"Morning Frost\" — Jonathan Shaw, www.jshaw.co.uk (CC-BY 3.0) · Cheerful Christmas Time — Tarush Singhal (CC0) · mixagem de glitchart",
		"\"Greenland Theme\" e \"Battle Theme 3\" — Alexandr Zhelanov (CC-BY 4.0)",
		"Dark Cavern Ambient — Paul Wortmann (CC0)",
		"\"Blackmoor Colossus\" (Colossal Boss Battle Theme) — Matthew Pablo, www.matthewpablo.com (CC-BY 3.0)",
	]],
	["Efeitos sonoros", [
		"Fantasy SFX Pack Vol 1 — JC Sounds (CC-BY 4.0)",
		"8 Magic Attacks — leohpaz (CC-BY 4.0)",
		"Magic SFX Sample — ViRiX (CC-BY 3.0)",
		"Fleshy Fight Sounds — will_leamon (OGA-BY 3.0)",
		"RPG Sound Pack — artisticdude (CC0) · 80 CC0 RPG SFX — rubberduck (CC0)",
		"50 RPG sound effects — Kenney (CC0) · Impact — qubodup (CC0) · Thwack Sounds — AntumDeluge (CC0)",
	]],
	["Ambiente", [
		"Birds and Wind — Spring Spring (CC0)",
		"Crickets Ambient Noise — Wolfgang_ (CC0)",
		"Fireplace Sound loop — PagDev (CC0)",
	]],
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := UITheme.centered_panel(self, 0.6)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.custom_minimum_size = Vector2(640, 0)
	p.add_child(v)
	v.add_child(UITheme.label("Créditos", 30, UITheme.GOLD))
	v.add_child(UITheme.label("Feito com Godot 4 · modelos low-poly criados no Blender", 16, UITheme.DIM))
	for group in AUDIO:
		var sp := Control.new()
		sp.custom_minimum_size.y = 6
		v.add_child(sp)
		v.add_child(UITheme.label(group[0], 20, UITheme.GOLD))
		for line in group[1]:
			var l := UITheme.label(line, 15)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(l)
	var sp2 := Control.new()
	sp2.custom_minimum_size.y = 6
	v.add_child(sp2)
	var note := UITheme.label("Todo o áudio vem do OpenGameArt.org (formatos convertidos, volume nivelado e cortes de duração).", 14, UITheme.DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	var back := UITheme.button("Voltar", _close)
	v.add_child(back)
	back.grab_focus.call_deferred()


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_close()
