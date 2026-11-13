extends Node
## Efeitos sonoros sintetizados em tempo de carregamento (sem arquivos de áudio).

const RATE := 22050

var streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _lp := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 1234
	for i in 14:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	streams["swing"] = _gen(0.2, _swing)
	streams["hit"] = _gen(0.22, _hit)
	streams["hurt"] = _gen(0.25, _hurt)
	streams["fire"] = _gen(0.35, _fire)
	streams["explode"] = _gen(0.5, _explode)
	streams["heal"] = _gen(0.45, _heal)
	streams["frost"] = _gen(0.6, _frost)
	streams["pickup"] = _gen(0.18, _pickup)
	streams["coin"] = _gen(0.15, _coin)
	streams["levelup"] = _gen(0.7, _levelup)
	streams["click"] = _gen(0.05, _click)
	streams["bloop"] = _gen(0.25, _bloop)
	streams["slam"] = _gen(0.6, _slam)
	streams["death"] = _gen(1.0, _death)
	streams["quest"] = _gen(0.6, _quest)
	streams["zap"] = _gen(0.3, _zap)
	streams["gem"] = _gen(0.09, _gem)


func play(sound: String, pitch_var := 0.08, volume_db := 0.0) -> void:
	if not streams.has(sound):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = streams[sound]
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.volume_db = volume_db
	p.play()


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


func _swing(t: float, d: float) -> float:
	return _noise(0.05 + 0.4 * t / d) * sin(PI * t / d) * 1.6


func _hit(t: float, d: float) -> float:
	return (_tone(t, 140.0 - 200.0 * t) * 0.8 + _noise(0.6) * 0.6) * _env(t, d, 0.002)


func _hurt(t: float, d: float) -> float:
	return sign(_tone(t, 260.0 - 300.0 * t)) * 0.35 * _env(t, d)


func _fire(t: float, d: float) -> float:
	return (_noise(0.15) * 1.2 + _tone(t, 320.0 - 500.0 * t) * 0.3) * _env(t, d, 0.03)


func _explode(t: float, d: float) -> float:
	return (_noise(0.08) * 2.0 + _tone(t, 70.0 - 40.0 * t) * 0.6) * _env(t, d, 0.005)


func _heal(t: float, d: float) -> float:
	var notes := [523.0, 659.0, 784.0]
	var idx: int = min(2, int(t / 0.12))
	return _tone(t, notes[idx]) * 0.35 * _env(fmod(t, 0.12) if idx < 2 else t - 0.24, 0.12 if idx < 2 else d - 0.24)


func _frost(t: float, d: float) -> float:
	return (_noise(0.7) * 0.4 + _tone(t, 1400.0 - 1000.0 * t) * 0.25) * _env(t, d, 0.01)


func _pickup(t: float, d: float) -> float:
	return _tone(t, 880.0 if t < 0.07 else 1320.0) * 0.3 * _env(t, d)


func _coin(t: float, d: float) -> float:
	return (_tone(t, 1600.0) + _tone(t, 2400.0) * 0.5) * 0.22 * _env(t, d, 0.002)


func _levelup(t: float, d: float) -> float:
	var notes := [523.0, 659.0, 784.0, 1046.0]
	var idx: int = min(3, int(t / 0.12))
	return (_tone(t, notes[idx]) + _tone(t, notes[idx] * 2.0) * 0.2) * 0.3 * (1.0 - t / d)


func _click(t: float, d: float) -> float:
	return _tone(t, 700.0) * 0.25 * _env(t, d, 0.001)


func _bloop(t: float, d: float) -> float:
	return _tone(t, 500.0 - 1400.0 * t) * 0.45 * _env(t, d)


func _slam(t: float, d: float) -> float:
	return (_noise(0.04) * 2.5 + _tone(t, 55.0) * 0.8) * _env(t, d, 0.003)


func _death(t: float, d: float) -> float:
	return (_tone(t, 220.0 - 150.0 * t) * 0.4 + _tone(t, 110.0 - 70.0 * t) * 0.3) * (1.0 - t / d)


func _zap(t: float, d: float) -> float:
	var crackle := _noise(0.9) * (0.6 if fmod(t, 0.03) < 0.015 else 0.2)
	return (crackle + _tone(t, 1800.0 - 4000.0 * t) * 0.2) * _env(t, d, 0.002)


func _gem(t: float, d: float) -> float:
	return (_tone(t, 1900.0 + 3000.0 * t) * 0.25) * _env(t, d, 0.002)


func _quest(t: float, d: float) -> float:
	var notes := [659.0, 784.0, 988.0]
	var idx: int = min(2, int(t / 0.15))
	return _tone(t, notes[idx]) * 0.3 * (1.0 - t / d)
