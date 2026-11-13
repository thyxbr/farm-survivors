extends Area3D
## Item/ouro largado no chão. É atraído pelo jogador próximo e coletado ao toque.

var item_id := ""   # vazio = ouro
var amount := 1
var _t := 0.0
var _vis: Node3D
var _vel := Vector3.ZERO
var _grounded := false


func _ready() -> void:
	collision_layer = 16
	collision_mask = 2
	var col := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.6
	col.shape = sh
	add_child(col)
	_vis = Node3D.new()
	add_child(_vis)
	var mi := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	var col_c := Color(1, 0.8, 0.2)
	if item_id == "":
		var c := CylinderMesh.new()
		c.top_radius = 0.18
		c.bottom_radius = 0.18
		c.height = 0.05
		mi.mesh = c
		mi.rotation.x = PI / 2
		m.metallic = 1.0
		m.roughness = 0.25
	else:
		var it := ItemDB.get_item(item_id)
		match it.type:
			"weapon":
				var b := BoxMesh.new()
				b.size = Vector3(0.08, 0.8, 0.04)
				mi.mesh = b
				col_c = it.get("color", Color.GRAY)
			"armor", "gear":
				var b := BoxMesh.new()
				b.size = Vector3(0.45, 0.45, 0.2) if it.type == "armor" else Vector3(0.3, 0.3, 0.2)
				mi.mesh = b
				col_c = it.get("color", Color(0.6, 0.6, 0.7))
			"consumable":
				var s := SphereMesh.new()
				s.radius = 0.15
				s.height = 0.3
				mi.mesh = s
				col_c = Color(1, 0.2, 0.25) if it.has("heal_hp") else Color(0.25, 0.4, 1)
			_:
				var s := SphereMesh.new()
				s.radius = 0.13
				s.height = 0.2
				mi.mesh = s
				col_c = Color(0.4, 0.9, 0.4) if item_id == "slime_gel" else Color(0.9, 0.8, 0.5)
				if it.type == "seed":
					col_c = ItemDB.CROPS[it.crop].color
	m.albedo_color = col_c
	m.emission_enabled = true
	m.emission = col_c
	m.emission_energy_multiplier = 0.6
	mi.material_override = m
	_vis.add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = col_c
	light.light_energy = 0.8
	light.omni_range = 1.6
	_vis.add_child(light)
	# feixe de luz para equipamentos raros ou melhores (cor da raridade)
	if item_id != "" and ItemDB.is_equippable(item_id) and ItemDB.RARITY[ItemDB.rarity_of(item_id)].rank >= 2:
		var rc := ItemDB.rarity_color(item_id)
		var beam := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.02
		cyl.bottom_radius = 0.09
		cyl.height = 3.5
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.albedo_color = Color(rc.r, rc.g, rc.b, 0.35)
		bm.cull_mode = BaseMaterial3D.CULL_DISABLED
		cyl.material = bm
		beam.mesh = cyl
		beam.position.y = 1.6
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(beam)
		light.light_color = rc
		light.light_energy = 1.6
		light.omni_range = 2.6
	body_entered.connect(_on_body)
	_vel = Vector3(randf_range(-2, 2), 5.0, randf_range(-2, 2))


func _physics_process(delta: float) -> void:
	_t += delta
	var player := get_tree().get_first_node_in_group("player") as Player
	if _t > 0.6 and player and not player.dead:
		var to := player.global_position + Vector3.UP * 0.8 - global_position
		if to.length() < 1.0:
			_collect()
			return
		if to.length() < 3.5:
			global_position += to.normalized() * min(to.length(), (12.0 - to.length() * 2.0) * delta)
			_grounded = true
	if not _grounded:
		_vel.y -= 16.0 * delta
		global_position += _vel * delta
		if global_position.y <= 0.35:
			global_position.y = 0.35
			_grounded = true
	_vis.rotation.y += delta * 2.5
	_vis.position.y = sin(_t * 3.0) * 0.1
	if _t > 120.0:
		queue_free()


func _on_body(body: Node) -> void:
	if body.is_in_group("player") and _t >= 0.4:
		_collect()


func _collect() -> void:
	if is_queued_for_deletion():
		return
	if item_id == "":
		Game.add_gold(amount)
		Game.notify.emit("+%d ouro" % amount, Color(1, 0.85, 0.3))
		Sfx.play("coin")
	else:
		Game.add_item(item_id, amount)
		Sfx.play("pickup")
	queue_free()
