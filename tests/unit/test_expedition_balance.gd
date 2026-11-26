extends RefCounted
## Balanceamento inicial da expedição (ExpeditionBalance + "level"/"balance" do ExpeditionDefs).
##
## São contas sobre as tabelas de verdade (enemies.json, progression.json, items.json) com a mesma fórmula do
## Enemy._ready e do Game (dano básico, vida máxima, defesa): mostram a ordem de grandeza da luta para um
## personagem de nível baixo com a arma inicial. NÃO são uma simulação de gameplay (sem esquiva, sem habilidades,
## sem ritmo de ataque); o comportamento real dos monstros na expedição é conferido no smoke (--smoke-part=expedicao).

var _bt: BalanceTables


func _tables() -> BalanceTables:
	if _bt == null:
		_bt = BalanceTables.load_dir("res://data/balance")
	return _bt


func _def() -> Dictionary:
	return ExpeditionDefs.get_def("pantano")


## Personagem de referência: nível 1, atributos iniciais (5 em tudo), arma inicial da classe, sem armadura.
## Mesmas contas do Game.melee_damage / max_hp / damage_taken_mult (o autoload não roda no teste unitário).
func _hero(char_class := "warrior", level := 1) -> Dictionary:
	var bt := _tables()
	var row: Dictionary = bt.get_table("classes")[char_class]
	var weapon: Dictionary = bt.get_table("items")[str(row.starter_weapon)]
	var attrs := {"str": 5, "int": 5, "vit": 5, "agi": 5}
	var dmg := CharRules.basic_damage(str(row.weapon_class), attrs, float(weapon.damage), 0.0)
	var hp := 60.0 + 5 * 10.0 + (level - 1) * 8.0
	var defense := 5 * 0.25
	var k := 10.0 + level
	return {"dmg": dmg, "hp": hp, "taken": k / (k + defense), "level": level}


## Monstros da expedição a partir da cena: [{kind, room, chief}] (a sala vem do "level" da sala do ExpeditionDefs
## pelo nome do ponto: o test_expedition_map já confere que cada bando nasce na sala certa).
func _spawns() -> Array:
	var root := (load(MapData.SCENES[ExpeditionDefs.map_of("pantano")]) as PackedScene).instantiate() as MapRoot
	var rooms := {}
	for r: MapDungeonRoom in root.pieces(MapDungeonRoom):
		rooms[str(r.name)] = {"node": r, "c": Vector2(root.local_xform(r).origin.x, root.local_xform(r).origin.z)}
	var out := []
	for s: EnemySpawn in root.pieces(EnemySpawn):
		var o := root.local_xform(s).origin
		var home := ""
		for id in rooms:
			if (rooms[id].node as MapDungeonRoom).contains(rooms[id].c, Vector2(o.x, o.z)):
				home = id
		out.append({"kind": s.kind, "room": home, "chief": s.chief, "level": s.level, "level_max": s.level_max})
	root.free()
	return out


func _role(s: Dictionary) -> String:
	var boss := bool(_tables().get_table("enemies").get(s.kind, {}).get("boss", false)) or bool(s.chief)
	return ExpeditionBalance.role_of(boss)


# ================================================================ dados
func test_balance_is_valid() -> void:
	for id in ExpeditionDefs.DATA:
		var problems := ExpeditionBalance.validate(ExpeditionDefs.get_def(id))
		for p in problems:
			T.ok(false, "%s: %s" % [id, p])
		T.eq(problems.size(), 0, "%s: balanceamento sem problemas" % id)


func test_validate_catches_bad_data() -> void:
	var bad := _def().duplicate(true)
	bad.rooms["Encruzilhada"]["level"] = [5, 2]
	bad.rooms["Entrada"]["level"] = [1, 1]
	bad.rooms["Clareira Funda"].erase("level")
	bad["balance"] = {"boss": {"hp": 0.0}, "chefão": {}}
	var p := ExpeditionBalance.validate(bad)
	T.eq(p.size(), 5, "faixa invertida, nível em sala sem luta, sala de luta sem nível, mult zero e papel estranho")


