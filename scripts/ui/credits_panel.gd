extends Control
## Créditos (menu principal). A lista de áudio espelha assets/audio/CREDITS.md: a faixa CC-BY exige
## o crédito visível no jogo.

signal closed

const AUDIO := [
	["Música", [
		"15 Melodic RPG Chiptunes — Aureolus_Omicron (CC0)",
		"Chiptune Adventures e Retro Game Music Pack — Juhani Junkala (CC0)",
		"The Bard's Tale e The Old Tower Inn — RandomMind (CC0)",
		"\"Big Scary Monster\", de Chiptune RPG Soundtrack — Trex0n (CC-BY 4.0; volume nivelado e convertido para OGG)",
	]],
	["Efeitos sonoros", [
		"512 Sound Effects (8-bit style) — Juhani Junkala (CC0)",
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
	v.add_child(UITheme.label("Todo o áudio vem do OpenGameArt.org.", 14, UITheme.DIM))
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
