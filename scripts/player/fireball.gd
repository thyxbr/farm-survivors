extends Area3D
## Bola de fogo: voa reto, explode ao tocar em inimigo ou cenário causando dano em área.

var direction := Vector3.FORWARD
var damage := 20.0
var speed := 24.0
var life := 3.0
## Multiplayer: bola de fogo de outro jogador — só o visual, sem dano.
var visual_only := false
## Desafio da Horda: chamado com a posição da explosão (gatilho dos combos em grupo).
var on_explode := Callable()
var _done := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | 4
	var col := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.3
	col.shape = sh
	add_child(col)
	FXToon.comet(self, FXToon.FIRE)     # cabeça na frente, cauda para trás: lê `direction` a cada quadro
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 3.0
	light.omni_range = 5.0
	add_child(light)
	body_entered.connect(_on_body)


func _physics_process(delta: float) -> void:
	if _done:
		return
	global_position += direction * speed * delta
	life -= delta
	if life <= 0:
		_explode()


func _on_body(body: Node) -> void:
	if body.is_in_group("player"):
		return
	_explode()


func _explode() -> void:
	if _done:
		return
	_done = true
	set_deferred("monitoring", false)
	FXToon.fire_burst(global_position)
	Sfx.play_at("explode", global_position)
	if visual_only:
		queue_free()
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var d: float = e.global_position.distance_to(global_position)
		if d <= 1.0 + e.radius + 0.6:
			var dmg_full := damage * randf_range(0.9, 1.1)
			e.take_damage(dmg_full, global_position - direction, false)
			Game.add_fury_from_damage(dmg_full, e.max_hp)
		elif d <= 2.5 + e.radius:
			e.take_damage(damage * 0.5, global_position - direction, false)
			Game.add_fury_from_damage(damage * 0.5, e.max_hp)
	if on_explode.is_valid():
		on_explode.call(global_position)
	queue_free()
