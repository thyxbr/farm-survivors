@tool
class_name VillageLayout
extends RefCounted
## Planta da vila de Valdoria (world.gd monta): ruas, casas (lidas de scenes/maps/vale.tscn), os pontos que vieram da antiga praça da cidade
## e os lugares dos eventos de Natal do Papai Noel. Só dados e contas puras (sem autoload), para os testes.
##
## A praça do poço continua no meio, com as seis casas de sempre em volta. Dela saem as ruas: a Rua do
## Portal ao norte (atravessa a vila de ponta a ponta), a Rua das Flores ao sul, a Rua do Oeste e a Estrada
## Leste (a trilha do acampamento goblin), cortadas por duas travessas. Os bairros novos ficam a oeste
## (casas e a Muralha, no caminho da arena) e a leste (Forja, Celeiro e o Largo dos Ecos, com o Mestre Orin,
## a mesa de guerra e o quadro de recordes).
##
## Frente das casas = +Z do modelo (yaw 0 olha para o sul, PI para o norte, PI/2 para o leste).

const S := 0.0
const N := PI
const E := PI / 2
const W := -PI / 2

## Limites da cerca (x0, x1, z0, z1) e as aberturas: [lado, centro, meia largura].
const BOUNDS := Rect2(-36, -18, 75, 45)
## O lado sul não tem cerca entre x = -12 e 12: ali a cerca da Horta faz a divisa (com o portão dela).
## No oeste, em z = 10, a Muralha da base ocupa o vão da cerca. O portão norte é largo: a carruagem da guilda
## (Regions.coach_point("vila")) para logo ali, no começo da trilha dos campos.
const GATES := [["n", -5.0, 8.2], ["e", 0.0, 3.0], ["w", 2.5, 3.0], ["w", 10.0, 2.6], ["s", 20.0, 2.0]]
const SOUTH_OPEN := 12.0

## Ruas pintadas no chão: [centro, tamanho (x, z)].
const STREETS := [
	[Vector3(1.5, 0, -15), Vector2(73, 4.0)],    # Rua do Portal (norte, de ponta a ponta)
	[Vector3(-25, 0, 2.5), Vector2(22, 4.0)],    # Rua do Oeste (até o portão oeste e a arena)
	[Vector3(28, 0, 0), Vector2(22, 4.0)],       # Estrada Leste (vira a trilha do acampamento)
	[Vector3(1.5, 0, 20), Vector2(73, 3.6)],     # Rua das Flores (sul)
	[Vector3(-26, 0, 2.5), Vector2(4.0, 35)],    # Travessa do Moinho (oeste)
	[Vector3(27, 0, 2.5), Vector2(4.0, 35)],     # Travessa do Leste
	[Vector3(0, 0, -10), Vector2(4.0, 10)],      # saída norte da praça até a Rua do Portal
]
## Cor do calçamento das ruas (a praça é Color(0.5, 0.45, 0.36)).
const STREET_COLOR := Color(0.5, 0.46, 0.38)

## Colisão (largura, altura, profundidade) de cada modelo de casa.
const HOUSE_SIZE := {
	"house": Vector3(5.2, 3.2, 4.2), "house_b": Vector3(5.2, 3.2, 4.2), "house_c": Vector3(5.2, 3.2, 4.2),
	"house_d": Vector3(5.6, 3.0, 4.4), "house_e": Vector3(7.6, 3.6, 4.8), "house_f": Vector3(3.8, 4.0, 3.8),
}

## Pegada (largura, profundidade) das construções que não são casa, para os testes da planta.
const FOOTPRINT := {
	"shop_merchant": Vector2(5.2, 3.6), "shop_alchemist": Vector2(4.4, 3.8), "shop_smithy": Vector2(4.6, 4.6),
	"well": Vector2(1.9, 1.9),
}

## Colisões das lojas no espaço delas: [boxes [[centro local, tamanho]], cyls [[centro local, raio]],
## raio sem capim]. A ferraria tem a origem no ferreiro: a forja fica sob a coifa, a bigorna na frente.
const SHOP_SHAPES := {
	"shop_merchant": [[[Vector3(0, 0, -0.4), Vector3(5.2, 3.0, 3.6)]], [], 3.4],
	"shop_alchemist": [[[Vector3(0.2, 0, 0), Vector3(4.4, 3.4, 3.8)]],
		[[Vector3(-2.05, 0, -1.8), 0.95], [Vector3(-1.05, 0, 2.85), 0.45]], 3.6],
	"shop_smithy": [[[Vector3(0, 0, -2.6), Vector3(4.0, 3.0, 0.5)], [Vector3(-1.8, 0, -0.7), Vector3(0.4, 1.1, 3.4)]],
		[[Vector3(1.4, 0, -0.4), 0.5]], 2.8],
}
## Onde o dono fica, no espaço da loja (a Mira atrás do balcão do empório, a Pip na porta da botica).
const MERCHANT_SPOT := Vector3(-0.7, 0, 2.4)
const ALCHEMIST_SPOT := Vector3(0.3, 0, 3.0)

