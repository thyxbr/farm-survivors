class_name PartyShieldBuff
extends Node3D
## Bastião de Escudos num personagem (scenes/vfx/party_shield/party_shield_buff.tscn): o visual do buff do Grito do
## Bastião enquanto ele dura: só os escudos pequenos de energia azul girando em volta do corpo. Nasce pela BuffAura do
## personagem (estilo "bastiao", buff "sword_rally" ativo), no jogador local e nas réplicas dos outros (o estilo vai pela
## rede junto com as outras auras), e se desfaz quando o buff sai (BuffAura chama dissipate() em vez de liberar o nó).
##
##   PartyShieldBuff (Node3D, origem nos pés, filho da BuffAura do modelo)
##   ├─ Orbit       (Node3D na altura da cintura, sem o giro do modelo)
##   │   └─ Shield0..N (MeshInstance3D criados aqui: escudos pequenos de energia girando)
##   └─ Dissipate   (GPUParticles3D, uma vez só: os escudos virando partículas azuis no fim)
##
## Os escudos crescem na entrada, giram pela órbita (passam atrás do corpo) e, no fim, se desfazem em partículas que
## somem aos poucos. Tudo com Tween; o nó se libera sozinho.

const SHIELD_MAT := preload("res://assets/vfx/party_shield/energy_shield_mat.tres")
const DEFAULT_CONFIG := preload("res://assets/vfx/party_shield/party_shield_config.tres")
## Tempo de vida das partículas da dissipação (s): o nó espera elas sumirem antes de se liberar.
const PARTICLE_LIFE := 0.9

@export var config: PartyShieldConfig

var t := 0.0
var dissipating := false
var _intensity := 0.0
var _shields: Array[MeshInstance3D] = []
var _shield_scale := 0.0
var _shield_dissolve := 0.0
var _tween: Tween

@onready var orbit: Node3D = $Orbit
@onready var dissipate_fx: GPUParticles3D = $Dissipate


func _ready() -> void:
	if config == null:
		config = DEFAULT_CONFIG
	orbit.position.y = config.orbit_height
	var quad := QuadMesh.new()
	quad.size = Vector2(config.shield_size, config.shield_size * 1.15)
	for i in config.shield_count:
		var m := MeshInstance3D.new()
		m.name = "Shield%d" % i
		m.mesh = quad
		m.material_override = SHIELD_MAT
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.set_instance_shader_parameter("phase", float(i) / maxf(float(config.shield_count), 1.0))
		orbit.add_child(m)
		_shields.append(m)
	PartyShieldParticles.setup_dissipate(dissipate_fx, config)
	# entrada: o brilho e os escudos crescem juntos
	_tween = create_tween().set_parallel(true)
	_tween.tween_method(_set_intensity, 0.0, 1.0, config.intro_time).set_trans(Tween.TRANS_SINE)
	_tween.tween_method(_set_shield_scale, 0.0, 1.0, config.intro_time * 1.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_apply()


func _process(delta: float) -> void:
	t += delta
	_apply()


## Posição, orientação e brilho de cada escudo no instante atual.
func _apply() -> void:
	# a órbita não gira junto com o modelo (o herói virando não acelera os escudos): só a escala do pai fica
	var s := orbit.global_basis.get_scale()
	orbit.global_basis = Basis.from_scale(s)
	var n := _shields.size()
	for i in n:
		var sh := _shields[i]
		var off := PartyShieldRules.shield_offset(i, n, t, config.orbit_radius, config.orbit_speed, config.orbit_bob)
		sh.position = off
		# cada escudo de frente para fora da órbita, um pouco inclinado para trás
		var out := Vector3(off.x, 0.0, off.z)
		if out.length() > 0.001:
			sh.basis = Basis.looking_at(-out.normalized(), Vector3.UP).rotated(out.normalized().cross(Vector3.UP).normalized(), -0.18)
		sh.scale = Vector3.ONE * maxf(_shield_scale, 0.001)
		sh.set_instance_shader_parameter("intensity", _intensity * config.buff_intensity)
		sh.set_instance_shader_parameter("dissolve", _shield_dissolve)


## O buff acabou (ou foi limpo): os escudos se desfazem em partículas azuis pequenas que somem aos poucos e o nó se
## libera sozinho no fim. Chamar de novo não faz nada.
func dissipate() -> void:
	if not is_inside_tree():
		queue_free()
		return
	if dissipating:
		return
	dissipating = true
	dissipate_fx.restart()
	dissipate_fx.emitting = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var d := config.dissipate_time
	_tween = create_tween().set_parallel(true)
	_tween.tween_method(_set_shield_dissolve, 0.0, 1.0, d * 0.6)
	_tween.tween_method(_set_shield_scale, _shield_scale, 0.35, d * 0.6).set_trans(Tween.TRANS_SINE)
	_tween.tween_method(_set_intensity, _intensity, 0.0, d).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.chain().tween_interval(PARTICLE_LIFE)
	_tween.chain().tween_callback(queue_free)


func _set_intensity(v: float) -> void:
	_intensity = v


func _set_shield_scale(v: float) -> void:
	_shield_scale = v


func _set_shield_dissolve(v: float) -> void:
	_shield_dissolve = v


## Escudos de energia em volta (testes).
func shield_nodes() -> Array[MeshInstance3D]:
	return _shields
