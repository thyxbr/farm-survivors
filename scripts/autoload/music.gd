extends Node
## Música de fundo e som ambiente. A cada POLL segundos monta um retrato do momento (cena, fase da
## cidade, horda, chefe por perto, jogador caído, posição) e pede a MusicRules a faixa e o ambiente;
## quando muda, troca com crossfade. Faixas com vários arquivos tocam em playlist; as de um arquivo
## ficam em loop. Arquivos e licenças em assets/audio/CREDITS.md.
##
## Troca de mapa (carruagem, teleporte, porta de dungeon) e de cena não espera o POLL: o mapa do jogador
## é olhado a cada quadro e, quando muda, a música e o ambiente trocam na hora, com fade curto. Os arquivos
## são carregados em segundo plano no início, para o primeiro uso de uma faixa não travar nem atrasar.

const MUSIC_DIR := "res://assets/audio/music/%s.ogg"
const AMBIENCE_DIR := "res://assets/audio/ambience/%s.ogg"
const POLL := 0.5
const FADE := 1.6
## Fade da troca de mapa: a tela já escureceu, a faixa nova entra quase junto com a imagem.
const FADE_FAST := 0.45
const SILENT_DB := -60.0
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
var _level := {}             # player -> volume linear 0..1 do fade (o volume_db sai daqui)
var _pending: Array[String] = []   # arquivos pedidos ao carregador em segundo plano
var _last_scene: Node = null
var _last_region := ""


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
	if enabled:
		_preload_all()


## Pede todos os arquivos de música e ambiente ao carregador em segundo plano.
func _preload_all() -> void:
	var paths: Array[String] = []
	for id in MusicRules.TRACKS:
		for f in MusicRules.TRACKS[id]:
			paths.append(MUSIC_DIR % f)
	for id in MusicRules.AMBIENCES:
		paths.append(AMBIENCE_DIR % MusicRules.AMBIENCES[id])
	for path in paths:
		if path in _pending or not ResourceLoader.exists(path):
			continue
		if ResourceLoader.load_threaded_request(path) == OK:
			_pending.append(path)


## Guarda no cache o que o carregador já terminou (sem esperar o que falta).
func _collect_loaded() -> void:
	for i in range(_pending.size() - 1, -1, -1):
		var path := _pending[i]
		var st := ResourceLoader.load_threaded_get_status(path)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		_pending.remove_at(i)
		if st == ResourceLoader.THREAD_LOAD_LOADED and not _cache.has(path):
			_cache[path] = ResourceLoader.load_threaded_get(path)


## Saindo do jogo: mata os fades em curso (o player que ainda toca é liberado normalmente).
func _exit_tree() -> void:
	for tw in _tweens.values():
		if tw != null and tw.is_valid():
			tw.kill()
	_tweens.clear()


func _process(delta: float) -> void:
	if not enabled:
		return
	if not _pending.is_empty():
		_collect_loaded()
	_t -= delta
	var jumped := _map_changed()
	if _t > 0.0 and not jumped:
		return
	_t = POLL
	refresh(FADE_FAST if jumped else FADE)


## Reavalia agora qual faixa e ambiente devem tocar e troca o que mudou.
func refresh(fade := FADE) -> void:
	var ctx := context()
	var want := MusicRules.track(ctx)
	if want != current:
		play(want, fade)
	var amb := MusicRules.ambience(ctx)
	if amb != current_ambience:
		play_ambience(amb, fade)


## Trocou de cena ou o jogador apareceu noutro mapa desde o último quadro (viagem, porta de dungeon).
## Barato: um get_first_node_in_group e uma conta de região por quadro.
func _map_changed() -> bool:
	var root := get_tree().current_scene
	var region := ""
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null and player.is_inside_tree():
		region = ExpeditionDefs.ambience_at(player.global_position)
	var changed := root != _last_scene or region != _last_region
	_last_scene = root
	_last_region = region
	return changed


## Retrato do momento para MusicRules.
func context() -> Dictionary:
	var root := get_tree().current_scene
	if root == null:
		return {}
	var ctx := {"scene": SCENES.get(root.scene_file_path, "")}
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null and player.is_inside_tree():
		ctx.pos = player.global_position
		ctx.region = ExpeditionDefs.ambience_at(player.global_position)
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
func play(id: String, fade := FADE) -> void:
	current = id
	_playlist = MusicRules.TRACKS.get(id, [])
	_index = randi() % _playlist.size() if _playlist.size() > 1 else 0
	var old := _music[_active]
	_fade(old, 0.0, 0.0, fade, true)
	if _playlist.is_empty():
		return
	_active = 1 - _active
	var p := _music[_active]
	p.stream = _track_stream(_playlist[_index], _playlist.size() == 1 and not id in MusicRules.ONE_SHOT)
	_set_level(0.0, p, 0.0)
	p.play()
	_fade(p, 1.0, 0.0, fade, false)


func play_ambience(id: String, fade := FADE) -> void:
	current_ambience = id
	_fade(_amb[_amb_active], 0.0, AMBIENCE_DB, fade, true)
	if id == "":
		return
	_amb_active = 1 - _amb_active
	var a := _amb[_amb_active]
	a.stream = _load(AMBIENCE_DIR % MusicRules.AMBIENCES[id], true)
	_set_level(0.0, a, AMBIENCE_DB)
	a.play()
	_fade(a, 1.0, AMBIENCE_DB, fade, false)


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
		if path in _pending:   # ainda carregando em segundo plano: espera só este
			_pending.erase(path)
			_cache[path] = ResourceLoader.load_threaded_get(path)
		else:
			_cache[path] = load(path)
	var s: AudioStream = _cache[path]
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = loop
	return s


## Um tween por player: trocar de novo no meio do fade cancela o anterior (senão o stop() do fade
## antigo desligaria o player que acabou de voltar a tocar). O fade anda no volume linear, não em dB:
## em dB a faixa nova passava quase um segundo inaudível antes de "começar" a tocar.
func _fade(p: AudioStreamPlayer, to_level: float, base_db: float, dur: float, stop_after: bool) -> void:
	var prev: Tween = _tweens.get(p)
	if prev != null and prev.is_valid():
		prev.kill()
	var tw := create_tween()
	_tweens[p] = tw
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_method(_set_level.bind(p, base_db), float(_level.get(p, 0.0)), to_level, dur)
	if stop_after:
		tw.tween_callback(_release.bind(p))


func _set_level(level: float, p: AudioStreamPlayer, base_db: float) -> void:
	_level[p] = level
	p.volume_db = maxf(base_db + linear_to_db(maxf(level, 0.0)), SILENT_DB)


## Fim do fade de saída: para e solta o stream. Um player parado que ainda segura o stream deixa a
## playback presa no servidor de áudio até o fim do jogo ("resources still in use at exit").
func _release(p: AudioStreamPlayer) -> void:
	p.stop()
	p.stream = null
