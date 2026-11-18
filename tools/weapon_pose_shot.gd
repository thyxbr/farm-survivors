extends Node3D
## Folha de contato das poses com cajado e arco: parado, andando (dois instantes do passo), golpes do cajado,
## mira do arco, tensão cheia e soltura. Três fileiras: frente em 3/4, de lado e de trás (visão da câmera do
## jogo, por cima do ombro). Precisa de janela (sem --headless) e do --import feito antes:
##   godot --path . --resolution 1900x1350 res://tools/weapon_pose_shot.tscn -- <saida.png> [cajado|arco|coleta] [roupa] [c=<coluna>]
## `coleta`: ciclos da picareta (KnightMoves.MINE) e do machado (CHOP), com uma pedra e um tronco no lugar do alvo.

const KNIGHT := preload("res://assets/models/knight.glb")
const STAFF_POSES := ["parado", "cajado 1 preparo", "cajado 1 meio", "cajado 1 mira", "cajado 1 coice", "meteoros", "cajado 3 alto", "cajado 3 mira"]
const BOW_POSES := ["parado", "andando A", "andando B", "mirando", "puxando", "tenso", "andando tenso", "soltou"]
const GATHER_POSES := ["picareta 0.0", "picareta 0.38", "picareta 0.5", "machado 0.0", "machado 0.36", "machado 0.44",
	"machado 0.47", "machado 0.5"]
const GAP := 1.35
const ROW_H := 450
const VIEWS := [35.0, 90.0, 180.0]

var _frames := 0
var _out := ""
var _names: Array = []
var _bow := false
var _gather := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://weapon_pose_shot.png"
	_bow = "arco" in args
	_gather = "coleta" in args
	_names = BOW_POSES if _bow else (GATHER_POSES if _gather else STAFF_POSES)
	var plate := not ("roupa" in args)
	WorldLighting.build(self)
	if "otimiza" in args:
		_optimize()
	for row in VIEWS.size():
		for i in _names.size():
			var m := KNIGHT.instantiate() as Node3D
			add_child(m)
			m.position = Vector3(i * _gap() + row * 100.0, 0, 0)
			m.rotation.y = deg_to_rad(VIEWS[row])
			var look := {"weapon": "hunter_bow" if _bow else "apprentice_staff"}
			if _gather:
				var tier := "iron"   # nivel=<pedra..astral em inglês: stone|iron|mithril|crystal|astral>
				for x in args:
					if x.begins_with("nivel="):
						tier = x.substr(6)
				look.weapon = ("pickaxe_" if str(_names[i]).begins_with("picareta") else "axe_") + tier
				_target(m, str(_names[i]).begins_with("picareta"))
			if plate:
				look.merge({"armor": "royal_plate", "head": "knight_helm", "hands": "iron_gauntlets", "feet": "iron_greaves"})
			var lk := KnightLook.apply(m, look)
			var r := KnightAnim.rig(m)
			_pose(r, lk, _names[i])
	var g := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(_names.size() * GAP + 302.0, 0.02, 40.0)
	g.mesh = bm
	g.position = Vector3(100.0, -0.01, 0.0)
	add_child(g)
	for row in VIEWS.size():
		var vp := SubViewport.new()
		vp.size = Vector2i(1900, ROW_H)
		vp.world_3d = get_viewport().world_3d
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.set_meta("row", row)
		add_child(vp)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 2.6
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.position = Vector3((_names.size() - 1) * _gap() / 2.0 + row * 100.0, 1.1, 8.0)
		if _gather:
			cam.size = 2.6 * _gap() / GAP
		for a in args:   # c=<coluna>: aproxima a câmera dessa coluna (e das vizinhas)
			if a.begins_with("c="):
				cam.size = 1.1
				cam.position = Vector3(float(a.substr(2)) * _gap() + row * 100.0, 1.35, 8.0)
		vp.add_child(cam)
		cam.current = true


