class_name HammerSheet
extends MeshInstance3D
## Martelo de Energia: um trecho da sprite sheet tocado num quad (prefabs scenes/vfx/hammer/hammer_sheet_*.tscn:
## billboard, deitado, de pé, ou deitado com os detalhes escuros).
## A sheet (assets/vfx/hammer/hammer_sheet.webp) tem 8 colunas x 8 linhas de 128 px, fundo preto puro, lidas da
## esquerda para a direita e de cima para baixo. Cada efeito usa só os seus quadros (constantes abaixo):
##   0-1    vazios
##   2-9    círculo mágico se materializando, visto de cima (anel, hexagrama, runas)   -> CIRCLE_FORM / CIRCLE_HOLD
##   10-17  o mesmo círculo inclinando em perspectiva (a inclinação aqui é 3D: não usados)
##   18-26  martelo saindo do círculo, desenhado (o martelo é 3D: não usados)
##   27-32  o círculo apagando com um feixe de energia subindo                          -> BEAM (energia e rastro)
##   33-47  impacto com o martelo desenhado no meio (não usados: o martelo é 3D)
##   48-50  explosão em estrela, sem martelo                                           -> BURST
##   51-54  chão rachado com as rachaduras acesas (51 ainda é quase só o clarão)       -> CRACKS = 52-54 (crateras)
##   55-63  martelo desenhado se desfazendo em faíscas / vazios; 57-60 são só a nuvem   -> SPARKLE (dissolução)
## O preto some pela mistura aditiva (hammer_sheet.gdshader) ou pela luminância (hammer_sheet_mix.gdshader).

const CIRCLE_FORM := Vector2i(2, 9)
const CIRCLE_HOLD := Vector2i(8, 9)
const BEAM := Vector2i(27, 31)
const BURST := Vector2i(48, 53)
const CRACKS := Vector2i(52, 54)
const SPARKLE := Vector2i(57, 60)
## Recorte do feixe dentro dos quadros 27-32 (x, y, largura, altura): só a coluna de luz, sem o anel de baixo.
const BEAM_CROP := Vector4(0.3, 0.0, 0.4, 0.62)

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


## Mesmo trecho de trás para a frente (o círculo perdendo os detalhes ao fechar).
func play_reverse(frames: Vector2i, duration: float) -> void:
	play(Vector2i(frames.y, frames.x), duration)


func set_param(name: StringName, v: Variant) -> void:
	set_instance_shader_parameter(name, v)


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
