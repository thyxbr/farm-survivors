class_name DarkSheet
extends MeshInstance3D
## Círculo da Provocação Sombria: um trecho da sprite sheet tocado num quad (prefabs scenes/vfx/dark_taunt/
## dark_sheet_*.tscn: deitado e aditivo, para o que é luz; de pé e com os escuros preservados, para mãos e fumaça).
## A sheet (assets/vfx/dark_taunt/dark_taunt_sheet.webp) tem 8 colunas x 8 linhas de 128 px (64 quadros, não 6 x 6),
## fundo preto, lida da esquerda para a direita e de cima para baixo. Medida por tools/taunt_sheet_bake.gd:
##   0        vazio
##   1-7      o círculo se desenhando (elipse em perspectiva, crescendo do miolo)        -> CIRCLE_FORM
##   8-10     círculo inteiro, runas e energia, sem mãos                                -> CIRCLE_HOLD
##   11-23    mãos saindo do círculo (uma, depois duas, subindo)                          -> HANDS_RISE
##   24-35    mãos erguidas, dedos abrindo e fechando (agarrando)                         -> HANDS_GRAB
##   36-47    as mãos se desfazendo em fumaça, o círculo apagando                         -> HANDS_FADE
##   48-56    só fumaça sobre o círculo quase apagado                                     -> SMOKE
##   57-63    vazios
## O círculo da sheet está em perspectiva (elipse com altura 0,68 da largura): deitado no chão, o quad estica na
## profundidade pelo inverso (CIRCLE_ASPECT) para virar um círculo visto de cima. As mãos da sheet não são as que
## agarram (essas são 3D, ShadowHand): aqui elas formam a coluna de energia no centro (DarkTauntVFX.plume), recortada
## acima do círculo desenhado (PLUME_CROP). A fumaça dos quadros 48-56 envolve os inimigos agarrados (SMOKE_CROP).

const CIRCLE_FORM := Vector2i(1, 7)
const CIRCLE_HOLD := Vector2i(8, 10)
const HANDS_RISE := Vector2i(11, 23)
const HANDS_GRAB := Vector2i(24, 35)
const HANDS_FADE := Vector2i(36, 47)
const SMOKE := Vector2i(48, 56)
## Elipse do círculo nos quadros 1-10: altura / largura, centro (u, v) e largura (fração do quadro).
const CIRCLE_ASPECT := 0.68
const CIRCLE_CENTER := Vector2(0.496, 0.575)
const CIRCLE_WIDTH := 0.95
## Recortes (x, y, largura, altura): as mãos acima do círculo; a fumaça na metade de baixo.
const PLUME_CROP := Vector4(0.06, 0.0, 0.88, 0.6)
const SMOKE_CROP := Vector4(0.0, 0.3, 1.0, 0.7)

var intensity := 1.0:
	set(v):
		intensity = v
		_apply()
var _from := 0.0
var _to := 0.0
var _dur := 1.0
var _t := 0.0
var _loop := false
var _fade := 1.0
var _fade_speed := 0.0
var _free_when_done := false


## Toca os quadros `frames.x`..`frames.y` em `duration` s; `loop` = vai e volta sem parar.
func play(frames: Vector2i, duration: float, loop := false) -> void:
	_from = float(frames.x)
	_to = float(frames.y)
	_dur = maxf(duration, 0.01)
	_t = 0.0
	_loop = loop
	_fade = 1.0
	_fade_speed = 0.0
	_apply()


func set_param(param: StringName, v: Variant) -> void:
	set_instance_shader_parameter(param, v)


## Deitado no chão, um círculo de raio `r` (m) com o desenho da sheet sem a perspectiva.
func fit_circle(r: float) -> void:
	var w := 2.0 * r / CIRCLE_WIDTH
	var d := 2.0 * r / (CIRCLE_WIDTH * CIRCLE_ASPECT)
	var rot := basis.orthonormalized()
	scale = Vector3(w, d, 1.0)   # o quad deitado: x = largura, y (do quad) = profundidade
	# o centro da elipse não é o do quadro: desloca (no plano do quad) para ele cair no centro do nó
	var h := position.y
	position = rot * Vector3((0.5 - CIRCLE_CENTER.x) * w, (CIRCLE_CENTER.y - 0.5) * d, 0.0)
	position.y = h


## Some em `time` s; com `free` o nó se libera quando apagar.
func fade_out(time: float, free := false) -> void:
	_fade_speed = 1.0 / maxf(time, 0.01)
	_free_when_done = free


func current_frame() -> float:
	var u := _t / _dur
	if _loop:
		u = 1.0 - absf(fmod(u, 2.0) - 1.0)
	return lerpf(_from, _to, clampf(u, 0.0, 1.0))


func done() -> bool:
	return not _loop and _t >= _dur


func faded() -> bool:
	return _fade <= 0.001


func _process(delta: float) -> void:
	_t += delta
	if _fade_speed > 0.0:
		_fade = maxf(0.0, _fade - _fade_speed * delta)
		if _fade <= 0.0 and _free_when_done:
			queue_free()
	_apply()


func _apply() -> void:
	set_instance_shader_parameter("frame", current_frame())
	set_instance_shader_parameter("intensity", intensity * _fade)
	visible = intensity * _fade > 0.001
