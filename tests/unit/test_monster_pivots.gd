extends RefCounted
## Cada modelo de monstro tem os pivôs que o enemy.gd anima.

const SPIDER := ["Body", "Abdomen", "Head", "Leg0L", "Leg1L", "Leg2L", "Leg3L", "Leg0R", "Leg1R", "Leg2R", "Leg3R"]
const REQUIRED := {
	"spider": SPIDER,
	"centipede": SPIDER,
}


func test_models_have_pivots() -> void:
	for m in REQUIRED:
		var path := "res://assets/models/%s.glb" % m
		T.ok(ResourceLoader.exists(path), "%s existe" % path)
		if not ResourceLoader.exists(path):
			continue
		var root: Node = (load(path) as PackedScene).instantiate()
		var missing: Array = []
		for p in REQUIRED[m]:
			if root.find_child(p, true, false) == null:
				missing.append(p)
		T.eq(missing, [], "%s: pivôs" % m)
		root.free()
