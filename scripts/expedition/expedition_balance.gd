class_name ExpeditionBalance
extends RefCounted
## Balanceamento dos monstros do modo Expedição (puro: só lê o ExpeditionDefs e as BalanceTables).
##
## Não é um sistema de combate à parte: o monstro da expedição é o Enemy de sempre, com nível, curva de nível e
## categoria (progression.json) como no MMO. A expedição só decide duas coisas, e só para os monstros dela:
##   1. o NÍVEL de quem nasce em cada sala ("level": [mín, máx] na sala do ExpeditionDefs), no lugar do nível
##      escrito na cena;
##   2. um multiplicador de vida e de dano por papel ("balance" do ExpeditionDefs: common, minion, boss), que o
##      modo da expedição põe em Enemy.hp_mult / dmg_mult antes do monstro entrar no mundo — o mesmo caminho que o
##      Desafio da Horda usa (survival_mode.gd). O Enemy._ready multiplica isso pela curva e pela categoria.
## Nada aqui muda enemies.json, progression.json, o Enemy nem os monstros fora da expedição.
##
## Para subir a dificuldade das próximas expedições basta subir os níveis das salas e/ou os multiplicadores.

const ROLES := ["common", "minion", "boss"]


## Papel do monstro na expedição: chefe da sala de chefe, lacaio (nasceu durante a luta) ou comum.
static func role_of(is_boss: bool, summoned := false) -> String:
	if is_boss:
		return "boss"
	return "minion" if summoned else "common"


## Faixa de nível [mín, máx] da sala; sem "level" na sala, a da cena (`scene_min`, `scene_max`).
static func level_range(def: Dictionary, room: String, scene_min: int, scene_max: int) -> Vector2i:
	var lv = ExpeditionDefs.rooms(def).get(room, {}).get("level")
	if lv is Array and lv.size() == 2:
		return Vector2i(int(lv[0]), maxi(int(lv[0]), int(lv[1])))
	return Vector2i(scene_min, maxi(scene_min, scene_max))


## Maior nível que um monstro da expedição pode ter (o chefe passa o dele aos lacaios).
static func max_level(def: Dictionary) -> int:
	var m := 0
	for r in ExpeditionDefs.rooms(def):
		var lv = ExpeditionDefs.rooms(def)[r].get("level")
		if lv is Array and lv.size() == 2:
			m = maxi(m, maxi(int(lv[0]), int(lv[1])))
	return m


## {"hp", "dmg"} da expedição para o papel (sem bloco = 1.0, os números do MMO).
static func mults(def: Dictionary, role: String) -> Dictionary:
	var b: Dictionary = def.get("balance", {}).get(role, {})
	return {"hp": float(b.get("hp", 1.0)), "dmg": float(b.get("dmg", 1.0))}


## Vida máxima e dano base ({"hp", "dmg"}) que um monstro `kind` de nível `level` terá na expedição: a mesma conta
## do Enemy._ready (dado do enemies.json x curva de nível x categoria) vezes o multiplicador do papel. Monstro
## comum (não elite). O "dmg" é o `data.damage * dmg_mult`; cada golpe ainda multiplica pelo próprio fator.
static func enemy_stats(bt: BalanceTables, def: Dictionary, kind: String, level: int, role: String,
		chief := false) -> Dictionary:
	var t: Dictionary = bt.get_table("enemies").get(kind, {})
	var lm := ProgressionRules.enemy_mults(bt, kind, level)
	var rk := ProgressionRules.rank_mults(bt, kind, chief) if level > 0 else {"hp": 1.0, "dmg": 1.0}
	var em := mults(def, role)
	return {"hp": float(t.get("hp", 0.0)) * float(lm.hp) * float(rk.hp) * float(em.hp),
		"dmg": float(t.get("damage", 0.0)) * float(lm.dmg) * float(rk.dmg) * float(em.dmg)}


## Problemas do balanceamento da expedição ([] = ok): faixas de nível válidas só em salas de luta, papéis
## conhecidos e multiplicadores positivos.
static func validate(def: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var rs := ExpeditionDefs.rooms(def)
	for r in rs:
		var lv = rs[r].get("level")
		if lv == null:
			if ExpeditionDefs.needs_clear(def, r):
				out.append("sala de luta '%s' sem faixa de nível" % r)
			continue
		if not (lv is Array) or lv.size() != 2:
			out.append("sala '%s': level precisa ser [mín, máx]" % r)
			continue
		if int(lv[0]) < 1 or int(lv[1]) < int(lv[0]):
			out.append("sala '%s': faixa de nível inválida %s" % [r, str(lv)])
		if not ExpeditionDefs.needs_clear(def, r):
			out.append("sala '%s' não tem luta e não precisa de nível" % r)
	var b = def.get("balance", {})
	if not (b is Dictionary):
		out.append("balance precisa ser um dicionário")
		return out
	for role in b:
		if not role in ROLES:
			out.append("papel desconhecido no balance: '%s'" % role)
			continue
		for k in ["hp", "dmg"]:
			if float(b[role].get(k, 1.0)) <= 0.0:
				out.append("balance.%s.%s precisa ser > 0" % [role, k])
	return out
