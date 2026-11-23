extends RefCounted
## EnemyGear: peças opcionais (Opt_<Nome>) dos modelos de monstro e o "gear" de data/balance/enemies.json.

const MODELS := {
	"goblin": "res://assets/models/goblin.glb",
	"skeleton": "res://assets/models/skeleton.glb",
	"brejeiro": "res://assets/models/brejeiro_ia.glb",   # malha da IA com as armas por código (Opt_*)
}
const PIVOTS := ["LegL", "LegR", "Body", "Head", "ArmL", "ArmR"]


func _fake() -> Node3D:
	var m := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	m.add_child(body)
	for n in ["Opt_A", "Opt_B", "Fixo"]:
		var c := Node3D.new()
		c.name = n
		body.add_child(c)
	return m


func test_keeps_only_listed() -> void:
	var m := _fake()
	T.eq(EnemyGear.apply(m, ["A"]), [], "nada faltando")
	T.ok(m.find_child("Opt_A", true, false) != null, "Opt_A fica")
	T.ok(m.find_child("Opt_B", true, false) == null, "Opt_B sai")
	T.ok(m.find_child("Fixo", true, false) != null, "peça fixa fica")
	m.free()


func test_missing_is_reported() -> void:
	var m := _fake()
	T.eq(EnemyGear.apply(m, ["X", "B"]), ["X"], "nome inexistente é devolvido")
	T.ok(m.find_child("Opt_B", true, false) != null, "o que existe continua")
	m.free()


func test_empty_gear_strips_all() -> void:
	var m := _fake()
	T.eq(EnemyGear.apply(m, []), [], "lista vazia não falta nada")
	T.eq(EnemyGear.names(m), [], "nenhuma peça opcional sobra")
	T.ok(m.find_child("Fixo", true, false) != null, "peça fixa fica")
	m.free()


func test_model_without_optional_parts() -> void:
	var m := Node3D.new()
	T.eq(EnemyGear.apply(m, []), [], "modelo sem peças (slime) passa direto")
	m.free()


## Todo tipo humanoide lista "gear", e cada peça existe no modelo dele. Os pivôs que o jogo anima também.
func test_every_enemy_gear_exists_in_model() -> void:
	var enemies: Dictionary = BalanceTables.load_dir("res://data/balance").get_table("enemies")
	var have := {}
	for id in MODELS:
		var inst: Node = (load(MODELS[id]) as PackedScene).instantiate()
		have[id] = EnemyGear.names(inst)
		for p in PIVOTS:
			T.ok(inst.find_child(p, true, false) != null, "%s tem o pivô %s" % [id, p])
		inst.free()
	var used := {}
	for kind in enemies:
		var d: Dictionary = enemies[kind]
		if not MODELS.has(d.model):
			T.ok(not d.has("gear"), "%s (modelo %s) não usa gear" % [kind, d.model])
			continue
		T.ok(d.has("gear"), "%s lista gear" % kind)
		for g in d.get("gear", []):
			T.ok(g in have[d.model], "%s: peça %s existe em %s.glb" % [kind, g, d.model])
			used["%s/%s" % [d.model, g]] = true
	for id in have:
		for g in have[id]:
			T.ok(used.has("%s/%s" % [id, g]), "peça %s de %s.glb é usada por algum tipo" % [g, id])


func test_new_kinds_present() -> void:
	var enemies: Dictionary = BalanceTables.load_dir("res://data/balance").get_table("enemies")
	for k in ["esqueleto", "esqueleto_arqueiro", "esqueleto_mago", "esqueleto_cavaleiro", "goblin_bombardeiro", "slime_gelo", "kobold"]:
		T.ok(enemies.has(k), "tipo %s existe" % k)
	T.ok(enemies.get("kobold", {}).get("ai", "") != "bomber", "kobold arremessa, não explode junto")
	T.ok(enemies.get("kobold", {}).has("throw_cd") and enemies.get("kobold", {}).has("throw_range"), "kobold tem arremesso")
	T.ok(enemies.get("centopeia", {}).get("chill_venom", false), "a lentidão da centopeia é veneno (aviso próprio)")
	T.ok(not enemies["slime_gelo"].get("chill_venom", false), "a do slime de gelo continua sendo frio")
	var mole: Dictionary = enemies.get("toupeira", {})
	T.eq(mole.get("ai", ""), "burrow", "toupeira cava")
	for key in ["dig_min", "dig_max", "surface_secs", "dig_max_secs", "dig_speed", "emerge_radius"]:
		T.ok(mole.has(key), "toupeira tem %s" % key)
	var worm: Dictionary = enemies.get("mae_verme", {})
	T.ok(worm.get("boss", false) and worm.get("ai", "") == "worm", "mãe-verme é chefe com ia de verme")
	T.eq(worm.get("summon", ""), "lobo_geada", "mãe-verme da Geleira chama Lobos da Geada")
	T.eq(worm.get("shot", ""), "acid", "mãe-verme cospe ácido")
	T.eq(worm.get("leash", []).size(), 2, "mãe-verme presa ao fosso (meio-tamanho x, z)")
	var golem: Dictionary = enemies.get("golem_cristal", {})
	T.eq(golem.get("model", ""), "golem", "golem usa o modelo novo")
	T.ok(float(golem.get("death_blast", 0.0)) > 0.0 and float(golem.get("death_delay", 0.0)) > 0.0, "golem estoura ao morrer")
	T.eq(enemies["esqueleto_mago"].get("shot", ""), "bolt", "mago atira projétil mágico")
	T.eq(enemies["goblin_bombardeiro"].get("ai", ""), "bomber", "bombardeiro explode")
	T.eq(float(enemies["slime_gelo"].get("chill", 0.0)), 2.5, "slime de gelo deixa lento por 2,5 s")
	T.ok(enemies["esqueleto_cavaleiro"].get("elite", false), "cavaleiro é elite")
	var items: Dictionary = BalanceTables.load_dir("res://data/balance").get_table("items")
	T.ok(items.has("bone_shard"), "item bone_shard existe")
	for kind in enemies:
		for l in enemies[kind].loot:
			T.ok(items.has(l[0]), "%s: item %s do loot existe" % [kind, l[0]])
