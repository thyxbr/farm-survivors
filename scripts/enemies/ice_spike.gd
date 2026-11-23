class_name IceSpike
extends Node3D
## Estaca de Gelo (Sentinela da Nevasca): a estaca que caiu do teto fica cravada no chão por BlizzardRules.SPIKE_LIFE
## s soltando frio; quem encosta nela (SPIKE_AURA m) leva um tique a cada SPIKE_TICK s e fica lento. No fim ela
## racha e se desfaz. Servidor e cliente criam a estaca no mesmo ponto; só quem manda no chefe (`deal`: servidor ou
## solo) dá o dano. Desenho: a estaca pintada de ponta para baixo (IceFX.crystal_card), cacos em volta do pé e a geada pintada no chão (IceFX.frost_patch).

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
	# a estaca: a agulha pintada de ponta para baixo, um pouco torta
	var spike := IceFX.crystal_card(_body, IceFX.SPIKE_CELL, IceFX.SPIKE_H, true)
	spike.rotation = Vector3(randf_range(-0.1, 0.1), 0.0, randf_range(-0.1, 0.1))
	for i in 5:   # cacos em volta do pé, de pé e abertos para fora
		var a := TAU * (i + randf_range(-0.3, 0.3)) / 5.0
		var out := Vector3(cos(a), 0.0, sin(a))
		var shard := IceFX.crystal_card(_body, 1 + i % 3, randf_range(0.9, 1.5))
		shard.position = out * randf_range(0.5, 0.85)
		shard.basis = Basis(out.cross(Vector3.UP).normalized(), -randf_range(0.25, 0.55)) * shard.basis
	# a geada pintada no chão marca a área do frio enquanto a estaca dura
	IceFX.frost_patch(BlizzardFX._root(), global_position, BlizzardRules.SPIKE_AURA * 1.15, BlizzardRules.SPIKE_LIFE - 0.3)
	_body.scale = Vector3(1.0, 0.6, 1.0)
	var tw := _body.create_tween()
	tw.tween_property(_body, "scale", Vector3.ONE, 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


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
