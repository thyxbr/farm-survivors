extends SceneTree
## Regrava no snapshot do teste de balanceamento (tests/unit/fixtures/balance_snapshot.bin) as tabelas
## que foram retocadas DE PROPÓSITO nos JSON de data/balance. Depois da migração as tabelas moram nos
## JSON (tools/export_balance.gd foi de uso único, das antigas `const` para os JSON); este é o caminho
## inverso, só para as tabelas pedidas, e as demais ficam como estavam no snapshot.
##   godot --headless --path . -s tools/balance_snapshot.gd -- colony
## Sem nome nenhum, não grava nada (para não apagar sem querer a referência de todas as tabelas).

const DIR := "res://data/balance"
const SNAPSHOT := "res://tests/unit/fixtures/balance_snapshot.bin"


func _init() -> void:
	var names := OS.get_cmdline_user_args()
	if names.is_empty():
		push_error("diga quais tabelas regravar, ex.: -- colony")
		quit(1)
		return
	var f := FileAccess.open(SNAPSHOT, FileAccess.READ)
	var snap: Dictionary = bytes_to_var(f.get_buffer(f.get_length()))
	f.close()
	var t := BalanceTables.load_dir(DIR)
	for n in names:
		if not n in BalanceTables.NAMES:
			push_error("tabela desconhecida: %s" % n)
			quit(1)
			return
		snap[n] = t.get_table(n)
	var out := FileAccess.open(SNAPSHOT, FileAccess.WRITE)
	out.store_buffer(var_to_bytes(snap))
	out.close()
	print("snapshot regravado: %s" % ", ".join(names))
	quit(0)
