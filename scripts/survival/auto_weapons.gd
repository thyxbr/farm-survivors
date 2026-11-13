extends Node3D
## Armas automáticas do Desafio da Horda. Fica como filho do jogador durante a partida.
## No multiplayer, a réplica de outro jogador ganha uma cópia só visual (visual_only): lâminas e aura
## giram em volta dela; orbes e raios chegam como eventos ("fireball" / "zap").

const FIREBALL := preload("res://scripts/player/fireball.gd")
const UPG := preload("res://scripts/survival/upgrades.gd")

var player: Player
var levels := {}          # id -> nível (1..5)
var _timers := {"fogo": 0.5, "raio": 1.0, "aura": 0.0}
var _blade_pivot: Node3D
var _blades: Array[MeshInstance3D] = []
var _blade_hits := {}     # instance_id -> tempo até poder acertar de novo
var _aura: MeshInstance3D
var _aura_mat: StandardMaterial3D
var _t := 0.0
## Réplica de outro jogador: só desenha, não causa dano.
var visual_only := false
## Raio extra (passiva "área") do dono, recebido junto com os níveis.
var area_override := 1.0
## Modo sobrevivência (lê os combos ativos do grupo). Nulo nas réplicas.
var survival: Node = null
var _combo_cd := {}       # combo -> recarga restante


func _ready() -> void:
	player = get_parent() as Player


func set_level(id: String, lv: int) -> void:
	levels[id] = lv
	match id:
		"laminas":
			_build_blades()
		"aura":
			_build_aura()


func _area() -> float:
	return area_override if visual_only else Game.mod("area")


## Multiplayer: avisa os outros jogadores quais armas giram em volta deste personagem.
func send_gear() -> void:
	if visual_only or not Network.is_client():
		return
	Network.send_event("horde_gear",
		Vector3(levels.get("fogo", 0), levels.get("laminas", 0), levels.get("raio", 0)),
		Vector3(levels.get("aura", 0), Game.mod("area"), 0))


func clear_gear() -> void:
	if not visual_only and Network.is_client():
		Network.send_event("horde_gear", Vector3.ZERO, Vector3.ZERO)


## Réplica: aplica os níveis recebidos em send_gear().
func apply_gear(a: Vector3, b: Vector3) -> void:
	area_override = b.y if b.y > 0.0 else 1.0
	var want := {"fogo": int(a.x), "laminas": int(a.y), "raio": int(a.z), "aura": int(b.x)}
	for id in want:
		var lv: int = clampi(want[id], 0, 5)
		if lv > 0 and levels.get(id, 0) != lv:
			set_level(id, lv)


func _physics_process(delta: float) -> void:
	if player == null or player.dead:
		return
	_t += delta
	if visual_only:
		if levels.has("aura"):
			_update_aura(delta)
		if levels.has("laminas"):
			_update_blades(delta)
		return
	var cd_mult: float = max(0.35, Game.mod("cooldown"))
	for id in _timers:
		_timers[id] -= delta
	for id in _combo_cd:
		_combo_cd[id] -= delta
	if levels.has("fogo") and _timers.fogo <= 0.0:
		_timers.fogo = [1.8, 1.5, 1.5, 1.25, 1.1][levels.fogo - 1] * cd_mult
		_fire_orbs()
	if levels.has("raio") and _timers.raio <= 0.0:
		_timers.raio = [2.6, 2.4, 2.1, 2.0, 1.7][levels.raio - 1] * cd_mult
		_lightning()
	if levels.has("aura"):
		_update_aura(delta)
	if levels.has("laminas"):
		_update_blades(delta)


# ------------------------------------------------------------ utilidades
func _damage(base: float) -> Array:
	var crit: bool = randf() < 0.05 + Game.mod("crit")
	return [base * Game.damage_mult() * randf_range(0.9, 1.1) * (1.8 if crit else 1.0), crit]


