extends Node3D
## Folha de contato da Égide Cristalina (habilidade 1 da espada com escudo). Precisa de janela (sem --headless):
##   godot --path . --fixed-fps 30 --resolution 960x720 res://tools/aegis_shot.tscn -- <saida.png> [pose|barreira|dissolver]
## pose:      a guarda medida no Mixamo (parado, tranco do golpe a 0,1 s e 0,23 s), de 3/4 e de lado.
## barreira:  a linha do tempo inteira: círculo, placas brotando, formado, golpes (70%, 40%, 15%), pulsação,
##            estouro, fragmentos e dissipação. Cada quadro tem o nome e o tempo embaixo.
## dissolver: soltar a tecla no meio: as placas se desfazem sem estouro.
## circulo:   o círculo do chão de perto, na ordem da formação (nitidez do desenho).

const KNIGHT := preload("res://assets/models/knight.glb")
const BARRIER := preload("res://scenes/vfx/aegis/aegis_barrier.tscn")
const CELL := Vector2i(480, 360)

var _out := ""
var _mode := "barreira"
var _t := 0.0
var _frames := 0
var _shots: Array = []        # [Image, legenda]
var _plan: Array = []         # [t, ação, arg]
var _knight: Node3D
var _rig: Dictionary
var _look: Dictionary
var _barrier: AegisBarrier
var _hit_at := -10.0
var _guard_on := true
var _done := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://aegis_shot.png"
	if args.size() > 1:
		_mode = args[1]
	WorldLighting.build(self)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.45, 0.22)
	g.material_override = gm
	add_child(g)
	if _mode == "pose":
		_pose_sheet()
		return
	_knight = _make_knight(Vector3.ZERO, 0.0)
	# mais 4 personagens em volta (o escudo tem que caber o grupo)
	for i in 4:
		var a := TAU * (float(i) + 0.5) / 4.0
		var ally := KNIGHT.instantiate() as Node3D
		add_child(ally)
		ally.position = Vector3(sin(a), 0.0, cos(a)) * 1.4
		ally.rotation.y = a
		KnightLook.apply(ally, {"weapon": "iron_sword"})
	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	if _mode == "circulo":   # de perto, olhando o chão (qualidade do desenho)
		cam.look_at_from_position(Vector3(0.0, 4.2, 4.6), Vector3(0, 0.0, 0.4))
	else:
		cam.look_at_from_position(Vector3(5.2, 3.6, 8.6), Vector3(0, 1.0, 0))
	cam.current = true
	_barrier = BARRIER.instantiate()
	add_child(_barrier)   # no jogo ela fica no corpo do jogador (que não agacha), não no modelo animado
	if _mode == "circulo":
		_plan = [[0.08, "shot", "borda"], [0.18, "shot", "anel de dentro"], [0.3, "shot", "hexagrama"], [0.45, "shot", "emblema"],
			[0.7, "shot", "pronto"], [1.6, "shot", "com a coroa"], [1.7, "end", null]]
	elif _mode == "dissolver":
		_plan = [[0.2, "shot", "formando"], [1.6, "shot", "formado"], [1.3, "dissolve", null], [1.45, "shot", "soltou +0,15 s"],
			[1.65, "shot", "+0,35 s"], [1.95, "shot", "+0,65 s"], [2.6, "end", null]]
	else:
		_plan = [[0.1, "shot", "círculo"], [0.32, "shot", "placas brotando"], [0.55, "shot", "crescendo"], [1.6, "shot", "formado"],
			[1.3, "hit", 0.7], [1.42, "shot", "golpe: 70%"], [1.8, "hit", 0.4], [1.95, "shot", "40%"],
			[2.3, "hit", 0.12], [2.45, "shot", "12%"], [2.8, "break", null], [2.95, "shot", "pulsação"],
			[3.13, "shot", "estouro"], [3.4, "shot", "fragmentos"], [3.9, "shot", "dissipando"], [4.5, "shot", "fim"], [4.7, "end", null]]


func _make_knight(pos: Vector3, yaw: float) -> Node3D:
	var m := KNIGHT.instantiate() as Node3D
	add_child(m)
	m.position = pos
	m.rotation.y = yaw
	_look = KnightLook.apply(m, {"weapon": "iron_sword", "offhand": "knight_shield", "armor": "royal_plate",
		"head": "knight_helm", "hands": "iron_gauntlets", "feet": "iron_greaves"})
	_rig = KnightAnim.rig(m)
	return m


