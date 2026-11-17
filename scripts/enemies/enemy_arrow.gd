extends Node3D
## Projétil dos inimigos à distância: flecha (arqueiros) ou orbe mágico (`magic`, Esqueleto Mago). No solo e
## no servidor causa dano: na Horda, em quem o modo sobrevivência persegue (source.targets()); no mundo e na
## cidade, nos jogadores do mesmo mundo 3D. A réplica no cliente usa damage = 0 e só desenha.
## Para no ar enquanto o grupo escolhe as cartas de nível (frozen).

const SPEED := 17.0
const LIFE := 1.6
const HIT_RADIUS := 0.85

var direction := Vector3.FORWARD
var damage := 0.0
## Nível de quem atirou (0 = sem nível): ao acertar, aplica o bônus do monstro bem acima do alvo (Enemy.vs).
var level := 0
## survival_mode (solo/servidor) ou o mundo (réplica no cliente).
var source: Node
## Orbe roxo no lugar da flecha.
var magic := false
## Bola de teia (Tecelã): ao acertar, prende o jogador por web_secs (Player.apply_web).
var web := false
var web_secs := 0.0
var _life := LIFE


func _ready() -> void:
	direction.y = 0.0
	direction = direction.normalized() if direction.length() > 0.01 else Vector3.FORWARD
	if magic:
		_build_orb()
		return
	if web:
		_build_web()
		return
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


func _build_web() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.93, 0.93, 0.97)
	var ball := SphereMesh.new()
	ball.radius = 0.16
	ball.height = 0.32
	ball.radial_segments = 8
	ball.rings = 4
	ball.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = ball
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	for k in 3:   # fios soltos girando em volta da bola
		var fio := CylinderMesh.new()
		fio.top_radius = 0.012
		fio.bottom_radius = 0.012
		fio.height = 0.55
		fio.radial_segments = 4
		fio.material = m
		var f := MeshInstance3D.new()
		f.mesh = fio
		f.rotation = Vector3(k * 1.1, k * 0.7, PI / 2 + k * 0.9)
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(f)


func _build_orb() -> void:
	var mi := MeshInstance3D.new()
	var orb := SphereMesh.new()
	orb.radius = 0.2
	orb.height = 0.4
	orb.radial_segments = 8
	orb.rings = 4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.75, 0.45, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.6, 0.25, 1.0)
	m.emission_energy_multiplier = 2.5
	orb.material = m
	mi.mesh = orb
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = Color(0.65, 0.35, 1.0)
	light.light_energy = 1.2
	light.omni_range = 3.0
	add_child(light)


## Quem o projétil pode acertar.
func _targets() -> Array:
	if source.has_method("targets"):
		return source.targets()
	var w := get_world_3d()
	return get_tree().get_nodes_in_group("players").filter(func(p): return p.get_world_3d() == w)


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
	if web:
		rotate_y(9.0 * delta)
	if magic and Engine.get_physics_frames() % 3 == 0:
		FX.burst(global_position, Color(0.7, 0.4, 1.0), 2, 0.8, 0.07, 0.35)
	if damage <= 0.0 or source == null or not is_instance_valid(source):
		return
	for p in _targets():
		if p.dead:
			continue
		var c: Vector3 = p.global_position + Vector3.UP * 1.0
		if c.distance_to(global_position) <= HIT_RADIUS:
			p.take_damage(Enemy.vs(level, p, damage), global_position - direction)
			if web and p.has_method("apply_web"):
				p.apply_web(web_secs)
			FX.burst(global_position, Color(0.93, 0.93, 0.97) if web else Color(0.7, 0.4, 1.0) if magic
				else Color(0.7, 0.5, 0.3), 8, 2.5, 0.08, 0.4)
			queue_free()
			return