## As construções (casas, lojas e o poço) ficam na cena do vale (scenes/maps/vale.tscn), que se edita no 3D do Godot
## (VillageBuilding). O jogo lê a cena uma vez e guarda: buildings() devolve os dados de cada uma.
const SCENE := "res://scenes/maps/vale.tscn"
static var _buildings: Array = []

## Paletas: [reboco (multiplica a cor original), telhado (cor nova), venezianas (cor nova)].
const PALETTES := [
	[Color(1.0, 1.0, 1.0), Color(0.42, 0.27, 0.18), Color(0.12, 0.3, 0.16)],
	[Color(1.05, 0.88, 0.82), Color(0.58, 0.3, 0.2), Color(0.1, 0.22, 0.45)],
	[Color(0.88, 0.95, 1.08), Color(0.32, 0.37, 0.5), Color(0.6, 0.45, 0.1)],
	[Color(1.0, 1.0, 1.0), Color(0.3, 0.45, 0.42), Color(0.12, 0.3, 0.16)],
	[Color(1.1, 0.96, 0.75), Color(0.33, 0.38, 0.52), Color(0.1, 0.22, 0.45)],
	[Color(0.92, 1.02, 0.88), Color(0.52, 0.22, 0.14), Color(0.45, 0.08, 0.06)],
	[Color(1.12, 1.08, 1.0), Color(0.3, 0.42, 0.25), Color(0.6, 0.45, 0.1)],
	[Color(1.0, 0.9, 0.85), Color(0.42, 0.27, 0.18), Color(0.1, 0.22, 0.45)],
	[Color(0.95, 1.0, 1.1), Color(0.55, 0.26, 0.16), Color(0.12, 0.3, 0.16)],
	[Color(1.08, 0.92, 0.8), Color(0.3, 0.45, 0.42), Color(0.45, 0.08, 0.06)],
	[Color(1.0, 0.95, 0.88), Color(0.58, 0.3, 0.2), Color(0.1, 0.22, 0.45)],
	[Color(0.9, 0.98, 1.05), Color(0.3, 0.42, 0.25), Color(0.6, 0.45, 0.1)],
	[Color(0.95, 1.05, 0.95), Color(0.42, 0.27, 0.18), Color(0.45, 0.08, 0.06)],
	[Color(1.1, 1.0, 0.82), Color(0.3, 0.45, 0.42), Color(0.12, 0.3, 0.16)],
	[Color(1.0, 0.92, 0.9), Color(0.33, 0.38, 0.52), Color(0.6, 0.45, 0.1)],
	[Color(1.05, 1.05, 1.0), Color(0.52, 0.22, 0.14), Color(0.1, 0.22, 0.45)],
]

## Pontos que eram da praça da cidade: [kind, posição, yaw (frente do ponto), building_id].
## Construção da base: o prédio fica BUILDING_BACK atrás do ponto (hub_point.gd).
const POINTS := [
	["building", Vector3(33.5, 0, -2.4), S, "forja"],
	["building", Vector3(33.5, 0, 2.4), N, "celeiro"],
	["building", Vector3(-32.4, 0, 10.0), E, "muralha"],
	["passive_master", Vector3(21.0, 0, 11.6), N, ""],
	["war_table", Vector3(24.6, 0, 6.4), W, ""],
	["records", Vector3(17.4, 0, 6.4), E, ""],
]
## Largo dos Ecos (calçamento em volta do Orin, da mesa de guerra e dos recordes).
const LARGO := Vector3(21.0, 0, 7.6)

## Papai Noel: do outro lado da árvore de Natal grande (a Lina e o Quadro de Contratos da guilda ficam do lado
## oeste dela), de frente para a praça; o trenó fica entre ele e a árvore.
const SANTA := Vector3(16.0, 0, -11.4)
const SANTA_YAW := -0.92
const SLEIGH := Vector3(12.7, 0, -11.9)
const SLEIGH_YAW := -2.2

## Horta da Vila (saída sul), o pomar a leste dela e o portal do Desafio da Horda (world.gd usa estas).
const FARM := Vector3(0, 0, 33)
const ORCHARD := Vector3(20, 0, 33)
const PORTAL := Vector3(-8, 0, -9.5)
## Lampiões: os quatro da praça (com o varal de luzes entre eles) e os das esquinas das ruas.
const LAMPS_SQUARE := [Vector3(-5, 0, -5), Vector3(5, 0, -5), Vector3(6, 0, 8), Vector3(-6, 0, 8)]
const LAMPS_STREET := [Vector3(-23.6, 0, -12.6), Vector3(-23.6, 0, 4.9), Vector3(-23.7, 0, 17.8),
	Vector3(-34.0, 0, 0.2), Vector3(24.6, 0, -12.6), Vector3(24.6, 0, 2.4), Vector3(24.6, 0, 17.8),
	Vector3(37.0, 0, -2.3), Vector3(-3.0, 0, -12.8), Vector3(3.0, 0, -12.8)]
