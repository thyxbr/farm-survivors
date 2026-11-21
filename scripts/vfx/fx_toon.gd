class_name FXToon
extends RefCounted
## Efeitos no estilo "desenhado": poucas formas grandes em malha, com borda dura, tons chapados e sumiço
## por erosão (shaders/fx_*.gdshader). Cada efeito é uma receita de camadas; a cor vem numa paleta de
## três tons, então o mesmo efeito serve para qualquer elemento.

const SLASH_SHADER := preload("res://shaders/fx_slash.gdshader")
const PUFF_SHADER := preload("res://shaders/fx_puff.gdshader")
const SIGIL_SHADER := preload("res://shaders/fx_frost_sigil.gdshader")
const CRYSTAL_SHADER := preload("res://shaders/fx_crystal.gdshader")
const GUST_SHADER := preload("res://shaders/fx_ground_gust.gdshader")
const RUNE_SHADER := preload("res://shaders/fx_rune_circle.gdshader")
const ORB_SHADER := preload("res://shaders/fx_orb.gdshader")
const TELEGRAPH_SHADER := preload("res://shaders/fx_telegraph.gdshader")

## Golpes do combo da espada, no espaço do personagem (x = esquerda dele, y = cima, z = frente).
## A pincelada gira em torno de `center`, de `from` até `to` (direções a partir do centro), pelo caminho
## mais curto; `pre`/`post` (graus) a esticam antes e depois. Sem `to`, gira `arc` graus em torno de `axis`
## (regra da mão direita: eixo para cima = anti-horário visto de cima, da frente para a esquerda).
## `at` = fração do golpe em que o efeito nasce; `sweep` = tempo que a ponta leva para percorrer o arco.
## Os valores saem da medição da ponta da lâmina (tools/vfx_lab.tscn -- --vfxpage=10 --vfxtip): o sentido
## e o plano do corte têm de ser os da lâmina. Mudou a animação em KnightMoves.SWORD? Meça de novo.
const SWORD_COMBO := [
	{   # 1: de cima da cabeça para baixo, à esquerda
		"center": Vector3(0, 1.3, 0.1), "from": Vector3(-0.04, 1.32, 0.47), "to": Vector3(0.97, -1.07, -0.06),
		"pre": 30.0, "post": 8.0, "radius": 1.6, "at": 0.37, "sweep": 0.05, "hold": 0.04, "fade": 0.2},
	{   # 2: revés, de cima e da frente para a direita
		"center": Vector3(0, 1.3, 0.1), "from": Vector3(0.13, 1.11, 0.84), "to": Vector3(-1.74, -0.12, -0.03),
		"pre": 35.0, "post": 35.0, "radius": 1.85, "at": 0.35, "sweep": 0.05, "hold": 0.04, "fade": 0.2},
	{   # 3: giro de uma volta, anti-horário visto de cima, lâmina na horizontal
		"center": Vector3(0, 1.36, 0), "from": Vector3(-0.47, 0, 0.88), "axis": Vector3.UP, "arc": 330.0,
		"radius": 1.9, "at": 0.325, "sweep": 0.25, "hold": 0.02, "fade": 0.22,
		"linear": true, "lead": 0.03, "trail": 0.6},
]

## Montante (KnightMoves.GREAT_TOOL): os três cortes medidos da ponta da lâmina com tools/weapon_pose_shot.tscn --
## montante (TIP de cada instante, em relação a `center`). `at` = fração do golpe em que a lâmina começa a descer,
## `sweep_frac` = fração do golpe que o corte leva para correr (great_slash converte em segundos).
const GREAT_COMBO := [
	{   # 1: diagonal do ombro direito ao joelho esquerdo (ponta de 0,42 a 0,54 do golpe)
		"center": Vector3(0, 1.3, 0.2), "from": Vector3(-0.31, 1.51, 0.53), "to": Vector3(1.03, -1.18, 0.83),
		"pre": 15.0, "post": 15.0, "radius": 1.75, "at": 0.42, "sweep_frac": 0.12},
	{   # 2: varrida da esquerda para a direita, pela frente (0,4 a 0,56)
		"center": Vector3(0, 1.1, 0.1), "from": Vector3(1.6, 0.2, 0.45), "to": Vector3(-1.68, -0.24, 0.4),
		"pre": 10.0, "post": 15.0, "radius": 1.75, "at": 0.4, "sweep_frac": 0.15},
	{   # 3: de cima para baixo, a ponta no chão à frente (0,42 a 0,5)
		"center": Vector3(0, 1.2, 0.4), "from": Vector3(-0.16, 2.07, -0.03), "to": Vector3(-0.13, -1.2, 1.1),
		"pre": 10.0, "post": 0.0, "radius": 1.85, "at": 0.42, "sweep_frac": 0.08},
]

## Poeira levantada pelos pés (paleta fixa: não depende da arma).
const DUST := {"core": Color(0.93, 0.88, 0.78), "mid": Color(0.72, 0.63, 0.5), "edge": Color(0.36, 0.29, 0.22)}

## Investida: duas meias-luas de poeira no chão, abrindo de trás para os lados (um "V" atrás dos pés).
const CHARGE_KICK := [
	{"center": Vector3(0, 0.07, 0.2), "from": Vector3(0, 0, -1), "to": Vector3(1, 0, 0.25), "pre": 4.0,
		"radius": 1.25, "sweep": 0.07, "hold": 0.05, "fade": 0.28, "lead": 0.3},
	{"center": Vector3(0, 0.07, 0.2), "from": Vector3(0, 0, -1), "to": Vector3(-1, 0, 0.25), "pre": 4.0,
		"radius": 1.25, "sweep": 0.07, "hold": 0.05, "fade": 0.28, "lead": 0.3},
]
## Chegada da Investida: o corte que fecha a estocada (KnightMoves.CHARGE, chave 0,75), da frente/esquerda
## para a direita, subindo do joelho ao peito. Medido com --vfxpage=11 --vfxtip, como SWORD_COMBO.
const CHARGE_CUT := {
	"center": Vector3(0, 0.75, 0), "from": Vector3(0.49, -0.49, 1.42), "to": Vector3(-1.72, 0.2, 0.0),
	"pre": 25.0, "post": 30.0, "radius": 1.8, "sweep": 0.05, "hold": 0.04, "fade": 0.22}
## Pedra e terra do Golpe Sísmico, e a fissura com o fundo em brasa.
const ROCK := {"core": Color(0.66, 0.56, 0.44), "mid": Color(0.38, 0.29, 0.21), "edge": Color(0.15, 0.11, 0.08)}
const FISSURE := {"core": Color(1.0, 0.72, 0.3), "mid": Color(0.2, 0.1, 0.06), "edge": Color(0.05, 0.03, 0.02)}
const EMBER := {"core": Color(1.0, 0.97, 0.85), "mid": Color(1.0, 0.72, 0.3), "edge": Color(0.8, 0.3, 0.08)}

## Golpe Sísmico: a lâmina sai de trás e de cima, passa por cima da cabeça e crava no chão à frente.
## Medido com --vfxpage=12 --vfxtip (ver SWORD_COMBO): no plano de pé que contém a frente do personagem,
## a ponta vai de -50° (atrás, em cima) a +151° (chão, à frente), passando por +113° (frente). São mais
## de 180°: por isso o eixo é dado (para a esquerda = por cima, de trás para a frente); com from/to o
## caminho mais curto seria por baixo, ao contrário. O eixo sobe 20°: o plano inclina um pouco, senão a
## câmera, que fica atrás do jogador, veria a pincelada de perfil (um fio).
const QUAKE_CUT := {
	"center": Vector3(0, 1.25, 0.15), "from": Vector3(0, 0.82, -0.57), "axis": Vector3(0.94, 0.34, 0), "arc": 186.0,
	"radius": 1.6, "sweep": 0.04, "hold": 0.05, "fade": 0.22}
## Onda de choque no chão: meia-lua gorda no meio e fina nas pontas, do eixo do cone para cada lado.
const QUAKE_RIPPLE := [
	{"center": Vector3(0, 0.06, 0), "from": Vector3(0, 0, 1), "to": Vector3(0.68, 0, 0.74), "blunt": 1.0,
		"peak": 0.2, "sweep": 0.06, "hold": 0.06, "fade": 0.3, "lead": 0.4},
	{"center": Vector3(0, 0.06, 0), "from": Vector3(0, 0, 1), "to": Vector3(-0.68, 0, 0.74), "blunt": 1.0,
		"peak": 0.2, "sweep": 0.06, "hold": 0.06, "fade": 0.3, "lead": 0.4},
]

## Paletas das magias do cajado.
const ICE := {"core": Color(0.96, 1.0, 1.0), "mid": Color(0.55, 0.85, 1.0), "edge": Color(0.14, 0.36, 0.78)}
const HEAL := {"core": Color(0.94, 1.0, 0.86), "mid": Color(0.4, 0.95, 0.45), "edge": Color(0.07, 0.46, 0.26)}
const SMOKE := {"core": Color(0.66, 0.62, 0.6), "mid": Color(0.43, 0.39, 0.39), "edge": Color(0.24, 0.21, 0.23)}
const MIST := {"core": Color(0.98, 1.0, 1.0), "mid": Color(0.74, 0.91, 1.0), "edge": Color(0.42, 0.64, 0.93)}
const FLASH := {"core": Color(1.0, 1.0, 0.92), "mid": Color(1.0, 0.86, 0.4), "edge": Color(1.0, 0.55, 0.1)}
## Onda em anel no chão: duas metades, da frente para trás por cada lado (raio e espessura por chamada).
const RING_WAVE := [
	{"center": Vector3.ZERO, "from": Vector3(0, 0, 1), "axis": Vector3.UP, "arc": 180.0, "blunt": 1.0, "peak": 0.2,
		"hold": 0.08, "fade": 0.35, "lead": 0.3},
	{"center": Vector3.ZERO, "from": Vector3(0, 0, 1), "axis": Vector3.DOWN, "arc": 180.0, "blunt": 1.0, "peak": 0.2,
		"hold": 0.08, "fade": 0.35, "lead": 0.3},
]

## Monstros: a identidade é o contrário da do jogador. Os efeitos do jogador têm o miolo claro e a borda
## escura; os dos monstros têm o miolo quase preto e a borda acesa em carmim, com formas de espinho.
const MENACE := {"core": Color(0.07, 0.02, 0.07), "mid": Color(0.55, 0.04, 0.22), "edge": Color(1.0, 0.22, 0.34)}
const THORN := {"core": Color(0.78, 0.1, 0.36), "mid": Color(0.3, 0.03, 0.17), "edge": Color(0.06, 0.01, 0.05)}
const HELLFIRE := {"core": Color(1.0, 0.3, 0.22), "mid": Color(0.62, 0.04, 0.16), "edge": Color(0.13, 0.01, 0.07)}
const SOOT := {"core": Color(0.3, 0.25, 0.3), "mid": Color(0.16, 0.12, 0.17), "edge": Color(0.05, 0.03, 0.06)}
const BLIGHT := {"core": Color(0.78, 1.0, 0.4), "mid": Color(0.3, 0.68, 0.2), "edge": Color(0.24, 0.05, 0.34)}
## Vento da Flecha do Vendaval.
const WIND := {"core": Color(1.0, 1.0, 1.0), "mid": Color(0.78, 0.9, 1.0), "edge": Color(0.36, 0.7, 0.98)}
## Fogo do Turbilhão.
const FIRE := {"core": Color(1.0, 0.95, 0.7), "mid": Color(1.0, 0.55, 0.1), "edge": Color(0.72, 0.1, 0.03)}

