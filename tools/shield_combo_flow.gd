extends Node
## Confere se o combo de espada com escudo é fluido: simula a 60 quadros/s o caminho do jogo (pose de parado,
## KnightAnim.shield_combo_pose, hips_follow, apply, unwind_twist e shield_recover_pose) e mede o maior salto
## da velocidade angular de cada peça entre dois quadros (um golpe rápido é suave; um estalo muda a velocidade
## de uma vez). Cenários: os 4 golpes emendados (clique segurado), com pausa entre
## eles (clique dentro da janela do combo) e golpes soltos voltando ao parado.
##   godot --headless --path . res://tools/shield_combo_flow.tscn
## Sai com 1 se algum salto passar de LIMIT (rad/quadro de mudança na velocidade): um estalo na tela.

const KNIGHT := preload("res://assets/models/knight.glb")
const DT := 1.0 / 60.0
## Referência: o combo da espada sozinha (KnightMoves.SWORD, feito à mão) chega a 1,3 no braço e 2,6 na espada; o
## combo com escudo fica abaixo de 0,7 (o pico é o estalo do pulso no acerto do 3º golpe, que é o do Mixamo).
const LIMIT := 0.7
const TIMES: Array = preload("res://scripts/player/player.gd").SHIELD_SWING_TIMES

var _r: Dictionary
var _lk: Dictionary
var _prev := {}
var _worst := {}
var _vel := {}
var _rec_from := {}
var _rec_t := -1.0


func _ready() -> void:
	var m := KNIGHT.instantiate() as Node3D
	add_child(m)
	_lk = KnightLook.apply(m, {"weapon": "knight_blade", "offhand": "knight_shield"})
	_r = KnightAnim.rig(m)
	var fail := false
	for sc in [["emendados", 0.0], ["pausa 0,25 s", 0.25], ["soltos", 1.0]]:
		_prev.clear()
		_worst.clear()
		_vel.clear()
		_idle(0.5, "parado antes")
		for c in 4:
			_swing(c + 1)
			_idle(sc[1], "parado após golpe %d" % (c + 1))
		_idle(0.6, "parado no fim")
		var line := "%-14s" % sc[0]
		var bad := []
		for j in _worst:
			line += "  %s %.2f" % [j, _worst[j][0]]
			if _worst[j][0] > LIMIT:
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
		if _rec_t >= 0.0:
			_rec_t += DT
			if _rec_t < KnightAnim.SHIELD_RECOVER:
				KnightAnim.shield_recover_pose(p, _rec_from, _rec_t / KnightAnim.SHIELD_RECOVER)
		_step(p, "%s t=%.2f" % [label, t])
		t += DT


func _swing(c: int) -> void:
	var dur: float = TIMES[c - 1]
	var from := KnightAnim.capture_pose(_r)   # como player.gd: o golpe nasce da pose em que o corpo está
	_rec_t = -1.0
	var t := 0.0
	while t < dur:
		var p := KnightAnim.idle_pose(0.0)
		KnightAnim.shield_combo_pose(p, c, t / dur, 0.0, from)
		KnightAnim.hips_follow(p)
		_step(p, "golpe %d t=%.2f" % [c, t / dur])
		t += DT
	KnightAnim.unwind_twist(_r)
	_rec_from = KnightAnim.capture_pose(_r)   # como player.gd: sem golpe emendado, volta daqui
	_rec_t = 0.0


func _step(p: Dictionary, where: String) -> void:
	KnightAnim.apply(_r, p, 1.0 - exp(-14.0 * DT))
	KnightAnim.hold_weapon_upright(_lk, _r)
	var now := {
		"quadril": (_r.Pelvis as Node3D).global_basis,
		"tronco": (_r.Body as Node3D).global_basis,
		"braço D": (_r.ArmR as Node3D).global_basis,
		"antebraço D": (_r.ElbowR as Node3D).global_basis,
		"espada": (_lk.holder as Node3D).global_basis,
		"braço E": (_r.ArmL as Node3D).global_basis,
		"coxa E": (_r.LegL as Node3D).global_basis,
		"coxa D": (_r.LegR as Node3D).global_basis,
	}
	# velocidade angular de cada peça (rad/quadro, vetor no mundo); o estalo é a velocidade mudando de uma vez
	var vel := {}
	for j in now:
		if not _prev.has(j):
			continue
		var dq := (Quaternion(now[j] as Basis) * Quaternion(_prev[j] as Basis).inverse()).normalized()
		if dq.w < 0.0:
			dq = -dq
		var w := dq.get_axis() * dq.get_angle() if dq.get_angle() > 1e-6 else Vector3.ZERO
		vel[j] = w
		if _vel.has(j):
			var jump: float = (w - (_vel[j] as Vector3)).length()
			if not _worst.has(j) or jump > _worst[j][0]:
				_worst[j] = [jump, where, w.length()]
	_prev = now
	_vel = vel