## Varal de luzes atravessando a saída norte da praça (entre os dois últimos lampiões das esquinas).
const NORTH_STRING := [Vector3(-3.0, 0, -12.8), Vector3(3.0, 0, -12.8)]
## Cerejeiras da praça: [posição, yaw, escala] (uma atrás da botica).
const CHERRIES := [[Vector3(-17, 0, -1.5), 0.3, 0.85], [Vector3(9, 0, 11.5), 2.0, 0.75]]
## Natal: a árvore grande ao lado do quadro de avisos, as pequenas na frente da botica e do empório, o
## boneco de neve olhando para o poço e os presentes ao pé do poço.
const XMAS_TREE := Vector3(8.8, 0, -10.3)
const XMAS_SMALL := [Vector3(-9.2, 0, 3.6), Vector3(8.4, 0, -3.6)]
const SNOWMAN := Vector3(-8.5, 0, -3.6)
const WELL_GIFTS := Vector3(1.4, 0, -1.4)
## Poste de direção perto do portão sul e o quadro de avisos da guilda ao norte da praça.
const SIGNPOST := Vector3(-1.8, 0, 20.5)
const NOTICE_BOARD := Vector3(5.0, 0, -10.6)

## Presentes Espalhados: 8 pontos pelo vale (fora da vila).
const GIFTS := [
	Vector3(-22, 0, -31),     # campos do noroeste
	Vector3(22, 0, -48),      # campos do nordeste
	Vector3(46, 0, 22),       # beira da floresta leste
	Vector3(26, 0, 44),       # depois do pomar
	Vector3(-24, 0, 44),      # perto do Ninho de Slimes
	Vector3(-50, 0, 18),      # caminho da arena
	Vector3(-8, 0, -78),      # trilha das Ruínas
	Vector3(54, 0, -24),      # perto do Acampamento Goblin
]


## Construções (VillageBuilding) do vale.tscn, na ordem da árvore: {name, model, pos, yaw, palette, flowers,
## delivery}. Só a posição e o giro em Y contam (o nó pode estar dentro de grupos, que também podem girar).
static func buildings() -> Array:
	if _buildings.is_empty():
		var root: Node = (load(SCENE) as PackedScene).instantiate()
		for n in root.find_children("*", "Node3D", true, false):
			if not n is VillageBuilding:
				continue
			var xf := Transform3D()
			var p: Node = n
			while p != root:
				xf = (p as Node3D).transform * xf
				p = p.get_parent()
			_buildings.append({"name": str(root.get_path_to(n)), "model": n.model, "pos": xf.origin,
				"yaw": xf.basis.get_euler().y, "palette": n.palette, "flowers": n.flowers, "delivery": n.delivery})
		root.free()
	return _buildings


## Só as casas (modelos house*), na ordem da cena.
static func houses() -> Array:
	return buildings().filter(func(b: Dictionary) -> bool: return str(b.model).begins_with("house"))


## Entregas na Vila: as casas marcadas com "delivery", na ordem da cena (a missão pede 6).
static func deliveries() -> Array:
	return houses().filter(func(b: Dictionary) -> bool: return b.delivery)


## A primeira construção com esse modelo ({} se a cena não tem nenhuma).
static func first(model: String) -> Dictionary:
	for b in buildings():
		if b.model == model:
			return b
	return {}


## Transform3D da construção no mundo.
static func xform(b: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, b.yaw), b.pos)


## Pinta uma casa com a paleta: reboco (multiplica a cor), telhado e venezianas (trocam a cor). Os materiais
## pintados são guardados por cor (todas as casas com a mesma paleta dividem o mesmo material) e entram como
## override de superfície antes da conversão do toon (que acontece no quadro seguinte).
static var _tinted := {}


static func tint(house: Node, palette: int) -> void:
	if palette < 0 or palette >= PALETTES.size():
		return
	var pal: Array = PALETTES[palette]
	for mi: MeshInstance3D in house.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if src == null:
				continue
			var c := _swap(src.resource_name, src.albedo_color, pal)
			if c == src.albedo_color:
				continue
			var key := "%s|%s" % [src.resource_name, c.to_html()]
			if not _tinted.has(key):
				var m := src.duplicate() as BaseMaterial3D
				m.albedo_color = c
				_tinted[key] = m
			mi.set_surface_override_material(s, _tinted[key])