## `otimiza`: para cada pose-chave da trajetória das ferramentas (KnightMoves.*_TOOL e *_TOOL_READY), procura perto
## do `end` e do `slide` desenhados onde as duas mãos fecham melhor no cabo (menor giro de pulso somado, sem perder
## alcance) com o tronco daquela pose, e imprime a chave pronta para colar em knight_moves.gd.
func _optimize() -> void:
	var m := KNIGHT.instantiate() as Node3D
	add_child(m)
	m.position = Vector3(-50, 0, 0)
	KnightLook.apply(m, {"weapon": "axe_iron"})
	var r := KnightAnim.rig(m)
	for axe in [true, false]:
		var track: Array = KnightMoves.CHOP_TOOL if axe else KnightMoves.MINE_TOOL
		var ready: Dictionary = KnightMoves.CHOP_TOOL_READY if axe else KnightMoves.MINE_TOOL_READY
		var keys: Array = [[0.0, ready]]
		for k in track:
			keys.append([k[0], k[1]])
		for key in keys:
			var p := KnightAnim.idle_pose(0.0)
			GatherAction.pose_cycle(p, axe, float(key[0]), 0.0)   # só o corpo (peso das mãos 0)
			KnightAnim.hips_follow(p)
			for _i in 2:
				KnightAnim.apply(r, p, 1.0)
			var d: Dictionary = key[1]
			var dir: Vector3 = (d.dir as Vector3).normalized()
			var free_slide: bool = float(d.slide) > 0.05
			var best_end: Vector3 = d.end
			var best_slide: float = d.slide
			var best := _grip_cost(r, best_end, dir, best_slide, d.end)
			var step := 0.08
			for _pass in 5:
				var improved := true
				while improved:
					improved = false
					for off in [Vector3(step, 0, 0), Vector3(-step, 0, 0), Vector3(0, step, 0), Vector3(0, -step, 0),
							Vector3(0, 0, step), Vector3(0, 0, -step)]:
						var c := _grip_cost(r, best_end + off, dir, best_slide, d.end)
						if c < best - 0.0005:
							best = c
							best_end += off
							improved = true
					if free_slide:
						for ds in [step * 0.5, -step * 0.5]:
							var sl := clampf(best_slide + ds, 0.15, 0.42)
							var c := _grip_cost(r, best_end, dir, sl, d.end)
							if c < best - 0.0005:
								best = c
								best_slide = sl
								improved = true
				step *= 0.5
			var gl := KnightAnim.grip_solve(r, "l", best_end, dir, KnightMoves.TOOL_POLE_L)
			var gr := KnightAnim.grip_solve(r, "r", best_end + dir * (best_slide - KnightMoves.TOOL_LEFT_GRIP.z), dir, KnightMoves.TOOL_POLE_R)
			print("OPT %s %.2f  end Vector3(%.2f, %.2f, %.2f) slide %.2f   giro esq %d dir %d graus (antes: custo %.2f)" % [
				"machado " if axe else "picareta", key[0], best_end.x, best_end.y, best_end.z, best_slide,
				roundi(rad_to_deg(gl.turn)), roundi(rad_to_deg(gr.turn)), _grip_cost(r, d.end, dir, d.slide, d.end)])
	m.queue_free()


## Giro de pulso somado das duas mãos (rad) + falta de alcance + distância da pose desenhada.
func _grip_cost(r: Dictionary, end: Vector3, dir: Vector3, slide: float, design: Vector3) -> float:
	var gl := KnightAnim.grip_solve(r, "l", end, dir, KnightMoves.TOOL_POLE_L)
	var gr := KnightAnim.grip_solve(r, "r", end + dir * (slide - KnightMoves.TOOL_LEFT_GRIP.z), dir, KnightMoves.TOOL_POLE_R)
	var hr := end + dir * (slide - KnightMoves.TOOL_LEFT_GRIP.z)
	# as mãos ficam na frente do corpo (nunca dentro ou atrás dele, salvo acima da cabeça) e perto da pose desenhada
	var body := 0.0
	for h in [end, hr]:
		if h.y < 1.6:
			body += maxf(0.0, 0.2 - h.z)
	return float(gl.turn) + float(gr.turn) + 12.0 * (float(gl.miss) + float(gr.miss)) + 2.0 * end.distance_to(design) \
		+ 15.0 * body


func _gap() -> float:
	return 2.2 if _gather else GAP   # coleta: espaço para o alvo à frente de cada um


