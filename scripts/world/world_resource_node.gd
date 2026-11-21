class_name WorldResourceNode
extends Node3D
## Veio de minério/cristal ou árvore de Valdoria. Os nós são do mundo: quem coleta primeiro leva e o nó some para
## todos até voltar (Econ.node_gone). Toda árvore do cenário é um nó (`prop`): o nó não monta modelo nem colisão,
## usa os da árvore do mapa (attach_prop) e os esconde quando ela cai.
## O jogador chega perto e aperta F (GatherAction): saca a picareta ou o machado e bate sozinho até o nó ceder.
## Cada golpe soma a força da ferramenta × maestria (GatherRules) até passar a resistência `tough`; aí o nó some
## e pede a coleta ao Econ (solo: concede na hora; online: o servidor confere distância, tempo de volta e a
## ferramenta na mochila, ver WorldHarvest e CharRules.gather).

const ROCK := preload("res://assets/models/rock.glb")

## Id do nó (node_id fixo da MapEntity "resource_node" na cena do mapa; ver WorldHarvest).
var node_id := 0
## Visual: "iron" (rocha com veios), "ore" (rocha na cor `tint`), "crystal" ou um modelo de árvore ("tree_pine"...).
var kind := "iron"
var tint := Color(0.55, 0.3, 0.2)
## Item que o nó dá (o nome aparece no aviso de F).
var item := ""
## Profissão de coleta e o nível dela que o nó pede (sem nível, F só avisa).
var prof := ""
var level := 1
var yaw := 0.0
var size := 1.1
## Raio da colisão (já com a escala); F alcança a partir dessa borda.
var radius := 0.75
## Resistência aos golpes, nível mínimo de ferramenta e segundos para voltar (da tabela).
var tough := 6.0
var tier := 1
var respawn := 180.0
## Árvore do cenário (MapProp do mapa): o visual e a colisão são os dela (attach_prop).
var prop := false
## Escala da árvore: o tronco (TRUNK) cresce com ela.
var trunk_scale := 1.0
var _prop_node: Node3D
var _prop_shapes: Array = []
## Força já somada dos golpes (0..tough). Fica guardada se o jogador parar no meio; zera quando o nó volta.
var progress := 0.0
var alive := true

var _shape: CollisionShape3D
var _visual: Node3D
var _tween: Tween


## Monta o nó a partir de WorldHarvest.node_def().
static func from_def(def: Dictionary) -> WorldResourceNode:
	var n := WorldResourceNode.new()
	n.node_id = int(def.id)
	n.kind = str(def.model)
	n.tint = def.get("tint", n.tint)
	n.item = str(def.get("item", ""))
	n.prof = str(def.get("prof", ""))
	n.level = int(def.get("level", 1))
	n.yaw = float(def.id) * 1.7
	n.tough = float(def.get("tough", 6.0))
	n.tier = int(def.get("tier", 1))
	n.respawn = float(def.respawn)
	n.position = def.pos
	n.prop = bool(def.get("prop", false))
	n.trunk_scale = float(def.get("scale", 1.0)) if n.prop else n.size
	if n.is_tree():
		n.radius = 0.45   # só o tronco bloqueia: o machado alcança de perto
	if n.prop:
		n.size = 1.0   # o modelo já vem na escala da árvore do mapa
		n.yaw = 0.0
		n.radius = float(TRUNK.get(n.kind, 0.24)) * n.trunk_scale + 0.2
	return n


## Liga o nó à árvore `p` do mapa (MapProp montado pelo MapLoader): o modelo dela é o visual que balança e cai, e a
## colisão dela some junto quando cai.
func attach_prop(p: Node3D) -> void:
	_prop_node = p
	for c in p.get_children():
		if c is StaticBody3D:
			for cs in c.get_children():
				if cs is CollisionShape3D:
					_prop_shapes.append(cs)
		elif c is Node3D and _visual == null:
			_visual = c


func _ready() -> void:
	add_to_group("harvest")
	if prop:
		return   # árvore do mapa: visual e colisão são dela (attach_prop)
	var body := StaticBody3D.new()
	body.collision_mask = 0
	_shape = CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = radius
	c.height = 3.0
	_shape.shape = c
	_shape.position.y = 1.5
	body.add_child(_shape)
	add_child(body)
	if DisplayServer.get_name() != "headless":
		_build_visual()


