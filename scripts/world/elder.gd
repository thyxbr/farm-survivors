class_name Elder
extends SkinnedNPC
## Ancião Bram: parado, apoiado no cajado (preso à mão esquerda). Quando o jogador fala com ele, o diálogo
## abre na hora e ele se anima (excited) por cima da primeira página; depois conversa (talk) até o diálogo
## fechar, e volta ao parado. O marcador !/? e o virar para quem chega perto vêm do npc.gd.

enum State { IDLE, EXCITED, TALK }

## Clipes do Mixamo (idle, excited, talk), montados por tools/build_npc_mixamo.gd com o braço esquerdo
## assado no cajado fincado.
const MIXAMO_LIB := "res://assets/animations/elder_mixamo.res"
## O excited do Mixamo tem 6,6 s: a reação é cortada e emenda na conversa depois disto (ou no fim do clipe).
const EXCITED_MAX := 3.0
## Emenda reação -> conversa: o excited cortado no meio está longe da pose do talk.
const TALK_BLEND := 0.5

var state: State = State.IDLE
var _excited_t := 0.0


func _init() -> void:
	npc_id = "elder"


func library_path() -> String:
	return MIXAMO_LIB


func _ready() -> void:
	super._ready()   # anim, skeleton, biblioteca "mixamo" e _animate (headless sem --smoketest: parado)
	attach_to_bone("Staff", "LeftHand")
	if _animate:
		_idle()


## interact() (SkinnedNPC) abriu o diálogo: a reação, animando com o jogo pausado.
func _on_dialogue_opened() -> void:
	if not _animate:
		return
	state = State.EXCITED
	_excited_t = 0.0
	_play("excited")


func _process(delta: float) -> void:
	if not get_tree().paused:
		super._process(delta)   # marcador e virar aos poucos
	match state:
		State.EXCITED:
			_excited_t += delta
			if not dialogue_open():
				_end_dialogue()
				_idle()
			elif _excited_t >= minf(EXCITED_MAX, anim.get_animation(clip("excited")).length):
				state = State.TALK
				_play("talk", TALK_BLEND)
		State.TALK:
			if not dialogue_open():
				_end_dialogue()
				_idle()


func _idle() -> void:
	state = State.IDLE
	_play("idle")
