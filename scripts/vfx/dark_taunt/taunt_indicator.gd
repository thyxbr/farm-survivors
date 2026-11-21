class_name TauntIndicator
extends MeshInstance3D
## Olhos da provocação (prefab scenes/vfx/dark_taunt/taunt_indicator.tscn): dois olhos vermelhos pequenos, inclinados
## e com raiva, acima da cabeça do inimigo provocado (Círculo da Provocação Sombria). Cada inimigo tem o seu (filho
## dele, criado por Enemy._set_taunt_look na primeira provocação e reaproveitado nas seguintes).
## Quadros de assets/vfx/dark_taunt/taunt_eyes.png (8 x 8, fundo já tirado por tools/taunt_sheet_bake.gd):
##   1-8    os olhos se abrindo, ainda fracos                                -> APPEAR
##   18-27  brilho subindo e descendo (o olhar aceso)                          -> GLARE (vai e volta enquanto dura)
##   44-60  um último clarão e o apagar até sumir                              -> FADE
## Billboard (taunt_eyes.gdshader): sempre de frente para a câmera. Segue a cabeça (o nó "Head" do modelo, quando
## existe, ou o topo do corpo), na altura DarkTauntConfig.eye_height, com tamanho DarkTauntConfig.eye_size
## proporcional ao inimigo. `top_level`: o giro do modelo não o carrega.

const CONFIG := preload("res://assets/vfx/dark_taunt/dark_taunt_config.tres")
const APPEAR := Vector2i(1, 8)
const GLARE := Vector2i(18, 27)
const FADE := Vector2i(44, 60)
const APPEAR_TIME := 0.35
const GLARE_TIME := 1.1
## A faixa recortada do quadro (taunt_eyes_mat: crop 0,8 x 0,4) mostra o par com ~0,78 da largura.
const PAIR_WIDTH := 0.78

enum State { HIDDEN, APPEAR, GLARE, FADE }

var state := State.HIDDEN
var active := false            ## olhos ligados (lido por Enemy._set_taunt_look)
var enemy: Node3D
var _head: Node3D
var _head_rest := 0.0
var _t := 0.0
var _fade_time := 0.6
var _base_scale := Vector3.ONE


func _ready() -> void:
	top_level = true
	visible = false


## Prende ao inimigo `e` (tamanho e cabeça dele).
func attach(e: Node3D) -> void:
	enemy = e
	var parts = e.get("parts")
	_head = parts.get("Head") if parts is Dictionary else null
	if _head != null and not is_instance_valid(_head):
		_head = null
	if _head != null:
		_head_rest = _head.global_position.y - e.global_position.y
	var top := _top()
	var k := clampf(top / 1.6, 0.7, 2.0)
	var w := CONFIG.eye_size * k / PAIR_WIDTH
	_base_scale = Vector3(w, w * 0.5, 1.0)
	scale = _base_scale
	_follow()


func show_eyes() -> void:
	if active and state != State.FADE:
		return
	active = true
	state = State.APPEAR
	_t = 0.0
	visible = true
	_follow()
	_apply(float(APPEAR.x), 0.0)


func hide_eyes() -> void:
	if not active:
		return
	active = false
	state = State.FADE
	_t = 0.0
	_fade_time = maxf(CONFIG.eye_fade_time, 0.05)


func _process(delta: float) -> void:
	if state == State.HIDDEN:
		return
	if enemy == null or not is_instance_valid(enemy):
		queue_free()
		return
	_t += delta
	_follow()
	match state:
		State.APPEAR:
			var u := clampf(_t / APPEAR_TIME, 0.0, 1.0)
			_apply(lerpf(APPEAR.x, APPEAR.y, u), u)
			scale = _base_scale * lerpf(0.6, 1.0, 1.0 - pow(1.0 - u, 3.0))
			if u >= 1.0:
				state = State.GLARE
				_t = 0.0
		State.GLARE:
			var u := fmod(_t / GLARE_TIME, 2.0)
			u = 1.0 - absf(u - 1.0)
			_apply(lerpf(GLARE.x, GLARE.y, u), 1.0)
			scale = _base_scale * (1.0 + 0.06 * u)   # pulsa de raiva
		State.FADE:
			var u := clampf(_t / _fade_time, 0.0, 1.0)
			_apply(lerpf(FADE.x, FADE.y, u), 1.0 - u * u)
			if u >= 1.0:
				state = State.HIDDEN
				visible = false


func _top() -> float:
	if enemy != null and enemy.has_method("head_top"):
		return float(enemy.head_top())
	return 1.6


## Em cima da cabeça: x/z da cabeça (balanço do modelo) e a altura do topo mais o quanto a cabeça subiu/desceu.
func _follow() -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var base := enemy.global_position
	var bob := 0.0
	if _head != null and is_instance_valid(_head):
		var hp := _head.global_position
		base = Vector3(hp.x, base.y, hp.z)
		bob = (hp.y - enemy.global_position.y) - _head_rest
	global_position = base + Vector3.UP * (_top() + CONFIG.eye_height * clampf(_top() / 1.6, 0.7, 2.0) + bob)


func _apply(frame: float, intensity: float) -> void:
	set_instance_shader_parameter("frame", frame)
	set_instance_shader_parameter("intensity", intensity)