func is_tree() -> bool:
	return kind.begins_with("tree_")


## Raio do tronco de cada modelo de árvore (m, sem a escala; medido nos GLBs na altura do golpe). Pinheiro e abeto
## têm galhos até o chão: o tronco por dentro tem uns 0,22.
const TRUNK := {"tree_pine": 0.22, "tree_fir": 0.22, "tree_oak": 0.3, "tree_birch": 0.16, "tree_maple": 0.28,
		"tree_swamp": 0.3, "tree_dead": 0.26}


## Distância do centro do nó em que o jogador para para bater: árvore = a ponta do machado no impacto
## (GatherAction.CHOP_REACH) encostando na casca; pedra = STAND da borda da colisão.
func stand_distance() -> float:
	if is_tree():
		return GatherAction.chop_target(float(TRUNK.get(kind, 0.24)) * trunk_scale).length()
	return radius + GatherAction.STAND


## Verbo do aviso de F: "Cortar" árvore, "Minerar" o resto.
func verb() -> String:
	return "Cortar" if is_tree() else "Minerar"


## Nome do que sai do nó ("Minério de Ferro").
func item_name() -> String:
	return str(ItemDB.get_item(item).get("name", item))


## Distância do jogador até a borda do nó (o aviso de F e o alcance usam a mesma medida).
func edge_distance(from: Vector3) -> float:
	var to := global_position - from
	to.y = 0.0
	return maxf(0.0, to.length() - radius)


## Pode coletar agora? Confere profissão e ferramenta do jogador local (o servidor confere de novo).
## {"ok", "msg", "tool", "power", "swing", "strikes"}: a melhor ferramenta do tipo, a força de cada golpe com a
## maestria, os segundos de cada golpe e quantos golpes ainda faltam.
## A ferramenta é a do espaço próprio (picareta/machado). Espaço vazio com uma na mochila: o plano usa a melhor da
## mochila e devolve "equip" com ela (player.start_gather equipa antes de bater).
func gather_plan() -> Dictionary:
	var out := {"ok": false, "msg": "", "tool": "", "power": 0.0, "swing": 1.0, "strikes": 0, "kind": ""}
	var kind_t := GatherRules.tool_kind(prof)
	out.kind = kind_t
	if Econ.node_busy(node_id):
		out.msg = Econ.BUSY_TEXT   # outro jogador já está batendo neste nó
		return out
	if prof != "" and Game.prof_level(prof) < level:
		out.msg = "Precisa de %s nível %d." % [Game.prof_name(prof), level]
		return out
	var tool := str(Game.equipment.get(kind_t, ""))
	if tool == "" and kind_t != "":
		tool = GatherRules.best_tool(ItemDB.ITEMS, Game.inventory, kind_t)
		if tool != "":
			out["equip"] = tool
	var ok := GatherRules.check(ItemDB.ITEMS, tool, kind_t, tier)
	if not ok.ok:
		out.msg = GatherRules.refusal_text(ItemDB.ITEMS, ok.err, kind_t, tier)
		return out
	var mastery := Game.prof_level(prof) if prof != "" else 1
	out.ok = true
	out.tool = tool
	out.power = GatherRules.hit_power(ItemDB.ITEMS, tool, mastery)
	out.swing = GatherRules.swing_time(GatherRules.tier(ItemDB.ITEMS, tool), mastery)
	out.strikes = GatherRules.strikes(tough - progress, out.power)
	return out


## Fração da resistência já vencida (0..1), para a barra de progresso.
func ratio() -> float:
	return clampf(progress / maxf(tough, 0.001), 0.0, 1.0)


## Um golpe de ferramenta com força `power` vindo de `from`. Devolve true quando o nó cedeu (e pediu a coleta).
func strike(from: Vector3, power: float) -> bool:
	if not alive or power <= 0.0:
		return false
	progress = minf(tough, progress + power)
	_shake(from)
	if progress < tough - 0.0001:
		return false
	set_alive(false)
	Econ.gather_node(node_id, from)
	get_tree().create_timer(respawn).timeout.connect(_restore)
	return true