func _enemies_by_distance(max_dist: float) -> Array:
	var out: Array = []
	var p := player.global_position
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var d: float = e.global_position.distance_to(p)
		if d <= max_dist:
			out.append([d, e])
	out.sort_custom(func(a, b) -> bool: return a[0] < b[0])
	return out


# ------------------------------------------------------------ Orbe de Fogo
func _fire_orbs() -> void:
	var lv: int = levels.fogo
	var count: int = [1, 1, 2, 2, 3][lv - 1]
	var dmg: float = [16.0, 21.0, 24.0, 30.0, 38.0][lv - 1]
	var targets := _enemies_by_distance(20.0)
	if targets.is_empty():
		return
	var origin := player.global_position + Vector3.UP * 1.3
	for i in count:
		var e: Enemy = targets[i % targets.size()][1]
		var aim := e.global_position + Vector3.UP * 0.5
		var dir := (aim - origin).normalized()
		if i >= targets.size():
			dir = dir.rotated(Vector3.UP, 0.25 * (i - targets.size() + 1))
		var fb := FIREBALL.new()
		fb.direction = dir
		fb.damage = _damage(dmg)[0]
		fb.speed = 20.0
		fb.on_explode = Callable(self, "_on_orb_explode")
		get_tree().current_scene.add_child(fb)
		fb.global_position = origin + Vector3(dir.x, 0, dir.z).normalized() * 0.5
		Network.send_event("fireball", fb.global_position, dir)
	Sfx.play("fire", 0.15, -9.0)


# ------------------------------------------------------------ Relâmpago
func _lightning() -> void:
	var lv: int = levels.raio
	var n: int = [1, 2, 2, 3, 5][lv - 1]
	var dmg: float = [22.0, 26.0, 34.0, 38.0, 50.0][lv - 1]
	var near := _enemies_by_distance(16.0 * _area())
	if near.is_empty():
		return
	near.shuffle()
	var first: Vector3 = near[0][1].global_position
	for i in min(n, near.size()):
		var e: Enemy = near[i][1]
		var d := _damage(dmg)
		bolt_fx(get_tree().current_scene, e.global_position)
		Network.send_event("zap", e.global_position)
		e.take_damage(d[0], e.global_position, d[1])
	Sfx.play("zap", 0.15, -4.0)
	_combo("raio", first)


static func bolt_fx(root: Node, pos: Vector3) -> void:
	if root == null:
		return
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.14
	cyl.height = 14.0
	cyl.radial_segments = 6
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.75, 0.9, 1.0, 1.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(0.5, 0.8, 1.0)
	m.emission_energy_multiplier = 6.0
	cyl.material = m
	mi.mesh = cyl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = pos + Vector3.UP * 7.0
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 0.25)
	tw.tween_callback(mi.queue_free)
	FX.burst(pos + Vector3.UP * 0.3, Color(0.6, 0.85, 1.0), 14, 5.0, 0.08, 0.35)


# ------------------------------------------------------------ Lâminas Orbitais
func _blade_stats() -> Dictionary:
	var lv: int = levels.laminas
	return {
		"count": [2, 3, 3, 4, 5][lv - 1],
		"dmg": [8.0, 9.0, 11.0, 12.0, 15.0][lv - 1],
		"radius": [2.1, 2.1, 2.5, 2.6, 2.8][lv - 1] * _area(),
		"speed": [3.0, 3.0, 3.2, 3.8, 4.0][lv - 1],
	}


func _build_blades() -> void:
	if _blade_pivot == null:
		_blade_pivot = Node3D.new()
		_blade_pivot.position.y = 0.9
		add_child(_blade_pivot)
	for b in _blades:
		b.queue_free()
	_blades.clear()
	var st := _blade_stats()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.1, 0.05, 1.0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.85, 1.0)
	m.metallic = 0.9
	m.roughness = 0.2
	m.emission_enabled = true
	m.emission = Color(0.4, 0.6, 1.0)
	m.emission_energy_multiplier = 1.5
	mesh.material = m
	for i in st.count:
		var b := MeshInstance3D.new()
		b.mesh = mesh
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_blade_pivot.add_child(b)
		_blades.append(b)


