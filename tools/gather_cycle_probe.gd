extends Node3D
## Sonda do ciclo da coleta: simula dois ciclos quadro a quadro como no jogo (KnightAnim.apply com a suavização do
## player, 60 qps) e imprime por quadro a rotação dos ombros e cotovelos e os saltos grandes entre quadros.
##   godot --headless --path . res://tools/gather_cycle_probe.tscn -- [machado] [swing=1.2]
## Com `foto=<saida.png>` (sem --headless) tira uma fileira de 12 instantes do segundo ciclo, de lado e de frente.
## Com `minerios=<saida.png>` (sem --headless) fotografa os veios de minério e o cristal de world_nodes.json lado a lado.

const KNIGHT := preload("res://assets/models/knight.glb")


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var axe := "machado" in args
	var swing := 1.2
	var foto := ""
	for a in args:
		if a.begins_with("swing="):
			swing = float(a.substr(6))
		if a.begins_with("foto="):
			foto = a.substr(5)
	for a in args:
		if a.begins_with("minerios="):
			_ores(a.substr(9))
			return
	if foto != "":
		_photo(axe, swing, foto)
		return
	var m := KNIGHT.instantiate() as Node3D
	add_child(m)
	var lk := KnightLook.apply(m, {"weapon": ("axe_" if axe else "pickaxe_") + "iron"})
	var r := KnightAnim.rig(m)
	var dt := 1.0 / 60.0
	var k := 1.0 - exp(-14.0 * dt)
	var prev := {}
	var worst := 0.0
	for f in int(swing * 2.0 / dt):
		var t := f * dt
		var p := KnightAnim.idle_pose(t)
		KnightAnim.weapon_carry(p, "sword", 0.0, 0.0)
		GatherAction.pose_cycle(p, axe, fposmod(t, swing) / swing, smoothstep(0.0, 0.15, t))
		KnightAnim.hips_follow(p)
		var tgt_r: Vector3 = p.arm_r
		var tgt_l: Vector3 = p.arm_l
		KnightAnim.apply(r, p, k)
		KnightAnim.hold_weapon_upright(lk, r)
		var cur := {"ar": r.ArmR.rotation, "al": r.ArmL.rotation, "er": r.ElbowR.rotation.x, "el": r.ElbowL.rotation.x,
			"qr": r.ArmR.quaternion, "ql": r.ArmL.quaternion}
		var jump := 0.0
		if not prev.is_empty():
			jump = maxf((cur.qr as Quaternion).angle_to(prev.qr), (cur.ql as Quaternion).angle_to(prev.ql))   # giro de verdade do ombro
		worst = maxf(worst, jump)
		print("%5.3f u=%.3f  R tgt%s cur%s e%.2f | L tgt%s cur%s e%.2f  salto %.2f%s" % [t, fposmod(t, swing) / swing,
			_v(tgt_r), _v(cur.ar), cur.er, _v(tgt_l), _v(cur.al), cur.el, jump, "  <<<" if jump > 0.25 else ""])
		prev = cur
	print("PIOR SALTO %.2f rad/quadro" % worst)
	get_tree().quit()


## Simula um modelo até o instante `t_end` (quadro a quadro, como no jogo).
func _sim(m: Node3D, axe: bool, swing: float, t_end: float) -> void:
	var lk := KnightLook.apply(m, {"weapon": ("axe_" if axe else "pickaxe_") + "iron", "armor": "royal_plate",
		"head": "knight_helm", "hands": "iron_gauntlets", "feet": "iron_greaves"})
	var r := KnightAnim.rig(m)
	var dt := 1.0 / 60.0
	var k := 1.0 - exp(-14.0 * dt)
	for f in int(t_end / dt) + 1:
		var t := f * dt
		var p := KnightAnim.idle_pose(t)
		KnightAnim.weapon_carry(p, "sword", 0.0, 0.0)
		GatherAction.pose_cycle(p, axe, fposmod(t, swing) / swing, smoothstep(0.0, 0.15, t))
		KnightAnim.hips_follow(p)
		KnightAnim.apply(r, p, k)
		KnightAnim.hold_weapon_upright(lk, r)


func _photo(axe: bool, swing: float, out: String) -> void:
	WorldLighting.build(self)
	var n := 12
	for row in 2:
		for i in n:
			var m := KNIGHT.instantiate() as Node3D
			add_child(m)
			m.position = Vector3(i * 1.3, row * -2.4, 0)
			m.rotation.y = deg_to_rad(90.0 if row == 0 else 30.0)
			_sim(m, axe, swing, swing * (1.0 + float(i) / n))
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 16.0
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	add_child(cam)
	cam.look_at_from_position(Vector3(7.15, -0.3, 12.0), Vector3(7.15, -0.3, 0.0))
	for _i in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	print("SHOT ", out, " ", get_viewport().get_texture().get_image().get_size())
	get_tree().quit()


func _ores(out: String) -> void:
	WorldLighting.build(self)
	var kinds := ["copper", "iron", "silver", "mithril", "astralite", "crystal"]
	var k: Dictionary = Balance.tables.get_table("world_nodes").kinds
	for i in kinds.size():
		var d: Dictionary = k[kinds[i]]
		for row in 2:
			var n := WorldResourceNode.from_def({"id": 11 + i * 3 + row, "model": str(d.model), "tint": d.get("tint", Color(0.55, 0.3, 0.2)),
				"respawn": 60.0, "tier": int(d.get("tier", 1)), "pos": Vector3(i * 2.6, 0, row * -3.2)})
			add_child(n)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	g.mesh = pm
	add_child(g)
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.look_at_from_position(Vector3(6.5, 4.5, 10.5), Vector3(6.5, 0.3, -1.6))
	for _i in 8:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	print("SHOT ", out)
	get_tree().quit()


func _v(v: Vector3) -> String:
	return "(%5.2f %5.2f %5.2f)" % [v.x, v.y, v.z]
