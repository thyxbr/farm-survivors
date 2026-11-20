@tool
class_name VillageLayout
extends RefCounted
## Regras das construções da vila (VillageBuilding, na cena scenes/maps/vale.tscn): tamanho da colisão de
## cada casa, colisões das lojas e onde fica o dono, as paletas das casas, e a leitura das construções da cena
## (buildings()). Só dados e contas puras (sem autoload), para os testes. O resto da vila (ruas, cerca,
## lampiões, enfeites, NPCs, pontos) são peças da cena do vale.
##
## Frente das casas = +Z do modelo (yaw 0 olha para o sul, PI para o norte, PI/2 para o leste).

## Área da vila (x0, z0, largura, profundidade), a mesma da cerca do vale.tscn: a música da vila
## (MusicRules) toca aqui dentro. Se mudar a cerca de lugar no editor, ajuste aqui também.
## A vila fica no sul do vale: quem chega pela estrada do sul passa pela Rua da Chegada até a praça da feira.
const BOUNDS := Rect2(-40, 46, 80, 55)

## Colisão (largura, altura, profundidade) de cada modelo de casa.
const HOUSE_SIZE := {
	"house": Vector3(5.2, 3.2, 4.2), "house_b": Vector3(5.2, 3.2, 4.2), "house_c": Vector3(5.2, 3.2, 4.2),
	"house_d": Vector3(5.6, 3.0, 4.4), "house_e": Vector3(7.6, 3.6, 4.8), "house_f": Vector3(3.8, 4.0, 3.8),
}

## Pegada (largura, profundidade) das construções que não são casa, para os testes da planta.
const FOOTPRINT := {
	"shop_merchant": Vector2(5.2, 3.6), "shop_alchemist": Vector2(4.4, 3.8), "shop_smithy": Vector2(4.6, 4.6),
	"well": Vector2(1.9, 1.9), "shop_workshop": Vector2(7.4, 4.6), "shop_alchemy_lab": Vector2(4.4, 3.6),
	"stall_cloth": Vector2(4.0, 2.4), "stall_farm": Vector2(4.0, 2.4), "stall_goods": Vector2(4.0, 2.4),
}

## Colisões das lojas no espaço delas: [boxes [[centro local, tamanho]], cyls [[centro local, raio]],
## raio sem capim]. A ferraria tem a origem no ferreiro: a forja fica sob a coifa, a bigorna na frente.
const SHOP_SHAPES := {
	"shop_merchant": [[[Vector3(0, 0, -0.4), Vector3(5.2, 3.0, 3.6)]], [], 3.4],
	"shop_alchemist": [[[Vector3(0.2, 0, 0), Vector3(4.4, 3.4, 3.8)]],
		[[Vector3(-2.05, 0, -1.8), 0.95], [Vector3(-1.05, 0, 2.85), 0.45]], 3.6],
	"shop_smithy": [[[Vector3(0, 0, -2.6), Vector3(4.0, 3.0, 0.5)], [Vector3(-1.8, 0, -0.7), Vector3(0.4, 1.1, 3.4)]],
		[[Vector3(1.4, 0, -0.4), 0.5]], 2.8],
	# oficina aberta na frente: parede do fundo, meias-paredes, bancada do fundo, cavalete, tear e o que fica
	# do lado de fora (tábuas e toras à direita, barril e caixotes à esquerda)
	"shop_workshop": [[[Vector3(0, 0, -2.4), Vector3(5.6, 2.7, 0.3)], [Vector3(-2.8, 0, -0.8), Vector3(0.25, 1.1, 3.2)],
		[Vector3(2.8, 0, -0.8), Vector3(0.25, 1.1, 3.2)], [Vector3(0, 0, -1.55), Vector3(2.6, 1.0, 0.8)],
		[Vector3(-2.2, 0, 0), Vector3(0.2, 1.9, 1.3)], [Vector3(2.05, 0, -0.2), Vector3(0.8, 1.4, 1.1)],
		[Vector3(3.4, 0, -0.1), Vector3(0.8, 0.7, 3.4)], [Vector3(-3.3, 0, 0.45), Vector3(0.8, 1.0, 2.0)]], [], 4.2],
	# laboratório aberto: parede do fundo, alambique e o caldeirão no fogareiro (a mesa é a CraftingStation)
	"shop_alchemy_lab": [[[Vector3(0, 0, -1.9), Vector3(4.0, 2.6, 0.4)], [Vector3(1.4, 0, -0.75), Vector3(0.8, 1.4, 0.7)]],
		[[Vector3(-1.35, 0, -0.55), 0.6], [Vector3(0.85, 0, -0.25), 0.2], [Vector3(-1.9, 0, 1.75), 0.25],
		[Vector3(1.9, 0, 1.75), 0.25]], 3.0],
	# barracas da feira: o miolo (balcão, esteios, fundo de pano) e o que fica dos lados
	"stall_cloth": [[[Vector3(0, 0, -0.05), Vector3(3.2, 2.6, 2.2)]], [[Vector3(-1.95, 0, 0.2), 0.45]], 2.4],
	"stall_farm": [[[Vector3(0, 0, -0.05), Vector3(3.2, 2.6, 2.2)]], [[Vector3(-1.85, 0, 0.6), 0.35],
		[Vector3(1.95, 0, 0.3), 0.55]], 2.4],
	"stall_goods": [[[Vector3(0, 0, -0.05), Vector3(3.2, 2.6, 2.2)]], [[Vector3(-1.95, 0, -0.4), 0.38],
		[Vector3(1.95, 0, 0.1), 0.6]], 2.4],
}
## Onde o dono fica, no espaço da loja (a Mira atrás do balcão do empório, a Pip na porta da botica).
const MERCHANT_SPOT := Vector3(-0.7, 0, 2.4)
const ALCHEMIST_SPOT := Vector3(0.3, 0, 3.0)
## Onde o feirante fica atrás do balcão da barraca, onde o artesão fica na oficina (a Bancada de Couraria na
## frente dele) e onde vai a mesa de alquimia no laboratório, no espaço de cada construção.
const STALL_SPOT := Vector3(0, 0, -0.25)
const WORKSHOP_SPOT := Vector3(0, 0, -0.75)
const WORKSHOP_BENCH := Vector3(0, 0, 0.45)
const LAB_TABLE := Vector3(0, 0, 0.0)


## A construção é loja ou barraca (modelo + colisões de SHOP_SHAPES), não casa nem poço.
static func is_shop(model: String) -> bool:
	return model.begins_with("shop_") or model.begins_with("stall_")

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