## Outro jogador coletou (ou o nó já estava esgotado ao entrar): some agora e volta em `secs` segundos.
func deplete(secs: float) -> void:
	if not alive:
		return
	set_alive(false)
	get_tree().create_timer(maxf(secs, 1.0)).timeout.connect(_restore)


func _restore() -> void:
	if is_inside_tree():
		set_alive(true)


## Liga ou desliga o nó (esgotado/restaurado), com a animação de queda ou de volta.
func set_alive(on: bool) -> void:
	if on == alive:
		return
	alive = on
	if _shape:
		_shape.set_deferred("disabled", not on)
	for cs in _prop_shapes:
		if is_instance_valid(cs):
			cs.set_deferred("disabled", not on)
	if on:
		progress = 0.0
	if _visual == null:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_visual.rotation = Vector3(0, yaw, 0)
	_visual.scale = Vector3.ONE * size
	if on:
		_visual.visible = true
		_visual.scale = Vector3.ONE * size * 0.05
		_tween = create_tween()
		_tween.tween_property(_visual, "scale", Vector3.ONE * size, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		return
	FX.burst(global_position + Vector3.UP * 0.8, _burst_color(), 22, 4.0, 0.14, 0.7)
	_tween = create_tween()
	_tween.tween_property(_visual, "scale", Vector3.ONE * size * 0.05, 0.3)
	_tween.tween_callback(func() -> void: _visual.visible = false)


func _shake(from: Vector3) -> void:
	if _visual == null:
		return
	Sfx.play_at("chop_wood" if is_tree() else "chop_stone", global_position, 0.15, -4.0)
	FX.burst(global_position + Vector3.UP * 1.0, _burst_color(), 8, 3.0, 0.08, 0.4)
	if _tween and _tween.is_valid():
		return
	var away := global_position - from
	away.y = 0
	var lean := away.normalized() * 0.08 if away.length() > 0.01 else Vector3.ZERO
	_tween = create_tween()
	_tween.tween_property(_visual, "rotation", Vector3(lean.z, yaw, -lean.x), 0.06)
	_tween.tween_property(_visual, "rotation", Vector3(0, yaw, 0), 0.18)


func _burst_color() -> Color:
	if kind == "crystal":
		return Color(0.55, 0.45, 1.0)
	if kind.begins_with("tree_"):
		return Color(0.45, 0.3, 0.15)
	return ore_color()


# ================================================================ visual (fora do headless)
func _build_visual() -> void:
	if kind.begins_with("tree_"):
		_visual = (load(MapProp.model_path(kind)) as PackedScene).instantiate()
		_visual.rotation.y = yaw
		_visual.scale = Vector3.ONE * size
		add_child(_visual)
		if tint != Color(0.55, 0.3, 0.2):
			_tint(_visual, tint)
		return
	_visual = Node3D.new()
	_visual.rotation.y = yaw
	_visual.scale = Vector3.ONE * size
	add_child(_visual)
	var r := RandomNumberGenerator.new()
	r.seed = node_id * 7919 + 13   # detalhes só visuais: não mexem no rng do mapa
	if kind == "crystal":
		_build_crystal(r)
		return
	_build_ore(r)


## Cor do minério de um veio: a da tabela ("ore") ou o cinza-aço do ferro.
func ore_color() -> Color:
	return Color(0.52, 0.54, 0.6) if kind == "iron" else tint


## Veio de minério: uma pedra baixa e escura com o minério saindo dela em lascas grandes (prismas de 6 faces que
## nascem de dentro da pedra e apontam para fora) e pepitas no chão em volta. O minério é a maior parte do que se vê,
## para dar para reconhecer o tipo de longe. Os comuns (nível 1: cobre, ferro) saem em blocos curtos e grossos, como
## pepitas de metal; os raros em cristais pontudos que brilham de leve (nível 2) ou com luz própria (nível 3).
func _build_ore(r: RandomNumberGenerator) -> void:
	var rock := ROCK.instantiate() as Node3D
	rock.scale = Vector3(0.78, 0.62, 0.78)
	_visual.add_child(rock)
	_tint(rock, Color(0.3, 0.28, 0.27) if tier >= 2 else Color(0.38, 0.36, 0.34))
	var color := ore_color()
	var glow := 0.0 if tier <= 1 else (0.45 if tier == 2 else 1.1)
	var mats := [_ore_mat(color, glow), _ore_mat(color.lightened(0.25), glow), _ore_mat(color.darkened(0.2), glow)]
	if kind == "iron":
		mats[2] = _ore_mat(Color(0.66, 0.36, 0.22), 0.0)   # ferrugem entre o aço
	var chunky := tier <= 1
	# lascas: espalhadas por cima e pelos lados da pedra, a maior no topo
	var n := r.randi_range(7, 9)
	for i in n:
		var up := 1.0 if i == 0 else r.randf_range(0.25, 0.85)       # 1 = de pé no topo; 0 = deitada para o lado
		var a := TAU * float(i) / float(n) + r.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a) * sqrt(1.0 - up * up), up, sin(a) * sqrt(1.0 - up * up)).normalized()
		var big := 1.25 if i == 0 else r.randf_range(0.75, 1.1)
		var m := CylinderMesh.new()
		m.radial_segments = 6
		m.rings = 1
		m.bottom_radius = (0.19 if chunky else 0.15) * big
		m.top_radius = m.bottom_radius * (r.randf_range(0.7, 0.9) if chunky else r.randf_range(0.35, 0.6))
		m.height = (r.randf_range(0.34, 0.46) if chunky else r.randf_range(0.5, 0.7)) * big
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = mats[i % mats.size()]
		# a base fica enterrada na pedra (centro em 0,3 m de altura) e mais da metade sai para fora
		var base := Vector3(0, 0.3, 0) + out * 0.28
		mi.basis = Basis(Quaternion(Vector3.UP, out)).rotated(out, r.randf() * TAU)
		mi.position = base + out * m.height * 0.42
		_visual.add_child(mi)
	# pepitas soltas no chão, como se tivessem lascado da pedra
	for i in r.randi_range(3, 4):
		var a := r.randf() * TAU
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radial_segments = 6
		sm.rings = 3
		mi.mesh = sm
		mi.material_override = mats[(i + 1) % mats.size()]
		var d := r.randf_range(0.62, 0.8)
		mi.position = Vector3(cos(a) * d, 0.04, sin(a) * d)
		mi.rotation = Vector3(r.randf_range(-0.5, 0.5), r.randf() * TAU, r.randf_range(-0.5, 0.5))
		mi.scale = Vector3(1.0, 0.6, 0.8) * r.randf_range(0.14, 0.2)
		_visual.add_child(mi)
	if tier >= 3:
		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = 0.7
		light.omni_range = 4.0
		light.position.y = 0.9
		_visual.add_child(light)


