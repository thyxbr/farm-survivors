class_name RegionBanner
extends Control
## Letreiro de entrada de região, no alto do centro da tela: o nome grande e a faixa de nível embaixo,
## entre dois traços dourados. Entra com fade, fica HOLD s e some. O HUD decide quando mostrar
## (MapRules.entered: só ao chegar numa região diferente da última).

const HOLD := 2.6
const FADE := 0.5

var _title: Label
var _sub: Label
var _tw: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	offset_left = -300.0
	offset_right = 300.0
	offset_top = 118.0
	offset_bottom = 196.0
	modulate.a = 0.0
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_title = UITheme.outlined("", 34, UITheme.GOLD, 7)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_sub = UITheme.outlined("", 17, UITheme.TEXT, 5)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_sub)


## Mostra o letreiro (troca na hora se já havia outro).
func show_area(title: String, sub: String) -> void:
	_title.text = title
	_sub.text = sub
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = create_tween()
	_tw.tween_property(self, "modulate:a", 1.0, FADE)
	_tw.tween_interval(HOLD)
	_tw.tween_property(self, "modulate:a", 0.0, FADE * 2.0)
	queue_redraw()


## Dois traços dourados dos lados do nome.
func _draw() -> void:
	if _title == null or _title.text == "":
		return
	var w := _title.get_theme_font("font").get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	var y := size.y * 0.42
	var c := Color(UITheme.GOLD, 0.8)
	var half := size.x / 2.0
	draw_line(Vector2(half - w / 2.0 - 70, y), Vector2(half - w / 2.0 - 14, y), c, 2.0, true)
	draw_line(Vector2(half + w / 2.0 + 14, y), Vector2(half + w / 2.0 + 70, y), c, 2.0, true)