func test_room_levels_override_scene() -> void:
	var def := _def()
	T.eq(ExpeditionBalance.level_range(def, "Encruzilhada", 16, 17), Vector2i(2, 3), "Encruzilhada: nível 2-3")
	T.eq(ExpeditionBalance.level_range(def, "Clareira Funda", 17, 19), Vector2i(3, 4), "Clareira Funda: nível 3-4")
	T.eq(ExpeditionBalance.level_range(def, "Trono da Rainha", 19, 20), Vector2i(5, 5), "Trono da Rainha: nível 5")
	T.eq(ExpeditionBalance.level_range(def, "sala sem faixa", 7, 9), Vector2i(7, 9), "sem faixa: vale o nível da cena")
	T.eq(ExpeditionBalance.level_range(def, "sala sem faixa", 7, 3), Vector2i(7, 7), "máx nunca abaixo do mín")


func test_scene_levels_match_defs() -> void:
	for s in _spawns():
		var lv := ExpeditionBalance.level_range(_def(), str(s.room), 0, 0)
		T.eq(Vector2i(int(s.level), maxi(int(s.level), int(s.level_max))), lv,
			"%s em %s: nível da cena igual ao do ExpeditionDefs" % [s.kind, s.room])


func test_roles() -> void:
	T.eq(ExpeditionBalance.role_of(true), "boss", "chefe")
	T.eq(ExpeditionBalance.role_of(false), "common", "monstro da sala")
	T.eq(ExpeditionBalance.role_of(false, true), "minion", "nasceu durante a luta")
	T.eq(ExpeditionBalance.role_of(true, true), "boss", "chefe invocado continua chefe")
	var none := ExpeditionBalance.mults({}, "boss")
	T.ok(is_equal_approx(none.hp, 1.0) and is_equal_approx(none.dmg, 1.0), "sem bloco balance: números do MMO (1.0)")


# ================================================================ sem escala de endgame
func test_no_endgame_levels() -> void:
	var bt := _tables()
	var top := ExpeditionBalance.max_level(_def())
	T.ok(top >= 1 and top <= 5, "nível máximo da primeira expedição baixo (%d)" % top)
	# placa vermelha (danger_mults) nunca liga: nem o personagem de nível 1 fica danger_diff abaixo do monstro
	var d := ProgressionRules.danger_mults(bt, top, 1)
	T.ok(top - 1 < ProgressionRules.danger_diff(bt), "nível %d - 1 < diferença da placa vermelha" % top)
	T.ok(is_equal_approx(d.dmg, 1.0) and is_equal_approx(d.taken, 1.0),
		"sem bônus de perigo contra nível 1 (dano x%.2f, recebe x%.2f)" % [d.dmg, d.taken])
	# a camada visual de nível alto (tinta/escala de tier 2+) também não aparece
	T.eq(ProgressionRules.tier_of(bt, top), 1, "monstros na primeira camada de nível")


func test_mults_never_buff_first_expedition() -> void:
	for role in ExpeditionBalance.ROLES:
		var m := ExpeditionBalance.mults(_def(), role)
		T.ok(m.hp <= 1.0 and m.dmg <= 1.0 and m.hp > 0.0 and m.dmg > 0.0,
			"%s: a primeira expedição só alivia (vida x%.2f, dano x%.2f)" % [role, m.hp, m.dmg])


# ================================================================ números da luta (contas, não gameplay)
func test_hero_kills_room_monsters() -> void:
	var bt := _tables()
	var hero := _hero()
	for s in _spawns():
		if _role(s) != "common":
			continue
		var lv := ExpeditionBalance.level_range(_def(), str(s.room), 0, 0)
		var st := ExpeditionBalance.enemy_stats(bt, _def(), s.kind, lv.y, "common")
		var hit: float = hero.dmg * ElementRules.mult(bt, s.kind, "fisico")
		var hits := ceili(st.hp / hit)
		T.ok(hit > 0.0, "%s: o golpe básico tira vida" % s.kind)
		T.ok(hits >= 2 and hits <= 12, "%s Nv %d: %d golpes básicos de nível 1 (vida %.0f, golpe %.0f)"
			% [s.kind, lv.y, hits, st.hp, hit])


func test_room_monster_damage_fits_level_one() -> void:
	var bt := _tables()
	var hero := _hero()
	for s in _spawns():
		if _role(s) != "common":
			continue
		var lv := ExpeditionBalance.level_range(_def(), str(s.room), 0, 0)
		var st := ExpeditionBalance.enemy_stats(bt, _def(), s.kind, lv.y, "common")
		var taken: float = st.dmg * hero.taken
		var frac: float = taken / hero.hp
		# o golpe base do slime explosivo é a explosão (dá para fugir); os outros batem bem menos
		var cap := 0.45 if s.kind == "slime_explosivo" else 0.2
		T.ok(frac >= 0.03 and frac <= cap, "%s Nv %d: golpe base tira %.0f%% da vida de nível 1 (%.0f de %.0f)"
			% [s.kind, lv.y, frac * 100.0, taken, hero.hp])


