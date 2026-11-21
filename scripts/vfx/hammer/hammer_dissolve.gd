class_name HammerDissolve
extends Node3D
## Martelo de Energia: o martelo virando partículas de energia (prefab scenes/vfx/hammer/hammer_dissolve.tscn).
## Acompanha a frente da dissolução do EnergyHammer (de baixo para cima: a cabeça primeiro, depois o cabo): o
## emissor fica na altura da frente, largo na cabeça e fino no cabo, e as partículas sobem girando devagar, com o
## brilho da sprite sheet (quadros 57-60, a nuvem de faíscas) indo junto. `follow` liga ao martelo; `stop` para
## de emitir e o nó se libera quando a última partícula some.

@onready var motes: CPUParticles3D = $Motes
@onready var sparkle: HammerSheet = $Sparkle

var hammer: EnergyHammer
var _stopping := false
var _left := 0.0


func _ready() -> void:
	(motes.mesh as QuadMesh).material = FXEpic._particle_mat(FXEpic._glow_tex(), true, true)
	sparkle.set_param("recolor", 0.55)
	sparkle.play(HammerSheet.SPARKLE, 0.5, true)
	sparkle.intensity = 0.0


func follow(h: EnergyHammer) -> void:
	hammer = h
	motes.emitting = true


## Frente da dissolução agora (mundo, y): o emissor vai junto.
func set_front(world_y: float) -> void:
	if not is_instance_valid(hammer):
		return
	var head_top := hammer.bottom_y() + 1.2 * hammer.length / EnergyHammer.BASE_LENGTH
	var on_head := world_y < head_top
	var w := hammer.head_width() * 0.5 if on_head else 0.14 * hammer.length / EnergyHammer.BASE_LENGTH
	var d := 0.5 * hammer.length / EnergyHammer.BASE_LENGTH if on_head else w
	motes.emission_box_extents = Vector3(w, 0.08, d)
	global_position = Vector3(hammer.global_position.x, clampf(world_y, hammer.bottom_y(), hammer.top_y()), hammer.global_position.z)
	sparkle.intensity = 0.9 if on_head else 0.55
	sparkle.scale = Vector3.ONE * (2.6 if on_head else 1.4) * hammer.length / EnergyHammer.BASE_LENGTH


func stop() -> void:
	if _stopping:
		return
	_stopping = true
	motes.emitting = false
	sparkle.fade_out(0.3)
	_left = motes.lifetime + 0.1


func _process(delta: float) -> void:
	if _stopping:
		_left -= delta
		if _left <= 0.0:
			queue_free()
