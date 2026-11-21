class_name EarthquakeDamage
extends Node3D
## Terremoto Devastador: o dano da onda de choque, separado do visual. EarthquakeAbilities cria um por ativação
## (só no cliente dono), no ponto do impacto, quando o EarthquakeSkill avisa que o escudo tocou o chão. A cada passo
## de física ele avança o mesmo relógio da onda visual (EarthquakeRules.wave_radius) e, entre os inimigos dentro da
## DamageArea (Area3D na camada dos inimigos, grupo "enemies": a mesma detecção do Martelo de Energia), emite `hit`
## para cada um que a frente da onda acabou de alcançar: só dentro do raio máximo, uma vez por ativação
## (EarthquakeRules.pick_reached). O herói e os aliados não estão nessa camada. Quem aplica o dano é
## EarthquakeAbilities (Enemy.take_damage: no multiplayer vira Network.client_hit_enemy). Se libera quando a onda
## termina de crescer.

signal hit(enemy: Node, center: Vector3)

const ENEMY_LAYER := 4
const SLACK := 0.15        ## a onda continua valendo um pouco depois de parar (s)

var config: EarthquakeConfig
var center := Vector3.ZERO
var t := 0.0
var wave_r := 0.0
var hit_count := 0
var _hit := {}
var _area: Area3D


func setup(cfg: EarthquakeConfig, c: Vector3) -> void:
	config = cfg
	center = c


func _ready() -> void:
	global_position = center
	_area = Area3D.new()
	_area.name = "DamageArea"
	_area.collision_layer = 0
	_area.collision_mask = ENEMY_LAYER
	_area.monitorable = false
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = config.radius + 1.5   # folga para o corpo dos inimigos na borda (o filtro exato é o de pick_reached)
	cyl.height = 10.0
	cs.shape = cyl
	_area.add_child(cs)
	add_child(_area)


func _physics_process(delta: float) -> void:
	t += delta
	wave_r = EarthquakeRules.wave_radius(t, config.radius, config.expansion_speed)
	var cands := []
	for b in _area.get_overlapping_bodies():
		if not b.is_in_group("enemies") or bool(b.get("dead")):
			continue
		cands.append({"id": b.get_instance_id(), "pos": b.global_position, "radius": float(b.get("radius")), "node": b})
	for x in EarthquakeRules.pick_reached(cands, center, wave_r, config.radius, _hit):
		hit_count += 1
		hit.emit(x.node, center)
	if t >= config.expansion_time() + SLACK:
		queue_free()