## Turbilhão, golpe final: mesma descida do Golpe Sísmico (a pose é a mesma; medido com --vfxpage=13).
const WHIRL_CUT := {
	"center": Vector3(0, 1.25, 0.15), "from": Vector3(0, 0.82, -0.57), "axis": Vector3(0.94, 0.34, 0), "arc": 186.0,
	"radius": 1.6, "sweep": 0.04, "hold": 0.05, "fade": 0.22}
## Onda de fogo do golpe final: duas metades, da frente para trás por cada lado.
const WHIRL_BLAST := [
	{"center": Vector3(0, 0.08, 0), "from": Vector3(0, 0, 1), "axis": Vector3.UP, "arc": 180.0, "blunt": 1.0,
		"peak": 0.2, "sweep": 0.12, "hold": 0.08, "fade": 0.35, "lead": 0.3},
	{"center": Vector3(0, 0.08, 0), "from": Vector3(0, 0, 1), "axis": Vector3.DOWN, "arc": 180.0, "blunt": 1.0,
		"peak": 0.2, "sweep": 0.12, "hold": 0.08, "fade": 0.35, "lead": 0.3},
]
const WHIRL_ARC := 300.0       ## quanto da volta cada faixa do redemoinho cobre atrás da lâmina (graus)

const LANCE_LENGTH := 7.0      ## comprimento da malha da lança (m): cobre a Investida inteira e a folga da ponta
const LANCE_WIDTH := 0.42      ## meia largura (m)

static var _slash_mat: ShaderMaterial
static var _lance: ArrayMesh
static var _puff_mesh: QuadMesh
static var _sigil_mesh: PlaneMesh
static var _crystal_mesh: ArrayMesh
static var _gust_mesh: PlaneMesh
static var _rune_mesh: PlaneMesh
static var _orb_mesh: QuadMesh
static var _telegraph_mesh: PlaneMesh
static var _arcs := {}


## Paleta de três tons a partir de uma cor: núcleo quase branco, meio saturado, sombra escura e fria.
static func palette(c: Color) -> Dictionary:
	var mid := Color.from_hsv(c.h, clampf(c.s * 1.1 + 0.1, 0.0, 0.9), maxf(c.v, 0.9))
	var edge := Color.from_hsv(fposmod(c.h + 0.06, 1.0), clampf(c.s + 0.35, 0.55, 0.95), 0.32)
	return {"core": c.lerp(Color.WHITE, 0.85), "mid": mid, "edge": edge}


static func slash_material() -> ShaderMaterial:
	if _slash_mat == null:
		_slash_mat = ShaderMaterial.new()
		_slash_mat.shader = SLASH_SHADER
	return _slash_mat


## Faixa em arco no plano XZ, raio 1 por fora e `inner` por dentro, cobrindo `degrees` a partir da
## frente (+Z) no sentido anti-horário. UV.x = 0..1 ao longo do arco; UV.y = 0 dentro, 1 fora.
static func arc_mesh(degrees: float, inner := 0.3) -> ArrayMesh:
	var key := "%d/%.2f" % [int(degrees), inner]
	var mesh: ArrayMesh = _arcs.get(key)
	if mesh != null:
		return mesh
	var seg := maxi(12, int(degrees / 5.0))
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in seg + 1:
		var u := float(i) / seg
		var a := deg_to_rad(degrees) * u
		var dir := Vector3(sin(a), 0.0, cos(a))
		verts.append(dir * inner)
		uvs.append(Vector2(u, 0.0))
		verts.append(dir)
		uvs.append(Vector2(u, 1.0))
		if i < seg:
			var b := i * 2
			idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, slash_material())
	_arcs[key] = mesh
	return mesh


## Faixa reta e deitada (plano XZ): corre de z = 0 (cauda) a z = 1 (ponta), de x = -1 a x = 1. UV.y vale 1
## na linha do meio e 0 nas duas bordas: o núcleo claro fica no eixo e as falhas de pincel, por fora.
static func lance_mesh() -> ArrayMesh:
	if _lance != null:
		return _lance
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for z in [0.0, 1.0]:
		for x in [-1.0, 0.0, 1.0]:
			verts.append(Vector3(x, 0.0, z))
			uvs.append(Vector2(z, 1.0 - absf(x)))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 3, 1, 4, 3, 1, 2, 4, 2, 5, 4])
	_lance = ArrayMesh.new()
	_lance.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_lance.surface_set_material(0, slash_material())
	return _lance


## Cortes da lista de receitas `list` num ponto fixo do mundo, virados para `dir` (somem sozinhos).
## `tilt` = base do chão (FXToon.ground_frame) para deitar os cortes num terreno inclinado.
static func slashes_at(pos: Vector3, dir: Vector3, list: Array, pal: Dictionary, tilt := Basis.IDENTITY) -> void:
	var root := FX._scene()
	if root == null:
		return
	var holder := Node3D.new()
	root.add_child(holder)
	holder.global_transform = Transform3D(tilt, pos)
	for o in list:
		slash(holder, atan2(dir.x, dir.z), o, pal)
	holder.get_tree().create_timer(1.2).timeout.connect(holder.queue_free)


## Pincelada reta de `a` até `b` (mundo), com meia largura `half_width`: nasce em `a` e corre até `b`.
## Opções em `o`: sweep/hold/fade/delay/linear/lead, "peak" e "blunt" (forma: ver o shader), "shadow"
## (false = sem a camada escura de trás) e "billboard" (true = a faixa gira em torno do próprio eixo
## para ficar de frente para a câmera: estilhaços e faíscas; false = deitada no chão: fissuras).
static func streak(a: Vector3, b: Vector3, half_width: float, pal: Dictionary, o := {}) -> void:
	var root := FX._scene()
	if root == null:
		return
	var seed0 := randf() * 20.0
	for layer in 2:
		if layer == 0 and not o.get("shadow", true):
			continue
		var s := SlashNode.new()
		s.mesh = lance_mesh()
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.line = true
		s.line_a = a
		s.line_b = b
		s.half_width = half_width
		s.face_camera = o.get("billboard", false)
		s.sweep = o.get("sweep", 0.06)
		s.hold = o.get("hold", 0.05)
		s.fade = o.get("fade", 0.2)
		s.delay = o.get("delay", 0.0)
		s.linear = o.get("linear", false)
		s.lead = o.get("lead", 0.2)
		s.grow = 1.0
		s.noise_seed = seed0 + layer * 4.7
		if layer == 0:
			s.delay += 0.02
			s.half_width *= 1.4
			s.sorting_offset = -0.1
			s.set_instance_shader_parameter("core", 0.0)
			s.set_instance_shader_parameter("col_mid", pal.edge)
			s.set_instance_shader_parameter("col_edge", (pal.edge as Color).darkened(0.45))
		else:
			s.set_instance_shader_parameter("col_core", pal.core)
			s.set_instance_shader_parameter("col_mid", pal.mid)
			s.set_instance_shader_parameter("col_edge", pal.edge)
		s.set_instance_shader_parameter("arc", a.distance_to(b) * 0.9)
		s.set_instance_shader_parameter("blunt", o.get("blunt", 0.0))
		s.set_instance_shader_parameter("peak", o.get("peak", 0.5))
		s.set_instance_shader_parameter("head", 0.0)
		root.add_child(s)


## Onda em anel deitada, centrada em `pos` (ou presa a `parent`, se dado), que abre até `radius`.
static func ring_wave(pos: Vector3, radius: float, thick: float, pal: Dictionary, sweep := 0.12, delay := 0.0,
		parent: Node3D = null, tilt := Basis.IDENTITY) -> void:
	var list := []
	for o in RING_WAVE:
		var r: Dictionary = (o as Dictionary).duplicate()
		r["radius"] = radius
		r["thick"] = thick
		r["sweep"] = sweep
		r["delay"] = delay
		if parent:
			r["center"] = pos
			slash(parent, 0.0, r, pal)
		else:
			list.append(r)
	if parent == null:
		slashes_at(pos, Vector3.BACK, list, pal, tilt)


## Cometa preso a um projétil (`parent` tem a variável `direction`, o sentido em que ele voa): a cabeça vai
## na frente do projétil e a cauda fica para trás, lidas de `direction` a cada quadro. `anchor` = nó de onde
## ler a posição (o visual do projétil, quando ele aparece deslocado da posição real).
static func comet(parent: Node3D, pal: Dictionary, length := 2.2, half_width := 0.32, embers := true,
		anchor: Node3D = null) -> void:
	if FX._scene() == null or parent == null:
		return
	var seed0 := randf() * 20.0
	for layer in 2:
		var c := CometNode.new()
		c.mesh = lance_mesh()
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.length = length * (1.12 if layer == 0 else 1.0)
		c.half_width = half_width * (1.4 if layer == 0 else 1.0)
		c.embers = embers and layer == 1
		c.anchor = anchor
		c.noise_seed = seed0 + layer * 4.7
		if layer == 0:
			c.sorting_offset = -0.1
			c.set_instance_shader_parameter("core", 0.0)
			c.set_instance_shader_parameter("col_mid", pal.edge)
			c.set_instance_shader_parameter("col_edge", (pal.edge as Color).darkened(0.45))
		else:
			c.set_instance_shader_parameter("col_core", pal.core)
			c.set_instance_shader_parameter("col_mid", pal.mid)
			c.set_instance_shader_parameter("col_edge", pal.edge)
		c.set_instance_shader_parameter("arc", length * 1.4)
		c.set_instance_shader_parameter("peak", 0.8)
		c.set_instance_shader_parameter("head", 1.0)
		c.set_instance_shader_parameter("tail", 0.0)
		parent.add_child(c)


## Um vetor unitário sorteado, puxado para cima (explosões perto do chão não gastam labaredas para baixo).
static func _burst_dir() -> Vector3:
	var v := Vector3(randf_range(-1.0, 1.0), randf_range(-0.25, 1.0), randf_range(-1.0, 1.0))
	return v.normalized() if v.length_squared() > 0.01 else Vector3.UP


