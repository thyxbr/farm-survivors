class_name LootFx
extends Node3D
## O espólio de um abate saltando do monstro e voando até o jogador. Só efeito: o ouro e os itens já
## entraram no inventário (CharRules.grant) quando isto aparece. Cada item é o ícone dele (ItemIcons.baked)
## num cartão virado para a câmera; o ouro, umas moedas. Equipamento raro ou melhor ganha um feixe de luz
## na cor da raridade onde o monstro caiu, e o épico ou melhor, um anel que se abre no chão.

const POP_UP := 5.2          # impulso vertical do salto (m/s)
const POP_SIDE := 2.6        # espalhamento lateral do salto (m/s)
const GRAVITY := 13.0
const HANG := 0.65           # segundos no ar antes de voar até o jogador
const FLY_ACCEL := 38.0
const REACH := 0.55          # perto assim do peito do jogador, chegou
const MAX_LIFE := 3.0
const ICON_PX := 0.006       # tamanho do ícone no mundo (192 px -> ~1,15 m)
const MAX_COINS := 7


class _Bit:
	var node: Node3D
	var vel: Vector3
	var t := 0.0
	var gold := false
	var spin := 0.0


var _bits: Array[_Bit] = []
var _t := 0.0
var _coin_sfx := false


## Solta o espólio em `pos` (posição do monstro). `items` = {id: qtd}. Nada a mostrar = não cria nada.
static func play(parent: Node, pos: Vector3, gold: int, items: Dictionary) -> LootFx:
	if parent == null or not is_instance_valid(parent) or (gold <= 0 and items.is_empty()):
		return null
	var fx := LootFx.new()
	parent.add_child(fx)
	fx.global_position = pos + Vector3.UP * 0.7
	fx._spawn(gold, items)
	return fx


func _spawn(gold: int, items: Dictionary) -> void:
	var n := 0
	var best_rank := -1
	var best_id := ""
	for id in items:
		var sid := str(id)
		_add_bit(_item_card(sid), false, n)
		n += 1
		if ItemDB.is_equippable(sid):
			var rank: int = ItemDB.RARITY[ItemDB.rarity_of(sid)].rank
			if rank > best_rank:
				best_rank = rank
				best_id = sid
	if gold > 0:
		var coins := clampi(2 + gold / 15, 2, MAX_COINS)
		for i in coins:
			_add_bit(_coin(), true, n + i)
	if best_rank >= 2:
		_beam(ItemDB.rarity_color(best_id), best_rank)
		Sfx.play_at("gem", global_position, 0.05, -2.0)


func _add_bit(node: Node3D, gold: bool, i: int) -> void:
	add_child(node)
	var b := _Bit.new()
	b.node = node
	b.gold = gold
	var ang := randf() * TAU + i * 2.4
	var side := POP_SIDE * (0.6 if gold else 1.0) * randf_range(0.6, 1.0)
	b.vel = Vector3(cos(ang) * side, POP_UP * randf_range(0.85, 1.1), sin(ang) * side)
	b.t = -0.04 * i          # um depois do outro: o espólio "escorre" do monstro
	b.spin = randf_range(8.0, 14.0)
	node.visible = false
	_bits.append(b)


## Cartão com o ícone de verdade do item (ou uma bolinha na cor dele, se não houver ícone assado).
func _item_card(id: String) -> Node3D:
	var root := Node3D.new()
	var tex: Texture2D = ItemSlot.item_art(id)
	if tex == null:
		tex = ItemIcons.baked(id)
	var rc := ItemDB.rarity_color(id) if ItemDB.is_equippable(id) else Color(1.0, 0.95, 0.75)
	if tex != null:
		var s := Sprite3D.new()
		s.texture = tex
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.pixel_size = ICON_PX * 192.0 / maxf(float(tex.get_width()), 1.0)
		s.shaded = false
		s.no_depth_test = true          # não some atrás do monstro nem da grama
		s.render_priority = 10
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(s)
	else:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.14
		sm.height = 0.28
		mi.mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = IconPainter.color_for(id)
		m.emission_enabled = true
		m.emission = IconPainter.color_for(id)
		m.emission_energy_multiplier = 0.8
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	# brilho atrás do ícone, na cor da raridade (material: dourado claro)
	var glow := Sprite3D.new()
	glow.texture = _glow_tex()
	glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	glow.pixel_size = 0.022
	glow.modulate = Color(rc.r, rc.g, rc.b, 0.75)
	glow.shaded = false
	glow.no_depth_test = true
	glow.render_priority = 9
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glow)
	return root


