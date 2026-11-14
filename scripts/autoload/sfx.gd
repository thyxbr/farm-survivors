extends Node
## Efeitos sonoros. A maioria vem de arquivos em assets/audio/sfx (FILES; vários arquivos por som
## sorteiam sem repetir o último). Os da horta e da cozinha seguem sintetizados no carregamento.
## Para trocar um som, troque o arquivo ou a lista em FILES; licenças em assets/audio/CREDITS.md.

const SFX_DIR := "res://assets/audio/sfx/%s.wav"
const FILES := {
	# espada: whoosh no golpe, metal no acerto; montantes e cutelos usam a versão pesada
	"sword_swing": ["sword_swing_1", "sword_swing_2", "sword_swing_3"],
	"sword_swing_heavy": ["sword_swing_heavy_1", "sword_swing_heavy_2", "sword_swing_heavy_3"],
	# acerto: só a lâmina (genérico, slime), lâmina em carne (criaturas), carne + pancada (espada pesada)
	"sword_hit": ["sword_hit_1", "sword_hit_2"],
	"sword_hit_flesh": ["sword_hit_flesh_1", "sword_hit_flesh_2"],
	"sword_hit_heavy": ["sword_hit_heavy_1", "sword_hit_heavy_2"],
	# coleta: golpe em árvore e em pedra/veio
	"chop_wood": ["chop_wood_1", "chop_wood_2"],
	"chop_stone": ["chop_stone_1"],
	# cajado: sopro de vento no gesto + o elemento da arma (staff_element) no disparo e no impacto
	"staff_wind": ["staff_wind_1", "staff_wind_2"],
	"arcane_cast": ["arcane_cast_1", "arcane_cast_2", "arcane_cast_3"],
	"arcane_hit": ["arcane_hit_1", "arcane_hit_2", "arcane_hit_3"],
	"fire_cast": ["fire_cast_1", "fire_cast_2", "fire_cast_3"],
	"fire_hit": ["fire_hit_1", "fire_hit_2", "fire_hit_3"],
	"frost_cast": ["frost_cast_1", "frost_cast_2", "frost_cast_3"],
	"frost_hit": ["frost_hit_1", "frost_hit_2", "frost_hit_3"],
	# arco: puxar a corda, tique na tensão total, soltar, flecha acertando
	"bow_draw": ["bow_draw_1", "bow_draw_2"],
	"bow_full": ["bow_full_1"],
	"bow_shot": ["bow_shot_1", "bow_shot_2"],
	"arrow_hit": ["arrow_hit_1", "arrow_hit_2"],
	# genéricos (inimigos, réplicas, mundo)
	"swing": ["swing_1", "swing_2", "swing_3"],
	"dodge": ["dodge_1", "dodge_2"],
	"hit": ["hit_1", "hit_2", "hit_3"],
	"hurt": ["hurt_1", "hurt_2", "hurt_3"],
	"enemy_die": ["enemy_die_1", "enemy_die_2", "enemy_die_3"],
	"slime": ["slime_1", "slime_2", "slime_3"],
	"fire": ["fire_cast_1", "fire_cast_2", "fire_cast_3"],
	"explode": ["explode_1", "explode_2", "explode_3", "explode_4"],
	"frost": ["frost_nova_1"],
	"heal": ["heal_1", "heal_2"],
	"zap": ["zap_1"],
	"slam": ["slam_1"],
	"death": ["death_1"],
	"portal": ["portal_1"],
	"anvil": ["anvil_1"],
	# interface e itens
	"pickup": ["pickup_1", "pickup_2"],
	# ouro usa o mesmo som de pegar um item do chão
	"coin": ["pickup_1", "pickup_2"],
	"gem": ["gem_1", "gem_2", "gem_3", "gem_4"],
	"levelup": ["levelup_1"],
	"quest": ["quest_1"],
	"click": ["click_1", "click_2", "click_3"],
	"error": ["error_1"],
}
const RATE := 22050
const NEAR_DIST := 6.0    # até aqui o som do mundo toca no volume cheio
const FAR_DIST := 32.0    # além disso não se ouve nada

var streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _players_3d: Array[AudioStreamPlayer3D] = []
var _next_3d := 0
var _lp := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 1234
	for i in 14:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_players.append(p)
	for i in 20:
		var p3 := AudioStreamPlayer3D.new()
		# a queda com a distância é calculada à mão (distance_gain) a partir do
		# jogador, não da câmera; o player 3D só cuida da direção
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		p3.panning_strength = 0.8
		p3.bus = &"SFX"
		add_child(p3)
		_players_3d.append(p3)
	for sound in FILES:
		streams[sound] = _from_files(FILES[sound])
	# sem arquivo: sintetizados
	streams["bloop"] = _gen(0.25, _bloop)
	streams["plant"] = _gen(0.22, _plant)
	streams["water"] = _gen(0.5, _water)
	streams["harvest"] = _gen(0.3, _harvest)
	streams["cook"] = _gen(0.8, _cook)
	streams["eat"] = _gen(0.36, _eat)


