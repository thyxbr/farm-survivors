class_name DarkTauntVFX
extends Node3D
## Círculo da Provocação Sombria: energia, fumaça e partículas que não são o círculo nem as mãos (prefab
## scenes/vfx/dark_taunt/dark_taunt_vfx.tscn), filho do DarkTauntSkill, no centro do círculo.
##   burst()      a onda de energia sombria que sai do herói quando ele solta os braços (anel escuro que corre
##                pelo chão até a borda, clarão roxo e fumaça)
##   eruption(p)  onde cada mão 3D rompe o chão: as mãos e a fumaça da sprite sheet (DarkSheet de pé, escuros
##                preservados) saem junto (quadros 11-23), agarram (24-35) e se desfazem em fumaça (36-56). Não fica
##                no centro: o herói está lá e a coluna o cobriria.
##   aura(e)      energia sombria em volta de cada inimigo agarrado: fumaça da sheet (48-56) envolvendo o corpo e
##                faíscas violeta subindo; segue o inimigo e some quando as mãos soltam
##   dissipate()  a fumaça escura se espalha e tudo apaga
## Só visual: a regra (quem é agarrado, provocação) é do DarkTauntSkill/Enemy.

const SHEET := preload("res://scenes/vfx/dark_taunt/dark_sheet_upright.tscn")
const VIOLET := Color(0.62, 0.25, 1.0)
const MAGENTA := Color(1.0, 0.3, 0.85)
const SMOKE := Color(0.06, 0.01, 0.1, 0.6)

@onready var wave: MeshInstance3D = $Wave

var config: DarkTauntConfig
var _auras: Array[Dictionary] = []
var _eruptions: Array[DarkSheet] = []
var _wave_t := -1.0
var _wave_dur := 0.5


func setup(cfg: DarkTauntConfig) -> void:
	config = cfg
	wave.visible = false


## A energia solta pelo herói: anel escuro correndo pelo chão, clarão e fumaça.
func burst(origin: Vector3) -> void:
	var k := config.energy_intensity
	FXEpic.flash(origin + Vector3.UP, VIOLET, 3.5 * k, config.radius * 1.2, 0.35)
	FXEpic.glow_burst(origin + Vector3.UP * 1.1, MAGENTA, int(24 * k) + 4, 4.0, 0.12, 0.55, -1.0)
	FXEpic.smoke(origin + Vector3.UP * 0.4, SMOKE, int(10 * k) + 4, 1.4, 1.3)
	_wave_t = 0.0
	_wave_dur = 0.45
	wave.visible = true


## Erupção de mãos e fumaça da sheet no ponto `p` (chão) onde uma mão rompe, subindo em `time` s.
func eruption(p: Vector3, size: float, time: float) -> void:
	var s: DarkSheet = SHEET.instantiate()
	add_child(s)
	s.top_level = true
	s.global_position = p - Vector3.UP * 0.05
	s.set_param("crop", DarkSheet.PLUME_CROP)
	s.set_param("soft_edge", 1.0)
	s.scale = Vector3(1.35 * size, 0.95 * size, 1.0)
	s.intensity = 0.8 * clampf(config.energy_intensity, 0.0, 1.5)
	s.play(DarkSheet.HANDS_RISE, time)
	_eruptions.append(s)


## As mãos fecharam (s de imobilização): as da sheet também agarram, em vai e vem.
func grab(time: float) -> void:
	for s in _eruptions:
		if is_instance_valid(s):
			s.play(DarkSheet.HANDS_GRAB, minf(time, 1.2), true)


## As mãos se desfazem em fumaça (s): erupções, auras, e a fumaça escura se espalha.
func dissipate(time: float) -> void:
	for s in _eruptions:
		if is_instance_valid(s):
			s.play(Vector2i(DarkSheet.HANDS_FADE.x, DarkSheet.SMOKE.y), time)
			s.fade_out(time * 1.05, true)
	_eruptions.clear()
	for a in _auras:
		_end_aura(a, time * 0.6)
	_auras.clear()


## Energia sombria em volta do inimigo agarrado `e` (fumaça da sheet + faíscas), até dissipate() ou ele morrer.
func aura(e: Node3D) -> void:
	if e == null or not is_instance_valid(e):
		return
	var h := float(e.head_top()) if e.has_method("head_top") else 1.6
	var s: DarkSheet = SHEET.instantiate()
	add_child(s)
	s.top_level = true
	s.set_param("crop", DarkSheet.SMOKE_CROP)
	s.set_param("soft_edge", 1.0)
	s.scale = Vector3(h * 1.5, h * 1.1, 1.0)
	s.intensity = 0.9 * config.energy_intensity
	s.play(DarkSheet.SMOKE, 1.3, true)
	var sparks := FXEpic.stream(e, "glow", VIOLET, int(10 * config.energy_intensity) + 2, 0.7, 0.05 * clampf(h / 1.6, 0.7, 2.0))
	if sparks:
		sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		sparks.emission_sphere_radius = 0.45 * clampf(h / 1.6, 0.7, 2.0)
		sparks.position = Vector3.UP * h * 0.4
		sparks.direction = Vector3.UP
		sparks.spread = 25.0
		sparks.initial_velocity_min = 0.4
		sparks.initial_velocity_max = 1.3
		sparks.gravity = Vector3(0, 0.6, 0)
	var a := {"e": e, "sheet": s, "sparks": sparks}
	_auras.append(a)
	_follow(a)


func _end_aura(a: Dictionary, time: float) -> void:
	var s = a.get("sheet")
	if is_instance_valid(s):
		s.fade_out(time, true)
	FXEpic.stop_stream(a.get("sparks"))


func _follow(a: Dictionary) -> bool:
	var e = a.e
	var s = a.sheet
	if not is_instance_valid(e) or e.get("dead") == true:
		return false
	if is_instance_valid(s):
		s.global_position = e.global_position - Vector3.UP * 0.1
	return true


## Restam efeitos vivos (para o dono saber quando liberar)?
func alive() -> bool:
	if wave.visible:
		return true
	for c in get_children():
		if c is DarkSheet and c.visible and not c.is_queued_for_deletion():
			return true
	return false


func _process(delta: float) -> void:
	for i in range(_auras.size() - 1, -1, -1):
		if not _follow(_auras[i]):
			_end_aura(_auras[i], 0.3)   # morreu: a fumaça em volta dele some logo
			_auras.remove_at(i)
	if _wave_t >= 0.0:
		_wave_t += delta
		var u := clampf(_wave_t / _wave_dur, 0.0, 1.0)
		var r := lerpf(0.4, config.radius * 1.05, 1.0 - pow(1.0 - u, 2.0))
		wave.scale = Vector3(r, 1.0, r)
		wave.set_instance_shader_parameter("intensity", (1.0 - u) * config.energy_intensity)
		if u >= 1.0:
			_wave_t = -1.0
			wave.visible = false