func _coin() -> Node3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.11
	c.bottom_radius = 0.11
	c.height = 0.03
	c.radial_segments = 12
	mi.mesh = c
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.8, 0.25)
	m.metallic = 1.0
	m.roughness = 0.25
	m.emission_enabled = true
	m.emission = Color(1.0, 0.75, 0.2)
	m.emission_energy_multiplier = 0.5
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation.x = PI / 2
	return mi


## Feixe de luz na cor da raridade onde o monstro caiu (raro ou melhor); épico ou melhor abre um anel no chão.
func _beam(col: Color, rank: int) -> void:
	var at := Node3D.new()
	get_parent().add_child(at)
	at.global_position = global_position - Vector3.UP * 0.7
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.16 + 0.04 * rank
	cyl.height = 5.0
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.albedo_color = Color(col.r, col.g, col.b, 0.55)
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	cyl.material = bm
	beam.mesh = cyl
	beam.position.y = 2.5
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	at.add_child(beam)
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 2.0 + rank * 0.5
	light.omni_range = 4.0
	light.position.y = 0.8
	at.add_child(light)
	var tw := at.create_tween()
	beam.scale = Vector3(0.2, 0.1, 0.2)
	tw.tween_property(beam, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if rank >= 3:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.5
		tm.outer_radius = 0.62
		var rm := bm.duplicate() as StandardMaterial3D
		rm.albedo_color = Color(col.r, col.g, col.b, 0.8)
		tm.material = rm
		ring.mesh = tm
		ring.position.y = 0.08
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		at.add_child(ring)
		var rt := at.create_tween().set_parallel()
		rt.tween_property(ring, "scale", Vector3(4.0, 1.0, 4.0), 0.7).set_ease(Tween.EASE_OUT)
		rt.tween_property(rm, "albedo_color:a", 0.0, 0.7)
	tw.tween_interval(1.4 + rank * 0.25)
	tw.tween_property(bm, "albedo_color:a", 0.0, 0.6)
	tw.parallel().tween_property(light, "light_energy", 0.0, 0.6)
	tw.tween_callback(at.queue_free)


func _physics_process(delta: float) -> void:
	_t += delta
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var target := player.global_position + Vector3.UP * 1.0 if player else global_position + Vector3.UP * 2.0
	var alive := 0
	for b in _bits:
		if b.node == null:
			continue
		b.t += delta
		if b.t < 0.0:
			alive += 1
			continue
		b.node.visible = true
		if b.gold:
			b.node.rotate_y(b.spin * delta)
		if b.t < HANG:
			# salto: sobe, abre e cai um pouco; o ícone cresce do nada
			b.vel.y -= GRAVITY * delta
			b.node.position += b.vel * delta
			var k := clampf(b.t / 0.15, 0.0, 1.0)
			b.node.scale = Vector3.ONE * (0.3 + 0.7 * k)
		else:
			# voa até o jogador, cada vez mais rápido, e encolhe ao chegar
			var to := target - b.node.global_position
			var d := to.length()
			var speed := (b.t - HANG) * FLY_ACCEL + 3.0
			if d <= REACH or b.t > MAX_LIFE:
				_arrive(b)
				continue
			b.node.global_position += to / d * minf(d, speed * delta)
			b.node.scale = Vector3.ONE * clampf(d / 2.0, 0.45, 1.0)
		alive += 1
	if alive == 0 or _t > MAX_LIFE + 1.0:
		queue_free()


func _arrive(b: _Bit) -> void:
	if b.gold:
		if not _coin_sfx:
			_coin_sfx = true
			Sfx.play("coin", 0.12, -4.0)
	else:
		Sfx.play("pickup", 0.1, -3.0)
	b.node.queue_free()
	b.node = null


static var _glow: Texture2D


## Mancha de luz redonda e macia (gerada uma vez).
static func _glow_tex() -> Texture2D:
	if _glow != null:
		return _glow
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.9))
	g.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = 64
	gt.height = 64
	_glow = gt
	return _glow
