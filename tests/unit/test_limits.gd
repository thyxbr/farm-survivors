extends RefCounted
## Limitadores puros: fila de derivação do AuthHttp, balde de fichas do Econ e checagem de volume montado.

const MOUNTS := "overlay / overlay rw,relatime,lowerdir=/var/lib/docker/overlay2/l/ABC,upperdir=/x,workdir=/y 0 0\n" \
	+ "proc /proc proc rw,nosuid,nodev,noexec,relatime 0 0\n" \
	+ "tmpfs /dev tmpfs rw,nosuid,size=65536k,mode=755 0 0\n" \
	+ "/dev/sda1 /data ext4 rw,relatime 0 0\n" \
	+ "/dev/sda1 /etc/hosts ext4 rw,relatime 0 0\n" \
	+ "/dev/sdb1 /mnt/meus\\040dados ext4 rw,relatime 0 0\n"


func test_derive_queue_never_runs_more_than_max() -> void:
	var q := DeriveQueue.new(2, 5)
	for i in 5:
		T.ok(q.push(i), "entra na fila %d" % i)
	T.ok(not q.push(99), "fila cheia recusa")
	T.eq(q.take_startable(), [0, 1], "começam só 2, na ordem")
	T.eq(q.take_startable(), [], "com 2 rodando nenhuma outra começa")
	T.eq(q.running, 2, "2 em andamento")
	q.finished()
	T.eq(q.take_startable(), [2], "terminou uma, começa uma")
	q.finished()
	q.finished()
	T.eq(q.take_startable(), [3, 4], "duas vagas, duas começam")
	T.eq(q.waiting(), 0, "fila vazia")
	q.finished()
	q.finished()
	q.finished()   # uma a mais: não fica negativo
	T.eq(q.running, 0, "nada rodando")


func test_derive_queue_simulated_flood() -> void:
	# 20 pedidos de uma vez (o curl em laço), cada derivação leva 3 ticks: em nenhum tick rodam mais de 2
	var q := DeriveQueue.new()   # mesmos limites do AuthHttp
	for i in 20:
		T.ok(q.push(i), "cabe na fila %d" % i)
	var running := []   # [ticks restantes]
	var peak := 0
	var done := 0
	for tick in 100:
		for r in running.duplicate():
			r[0] -= 1
			if r[0] <= 0:
				running.erase(r)
				q.finished()
				done += 1
		for _item in q.take_startable():
			running.append([3])
		peak = maxi(peak, running.size())
	T.eq(done, 20, "todos terminam")
	T.eq(peak, DeriveQueue.MAX_RUNNING, "pico de %d derivações ao mesmo tempo" % DeriveQueue.MAX_RUNNING)
	T.ok(DeriveQueue.MAX_RUNNING <= 2, "no máximo 2 derivações em paralelo")


func test_token_bucket_burst_and_refill() -> void:
	var b := TokenBuckets.new(10.0, 5.0)
	var t := 100.0
	var ok := 0
	for i in 15:
		if b.allow(7, t):
			ok += 1
	T.eq(ok, 10, "rajada de 10")
	T.ok(not b.allow(7, t), "sem ficha recusa")
	T.ok(b.allow(8, t), "outro peer tem balde próprio")
	t += 0.2
	T.ok(b.allow(7, t), "0,2 s depois volta 1 ficha (5/s)")
	T.ok(not b.allow(7, t), "e só uma")
	t += 10.0
	ok = 0
	for i in 15:
		if b.allow(7, t):
			ok += 1
	T.eq(ok, 10, "parado muito tempo não passa da rajada")
	b.forget(7)
	b.forget(8)
	T.eq(b.size(), 0, "esquece os peers que saíram")


func test_token_bucket_steady_rate() -> void:
	var b := TokenBuckets.new(10.0, 5.0)
	var ok := 0
	# 20 pedidos por segundo durante 10 s: passam a rajada + ~5/s
	for i in 200:
		if b.allow(1, i * 0.05):
			ok += 1
	T.ok(ok >= 58 and ok <= 61, "rajada + 5/s em 10 s (%d)" % ok)


func test_is_mount_point() -> void:
	T.ok(Mounts.is_mount_point("/data", MOUNTS), "/data montado")
	T.ok(Mounts.is_mount_point("/data/", MOUNTS), "barra no fim não importa")
	T.ok(not Mounts.is_mount_point("/data/sub", MOUNTS), "subpasta não é o ponto de montagem")
	T.ok(not Mounts.is_mount_point("/dat", MOUNTS), "prefixo não conta")
	T.ok(not Mounts.is_mount_point("/game", MOUNTS), "pasta da camada do container não é montagem")
	T.ok(Mounts.is_mount_point("/", MOUNTS), "raiz (overlay) é montagem")
	T.ok(Mounts.is_mount_point("/mnt/meus dados", MOUNTS), "espaço escapado em octal")
	T.ok(not Mounts.is_mount_point("/data", ""), "sem /proc/mounts: não montado")
	T.ok(not Mounts.is_mount_point("", MOUNTS), "pasta vazia: não")
	T.ok(not Mounts.is_mount_point("/data", MOUNTS.replace("/dev/sda1 /data ", "/dev/sda1 /dados ")), "sem a linha do /data")
	T.ok(Mounts.is_mount_point("/data", MOUNTS.replace("\n", "\r\n")), "tolera CRLF")
