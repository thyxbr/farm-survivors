class_name BackWings
extends Node
## Asas do espaço das costas (assets/models/back/<estilo>.glb): bate os pivôs WingL e WingR devagar com o
## personagem parado, joga as asas para trás e treme as pontas na corrida, e solta de cada asa as
## partículas do tipo da peça (item "back_fx", receitas em BackFx). Só visual: nada aqui afeta
## jogabilidade nem rede.

## Batida parada: amplitude (rad) e frequência (Hz). O item pode acelerar com "flap" (asas de fada: 2.5).
const IDLE_AMP := 0.07
const IDLE_HZ := 0.28
## Corrida: quanto as asas recuam (rad) e a tremida das pontas.
const RUN_SWEEP := 0.34
const RUN_AMP := 0.05
const RUN_HZ := 2.1
## Velocidade (m/s) em que a asa já está toda recuada.
const RUN_SPEED := 5.0

var _l: Node3D
var _r: Node3D
var _rest_l: Basis
var _rest_r: Basis
var _t := 0.0
var _run := 0.0
var _flap := 1.0
var _last := Vector3.ZERO
var _has_last := false


## Liga a animação aos pivôs dentro de `root` (a instância do GLB) e cria o efeito do item.
func setup(root: Node3D, item: Dictionary) -> void:
	_l = root.find_child("WingL", true, false) as Node3D
	_r = root.find_child("WingR", true, false) as Node3D
	if _l:
		_rest_l = _l.transform.basis
	if _r:
		_rest_r = _r.transform.basis
	_t = randf() * 10.0     # cada personagem bate num tempo diferente
	_flap = float(item.get("flap", 1.0))
	var kind: String = item.get("back_fx", "")
	# o pivô fica na raiz da asa; o meio da asa está para fora, um pouco acima e atrás dele
	for side in [[_l, 1.0], [_r, -1.0]]:
		var wing: Node3D = side[0]
		if wing == null:
			continue
		var fx := BackFx.make(kind, Vector3(0.48 * side[1], 0.12, -0.2), Vector3(0.32, 0.4, 0.05))
		if fx:
			wing.add_child(fx)


func _process(delta: float) -> void:
	var host := get_parent() as Node3D
	if host == null or (_l == null and _r == null):
		return
	_t += delta
	var p := host.global_position
	var speed := 0.0
	if _has_last and delta > 0.0:
		speed = Vector2(p.x - _last.x, p.z - _last.z).length() / delta
	_last = p
	_has_last = true
	_run = lerpf(_run, clampf(speed / RUN_SPEED, 0.0, 1.0), 1.0 - exp(-5.0 * delta))
	var hz := IDLE_HZ * _flap
	var beat := sin(_t * TAU * hz)
	# ângulo em torno do eixo de pé: positivo recua a asa esquerda (a direita espelha)
	var sweep := beat * IDLE_AMP * (1.0 - 0.6 * _run) + _run * RUN_SWEEP + sin(_t * TAU * RUN_HZ) * RUN_AMP * _run
	# sobe e desce as pontas um pouco, atrasado em relação à batida
	var lift := sin(_t * TAU * hz - 0.9) * 0.045 - _run * 0.10
	if _l:
		_l.transform.basis = Basis(Vector3.UP, sweep) * Basis(Vector3.BACK, lift) * _rest_l
	if _r:
		_r.transform.basis = Basis(Vector3.UP, -sweep) * Basis(Vector3.BACK, -lift) * _rest_r
