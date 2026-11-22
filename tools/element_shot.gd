extends Node3D
## Foto do retorno das afinidades elementais no número de dano (ElementRules): monstros de verdade lado a lado,
## cada um levando um golpe de um elemento por Enemy.take_damage (o mesmo caminho do jogo), com a câmera do jogo.
##   godot --path . --resolution 1280x720 res://tools/element_shot.tscn -- --out=elementos.png
## Padrão: Slime Veloz com fogo (Fraco!), Slime Explosivo com fogo (Imune) e Esqueleto Cavaleiro com golpe
## físico (Resistiu). `--hits=tipo:elemento,...` troca a fileira.

var out := "element_shot.png"
var hits := [["slime_veloz", "fogo"], ["slime_explosivo", "fogo"], ["esqueleto_cavaleiro", "fisico"]]
var enemies: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--hits="):
			hits = []
			for h in a.substr(7).split(","):
				var p := h.split(":")
				hits.append([p[0], p[1] if p.size() > 1 else "fisico"])
	WorldLighting.build(self)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.42, 0.6, 0.3)
	floor_mi.material_override = fm
	add_child(floor_mi)
	for i in hits.size():
		var e := Enemy.new()
		e.kind = hits[i][0]
		add_child(e)
		e.set_physics_process(false)
		e.set_process(false)
		e.position = Vector3((i - (hits.size() - 1) * 0.5) * 3.2, 0, 0)
		e.model.rotation.y = 0.0
		enemies.append(e)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 60.0
	cam.look_at_from_position(Vector3(0, 4.2, 8.5), Vector3(0, 1.2, 0))
	cam.current = true
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(0.6).timeout
	for i in enemies.size():
		var e: Enemy = enemies[i]
		e.take_damage(16.0, e.global_position + Vector3(0, 0, 3), false, 0.0, 0.0, 0.0, hits[i][1])
		print("%s com %s: x%.2f (%s)" % [e.kind, hits[i][1], e.element_mult(hits[i][1]),
			ElementRules.hint(e.element_mult(hits[i][1]))])
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
