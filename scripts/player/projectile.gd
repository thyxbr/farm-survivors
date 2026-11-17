extends Area3D
## Projétil do ataque básico: "bolt" (cajado, faísca arcana) ou "arrow" (arco, com leve queda).
## fx: "slow" deixa o alvo lento, "splash" explode em área, "pierce" atravessa inimigos.

var kind := "bolt"
var direction := Vector3.FORWARD
var damage := 10.0
var speed := 30.0
var color := Color(0.6, 0.8, 1.0)
var fx := ""
## Cajado: elemento do som do impacto (Sfx.staff_element): arcane, fire ou frost.
var element := "arcane"
var crit := false
var pierce := 0
var life := 1.6
## Multiplayer: projétil de outro jogador — só o visual, sem dano.
var visual_only := false
## Flecha: queda (m/s²). player.arrow_launch compensa na mira.
const ARROW_DROP := 4.0
## Deslocamento do visual em relação à posição real no disparo (a flecha nasce na linha da câmera, mas aparece
## saindo do arco); some em VIS_SETTLE segundos.
var vis_offset := Vector3.ZERO
const VIS_SETTLE := 0.12
var _age := 0.0
var _vel := Vector3.ZERO
var _done := false
var _hit := {}
var _vis: Node3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | 4
	var col := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.22 if kind == "bolt" else 0.16
	col.shape = sh
	add_child(col)
	_vel = direction.normalized() * speed
	_vis = Node3D.new()
	add_child(_vis)
	if kind == "arrow":
		_build_arrow()
	else:
		_build_bolt()
	body_entered.connect(_on_body)
	_orient()


func _build_bolt() -> void:
	# faísca desenhada: esfera de energia na cor da arma, com um rastro fino para trás (lê `direction`)
	var pal := FXToon.palette(color)
	FXToon.comet(self, pal, 1.7, 0.13, false, _vis)
	FXToon.orb(_vis, pal, 0.62)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 2.0
	light.omni_range = 3.5
	add_child(light)


func _build_arrow() -> void:
	var shaft := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.012
	c.bottom_radius = 0.012
	c.height = 0.8
	c.radial_segments = 6
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.55, 0.4, 0.22)
	c.material = wm
	shaft.mesh = c
	shaft.rotation.x = PI / 2
	_vis.add_child(shaft)
	var head := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.03
	cone.height = 0.1
	cone.radial_segments = 6
	var hm := StandardMaterial3D.new()
	hm.albedo_color = color
	hm.emission_enabled = true
	hm.emission = color
	hm.emission_energy_multiplier = 1.5
	cone.material = hm
	head.mesh = cone
	head.rotation.x = PI / 2
	head.position.z = 0.44
	_vis.add_child(head)
	# rastro desenhado atrás da flecha (lê `direction`, que acompanha a queda): fino e claro; a Flecha
	# Glacial leva um rastro de gelo mais gordo
	if fx == "glacial":
		FXToon.comet(self, FXToon.ICE, 2.6, 0.17, false, _vis)
	else:
		FXToon.comet(self, FXToon.light_palette(color), 1.7, 0.05, false, _vis)


func _orient() -> void:
	if _vel.length() > 0.01:
		var up := Vector3.UP if abs(_vel.normalized().dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
		_vis.look_at(global_position + _vel if is_inside_tree() else _vel, up, true)


func _physics_process(delta: float) -> void:
	if _done:
		return
	if kind == "arrow":
		_vel.y -= ARROW_DROP * delta
		direction = _vel.normalized()      # o rastro desenhado segue a queda
	global_position += _vel * delta
	_age += delta
	if vis_offset != Vector3.ZERO:
		var k := 1.0 - smoothstep(0.0, VIS_SETTLE, _age)
		_vis.position = vis_offset * k
		if k <= 0.0:
			vis_offset = Vector3.ZERO
	_orient()
	life -= delta
	if life <= 0:
		_finish(false)


func _on_body(body: Node) -> void:
	if _done or body.is_in_group("player") or body.is_in_group("players"):
		return
	if body.is_in_group("enemies"):
		if body.dead or _hit.has(body.get_instance_id()):
			return
		_hit[body.get_instance_id()] = true
		if fx != "splash":
			Sfx.play_at(_hit_sound(), global_position, 0.1, -2.0)
		if not visual_only:
			_damage(body, damage)
		if fx == "splash":
			_finish(true)
		elif pierce > 0:
			pierce -= 1
			damage *= 0.85
			if kind == "bolt":
				FXToon.energy_pop(global_position, _vel.normalized(), FXToon.palette(color), 3, 0.7)
			else:
				FXToon.spark_hit(global_position, _vel.normalized(), FXToon.light_palette(color), 2, 0.5)
		else:
			_finish(true)
		return
	if fx != "splash":
		Sfx.play_at(_hit_sound(), global_position, 0.1, -9.0)
	_finish(fx == "splash")


## Flecha: ponta acertando; faísca do cajado: impacto do elemento.
func _hit_sound() -> String:
	return "arrow_hit" if kind == "arrow" else element + "_hit"


func _damage(e: Node, amount: float) -> void:
	var dmg := EnchantHit.scale(e, amount * randf_range(0.9, 1.1))
	if fx == "glacial":
		# Flecha Glacial: prende 1,5 s e atrasa 3 s (chefes ignoram a prisão em apply_stun); gelo no alvo
		e.take_damage(dmg, global_position - _vel.normalized(), crit, 3.0, 1.5)
		_ice_fx(e)
	else:
		e.take_damage(dmg, global_position - _vel.normalized(), crit, 2.5 if fx == "slow" else 0.0)
	Game.on_damage_dealt(dmg, e.max_hp)
	EnchantHit.on_hit(e, dmg)   # efeito do elemento da arma encantada


## Gelo no alvo: cristais fecham em volta dele enquanto fica preso (FXToon.frost_hit).
func _ice_fx(e: Node) -> void:
	FXToon.frost_hit(e.global_position, 1.3, maxf(1.0, float(e.radius) + 0.6))
	Sfx.play_at("frost_hit", e.global_position + Vector3.UP * 0.6, 0.1, -4.0)


func _finish(impact: bool) -> void:
	if _done:
		return
	_done = true
	set_deferred("monitoring", false)
	if fx == "splash" and impact:
		if kind == "bolt" and element == "fire":
			FXToon.fire_burst(global_position, 0.85)
		elif kind == "bolt":
			FXToon.energy_burst(global_position, FXToon.palette(color))
		else:
			FXToon.energy_burst(global_position, FXToon.palette(color))
		Sfx.play_at("explode", global_position, 0.1, -6.0)
		if not visual_only:
			for e in get_tree().get_nodes_in_group("enemies"):
				if e.dead or _hit.has(e.get_instance_id()):
					continue
				if e.global_position.distance_to(global_position) <= 2.4 + e.radius:
					_damage(e, damage * 0.6)
	elif kind == "bolt":
		FXToon.energy_pop(global_position, _vel.normalized(), FXToon.palette(color))
	else:
		FXToon.spark_hit(global_position, _vel.normalized(), FXToon.light_palette(color), 4, 0.6)
	queue_free()
