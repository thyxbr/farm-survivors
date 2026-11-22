class_name SeismicSpikesDamage
extends Node3D
## Estacas Sísmicas: o dano do tremor, separado do visual. SeismicSpikesAbilities cria um por ativação (só no cliente
## dono), no ponto do golpe, quando o SeismicSpikesAoE avisa `quake_started`. Uma Area3D cilíndrica na camada dos inimigos
## (grupo "enemies", a mesma detecção do Terremoto) acha os candidatos com get_overlapping_bodies(); a cada passo de
## física a frente do tremor cresce do centro até o raio (SeismicSpikesRules.quake_front, o mesmo relógio do
## terremoto) e `hit` sai para cada inimigo que ela acabou de alcançar: dentro do raio, uma vez por
## ativação (SeismicSpikesRules.pick_reached). O herói e os aliados não estão nessa camada. Quem aplica o dano é
## SeismicSpikesAbilities (Enemy.take_damage: no multiplayer vira Network.client_hit_enemy). Libera-se no fim.

signal hit(enemy: Node, center: Vector3)

const ENEMY_LAYER := 4
const SLACK := 0.15        ## o tremor continua valendo um pouco depois de chegar à borda (s)

var config: SeismicSpikesConfig
var center := Vector3.ZERO
var t := 0.0
var front := 0.0
var hit_count := 0
var _hit := {}
var _area: Area3D


func setup(cfg: SeismicSpikesConfig, c: Vector3) -> void:
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
	cyl.radius = config.radius + 1.5   # folga para o corpo de quem está na borda (o filtro exato é o de pick_reached)
	cyl.height = 10.0
	cs.shape = cyl
	_area.add_child(cs)
	add_child(_area)


func _physics_process(delta: float) -> void:
	t += delta
	front = SeismicSpikesRules.quake_front(t, config.radius, config.quake_propagate)
	var cands := []
	for b in _area.get_overlapping_bodies():
		if not b.is_in_group("enemies") or bool(b.get("dead")):
			continue
		cands.append({"id": b.get_instance_id(), "pos": b.global_position, "radius": float(b.get("radius")), "node": b})
	for x in SeismicSpikesRules.pick_reached(cands, center, front, config.radius, _hit):
		hit_count += 1
		hit.emit(x.node, center)
	if t >= config.quake_propagate + SLACK:
		queue_free()
