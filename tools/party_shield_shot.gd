extends Node3D
## Folha de contato do Grito do Bastião (habilidade 5 da espada com escudo). Precisa de janela (sem --headless):
##   godot --path . --fixed-fps 30 --resolution 960x720 res://tools/party_shield_shot.tscn -- <saida.png> [jogo|perto]
## jogo: da câmera do jogo (atrás do herói, recuada como na habilidade), o herói gritando no meio de dois aliados.
## perto: mais perto, para ver a aura, os escudos girando e as partículas.
## A linha do tempo: a animação "Sword And Shield Power Up" com a aura azul (PartyShieldCast), o grito, o buff entrando
## nos três (PartyShieldBuff, como a BuffAura faz), a órbita e a dissipação em partículas quando ele acaba.

const KNIGHT := preload("res://assets/models/knight.glb")
const CAST := preload("res://scenes/vfx/party_shield/party_shield_cast.tscn")
const BUFF := preload("res://scenes/vfx/party_shield/party_shield_buff.tscn")
const CELL := Vector2i(480, 360)
## Quanto tempo o buff fica antes de dissipar na folha (s; no jogo é o tempo da tabela).
const HOLD := 2.2

var _out := ""
var _mode := "jogo"
var _t := 0.0
var _shots: Array = []
var _plan: Array = []
var _heroes: Array = []   # [modelo, rig, look]
var _cast: PartyShieldCast
var _buffs: Array = []
var _cfg: PartyShieldConfig
var _shouted := false
var _granted := false
var _dissipated := false
var _done := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://party_shield_shot.png"
	if args.size() > 1:
		_mode = args[1]
	_cfg = load("res://assets/vfx/party_shield/party_shield_config.tres")
	WorldLighting.build(self)
	_ground()
	_heroes.append(_make_knight(Vector3.ZERO, 0.0))
	_heroes.append(_make_knight(Vector3(-2.2, 0, 1.4), 0.4))
	_heroes.append(_make_knight(Vector3(2.4, 0, 1.0), -0.5))
	var cam := Camera3D.new()
	cam.fov = 70.0
	add_child(cam)
	var dist := (4.0 + _cfg.camera_back) if _mode == "jogo" else 3.0
	var pivot := Vector3(0.0, 1.45, 0.0)
	cam.position = pivot + Vector3(0, sin(0.25), -cos(0.25)) * dist + Vector3(-0.45, 0, 0)
	cam.rotation = Vector3(-0.25, PI, 0.0)
	cam.current = true
	_cast = CAST.instantiate()
	_cast.config = _cfg
	_heroes[0][0].add_child(_cast)
	var end := PartyShieldRules.cast_time(_cfg.cast_speed)
	_cast.duration = end
	var d := _cfg.dissipate_time
	_plan = [[0.12, "aura acendendo"], [0.3, "recolhendo"], [PartyShieldRules.SHOUT_AT / _cfg.cast_speed + 0.05, "grito"],
		[end * 0.5, "aura: formação"], [end * 0.8, "aura: anel fechando"], [end - 0.05, "fim da animação"],
		[end + 0.25, "buff entrando"], [end + 0.8, "escudos girando"], [end + 1.6, "órbita"],
		[end + HOLD + d * 0.2, "dissipando"], [end + HOLD + d * 0.55, "partículas"], [end + HOLD + d + PartyShieldBuff.PARTICLE_LIFE + 0.3, "fim"]]


func _ground() -> void:
	var g := StaticBody3D.new()
	add_child(g)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.45, 0.22)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(80, 0.2, 80)
	mi.mesh = bm
	mi.material_override = gm
	mi.position = Vector3(0, -0.1, 0)
	g.add_child(mi)


func _make_knight(pos: Vector3, yaw: float) -> Array:
	var m := KNIGHT.instantiate() as Node3D
	add_child(m)
	m.position = pos
	m.rotation.y = yaw
	var lk := KnightLook.apply(m, {"weapon": "iron_sword", "offhand": "knight_shield", "armor": "royal_plate",
		"head": "knight_helm", "hands": "iron_gauntlets", "feet": "iron_greaves"})
	return [m, KnightAnim.rig(m), lk]


func _pose(h: Array, t: float, cast: bool, k: float) -> void:
	var p := KnightAnim.idle_pose(t)
	KnightAnim.weapon_carry(p, "sword", 0.0, 0.0)
	if cast:
		KnightAnim.taunt_pose(p, minf(t * _cfg.cast_speed, PartyShieldRules.CLIP_END))
	KnightAnim.hips_follow(p)
	KnightAnim.apply(h[1], p, k)
	KnightAnim.hold_weapon_upright(h[2], h[1])


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	var k := 1.0 - exp(-14.0 * delta)
	for i in _heroes.size():
		_pose(_heroes[i], _t, i == 0, k)
	if not _shouted and _t >= PartyShieldRules.SHOUT_AT / _cfg.cast_speed:
		_shouted = true
		_cast.shout()
	if not _granted and _t >= PartyShieldRules.cast_time(_cfg.cast_speed):
		_granted = true
		_cast.finish()
		for h in _heroes:
			var b: PartyShieldBuff = BUFF.instantiate()
			b.config = _cfg
			h[0].add_child(b)
			_buffs.append(b)
	if _granted and not _dissipated and _t >= PartyShieldRules.cast_time(_cfg.cast_speed) + HOLD:
		_dissipated = true
		for b in _buffs:
			b.dissipate()
	while not _plan.is_empty() and _t >= float(_plan[0][0]):
		var step: Array = _plan.pop_front()
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
		_shots.append([img, "%s (%.2f s)" % [step[1], _t]])
		var alive := 0
		for b in _buffs:
			if is_instance_valid(b):
				alive += 1
		print("quadro %-22s t=%.2f aura=%.2f buffs=%d nós=%d" % [step[1], _t,
			_cast.weight() if is_instance_valid(_cast) else -1.0, alive, get_tree().get_node_count()])
		if _plan.is_empty():
			_save()


func _save() -> void:
	_done = true
	var cols := 4
	var rows := int(ceil(_shots.size() / float(cols)))
	var img := Image.create(CELL.x * cols, CELL.y * rows, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.06, 0.06, 0.08))
	for i in _shots.size():
		img.blit_rect(_shots[i][0], Rect2i(Vector2i.ZERO, CELL), Vector2i((i % cols) * CELL.x, (i / cols) * CELL.y))
	img.save_png(_out)
	for i in _shots.size():
		print("  %d: %s" % [i + 1, _shots[i][1]])
	var left := 0
	for b in _buffs:
		if is_instance_valid(b):
			left += 1
	print("SHOT ", _out, " — aura liberada: ", not is_instance_valid(_cast), " — buffs restantes: ", left)
	get_tree().quit()
