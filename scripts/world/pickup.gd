extends Area3D
## Item/ouro largado no chão. É atraído pelo jogador próximo e coletado ao toque.
## Offline: a coleta concede pelo Econ (solo). Online (net_id > 0): o pickup é do servidor
## (PickupRegistry); a coleta é um pedido `claim_pickup` e só vale com a resposta dele.

## Quanto um pickup do servidor pode ser arrastado pelo ímã a partir de onde caiu: o servidor só aceita
## a coleta a até PickupRegistry.MAX_DIST (4 m) da última posição recebida do jogador.
const NET_LEASH := 2.5
const LIFETIME := 120.0
## Sem resposta do servidor à coleta em tanto tempo: volta ao chão (pode tentar de novo).
const CLAIM_TIMEOUT := 5.0

var item_id := ""   # vazio = ouro
var amount := 1
## > 0: pickup do servidor (online); a coleta é pedida a ele.
var net_id := 0
## Origem da concessão offline ("loot"; "horde_run" nas moedas do Desafio da Horda).
var source := "loot"
var _origin := Vector3.ZERO
var _claiming := false
var _claim_t := 0.0
var _cooldown := 0.0   # segundos sem ímã depois de voltar ao chão
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
	if net_id > 0:
		_vel = Vector3(_vel.x * 0.4, 5.0, _vel.z * 0.4)   # perto de onde o servidor registrou


## Cria um pickup no chão (net_id > 0 = do servidor).
static func spawn(parent: Node, id: String, qty: int, pos: Vector3, p_net_id := 0, p_source := "loot") -> Node:
	var p = load("res://scripts/world/pickup.gd").new()
	p.item_id = id
	p.amount = qty
	p.net_id = p_net_id
	p.source = p_source
	parent.add_child(p)
	p.global_position = pos
	p._origin = pos
	return p


func _physics_process(delta: float) -> void:
	_t += delta
	if _t > LIFETIME:
		queue_free()
		return
	if _claiming:
		_claim_t += delta
		if _claim_t >= CLAIM_TIMEOUT:
			_reopen()
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	var player := get_tree().get_first_node_in_group("player") as Player
	if _t > 0.6 and _cooldown <= 0.0 and player and not player.dead:
		var to := player.global_position + Vector3.UP * 0.8 - global_position
		if to.length() < 1.0:
			_collect()
			return
		if to.length() < 3.5:
			global_position += to.normalized() * min(to.length(), (12.0 - to.length() * 2.0) * delta)
			_grounded = true
			if net_id > 0:
				_leash()
	if not _grounded:
		_vel.y -= 16.0 * delta
		global_position += _vel * delta
		if global_position.y <= 0.35:
			global_position.y = 0.35
			_grounded = true
	_vis.rotation.y += delta * 2.5
	_vis.position.y = sin(_t * 3.0) * 0.1


## Pickup do servidor não se afasta mais que NET_LEASH (no plano) de onde caiu.
func _leash() -> void:
	var off := global_position - _origin
	var flat := Vector2(off.x, off.z)
	if flat.length() > NET_LEASH:
		flat = flat.normalized() * NET_LEASH
		global_position = Vector3(_origin.x + flat.x, global_position.y, _origin.z + flat.y)


func _on_body(body: Node) -> void:
	if body.is_in_group("player") and _t >= 0.4:
		_collect()


func _collect() -> void:
	if is_queued_for_deletion() or _claiming:
		return
	if net_id > 0:
		# o servidor decide: some da tela enquanto espera; "longe" devolve ao chão
		_claiming = true
		_claim_t = 0.0
		visible = false
		Econ.done.connect(_on_claim_done)
		Econ.request("claim_pickup", [net_id])
		return
	if item_id == "":
		Econ.grant(amount, 0, {}, source)
	else:
		Econ.grant(0, 0, {item_id: amount}, source)
	_collected_fx()
	queue_free()


func _collected_fx() -> void:
	if item_id == "":
		Game.notify.emit("+%d ouro" % amount, Color(1, 0.85, 0.3))
		Sfx.play("coin")
	else:
		Sfx.play("pickup")


func _on_claim_done(op: String, args: Array, ok: bool, err: String, _events: Array) -> void:
	if op != "claim_pickup" or args.is_empty() or int(args[0]) != net_id:
		return
	if ok:
		Econ.done.disconnect(_on_claim_done)
		_collected_fx()
		queue_free()
	elif err in ["longe", "erro_banco", "devagar"]:
		# o servidor ainda não viu o jogador perto, não gravou (o pickup voltou ao registro) ou recusou por
		# excesso de pedidos: volta ao chão e tenta de novo depois
		_reopen()
	else:
		queue_free()   # de outro, já pego, expirado, sem conexão


## Volta ao chão depois de uma coleta recusada ou sem resposta (a validade continua contando).
func _reopen() -> void:
	if Econ.done.is_connected(_on_claim_done):
		Econ.done.disconnect(_on_claim_done)
	_claiming = false
	visible = true
	_cooldown = 0.6