## Cor nova de um material da casa pela paleta (a mesma cor se ele não muda).
static func _swap(mat_name: String, c: Color, pal: Array) -> Color:
	if mat_name.begins_with("v_plaster") and not mat_name.ends_with("dark"):
		var k: Color = pal[0]
		return Color(clampf(c.r * k.r, 0, 1), clampf(c.g * k.g, 0, 1), clampf(c.b * k.b, 0, 1), c.a)
	if mat_name in ["p_roof", "v_slate", "v_roof_teal", "v_shingle"]:
		return pal[1]
	if mat_name in ["p_roof_dark", "v_slate_dark", "v_roof_teal_dark", "v_shingle_dark"]:
		return (pal[1] as Color).darkened(0.32)
	if mat_name.begins_with("v_shutter"):
		return pal[2]
	return c


## Círculos [Vector2 centro, raio] que cobrem as ruas (sem capim por cima do calçamento).
static func street_circles() -> Array:
	var out: Array = []
	for st in STREETS:
		var c: Vector3 = st[0]
		var sz: Vector2 = st[1]
		var along_x := sz.x >= sz.y
		var length: float = sz.x if along_x else sz.y
		var r: float = minf(sz.x, sz.y) * 0.5 + 0.4
		var n := int(ceil(length / r)) + 1
		for i in n:
			var t := -length / 2.0 + length * i / float(n - 1)
			out.append([Vector2(c.x + (t if along_x else 0.0), c.z + (0.0 if along_x else t)), r])
	return out


## NPCs da vila que não são donos de loja: {id: [posição, yaw]} (os donos ficam na frente das lojas).
static func npc_spots() -> Dictionary:
	var lina := Vector3(2.3, 0, -9.6)
	return {
		"elder": [Vector3(-3, 0, -2.5), atan2(3.0, 8.5)],          # Ancião Bram, perto do poço
		"kael": [Vector3(16.2, 0, -1.6), -PI / 2],                  # no vão do portão leste
		"lina": [lina, atan2(-lina.x, 4.0 - lina.z)],               # ao lado do quadro de avisos
		"rufus": [Vector3(4.6, 0, -16.6), PI],                      # guarda no portão norte
		"zelia": [Vector3(-2.6, 0, 12.6), PI],                      # na porta da casa ao sul
	}


## Cerca em volta da vila (BOUNDS), aberta nos portões: [posição, yaw] de cada trecho de 2 m. No sul, entre
## as casas, a cerca da Horta faz a divisa.
static func fence_posts() -> Array:
	var out: Array = []
	var b := BOUNDS
	var x := b.position.x + 1.0
	while x <= b.end.x - 1.0:
		if not gate_at("n", x):
			out.append([Vector3(x, 0, b.position.y), 0.0])
		if not gate_at("s", x) and absf(x - 1.0) > SOUTH_OPEN:
			out.append([Vector3(x, 0, b.end.y), 0.0])
		x += 2.0
	var z := b.position.y + 1.0
	while z <= b.end.y - 1.0:
		if not gate_at("w", z):
			out.append([Vector3(b.position.x, 0, z), PI / 2])
		if not gate_at("e", z):
			out.append([Vector3(b.end.x, 0, z), PI / 2])
		z += 2.0
	return out


static func gate_at(side: String, t: float) -> bool:
	for g in GATES:
		if g[0] == side and absf(t - float(g[1])) < float(g[2]):
			return true
	return false


## Cerca da Horta, com o portão alinhado ao portão sul da vila: [posição, yaw] de cada trecho.
static func farm_fence_posts() -> Array:
	var out: Array = []
	var x := -10.0
	while x <= 10.0:
		if x != 0.0 and x != 2.0:
			out.append([FARM + Vector3(x, 0, -7), 0.0])
		out.append([FARM + Vector3(x, 0, 7.5), 0.0])
		x += 2.0
	var z := -6.0
	while z <= 6.5:
		out.append([FARM + Vector3(-11, 0, z), PI / 2])
		out.append([FARM + Vector3(11, 0, z), PI / 2])
		z += 2.0
	return out


## Bengalas doces nos portões (norte, sul da Horta, leste e oeste): [posição, yaw].
static func candy_canes() -> Array:
	var b := BOUNDS
	var out: Array = []
	for p in [Vector3(-13.4, 0, b.position.y + 0.6), Vector3(3.4, 0, b.position.y + 0.6), Vector3(-1.4, 0, 25.4),
			Vector3(3.4, 0, 25.4), Vector3(b.end.x - 0.6, 0, -3.4), Vector3(b.end.x - 0.6, 0, 3.4),
			Vector3(b.position.x + 0.6, 0, -0.9), Vector3(b.position.x + 0.6, 0, 5.9)]:
		out.append([p, atan2(-p.x, -p.z) + PI / 2])
	return out
