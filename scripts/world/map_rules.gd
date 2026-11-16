class_name MapRules
extends RefCounted
## Minimapa e mapa-mundi (puro, sem autoload): retângulo de cada mapa (Regions), conversão mundo → mapa,
## nomes dos lugares e quem aparece no mapa. O norte (-Z) fica para cima.

## Lugares com nome no mapa: região -> [[nome, posição local (relativa ao centro da região)]].
## Nome no mapa -> landmark da cena do mapa (MapData.landmark); "" = o centro do mapa.
const PLACES := {
	"vila": [["Vila de Valdoria", ""], ["Horta", "farm"], ["Pomar", "orchard"], ["Acampamento Goblin", "camp"],
		["Ruínas", "ruins"], ["Portal da Horda", "portal"], ["Ninho de Slimes", "nest"]],
	"bosque": [["Bosque Sussurrante", ""]],
	"mina": [["Mina de Cristal", ""]],
	"pico": [["Pico das Cinzas", ""]],
}
## Raio (m) do pedaço do mapa que o minimapa mostra em volta do jogador.
const MINI_RADIUS := 42.0


## Folga (m) do círculo do mapa além dos cantos da área jogável.
const CIRCLE_PAD := 4.0


## Raio do mapa redondo: o círculo que contém a área jogável inteira (os cantos também); o que fica entre
## o muro e o círculo é a serra da borda, que existe no chão (ground.gd vai até half + 150).
static func radius(region: String) -> float:
	return float(Regions.DATA[region].half) * sqrt(2.0) + CIRCLE_PAD


## Pedaço do chão que a foto de cima (MapCapture) cobre: o círculo do mapa e, perto da borda, o raio do
## minimapa inteiro (assim nada do que o minimapa ou o atlas mostram fica sem foto).
static func capture_rect(region: String) -> Rect2:
	var o: Vector3 = Regions.origin(region)
	var h := maxf(radius(region), float(Regions.DATA[region].half) + MINI_RADIUS + 4.0)
	return Rect2(o.x - h, o.z - h, h * 2.0, h * 2.0)


## Retângulo do mapa no plano XZ: posição = canto noroeste (x mín, z mín), tamanho = largura.
static func rect(region: String) -> Rect2:
	var o: Vector3 = Regions.origin(region)
	var h: float = Regions.DATA[region].half
	return Rect2(o.x - h, o.z - h, h * 2.0, h * 2.0)


## Posição do mundo → coordenada 0..1 no mapa da região (fora do mapa passa de 0..1).
static func to_uv(region: String, pos: Vector3) -> Vector2:
	var r := rect(region)
	return Vector2((pos.x - r.position.x) / r.size.x, (pos.z - r.position.y) / r.size.y)


## Coordenada 0..1 no mapa → posição no chão (y = 0).
static func from_uv(region: String, uv: Vector2) -> Vector3:
	var r := rect(region)
	return Vector3(r.position.x + uv.x * r.size.x, 0.0, r.position.y + uv.y * r.size.y)


## Lugares com nome da região em posição global: [[nome, Vector3]].
static func places(region: String) -> Array:
	var out: Array = []
	for p in PLACES.get(region, []):
		out.append([p[0], Regions.origin(region) if p[1] == "" else MapData.landmark(region, p[1])])
	out.append(["Carruagem da Guilda", Regions.coach_point(region)])
	return out


## ---- Atlas (mapa-mundi): as regiões ficam a centenas de metros umas das outras na cena; no atlas elas
## são círculos (radius) postos lado a lado na mesma direção (o vale no meio, as outras a leste/sul dele)
## com ATLAS_GAP metros de mar entre eles. Coordenadas do atlas = metros, o norte (-Z) para cima.
const ATLAS_GAP := 46.0


## Centro da região no atlas.
static func atlas_center(region: String) -> Vector2:
	var o: Vector3 = Regions.origin(region)
	var hv := radius("vila")
	var h := radius(region)
	var c := Vector2.ZERO
	if o.x > 1.0:
		c.x = hv + ATLAS_GAP + h
	elif o.x < -1.0:
		c.x = -(hv + ATLAS_GAP + h)
	if o.z > 1.0:
		c.y = hv + ATLAS_GAP + h
	elif o.z < -1.0:
		c.y = -(hv + ATLAS_GAP + h)
	return c


## Quadrado em volta do círculo da região no atlas.
static func atlas_rect(region: String) -> Rect2:
	var h := radius(region)
	return Rect2(atlas_center(region) - Vector2(h, h), Vector2(h, h) * 2.0)


## Região cujo círculo contém o ponto do atlas ("" = mar).
static func atlas_region_at(a: Vector2) -> String:
	for id in Regions.ORDER:
		if a.distance_to(atlas_center(id)) <= radius(id):
			return id
	return ""


## Leva um ponto do atlas para dentro do mapa mais perto (onde não há mapa não se vai). `slack` = metros de
## mar permitidos além da borda (o atlas afastado deixa o centro da tela entre os mapas).
static func clamp_to_land(a: Vector2, slack := 0.0) -> Vector2:
	for id in Regions.ORDER:
		if a.distance_to(atlas_center(id)) <= radius(id) + slack:
			return a
	var best := a
	var best_d := INF
	for id in Regions.ORDER:
		var c := atlas_center(id)
		var p := c + (a - c).limit_length(radius(id) + slack - 0.01)
		if p.distance_to(a) < best_d:
			best_d = p.distance_to(a)
			best = p
	return best


## Retângulo que contém todas as regiões.
static func atlas_bounds() -> Rect2:
	var r := atlas_rect(Regions.ORDER[0])
	for id in Regions.ORDER:
		r = r.merge(atlas_rect(id))
	return r


## Posição do mundo → ponto no atlas (pela região onde ela fica).
static func to_atlas(pos: Vector3) -> Vector2:
	var reg := Regions.region_at(pos)
	var o: Vector3 = Regions.origin(reg)
	return atlas_center(reg) + Vector2(pos.x - o.x, pos.z - o.z)


## Saídas da carruagem de uma região: [[região destino, liberada pelo rank]], na ordem dos mapas.
static func exits(region: String, rank: String) -> Array:
	var out: Array = []
	for id in Regions.ORDER:
		if id != region:
			out.append([id, Regions.unlocked(id, rank)])
	return out


## Zoom em volta de um ponto: novo centro (atlas) para que o ponto `anchor` do atlas, que está em
## `screen_off` pixels do meio do controle, continue embaixo do mouse com a escala `new_scale` (px/m).
static func zoom_center(anchor: Vector2, screen_off: Vector2, new_scale: float) -> Vector2:
	return anchor - screen_off / new_scale


## Jogadores que aparecem no mapa: no multiplayer, só os do meu grupo (e nunca eu, que tem a seta).
static func shown_players(peers: Array, party: Array, me: int) -> Array:
	var out: Array = []
	for p in peers:
		if p != me and p in party:
			out.append(p)
	return out


## Ângulo (rad) de uma direção no plano para desenhar no mapa (0 = norte/para cima, sentido horário).
static func heading(dir: Vector3) -> float:
	return atan2(dir.x, -dir.z)
