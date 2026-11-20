class_name BookLayout
extends RefCounted
## Medidas do livro da interface (assets/ui/book.png) e a regra "cabe na página".
## Script puro: não cita autoload, para rodar no executor unitário.

## Tamanho da imagem do livro aberto.
const SIZE := Vector2(1408, 800)
## Margem das páginas até a borda do livro: lados, e cima/baixo.
const SIDE := 88.0
const TOP := 62.0
## Vão entre as duas páginas (a lombada).
const SPINE := 84.0
## Vão entre as duas colunas de uma janela lateral (BookWindow).
const COL_GAP := 28.0
## Folga mínima entre o livro e a borda da janela, e a menor escala aceita.
const SCREEN_GAP := 16.0
const MIN_SCALE := 0.25


## Área das duas páginas juntas (o que uma tela inteira pode ocupar).
static func content_room() -> Vector2:
	return SIZE - Vector2(SIDE * 2.0, TOP * 2.0)


## Área de uma página só.
static func page_room() -> Vector2:
	var room := content_room()
	return Vector2((room.x - SPINE) * 0.5, room.y)


static func fits(need: Vector2) -> bool:
	var room := content_room()
	return need.x <= room.x and need.y <= room.y


## Escala do livro para caber inteiro na janela; nunca amplia.
static func scale_for(viewport: Vector2) -> float:
	var free := viewport - Vector2(SCREEN_GAP, SCREEN_GAP) * 2.0
	return clampf(minf(free.x / SIZE.x, free.y / SIZE.y), MIN_SCALE, 1.0)
