extends Node3D
## Projétil dos inimigos à distância: flecha (arqueiros), orbe mágico (`magic`: a Esfera Sombria do Esqueleto
## Mago, ácido, gelo) ou lâmina rúnica (`blade`, Arauto do Abismo). No solo e
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
## Cuspe de ácido (Mãe-Verme): o orbe verde (com `magic`).
var acid := false
const BLADE_TRAIL := {"core": Color(0.12, 0.0, 0.01), "mid": Color(0.7, 0.05, 0.05), "edge": Color(1.0, 0.3, 0.2)}
const ACID := {"core": Color(0.08, 0.14, 0.02), "mid": Color(0.3, 0.6, 0.05), "edge": Color(0.65, 1.0, 0.25)}
## Faísca do projétil batendo na Égide Cristalina (azul e branco, como a barreira).
const AEGIS_SPARK := {"core": Color(0.2, 0.35, 0.8), "mid": Color(0.45, 0.75, 1.0), "edge": Color(0.9, 0.97, 1.0)}
## Estilhaço de gelo (Gralha-de-Cristal): o orbe azul-gelo (com `magic`); ao acertar deixa o jogador lento por
## `chill` segundos (Player.apply_chill).
var ice := false
var chill := 0.0
## Bola de teia (Tecelã): ao acertar, prende o jogador por web_secs (Player.apply_web).
var web := false
## Lâmina rúnica (Rajada de Sombras do Arauto do Abismo): no lugar do orbe, uma lâmina de RuneBladesFX apontada
## para onde voa; ao acertar, o estouro dela.
var blade := false
var web_secs := 0.0
var _life := LIFE


func _ready() -> void:
	direction.y = 0.0
	direction = direction.normalized() if direction.length() > 0.01 else Vector3.FORWARD
	if blade:
		_build_blade()
		return
	if magic:
		_build_orb()
		# rastro desenhado atrás do orbe (lê `direction`)
		FXToon.comet(self, _pal(), 1.6, 0.16, false)      # miolo escuro, borda acesa: o traço dos monstros
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
	FXToon.comet(self, FXToon.THORN, 1.3, 0.05, false)      # risco escuro atrás da flecha
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


func _build_blade() -> void:
	if FX._scene() == null:
		return
	var b := RuneBladesFX.make_blade(1.9)
	add_child(b)
	b.basis = RuneBladesFX.basis_along(direction)
	FXToon.comet(self, BLADE_TRAIL, 1.8, 0.1, false)


func _build_orb() -> void:
	if not acid and not ice:   # a ameaça roxa dos magos: a Esfera Sombria (traz a própria luz)
		if FX._scene() != null:
			var o := ShadowOrbFX.new()
			o.radius = 0.42
			add_child(o)
		return
	var mi := MeshInstance3D.new()
	var orb := SphereMesh.new()
	orb.radius = 0.2
	orb.height = 0.4
	orb.radial_segments = 8
	orb.rings = 4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.25, 0.55, 0.08) if acid else Color(0.75, 0.93, 1.0) if ice else Color(0.12, 0.03, 0.14)      # miolo escuro; a borda acesa vem do rastro e da luz
	orb.material = m
	mi.mesh = orb
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 1.0, 0.25) if acid else Color(0.45, 0.85, 1.0) if ice else Color(0.65, 0.35, 1.0)
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
	var from := global_position
	global_position += direction * SPEED * delta
	if web:
		rotate_y(9.0 * delta)
	# Égide Cristalina erguida: o projétil para na coroa (réplica também, para o desenho bater) e o golpe vai
	# para o escudo de quem ergueu (só quem decide aplica dano)
	var wall := AegisWalls.crossing(from, global_position, self)
	if not wall.is_empty():
		var caster: Node = wall.caster
		if damage > 0.0 and source != null and is_instance_valid(source) and not caster.dead:
			caster.take_damage(Enemy.vs(level, caster, damage), wall.point - direction)
		FXToon.spark_hit(wall.point, -direction, AEGIS_SPARK, 6, 0.9)
		queue_free()
		return
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
			if chill > 0.0 and p.has_method("apply_chill"):
				p.apply_chill(chill)
			if blade:
				RuneBladesFX.impact(FX._scene(), global_position)
			elif magic:
				FXToon.spark_hit(global_position, direction, _pal(), 6, 1.1)
			elif web:
				FXToon.hit_splat(global_position, Color(0.93, 0.93, 0.97), 6)
			else:
				FXToon.spark_hit(global_position, direction, FXToon.THORN, 4, 0.6)
			queue_free()
			return


## Cores do orbe: ácido, gelo ou a ameaça roxa dos magos.
func _pal() -> Dictionary:
	return ACID if acid else FXToon.ICE if ice else FXToon.MENACE