## O chão em volta de `pos`: posição no chão e base inclinada como o terreno (Y = normal), medidas com
## nove raios para baixo (centro e oito pontos a `reach` metros). Sem chão por baixo (ou fora de cena
## com física), devolve `pos` e a base reta. Os desenhos de área usam isto para deitar no terreno.
static func ground_frame(pos: Vector3, reach: float) -> Transform3D:
	var root := FX._scene() as Node3D
	if root == null or not root.is_inside_tree():
		return Transform3D(Basis.IDENTITY, pos)
	var space := root.get_world_3d().direct_space_state
	if space == null:
		return Transform3D(Basis.IDENTITY, pos)
	var pts: Array = []
	for i in 9:
		var off := Vector3.ZERO if i == 0 else Vector3(cos(i * TAU / 8.0), 0, sin(i * TAU / 8.0)) * reach
		var q := PhysicsRayQueryParameters3D.create(pos + off + Vector3.UP * 6.0, pos + off - Vector3.UP * 8.0, 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			pts.append(hit.position)
	return GroundFit.fit(pts, pos)


## Desenho de chão com o shader `shader` (fx_frost_sigil, fx_rune_circle), centrado em `pos`, até `radius`:
## aparece do centro para fora em `sweep` segundos, fica `hold` (negativo = até release()) e some em manchas.
static func _ground_drawing(mesh: PlaneMesh, pos: Vector3, radius: float, line: Color, fill: Color, sweep: float,
		hold: float, spin_rate := 0.0) -> SigilNode:
	var root := FX._scene()
	if root == null:
		return null
	var n := SigilNode.new()
	n.mesh = mesh
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.sweep = sweep
	n.hold = hold
	n.spin_rate = spin_rate
	n.sorting_offset = -0.5
	n.set_instance_shader_parameter("col_line", line)
	n.set_instance_shader_parameter("col_fill", fill)
	n.set_instance_shader_parameter("seed", randf() * 20.0)
	n.set_instance_shader_parameter("reveal", 0.0)
	root.add_child(n)
	var gf := ground_frame(pos, radius * 0.6)
	n.global_transform = Transform3D(gf.basis.scaled_local(Vector3.ONE * radius * 1.05), gf.origin + gf.basis.y * 0.05)
	return n


## Círculo de runas de fogo no chão (Chuva de Meteoros), girando devagar. `hold` < 0: fica até release().
static func rune_circle(pos: Vector3, radius: float, sweep := 0.3, hold := -1.0) -> SigilNode:
	if FX._scene() == null:
		return null
	return _ground_drawing(_rune_quad(), pos, radius, EMBER.mid, FIRE.edge, sweep, hold, 0.35)


static func _rune_quad() -> PlaneMesh:
	if _rune_mesh == null:
		_rune_mesh = PlaneMesh.new()
		_rune_mesh.size = Vector2(2, 2)
		var m := ShaderMaterial.new()
		m.shader = RUNE_SHADER
		_rune_mesh.material = m
	return _rune_mesh


## Explosão de um meteoro em `pos` (no chão): como fire_burst, mas enxuta (caem uns cinco por segundo por
## chuva, e pode haver quatro chuvas): clarão, três bolas de fogo, três de fumaça, faíscas e um anel.
static func meteor_burst(pos: Vector3, size := 1.0) -> void:
	if FX._scene() == null:
		return
	var at := pos + Vector3.UP * 0.7 * size
	for i in 3:
		var v := (_burst_dir() * 0.8 + Vector3.UP * 0.6).normalized()
		puff(at + v * 0.5 * size, randf_range(1.3, 1.8) * size, SMOKE,
			{"vel": v * randf_range(2.0, 3.2) * size + Vector3.UP * 1.0, "delay": 0.16, "grow": 0.28, "hold": 0.25,
			"fade": 0.55, "sort": -0.2})
	for i in 3:
		var v := _burst_dir()
		puff(at + v * 0.3 * size, randf_range(1.4, 1.9) * size, FIRE,
			{"vel": v * randf_range(4.0, 6.0) * size, "grow": 0.1, "hold": 0.07, "fade": 0.28})
	puff(at, 2.1 * size, FLASH, {"grow": 0.06, "hold": 0.05, "fade": 0.2, "sort": 0.2})
	impact_sparks(pos + Vector3.UP * 0.1, Vector3.BACK, 4, 180.0)
	var list := []
	for o in RING_WAVE:
		var r: Dictionary = (o as Dictionary).duplicate()
		r["radius"] = 2.2 * size
		r["thick"] = 0.22
		r["sweep"] = 0.1
		r["shadow"] = false
		list.append(r)
	slashes_at(pos + Vector3.UP * 0.1, Vector3.BACK, list, FIRE)


## Baforada arredondada em `pos` (mundo), com `size` metros de largura: estufa, anda com "vel" freando e
## some encolhendo. Opções em `o`: vel (Vector3), delay, grow (s para estufar), hold, fade.
static func puff(pos: Vector3, size: float, pal: Dictionary, o := {}) -> void:
	var root := FX._scene()
	if root == null:
		return
	if _puff_mesh == null:
		_puff_mesh = QuadMesh.new()
		_puff_mesh.size = Vector2(1, 1)
		var m := ShaderMaterial.new()
		m.shader = PUFF_SHADER
		_puff_mesh.material = m
	var n := PuffNode.new()
	n.mesh = _puff_mesh
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.size = size
	n.vel = o.get("vel", Vector3.ZERO)
	n.delay = o.get("delay", 0.0)
	n.grow = o.get("grow", 0.15)
	n.hold = o.get("hold", 0.15)
	n.fade = o.get("fade", 0.4)
	n.sorting_offset = o.get("sort", 0.0)
	n.set_instance_shader_parameter("col_core", pal.core)
	n.set_instance_shader_parameter("col_mid", pal.mid)
	n.set_instance_shader_parameter("col_edge", pal.edge)
	n.set_instance_shader_parameter("seed", randf())
	root.add_child(n)
	n.global_position = pos


static func _orb_quad() -> QuadMesh:
	if _orb_mesh == null:
		_orb_mesh = QuadMesh.new()
		_orb_mesh.size = Vector2(1, 1)
		var m := ShaderMaterial.new()
		m.shader = ORB_SHADER
		_orb_mesh.material = m
	return _orb_mesh


## Esfera de energia presa a `parent` (o visual de um projétil), com `size` metros: núcleo claro, cor e
## borda escura, pulsando de leve. Devolve o nó (null no servidor).
static func orb(parent: Node3D, pal: Dictionary, size: float) -> Node3D:
	if FX._scene() == null or parent == null:
		return null
	var n := PopNode.new()
	n.mesh = _orb_quad()
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.size0 = size
	n.size1 = size
	n.time = -1.0            # fica enquanto o pai existir
	n.pulse = 0.08
	n.sorting_offset = 0.15
	n.set_instance_shader_parameter("col_core", Color.WHITE)
	n.set_instance_shader_parameter("col_mid", pal.mid)
	n.set_instance_shader_parameter("col_edge", pal.edge)
	n.set_instance_shader_parameter("seed", randf())
	parent.add_child(n)
	return n


## Disco ou anel de energia solto em `pos` (mundo), que muda de tamanho e de furo e some sozinho. Opções em
## `o`: size0/size1 (m, começo e fim), inner0/inner1 (furo: 0 = disco, perto de 1 = anel fino), time,
## delay, vel (Vector3, freando), ease_in (true = começa devagar: encolher até sumir).
static func pop(pos: Vector3, pal: Dictionary, o := {}) -> void:
	var root := FX._scene()
	if root == null:
		return
	var n := PopNode.new()
	n.mesh = _orb_quad()
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.size0 = o.get("size0", 0.5)
	n.size1 = o.get("size1", 1.0)
	n.inner0 = o.get("inner0", 0.0)
	n.inner1 = o.get("inner1", 0.0)
	n.time = o.get("time", 0.2)
	n.delay = o.get("delay", 0.0)
	n.vel = o.get("vel", Vector3.ZERO)
	n.ease_in = o.get("ease_in", false)
	n.sorting_offset = o.get("sort", 0.0)
	n.set_instance_shader_parameter("col_core", o.get("core", pal.core))
	n.set_instance_shader_parameter("col_mid", pal.mid)
	n.set_instance_shader_parameter("col_edge", pal.edge)
	n.set_instance_shader_parameter("seed", randf())
	root.add_child(n)
	n.global_position = pos


## Impacto de uma esfera de energia em `pos`, que vinha no sentido `dir`: clarão redondo que encolhe, um
## anel que abre e afina, e `n` bolinhas espirrando para trás e para os lados. Tudo em formas redondas.
static func energy_pop(pos: Vector3, dir: Vector3, pal: Dictionary, n := 6, size := 1.0) -> void:
	if FX._scene() == null:
		return
	# anel grosso e cheio de cor (um anel fino de contorno lê como bolha de sabão)
	pop(pos, pal, {"size0": 0.8 * size, "size1": 2.3 * size, "inner0": 0.2, "inner1": 0.8, "time": 0.18, "core": Color.WHITE})
	pop(pos, pal, {"size0": 1.7 * size, "size1": 0.0, "time": 0.15, "ease_in": true, "core": Color.WHITE, "sort": 0.1})
	var bright := {"core": Color.WHITE, "mid": pal.core, "edge": pal.mid}     # bolinhas cheias, sem contorno escuro
	for i in n:
		var v := (_burst_dir() - dir * 0.6).normalized()
		pop(pos + v * 0.2 * size, bright, {"size0": randf_range(0.2, 0.32) * size, "size1": 0.0, "time": randf_range(0.24, 0.36),
			"vel": v * randf_range(4.0, 7.0) * size, "ease_in": true})


## Impacto de uma faísca em `pos`, que vinha no sentido `dir`: uma estrela de quatro pontas e `n` riscos
## curtos espirrando para trás e para os lados, na paleta `pal`.
static func spark_hit(pos: Vector3, dir: Vector3, pal: Dictionary, n := 6, size := 1.0) -> void:
	if FX._scene() == null:
		return
	var light := {"core": Color.WHITE, "mid": pal.core, "edge": pal.mid}
	for axis in [Vector3.UP, Vector3.UP.cross(dir).normalized() if absf(dir.y) < 0.95 else Vector3.RIGHT]:
		streak(pos - axis * 0.45 * size, pos + axis * 0.45 * size, 0.07 * size, light,
			{"billboard": true, "shadow": false, "lead": 1.0, "sweep": 0.02, "hold": 0.05, "fade": 0.14, "peak": 0.5})
	for i in n:
		var v := (_burst_dir() - dir * 0.7).normalized()
		streak(pos + v * 0.1, pos + v * randf_range(0.45, 0.9) * size, randf_range(0.04, 0.07) * size, pal,
			{"billboard": true, "shadow": false, "sweep": 0.05, "hold": 0.03, "fade": 0.16, "peak": 0.6})


## Estouro de energia em `pos` (faísca que explode em área, sem ser de fogo): anel no chão e riscos em
## estrela na paleta `pal`. Sem baforadas: fumaça clara lê como sabão.
static func energy_burst(pos: Vector3, pal: Dictionary, radius := 2.4) -> void:
	if FX._scene() == null:
		return
	ring_wave(pos - Vector3.UP * 0.3, radius, 0.2, pal, 0.1)
	for i in 10:
		var v := _burst_dir()
		var length := randf_range(0.5, 0.85) * radius
		streak(pos + v * 0.15, pos + v * length, length * 0.1, pal,
			{"billboard": true, "sweep": 0.06, "hold": 0.05, "fade": 0.22, "peak": 0.45, "lead": 0.35})
	spark_hit(pos, Vector3.DOWN, pal, 0, 1.6)


## Paleta clara de uma cor (riscos de vento, rastro de flecha): branco no meio, a cor clareada e a cor.
static func light_palette(c: Color) -> Dictionary:
	return {"core": Color.WHITE, "mid": c.lightened(0.55), "edge": c}


## Disparo em `origin` no sentido `dir` (arco): riscos curtos saindo para a frente num leque fechado.
static func muzzle(origin: Vector3, dir: Vector3, pal: Dictionary, n := 5, size := 1.0) -> void:
	if FX._scene() == null:
		return
	var side := Vector3.UP.cross(dir).normalized() if absf(dir.y) < 0.95 else Vector3.RIGHT
	var up := dir.cross(side).normalized()
	for i in n:
		var v := (dir + side * randf_range(-0.45, 0.45) + up * randf_range(-0.3, 0.45)).normalized()
		streak(origin + v * 0.1, origin + v * randf_range(0.6, 1.1) * size, randf_range(0.035, 0.06) * size, pal,
			{"billboard": true, "shadow": false, "sweep": 0.05, "hold": 0.02, "fade": 0.14, "peak": 0.6})


## Carga de gelo na ponta da flecha em `at`: um anel que fecha sobre a ponta durante `time` segundos.
static func frost_charge(at: Vector3, time: float) -> void:
	# anel grosso que fecha até virar um ponto cheio (um anel fino de contorno lê como bolha)
	pop(at, ICE, {"size0": 1.2, "size1": 0.32, "inner0": 0.62, "inner1": 0.0, "time": time, "ease_in": true, "core": Color.WHITE})


## Flecha Glacial acerta um alvo em `feet` (pés do inimigo): cristais fecham em volta dele, um floco pequeno
## no chão e brilhos. Os cristais duram `hold` segundos (o tempo em que o alvo fica preso).
static func frost_hit(feet: Vector3, hold := 1.2, radius := 1.2) -> void:
	if FX._scene() == null:
		return
	frost_sigil(feet, radius * 1.25, 0.12, hold)
	var gf := ground_frame(feet, radius * 0.6)
	ground_gust(gf.origin, radius * 1.6, MIST, 0.3, 0.0, gf.basis)
	for i in 5:
		var out := gf.basis * Vector3.BACK.rotated(Vector3.UP, TAU * (i + randf_range(-0.25, 0.25)) / 5.0)
		var h := randf_range(0.8, 1.35)
		# de pé em volta do alvo, tombando um pouco para dentro (como uma gaiola de gelo)
		crystal(gf.origin + out * radius * randf_range(0.5, 0.7), h, h * randf_range(0.42, 0.5),
			Vector3.UP - out * randf_range(0.1, 0.3), {"delay": i * 0.02, "hold": hold})
	var glint := {"core": Color.WHITE, "mid": Color.WHITE, "edge": ICE.mid}
	for i in 5:
		var a2 := randf() * TAU
		var at := feet + Vector3(sin(a2), 0, cos(a2)) * radius * randf() + Vector3.UP * randf_range(0.5, 1.7)
		streak(at, at + Vector3.UP * randf_range(0.25, 0.5), 0.045, glint,
			{"billboard": true, "shadow": false, "delay": randf_range(0.05, 0.5), "sweep": 0.08, "hold": 0.04,
			"fade": 0.2, "peak": 0.5})


## Flecha do Vendaval, a tensão: vento desenhado girando em volta de `parent` (o jogador) e fechando sobre
## ele conforme a carga sobe, poeira rodando no chão e uma esfera de luz crescendo em `tip` (a ponta da
## flecha). Quem tensiona escreve a carga (0..1) em `charge` do nó devolvido a cada passo; solte o nó no
## disparo. Devolve null no servidor.
static func gale_charge(parent: Node3D, tip: Node3D) -> GaleCharge:
	if FX._scene() == null or parent == null:
		return null
	var holder := GaleCharge.new()
	holder.tip = tip
	parent.add_child(holder)
	var seed0 := randf() * 20.0
	# [paleta, fase (graus), altura, raio com carga 0, raio com carga 1, espessura]
	var rings := [
		[WIND, 0.0, 0.45, 2.3, 1.2, 0.2],
		[WIND, 130.0, 1.1, 2.0, 0.95, 0.22],
		[WIND, 250.0, 1.8, 1.7, 0.8, 0.2],
		[DUST, 60.0, 0.1, 2.6, 1.8, 0.24],
		[DUST, 220.0, 0.12, 2.1, 1.4, 0.22],
	]
	for i in rings.size():
		var r: Array = rings[i]
		var pal: Dictionary = r[0]
		var n := WindRing.new()
		n.mesh = arc_mesh(210.0)
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.angle = deg_to_rad(float(r[1]))
		n.height = r[2]
		n.radius0 = r[3]
		n.radius1 = r[4]
		n.noise_seed = seed0 + i * 3.1
		n.set_instance_shader_parameter("thick", r[5])
		n.set_instance_shader_parameter("col_core", pal.core)
		n.set_instance_shader_parameter("col_mid", pal.mid)
		n.set_instance_shader_parameter("col_edge", pal.edge)
		n.set_instance_shader_parameter("arc", deg_to_rad(210.0))
		n.set_instance_shader_parameter("peak", 0.75)
		n.set_instance_shader_parameter("head", 1.0)
		n.set_instance_shader_parameter("tail", 1.0)
		holder.add_child(n)
	if is_instance_valid(tip):
		holder.glow = orb(tip, WIND, 0.2) as PopNode
	return holder


## Flecha do Vendaval, o disparo de `origin` no sentido `dir` com carga `c` (0..1): clarão e leque de riscos
## na boca do arco, onda de vento nos pés (`feet`) e a poeira do recuo atrás.
static func gale_fire(feet: Vector3, origin: Vector3, dir: Vector3, c: float) -> void:
	if FX._scene() == null:
		return
	var at := origin + dir * 0.3   # origin = ponta da flecha: o estouro fica logo à frente do arco
	pop(at, WIND, {"size0": 1.1 + 0.5 * c, "size1": 0.0, "time": 0.14, "ease_in": true, "sort": 0.1})
	muzzle(at, dir, light_palette(WIND.edge), 8, 1.3 + 0.6 * c)
	ring_wave(feet + Vector3.UP * 0.07, 2.5 + 2.0 * c, 0.14, WIND, 0.14)
	slashes_at(feet, dir, CHARGE_KICK, DUST)


## Aviso de ataque em área no chão, centrado em `pos`, com `radius` metros: o anel marca o raio desde o
## começo e o miolo enche do centro para fora durante `duration` segundos (cheio = o golpe cai). Deita no terreno.
static func telegraph(pos: Vector3, radius: float, duration: float) -> void:
	if FX._scene() == null:
		return
	if _telegraph_mesh == null:
		_telegraph_mesh = PlaneMesh.new()
		_telegraph_mesh.size = Vector2(2, 2)
		var m := ShaderMaterial.new()
		m.shader = TELEGRAPH_SHADER
		_telegraph_mesh.material = m
	var n := _ground_drawing(_telegraph_mesh, pos, radius / 0.95, Color(1.0, 0.3, 0.14), Color(0.92, 0.1, 0.05),
		maxf(duration, 0.05), 0.0, 0.5)
	if n:
		n.linear = true
		n.fade = 0.12


## Respingo de quem levou um golpe, em `pos`, na cor `color` (a do monstro): `n` riscos curtos para todo
## lado. Leve de propósito: na Horda saem dezenas por segundo.
static func hit_splat(pos: Vector3, color: Color, n := 4) -> void:
	if FX._scene() == null:
		return
	var pal := {"core": color.lightened(0.6), "mid": color, "edge": color.darkened(0.45)}
	for i in n:
		var v := _burst_dir()
		streak(pos + v * 0.1, pos + v * randf_range(0.4, 0.8), randf_range(0.05, 0.08), pal,
			{"billboard": true, "shadow": false, "sweep": 0.05, "hold": 0.02, "fade": 0.14, "peak": 0.55})


## Espinhos escuros brotando em roda de `at` (com a base `tilt` do chão), entre `r0` e `r1` metros: o traço
## dos monstros. Tombam para fora; `n` espinhos de altura em torno de `height`.
static func thorns(at: Vector3, tilt: Basis, r0: float, r1: float, n: int, height: float, hold := 0.16) -> void:
	for i in n:
		var out := tilt * Vector3.BACK.rotated(Vector3.UP, TAU * (i + randf_range(-0.3, 0.3)) / n)
		var dist := randf_range(r0, r1)
		var foot := at + out * dist
		var h := height * randf_range(0.7, 1.3)
		streak(foot, foot + (tilt.y + out * randf_range(0.5, 1.0)).normalized() * h, h * randf_range(0.13, 0.19), THORN,
			{"billboard": true, "delay": dist * 0.03, "sweep": 0.06, "hold": hold, "fade": 0.3, "blunt": 1.0,
			"peak": 0.05, "lead": 0.3})


## Pancada no chão de um monstro em `pos`, com `radius` metros: uma onda escura de borda carmim até o raio,
## espinhos pretos brotando em roda e três garras rasgando o chão a partir do centro. Deita no terreno.
static func slam(pos: Vector3, radius: float) -> void:
	if FX._scene() == null:
		return
	var gf := ground_frame(pos, radius * 0.6)
	var tilt := gf.basis
	var at := gf.origin
	ring_wave(at + tilt.y * 0.07, radius, clampf(1.1 / radius, 0.12, 0.34), MENACE, 0.14, 0.0, null, tilt)
	thorns(at, tilt, radius * 0.45, radius * 0.9, clampi(int(radius * 3.0), 7, 14), 0.9 + radius * 0.08)
	# garras: três rasgos escuros, quase paralelos, numa direção sorteada
	var a0 := randf() * TAU
	for k in [-1.0, 0.0, 1.0]:
		var d := tilt * Vector3.BACK.rotated(Vector3.UP, a0 + k * 0.32)
		var from := at + tilt.y * 0.05 - d * radius * 0.25
		streak(from, from + d * radius * (0.95 if k == 0.0 else 0.8), 0.17, MENACE,
			{"shadow": false, "linear": true, "lead": 0.1, "sweep": 0.09, "hold": 0.55, "fade": 0.5, "peak": 0.45})


## Explosão de um monstro-bomba em `pos`, com `radius` metros de alcance: fogo carmim com fuligem preta (não
## o fogo laranja do jogador), um anel escuro até o raio do dano e espinhos em volta.
static func blast(pos: Vector3, radius: float) -> void:
	if FX._scene() == null:
		return
	fire_burst(pos + Vector3.UP * 0.6, clampf(radius / 2.6, 0.8, 1.8), HELLFIRE, SOOT, HELLFIRE, MENACE)
	var gf := ground_frame(pos, radius * 0.6)
	ring_wave(gf.origin + gf.basis.y * 0.07, radius, clampf(1.0 / radius, 0.12, 0.32), MENACE, 0.14, 0.0, null, gf.basis)
	thorns(gf.origin, gf.basis, radius * 0.3, radius * 0.75, 8, 0.8)


## Cura de um xamã em `pos`, com `radius` metros: um círculo de ritual no chão (verde doentio sobre roxo
## escuro), que gira e some, e fios de praga subindo do xamã. Nada do anel limpo da cura do jogador.
static func heal_pulse(pos: Vector3, radius: float) -> void:
	if FX._scene() == null:
		return
	_ground_drawing(_rune_quad(), pos, radius, BLIGHT.core, BLIGHT.edge, 0.25, 0.45, -0.9)
	heal_touch(pos, 8, 0.9)


## Quem foi curado pelo xamã, em `pos` (pés): fios de praga (verde com contorno roxo) subindo em volta.
static func heal_touch(pos: Vector3, n := 4, spread := 0.5) -> void:
	if FX._scene() == null:
		return
	for i in n:
		var a2 := TAU * (i + randf_range(-0.3, 0.3)) / n
		var foot := pos + Vector3(sin(a2), 0, cos(a2)) * randf_range(0.3, 1.0) * spread
		streak(foot + Vector3.UP * randf_range(0.2, 0.8), foot + Vector3.UP * randf_range(1.5, 2.2), randf_range(0.07, 0.1), BLIGHT,
			{"billboard": true, "linear": true, "delay": randf_range(0.0, 0.2), "sweep": 0.3, "hold": 0.05, "fade": 0.3,
			"peak": 0.7})


## Explosão de fogo em `pos` (Bola de Fogo): clarão, bolas de fogo que estufam para fora, faíscas, anel e
## a fumaça que sobe e demora a sumir.
static func fire_burst(pos: Vector3, size := 1.0, fire: Dictionary = FIRE, smoke: Dictionary = SMOKE,
		flash: Dictionary = FLASH, sparks: Dictionary = EMBER) -> void:
	if FX._scene() == null:
		return
	# fumaça primeiro (fica atrás do fogo) e por último a sumir
	for i in 7:
		var v := (_burst_dir() * 0.8 + Vector3.UP * 0.5).normalized()
		puff(pos + v * 0.5 * size, randf_range(1.3, 1.9) * size, smoke,
			{"vel": v * randf_range(2.0, 3.4) * size + Vector3.UP * 0.9, "delay": 0.15 + randf() * 0.08,
			"grow": 0.3, "hold": 0.3, "fade": 0.65, "sort": -0.2})
	for i in 6:
		var v := _burst_dir()
		puff(pos + v * 0.3 * size, randf_range(1.2, 1.7) * size, fire,
			{"vel": v * randf_range(4.0, 6.5) * size, "grow": 0.1, "hold": 0.07, "fade": 0.3})
	puff(pos, 1.9 * size, flash, {"grow": 0.06, "hold": 0.05, "fade": 0.22, "sort": 0.2})
	impact_sparks(pos, Vector3.BACK, 8, 180.0, sparks)
	ring_wave(pos - Vector3.UP * 0.3, 2.3 * size, 0.2, fire, 0.1)


## Desenho de gelo no chão, centrado em `pos`, até `radius`: aparece do centro para fora em `sweep`
## segundos, fica `hold` e some em manchas.
static func frost_sigil(pos: Vector3, radius: float, sweep := 0.22, hold := 1.1) -> void:
	if FX._scene() == null:
		return
	if _sigil_mesh == null:
		_sigil_mesh = PlaneMesh.new()
		_sigil_mesh.size = Vector2(2, 2)
		var m := ShaderMaterial.new()
		m.shader = SIGIL_SHADER
		_sigil_mesh.material = m
	_ground_drawing(_sigil_mesh, pos, radius, ICE.core, ICE.mid, sweep, hold)


## Cristal de gelo lapidado: prisma de seis lados que afina e termina num topo chato (não em agulha), de
## altura 1 e base de raio 0,5, com a base em y = 0. Faces com normal própria (tons chapados por face).
static func crystal_mesh() -> ArrayMesh:
	if _crystal_mesh != null:
		return _crystal_mesh
	var rings := [[0.0, 0.5], [0.58, 0.45], [1.0, 0.16]]     # [altura, raio]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tri := func(a: Vector3, b: Vector3, c: Vector3) -> void:
		var n := (b - a).cross(c - a).normalized()
		var mid := (a + b + c) / 3.0
		if n.dot(Vector3(mid.x, 0.35, mid.z)) < 0.0:         # a normal aponta para fora (e o topo, para cima)
			n = -n
		verts.append_array([a, b, c])
		normals.append_array([n, n, n])
	var at := func(i: int, k: int) -> Vector3:
		var a := TAU * i / 6.0
		return Vector3(cos(a) * float(rings[k][1]), float(rings[k][0]), sin(a) * float(rings[k][1]))
	for i in 6:
		for k in 2:
			tri.call(at.call(i, k), at.call(i, k + 1), at.call(i + 1, k + 1))
			tri.call(at.call(i, k), at.call(i + 1, k + 1), at.call(i + 1, k))
		tri.call(at.call(i, 2), Vector3(0, 1.04, 0), at.call(i + 1, 2))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	_crystal_mesh = ArrayMesh.new()
	_crystal_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var m := ShaderMaterial.new()
	m.shader = CRYSTAL_SHADER
	_crystal_mesh.surface_set_material(0, m)
	return _crystal_mesh


## Cristal brotando do chão em `foot`, com `height` de altura e `width` de largura, inclinado para `lean`
## (vetor; para cima = de pé). Salta, fica `hold` segundos e afunda. Opções: delay, pal.
static func crystal(foot: Vector3, height: float, width: float, lean: Vector3, o := {}) -> void:
	var root := FX._scene()
	if root == null:
		return
	var pal: Dictionary = o.get("pal", ICE)
	var n := CrystalNode.new()
	n.mesh = crystal_mesh()
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.delay = o.get("delay", 0.0)
	n.hold = o.get("hold", 0.7)
	n.size = Vector3(width, height, width)
	n.set_instance_shader_parameter("col_core", pal.core)
	n.set_instance_shader_parameter("col_mid", pal.mid)
	n.set_instance_shader_parameter("col_edge", pal.edge)
	root.add_child(n)
	var up := lean.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	n.base = Basis(side, up, side.cross(up)).rotated(up, randf() * TAU)
	n.global_position = foot
	n.place()


## Rajada rasteira de ar frio em `pos`, do centro até `radius`: fiapos claros correndo rente ao chão.
static func ground_gust(pos: Vector3, radius: float, pal: Dictionary, time := 0.45, delay := 0.0, tilt := Basis.IDENTITY) -> void:
	var root := FX._scene()
	if root == null:
		return
	if _gust_mesh == null:
		_gust_mesh = PlaneMesh.new()
		_gust_mesh.size = Vector2(2, 2)
		var m := ShaderMaterial.new()
		m.shader = GUST_SHADER
		_gust_mesh.material = m
	var n := GustNode.new()
	n.mesh = _gust_mesh
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.time = time
	n.delay = delay
	n.sorting_offset = -0.3
	n.set_instance_shader_parameter("col_front", pal.core)
	n.set_instance_shader_parameter("col_trail", pal.mid)
	n.set_instance_shader_parameter("seed", randf() * 20.0)
	n.set_instance_shader_parameter("front", 0.0)
	root.add_child(n)
	n.global_transform = Transform3D(tilt.scaled_local(Vector3.ONE * radius * 1.25), pos + tilt.y * 0.09)


## Nova Gélida centrada em `pos`: o desenho de gelo no chão, um anel e duas rajadas de ar frio abrindo até
## `radius`, cristais lapidados brotando em volta (de dentro para fora) e alguns brilhos.
static func frost_nova(pos: Vector3, radius: float) -> void:
	if FX._scene() == null:
		return
	frost_sigil(pos, radius)
	var gf := ground_frame(pos, radius * 0.6)      # tudo deita no terreno, como o desenho
	var tilt := gf.basis
	pos = gf.origin
	ring_wave(pos + tilt.y * 0.07, radius, 0.1, ICE, 0.2, 0.0, null, tilt)
	ground_gust(pos, radius, MIST, 0.4, 0.0, tilt)
	ground_gust(pos, radius * 0.8, MIST, 0.5, 0.12, tilt)
	for i in 9:
		var out := tilt * Vector3.BACK.rotated(Vector3.UP, TAU * (i + randf_range(-0.3, 0.3)) / 9.0)
		var dist := radius * randf_range(0.5, 0.9)
		var foot := pos + out * dist
		var wait := dist * 0.035
		var h := randf_range(1.2, 1.9)
		crystal(foot, h, h * randf_range(0.42, 0.52), Vector3.UP + out * randf_range(0.05, 0.25), {"delay": wait})
		# dois menores ao pé do grande, abrindo para os lados
		var side := Vector3.UP.cross(out)
		for k in [-1.0, 1.0]:
			var hs := h * randf_range(0.4, 0.62)
			crystal(foot + side * k * h * randf_range(0.24, 0.34) + out * randf_range(-0.2, 0.2), hs, hs * 0.5,
				Vector3.UP + side * k * randf_range(0.3, 0.55) + out * 0.15, {"delay": wait + 0.04})
	var glint := {"core": Color.WHITE, "mid": Color.WHITE, "edge": ICE.mid}
	for i in 10:
		var a := randf() * TAU
		var at := pos + Vector3(sin(a), 0, cos(a)) * radius * sqrt(randf()) + Vector3.UP * randf_range(0.4, 1.8)
		streak(at, at + Vector3.UP * randf_range(0.3, 0.6), 0.05, glint,
			{"billboard": true, "shadow": false, "delay": randf_range(0.2, 0.7), "sweep": 0.08, "hold": 0.04,
			"fade": 0.2, "peak": 0.5})


## Cura em `parent` (o jogador; os anéis andam com ele): anel no chão, outro na cintura e fios de luz subindo.
static func heal(parent: Node3D) -> void:
	if FX._scene() == null or parent == null:
		return
	ring_wave(Vector3(0, 0.08, 0), 1.35, 0.4, HEAL, 0.16, 0.0, parent)
	ring_wave(Vector3(0, 1.0, 0), 0.95, 0.3, HEAL, 0.16, 0.14, parent)
	var light := {"core": Color.WHITE, "mid": HEAL.core, "edge": HEAL.mid}
	for i in 10:
		var a := TAU * (i + randf_range(-0.3, 0.3)) / 10.0
		var foot := parent.global_position + Vector3(sin(a), 0, cos(a)) * randf_range(0.45, 1.0)
		streak(foot + Vector3.UP * randf_range(0.1, 0.8), foot + Vector3.UP * randf_range(1.6, 2.4), randf_range(0.05, 0.08), light,
			{"billboard": true, "shadow": false, "linear": true, "delay": randf_range(0.0, 0.25), "sweep": 0.3,
			"hold": 0.05, "fade": 0.3, "peak": 0.7})


## Faíscas de impacto: `n` riscos curtos saindo de `at`, para cima e abertos até `half_angle` graus de `dir`.
static func impact_sparks(at: Vector3, dir: Vector3, n: int, half_angle: float, pal: Dictionary = EMBER) -> void:
	for i in n:
		var ang := deg_to_rad(randf_range(-half_angle, half_angle))
		var out := (dir.rotated(Vector3.UP, ang) * randf_range(0.5, 1.0) + Vector3.UP * randf_range(0.5, 1.2)).normalized()
		streak(at + out * 0.15, at + out * randf_range(0.9, 1.7), randf_range(0.05, 0.09), pal,
			{"billboard": true, "shadow": false, "sweep": 0.05, "hold": 0.03, "fade": 0.16, "peak": 0.6})


## Turbilhão, o giro: redemoinho de fogo preso a `parent` (o jogador) por `time` segundos. As faixas giram
## com a lâmina: a cada quadro leem a ponta dela (`tip`) e põem a frente da pincelada ali, no mesmo raio e
## na mesma altura (nada é chutado: se o giro mudar de sentido ou de velocidade, o efeito vai junto, desde
## que seja anti-horário; ver WhirlRing). Devolve o nó (null no servidor): solte-o para interromper.
static func whirl_spin(parent: Node3D, tip: Node3D, time: float) -> Node3D:
	if FX._scene() == null or parent == null or tip == null:
		return null
	var holder := WhirlSpin.new()
	holder.time = time
	parent.add_child(holder)
	var seed0 := randf() * 20.0
	# [paleta, fase (graus atrás da lâmina), raio (x o da lâmina, ou fixo se < 0), altura (somada à da lâmina,
	#  ou fixa se < 0), espessura, sombra?]
	var rings := [
		[FIRE, 0.0, 1.12, 0.0, 0.62, true],            # a pincelada da lâmina
		[FIRE, 130.0, 0.8, 0.75, 0.5, true],           # mais alta e fechada: o funil sobe
		[FIRE, 250.0, 0.55, 1.45, 0.45, false],
		[DUST, 70.0, -2.9, -0.12, 0.3, false],         # poeira rodando no chão
		[DUST, 230.0, -2.3, -0.1, 0.26, false],
	]
	for i in rings.size():
		var r: Array = rings[i]
		var pal: Dictionary = r[0]
		for layer in 2:
			if layer == 0 and not r[5]:
				continue
			var n := WhirlRing.new()
			n.mesh = arc_mesh(WHIRL_ARC)
			n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n.tip = tip
			n.time = time
			n.phase = deg_to_rad(float(r[1]))
			n.radius_k = r[2]
			n.height_k = r[3]
			n.noise_seed = seed0 + i * 3.1 + layer * 4.7
			if layer == 0:
				n.radius_k *= 1.05 if n.radius_k > 0.0 else 1.0
				n.phase += deg_to_rad(8.0)
				n.sorting_offset = -0.1
				n.set_instance_shader_parameter("core", 0.0)
				n.set_instance_shader_parameter("thick", minf(1.0, float(r[4]) * 1.36))
				n.set_instance_shader_parameter("col_mid", pal.edge)
				n.set_instance_shader_parameter("col_edge", (pal.edge as Color).darkened(0.45))
			else:
				n.set_instance_shader_parameter("thick", r[4])
				n.set_instance_shader_parameter("col_core", pal.core)
				n.set_instance_shader_parameter("col_mid", pal.mid)
				n.set_instance_shader_parameter("col_edge", pal.edge)
			n.set_instance_shader_parameter("arc", deg_to_rad(WHIRL_ARC))
			n.set_instance_shader_parameter("peak", 0.72)
			n.set_instance_shader_parameter("head", 1.0)
			n.set_instance_shader_parameter("tail", 1.0)
			holder.add_child(n)
	return holder


## Turbilhão, a descida do golpe final: o corte preso ao jogador.
static func whirl_cut(parent: Node3D, dir: Vector3) -> void:
	slash(parent, atan2(dir.x, dir.z), WHIRL_CUT, FIRE)


## Turbilhão, o golpe final crava em `tip`: faíscas, labaredas em roda, onda de fogo até `radius`, poeira
## e fissuras em brasa saindo do ponto.
static func whirl_finale(base: Vector3, dir: Vector3, tip: Vector3, radius: float) -> void:
	if FX._scene() == null:
		return
	var ground := Vector3(tip.x, base.y + 0.05, tip.z)
	impact_sparks(ground, dir, 10, 180.0)
	for i in 12:
		var out := dir.rotated(Vector3.UP, TAU * (i + randf_range(-0.3, 0.3)) / 12.0)
		var dist := randf_range(1.1, radius * 0.9)
		var foot := base + out * dist
		var lean := (Vector3.UP + out * randf_range(0.2, 0.6)).normalized()
		var h := randf_range(1.0, 1.9)
		streak(foot, foot + lean * h, h * randf_range(0.2, 0.28), FIRE,
			{"billboard": true, "delay": dist * 0.03, "sweep": 0.07, "hold": 0.1, "fade": 0.35, "blunt": 1.0,
			"peak": 0.12, "lead": 0.3})
	for wave in [[FIRE, radius + 0.3, 0.3], [DUST, radius + 1.2, 0.16]]:
		var list := []
		for o in WHIRL_BLAST:
			var r: Dictionary = (o as Dictionary).duplicate()
			r["radius"] = wave[1]
			r["thick"] = wave[2]
			list.append(r)
		slashes_at(base, dir, list, wave[0])
	for i in 5:
		var d := dir.rotated(Vector3.UP, TAU * (i + randf_range(-0.25, 0.25)) / 5.0)
		var length := randf_range(2.0, 3.0)
		streak(ground, ground + d * length, 0.24, FISSURE,
			{"shadow": false, "linear": true, "lead": 0.1, "sweep": 0.14, "hold": 0.6, "fade": 0.5, "blunt": 1.0, "peak": 0.25})


## Golpe Sísmico, a descida: o corte preso ao jogador.
static func quake_cut(parent: Node3D, dir: Vector3, color: Color) -> void:
	slash(parent, atan2(dir.x, dir.z), QUAKE_CUT, palette(color))


## Golpe Sísmico, a lâmina crava em `tip` (no chão): faíscas em leque, poeira, e três fissuras em brasa
## que correm pelo cone (`range_m` de alcance, `half_angle` graus de meio ângulo) na velocidade da onda
## (`step` segundos por metro), a partir de `base` (pés do jogador).
static func quake_impact(base: Vector3, dir: Vector3, tip: Vector3, range_m: float, half_angle: float, step: float) -> void:
	if FX._scene() == null:
		return
	var ground := Vector3(tip.x, base.y + 0.05, tip.z)
	impact_sparks(ground, dir, 7, 75.0)
	slashes_at(base, -dir, CHARGE_KICK, DUST)
	# fissuras: a do meio vai até o fim do cone; as de lado são mais curtas
	for f in [[0.0, 1.0, 0.3], [0.62, 0.72, 0.22], [-0.62, 0.72, 0.22]]:
		var d := dir.rotated(Vector3.UP, deg_to_rad(half_angle) * float(f[0]))
		var length := range_m * float(f[1])
		streak(ground, ground + d * length, float(f[2]), FISSURE,
			{"shadow": false, "linear": true, "lead": 0.05, "sweep": length * step, "hold": 0.45, "fade": 0.5,
			"blunt": 1.0, "peak": 0.25})


## Golpe Sísmico, a onda chegou a `m` metros de `base`: estilhaços de pedra saltam dentro do cone e, a cada
## dois metros, uma onda de choque de poeira.
static func quake_wave(base: Vector3, dir: Vector3, m: float, half_angle: float) -> void:
	if FX._scene() == null:
		return
	var side := Vector3.UP.cross(dir)
	var spread := tan(deg_to_rad(half_angle)) * m
	for k in 3:
		var foot := base + dir * (m + randf_range(-0.3, 0.3)) + side * randf_range(-0.85, 0.85) * spread
		var lean := (Vector3.UP + dir * randf_range(0.1, 0.5) + side * randf_range(-0.35, 0.35)).normalized()
		var h := randf_range(0.7, 1.25) + m * 0.08
		streak(foot, foot + lean * h, h * randf_range(0.2, 0.3), ROCK,
			{"billboard": true, "sweep": 0.07, "hold": 0.12, "fade": 0.32, "blunt": 1.0, "peak": 0.12, "lead": 0.3})
	if int(m) % 2 == 0:
		var list := []
		for o in QUAKE_RIPPLE:
			var r: Dictionary = (o as Dictionary).duplicate()
			r["radius"] = m + 0.3
			r["thick"] = clampf(0.75 / m, 0.1, 0.5)
			list.append(r)
		slashes_at(base, dir, list, DUST)


## Lança da Investida: nasce em `origin` (pés do jogador na saída) apontando para `dir`. Quem avança chama
## reach(ponta, meio da lâmina) a cada passo: a ponta da lança vai sempre na lâmina, e a altura e o lado
## também vêm dela (nada é chutado). Parou de ser chamada (chegou, parede, morte)? Ela se desfaz sozinha.
## Devolve null no servidor dedicado.
static func charge_lance(origin: Vector3, dir: Vector3, color: Color) -> LanceNode:
	var root := FX._scene()
	if root == null:
		return null
	var pal := palette(color)
	var seed0 := randf() * 20.0
	# sombra (atrás, mais larga), a lança, e três riscos de velocidade soltos em volta
	var layers := [
		{"w": 1.0, "core": 1.0, "mid": pal.mid, "edge": pal.edge},
		{"w": 1.45, "delay": 0.03, "sort": -0.1, "core": 0.0, "mid": pal.edge, "edge": (pal.edge as Color).darkened(0.45)},
		{"w": 0.12, "off": Vector3(0.75, 0.25, 0), "lag": 1.6, "core": 1.0, "mid": pal.core, "edge": pal.mid},
		{"w": 0.1, "off": Vector3(-0.8, 0.05, 0), "lag": 2.3, "core": 1.0, "mid": pal.core, "edge": pal.mid},
		{"w": 0.09, "off": Vector3(-0.35, -0.5, 0), "lag": 1.2, "core": 1.0, "mid": pal.core, "edge": pal.mid},
	]
	var main: LanceNode = null
	for i in layers.size():
		var layer: Dictionary = layers[i]
		var n := LanceNode.new()
		n.mesh = lance_mesh()
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.origin = origin
		n.dir = dir
		n.half_width = LANCE_WIDTH * float(layer.w)
		n.offset = layer.get("off", Vector3.ZERO)
		n.lag = layer.get("lag", 0.0)
		n.delay = layer.get("delay", 0.0)
		n.sorting_offset = layer.get("sort", 0.0)
		n.noise_seed = seed0 + i * 4.7
		n.set_instance_shader_parameter("core", layer.core)
		n.set_instance_shader_parameter("col_core", pal.core)
		n.set_instance_shader_parameter("col_mid", layer.mid)
		n.set_instance_shader_parameter("col_edge", layer.edge)
		n.set_instance_shader_parameter("arc", LANCE_LENGTH * 0.9)
		n.set_instance_shader_parameter("peak", 0.82)
		n.set_instance_shader_parameter("head", 0.0)
		if main == null:
			main = n
		else:
			n.follower = true
			main.twins.append(n)
		root.add_child(n)
	return main


## Saída da Investida: poeira em "V" atrás dos pés.
static func charge_kick(pos: Vector3, dir: Vector3) -> void:
	slashes_at(pos, dir, CHARGE_KICK, DUST)


## Chegada da Investida: a poeira da freada, abrindo para a frente.
static func charge_arrive(pos: Vector3, dir: Vector3) -> void:
	slashes_at(pos, -dir, CHARGE_KICK, DUST)


## O corte que fecha a Investida, preso a `parent` (o jogador) e virado para `dir`.
static func charge_cut(parent: Node3D, dir: Vector3, color: Color) -> void:
	slash(parent, atan2(dir.x, dir.z), CHARGE_CUT, palette(color))


## Corte do golpe `combo` (1..3) da espada, preso a `parent` (o nó do jogador) e virado por `yaw`.
static func sword_slash(parent: Node3D, yaw: float, combo: int, color: Color) -> void:
	slash(parent, yaw, SWORD_COMBO[clampi(combo, 1, 3) - 1], palette(color))


## Corte da montante (GREAT_COMBO); `dur` = duração do golpe.
static func great_slash(parent: Node3D, yaw: float, combo: int, dur: float, color: Color) -> void:
	var o: Dictionary = (GREAT_COMBO[clampi(combo, 1, GREAT_COMBO.size()) - 1] as Dictionary).duplicate()
	o["sweep"] = maxf(0.04, float(o.sweep_frac) * dur)
	o["hold"] = 0.05
	o["fade"] = 0.24
	slash(parent, yaw, o, palette(color))


## Corte do combo de espada com escudo (KnightMovesShield.SLASH, medido da ponta da lâmina pelo retarget);
## `dur` = duração do golpe, que converte o tempo do arco (fração do golpe) em segundos. O giro (último)
## corre por igual, como o giro da espada.
static func shield_combo_slash(parent: Node3D, yaw: float, combo: int, dur: float, color: Color) -> void:
	var n: int = KnightMovesShield.SLASH.size()
	var o: Dictionary = (KnightMovesShield.SLASH[clampi(combo, 1, n) - 1] as Dictionary).duplicate()
	o["sweep"] = maxf(0.04, float(o.sweep_frac) * dur)
	o["hold"] = 0.04
	o["fade"] = 0.22
	if combo == n:
		o.merge({"linear": true, "lead": 0.03, "trail": 0.6, "hold": 0.02})
	slash(parent, yaw, o, palette(color))


## Base da pincelada da receita `o`: Z aponta para onde ela começa, Y é o eixo do giro (a malha de
## arc_mesh corre de +Z para +X). Devolve também quantos graus ela cobre.
static func slash_frame(o: Dictionary) -> Dictionary:
	var from: Vector3 = (o.from as Vector3).normalized()
	var axis: Vector3
	var degrees: float
	if o.has("to"):
		var to: Vector3 = (o.to as Vector3).normalized()
		axis = from.cross(to).normalized()
		var pre: float = o.get("pre", 0.0)
		degrees = rad_to_deg(from.angle_to(to)) + pre + float(o.get("post", 0.0))
		from = from.rotated(axis, -deg_to_rad(pre))
	else:
		axis = (o.axis as Vector3).normalized()
		from = (from - axis * from.dot(axis)).normalized()    # o começo fica no plano do giro
		degrees = o.arc
	return {"basis": Basis(axis.cross(from), axis, from), "degrees": degrees}


## Um corte: duas pinceladas (a de trás é a sombra, um pouco maior e atrasada) presas a `parent`.
static func slash(parent: Node3D, yaw: float, o: Dictionary, pal: Dictionary) -> void:
	if Network.is_server() or parent == null or not is_instance_valid(parent):
		return
	var fr := slash_frame(o)
	var b: Basis = Basis(Vector3.UP, yaw) * (fr.basis as Basis)
	var center: Vector3 = o.get("center", Vector3(0, 1.2, 0)) - Vector3(0, KnightLook.fx_drop(parent), 0)   # corpo mais baixo (anão)
	var seed0 := randf() * 20.0
	for layer in 2:
		if layer == 0 and not o.get("shadow", true):
			continue
		var s := SlashNode.new()
		s.mesh = arc_mesh(fr.degrees)
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.sweep = o.get("sweep", 0.08)
		s.hold = o.get("hold", 0.03)
		s.fade = o.get("fade", 0.2)
		s.linear = o.get("linear", false)
		s.lead = o.get("lead", 0.2)
		s.trail = o.get("trail", 1.0)
		s.delay = o.get("delay", 0.0)
		s.noise_seed = seed0 + layer * 4.7
		var r: float = o.get("radius", 1.8)
		if layer == 0:      # sombra: atrás, mais larga, sem núcleo, chega um instante depois
			s.delay += 0.025
			s.grow = 1.08
			s.sorting_offset = -0.1
			r *= 1.04
			s.set_instance_shader_parameter("core", 0.0)
			s.set_instance_shader_parameter("thick", minf(1.0, float(o.get("thick", 0.7)) * 1.36))
			s.set_instance_shader_parameter("col_mid", pal.edge)
			s.set_instance_shader_parameter("col_edge", (pal.edge as Color).darkened(0.45))
		else:
			s.set_instance_shader_parameter("thick", o.get("thick", 0.7))
			s.set_instance_shader_parameter("col_core", pal.core)
			s.set_instance_shader_parameter("col_mid", pal.mid)
			s.set_instance_shader_parameter("col_edge", pal.edge)
		s.set_instance_shader_parameter("arc", deg_to_rad(fr.degrees))
		s.set_instance_shader_parameter("blunt", o.get("blunt", 0.0))
		s.set_instance_shader_parameter("peak", o.get("peak", 0.5))
		s.radius = r
		s.base = b
		s.transform = Transform3D(b.scaled_local(Vector3.ONE * r), Basis(Vector3.UP, yaw) * center)
		parent.add_child(s)


## Uma pincelada: avança até a ponta em `sweep`, segura `hold` e se desfaz pela cauda em `fade`.
## Anima "em dois": o ruído muda a 12 quadros por segundo, como desenho quadro a quadro.
class SlashNode extends MeshInstance3D:
	var sweep := 0.08
	var hold := 0.03
	var fade := 0.2
	var delay := 0.0
	var noise_seed := 0.0
	var grow := 1.04
	var linear := false     ## a ponta anda em velocidade constante (giro) em vez de estalar e frear
	var lead := 0.2         ## fração do arco já desenhada no primeiro quadro
	var trail := 1.0        ## comprimento máximo da pincelada atrás da ponta (fração do arco)
	var radius := 1.8
	var base := Basis.IDENTITY
	var line := false         ## pincelada reta (FXToon.streak) de line_a a line_b, no mundo
	var line_a := Vector3.ZERO
	var line_b := Vector3.ZERO
	var half_width := 0.2
	var face_camera := false  ## a faixa reta gira em torno do próprio eixo para encarar a câmera
	var _age := 0.0

	func _ready() -> void:
		_apply()

	func _process(delta: float) -> void:
		_age += delta
		if _age - delay >= sweep + hold + fade:
			queue_free()
			return
		_apply()

	func _apply() -> void:
		var t := _age - delay
		visible = t >= 0.0
		if not visible:
			return
		var k := clampf(t / sweep, 0.0, 1.0)
		var out := clampf((t - sweep - hold) / fade, 0.0, 1.0)
		var h := lead + (1.0 - lead) * (k if linear else 1.0 - pow(1.0 - k, 2.5))
		var tl := maxf(0.0, h - trail)
		set_instance_shader_parameter("head", h)
		set_instance_shader_parameter("tail", lerpf(tl, h, 0.55 * out * out))
		set_instance_shader_parameter("erode", out)
		set_instance_shader_parameter("seed", noise_seed + floorf(t * 12.0) * 0.13)
		if line:
			var along := line_b - line_a
			var look := Vector3.UP
			if face_camera:
				var cam := get_viewport().get_camera_3d()
				if cam:
					look = cam.global_position - line_a
			var side := look.cross(along)
			if side.length_squared() < 0.000001:
				side = Vector3.RIGHT
			side = side.normalized()
			global_transform = Transform3D(Basis(side * half_width, along.normalized().cross(side), along), line_a)
			return
		var sc := radius * lerpf(1.0, grow, clampf(t / (sweep + hold + fade), 0.0, 1.0))
		basis = base.scaled_local(Vector3.ONE * sc)


## Uma faixa da lança da Investida (ver FXToon.charge_lance).
class LanceNode extends MeshInstance3D:
	var origin := Vector3.ZERO
	var dir := Vector3.FORWARD
	var half_width := 0.4
	var offset := Vector3.ZERO      ## deslocamento (x = para a esquerda de `dir`, y = cima) dos riscos soltos
	var lag := 0.0                  ## quantos metros a ponta deste risco fica atrás da lâmina
	var delay := 0.0
	var fade := 0.24
	var trail := 0.7                ## comprimento máximo atrás da ponta (fração da malha)
	var noise_seed := 0.0
	var follower := false           ## camada comandada pela principal (reach/finish chegam por ela)
	var twins: Array = []
	var _head_m := 0.0
	var _line := Vector3.ZERO       ## por onde a lança passa: o ponto da lâmina, trazido de volta até a saída
	var _age := 0.0
	var _idle := 0.0
	var _out := -1.0

	func _ready() -> void:
		_line = origin + Vector3.UP
		_place()

	## A ponta da lâmina está em `tip` e o meio dela em `mid` (mundo): a ponta da lança vai até `tip` e a
	## lança corre pela altura e pelo lado de `mid` (a lâmina fica dentro dela, não em cima).
	func reach(tip: Vector3, mid: Vector3) -> void:
		_head_m = maxf(_head_m, (tip - origin).dot(dir) + 0.35 - lag)
		_line = mid - dir * (mid - origin).dot(dir)
		_idle = 0.0
		for t in twins:
			if is_instance_valid(t):
				(t as LanceNode).reach(tip, mid)

	func finish() -> void:
		if _out < 0.0:
			_out = 0.0
		for t in twins:
			if is_instance_valid(t):
				(t as LanceNode).finish()

	func _process(delta: float) -> void:
		_age += delta
		_idle += delta
		if _idle > 0.1 and not follower:
			finish()
		if _out >= 0.0:
			_out += delta
			if _out >= fade:
				queue_free()
				return
		_place()

	func _place() -> void:
		var side := Vector3.UP.cross(dir).normalized()
		global_transform = Transform3D(Basis(side * half_width, Vector3.UP, dir * FXToon.LANCE_LENGTH),
			_line + side * offset.x + Vector3.UP * offset.y)
		visible = _age >= delay and _head_m > 0.05
		var h := clampf(_head_m / FXToon.LANCE_LENGTH, 0.0, 1.0)
		var out := clampf(_out / fade, 0.0, 1.0)
		set_instance_shader_parameter("head", h)
		set_instance_shader_parameter("tail", lerpf(maxf(0.0, h - trail), h, 0.6 * out * out))
		set_instance_shader_parameter("erode", out)
		set_instance_shader_parameter("seed", noise_seed + floorf(_age * 12.0) * 0.13)


## O redemoinho do Turbilhão (FXToon.whirl_spin): segura as faixas e solta brasas subindo em volta.
class WhirlSpin extends Node3D:
	var time := 1.5
	var _age := 0.0
	var _ember := 0.0

	func _process(delta: float) -> void:
		_age += delta
		if _age > time + 0.4:
			queue_free()
			return
		_ember -= delta
		if _ember <= 0.0 and _age < time:
			_ember = 0.06
			var a := randf() * TAU
			var foot := global_position + Vector3(sin(a), 0, cos(a)) * randf_range(1.0, 3.0) + Vector3.UP * randf_range(0.1, 1.6)
			FXToon.streak(foot, foot + Vector3(0, randf_range(0.5, 1.0), 0), randf_range(0.03, 0.06), FXToon.EMBER,
				{"billboard": true, "shadow": false, "sweep": 0.12, "hold": 0.05, "fade": 0.2, "peak": 0.6})


## Uma faixa do redemoinho: um arco deitado, filho de WhirlSpin, que roda para a ponta da pincelada ficar
## sempre no ângulo da lâmina menos `phase`. A malha (FXToon.arc_mesh) corre no sentido anti-horário visto
## de cima, então a pincelada só "segue" a lâmina se o giro for anti-horário (é o que SwordAbilities faz;
## se um dia inverter, espelhe a malha aqui).
class WhirlRing extends MeshInstance3D:
	var tip: Node3D
	var time := 1.5
	var phase := 0.0
	var radius_k := 1.1      ## > 0: vezes o raio da lâmina; < 0: raio fixo (m)
	var height_k := 0.0      ## >= 0: somado à altura da lâmina; < 0: altura fixa (m)
	var noise_seed := 0.0
	var _age := 0.0
	var _r := 0.0
	var _y := 0.0

	func _ready() -> void:
		_place(1.0)

	func _process(delta: float) -> void:
		_age += delta
		_place(1.0 - exp(-12.0 * delta))

	func _place(k: float) -> void:
		if not is_instance_valid(tip):
			visible = false
			return
		var at: Vector3 = (get_parent() as Node3D).to_local(tip.global_position)
		var r := Vector2(at.x, at.z).length()
		# raio e altura suavizados (o tronco inclinado faz a ponta subir e descer a cada volta)
		_r = r if _r == 0.0 else lerpf(_r, r, k)
		_y = at.y if _y == 0.0 else lerpf(_y, at.y, k)
		var radius := _r * radius_k if radius_k > 0.0 else -radius_k
		var y := _y + height_k if height_k >= 0.0 else -height_k
		var ang := atan2(at.x, at.z) - phase - deg_to_rad(FXToon.WHIRL_ARC) + 0.12
		transform = Transform3D(Basis(Vector3.UP, ang).scaled_local(Vector3.ONE * radius), Vector3(0, y, 0))
		# a pincelada cresce com o giro e se desfaz no fim
		var grown := clampf(_age / 0.3, 0.0, 1.0)
		var out := clampf((_age - time) / 0.35, 0.0, 1.0)
		set_instance_shader_parameter("tail", 1.0 - grown * (1.0 - 0.5 * out * out))
		set_instance_shader_parameter("erode", out)
		set_instance_shader_parameter("seed", noise_seed + floorf(_age * 12.0) * 0.13)


## Uma camada do cometa de um projétil (FXToon.comet): faixa reta, de frente para a câmera, com a cabeça um
## pouco à frente do projétil e a cauda para trás, no sentido contrário ao de `direction` do pai.
class CometNode extends MeshInstance3D:
	var length := 2.2
	var half_width := 0.3
	var noise_seed := 0.0
	var embers := false       ## solta brasas pela cauda
	var anchor: Node3D        ## de onde ler a posição (null = o pai)
	var _age := 0.0
	var _ember := 0.0

	func _dir() -> Vector3:
		var d: Vector3 = get_parent().get("direction")
		return d.normalized() if d.length_squared() > 0.000001 else Vector3.FORWARD

	func _at() -> Vector3:
		return anchor.global_position if is_instance_valid(anchor) else (get_parent() as Node3D).global_position

	func _ready() -> void:
		top_level = true
		_place()

	func _process(delta: float) -> void:
		_age += delta
		_place()
		_ember -= delta
		if embers and _ember <= 0.0:
			_ember = 0.045
			var d := _dir()
			var at := _at() - d * 0.3 + Vector3(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2), randf_range(-0.2, 0.2))
			FXToon.streak(at, at - d * 0.5 + Vector3.UP * 0.15, 0.05, FXToon.EMBER,
				{"billboard": true, "shadow": false, "sweep": 0.08, "hold": 0.02, "fade": 0.18, "peak": 0.6})

	func _place() -> void:
		var d := _dir()
		var here := _at()
		# a cauda cresce no primeiro décimo de segundo: não nasce atravessando quem lançou
		var tail := here - d * length * clampf(_age / 0.12, 0.08, 1.0)
		var along := here + d * half_width - tail
		var look := Vector3.UP
		var cam := get_viewport().get_camera_3d()
		if cam:
			look = cam.global_position - tail
		var side := look.cross(along)
		side = side.normalized() if side.length_squared() > 0.000001 else Vector3.RIGHT
		global_transform = Transform3D(Basis(side * half_width, along.normalized().cross(side), along), tail)
		set_instance_shader_parameter("seed", noise_seed + floorf(_age * 12.0) * 0.13)


