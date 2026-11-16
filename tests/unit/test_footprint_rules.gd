extends RefCounted
## FootprintRules: onde cada pé pisa e quanto a pegada dura com o chão de cada jeito.


func test_feet_sit_on_each_side_of_the_path() -> void:
	var pos := Vector3(3, 0, 5)
	var l := FootprintRules.foot_pos(pos, Vector2(0, 2), -1)
	var r := FootprintRules.foot_pos(pos, Vector2(0, 2), 1)
	T.ok(absf(l.distance_to(r) - (FootprintRules.GAUGE * 2.0)) < 0.001, "os pés ficam a 2 × GAUGE")
	T.ok(absf(l.z - (5.0)) < 0.001, "andando em z, o pé só sai para o lado")
	T.ok(absf(r.x - pos.x - (-(l.x - pos.x))) < 0.001, "um de cada lado")
	T.eq(FootprintRules.foot_pos(pos, Vector2.ZERO, 1).is_finite(), true, "parado não dá NaN")


func test_yaw_points_along_the_walk() -> void:
	for dir in [Vector2(1, 0), Vector2(0, -1), Vector2(-0.6, 0.8)]:
		var b := Basis(Vector3.UP, FootprintRules.yaw_of(dir))
		var fwd := b * Vector3(0, 0, 1)
		T.ok(absf(Vector2(fwd.x, fwd.z).dot(dir.normalized()) - (1.0)) < 0.001, "a ponta do pé vai para %s" % dir)


func test_snow_keeps_prints_longest_and_falling_snow_fills_them() -> void:
	var dry := FootprintRules.life(0.0, 0.0, 0.0)
	var mud := FootprintRules.life(0.0, 0.0, 1.0)
	var snow := FootprintRules.life(1.0, 0.0, 0.0)
	var snowing := FootprintRules.life(1.0, 1.0, 0.0)
	T.ok(dry < mud and mud < snow, "seco < lama < neve (%.0f, %.0f, %.0f)" % [dry, mud, snow])
	T.ok(snowing < snow, "neve caindo enche a pegada mais rápido")
