@tool
class_name MapRoot
extends Node3D
## Raiz de uma cena de mapa (scenes/maps/<mapa>.tscn). Guarda o que vale para o mapa inteiro (tamanho, serra
## da borda, capim) e sabe ler das peças o que o chão precisa: formas pintadas, morros e as áreas do capim.
## O jogo (MapLoader) e a prévia do editor usam as mesmas leituras, então o editor mostra o chão de verdade
## (ground.gd), com a luz (WorldLighting) e o toon do jogo.
##
## A cena fica em coordenadas do mapa; no jogo ela vai para a origem da região (Regions.origin).

const GROUND := "res://scripts/world/ground.gd"
const PLAN := "Planta"

## Mapa: vila (vale de Valdoria), bosque, mina ou pico.
@export_enum("vila", "bosque", "mina", "pico", "arena", "dg_bosque", "dg_mina", "dg_pico", "dg_final") var map_id := "vila"
## Usa o chão de Valdoria (ground.gd: relevo, serra, formas pintadas). A Arena não usa: o chão dela são
## discos e uma colisão de caixa da própria cena.
@export var has_ground := true
## Meia largura da área jogável (m).
@export var half := 125.0
## Altura da serra em volta do mapa (0 = sem serra).
@export var border_height := 58.0
## Passagem na serra do sul (a estrada por onde o aventureiro chega): x do meio e meia largura do fundo (m);
## 0 = sem passagem. O vale da passagem vai sumindo numa curva uns 30 m depois da borda.
@export var south_pass_x := 0.0
@export var south_pass_width := 0.0
## Densidade do capim (0..1) e das plantinhas no meio dele.
@export_range(0.0, 1.0, 0.01) var grass_density := 0.6
@export_range(0.0, 2.0, 0.05) var grass_plants := 1.0
## Semente do sorteio do capim.
@export var grass_seed := 0
## Mostra no editor o chão, a luz e o resto da prévia.
@export var show_preview := true:
	set(v):
		show_preview = v
		_queue_rebuild()
## Mostra o contorno das colisões dos objetos (caixas e cilindros azuis).
@export var show_colliders := false:
	set(v):
		show_colliders = v
		_queue_rebuild()
## Desenha também o capim na prévia (pesado: desligado por padrão).
@export var preview_grass := false:
	set(v):
		preview_grass = v
		_queue_rebuild()

var _ground: Node3D = null
var _rebuild_queued := false


func _ready() -> void:
	if Engine.is_editor_hint():
		_queue_rebuild()


# ---------------------------------------------------------------- leituras (jogo e editor)

## Peças de um tipo, em qualquer profundidade.
func pieces(type: Script) -> Array:
	return all_pieces().filter(func(n: Node) -> bool: return n.get_script() == type)


## Todas as peças da cena (nós com script de peça), em ordem da árvore, sem entrar nas prévias.
func all_pieces() -> Array:
	var out: Array = []
	_walk(self, out)
	return out


