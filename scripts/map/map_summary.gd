class_name MapSummary
extends RefCounted
## Retrato do conteúdo de um mundo montado, para provar que a conversão para cenas não mudou o jogo. Cada linha
## é "chave;n1;n2;..." (chave = o que é; números = onde está e como). compare() casa as linhas por chave e
## aceita números iguais dentro da tolerância; a ordem não importa. A coleta fica em WorldSummary (lado do jogo).

const TOL := 0.011


static func _split(line: String) -> Array:
	var parts := line.split(";")
	var nums: Array[float] = []
	for i in range(1, parts.size()):
		nums.append(float(parts[i]))
	return [parts[0], nums]


static func _close(a: Array[float], b: Array[float], tol: float) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if absf(a[i] - b[i]) > tol:
			return false
	return true


## Diferenças entre o retrato antigo (`base`) e o novo (`cur`): "falta: <linha>" (está em base e não em cur) e
## "sobra: <linha>" (está em cur e não em base). Vazio = mesmo conteúdo.
static func compare(base: PackedStringArray, cur: PackedStringArray, tol := TOL) -> PackedStringArray:
	var pool := {}   # chave -> [[linha, números]] ainda não casados do novo
	for line in cur:
		var s := _split(line)
		if not pool.has(s[0]):
			pool[s[0]] = []
		pool[s[0]].append([line, s[1]])
	var out := PackedStringArray()
	for line in base:
		var s := _split(line)
		var cands: Array = pool.get(s[0], [])
		var hit := -1
		for i in cands.size():
			if _close(s[1], cands[i][1], tol):
				hit = i
				break
		if hit < 0:
			out.append("falta: " + line)
		else:
			cands.remove_at(hit)
	for k in pool:
		for c in pool[k]:
			out.append("sobra: " + c[0])
	return out


## Número com 3 casas, sem "-0.000".
static func num(v: float) -> String:
	var s := "%.3f" % v
	return "0.000" if s == "-0.000" else s


static func vec(v: Vector3) -> String:
	return "%s;%s;%s" % [num(v.x), num(v.y), num(v.z)]
