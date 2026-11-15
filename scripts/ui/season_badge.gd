class_name SeasonBadge
extends PanelContainer
## Selo da estação no HUD (Valdoria e praça): estação atual, dia e hora do jogo e quanto falta para
## a próxima estação. Lê o autoload Weather, que segue o relógio do servidor no multiplayer: todos os
## jogadores veem a mesma estação, a mesma hora e o mesmo contador.

var _season: Label
var _clock: Label
var _next: Label
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UITheme._box(Color(0.03, 0.025, 0.02, 0.6), UITheme.GOLD_DIM, 1, 6, 12, 5))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.alignment = BoxContainer.ALIGNMENT_END
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	_season = UITheme.outlined("", 17, Color.WHITE, 4)
	top.add_child(_season)
	_clock = UITheme.outlined("", 15, UITheme.TEXT, 4)
	top.add_child(_clock)
	_next = UITheme.outlined("", 12, Color(0.85, 0.82, 0.74, 0.9), 3)
	_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_next)
	for c in [_season, _clock, _next]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh()


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = 0.2
		_refresh()


func _refresh() -> void:
	var k: int = Weather.season
	_season.text = SeasonRules.TITLES[k]
	_season.add_theme_color_override("font_color", SeasonRules.COLORS[k])
	var c: Dictionary = Weather.game_clock()
	_clock.text = "Dia %d  ·  %02d:%02d" % [c.day, c.hour, c.minute]
	var nk := SeasonRules.next_kind(k)
	_next.text = "%s em %s" % [SeasonRules.TITLES[nk], SeasonRules.countdown_text(Weather.season_left())]
