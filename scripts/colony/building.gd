class_name ColonyBuilding
extends StaticBody3D
## Construção posicionada pelo jogador na Defesa da Cidade. Tem vida, nível e pegada retangular
## (usada para o encaixe, para os monstros acharem o ponto mais próximo e para as estacas).
## Torres procuram o monstro mais próximo e disparam; estacas ferem quem pisa nelas.

signal destroyed(b: ColonyBuilding)

const SHOT := preload("res://scripts/colony/tower_shot.gd")

var kind := "house"
var level := 1
var hp := -1.0
var max_hp := 1.0
var dead := false
var is_core := false
var targetable := true
## Recursos gastos (construção + melhorias), para o reembolso ao demolir.
var invested := {}
var colony: Node
var data: Dictionary
## Cooperativo: id comum entre servidor e clientes; puppet = réplica no cliente (sem disparar nem levar dano).
var net_id := 0
var puppet := false
var net_sent_hp := -1.0
var size := Vector2.ONE

var visual: Node3D
var turret: Node3D
var muzzle: Node3D
var _shape: CollisionShape3D
var _bar_root: Node3D
var _bar_fg: MeshInstance3D
var _cd := 0.0
var _tick := 0.0
var _flash := 0.0
var _t := 0.0
var _hit_sfx := 0.0
var _overlay: StandardMaterial3D
var _turret_y := 0.0


func _ready() -> void:
	data = ColonyData.building(kind)
	size = data.size
	is_core = kind == "town_hall"
	targetable = kind != "spikes"
	add_to_group("buildings")
	# o portão fica numa camada só dos monstros: o jogador e os soldados atravessam
	collision_layer = 32 if kind == "gate" else (0 if kind == "spikes" else 1)
	collision_mask = 0
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = _collision_size()
	_shape.shape = box
	_shape.position = Vector3(0, box.size.y / 2.0, _collision_offset_z())
	add_child(_shape)
	_overlay = StandardMaterial3D.new()
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.albedo_color = Color(1, 0.35, 0.25, 0.55)
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_apply_level(hp < 0.0)
	_make_bar()
	_update_interactable()
	_cd = randf() * 0.5


func _collision_size() -> Vector3:
	match kind:
		"farm":
			return Vector3(1.6, 1.2, 1.0)        # só o depósito bloqueia; a plantação é pisável
		"market":
			return Vector3(4.2, 2.4, 3.6)
		"wall":
			return Vector3(4.0, 3.0, 0.9)
		"gate":
			return Vector3(4.0, 3.4, 1.1)
		"spikes":
			return Vector3(4.0, 0.4, 1.6)
		"archer_tower", "mage_tower":
			return Vector3(2.6, 5.0, 2.6)
		"cannon_tower":
			return Vector3(3.4, 4.0, 3.4)
	return Vector3(size.x - 0.4, 4.0, size.y - 0.4)


func _collision_offset_z() -> float:
	return -2.6 if kind == "farm" else 0.0


func _apply_level(full_hp: bool) -> void:
	var old_max := max_hp
	max_hp = data.hp * ColonyData.level_mult(level, 0.4)
	if full_hp:
		hp = max_hp
	else:
		hp = clampf(hp + (max_hp - old_max if old_max > 1.0 else 0.0), 1.0, max_hp)
	if visual:
		visual.free()
	visual = ColonyVisuals.make(kind, level)
	add_child(visual)
	turret = visual.find_child("Turret", true, false)
	muzzle = visual.find_child("Muzzle", true, false)
	if turret:
		_turret_y = turret.position.y
	if is_core:
		_add_light(Vector3(0, 2.4, 3.6), Color(1, 0.7, 0.35), 2.0, 10.0)
	elif ColonyData.is_tower(kind):
		_add_light(Vector3(0, ColonyVisuals.height(kind) - 1.0, 0), Color(1, 0.7, 0.4) if kind != "mage_tower" else Color(0.5, 0.8, 1.0), 1.2, 8.0)


