class_name WorldResourceNode
extends ColonyResourceNode
## Veio de ferro ou cristal arcano de Valdoria (materiais do encantamento). Reaproveita o nó de recurso
## da Defesa da Cidade (modelo, tremida, queda e volta), mas sem a ColonyNature: cada jogador tem os
## seus veios, como o saque pessoal. Os golpes são contados aqui; no último o nó some e pede a coleta
## ao Econ (solo: concede na hora; online: o servidor confere distância e tempo de volta, ver WorldHarvest).

## Id do nó em world_nodes.json (a posição na lista "nodes").
var node_id := 0
## Golpes para quebrar e segundos para voltar (da tabela).
var hits := 5
var respawn := 180.0


## Monta o nó a partir de WorldHarvest.node_def().
static func from_def(def: Dictionary) -> WorldResourceNode:
	var n := WorldResourceNode.new()
	n.node_id = int(def.id)
	n.id = int(def.id)
	n.kind = str(def.model)          # "iron" ou "crystal": escolhe o visual do nó da cidade
	n.model = "rock"
	n.radius = 0.75
	n.size = 1.1
	n.yaw = float(def.id) * 1.7
	n.hits = int(def.hits)
	n.respawn = float(def.respawn)
	n.position = def.pos
	return n


func data() -> Dictionary:
	return {"total": 1, "hits": hits}


func hit(from: Vector3) -> void:
	if not alive:
		return
	hits_left -= 1
	_shake(from)
	if hits_left > 0:
		return
	set_alive(false)
	Econ.gather_node(node_id, from)
	get_tree().create_timer(respawn).timeout.connect(_restore)


func _restore() -> void:
	if is_inside_tree():
		set_alive(true)