## Elemento do cajado pelo efeito da arma: lentidão = gelo, explosão = fogo, o resto = arcano (faísca).
func staff_element(weapon_id: String) -> String:
	match str(ItemDB.get_item(weapon_id).get("fx", "")):
		"slow":
			return "frost"
		"splash":
			return "fire"
	return "arcane"


## Som do acerto da espada: em carne (pesado ou não) se acertou alguma criatura; só a lâmina se foi só slime.
func sword_hit(flesh: bool, heavy: bool) -> String:
	if not flesh:
		return "sword_hit"
	return "sword_hit_heavy" if heavy else "sword_hit_flesh"


## Montantes e cutelos golpeiam com o som pesado.
func heavy_sword(weapon_id: String) -> bool:
	return str(ItemDB.get_item(weapon_id).get("shape", "")) in ["great", "cleaver"]


func play(sound: String, pitch_var := 0.08, volume_db := 0.0) -> void:
	if not streams.has(sound):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = streams[sound]
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.volume_db = volume_db
	p.play()


## Som que acontece num ponto do mundo (inimigos, outros jogadores, explosões).
## O volume cai com a distância até o jogador local e some de vez além de FAR_DIST;
## o AudioStreamPlayer3D dá a direção (esquerda/direita) em relação à câmera.
func play_at(sound: String, pos: Vector3, pitch_var := 0.08, volume_db := 0.0) -> void:
	if not streams.has(sound):
		return
	var listener: Variant = _listener_pos()
	if listener == null:
		play(sound, pitch_var, volume_db)
		return
	var gain := distance_gain(pos.distance_to(listener))
	if gain <= 0.0:
		return
	var p := _players_3d[_next_3d]
	_next_3d = (_next_3d + 1) % _players_3d.size()
	p.stream = streams[sound]
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.volume_db = volume_db + linear_to_db(gain)
	p.global_position = pos
	p.play()


## 1.0 até NEAR_DIST, cai em curva até 0.0 em FAR_DIST.
static func distance_gain(d: float) -> float:
	if d <= NEAR_DIST:
		return 1.0
	if d >= FAR_DIST:
		return 0.0
	var t := (d - NEAR_DIST) / (FAR_DIST - NEAR_DIST)
	return (1.0 - t) * (1.0 - t)


func _listener_pos() -> Variant:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not player.is_inside_tree():
		return null
	return player.global_position


## Um arquivo vira o próprio stream; vários viram um AudioStreamRandomizer que sorteia sem repetir
## o último (o tom continua variando em play() por pitch_scale).
func _from_files(files: Array) -> AudioStream:
	if files.size() == 1:
		return load(SFX_DIR % files[0])
	var r := AudioStreamRandomizer.new()
	r.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	r.random_pitch = 1.0
	r.random_volume_offset_db = 0.0
	for f in files:
		r.add_stream(-1, load(SFX_DIR % f))
	return r


func _gen(dur: float, f: Callable) -> AudioStreamWAV:
	_lp = 0.0
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var v: float = clamp(f.call(t, dur), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


func _noise(cut: float) -> float:
	_lp += (_rng.randf_range(-1.0, 1.0) - _lp) * cut
	return _lp


func _env(t: float, dur: float, attack := 0.01) -> float:
	if t < attack:
		return t / attack
	return pow(1.0 - (t - attack) / (dur - attack), 2.0)


func _tone(t: float, freq: float) -> float:
	return sin(TAU * freq * t)


func _bloop(t: float, d: float) -> float:
	return _tone(t, 500.0 - 1400.0 * t) * 0.45 * _env(t, d)


func _plant(t: float, d: float) -> float:
	return (_noise(0.12) * 0.9 + _tone(t, 120.0 - 120.0 * t) * 0.5) * _env(t, d, 0.004)


func _water(t: float, d: float) -> float:
	var trickle := 0.6 + 0.4 * sin(TAU * 23.0 * t) * sin(TAU * 7.0 * t)
	return _noise(0.5) * 0.7 * trickle * sin(PI * t / d)


func _harvest(t: float, d: float) -> float:
	var pop := _noise(0.4) * (1.0 if t < 0.03 else 0.0)
	return pop + _tone(t, 520.0 + 900.0 * t) * 0.3 * _env(t, d, 0.01)


func _cook(t: float, d: float) -> float:
	var sizzle := _noise(0.85) * 0.35 * (0.7 + 0.3 * sin(TAU * 13.0 * t))
	var blub := _tone(t, 180.0 + 60.0 * sin(TAU * 6.0 * t)) * 0.25 * (1.0 if fmod(t, 0.2) < 0.06 else 0.0)
	return (sizzle + blub) * _env(t, d, 0.05)


func _eat(t: float, d: float) -> float:
	var bite: float = fmod(t, 0.12)
	return _noise(0.6) * 0.8 * (pow(1.0 - bite / 0.12, 3.0) if bite < 0.12 else 0.0) * (1.0 - t / d)