## Uma baforada (FXToon.puff): estufa em `grow`, segura `hold` e some encolhendo em `fade`; anda com `vel`,
## que freia. O shader a mantém de frente para a câmera.
class PuffNode extends MeshInstance3D:
	var size := 1.0
	var vel := Vector3.ZERO
	var delay := 0.0
	var grow := 0.15
	var hold := 0.15
	var fade := 0.4
	var _age := 0.0

	func _ready() -> void:
		_apply()

	func _process(delta: float) -> void:
		_age += delta
		var t := _age - delay
		if t >= grow + hold + fade:
			queue_free()
			return
		if t >= 0.0:
			global_position += vel * delta
			vel *= exp(-4.0 * delta)
		_apply()

	func _apply() -> void:
		var t := _age - delay
		visible = t >= 0.0
		if not visible:
			return
		var k := clampf(t / grow, 0.0, 1.0)
		var out := clampf((t - grow - hold) / fade, 0.0, 1.0)
		# estufa rápido e continua crescendo devagar enquanto se desfaz
		scale = Vector3.ONE * size * (0.3 + 0.7 * (1.0 - pow(1.0 - k, 2.5))) * (1.0 + 0.2 * out)
		set_instance_shader_parameter("erode", out)
		set_instance_shader_parameter("boil", floorf(t * 12.0))


