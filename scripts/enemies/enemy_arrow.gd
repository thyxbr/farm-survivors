extends Node3D
## Flecha do Goblin Arqueiro (Desafio da Horda). No solo e no servidor causa dano nos jogadores
## que o modo sobrevivência persegue (source.targets()); a réplica no cliente usa damage = 0 e só desenha.
## Para no ar enquanto o grupo escolhe as cartas de nível (frozen).

const SPEED := 17.0
const LIFE := 1.6
const HIT_RADIUS := 0.85

var direction := Vector3.FORWARD
var damage := 0.0
## survival_mode (solo/servidor) ou o mundo (réplica no cliente).
var source: Node
var _life := LIFE


func _ready() -> void:
	direction.y = 0.0
	direction = direction.normalized() if direction.length() > 0.01 else Vector3.FORWARD
	var mi := MeshInstance3D.new()
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.035
	shaft.bottom_radius = 0.035
	shaft.height = 0.9
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.3, 0.15)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.55, 0.2)
	m.emission_energy_multiplier = 0.6
	shaft.material = m
	mi.mesh = shaft
	mi.rotation.x = PI / 2
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var tip := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.08
	cone.height = 0.2
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.75, 0.75, 0.8)
	tm.metallic = 0.8
	cone.material = tm
	tip.mesh = cone
	tip.rotation.x = PI / 2
	tip.position.z = 0.5
	add_child(tip)
	look_at(global_position + direction, Vector3.UP)
	rotate_object_local(Vector3.UP, PI)   # o +Z local (ponta) aponta para a frente


func _frozen() -> bool:
	if source == null or not is_instance_valid(source):
		return false
	if source.get("frozen") == true:
		return true
	var sv = source.get("survival")
	return sv != null and is_instance_valid(sv) and sv.get("frozen") == true


func _physics_process(delta: float) -> void:
	if _frozen():
		return
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	global_position += direction * SPEED * delta
	if damage <= 0.0 or source == null or not is_instance_valid(source) or not source.has_method("targets"):
		return
	for p in source.targets():
		if p.dead:
			continue
		var c: Vector3 = p.global_position + Vector3.UP * 1.0
		if c.distance_to(global_position) <= HIT_RADIUS:
			p.take_damage(damage, global_position - direction)
			FX.burst(global_position, Color(0.7, 0.5, 0.3), 8, 2.5, 0.08, 0.4)
			queue_free()
			return
