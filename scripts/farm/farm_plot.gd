extends Node3D
## Canteiro da Horta. O estado vive em Game.farm.plots[index] (espelho do personagem; o crescimento
## corre pelo relógio, ver Game.plot_growth); este nó só desenha a planta e trata a interação (E):
## preparar, plantar, regar, adubar com gel de slime e colher — pedidos ao Econ.

var npc_id := "plot"   # lido pelo teste e pela depuração junto com os NPCs
var index := 0

var _soil_mat: StandardMaterial3D
var _plants: Node3D           # visual da cultura (recriado ao plantar)
var _fruits: Array[Node3D] = []
var _weeds: Node3D
var _label: Label3D
var _glow: OmniLight3D
var _sparkle: CPUParticles3D
var _shown_crop := "-"
var _t := 0.0
var _pop := 0.0               # "pulinho" ao plantar/colher
var _last_state := ""          # para avisar quando fica pronta

static var _mats := {}
static var _last_ready_notice := -100.0


func _ready() -> void:
	add_to_group("interactable")
	_t = randf() * 10.0
	# terra fofa com bordas de madeira
	var soil := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.8, 0.14, 1.8)
	soil.mesh = box
	soil.position.y = 0.07
	_soil_mat = StandardMaterial3D.new()
	_soil_mat.albedo_color = Color(0.33, 0.22, 0.13)
	_soil_mat.roughness = 1.0
	soil.material_override = _soil_mat
	add_child(soil)
	for i in 4:
		var plank := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(2.0, 0.2, 0.1)
		plank.mesh = pb
		plank.material_override = _mat("wood", Color(0.45, 0.3, 0.17))
		var a := i * PI / 2.0
		plank.rotation.y = a
		plank.position = Vector3(sin(a), 0, cos(a)) * 0.95 + Vector3.UP * 0.1
		add_child(plank)
	# sulcos
	for r in 3:
		var furrow := MeshInstance3D.new()
		var fb := BoxMesh.new()
		fb.size = Vector3(1.6, 0.04, 0.16)
		furrow.mesh = fb
		furrow.material_override = _mat("furrow", Color(0.25, 0.16, 0.09))
		furrow.position = Vector3(0, 0.15, -0.55 + r * 0.55)
		add_child(furrow)

	_weeds = Node3D.new()
	add_child(_weeds)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777 + index
	for i in 9:
		var w := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.18, rng.randf_range(0.25, 0.45), 0.06)
		w.mesh = pm
		w.material_override = _mat("weed", Color(0.3, 0.45, 0.15))
		w.position = Vector3(rng.randf_range(-0.7, 0.7), 0.25, rng.randf_range(-0.7, 0.7))
		w.rotation.y = rng.randf() * TAU
		_weeds.add_child(w)
	for i in 2:
		var rock := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.14
		sm.height = 0.18
		rock.mesh = sm
		rock.material_override = _mat("stone", Color(0.5, 0.5, 0.48))
		rock.position = Vector3(rng.randf_range(-0.6, 0.6), 0.16, rng.randf_range(-0.6, 0.6))
		_weeds.add_child(rock)

	_label = Label3D.new()
	_label.font_size = 34
	_label.outline_size = 8
	_label.pixel_size = 0.005
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 1.45
	_label.no_depth_test = true
	add_child(_label)

	_glow = OmniLight3D.new()
	_glow.light_energy = 0.0
	_glow.omni_range = 2.2
	_glow.position.y = 0.8
	add_child(_glow)

	_sparkle = CPUParticles3D.new()
	var spm := SphereMesh.new()
	spm.radius = 0.035
	spm.height = 0.07
	var sp_mat := StandardMaterial3D.new()
	sp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sp_mat.albedo_color = Color(1, 0.95, 0.6)
	spm.material = sp_mat
	_sparkle.mesh = spm
	_sparkle.amount = 10
	_sparkle.lifetime = 1.4
	_sparkle.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_sparkle.emission_box_extents = Vector3(0.75, 0.1, 0.75)
	_sparkle.direction = Vector3.UP
	_sparkle.spread = 15.0
	_sparkle.gravity = Vector3(0, 0.5, 0)
	_sparkle.initial_velocity_min = 0.3
	_sparkle.initial_velocity_max = 0.7
	_sparkle.position.y = 0.4
	_sparkle.emitting = false
	add_child(_sparkle)

	Game.farm_changed.connect(_refresh)
	Econ.done.connect(_on_econ_done)
	_refresh()


