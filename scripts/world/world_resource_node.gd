class_name WorldResourceNode
extends Node3D
## Veio de minério/cristal ou árvore de coleta de Valdoria. Cada jogador tem os seus nós, como o saque pessoal.
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
	if n.is_tree():
		n.radius = 0.45   # só o tronco bloqueia: o machado alcança de perto
	return n


func _ready() -> void:
	add_to_group("harvest")
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
const TRUNK := {"tree_pine": 0.22, "tree_fir": 0.22, "tree_oak": 0.3, "tree_birch": 0.16, "tree_maple": 0.28}


## Distância do centro do nó em que o jogador para para bater: árvore = a ponta do machado no impacto
## (GatherAction.CHOP_REACH) encostando na casca; pedra = STAND da borda da colisão.
func stand_distance() -> float:
	if is_tree():
		return GatherAction.chop_target(float(TRUNK.get(kind, 0.24)) * size).length()
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
func gather_plan() -> Dictionary:
	var out := {"ok": false, "msg": "", "tool": "", "power": 0.0, "swing": 1.0, "strikes": 0}
	if prof != "" and Game.prof_level(prof) < level:
		out.msg = "Precisa de %s nível %d." % [Game.prof_name(prof), level]
		return out
	var kind_t := GatherRules.tool_kind(prof)
	var tool := GatherRules.best_tool(ItemDB.ITEMS, Game.inventory, kind_t)
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
	return tint


# ================================================================ visual (fora do headless)
func _build_visual() -> void:
	if kind.begins_with("tree_"):
		_visual = (load(MapProp.model_path(kind)) as PackedScene).instantiate()
		_visual.rotation.y = yaw
		_visual.scale = Vector3.ONE * size
		add_child(_visual)
		if tint != Color(0.55, 0.3, 0.2):
			_tint(_visual, tint)
		# fita amarela no tronco: árvore que dá para cortar (as de enfeite não têm)
		var band := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.3
		cyl.bottom_radius = 0.3
		cyl.height = 0.18
		band.mesh = cyl
		band.position.y = 1.1
		band.material_override = _mat(Color(1.0, 0.8, 0.2), 0.3)
		_visual.add_child(band)
		return
	_visual = Node3D.new() if kind == "crystal" else ROCK.instantiate()
	_visual.rotation.y = yaw
	_visual.scale = Vector3.ONE * size
	add_child(_visual)
	var r := RandomNumberGenerator.new()
	r.seed = node_id * 7919 + 13   # detalhes só visuais: não mexem no rng do mapa
	if kind == "crystal":
		_build_crystal(r)
		return
	_tint(_visual, Color(0.55, 0.3, 0.2) if kind == "iron" else Color(0.42, 0.4, 0.38))
	for i in 6:
		var a := r.randf() * TAU
		var mi := MeshInstance3D.new()
		mi.mesh = SphereMesh.new()
		mi.material_override = _mat(Color(0.12, 0.1, 0.1), 0.0) if kind == "iron" else _mat(tint, 0.4)
		mi.position = Vector3(cos(a) * 0.45, r.randf_range(0.25, 0.65), sin(a) * 0.45)
		mi.rotation = Vector3(r.randf_range(-0.6, 0.6), r.randf() * TAU, r.randf_range(-0.6, 0.6))
		mi.scale = Vector3.ONE * 0.12 * r.randf_range(0.8, 1.3)
		_visual.add_child(mi)


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
