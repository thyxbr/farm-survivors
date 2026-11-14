class_name T
extends RefCounted
## Asserções mínimas dos testes unitários. Cada falha é registrada (não interrompe o teste)
## e o executor (run.gd) lê `failures` no fim para decidir o código de saída.

static var failures: Array[String] = []
static var checks := 0


static func eq(a, b, msg := "") -> void:
	checks += 1
	if a != b:
		failures.append("%s esperado %s, veio %s" % [msg if msg != "" else "eq:", var_to_str(b), var_to_str(a)])


static func ok(cond: bool, msg := "") -> void:
	checks += 1
	if not cond:
		failures.append(msg if msg != "" else "ok: condição falsa")