func _update_blades(delta: float) -> void:
	var st := _blade_stats()
	_blade_pivot.rotation.y += st.speed * delta
	var n := _blades.size()
	for i in n:
		var a := TAU * i / n
		var b := _blades[i]
		b.position = Vector3(cos(a), 0, sin(a)) * st.radius
		b.rotation.y = -a  # alinhada com a direção do giro
	if visual_only:
		return
	for k in _blade_hits.keys():
		_blade_hits[k] -= delta
		if _blade_hits[k] <= 0.0:
			_blade_hits.erase(k)
	var ppos := player.global_position
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var to: Vector3 = e.global_position - ppos
		to.y = 0
		if abs(to.length() - st.radius) > 0.9 + e.radius:
			continue
		var id: int = e.get_instance_id()
		if _blade_hits.has(id):
			continue
		for b in _blades:
			var bp := b.global_position
			if Vector2(bp.x - e.global_position.x, bp.z - e.global_position.z).length() < 0.75 + e.radius:
				var d := _damage(st.dmg)
				var hit_pos: Vector3 = e.global_position
				e.take_damage(d[0], ppos, d[1])
				_blade_hits[id] = 0.4
				_combo("laminas", hit_pos)
				break


# ------------------------------------------------------------ Aura Gélida
func _aura_radius() -> float:
	return [2.4, 2.8, 3.2, 3.6, 4.0][levels.aura - 1] * _area()


func _build_aura() -> void:
	if _aura == null:
		_aura = MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 1.0
		disc.bottom_radius = 1.0
		disc.height = 0.03
		disc.radial_segments = 40
		_aura_mat = StandardMaterial3D.new()
		_aura_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_aura_mat.albedo_color = Color(0.45, 0.8, 1.0, 0.18)
		_aura_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_aura_mat.emission_enabled = true
		_aura_mat.emission = Color(0.4, 0.8, 1.0)
		disc.material = _aura_mat
		_aura.mesh = disc
		_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_aura.position.y = 0.08
		add_child(_aura)


func _update_aura(delta: float) -> void:
	var r := _aura_radius()
	_aura.scale = Vector3(r, 1, r)
	_aura_mat.albedo_color.a = 0.14 + 0.06 * sin(_t * 4.0)
	if visual_only or _timers.aura > 0.0:
		return
	_timers.aura = 0.5
	var lv: int = levels.aura
	var dmg: float = [5.0, 6.5, 8.5, 9.5, 13.0][lv - 1]
	var slow: float = 0.7 if lv < 4 else 1.2
	var hit_any := false
	for item in _enemies_by_distance(r + 1.0):
		var e: Enemy = item[1]
		if item[0] > r + e.radius:
			continue
		var d := _damage(dmg)
		if not hit_any:
			hit_any = true
			_combo("aura", e.global_position)
		e.take_damage(d[0], e.global_position, d[1], slow)   # dano e lentidão numa mensagem só


# ------------------------------------------------------------ combos em grupo
func _on_orb_explode(pos: Vector3) -> void:
	_combo("fogo", pos)


## Ataque da arma weapon_id acertou em pos: dispara os combos ativos (colega perto com a arma par).
func _combo(weapon_id: String, pos: Vector3) -> void:
	if visual_only or survival == null or player == null or player.dead:
		return
	var active: Dictionary = survival.active_combos
	for cid in active:
		var c: Dictionary = active[cid]
		if not c.near or not (weapon_id in c.mine) or _combo_cd.get(cid, 0.0) > 0.0:
			continue
		_combo_cd[cid] = UPG.COMBO_COOLDOWN * maxf(0.5, Game.mod("cooldown"))
		combo_strike(cid, pos, int(levels.get(weapon_id, 1)) + int(c.plv))
		survival.combos_done += 1


