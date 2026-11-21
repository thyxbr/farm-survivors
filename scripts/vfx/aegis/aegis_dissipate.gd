class_name AegisDissipate
extends CPUParticles3D
## Égide Cristalina: partículas de dissipação (prefab scenes/vfx/aegis/aegis_dissipate.tscn).
## Faíscas azuis, cianas e douradas que se espalham devagar, sobem um pouco e apagam. Rajada única dentro
## de uma esfera (o volume do escudo); libera a si mesmo no fim.


## `radius`/`height` = tamanho do escudo; `intensity` multiplica a quantidade; `time` = vida das faíscas.
func burst(radius: float, height: float, intensity := 1.0, time := 1.3) -> void:
	emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	emission_box_extents = Vector3(radius, height * 0.5, radius)
	position.y += height * 0.5
	amount = maxi(4, int(round(amount * intensity)))
	lifetime = time
	one_shot = true
	emitting = true
	finished.connect(queue_free)
	get_tree().create_timer(time + 0.6, false).timeout.connect(func() -> void:
		if is_instance_valid(self):
			queue_free())