static func _mat(key: String, c: Color, emit := 0.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	_mats[key] = m
	return m


func _process(delta: float) -> void:
	_t += delta
	_pop = max(0.0, _pop - delta * 3.0)
	var st := Game.plot_state(index)
	# a planta cresce pelo relógio (o servidor/serviço guarda o instante do plantio): aqui só desenha
	if st == "ready" and _last_state == "growing":
		_on_ready()
	_last_state = st
	_animate(st)
	# rótulo só de perto
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var near := player != null and player.global_position.distance_to(global_position) < 7.0
	_label.visible = near or st == "ready" or (st == "locked" and index == Game.farm.unlocked)
	_update_label(st)


func _on_ready() -> void:
	_refresh()
	FX.burst(global_position + Vector3.UP * 0.6, Color(1, 0.95, 0.5), 14, 2.5, 0.08, 0.8, 1.0)
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_ready_notice > 6.0:
		_last_ready_notice = now
		Game.notify.emit("Há colheita pronta na Horta!", Color(0.8, 1.0, 0.5))


# ------------------------------------------------------------ visual
func _refresh() -> void:
	var st := Game.plot_state(index)
	var p: Dictionary = Game.farm.plots[index]
	_weeds.visible = st == "locked"
	_soil_mat.albedo_color = Color(0.2, 0.13, 0.08) if p.watered and st != "locked" else Color(0.33, 0.22, 0.13)
	_soil_mat.roughness = 0.45 if p.watered else 1.0
	var crop: String = p.crop if st in ["growing", "ready"] else ""
	if crop != _shown_crop:
		_shown_crop = crop
		if _plants:
			_plants.queue_free()
			_plants = null
		_fruits.clear()
		if crop != "":
			_plants = _build_crop(crop)
			add_child(_plants)
	var ready := st == "ready"
	_sparkle.emitting = ready
	_glow.light_color = ItemDB.CROPS[crop].color if crop != "" else Color.WHITE
	_glow.light_energy = 0.9 if ready else (0.5 if crop == "mint" else 0.0)


func _animate(st: String) -> void:
	if _plants == null:
		return
	var g: float = Game.plot_growth(index)
	var s := lerpf(0.22, 1.0, smoothstep(0.0, 0.85, g)) * (1.0 + _pop * 0.25)
	var sway := sin(_t * 1.6) * 0.04
	_plants.scale = Vector3(s, s, s)
	_plants.rotation.z = sway
	var fs := smoothstep(0.45, 1.0, g)
	for f in _fruits:
		f.scale = Vector3.ONE * max(0.001, fs)
	if st == "ready":
		_plants.position.y = abs(sin(_t * 3.0)) * 0.05


func _build_crop(crop: String) -> Node3D:
	var root := Node3D.new()
	var c: Color = ItemDB.CROPS[crop].color
	var leaf := _mat("leaf", Color(0.25, 0.6, 0.18))
	match crop:
		"carrot":
			for pos in _grid(2, 0.42):
				var plant := _node(root, pos)
				for k in 3:
					var l := _mesh(plant, _prism(0.12, 0.42, 0.04), leaf, Vector3(0, 0.36, 0))
					l.rotation = Vector3(0.0, k * TAU / 3.0, 0.35)
				var top := _cyl(0.09, 0.03, 0.28)
				var f := _mesh(plant, top, _mat("carrot", c), Vector3(0, 0.2, 0))
				_fruits.append(f)
		"wheat":
			for pos in _grid(3, 0.5):
				var plant := _node(root, pos)
				var stalk_c := Color(0.55, 0.7, 0.25)
				_mesh(plant, _cyl(0.025, 0.03, 0.8), _mat("stalk", stalk_c), Vector3(0, 0.55, 0))
				var head := _mesh(plant, _cyl(0.06, 0.05, 0.26), _mat("wheat", c), Vector3(0, 1.02, 0))
				_fruits.append(head)
		"tomato":
			for pos in _grid(2, 0.42):
				var plant := _node(root, pos)
				_mesh(plant, _cyl(0.02, 0.02, 1.0), _mat("wood", Color(0.45, 0.3, 0.17)), Vector3(0, 0.6, 0))
				_mesh(plant, _sphere(0.26, 0.45), leaf, Vector3(0, 0.6, 0))
				for k in 3:
					var a := k * TAU / 3.0 + 0.4
					var f := _mesh(plant, _sphere(0.08, 0.15), _mat("tomato", c), Vector3(cos(a) * 0.2, 0.45 + k * 0.12, sin(a) * 0.2))
					_fruits.append(f)
		"pepper":
			for pos in _grid(2, 0.42):
				var plant := _node(root, pos)
				_mesh(plant, _sphere(0.24, 0.38), _mat("leaf_dark", Color(0.18, 0.48, 0.14)), Vector3(0, 0.38, 0))
				for k in 3:
					var a := k * TAU / 3.0
					var f := _mesh(plant, _cyl(0.045, 0.012, 0.22), _mat("pepper", c, 0.5), Vector3(cos(a) * 0.2, 0.32, sin(a) * 0.2))
					f.rotation.z = 0.3
					_fruits.append(f)
		"mint":
			for pos in _grid(2, 0.42):
				var plant := _node(root, pos)
				_mesh(plant, _cyl(0.02, 0.025, 0.55), _mat("leaf_dark", Color(0.18, 0.48, 0.14)), Vector3(0, 0.38, 0))
				for k in 6:
					var a := k * 2.4
					var l := _mesh(plant, _sphere(0.11, 0.05), _mat("mint", c, 1.2), Vector3(cos(a) * 0.1, 0.2 + k * 0.08, sin(a) * 0.1))
					l.rotation = Vector3(1.0, -a, 0)
					l.scale = Vector3(1.0, 1.0, 1.6)
					if k >= 3:
						_fruits.append(l)
		"pumpkin":
			for k in 5:
				var a := k * TAU / 5.0
				var l := _mesh(root, _sphere(0.26, 0.08), leaf, Vector3(cos(a) * 0.55, 0.2, sin(a) * 0.55))
				l.rotation.y = a
			var holder := _node(root, Vector3.ZERO)
			var body := _mesh(holder, _sphere(0.42, 0.62), _mat("pumpkin", c), Vector3(0, 0.42, 0))
			body.scale = Vector3(1.15, 1.0, 1.15)
			_mesh(holder, _cyl(0.04, 0.05, 0.16), _mat("stem", Color(0.35, 0.45, 0.15)), Vector3(0, 0.78, 0))
			_fruits.append(holder)
	return root


func _grid(n: int, step: float) -> Array:
	var out := []
	var off := (n - 1) * step / 2.0
	for x in n:
		for z in n:
			out.append(Vector3(x * step - off, 0.12, z * step - off))
	return out


func _node(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _prism(w: float, h: float, d: float) -> PrismMesh:
	var p := PrismMesh.new()
	p.size = Vector3(w, h, d)
	return p


func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 8
	c.rings = 1
	return c


func _sphere(r: float, h: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = h
	s.radial_segments = 10
	s.rings = 5
	return s


func _update_label(st: String) -> void:
	var p: Dictionary = Game.farm.plots[index]
	match st:
		"locked":
			_label.text = "Novo canteiro: %d ouro" % Game.unlock_cost() if index == Game.farm.unlocked else ""
			_label.modulate = Color(1, 0.85, 0.4)
		"empty":
			_label.text = "Vazio"
			_label.modulate = Color(0.8, 0.75, 0.65)
		"growing":
			var cname: String = ItemDB.CROPS[p.crop].name
			_label.text = "%s %d%%%s" % [cname, int(Game.plot_growth(index) * 100.0), "  ~ regado" if p.watered else "  (regar!)"]
			_label.modulate = Color(0.6, 0.85, 1.0) if p.watered else Color(0.95, 0.9, 0.75)
		"ready":
			_label.text = "%s pronta!" % ItemDB.CROPS[p.crop].name
			_label.modulate = Color(0.75, 1.0, 0.4)


# ------------------------------------------------------------ interação
func interact_prompt() -> String:
	var p: Dictionary = Game.farm.plots[index]
	match Game.plot_state(index):
		"locked":
			if index == Game.farm.unlocked:
				return "Preparar canteiro (%d ouro)" % Game.unlock_cost()
			return "Canteiro abandonado"
		"empty":
			return "Plantar"
		"ready":
			return "Colher %s" % ItemDB.CROPS[p.crop].name
	var cname: String = ItemDB.CROPS[p.crop].name
	if not p.watered:
		return "Regar %s (cresce 2x mais rápido)" % cname
	if not p.fert and Game.count_item("slime_gel") > 0:
		return "Adubar %s com Gel de Slime (+40%%)" % cname
	return "%s crescendo — %d%%" % [cname, int(Game.plot_growth(index) * 100.0)]


func interact(_player: Node) -> void:
	var world := get_tree().current_scene
	match Game.plot_state(index):
		"locked":
			if index != Game.farm.unlocked:
				Game.notify.emit("Prepare os canteiros mais perto da entrada primeiro.", Color(1, 0.8, 0.55))
				return
			if world.has_method("open_dialogue"):
				world.open_dialogue("Horta da Vila", [{
					"text": "Este canteiro está cheio de mato e pedras. Limpar e adubar custa %d ouro.\nVocê tem %d ouro." % [Game.unlock_cost(), Game.gold],
					"choices": [
						{"text": "Preparar (%d ouro)" % Game.unlock_cost(), "action": _unlock},
						{"text": "Agora não", "action": Callable()},
					]}])
		"empty":
			if world.has_method("open_plant_menu"):
				world.open_plant_menu(index)
		"growing":
			# a mesma escolha de antes (regar, senão adubar), feita com o espelho; o efeito vem na resposta
			var p: Dictionary = Game.farm.plots[index]
			if not p.watered:
				Game.water(index)
			elif not p.fert and Game.count_item("slime_gel") > 0:
				Game.fertilize(index)
			else:
				Game.notify.emit("Ainda crescendo... %d%%" % int(Game.plot_growth(index) * 100.0), Color(0.85, 0.85, 0.7))
		"ready":
			Game.harvest(index)


func _unlock() -> void:
	Game.unlock_next_plot()


## Efeitos quando o Econ confirma uma ação neste canteiro (no solo, na hora; online, quando o servidor responde).
func _on_econ_done(op: String, args: Array, ok: bool, _err: String, events: Array) -> void:
	if not ok:
		return
	if op == "unlock_plot":
		if index == Game.farm.unlocked - 1:
			Sfx.play("coin")
			FX.burst(global_position + Vector3.UP * 0.4, Color(0.55, 0.4, 0.25), 30, 3.5, 0.1, 0.8)
		return
	if args.is_empty() or not (args[0] is int) or args[0] != index:
		return
	match op:
		"water":
			_pop = 1.0
			Sfx.play("water", 0.1)
			FX.burst(global_position + Vector3.UP * 0.9, Color(0.4, 0.7, 1.0), 24, 2.5, 0.07, 0.7, -9.0)
		"fertilize":
			_pop = 1.0
			Sfx.play("bloop", 0.1)
			FX.burst(global_position + Vector3.UP * 0.4, Color(0.4, 1.0, 0.45), 22, 3.0, 0.09, 0.8, 1.0)
			Game.notify.emit("Adubado! +40% de crescimento", Color(0.5, 1.0, 0.5))
		"harvest":
			for e in events:
				if e.get("t") != "harvest" or not ItemDB.CROPS.has(str(e.get("crop", ""))):
					continue
				var c: Color = ItemDB.CROPS[e.crop].color
				Sfx.play("harvest", 0.12)
				FX.burst(global_position + Vector3.UP * 0.6, c, 26 if not e.bonus else 60, 4.0, 0.11, 0.8)
				FX.damage_number(global_position + Vector3.UP * 1.4, "+%d" % int(e.qty), c.lightened(0.3), 54)
				if e.bonus:
					FX.ring(global_position, Color(1, 0.9, 0.3, 0.9), 2.2, 0.6)
