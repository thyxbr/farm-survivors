class_name EarthquakeSheet
extends MeshInstance3D
## Terremoto Devastador: um trecho da sprite sheet tocado num billboard aditivo (prefab
## scenes/vfx/earthquake/earthquake_sheet.tscn, shader shaders/earthquake/eq_sheet.gdshader).
## A sheet (assets/vfx/earthquake/earthquake_sheet.webp) tem 8 colunas x 8 linhas de 128 px, fundo preto puro, lidas
## da esquerda para a direita e de cima para baixo. Analisada quadro a quadro, cada efeito usa só o seu trecho:
##   0-4    ponto de luz crescendo até um anel pequeno com faíscas          -> CHARGE (energia acumulada no chão)
##   4-12   o clarão abre em estrela e vira o anel de energia no chão        -> BURST (explosão inicial)
##   12-31  anel aceso no chão rachado, placas subindo, fumaça começando     -> WAVE (centro da onda de choque)
##   32-41  pedras e placas sendo arremessadas, fumaça densa (quadro cheio)  -> DEBRIS (explosões secundárias)
##   42-47  só os raios das rachaduras, se apagando                          -> LIGHTNING (rachaduras luminosas)
##   48-62  fissuras escuras e a poeira assentando até sumir                 -> DUST (poeira e dissipação)
##   63     vazio
## O preto some pela mistura aditiva; a borda dos quadros cheios (linhas 4-7) some pela máscara radial do shader.

const CHARGE := Vector2i(0, 4)
const BURST := Vector2i(4, 12)
const WAVE := Vector2i(12, 31)
const DEBRIS := Vector2i(32, 41)
const LIGHTNING := Vector2i(42, 47)
const DUST := Vector2i(48, 62)
## Onde fica o ponto do impacto dentro do quadro (0 = topo, 1 = base): o anel desenhado está um pouco abaixo do meio.
const GROUND_V := 0.6

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


## Toca os quadros `frames.x`..`frames.y` em `duration` s; `loop` = vai e volta sem parar; `free` = se libera no fim.
func play(frames: Vector2i, duration: float, loop := false, free := false) -> void:
	_from = float(frames.x)
	_to = float(frames.y)
	_dur = maxf(duration, 0.01)
	_t = 0.0
	_loop = loop
	_fade = 1.0
	_fade_speed = 0.0
	_free_when_done = free
	_apply()


## Põe o billboard em pé sobre `ground_point` (local do pai) com `size` m de lado: o ponto desenhado do impacto
## (GROUND_V) fica sobre o ponto de verdade.
func place(ground_point: Vector3, size: float) -> void:
	scale = Vector3.ONE * size
	position = ground_point + Vector3(0.0, (GROUND_V - 0.5) * size, 0.0)


## Some em `time` s; com `free` o nó se libera quando apagar.
func fade_out(time: float, free := true) -> void:
	_fade_speed = 1.0 / maxf(time, 0.01)
	_free_when_done = free


func done() -> bool:
	return not _loop and _t >= _dur


func current_frame() -> float:
	var u := _t / _dur
	if _loop:
		u = 1.0 - absf(fmod(u, 2.0) - 1.0)
	return lerpf(_from, _to, clampf(u, 0.0, 1.0))


func _process(delta: float) -> void:
	_t += delta
	if _fade_speed > 0.0:
		_fade = maxf(0.0, _fade - _fade_speed * delta)
	_apply()
	if _free_when_done and (_fade <= 0.0 or (done() and _fade_speed <= 0.0)):
		queue_free()


func _apply() -> void:
	set_instance_shader_parameter("frame", current_frame())
	set_instance_shader_parameter("intensity", intensity * _fade)
	visible = intensity * _fade > 0.001
