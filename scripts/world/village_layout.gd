class_name VillageLayout
extends RefCounted
## Planta da vila de Valdoria (world.gd monta): ruas, casas, os pontos que vieram da antiga praça da cidade
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

## Casas novas: [posição, yaw, modelo, cores (índice em PALETTES)]. As seis da praça ficam em world.gd.
const HOUSES := [
	# ---- bairro oeste
	[Vector3(-31, 0, -10.5), N, "house_d", 0],
	[Vector3(-20, 0, -10.5), N, "house_c", 1],
	[Vector3(-31, 0, -2.3), S, "house", 2],
	[Vector3(-20.2, 0, -2.3), S, "house_e", 3],
	[Vector3(-30.5, 0, 6.6), N, "house_f", 4],
	[Vector3(-20.3, 0, 7.4), N, "house_b", 5],
	[Vector3(-31, 0, 15.6), S, "house_c", 6],
	[Vector3(-20.5, 0, 15.3), S, "house_d", 7],
	# ---- bairro leste
	[Vector3(20.5, 0, -10.6), N, "house_f", 8],
	[Vector3(21.0, 0, -4.3), S, "house_b", 9],
	[Vector3(33.5, 0, 15.5), S, "house_e", 10],
	[Vector3(21.0, 0, 15.6), S, "house", 11],
	# ---- lado sul da Rua das Flores, dos dois lados da Horta
	[Vector3(-16.5, 0, 24.4), N, "house_d", 14],
	[Vector3(16.0, 0, 24.2), N, "house_b", 15],
]

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
## Cores para as seis casas da praça (índices de PALETTES; -1 = cores originais do modelo).
const SQUARE_PALETTES := [-1, 1, 4, -1, 6, 9]

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

## Entregas na Vila: índices em HOUSES das 6 casas que recebem presente.
const DELIVERY := [1, 4, 7, 9, 10, 13]

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


## Casa i de HOUSES em coordenadas do mundo: Transform3D da casa.
static func house_xform(h: Array) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, h[1]), h[0])


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