func test_espinheira_beatable_not_trivial() -> void:
	var bt := _tables()
	var hero := _hero()
	var lv := ExpeditionBalance.level_range(_def(), "Trono da Rainha", 0, 0)
	var st := ExpeditionBalance.enemy_stats(bt, _def(), "espinheira", lv.x, "boss", true)
	var mmo := ExpeditionBalance.enemy_stats(bt, {}, "espinheira", 20, "boss", true)
	var hit: float = hero.dmg * ElementRules.mult(bt, "espinheira", "fisico")
	var hits := ceili(st.hp / hit)
	T.ok(hits >= 60 and hits <= 200, "Espinheira Nv %d: %d golpes básicos de nível 1 (vida %.0f)" % [lv.x, hits, st.hp])
	T.ok(st.hp < mmo.hp * 0.25, "vida bem abaixo da Espinheira do Covil Nv 20 (%.0f x %.0f)" % [st.hp, mmo.hp])
	var frac: float = st.dmg * hero.taken / hero.hp
	T.ok(frac >= 0.12 and frac <= 0.3, "Espinheira: golpe base tira %.0f%% da vida de nível 1 (%.0f)"
		% [frac * 100.0, st.dmg * hero.taken])
	# brotos (lacaios) com o nível dela e o balanceamento de lacaio
	var sp := ExpeditionBalance.enemy_stats(bt, _def(), "broto_espinheiro", lv.x, "minion")
	var sp_hits := ceili(sp.hp / (hero.dmg * ElementRules.mult(bt, "broto_espinheiro", "fisico")))
	T.ok(sp_hits >= 2 and sp_hits <= 8, "broto da Espinheira: %d golpes básicos (vida %.0f)" % [sp_hits, sp.hp])


# ================================================================ isolamento do MMO
func test_stats_match_enemy_formula_without_expedition() -> void:
	# sem o bloco da expedição a conta é a do Enemy._ready (curva x categoria), igual ao MMO
	var bt := _tables()
	for kind in ["slime_veloz", "goblin_xama", "espinheira"]:
		var chief: bool = kind == "espinheira"
		var st := ExpeditionBalance.enemy_stats(bt, {}, kind, 18, "boss" if chief else "common", chief)
		var t: Dictionary = bt.get_table("enemies")[kind]
		var lm := ProgressionRules.enemy_mults(bt, kind, 18)
		var rk := ProgressionRules.rank_mults(bt, kind, chief)
		T.ok(is_equal_approx(st.hp, float(t.hp) * lm.hp * rk.hp), "%s: vida do MMO sem o balanceamento" % kind)
		T.ok(is_equal_approx(st.dmg, float(t.damage) * lm.dmg * rk.dmg), "%s: dano do MMO sem o balanceamento" % kind)


func test_mmo_tables_untouched() -> void:
	# o balanceamento da expedição não mexe nas tabelas que o MMO e a Horda leem
	var bt := _tables()
	var p: Dictionary = bt.get_table("progression")
	T.ok(is_equal_approx(float(p.rank.common.hp), 2.0) and is_equal_approx(float(p.rank.common.dmg), 2.3),
		"categoria comum do MMO intacta")
	T.ok(is_equal_approx(float(p.rank.boss.hp), 3.0) and is_equal_approx(float(p.rank.boss.dmg), 4.83),
		"categoria chefe do MMO intacta")
	T.eq(int(p.danger.diff), 5, "placa vermelha do MMO intacta")
	var e: Dictionary = bt.get_table("enemies")
	T.ok(int(e.espinheira.hp) == 1500 and int(e.espinheira.damage) == 30, "Espinheira do enemies.json intacta")
	var rt: Dictionary = bt.get_table("regions")
	T.ok(int(rt.dg_bosque_trono.level_min) == 19 and int(rt.dg_bosque_trono.level_max) == 20,
		"Trono do Covil das Raízes (MMO) continua Nv 19-20")
	T.ok(not bt.get_table("horde").has("expedition"), "Horda sem nada da expedição")