func _add_light(pos: Vector3, c: Color, energy: float, rng: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	visual.add_child(l)


func set_level(lv: int) -> void:
	level = clampi(lv, 1, ColonyData.MAX_LEVEL)
	_apply_level(false)
	FX.burst(global_position + Vector3.UP * 2.0, Color(1, 0.85, 0.3), 40, 5.0, 0.12, 0.9)
	FX.ring(global_position, Color(1, 0.85, 0.3, 0.9), maxf(size.x, size.y) * 0.7, 0.6)


# ---------------------------------------------------------------- dados das torres
func tower_range() -> float:
	var r := float(data.get("range", 0.0)) + 2.0 * (level - 1)
	if colony and colony.has_method("range_mult"):
		r *= colony.range_mult()
	return r


func tower_damage() -> float:
	return float(data.get("damage", 0.0)) * ColonyData.level_mult(level, 0.45)


func tower_rate() -> float:
	return float(data.get("rate", 1.0)) * (1.0 - 0.08 * (level - 1)) * ColonyData.tower_rate_mult(colony.crew_eff(self))


# ---------------------------------------------------------------- geometria da pegada
## Ponto da pegada mais próximo de p (no plano do chão).
func closest_point(p: Vector3) -> Vector3:
	var local := global_transform.affine_inverse() * p
	local.x = clampf(local.x, -size.x / 2.0, size.x / 2.0)
	local.z = clampf(local.z, -size.y / 2.0, size.y / 2.0)
	local.y = 0.0
	var g := global_transform * local
	g.y = p.y
	return g


func distance_to_point(p: Vector3) -> float:
	var c := closest_point(p)
	return Vector2(c.x - p.x, c.z - p.z).length()


func contains_point(p: Vector3, margin := 0.0) -> bool:
	var local := global_transform.affine_inverse() * p
	return absf(local.x) <= size.x / 2.0 + margin and absf(local.z) <= size.y / 2.0 + margin


# ---------------------------------------------------------------- interação
func _update_interactable() -> void:
	# muros, portões e estacas só aceitam E quando estão danificados (para reparar);
	# assim não "roubam" a interação de quem passa do lado
	var want: bool = not data.get("wall", false) or hp < max_hp - 0.5
	if want and not is_in_group("interactable"):
		add_to_group("interactable")
	elif not want and is_in_group("interactable"):
		remove_from_group("interactable")


func interact_prompt() -> String:
	match kind:
		"town_hall":
			return "Prefeitura — economia e impostos"
		"barracks":
			return "Quartel — recrutar soldados"
	if hp < max_hp - 0.5:
		return "%s Nv %d — reparar / melhorar" % [data.name, level]
	return "%s Nv %d — melhorar" % [data.name, level]


func interact(_player: Node) -> void:
	if colony and colony.world:
		colony.world.open_building_menu(self)


# ---------------------------------------------------------------- dano
func take_damage(amount: float, _from_pos: Vector3) -> void:
	if dead or puppet:
		return
	hp -= amount
	_flash = 0.12
	_bar_root.visible = true
	if _hit_sfx <= 0.0:
		_hit_sfx = 0.35
		Sfx.play_at("hit", global_position, 0.2, -10.0)
		FX.burst(global_position + Vector3.UP * minf(2.0, ColonyVisuals.height(kind) * 0.5),
			Color(0.55, 0.45, 0.35), 6, 3.0, 0.1, 0.5)
	if is_core and colony:
		colony.on_core_hit()
	_update_interactable()
	if hp <= 0.0:
		_destroy()


func repair_full() -> void:
	hp = max_hp
	_update_interactable()
	FX.burst(global_position + Vector3.UP * 1.5, Color(0.5, 1.0, 0.5), 25, 4.0, 0.1, 0.8)


func _destroy() -> void:
	dead = true
	hp = 0.0
	remove_from_group("buildings")
	remove_from_group("interactable")
	collision_layer = 0
	Sfx.play_at("slam", global_position, 0.1, -2.0)
	var c := global_position + Vector3.UP * 1.0
	FX.burst(c, Color(0.5, 0.42, 0.35), 50, 7.0, 0.18, 1.0)
	FX.burst(c, Color(0.3, 0.3, 0.3), 30, 3.0, 0.3, 1.4, -2.0)
	destroyed.emit(self)
	var tw := create_tween()
	tw.tween_property(visual, "position:y", -ColonyVisuals.height(kind), 1.2).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(visual, "rotation:z", 0.25, 1.2)
	tw.tween_callback(queue_free)


## Cliente: vida vinda do servidor (pisca quando cai).
func net_set_hp(v: float) -> void:
	if dead:
		return
	if v < hp - 0.5:
		_flash = 0.12
		_bar_root.visible = true
		if _hit_sfx <= 0.0:
			_hit_sfx = 0.35
			Sfx.play_at("hit", global_position, 0.2, -10.0)
			FX.burst(global_position + Vector3.UP * minf(2.0, ColonyVisuals.height(kind) * 0.5),
				Color(0.55, 0.45, 0.35), 6, 3.0, 0.1, 0.5)
	elif v > hp + 0.5 and v >= max_hp - 0.5:
		FX.burst(global_position + Vector3.UP * 1.5, Color(0.5, 1.0, 0.5), 25, 4.0, 0.1, 0.8)
	hp = clampf(v, 0.0, max_hp)
	if hp < max_hp - 0.5:
		_bar_root.visible = true
	_update_interactable()


## Cliente: o servidor avisou que caiu.
func net_destroy() -> void:
	if not dead:
		_destroy()


func _make_bar() -> void:
	_bar_root = Node3D.new()
	_bar_root.position.y = ColonyVisuals.height(kind) + 0.6
	add_child(_bar_root)
	var w := clampf(size.x * 0.45, 1.4, 3.0)
	var bg := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, 0.16)
	bg.mesh = q
	bg.material_override = _bar_mat(Color(0, 0, 0, 0.7), 0)
	_bar_root.add_child(bg)
	_bar_fg = MeshInstance3D.new()
	var q2 := QuadMesh.new()
	q2.size = Vector2(w - 0.06, 0.1)
	_bar_fg.mesh = q2
	_bar_fg.material_override = _bar_mat(Color(0.3, 0.85, 0.3), 1)
	_bar_root.add_child(_bar_fg)
	_bar_root.visible = false


