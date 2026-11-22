class_name LevelUpFX
extends RefCounted
## Subida de nível no estilo do Ragnarok Online: coluna de luz dourada sobe do chão, um selo abre aos
## pés, dois fios de brilhos sobem em espiral em volta do corpo e o letreiro "LEVEL UP!" estala em cima
## da cabeça (pula grande, assenta, flutua e some), com o nível novo embaixo. Usa as peças desenhadas de
## HolyFX (coluna, selo, estrela) para combinar com o resto dos efeitos. Nada aparece no servidor dedicado.

const FONT := preload("res://assets/fonts/Cinzel.ttf")
const TEXT_GOLD := Color(1.0, 0.86, 0.3)
const TEXT_EDGE := Color(0.42, 0.18, 0.02)
const TEXT_Y := 2.55          ## altura do letreiro acima dos pés (humano; o anão usa body_y)
const SPIRAL_TIME := 1.05


## Toca o efeito inteiro em `who` (o personagem que subiu); `level` = nível novo.
static func play(who: Node3D, level: int) -> void:
	if who == null or not is_instance_valid(who) or FX._scene() == null:
		return
	var feet := who.global_position
	var pal := HolyFX.PAL_GOLD
	# chão e coluna: o selo abre e a coluna sobe num estalo, translúcida para não estourar no bloom
	HolyFX.seal(feet, pal, 1.7, 1.3, {"ticks": 16, "glyph": false})
	HolyFX.seal(feet, pal, 2.6, 1.0, {"inner": false, "thick": 0.04, "delay": 0.1})
	HolyFX.pillar(feet, pal, 0.85, 5.0, 1.1, {"alpha": 0.3, "core": 0.2, "dense": 0.7})
	HolyFX.pillar(feet, pal, 0.16, 7.0, 0.7, {"delay": 0.04, "alpha": 0.7, "core": 0.6, "dense": 0.6})
	FXEpic.flash(feet + Vector3.UP * KnightLook.body_y(who, 1.4), HolyFX.GOLD, 2.2, 6.0, 0.6)
	# espiral de brilhos subindo em volta do corpo
	var sp := Spiral.new()
	sp.top = KnightLook.body_y(who, 2.6)
	who.add_child(sp)
	# letreiro
	var y := KnightLook.body_y(who, TEXT_Y)
	_banner(who, y, level)
	# estrela grande atrás do letreiro, quando ele estala
	HolyFX.star(feet + Vector3.UP * y, pal, 1.9, {"points": 12, "sharp": 2.2, "body": 0.24, "delay": 0.12,
		"hold": 0.1, "fade": 0.35, "shadow": true})
	# brilhos caindo devagar depois, como poeira de luz
	(who.get_tree().create_timer(0.7)).timeout.connect(func() -> void:
		if is_instance_valid(who):
			HolyFX.sparkles(who.global_position + Vector3.UP * KnightLook.body_y(who, 2.2), pal, 10, 1.1, 0.8, 0.0, 0.22))


## "LEVEL UP!" e "Nível N" presos no personagem (acompanham se ele andar).
static func _banner(who: Node3D, y: float, level: int) -> void:
	var root := Node3D.new()
	root.position = Vector3.UP * y
	who.add_child(root)
	var title := _label("LEVEL UP!", 112, TEXT_GOLD, TEXT_EDGE, 28)
	root.add_child(title)
	var sub := _label("Nível %d" % level, 52, Color(1.0, 0.97, 0.85), TEXT_EDGE, 16)
	sub.position = Vector3.DOWN * 0.42
	root.add_child(sub)
	# estalo: começa pequeno, passa do tamanho, assenta; flutua e some
	root.scale = Vector3.ONE * 0.2
	title.transparency = 1.0
	sub.transparency = 1.0
	var tw := root.create_tween()
	tw.tween_interval(0.12)
	tw.tween_property(title, "transparency", 0.0, 0.06)
	tw.parallel().tween_property(root, "scale", Vector3.ONE * 1.25, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(sub, "transparency", 0.0, 0.2)
	tw.tween_property(root, "position:y", y + 0.35, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(title, "transparency", 1.0, 0.45).set_delay(1.05)
	tw.parallel().tween_property(sub, "transparency", 1.0, 0.45).set_delay(1.05)
	tw.tween_callback(root.queue_free)
	# brilho pulsando no letreiro enquanto ele está assentado
	var pulse := title.create_tween().set_loops(4)
	pulse.tween_property(title, "modulate", Color(1.0, 0.97, 0.75), 0.18).set_delay(0.3)
	pulse.tween_property(title, "modulate", TEXT_GOLD, 0.18)


static func _label(text: String, size: int, color: Color, edge: Color, outline: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = FONT
	l.font_size = size
	l.outline_size = outline
	l.modulate = color
	l.outline_modulate = edge
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 10
	l.outline_render_priority = 9
	l.pixel_size = 0.005
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return l


## Dois fios de estrelinhas subindo em hélice em volta do personagem (o raio fecha conforme sobe).
class Spiral extends Node3D:
	var top := 2.6
	var _t := 0.0
	var _emit := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if _t >= LevelUpFX.SPIRAL_TIME:
			queue_free()
			return
		_emit -= delta
		if _emit > 0.0:
			return
		_emit = 0.028
		var k := _t / LevelUpFX.SPIRAL_TIME
		var h := top * (1.0 - pow(1.0 - k, 1.6))
		var r := lerpf(1.0, 0.45, k)
		var base := global_position
		for strand in 2:
			var a := _t * 9.0 + PI * strand
			var p := base + Vector3(cos(a) * r, h, sin(a) * r)
			HolyFX.star(p, HolyFX.PAL_GOLD, randf_range(0.18, 0.28) * (1.0 - 0.4 * k),
				{"hold": 0.12, "fade": 0.3, "rise": Vector3.UP * 0.6})
