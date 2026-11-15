@tool
class_name MapEntity
extends Node3D
## Algo do mapa que tem script de jogo: NPC, ponto da antiga praça, canteiro da Horta, cozinha, ponto da
## história, presente ou porta do Natal, portal da Horda, poste de direção, Papai Noel, nó de coleta. No jogo o
## mundo cria o nó certo pelo `kind` (world.gd, make_entity); aqui ficam só os dados, sem autoload.

## Tipo: elder, merchant, alchemist, blacksmith, rival, npc, story_point, hub_point, farm_plot, kitchen,
## portal, signpost, santa, xmas_gift, xmas_door, resource_node.
@export var kind := "npc"
## Referência do tipo: id do NPC ou do ponto da história, building_id do ponto da praça, tipo do veio
## (iron/crystal) do nó de coleta.
@export var ref := ""
## Índice (canteiro 0..11, presente 0..7, porta 0..5); -1 quando não se aplica.
@export var index := -1
## Número fixo do nó de coleta (o mesmo que o save e a rede usam); -1 quando não é nó de coleta.
@export var node_id := -1
## Parâmetros extras do tipo (ex.: destinos do poste de direção).
@export var params := {}
## Assenta no relevo (a altura do nó vira distância até o chão).
@export var follow_ground := true
