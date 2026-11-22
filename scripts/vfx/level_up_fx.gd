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
## Anjo (imagem com fundo transparente, de frente). Sem o arquivo, o efeito toca sem ele.
const ANGEL_PATH := "res://assets/vfx/level_up_angel.png"
const ANGEL_HEIGHT := 1.5     ## altura do anjo no mundo (m)
const SPIRIT_SHADER := preload("res://shaders/fx_spirit.gdshader")

static var _spirit_mat: ShaderMaterial


## Toca o efeito inteiro em `who` (o personagem que subiu); `level` = nível novo.
static func play(who: Node3D, level: int) -> void:
	if who == null or not is_instance_valid(who) or FX._scene() == null:
		return
	var feet := who.global_position
	var pal := HolyFX.PAL_GOLD
	# chão e coluna: selo fino e coluna bem translúcida (forte demais escondia o personagem e cansava)
	HolyFX.seal(feet, pal, 1.3, 1.2, {"ticks": 8, "thick": 0.07})
	HolyFX.pillar(feet, pal, 0.6, 4.2, 1.0, {"alpha": 0.16, "core": 0.08, "dense": 0.5})
	FXEpic.flash(feet + Vector3.UP * KnightLook.body_y(who, 1.4), HolyFX.GOLD, 0.8, 4.0, 0.5)
	# espiral de brilhos subindo em volta do corpo
	var sp := Spiral.new()
	sp.top = KnightLook.body_y(who, 2.6)
	who.add_child(sp)
	# anjo subindo atrás do personagem (se a imagem existir)
	_angel(who)
	# letreiro
	var y := KnightLook.body_y(who, TEXT_Y)
	_banner(who, y, level)
	# estrelinha atrás do letreiro, quando ele estala
	HolyFX.star(feet + Vector3.UP * y, pal, 0.9, {"points": 8, "sharp": 2.6, "body": 0.18, "delay": 0.12,
		"hold": 0.06, "fade": 0.25})
	# brilhos caindo devagar depois, como poeira de luz
	(who.get_tree().create_timer(0.7)).timeout.connect(func() -> void:
		if is_instance_valid(who):
			HolyFX.sparkles(who.global_position + Vector3.UP * KnightLook.body_y(who, 2.2), pal, 6, 1.0, 0.7, 0.0, 0.18))


## O anjo é um espírito (shaders/fx_spirit.gdshader: translúcido, dourado, halo e pés em rastro), soltando
## brilhos enquanto sobe (AngelSparkle).
## Sai de dentro do personagem, sobe até acima do letreiro balançando de leve, com as asas "batendo"
## (o quad estica e encolhe na largura), e se desfaz no alto.
static func _angel(who: Node3D) -> void:
	if not ResourceLoader.exists(ANGEL_PATH):
		return
	var tex: Texture2D = load(ANGEL_PATH)
	if _spirit_mat == null:
		_spirit_mat = ShaderMaterial.new()
		_spirit_mat.shader = SPIRIT_SHADER
		_spirit_mat.set_shader_parameter("tex", tex)
	var q := QuadMesh.new()
	q.size = Vector2(ANGEL_HEIGHT * tex.get_width() / float(tex.get_height()), ANGEL_HEIGHT)
	var a := MeshInstance3D.new()
	a.mesh = q
	a.material_override = _spirit_mat
	a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	a.sorting_offset = -0.5          # atrás do letreiro
	a.set_instance_shader_parameter("fade", 0.0)
	var y0 := KnightLook.body_y(who, 1.0)
	var y1 := KnightLook.body_y(who, TEXT_Y + 1.7)
	a.position = Vector3(0, y0, 0)
	a.scale = Vector3.ONE * 0.6
	who.add_child(a)
	var tw := a.create_tween()
	tw.tween_method(func(v: float) -> void: a.set_instance_shader_parameter("fade", v), 0.0, 1.0, 0.4).set_delay(0.1)
	tw.parallel().tween_property(a, "position:y", y1, 2.2).set_delay(0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(a, "scale", Vector3.ONE, 0.6).set_delay(0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(func(v: float) -> void: a.set_instance_shader_parameter("fade", v), 1.0, 0.0, 0.8).set_delay(1.5)
	tw.tween_callback(a.queue_free)
	# deriva de lado, devagar, como fumaça
	var drift := a.create_tween().set_loops(3)
	drift.tween_property(a, "position:x", 0.12, 0.4).set_trans(Tween.TRANS_SINE)
	drift.tween_property(a, "position:x", -0.12, 0.4).set_trans(Tween.TRANS_SINE)
	var sp := AngelSparkle.new()
	sp.wing = q.size.x * 0.5
	sp.life = 2.2
	a.add_child(sp)
	var flap := a.create_tween().set_loops(6)
	flap.tween_property(a, "scale:x", 0.88, 0.18).set_trans(Tween.TRANS_SINE)
	flap.tween_property(a, "scale:x", 1.04, 0.18).set_trans(Tween.TRANS_SINE)


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
		_emit = 0.04
		var k := _t / LevelUpFX.SPIRAL_TIME
		var h := top * (1.0 - pow(1.0 - k, 1.6))
		var r := lerpf(1.0, 0.45, k)
		var base := global_position
		for strand in 2:
			var a := _t * 9.0 + PI * strand
			var p := base + Vector3(cos(a) * r, h, sin(a) * r)
			HolyFX.star(p, HolyFX.PAL_GOLD, randf_range(0.13, 0.2) * (1.0 - 0.4 * k),
				{"hold": 0.12, "fade": 0.3, "rise": Vector3.UP * 0.6})


## Brilhos saindo do anjo enquanto ele sobe: estrelinhas de 4 pontas nas pontas das asas e em volta do
## corpo, que ficam para trás e caem devagar (rastro de luz), e de vez em quando um brilho maior.
class AngelSparkle extends Node3D:
	var wing := 1.0
	var life := 2.0
	var _t := 0.0
	var _emit := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if _t >= life:
			queue_free()
			return
		_emit -= delta
		if _emit > 0.0:
			return
		_emit = 0.06
		var base := global_position
		var s := (get_parent() as Node3D).scale.x if get_parent() is Node3D else 1.0
		for i in 2:
			var side := -1.0 if randf() < 0.5 else 1.0
			var off := Vector3(side * wing * s * randf_range(0.3, 0.95), randf_range(-0.3, 0.4), 0.0)
			HolyFX.star(base + off, HolyFX.PAL_GOLD, randf_range(0.1, 0.2),
				{"hold": randf_range(0.1, 0.25), "fade": 0.35, "rise": Vector3(randf_range(-0.2, 0.2), -0.5, 0.0)})
		if randf() < 0.25:
			HolyFX.star(base + Vector3(randf_range(-0.3, 0.3), randf_range(0.0, 0.5), 0.0), HolyFX.PAL_GOLD, 0.38,
				{"points": 4, "sharp": 6.0, "hold": 0.05, "fade": 0.2})