func _bar_mat(c: Color, priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.no_depth_test = true
	m.render_priority = priority
	return m


# ---------------------------------------------------------------- atualização
func _physics_process(delta: float) -> void:
	if dead:
		return
	_t += delta
	_hit_sfx = maxf(0.0, _hit_sfx - delta)
	if _flash > 0.0:
		_flash -= delta
		_set_overlay(_overlay if _flash > 0.0 else null)
	if _bar_root.visible:
		var r := hp / max_hp
		_bar_fg.scale.x = maxf(0.001, r)
		(_bar_fg.material_override as StandardMaterial3D).albedo_color = Color(0.85, 0.2, 0.15).lerp(Color(0.3, 0.85, 0.3), r)
		if r >= 0.999:
			_bar_root.visible = false
	if kind == "mage_tower" and turret:
		turret.position.y = _turret_y + sin(_t * 2.0) * 0.15
		turret.rotation.y += delta * 1.5
	if ColonyData.is_tower(kind):
		_tower_process(delta)
	elif kind == "spikes" and not puppet:
		_spikes_process(delta)


func _set_overlay(m: Material) -> void:
	for mi in visual.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = m


func _tower_process(delta: float) -> void:
	_cd -= delta
	var rng := tower_range()
	var best: Enemy = null
	var best_d := rng
	for e in colony.live_enemies():
		var d := Vector2(e.global_position.x - global_position.x, e.global_position.z - global_position.z).length()
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		return
	if turret and kind != "mage_tower":
		var to := best.global_position - global_position
		turret.rotation.y = lerp_angle(turret.rotation.y, atan2(to.x, to.z), 1.0 - exp(-10.0 * delta))
	if _cd > 0.0 or puppet:
		return
	_cd = tower_rate()
	var s := SHOT.new()
	s.kind = data.shot
	s.target = best
	s.damage = tower_damage()
	s.splash = float(data.get("splash", 0.0)) * (1.0 + 0.1 * (level - 1))
	s.slow = float(data.get("slow", 0.0))
	s.chain = int(data.get("chain", 0)) + (level - 1 if kind == "mage_tower" else 0)
	get_parent().add_child(s)
	s.global_position = muzzle.global_position if muzzle else global_position + Vector3.UP * 5.0
	if colony.role == "server":
		Lobby.city_shot(s.kind, s.global_position, best, s.splash)
	match kind:
		"cannon_tower":
			Sfx.play_at("explode", global_position, 0.15, -10.0)
			FX.burst(s.global_position, Color(0.6, 0.6, 0.6), 12, 3.0, 0.15, 0.5, 1.0)
		"mage_tower":
			Sfx.play_at("zap", global_position, 0.15, -10.0)
		_:
			Sfx.play_at("swing", global_position, 0.25, -14.0)


func _spikes_process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.5
	var dps: float = data.dps * ColonyData.level_mult(level, 0.5)
	for e in colony.live_enemies():
		if contains_point(e.global_position, e.radius * 0.5):
			e.take_damage(dps * 0.5, e.global_position, false, 0.7)
			hp -= 3.0
			_bar_root.visible = true
	_update_interactable()
	if hp <= 0.0:
		_destroy()
