extends SceneTree
## Executor dos testes unitários (regras puras, sem cena nem autoload):
##   godot --headless --path . -s tests/unit/run.gd
## Acha tests/unit/test_*.gd, instancia cada um e roda todo método test_*. Sai com 1 se algo falhar.
## Depois de criar um class_name novo rode `--import` uma vez para o cache de classes atualizar.
## Erro de script durante um teste (acesso a nulo, método inexistente...) aborta só aquele método
## e o Godot segue; por isso um Logger conta os SCRIPT ERROR e o teste que causou algum FALHA.
## push_error de propósito (entrada malformada, SQL recusado) não conta: é ERROR comum, não de script.

const DIR := "res://tests/unit"


## Conta os erros de script (ERROR_TYPE_SCRIPT). O Logger pode ser chamado de outra thread.
class ScriptErrors extends Logger:
	var count := 0
	var last := ""
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_mutex.lock()
		count += 1
		last = "%s (%s:%d %s)" % [rationale if rationale != "" else code, file, line, function]
		_mutex.unlock()


func _init() -> void:
	var errors := ScriptErrors.new()
	OS.add_logger(errors)
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
			var errs_before := errors.count
			inst.call(m)
			ran += 1
			if errors.count > errs_before:
				T.failures.append("erro de script durante o teste: %s" % errors.last)
			if T.failures.size() > before:
				failed_tests += 1
				printerr("FALHOU %s::%s" % [f, m])
				for i in range(before, T.failures.size()):
					printerr("    ", T.failures[i])
			else:
				print("ok     %s::%s" % [f, m])
	print("%d testes, %d falharam, %d verificações" % [ran, failed_tests, T.checks])
	OS.remove_logger(errors)
	quit(1 if failed_tests > 0 else 0)
