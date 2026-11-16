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