## Um desenho de chão (FXToon.frost_sigil, FXToon.rune_circle).
class SigilNode extends MeshInstance3D:
	var sweep := 0.22
	var hold := 1.1           ## < 0: fica até release()
	var fade := 0.6
	var spin_rate := 0.0      ## rad/s do giro do desenho (o de runas e o aviso giram)
	var linear := false       ## o desenho enche em velocidade constante até 1 (aviso: cheio = o golpe cai)
	var _age := 0.0

	## Começa a sumir agora (para os de `hold` negativo).
	func release() -> void:
		if hold < 0.0:
			hold = maxf(_age - sweep, 0.0)

	func _process(delta: float) -> void:
		_age += delta
		if hold >= 0.0 and _age >= sweep + hold + fade:
			queue_free()
			return
		set_instance_shader_parameter("reveal", (1.0 if linear else 1.1) * clampf(_age / sweep, 0.0, 1.0))
		set_instance_shader_parameter("erode", clampf((_age - sweep - hold) / fade, 0.0, 1.0) if hold >= 0.0 else 0.0)
		if spin_rate != 0.0:
			set_instance_shader_parameter("spin", _age * spin_rate)


## Um cristal de gelo (FXToon.crystal): salta do chão passando um pouco do tamanho, assenta, fica `hold`
## segundos e afunda de volta.
class CrystalNode extends MeshInstance3D:
	var delay := 0.0
	var hold := 0.7
	var size := Vector3.ONE
	var base := Basis.IDENTITY
	var _age := 0.0

	func _process(delta: float) -> void:
		_age += delta
		if _age - delay >= 0.16 + hold + 0.22:
			queue_free()
			return
		place()

	func place() -> void:
		var t := _age - delay
		visible = t >= 0.0
		if not visible:
			return
		var k := clampf(t / 0.16, 0.0, 1.0) - 1.0
		var pop := 1.0 + 2.7 * k * k * k + 1.7 * k * k            # passa do tamanho e volta
		var sink := clampf((t - 0.16 - hold) / 0.22, 0.0, 1.0)
		var y := pop * (1.0 - sink * sink)
		basis = base.scaled_local(Vector3(size.x * (0.6 + 0.4 * pop), maxf(size.y * y, 0.001), size.z * (0.6 + 0.4 * pop)))


