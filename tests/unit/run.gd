extends SceneTree
## Executor dos testes unitários (regras puras, sem cena nem autoload):
##   godot --headless --path . -s tests/unit/run.gd
## Acha tests/unit/test_*.gd, instancia cada um e roda todo método test_*. Sai com 1 se algo falhar.
## Depois de criar um class_name novo rode `--import` uma vez para o cache de classes atualizar.

const DIR := "res://tests/unit"


func _init() -> void:
	var files: Array[String] = []
	for f in DirAccess.get_files_at(DIR):
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	var ran := 0
	var failed_tests := 0
	for f in files:
		var script: GDScript = load("%s/%s" % [DIR, f])
		if script == null or not script.can_instantiate():
			printerr("FALHA ao carregar ", f)
			failed_tests += 1
			continue
		var inst = script.new()
		var methods: Array[String] = []
		for m in script.get_script_method_list():
			if String(m.name).begins_with("test_"):
				methods.append(m.name)
		methods.sort()
		for m in methods:
			var before := T.failures.size()
			inst.call(m)
			ran += 1
			if T.failures.size() > before:
				failed_tests += 1
				printerr("FALHOU %s::%s" % [f, m])
				for i in range(before, T.failures.size()):
					printerr("    ", T.failures[i])
			else:
				print("ok     %s::%s" % [f, m])
	print("%d testes, %d falharam, %d verificações" % [ran, failed_tests, T.checks])
	quit(1 if failed_tests > 0 else 0)
