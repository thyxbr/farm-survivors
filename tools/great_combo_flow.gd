extends "res://tools/shield_combo_flow.gd"
## Confere se o combo da montante (KnightMovesGreat) é fluido, como tools/shield_combo_flow.gd faz com o combo com
## escudo: simula a 60 quadros/s o caminho do jogo (guarda parada de great_carry, KnightAnim.great_pose, hips_follow,
## apply, unwind_twist e great_recover_pose) e mede o maior salto da velocidade angular de cada peça entre dois
## quadros. Cenários: os 3 golpes emendados, com pausa entre eles e golpes soltos voltando à guarda.
##   godot --headless --path . res://tools/great_combo_flow.tscn
## Sai com 1 se algum salto passar de GREAT_LIMIT (rad/quadro de mudança na velocidade).

## O mesmo limite do combo com escudo (o pico fica em ~0,65 no braço direito, no acerto do 1º golpe).
const GREAT_LIMIT := 0.7
const GREAT_TIMES: Array = preload("res://scripts/player/player.gd").GREAT_SWING_TIMES


func _ready() -> void:
	var m := KNIGHT.instantiate() as Node3D
	add_child(m)
	_lk = KnightLook.apply(m, {"weapon": "eclipse_greatsword"})
	_r = KnightAnim.rig(m)
	var fail := false
	for sc in [["emendados", 0.0], ["pausa 0,25 s", 0.25], ["soltos", 1.0]]:
		_prev.clear()
		_worst.clear()
		_vel.clear()
		_idle(0.5, "parado antes")
		for c in 3:
			_swing(c + 1)
			_idle(sc[1], "parado após golpe %d" % (c + 1))
		_idle(0.6, "parado no fim")
		var line := "%-14s" % sc[0]
		var bad := []
		for j in _worst:
			line += "  %s %.2f" % [j, _worst[j][0]]
			if _worst[j][0] > GREAT_LIMIT:
				bad.append("%s %.2f (%s)" % [j, _worst[j][0], _worst[j][1]])
		print(line)
		if not bad.is_empty():
			fail = true
			print("  ESTALO: ", ", ".join(bad))
	print("FLOW ", "FALHOU" if fail else "OK")
	get_tree().quit(1 if fail else 0)


func _idle(secs: float, label: String) -> void:
	var t := 0.0
	while t < secs - 0.0001:
		var p := KnightAnim.idle_pose(t)
		KnightAnim.great_carry(p, 0.0, 0.0)
		if _rec_t >= 0.0:
			_rec_t += DT
			if _rec_t < KnightAnim.SHIELD_RECOVER:
				KnightAnim.great_recover_pose(p, _rec_from, _rec_t / KnightAnim.SHIELD_RECOVER)
		_step(p, "%s t=%.2f" % [label, t])
		t += DT


func _swing(c: int) -> void:
	var dur: float = GREAT_TIMES[c - 1]
	var from := KnightAnim.capture_pose(_r)   # como player.gd: o golpe nasce da pose em que o corpo está
	_rec_t = -1.0
	var t := 0.0
	while t < dur:
		var p := KnightAnim.idle_pose(0.0)
		KnightAnim.great_carry(p, 0.0, 0.0)
		KnightAnim.great_pose(p, c, t / dur, 0.0, from)
		KnightAnim.hips_follow(p)
		_step(p, "golpe %d t=%.2f" % [c, t / dur])
		t += DT
	KnightAnim.unwind_twist(_r)
	_rec_from = KnightAnim.capture_pose(_r)   # como player.gd: sem golpe emendado, volta daqui
	_rec_t = 0.0