## A rajada rasteira (FXToon.ground_gust): a frente corre do centro até a borda e os fiapos se desfazem.
class GustNode extends MeshInstance3D:
	var time := 0.45
	var delay := 0.0
	var _age := 0.0

	func _process(delta: float) -> void:
		_age += delta
		var t := _age - delay
		visible = t >= 0.0
		if t >= time + 0.35:
			queue_free()
			return
		var k := clampf(t / time, 0.0, 1.0)
		set_instance_shader_parameter("front", 1.0 - pow(1.0 - k, 2.0))
		set_instance_shader_parameter("erode", clampf((t - time * 0.7) / (time * 0.3 + 0.35), 0.0, 1.0))


## Disco ou anel de energia (FXToon.orb, FXToon.pop): vai de size0 a size1 e de inner0 a inner1 em `time`
## segundos e se libera; com `time` negativo fica para sempre, pulsando (esfera de um projétil).
class PopNode extends MeshInstance3D:
	var size0 := 0.5
	var size1 := 1.0
	var inner0 := 0.0
	var inner1 := 0.0
	var time := 0.2
	var delay := 0.0
	var vel := Vector3.ZERO
	var ease_in := false
	var pulse := 0.0
	var _age := 0.0

	func _ready() -> void:
		_apply()

	func _process(delta: float) -> void:
		_age += delta
		var t := _age - delay
		if time >= 0.0 and t >= time:
			queue_free()
			return
		if t >= 0.0 and vel != Vector3.ZERO:
			global_position += vel * delta
			vel *= exp(-5.0 * delta)
		_apply()

	func _apply() -> void:
		var t := _age - delay
		visible = t >= 0.0
		if not visible:
			return
		var k := clampf(t / time, 0.0, 1.0) if time > 0.0 else 0.0
		k = k * k if ease_in else 1.0 - pow(1.0 - k, 2.0)
		var s := lerpf(size0, size1, k) * (1.0 + pulse * sin(_age * 26.0))
		scale = Vector3.ONE * maxf(s, 0.001)
		set_instance_shader_parameter("inner", lerpf(inner0, inner1, k))
		set_instance_shader_parameter("boil", floorf(_age * 14.0))


