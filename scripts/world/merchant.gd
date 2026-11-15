class_name Merchant
extends SkinnedNPC
## Mira, a Mercadora: parada na barraca, chama quem passa (o jogador local entre CALL_MIN e CALL_MAX metros,
## no máximo um chamado a cada CALL_COOLDOWN s), virada para ele; conversa gesticulando enquanto o diálogo
## dela está aberto e, ao abrir a loja ou fechar o diálogo, volta ao parado. O virar para quem chega a menos
## de 7 m vem do npc.gd.

enum State { IDLE, CALL, TALK }

## Clipes do Mixamo (idle, call, talk), montados por tools/build_npc_mixamo.gd.
const MIXAMO_LIB := "res://assets/animations/merchant_mixamo.res"
const CALL_MIN := 7.0
const CALL_MAX := 14.0
## Intervalo mínimo entre o começo de um chamado e o do próximo (s).
const CALL_COOLDOWN := 8.0
## O call do Mixamo é um aceno só (0,53 s, com fim igual ao começo): cada chamado repete o aceno.
const CALL_WAVES := 3
## Volta do aceno (braço erguido) ao parado.
const CALL_BLEND := 0.4

var state: State = State.IDLE
## Chamados feitos desde que ela nasceu.
var calls := 0
var _cooldown := 0.0
var _waves_left := 0


func _init() -> void:
	npc_id = "merchant"


func library_path() -> String:
	return MIXAMO_LIB


func _ready() -> void:
	super._ready()   # anim, skeleton, biblioteca "mixamo" e _animate (headless sem --smoketest: parado)
	if not _animate:
		return
	anim.animation_finished.connect(_on_anim_finished)
	_idle()


## interact() (SkinnedNPC) abriu o diálogo: conversa, animando com o jogo pausado.
func _on_dialogue_opened() -> void:
	if not _animate:
		return
	state = State.TALK
	_play("talk")


func _process(delta: float) -> void:
	var yaw := model.rotation.y
	if not get_tree().paused:
		super._process(delta)   # virar aos poucos (para o jogador a menos de 7 m ou de volta à barraca)
		_cooldown -= delta
	var player := get_tree().get_first_node_in_group("player") as Node3D
	match state:
		State.TALK:
			if not dialogue_open():
				_end_dialogue()   # loja aberta (pausa o jogo) ou diálogo fechado
				_idle()
		State.CALL:
			if player:   # chamando, ela se vira para ele também entre 7 e 14 m
				var to := player.global_position - global_position
				model.rotation.y = lerp_angle(yaw, atan2(to.x, to.z) - global_rotation.y, 4.0 * delta)
		State.IDLE:
			if player and _cooldown <= 0.0 and not get_tree().paused:
				var d := player.global_position.distance_to(global_position)
				if d >= CALL_MIN and d <= CALL_MAX:
					_call()


## Volta ao parado com o chamado liberado: chama de novo assim que o jogador estiver entre CALL_MIN e
## CALL_MAX metros, sem esperar o intervalo (testes e quem reposiciona a Mira).
func reset_call() -> void:
	_cooldown = 0.0
	_waves_left = 0
	if _animate:
		_idle()
	else:
		state = State.IDLE


func _call() -> void:
	state = State.CALL
	calls += 1
	_cooldown = CALL_COOLDOWN
	_waves_left = CALL_WAVES - 1
	_play("call")


func _idle(blend := BLEND) -> void:
	state = State.IDLE
	_play("idle", blend)


func _on_anim_finished(anim_name: StringName) -> void:
	if state != State.CALL or String(anim_name) != clip("call"):
		return
	if _waves_left > 0:
		_waves_left -= 1
		anim.play(clip("call"), 0.0)
		anim.seek(0.0, true)
	else:
		_idle(CALL_BLEND)
