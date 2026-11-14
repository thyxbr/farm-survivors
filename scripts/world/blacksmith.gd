class_name Blacksmith
extends SkinnedNPC
## Doran, o ferreiro: martela na bigorna (com pausas de vez em quando), para e se vira quando o
## jogador chega e gesticula enquanto conversa. Cada golpe solta faíscas e o som da bigorna,
## sincronizados com a animação por uma method track injetada nos clipes em _ready.

enum State { WORK, PAUSE, IDLE, TALK }

const NEAR := 7.0     # mesmo raio em que o npc.gd vira para o jogador
## Entrada e saída da pausa: o work_pause (Mixamo) começa e termina numa base aberta e com o corpo virado,
## longe da pose do martelar provisório; em 0,25 s as pernas cruzavam e o pé escorregava.
const PAUSE_BLEND := 0.5
## Clipes em que o martelo bate na bigorna (nome base, antes de clip()).
const STRIKE_CLIPS := ["work_hammer"]
## Tempo (s) do impacto em cada clipe, pelo nome resolvido por clip(): work_hammer provisório = quadro 13
## de 36 a 30 fps. O Mixamo não tinha martelar; se um dia entrar, vem com a própria chave ("mixamo/work_hammer").
const STRIKES := {"work_hammer": [0.433]}
## Clipes do Mixamo (parado, conversa e pausa), montados por tools/build_npc_mixamo.gd. Entram como
## a biblioteca "mixamo" do AnimationPlayer e têm prioridade sobre os provisórios do .glb (ver clip()).
const MIXAMO_LIB := "res://assets/animations/blacksmith_mixamo.res"
const SPARK_COLOR := Color(1.0, 0.72, 0.25)
## Ferraria em coordenadas do ferreiro (frente = +Z): bigorna à frente, de lado (chifre à esquerda dele) e
## puxada para a direita, com o StrikePoint embaixo da face do martelo na batida; forja às costas com a boca
## virada para ele. Usado pelo mundo, por tools/blacksmith_shot.gd (que confere o golpe) e, nas coordenadas do
## Blender, por BS_BAR_*/BS_STRIKE em tools/blender/characters.py (barra, tenaz e alvo do martelo).
const ANVIL_OFFSET := Vector3(-0.18, 0, 0.6)
const ANVIL_YAW := PI / 2
const FORGE_OFFSET := Vector3(0, 0, -1.6)
const FORGE_YAW := 0.0

var state: State = State.WORK
var strikes := 0
## Golpes de encantamento dados (um por arma encantada no painel).
var enchant_strikes := 0
var anvil: Node3D          # criado pelo mundo e atribuído antes do add_child
var _sparks: CPUParticles3D
var _strike_point: Node3D
var _cycles_left := 0
var _last_pos := 0.0


func _init() -> void:
	npc_id = "blacksmith"


func library_path() -> String:
	return MIXAMO_LIB


func _ready() -> void:
	super._ready()   # anim, skeleton, biblioteca "mixamo" e _animate (headless sem --smoketest: parado)
	anim.animation_finished.connect(_on_anim_finished)
	# o martelo e a tenaz vêm como malhas soltas com o pivô no punho (pose T)
	attach_to_bone("Hammer", "RightHand")
	attach_to_bone("Tongs", "LeftHand")
	if anvil:
		_strike_point = anvil.find_child("StrikePoint", true, false)
	if not _animate:
		return
	# os clipes provisórios idle/talk/work_pause só animam tronco, braços e cabeça (o work_hammer anima também
	# quadril e pernas, e aí as tracks dele já existem e ficam como estão)
	_add_rest_tracks(anim.get_animation_library("").get_animation_list())
	_add_strike_tracks()
	if DisplayServer.get_name() != "headless":
		_sparks = FX.burst_particles(SPARK_COLOR, 20, 3.5, 0.035, 0.35, -9.0)
		_sparks.spread = 70.0
		add_child(_sparks)
		_sparks.global_position = strike_pos()
	_work()