func _walk(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c.name == MapPreview.NAME or c.name == PLAN:
			continue
		if c.has_method("build_preview"):
			out.append(c)
		_walk(c, out)


func local_xform(n: Node3D) -> Transform3D:
	return MapData.local_xform(self, n)


## Formas pintadas no chão, em coordenadas do mapa. `angle` = giro do retângulo em Y (o do nó, somado ao dos
## grupos acima dele), para ruas na diagonal.
func paint_data() -> Array:
	var out: Array = []
	for p: MapGroundPaint in pieces(MapGroundPaint):
		var xf := local_xform(p)
		var ax := xf.basis.x
		out.append({"center": xf.origin, "disc": p.disc, "size": p.size, "radius": p.radius,
			"color": p.color, "soft": p.soft, "grass": p.ground_mix(), "angle": snappedf(-atan2(ax.z, ax.x), 0.0001)})
	return out


## Morros: Vector4(x, z, raio, altura) em coordenadas do mapa.
func mountain_data() -> Array:
	var out: Array = []
	for m: MapMountain in pieces(MapMountain):
		var c := local_xform(m).origin
		out.append(Vector4(c.x, c.z, m.radius, m.height))
	return out


## Áreas do capim em coordenadas do mapa: {"keep_out": [[Vector2, raio]], "sparse": [[Vector2, raio]]}.
## keep_out = áreas sem capim + pegada dos objetos com colisão e no_grass (raio + 0,15 m, como o prop() antigo).
func grass_lists() -> Dictionary:
	var keep: Array = []
	var sparse: Array = []
	for a: MapGrassArea in pieces(MapGrassArea):
		var c := local_xform(a).origin
		(sparse if a.sparse else keep).append([Vector2(c.x, c.z), a.radius])
	for p: MapProp in pieces(MapProp):
		if p.no_grass and p.shape != 0:
			var c := local_xform(p).origin
			keep.append([Vector2(c.x, c.z), p.footprint() + 0.15])
	for r: MapRiver in pieces(MapRiver):
		keep.append_array(r.grass_discs())
	return {"keep_out": keep, "sparse": sparse}


## Chão do mapa montado com as formas e os morros da cena (sem pôr na árvore; quem chama adiciona e depois
## chama build_terrain). `world_offset` = origem da região no plano (o shader desenha em coordenadas do mundo).
func make_ground(world_offset := Vector2.ZERO) -> Node3D:
	var g: Node3D = load(GROUND).new()
	g.name = "Ground_" + map_id
	g.world_offset = world_offset
	g.biome = BiomeRules.of(map_id)
	g.setup(half)
	for p in paint_data():
		if p.disc:
			g.add_disc(p.center, p.radius, p.color, p.soft, p.grass)
		else:
			g.add_rect(p.center, p.size, p.color, p.soft, p.grass, p.angle)
	for m: Vector4 in mountain_data():
		g.add_mountain(Vector3(m.x, 0, m.y), m.z, m.w)
	for r: MapRiver in pieces(MapRiver):
		g.add_river(r.samples(), r.half_total())
	g.border_mountains(border_height)
	g.border_pass(south_pass_x, south_pass_width)
	return g


# ---------------------------------------------------------------- prévia no editor

func _queue_rebuild() -> void:
	if not Engine.is_editor_hint() or _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


## Uma peça do chão (forma pintada, morro) mudou: remonta o chão e reassenta as peças no relevo.
static func ground_changed(piece: Node) -> void:
	var p := piece.get_parent()
	while p != null and not p is MapRoot:
		p = p.get_parent()
	if p != null:
		(p as MapRoot)._queue_rebuild()


func _rebuild() -> void:
	_rebuild_queued = false
	if is_inside_tree():
		build_preview()


## Monta a prévia: chão de verdade, luz do jogo e a prévia de cada peça assentada no relevo.
func build_preview() -> void:
	var old := get_node_or_null(PLAN)
	if old != null:
		remove_child(old)
		old.free()
	_ground = null
	if not show_preview:
		return
	MapPreview.show_colliders = show_colliders
	var plan := Node3D.new()
	plan.name = PLAN
	add_child(plan)
	load("res://scripts/world/world_lighting.gd").build(plan)
	if has_ground:
		_ground = make_ground()
		plan.add_child(_ground)
		_ground.build_terrain()
	if has_ground and preview_grass:
		var g := grass_lists()
		_ground.scatter_grass(grass_seed, grass_density, g.keep_out, g.sparse, grass_plants)
	var height := Callable(_ground, "height_at") if _ground != null else Callable()
	for n in all_pieces():
		n.build_preview(height)
	MapPreview.toon(plan)


## Altura do chão da prévia (Callable inválido se não há prévia).
func preview_height() -> Callable:
	return Callable(_ground, "height_at") if _ground != null else Callable()
