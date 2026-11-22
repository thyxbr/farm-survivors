class_name PartyShieldCast
extends Node3D
## Aura azul do Grito do Bastião no herói enquanto a animação roda (scenes/vfx/party_shield/party_shield_cast.tscn).
## Filho do Player (segue o herói; a origem é nos pés). PartyShieldAbilities cria no começo e chama shout() no grito e
## finish() quando a animação termina (o buff entra aí) ou cancel() na esquiva. Some sozinho com Tween.
##
##   PartyShieldCast (Node3D)
##   ├─ Aura        (MeshInstance3D, cápsula em volta do corpo: borda azul suave, rally_aura.gdshader)
##   ├─ SheetBack   (MeshInstance3D, quad: formação da sprite sheet, metade de trás)
##   ├─ SheetFront  (MeshInstance3D, quad: formação da sprite sheet, metade da frente)
##   ├─ Glow        (MeshInstance3D, plano no chão: brilho e runas sob os pés)
##   ├─ Wave        (MeshInstance3D, plano no chão: a onda do grito correndo para fora)
##   ├─ Light       (OmniLight3D azul, acompanha o brilho)
##   └─ Motes       (GPUParticles3D: energia subindo do chão)
##
## O brilho de tudo sobe e desce por Tween (aura_fade_in / aura_fade_out do PartyShieldConfig): a aura nunca acende
## ou apaga num tranco. A sheet toca a formação (quadros 1..18) ao longo da animação inteira.

const DEFAULT_CONFIG := preload("res://assets/vfx/party_shield/party_shield_config.tres")
## Quanto as metades da formação saem do centro do corpo (m).
const SHEET_PUSH := 0.5
## Duração da onda do grito no chão (s).
const WAVE_TIME := 0.7

@export var config: PartyShieldConfig
## Duração da animação (s): a formação da sheet termina junto com ela.
@export var duration := PartyShieldRules.CLIP_END

var t := 0.0
var finished := false
var _weight := 0.0
var _flash := 0.0
var _wave := 0.0
var _wave_alpha := 0.0
var _tween: Tween

@onready var aura: MeshInstance3D = $Aura
@onready var sheet_back: MeshInstance3D = $SheetBack
@onready var sheet_front: MeshInstance3D = $SheetFront
@onready var glow: MeshInstance3D = $Glow
@onready var wave: MeshInstance3D = $Wave
@onready var light: OmniLight3D = $Light
@onready var motes: GPUParticles3D = $Motes


func _ready() -> void:
	if config == null:
		config = DEFAULT_CONFIG
	var mat: ShaderMaterial = aura.material_override
	mat = mat.duplicate()   # a cor vem do config (cada herói pode ter a sua sem mexer no .tres)
	mat.set_shader_parameter("color", config.aura_color)
	aura.material_override = mat
	var s := config.cast_sheet_size
	for q in [sheet_back, sheet_front]:
		q.scale = Vector3(s, s, s)
	sheet_back.set_instance_shader_parameter("half_mode", 1.0)
	sheet_back.set_instance_shader_parameter("push", -SHEET_PUSH)
	sheet_front.set_instance_shader_parameter("half_mode", 2.0)
	sheet_front.set_instance_shader_parameter("push", SHEET_PUSH)
	wave.scale = Vector3(config.shout_wave_radius, 1.0, config.shout_wave_radius)
	light.light_color = config.aura_color
	PartyShieldParticles.setup_motes(motes, config)
	motes.emitting = true
	_tween = create_tween()
	_tween.tween_method(_set_weight, 0.0, 1.0, config.aura_fade_in).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_apply()


func _process(delta: float) -> void:
	t += delta
	_flash = maxf(0.0, _flash - delta * 2.5)
	_apply()


func _apply() -> void:
	var k := _weight * config.aura_intensity
	# respira devagar: suave, sem piscar
	var breath := 0.85 + 0.15 * sin(t * 3.0)
	aura.set_instance_shader_parameter("intensity", k * breath + _flash * 0.8)
	var f := PartyShieldRules.form_frame(t, duration)
	var fa := floorf(f)
	for q in [sheet_back, sheet_front]:
		q.set_instance_shader_parameter("frame_a", fa)
		q.set_instance_shader_parameter("frame_b", minf(fa + 1.0, float(PartyShieldRules.FORM_LAST)))
		q.set_instance_shader_parameter("blend", f - fa)
		q.set_instance_shader_parameter("intensity", k)
	glow.set_instance_shader_parameter("glow", k * (0.8 + _flash))
	wave.set_instance_shader_parameter("wave", _wave)
	wave.set_instance_shader_parameter("wave_alpha", _wave_alpha)
	light.light_energy = config.light_energy * (k * breath + _flash * 1.5)
	light.visible = light.light_energy > 0.01


## O grito: a onda corre pelo chão e a aura dá um pulso.
func shout() -> void:
	_flash = 1.0
	var tw := create_tween().set_parallel(true)
	tw.tween_method(_set_wave, 0.0, 1.0, WAVE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(_set_wave_alpha, 1.0, 0.0, WAVE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


## A animação terminou (o buff entrou): um último pulso e a aura apaga devagar; depois o nó se libera.
func finish() -> void:
	_end(config.aura_fade_out, 0.6)


## Esquiva antes do grito terminar: apaga mais rápido, sem pulso.
func cancel() -> void:
	_end(config.aura_fade_out * 0.5, 0.0)


func _end(time: float, flash: float) -> void:
	if finished:
		return
	finished = true
	_flash = maxf(_flash, flash)
	motes.emitting = false
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_weight, _weight, 0.0, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_interval(0.5)   # as últimas partículas sobem e somem
	_tween.tween_callback(queue_free)


func _set_weight(v: float) -> void:
	_weight = v


func _set_wave(v: float) -> void:
	_wave = v


func _set_wave_alpha(v: float) -> void:
	_wave_alpha = v


## Brilho atual da aura, 0..1 (testes).
func weight() -> float:
	return _weight