## Material das lascas: metálico e liso, para pegar reflexo; os raros com brilho próprio (`glow`).
func _ore_mat(color: Color, glow: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = 0.45
	m.roughness = 0.35
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


func _build_crystal(r: RandomNumberGenerator) -> void:
	var color := Color(0.55, 0.3, 0.95)
	for i in r.randi_range(3, 5):
		var m := CylinderMesh.new()
		m.radial_segments = 6
		m.rings = 1
		m.top_radius = 0.04
		m.bottom_radius = r.randf_range(0.16, 0.26)
		m.height = r.randf_range(0.9, 1.8)
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = _mat(color.lerp(Color(0.4, 0.35, 1.0), r.randf()), 1.0)
		var a := r.randf() * TAU
		var d := 0.0 if i == 0 else r.randf_range(0.2, 0.45)
		mi.position = Vector3(cos(a) * d, m.height * 0.42, sin(a) * d)
		mi.rotation = Vector3(r.randf_range(-0.35, 0.35), 0, r.randf_range(-0.35, 0.35))
		_visual.add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.6
	light.omni_range = 4.5
	light.position.y = 1.0
	_visual.add_child(light)


func _mat(color: Color, glow: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.4 if glow > 0.0 else 0.9
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


func _tint(n: Node, color: Color) -> void:
	if n is MeshInstance3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.95
		n.material_override = m
	for c in n.get_children():
		_tint(c, color)
