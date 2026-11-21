class_name AegisFlipbook
extends MeshInstance3D
## Égide Cristalina: a sprite sheet de referência tocada num billboard (prefab scenes/vfx/aegis/aegis_flipbook.tscn).
## A sheet (assets/vfx/aegis/aegis_sheet.webp) é uma grade de 8 colunas x 8 linhas, quadros iguais de 128 px,
## lidos da esquerda para a direita e de cima para baixo:
##   0-14   círculo mágico se formando (anel, hexagrama, emblema)   32-35  coroa cheia
##   15-20  primeiras placas em losango                            36-47  rachando e partindo
##   21-31  a coroa de losangos fechando                           48-59  estilhaços se dissipando
## As placas (quadros 15 e 42) viram texturas das peças 3D (tools/aegis_sheet_extract.gd); aqui o
## billboard toca a quebra, que é a parte que a malha não reproduz quadro a quadro.
## O fundo preto some com o blend aditivo do shader (aegis_flipbook), sem cortar os brilhos.

const FORM := Vector2i(21, 31)    ## a coroa fechando
const HOLD := Vector2i(32, 35)    ## coroa cheia (vai e volta devagar)
const DAMAGED := Vector2i(36, 43) ## rachando (pela integridade)
const BREAK := Vector2i(44, 59)   ## partindo, estilhaços e dissipação

var intensity := 1.0
var _from := 0.0
var _to := 0.0
var _dur := 1.0
var _t := 0.0
var _loop := false
var _fade := 1.0
var _fade_speed := 0.0


## Toca os quadros `frames.x`..`frames.y` em `duration` s; `loop` = vai e volta sem parar.
func play(frames: Vector2i, duration: float, loop := false) -> void:
	_from = float(frames.x)
	_to = float(frames.y)
	_dur = maxf(duration, 0.01)
	_t = 0.0
	_loop = loop
	_apply()


func fade_out(time: float) -> void:
	_fade_speed = 1.0 / maxf(time, 0.01)


func current_frame() -> float:
	var u := _t / _dur
	if _loop:
		u = 1.0 - absf(fmod(u, 2.0) - 1.0)
	return lerpf(_from, _to, clampf(u, 0.0, 1.0))


func done() -> bool:
	return not _loop and _t >= _dur


func _process(delta: float) -> void:
	_t += delta
	if _fade_speed > 0.0:
		_fade = maxf(0.0, _fade - _fade_speed * delta)
	_apply()


func _apply() -> void:
	set_instance_shader_parameter("frame", current_frame())
	set_instance_shader_parameter("intensity", intensity * _fade)
	visible = intensity * _fade > 0.001
