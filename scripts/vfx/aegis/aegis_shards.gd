class_name AegisShards
extends CPUParticles3D
## Égide Cristalina: fragmentos cristalinos da quebra (prefab scenes/vfx/aegis/aegis_shards.tscn).
## Rajada única saindo de pontos com direção (os centros das placas e a normal de cada uma): cada fragmento
## voa para fora, gira, cai devagar e some. Também serve para lascas de uma placa só (chip()).
## Libera a si mesmo quando a última partícula acaba.

@export var per_point := 4          ## fragmentos por ponto na quebra
@export var velocity_scale := 1.0


## Quebra inteira: `points` e `normals` no espaço global. `intensity` = AegisConfig.shard_intensity.
func burst(points: PackedVector3Array, normals: PackedVector3Array, intensity := 1.0, life := 1.3) -> void:
	_fire(points, normals, maxi(4, int(round(points.size() * per_point * intensity))), intensity, life)


## Lascas de uma placa rachada (poucas, lentas).
func chip(point: Vector3, normal: Vector3, count := 3) -> void:
	_fire(PackedVector3Array([point]), PackedVector3Array([normal]), count, 0.45, 0.7)


func _fire(points: PackedVector3Array, normals: PackedVector3Array, count: int, intensity: float, life: float) -> void:
	# os pontos vão no espaço local do emissor: ele fica parado na origem do mundo do pai
	var local := PackedVector3Array()
	var lnorm := PackedVector3Array()
	var inv := global_transform.affine_inverse()
	for i in points.size():
		local.append(inv * points[i])
		lnorm.append((inv.basis * normals[i]).normalized())
	emission_shape = CPUParticles3D.EMISSION_SHAPE_DIRECTED_POINTS
	emission_points = local
	emission_normals = lnorm
	amount = count
	lifetime = life
	initial_velocity_min *= velocity_scale * lerpf(0.6, 1.0, clampf(intensity, 0.0, 1.0))
	initial_velocity_max *= velocity_scale * maxf(intensity, 0.3)
	one_shot = true
	emitting = true
	finished.connect(queue_free)
	# garante a limpeza mesmo se o finished não vier (nó fora da árvore no meio)
	get_tree().create_timer(life + 0.6, false).timeout.connect(func() -> void:
		if is_instance_valid(self):
			queue_free())
