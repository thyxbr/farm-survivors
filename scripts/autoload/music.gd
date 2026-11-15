extends Node
## Música de fundo e som ambiente. A cada POLL segundos monta um retrato do momento (cena, fase da
## cidade, horda, chefe por perto, jogador caído, posição) e pede a MusicRules a faixa e o ambiente;
## quando muda, troca com crossfade. Faixas com vários arquivos tocam em playlist; as de um arquivo
## ficam em loop. Arquivos e licenças em assets/audio/CREDITS.md.

const MUSIC_DIR := "res://assets/audio/music/%s.ogg"
const AMBIENCE_DIR := "res://assets/audio/ambience/%s.ogg"
const POLL := 0.5
const FADE := 1.6
const SILENT_DB := -40.0
## Ambiente fica um pouco abaixo da música e dos efeitos.
const AMBIENCE_DB := -4.0
## Chefe entra na conta a BOSS_ENTER m do jogador e só sai a BOSS_LEAVE m (sem ficar trocando na borda).
const BOSS_ENTER := 40.0
const BOSS_LEAVE := 60.0
const SCENES := {
	"res://scenes/main_menu.tscn": "menu",
	"res://scenes/world.tscn": "world",
}

var current := ""            # id da faixa (MusicRules.TRACKS) tocando agora
var current_ambience := ""   # id do ambiente (MusicRules.AMBIENCES)
var enabled := true
var _music: Array[AudioStreamPlayer] = []
var _amb: Array[AudioStreamPlayer] = []
var _active := 0
var _amb_active := 0
var _playlist: Array = []
var _index := 0
var _t := 0.0
var _boss_near := false
var _cache := {}
var _tweens := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# servidor dedicado não tem som: não carrega nem varre nada
	enabled = not ("--server" in OS.get_cmdline_user_args())
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = &"Music"
		m.volume_db = SILENT_DB
		m.finished.connect(_on_finished.bind(m))
		add_child(m)
		_music.append(m)
		var a := AudioStreamPlayer.new()
		a.bus = &"Ambience"
		a.volume_db = SILENT_DB
		add_child(a)
		_amb.append(a)


## Saindo do jogo: mata os fades em curso (o player que ainda toca é liberado normalmente).
func _exit_tree() -> void:
	for tw in _tweens.values():
		if tw != null and tw.is_valid():
			tw.kill()
	_tweens.clear()


func _process(delta: float) -> void:
	if not enabled:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = POLL
	var ctx := context()
	var want := MusicRules.track(ctx)
	if want != current:
		play(want)
	var amb := MusicRules.ambience(ctx)
	if amb != current_ambience:
		play_ambience(amb)


## Retrato do momento para MusicRules.
func context() -> Dictionary:
	var root := get_tree().current_scene
	if root == null:
		return {}
	var ctx := {"scene": SCENES.get(root.scene_file_path, "")}
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null and player.is_inside_tree():
		ctx.pos = player.global_position
		ctx.dead = bool(player.get("dead"))
		_boss_near = _boss_in_range(player.global_position, BOSS_LEAVE if _boss_near else BOSS_ENTER)
	else:
		_boss_near = false
	ctx.boss_near = _boss_near
	if ctx.scene == "world":
		ctx.horde = root.get("survival") != null
	return ctx


func _boss_in_range(from: Vector3, radius: float) -> bool:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Enemy and e.is_boss and not e.dead and e.global_position.distance_to(from) <= radius:
			return true
	return false


## Troca para a faixa `id` (MusicRules.TRACKS) com crossfade; "" silencia.
func play(id: String) -> void:
	current = id
	_playlist = MusicRules.TRACKS.get(id, [])
	_index = randi() % _playlist.size() if _playlist.size() > 1 else 0
	var old := _music[_active]
	_fade(old, SILENT_DB, true)
	if _playlist.is_empty():
		return
	_active = 1 - _active
	var p := _music[_active]
	p.stream = _track_stream(_playlist[_index], _playlist.size() == 1 and not id in MusicRules.ONE_SHOT)
	p.volume_db = SILENT_DB
	p.play()
	_fade(p, 0.0, false)


func play_ambience(id: String) -> void:
	current_ambience = id
	_fade(_amb[_amb_active], SILENT_DB, true)
	if id == "":
		return
	_amb_active = 1 - _amb_active
	var a := _amb[_amb_active]
	a.stream = _load(AMBIENCE_DIR % MusicRules.AMBIENCES[id], true)
	a.volume_db = SILENT_DB
	a.play()
	_fade(a, AMBIENCE_DB, false)


## Fim de faixa numa playlist: segue para a próxima (as de loop nunca terminam).
func _on_finished(p: AudioStreamPlayer) -> void:
	if p != _music[_active] or _playlist.size() < 2:
		return
	_index = (_index + 1) % _playlist.size()
	p.stream = _track_stream(_playlist[_index], false)
	p.play()


func _track_stream(file: String, loop: bool) -> AudioStream:
	return _load(MUSIC_DIR % file, loop)


func _load(path: String, loop: bool) -> AudioStream:
	if not _cache.has(path):
		_cache[path] = load(path)
	var s: AudioStream = _cache[path]
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = loop
	return s


## Um tween por player: trocar de novo no meio do fade cancela o anterior (senão o stop() do fade
## antigo desligaria o player que acabou de voltar a tocar).
func _fade(p: AudioStreamPlayer, to_db: float, stop_after: bool) -> void:
	var prev: Tween = _tweens.get(p)
	if prev != null and prev.is_valid():
		prev.kill()
	var tw := create_tween()
	_tweens[p] = tw
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(p, "volume_db", to_db, FADE).set_trans(Tween.TRANS_SINE)
	if stop_after:
		tw.tween_callback(_release.bind(p))


## Fim do fade de saída: para e solta o stream. Um player parado que ainda segura o stream deixa a
## playback presa no servidor de áudio até o fim do jogo ("resources still in use at exit").
func _release(p: AudioStreamPlayer) -> void:
	p.stop()
	p.stream = null
