class_name EnemyGear
extends RefCounted
## Peças opcionais dos modelos de monstro (tools/blender/monsters.py): todo nó "Opt_<Nome>" é equipamento de
## variante. `gear` (de data/balance/enemies.json) diz quais ficam; o resto sai do modelo.
## Script puro (sem autoloads) para rodar no runner de testes unitários.

const PREFIX := "Opt_"


## Remove do modelo as peças opcionais que não estão em `gear` (nomes sem o prefixo).
## Devolve os nomes pedidos que o modelo não tem (vazio = tudo certo).
static func apply(model: Node, gear: Array) -> Array:
	var found := {}
	for n in _optional(model):
		var id := String(n.name).substr(PREFIX.length())
		if id in gear:
			found[id] = true
		else:
			n.get_parent().remove_child(n)
			n.free()
	var missing: Array = []
	for g in gear:
		if not found.has(g):
			missing.append(g)
	return missing


## Nomes (sem prefixo) de todas as peças opcionais do modelo.
static func names(model: Node) -> Array:
	var out: Array = []
	for n in _optional(model):
		out.append(String(n.name).substr(PREFIX.length()))
	return out


static func _optional(model: Node) -> Array:
	var out: Array = []
	var stack: Array = [model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if String(c.name).begins_with(PREFIX):
				out.append(c)   # peça dentro de peça não existe: não desce
			else:
				stack.append(c)
	return out