## Onde o martelo bate na bigorna (coordenadas globais).
func strike_pos() -> Vector3:
	if _strike_point:
		return _strike_point.global_position
	return global_position + model.global_basis.z * 0.7 + Vector3.UP * 0.8


## interact() (SkinnedNPC) abriu o diálogo: o ferreiro conversa, animando com o jogo pausado.
func _on_dialogue_opened() -> void:
	state = State.TALK
	_play("talk")


func _process(delta: float) -> void:
	if not get_tree().paused:
		super._process(delta)   # marcador e virar aos poucos (para o jogador ou de volta à bigorna)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var near := player != null and player.global_position.distance_to(global_position) < NEAR
	match state:
		State.TALK:
			if not dialogue_open():
				_end_dialogue()
				if near:
					_idle()
				else:
					_work()
		State.IDLE:
			if not near:
				_work()
		_:
			if near:
				_idle()
			elif state == State.WORK:
				_count_cycle()


## Um golpe na bigorna para selar um encanto: som do martelo e faíscas na cor do elemento.
## No servidor dedicado (sem animação) só conta.
func enchant_strike(color: Color) -> void:
	enchant_strikes += 1
	if not _animate:
		return
	Sfx.play_at("anvil", strike_pos())
	FX.burst(strike_pos(), color, 36, 4.5, 0.045, 0.6, -6.0)
	FX.ring(strike_pos() - Vector3(0, 0.1, 0), Color(color.r, color.g, color.b, 0.9), 1.2, 0.5)


func _on_strike() -> void:
	# a method track do work_hammer ainda dispara durante o blend de saída (BLEND): fora do WORK não bate
	# get_tree().paused: segurança extra, a bigorna nunca toca com o jogo pausado
	if not _animate or state != State.WORK or get_tree().paused:
		return
	strikes += 1
	Sfx.play_at("anvil", strike_pos())
	if _sparks:
		_sparks.restart()


# ---------------------------------------------------------------- estados
func _work(blend := BLEND) -> void:
	state = State.WORK
	_cycles_left = randi_range(3, 5)
	_last_pos = 0.0
	_play("work_hammer", blend)


func _idle() -> void:
	state = State.IDLE
	_play("idle")


## Conta as voltas do martelar (a posição do clipe em loop volta para o início); depois de 3 a 5,
## faz a pausa (limpar a testa) e volta a martelar.
func _count_cycle() -> void:
	var pos := anim.current_animation_position
	if pos < _last_pos:
		_cycles_left -= 1
		if _cycles_left <= 0:
			state = State.PAUSE
			_play("work_pause", PAUSE_BLEND)
	_last_pos = pos


func _on_anim_finished(anim_name: StringName) -> void:
	if state == State.PAUSE and String(anim_name) == clip("work_pause"):
		_work(PAUSE_BLEND)


# ---------------------------------------------------------------- montagem
## Injeta no clipe que vai tocar (clip(): o provisório ou o do Mixamo) uma method track que chama
## _on_strike no instante do impacto. Os clipes são recursos compartilhados do .glb: se outro ferreiro
## já injetou, a track está lá e é reaproveitada.
func _add_strike_tracks() -> void:
	var path := anim.get_node(anim.root_node).get_path_to(self)
	for base: String in STRIKE_CLIPS:
		var clip_name := clip(base)
		if not anim.has_animation(clip_name):
			continue
		if not STRIKES.has(clip_name):
			push_warning("Ferreiro: sem tempo de golpe em STRIKES para o clipe %s" % clip_name)
			continue
		var a := anim.get_animation(clip_name)
		if a.find_track(path, Animation.TYPE_METHOD) >= 0:
			continue
		var t := a.add_track(Animation.TYPE_METHOD)
		a.track_set_path(t, path)
		for time: float in STRIKES[clip_name]:
			a.track_insert_key(t, time, {"method": &"_on_strike", "args": []})
