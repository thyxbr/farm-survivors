class_name Password
extends RefCounted
## PBKDF2-HMAC-SHA256 (32 bytes de saída) e comparação em tempo constante.


static func new_salt() -> PackedByteArray:
	return Crypto.new().generate_random_bytes(16)


## Deriva a chave da senha (não se chama `hash` para não colidir com o hash() embutido).
static func derive(pass_: String, salt: PackedByteArray, iterations := 100000) -> PackedByteArray:
	var key := pass_.to_utf8_buffer()
	var block := salt.duplicate()
	block.append_array(PackedByteArray([0, 0, 0, 1]))  # índice do bloco 1 (32 bytes = 1 bloco)
	var ctx := HMACContext.new()
	ctx.start(HashingContext.HASH_SHA256, key)
	ctx.update(block)
	var u := ctx.finish()
	var out := u.duplicate()
	for i in range(1, iterations):
		ctx = HMACContext.new()
		ctx.start(HashingContext.HASH_SHA256, key)
		ctx.update(u)
		u = ctx.finish()
		for j in 32:
			out[j] ^= u[j]
	return out


## Compara em tempo constante (sem sair no primeiro byte diferente).
static func matches(pass_: String, salt: PackedByteArray, expected: PackedByteArray, iterations := 100000) -> bool:
	return constant_eq(derive(pass_, salt, iterations), expected)


static func constant_eq(a: PackedByteArray, b: PackedByteArray) -> bool:
	var diff := a.size() ^ b.size()
	for i in mini(a.size(), b.size()):
		diff |= a[i] ^ b[i]
	return diff == 0