## A tensão da Flecha do Vendaval (FXToon.gale_charge): segura as faixas de vento, a esfera da ponta da
## flecha e solta um pulso de luz na ponta a cada 0,3 s. `charge` (0..1) é escrita por quem tensiona.
class GaleCharge extends Node3D:
	var charge := 0.0
	var tip: Node3D
	var glow: PopNode
	var _pulse := 0.3

	func _process(delta: float) -> void:
		if is_instance_valid(glow):
			glow.size0 = 0.14 + 0.24 * charge
			glow.size1 = glow.size0
		_pulse -= delta
		if _pulse <= 0.0 and is_instance_valid(tip):
			_pulse = 0.3
			# anel grosso que fecha sobre a ponta (o ar sendo puxado para a flecha)
			FXToon.pop(tip.global_position, FXToon.WIND, {"size0": 1.0 + 0.8 * charge, "size1": 0.25, "inner0": 0.6,
				"inner1": 0.0, "time": 0.22, "ease_in": true})

	func _exit_tree() -> void:
		if is_instance_valid(glow):
			glow.queue_free()


## Uma faixa de vento da tensão: arco deitado, filho de GaleCharge, que gira sozinho (anti-horário visto de
## cima, o sentido da malha) cada vez mais rápido e mais fechado conforme a carga do pai sobe.
class WindRing extends MeshInstance3D:
	var angle := 0.0
	var height := 1.0
	var radius0 := 2.0
	var radius1 := 1.0
	var noise_seed := 0.0
	var _age := 0.0

	func _ready() -> void:
		_place(0.0)

	func _process(delta: float) -> void:
		_age += delta
		_place(delta)

	func _place(delta: float) -> void:
		var c: float = (get_parent() as GaleCharge).charge
		angle += lerpf(5.0, 16.0, c) * delta
		transform = Transform3D(Basis(Vector3.UP, angle).scaled_local(Vector3.ONE * lerpf(radius0, radius1, c)), Vector3(0, height, 0))
		set_instance_shader_parameter("tail", 1.0 - clampf(_age / 0.3, 0.0, 1.0))
		set_instance_shader_parameter("seed", noise_seed + floorf(_age * 12.0) * 0.13)
