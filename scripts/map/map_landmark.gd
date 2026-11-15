@tool
class_name MapLandmark
extends Node3D
## Lugar com nome no mapa, lido por outros sistemas (acampamento, ruínas, arena, Horta, ninho, pomar, onde o
## jogador nasce, portal, carruagem da guilda, chegada da viagem). O código procura pelo `id`
## (MapData.landmark), então mover o nó no editor move o lugar no jogo todo.

## Nome do lugar: camp, ruins, arena, farm, nest, orchard, village_spawn, portal, coach, arrive...
@export var id := ""
## Assenta no relevo (a altura do nó vira distância até o chão).
@export var follow_ground := true