## Alvo da coleta na frente do modelo (+Z): pedra baixa a ~1,2 m ou tronco de árvore a ~1 m.
func _target(m: Node3D, rock: bool) -> void:
	var mi := MeshInstance3D.new()
	if rock:
		var sm := SphereMesh.new()
		sm.radius = 0.45
		sm.height = 0.7
		mi.mesh = sm
		mi.position = Vector3(0, 0.25, 1.2)   # borda da colisão (0,75) a 0,55 m do jogador; a rocha é um pouco menor
	else:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.22   # tronco de pinheiro (WorldResourceNode.TRUNK)
		cm.bottom_radius = 0.22
		cm.height = 2.4
		mi.mesh = cm
		mi.position = GatherAction.chop_target(0.22) + Vector3(0, 1.2, 0)   # onde o tronco fica em relação ao jogador
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.48, 0.45, 0.55) if rock else Color(0.45, 0.3, 0.15, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	m.add_child(mi)


func _pose(r: Dictionary, lk: Dictionary, kind: String) -> void:
	var cls := "bow" if _bow else ("sword" if _gather else "staff")
	var p := KnightAnim.idle_pose(0.0)
	var move := 0.0
	match kind:
		"andando A", "andando B", "andando tenso", "correndo":
			move = 1.0
			var ph := 0.0 if kind != "andando B" else PI * 0.5
			p = KnightAnim.locomotion_pose(r, ph, move, 1.0 if kind == "correndo" else 0.0)
	KnightAnim.weapon_carry(p, cls, move, 1.0 if kind == "correndo" else 0.0)
	var atk := true
	match kind:
		"cajado 1 preparo":
			KnightAnim.staff_pose(p, 1, 0.16, 0.0)
		"cajado 1 meio":
			KnightAnim.staff_pose(p, 1, 0.25, 0.0)
		"cajado 2 preparo":
			KnightAnim.staff_pose(p, 2, 0.16, 0.0)
		"meteoros":
			KnightAnim.meteor_pose(p, 1.0, 0.0)
		"cajado 3 mira":
			KnightAnim.staff_pose(p, 3, 0.36, 0.0)
		"cajado 1 mira":
			KnightAnim.staff_pose(p, 1, 0.34, 0.0)
		"cajado 1 coice":
			KnightAnim.staff_pose(p, 1, 0.48, 0.0)
		"cajado 3 alto":
			KnightAnim.staff_pose(p, 3, 0.22, 0.0)
		"magia":
			KnightAnim.cast_pose(p, "fireball", 0.3, 0.0, true)
		"mirando":
			KnightAnim.bow_draw_pose(p, 0.0)
		"puxando":
			KnightAnim.bow_draw_pose(p, 0.45)
		"tenso", "andando tenso":
			KnightAnim.bow_draw_pose(p, 1.0, move)
		"soltou":
			KnightAnim.bow_release_pose(p, 0.2, 0.0)
		_ when kind.begins_with("picareta") or kind.begins_with("machado"):
			GatherAction.pose_cycle(p, kind.begins_with("machado"), float(kind.get_slice(" ", 1)), 1.0)
		_:
			atk = false
	if atk:
		KnightAnim.hips_follow(p)
	for _i in 2:   # a segunda vez: a altura do modelo usa as rotações já aplicadas
		KnightAnim.apply(r, p, 1.0)
	KnightAnim.hold_weapon_upright(lk, r)
	if OS.get_environment("POSE_DEBUG") != "" and lk.get("holder") and m_row(r) == 0:
		var h: Node3D = lk.holder
		var inv := (r.model as Node3D).global_transform.affine_inverse()
		print("POSE %-16s mão %s  ponta de baixo %s" % [kind, inv * h.global_position, inv * (h.global_transform * Vector3(0, -0.85, 0))])
	if _gather and lk.get("holder") and m_row(r) == 0:
		# distância de cada mão até a linha do cabo (cm): 0 = segurando
		var h: Node3D = lk.holder
		var a0 := h.global_transform * Vector3(0, 0, -0.2)
		var a1 := h.global_transform * Vector3(0, 0, 0.6)
		var hl: Vector3 = (r.ElbowL as Node3D).global_transform * (r.hand_l as Vector3)
		var hr: Vector3 = (r.ElbowR as Node3D).global_transform * (r.hand_r as Vector3)
		var cl := Geometry3D.get_closest_point_to_segment(hl, a0, a1)
		var cr := Geometry3D.get_closest_point_to_segment(hr, a0, a1)
		print("HANDS %-14s esq %.1f cm  dir %.1f cm  dobra esq %d dir %d  giro esq %d dir %d graus" % [kind,
			hl.distance_to(cl) * 100.0, hr.distance_to(cr) * 100.0,
			roundi(rad_to_deg(float(r.get("wrist_dev_L", 0.0)))), roundi(rad_to_deg(float(r.get("wrist_dev_R", 0.0)))),
			roundi(rad_to_deg(float(r.get("wrist_turn_L", 0.0)))), roundi(rad_to_deg(float(r.get("wrist_turn_R", 0.0))))])
	if _gather and lk.get("tip") and m_row(r) == 0:
		var inv2 := (r.model as Node3D).global_transform.affine_inverse()
		print("TIP %-14s %s  ombroR %s  maoR %s  maoL %s" % [kind, inv2 * (lk.tip as Node3D).global_position,
			inv2 * (r.ArmR as Node3D).global_position, inv2 * (lk.holder as Node3D).global_position,
			inv2 * (r.ElbowL as Node3D).global_transform * (r.hand_l as Vector3)])
	if lk.get("arrow"):
		lk.arrow.visible = kind in ["mirando", "puxando", "tenso", "andando tenso"]
	KnightAnim.bow_string(lk, r)


func m_row(r: Dictionary) -> int:
	return int((r.model as Node3D).position.x / 100.0)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 14:
		return
	var img := Image.create(1900, ROW_H * VIEWS.size(), false, Image.FORMAT_RGBA8)
	for vp: SubViewport in find_children("*", "SubViewport", false, false):
		var part := vp.get_texture().get_image()
		part.convert(Image.FORMAT_RGBA8)
		img.blit_rect(part, Rect2i(Vector2i.ZERO, part.get_size()), Vector2i(0, ROW_H * int(vp.get_meta("row"))))
	img.save_png(_out)
	print("SHOT ", _out)
	get_tree().quit()
