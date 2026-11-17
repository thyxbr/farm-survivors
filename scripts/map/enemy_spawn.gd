@tool
class_name EnemySpawn
extends Node3D
## Ponto de nascimento de monstros. O servidor (ou o solo) cria `count` monstros do tipo `kind`, espalhados no
## raio (spread), e cada um volta `respawn` segundos depois de morrer. Os números do monstro (vida, dano, loot)
## vêm do data/balance/enemies.json. `boss`: só nasce quando a missão chama (o rei goblin).

## Tipo do monstro (chave do enemies.json).
@export var kind := "slime":
	set(v):
		kind = v
		if Engine.is_editor_hint() and is_inside_tree():
			build_preview(_height)
## Quantos monstros este ponto mantém.
@export_range(0, 50) var count := 1:
	set(v):
		count = v
		if Engine.is_editor_hint() and is_inside_tree():
			build_preview(_height)
## Raio (m) em volta do ponto onde eles nascem; 0 = todos no centro.
@export_range(0.0, 40.0, 0.1) var radius := 0.0:
	set(v):
		radius = v
		if Engine.is_editor_hint() and is_inside_tree():
			build_preview(_height)
## Segundos até um monstro morto voltar.
@export_range(1.0, 3600.0, 1.0) var respawn := 30.0
## Bicho da noite: só aparece depois de escurecer e vai embora de dia (as Asas-de-couro).
@export var night_only := false
## Só nasce pela missão (o chefe).
@export var boss := false:
	set(v):
		boss = v
		if Engine.is_editor_hint() and is_inside_tree():
			build_preview(_height)
## Assenta no relevo (a altura do nó vira distância até o chão).
@export var follow_ground := true
## Nível dos monstros. 0 = a faixa da região com nome (MapRegion + data/balance/regions.json) onde o ponto
## fica; fora de região, o nível de referência do monstro (números de hoje, como na Horda). Com `level_max` >
## `level`, cada um sorteia o nível na faixa ao nascer.
@export_range(0, 60) var level := 0
## Fim da faixa de nível (0 = nível fixo em `level`).
@export_range(0, 60) var level_max := 0
## Elite: alguns níveis a mais, mais vida e maior (data/balance/progression.json, "elite").
@export var elite := false
## Chefe da dungeon: barra de chefe, volta em minutos e o loot de chefe da dungeon (progression.json "dungeons").
@export var chief := false

const GOLDEN := 2.399963229728653   # ângulo áureo (rad)


## Onde nasce cada um dos `count` monstros: o primeiro no centro e os outros numa espiral de ângulo áureo até
## o raio (espalha por igual e dá sempre o mesmo resultado, então servidor, solo e testes concordam).
static func spread(center: Vector3, count: int, radius: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in maxi(count, 0):
		if i == 0 or radius <= 0.0:
			out.append(center)
			continue
		var r := radius * sqrt(float(i) / float(count - 1))
		var a := i * GOLDEN
		out.append(center + Vector3(cos(a) * r, 0.0, sin(a) * r))
	return out

## Como spread(), mas cada ponto assentado no chão (`height`, coordenadas do mapa) com a mesma distância
## (`offset`) do centro: numa encosta os monstros não nascem dentro do morro. Sem chão: y = offset.
static func spread_on_ground(center: Vector3, count: int, radius: float, offset: float, height: Callable) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in spread(center, count, radius):
		p.y = MapPreview.ground_y(true, offset, height, p.x, p.z)
		out.append(p)
	return out


const SPAWN_COLOR := Color(1.0, 0.25, 0.2)

var _height := Callable()


func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_transform(true)
	if Engine.is_editor_hint():
		build_preview(_height)


## Disco do raio, um boneco vermelho onde nasce cada monstro e o rótulo "tipo ×quantidade".
func build_preview(height: Callable = Callable()) -> void:
	_height = height
	var p := MapPreview.fresh(self)
	if radius > 0.0:
		MapPreview.disc(p, radius, Color(SPAWN_COLOR, 0.15), 0.08)
	for at in spread(Vector3.ZERO, count, radius):
		MapPreview.dummy(p, at, "", SPAWN_COLOR, 1.0)
	MapPreview.label(p, Vector3(0, 2.0, 0), "%s ×%d%s" % [kind, count, " (chefe)" if boss else ""])
	MapPreview.seat(self, p, follow_ground, height)

## No editor: mover o nó reassenta a prévia no relevo.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		build_preview(_height)
