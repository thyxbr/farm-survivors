class_name WorldSummary
extends RefCounted
## Coleta o retrato (MapSummary) de um mundo já montado: modelos, colisões, luzes, peças montadas por código,
## textos, NPCs e pontos de jogo, pontos de monstro e o chão (formas, morros, serra). Fica de fora o que é
## sorteado a cada montagem ou não é conteúdo de mapa: capim e plantações (MultiMesh), jogador, interface,
## monstros vivos (os pontos deles entram), clima. Flores de canteiro de casa entram só pela contagem.

## Scripts de jogo que contam como "entidade" (o resto com script é interface/jogador/clima e fica de fora).
const ENTITY_SCRIPTS := ["elder", "merchant", "alchemist", "blacksmith", "rival", "villager_npc", "knight_npc",
	"story_point", "hub_point", "farm_plot", "kitchen", "challenge_portal", "santa", "christmas_event_point",
	"world_resource_node"]
const ID_FIELDS := ["npc_id", "kind", "building_id", "index", "node_id"]
const BED_FLOWERS := ["flower_lavender", "flower_tulips"]


static func collect(w: Node3D) -> PackedStringArray:
	var out := PackedStringArray()
	var flicker := {}
	for f in w.get("flicker_lights"):
		flicker[f[0]] = f[1]   # força-base (a luz em si muda a cada quadro)
	for c in w.get_children():
		_walk(c, out, flicker)
	for s in w.get("spawns"):
		out.append("spawn|%s;%s;%s" % [s.kind, MapSummary.vec(s.pos), MapSummary.num(s.respawn)])
	var grounds: Array = [w.get("ground")]
	grounds.append_array((w.get("region_grounds") as Dictionary).values())
	for g in grounds:
		if g != null:
			_ground(g, out)
	out.sort()
	return out


static func _yaw(n: Node3D) -> String:
	var f := n.global_basis.z.normalized()
	return "%s;%s" % [MapSummary.num(f.x), MapSummary.num(f.z)]


static func _script_name(n: Node) -> String:
	var s: Script = n.get_script()
	return s.resource_path.get_file().get_basename() if s != null else ""


static func _walk(n: Node, out: PackedStringArray, flicker: Dictionary) -> void:
	if n is Node3D and (n as Node3D).global_position.y < -50.0:
		return   # algo caindo (efeito, objeto solto): não é conteúdo de mapa
	if n is MultiMeshInstance3D or n is CanvasLayer or n is Camera3D or n is AudioStreamPlayer3D:
		return
	if n.has_method("build_terrain") or n.has_method("take_damage"):
		return   # chão (registrado à parte) e monstros vivos
	var sname := _script_name(n)
	var model := ""
	if n.scene_file_path.begins_with("res://assets/models/"):
		model = n.scene_file_path.get_file().get_basename()
	if n is Node3D:
		var n3 := n as Node3D
		if model in BED_FLOWERS:
			out.append("flower|bed")
			return
		if model != "":
			out.append("prop|%s;%s;%s;%s" % [model, MapSummary.vec(n3.global_position), _yaw(n3),
				MapSummary.num(n3.global_basis.get_scale().x)])
		elif sname in ENTITY_SCRIPTS:
			var ids := PackedStringArray()
			for k in ID_FIELDS:
				var v = n.get(k)
				if v != null:
					ids.append("%s=%s" % [k, str(v)])
			out.append("entity|%s|%s;%s;%s" % [sname, ",".join(ids), MapSummary.vec(n3.global_position), _yaw(n3)])
			return
		elif sname != "" and not sname.begins_with("map_") and sname != "enemy_spawn":
			return   # jogador, interface, clima, ferramentas (as peças das cenas de mapa só agrupam)
		elif n is CollisionShape3D:
			var sh: Shape3D = (n as CollisionShape3D).shape
			var size := Vector3.ZERO
			if sh is BoxShape3D:
				size = (sh as BoxShape3D).size
			elif sh is CylinderShape3D:
				size = Vector3((sh as CylinderShape3D).radius, (sh as CylinderShape3D).height, 0)
			# cilindro girado em volta do eixo vertical é a mesma colisão: o giro só conta na caixa
			out.append("body|%s;%s;%s%s" % [sh.get_class(), MapSummary.vec(n3.global_position), MapSummary.vec(size),
				";" + _yaw(n3) if sh is BoxShape3D else ""])
		elif n is OmniLight3D:
			var l := n as OmniLight3D
			var mode := "flicker" if flicker.has(l) else ("night" if l.has_meta("night_energy") else "normal")
			var energy: float = l.light_energy
			if mode == "night":
				energy = l.get_meta("night_energy")
			elif mode == "flicker":
				energy = flicker[l]
			out.append("light|%s;%s;%s;%s;%s;%s;%s" % [mode, MapSummary.vec(l.global_position), MapSummary.num(energy),
				MapSummary.num(l.omni_range), MapSummary.num(l.light_color.r), MapSummary.num(l.light_color.g),
				MapSummary.num(l.light_color.b)])
		elif n is Label3D:
			out.append("label|%s;%s" % [(n as Label3D).text.replace(";", ",").replace("\n", " "),
				MapSummary.vec(n3.global_position)])
		elif n is MeshInstance3D and (n.name.begins_with("ToonOutline") or (n as MeshInstance3D).mesh is ImmediateMesh):
			return   # contorno do toon (só existe com o estilo ligado) e desenho imediato (efeitos)
		elif n is MeshInstance3D:
			# o centro da malha no mundo (a origem do nó pode mudar sem a malha mudar de lugar)
			var mi := n as MeshInstance3D
			var at := mi.global_transform * mi.get_aabb().get_center() if mi.mesh else n3.global_position
			out.append("mesh|%s;%s" % [mi.mesh.get_class() if mi.mesh else "none", MapSummary.vec(at)])
	for c in n.get_children():
		# dentro de um modelo, só o que o código pendurou nele (luzes, enfeites); as peças do GLB têm dono
		if model != "" and c.owner == n:
			continue
		_walk(c, out, flicker)


static func _ground(g: Node3D, out: PackedStringArray) -> void:
	var o: Vector3 = g.global_position
	var shapes: PackedVector4Array = g.get("_shapes")
	var cols: PackedVector4Array = g.get("_cols")
	var mix: PackedFloat32Array = g.get("_mix")
	for i in shapes.size():
		var s := shapes[i]
		var c := cols[i]
		out.append("paint|%s;%s;%s;%s;%s;%s;%s;%s;%s;%s" % ["disc" if s.w < 0.0 else "rect", MapSummary.num(o.x + s.x),
			MapSummary.num(o.z + s.y), MapSummary.num(s.z), MapSummary.num(s.w), MapSummary.num(c.x), MapSummary.num(c.y),
			MapSummary.num(c.z), MapSummary.num(c.w), MapSummary.num(mix[i])])
	for pk: Vector4 in g.get("_peaks"):
		out.append("mountain;%s;%s;%s;%s" % [MapSummary.num(o.x + pk.x), MapSummary.num(o.z + pk.y),
			MapSummary.num(pk.z), MapSummary.num(pk.w)])
	out.append("border;%s;%s;%s" % [MapSummary.num(o.x), MapSummary.num(o.z), MapSummary.num(g.get("_ring_height"))])