## Efeito do combo: dano escala com a soma dos níveis das duas armas (a sua e a do colega).
func combo_strike(cid: String, pos: Vector3, total_lv: int) -> void:
	var c: Dictionary = UPG.COMBOS[cid]
	var power := 1.0 + 0.15 * maxf(0.0, total_lv - 2)
	var root := get_tree().current_scene
	combo_fx(root, cid, pos)
	Network.send_event("combo", pos, Vector3(UPG.COMBOS.keys().find(cid), 0, 0))
	var slow: float = c.slow
	match c.shape:
		"area":
			for item in _enemies_near(pos, c.radius):
				var e: Enemy = item[1]
				var d := _damage(c.dmg * power)
				e.take_damage(d[0], pos, d[1], slow)
		"chain":
			var from := pos
			var hit := {}
			for i in int(c.n):
				var best: Enemy = null
				var best_d := INF
				for item in _enemies_near(from, c.radius):
					var e: Enemy = item[1]
					if not hit.has(e.get_instance_id()) and item[0] < best_d:
						best_d = item[0]
						best = e
				if best == null:
					break
				hit[best.get_instance_id()] = true
				var to := best.global_position
				_arc_fx(root, from + Vector3.UP * 0.8, to + Vector3.UP * 0.8, c.color)
				var d := _damage(c.dmg * power)
				best.take_damage(d[0], from, d[1], slow)
				from = to
		"strikes":
			var near := _enemies_near(pos, c.radius)
			near.shuffle()
			for i in min(int(c.n), near.size()):
				var e: Enemy = near[i][1]
				bolt_fx(root, e.global_position)
				var d := _damage(c.dmg * power)
				e.take_damage(d[0], e.global_position, d[1], slow)


func _enemies_near(pos: Vector3, max_dist: float) -> Array:
	var out: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var d: float = e.global_position.distance_to(pos)
		if d <= max_dist + e.radius:
			out.append([d, e])
	return out


## Visual do combo (também nas réplicas): anel e faíscas nas cores das duas armas e o nome do combo.
static func combo_fx(root: Node, cid: String, pos: Vector3) -> void:
	if root == null or not UPG.COMBOS.has(cid):
		return
	var c: Dictionary = UPG.COMBOS[cid]
	var ca: Color = UPG.WEAPONS[c.a].color
	var cb: Color = UPG.WEAPONS[c.b].color
	var r: float = c.radius if c.shape == "area" else 2.5
	FX.ring(pos + Vector3.UP * 0.1, Color(ca.r, ca.g, ca.b, 0.9), r, 0.45)
	FX.ring(pos + Vector3.UP * 0.15, Color(cb.r, cb.g, cb.b, 0.8), r * 0.7, 0.55)
	FX.burst(pos + Vector3.UP * 0.5, ca, 18, 6.0, 0.12, 0.5)
	FX.burst(pos + Vector3.UP * 0.5, cb, 18, 5.0, 0.12, 0.6)
	FX.damage_number(pos + Vector3.UP * 2.6, c.name + "!", c.color, 40)
	Sfx.play_at("explode" if c.shape == "area" else "zap", pos, 0.1, -6.0)


## Réplica: evento "combo" de outro jogador (índice do combo em UPG.COMBOS).
static func combo_fx_index(root: Node, idx: int, pos: Vector3) -> void:
	var keys := UPG.COMBOS.keys()
	if idx >= 0 and idx < keys.size():
		combo_fx(root, keys[idx], pos)


static func _arc_fx(root: Node, a: Vector3, b: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var len := a.distance_to(b)
	if len < 0.05:
		return
	var box := BoxMesh.new()
	box.size = Vector3(0.09, 0.09, len)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col.r, col.g, col.b, 1.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 5.0
	box.material = m
	mi.mesh = box
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = (a + b) * 0.5
	mi.look_at(b, Vector3.UP if absf((b - a).normalized().y) < 0.95 else Vector3.RIGHT)
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 0.3)
	tw.tween_callback(mi.queue_free)
	FX.burst(b, col, 8, 4.0, 0.08, 0.3)
