class_name IceSpike
extends Node3D
## Estaca de Gelo (Sentinela da Nevasca): a estaca que caiu do teto fica cravada no chão por BlizzardRules.SPIKE_LIFE
## s soltando frio; quem encosta nela (SPIKE_AURA m) leva um tique a cada SPIKE_TICK s e fica lento. No fim ela
## racha e se desfaz. Servidor e cliente criam a estaca no mesmo ponto; só quem manda no chefe (`deal`: servidor ou
## solo) dá o dano. Desenho: a estaca lapidada de ponta para baixo, cacos em volta do pé e a geada no chão.

## Dano por tique, já com o multiplicador do chefe; o nível ajusta contra cada jogador.
var dmg := 5.0
var level := 0
var deal := false
var _t := 0.0
var _tick := 0.0
var _puff_t := 0.0
var _body: Node3D


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_body = Node3D.new()
	add_child(_body)
	var lean := Vector3(randf_range(-0.12, 0.12), 0.0, randf_range(-0.12, 0.12))
	_shard(Vector3(0, 3.3, 0), Basis(Vector3.RIGHT, PI + lean.x) * Basis(Vector3.BACK, lean.z), Vector3(0.72, 3.6, 0.72))
	for i in 4:   # cacos em volta do pé, de pé e abertos para fora
		var a := TAU * (i + randf_range(-0.3, 0.3)) / 4.0
		var h := randf_range(0.5, 0.9)
		var out := Vector3(cos(a), 0.0, sin(a))
		_shard(out * randf_range(0.45, 0.7) - Vector3.UP * 0.05, Basis(out.cross(Vector3.UP).normalized(), -0.5), Vector3(h * 0.5, h, h * 0.5))
	FXToon.frost_sigil(global_position, BlizzardRules.SPIKE_AURA, 0.25, BlizzardRules.SPIKE_LIFE - 0.9)
	_body.scale = Vector3(1.0, 0.6, 1.0)
	var tw := _body.create_tween()
	tw.tween_property(_body, "scale", Vector3.ONE, 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _shard(pos: Vector3, basis: Basis, size: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = FXToon.crystal_mesh()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("col_core", BlizzardFX.FROSTBITE.core)
	mi.set_instance_shader_parameter("col_mid", BlizzardFX.FROSTBITE.mid)
	mi.set_instance_shader_parameter("col_edge", BlizzardFX.FROSTBITE.edge)
	mi.transform = Transform3D(basis.scaled_local(size), pos)
	_body.add_child(mi)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= BlizzardRules.SPIKE_LIFE:
		BlizzardFX.spike_impact(global_position, BlizzardRules.SPIKE_AURA * 0.7)
		queue_free()
		return
	if _body:
		var left := BlizzardRules.SPIKE_LIFE - _t
		if left < 0.8:   # racha: treme antes de se desfazer
			_body.position = Vector3(sin(_t * 70.0), 0.0, cos(_t * 55.0)) * 0.04
		_puff_t -= delta
		if _puff_t <= 0.0:
			_puff_t = 0.5
			var a := randf() * TAU
			FXToon.puff(global_position + Vector3(cos(a) * 1.0, 0.3, sin(a) * 1.0), randf_range(0.8, 1.2), FXToon.MIST,
				{"vel": Vector3(cos(a) * 0.8, 0.3, sin(a) * 0.8), "grow": 0.3, "hold": 0.3, "fade": 0.7})
	if not deal:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = BlizzardRules.SPIKE_TICK
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead:
			continue
		var d := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length()
		if d <= BlizzardRules.SPIKE_AURA and absf(p.global_position.y - global_position.y) < 3.0:
			p.take_damage(Enemy.vs(level, p, dmg), global_position)
			if p.has_method("apply_chill"):
				p.apply_chill(1.5)