func _pose_knight(r: Dictionary, lk: Dictionary, guard: bool, impact: float, k := 1.0) -> void:
	var p := KnightAnim.idle_pose(_t)
	KnightAnim.weapon_carry(p, "sword", 0.0, 0.0)
	if guard:
		KnightAnim.aegis_guard_pose(p, 1.0, impact, 0.0)
		KnightAnim.hips_follow(p)
	KnightAnim.apply(r, p, k)
	KnightAnim.hold_weapon_upright(lk, r)


func _pose_sheet() -> void:
	var names := ["parado", "guarda", "golpe 0,1 s", "golpe 0,23 s"]
	for row in 2:
		for i in names.size():
			var m := KNIGHT.instantiate() as Node3D
			add_child(m)
			m.position = Vector3(i * 1.6 + row * 100.0, 0, 0)
			m.rotation.y = deg_to_rad(35.0) if row == 0 else deg_to_rad(90.0)
			var lk := KnightLook.apply(m, {"weapon": "iron_sword", "offhand": "knight_shield", "armor": "royal_plate",
				"head": "knight_helm", "hands": "iron_gauntlets", "feet": "iron_greaves"})
			var r := KnightAnim.rig(m)
			for _j in 3:
				_pose_knight(r, lk, i > 0, [0.0, 0.0, 0.1, 0.23][i])
	for row in 2:
		var vp := SubViewport.new()
		vp.size = Vector2i(1280, 420)
		vp.world_3d = get_viewport().world_3d
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.set_meta("row", row)
		add_child(vp)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 2.3
		cam.position = Vector3(1.5 * 1.6 + row * 100.0, 1.0, 8.0)
		vp.add_child(cam)
		cam.current = true


func _process(delta: float) -> void:
	_frames += 1
	if _mode == "pose":
		if _frames == 12:
			var img := Image.create(1280, 840, false, Image.FORMAT_RGBA8)
			for vp: SubViewport in find_children("*", "SubViewport", false, false):
				var part := vp.get_texture().get_image()
				part.convert(Image.FORMAT_RGBA8)
				img.blit_rect(part, Rect2i(Vector2i.ZERO, part.get_size()), Vector2i(0, 420 * int(vp.get_meta("row"))))
			img.save_png(_out)
			print("SHOT ", _out)
			get_tree().quit()
		return
	if _done:
		return
	_t += delta
	_pose_knight(_rig, _look, _guard_on, _t - _hit_at, 1.0 - exp(-14.0 * delta))
	while not _plan.is_empty() and _t >= float(_plan[0][0]):
		var step: Array = _plan.pop_front()
		match step[1]:
			"shot":
				var img := get_viewport().get_texture().get_image()
				img.convert(Image.FORMAT_RGBA8)
				img.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
				_shots.append([img, "%s (%.2f s)" % [step[2], _t]])
				print("quadro %s  t=%.2f  placas formadas=%.2f  estado=%d  nós na cena=%d" % [step[2], _t,
					_barrier.formed() if is_instance_valid(_barrier) else -1.0,
					_barrier.state if is_instance_valid(_barrier) else -1, get_tree().get_node_count()])
			"hit":
				var from := Vector3(-1.5, 1.2, 2.5)
				_barrier.impact(from)
				_barrier.set_integrity(float(step[2]), from)
				_hit_at = _t
			"break":
				_barrier.set_integrity(0.0, Vector3(-1.5, 1.2, 2.5))
				_barrier.shatter()
				_guard_on = false
			"dissolve":
				_barrier.dissolve()
				_guard_on = false
			"end":
				_save()


func _save() -> void:
	_done = true
	var cols := 4
	var rows := int(ceil(_shots.size() / float(cols)))
	var img := Image.create(CELL.x * cols, (CELL.y + 26) * rows, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.06, 0.06, 0.08))
	for i in _shots.size():
		var at := Vector2i((i % cols) * CELL.x, (i / cols) * (CELL.y + 26))
		img.blit_rect(_shots[i][0], Rect2i(Vector2i.ZERO, CELL), at)
	img.save_png(_out)
	for i in _shots.size():
		print("  %d: %s" % [i + 1, _shots[i][1]])
	print("SHOT ", _out, " — barreira liberada: ", not is_instance_valid(_barrier))
	get_tree().quit()
