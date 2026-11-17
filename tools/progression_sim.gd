extends SceneTree
## Simulador de ritmo da progressão: lê data/balance (as mesmas contas do jogo, em ProgressionRules) e imprime
##   - por nível: XP para o próximo, vida e XP do monstro de referência (sim.ref_enemy) no mesmo nível,
##     dano do ataque básico e golpes para matar de cada classe (build focada, melhor arma de nível <= L),
##     e os minutos estimados no nível;
##   - por faixa: horas estimadas x alvo, e quanto da XP da faixa as missões do quests.json dão (o simulador
##     desconta da caça essa fração, no máximo quest_xp_share);
##   - golpes do guerreiro em cada monstro do enemies.json em alguns níveis;
##   - itens por morte dos monstros comuns (meta 0,5-0,8).
## Uso (na raiz do projeto):
##   godot --headless --path . -s tools/progression_sim.gd
## Guia dos números: docs/BALANCEAMENTO.md. O teste tests/unit/test_progression_pacing.gd falha se os golpes
## saírem de 3-5 (healer até 7) ou as horas por faixa saírem mais de 20% do alvo.

const CLASSES := ["warrior", "archer", "mage", "healer"]
const SHORT := {"warrior": "guer", "archer": "arq", "mage": "mago", "healer": "heal"}
const MONSTER_LEVELS := [5, 15, 25, 40]


func _init() -> void:
	var bt := BalanceTables.load_dir("res://data/balance")
	var prog: Dictionary = bt.get_table("progression")
	var sim: Dictionary = prog.get("sim", {})
	var ref := str(sim.get("ref_enemy", "goblin"))
	var maxl := ProgressionRules.max_level(bt)

	print("\n== Ritmo por nível (monstro de referência: %s, caçando com %s) ==" % [ref, str(sim.get("ref_class", "warrior"))])
	var head := "%4s %10s %7s %7s" % ["nv", "xp p/prox", "vida", "xp mob"]
	for c in CLASSES:
		head += " %6s" % ("d." + SHORT[c])
	for c in CLASSES:
		head += " %5s" % ("g." + SHORT[c])
	head += " %8s  %s" % ["min", "armas (guer/arq/mago/heal)"]
	print(head)
	for l in range(1, maxl + 1):
		var row := "%4d %10d %7d %7d" % [l, ProgressionRules.xp_to_next(bt, l), roundi(ProgressionRules.sim_enemy_hp(bt, l)),
			ProgressionRules.sim_enemy_xp(bt, l)]
		var weapons: Array = []
		for c in CLASSES:
			var w := ProgressionRules.sim_best_weapon(bt, c, l)
			row += " %6d" % roundi(float(w.damage))
			weapons.append(str(w.id))
		for c in CLASSES:
			row += " %5d" % ProgressionRules.sim_hits(bt, c, l)
		var mins := ProgressionRules.sim_minutes(bt, l) if l < maxl else 0.0
		row += " %8.1f  %s" % [mins, "/".join(weapons)]
		print(row)

	print("\n== Horas por faixa ==")
	var hours := ProgressionRules.sim_hours(bt)
	var targets: Dictionary = sim.get("target_hours", {})
	var quest_xp := _quest_xp_by_level(bt)
	var total := 0.0
	print("%8s %8s %8s %8s %14s %10s" % ["faixa", "horas", "alvo", "desvio", "XP de missão", "usada"])
	for band in sim.get("bands", []):
		var key := "%d-%d" % [int(band[0]), int(band[1])]
		var h := float(hours.get(key, 0.0))
		total += h
		var t := float(targets.get(key, 0.0))
		var dev := "%+.0f%%" % ((h / t - 1.0) * 100.0) if t > 0.0 else "-"
		var need := 0
		var got := 0
		for l in range(int(band[0]), int(band[1])):
			need += ProgressionRules.xp_to_next(bt, l)
			got += int(quest_xp.get(l, 0))
		print("%8s %8.2f %8.1f %8s %13.0f%% %9.0f%%" % [key, h, t, dev, 100.0 * float(got) / float(maxi(need, 1)),
			100.0 * ProgressionRules.sim_quest_share(bt, int(band[0]))])
	print("%8s %8.2f" % ["total", total])
	print("(XP de missão: soma do reward_xp das missões com nível na faixa / XP para atravessar a faixa;")
	print(" usada: o que o simulador desconta da caça, no máximo quest_xp_share = %.0f%%.)" % (100.0 * float(prog.get("quest_xp_share", 0.0))))

	print("\n== Golpes do guerreiro (build focada) em cada monstro no mesmo nível ==")
	var line := "%-20s %4s" % ["monstro", "ref"]
	for l in MONSTER_LEVELS:
		line += " %12s" % ("nv %d vida/g" % l)
	print(line)
	var enemies: Dictionary = bt.get_table("enemies")
	for kind in enemies:
		var e: Dictionary = enemies[kind]
		line = "%-20s %4d" % [kind, ProgressionRules.enemy_level(bt, kind, 0)]
		for l in MONSTER_LEVELS:
			var hp := float(e.get("hp", 0.0)) * float(ProgressionRules.enemy_mults(bt, kind, l).hp)
			var dmg := float(ProgressionRules.sim_best_weapon(bt, "warrior", l).damage)
			line += " %12s" % ("%d/%d" % [roundi(hp), ceili(hp / maxf(dmg, 1.0) - 0.000001)])
		var tag := " (chefe)" if e.get("boss", false) else (" (elite)" if e.get("elite", false) else "")
		print(line + tag)

	print("\n== Itens por morte no ref_level (4000 sorteios, equipamento incluído; meta 0,5-0,8 nos comuns) ==")
	for kind in enemies:
		var e2: Dictionary = enemies[kind]
		if e2.get("boss", false) or e2.get("elite", false):
			continue
		print("%-20s %.2f" % [kind, ProgressionRules.sim_items_per_kill(bt, kind, 4000, 1234)])
	quit(0)


## {nível: soma do reward_xp das missões desse nível} (quests.json; sem as de evento sazonal, como o
## ProgressionRules.sim_quest_share).
func _quest_xp_by_level(bt: BalanceTables) -> Dictionary:
	var out := {}
	var quests: Dictionary = bt.get_table("quests")
	for id in quests:
		if quests[id].has("event"):
			continue
		var l := int(quests[id].get("level", 1))
		out[l] = int(out.get(l, 0)) + int(quests[id].get("reward_xp", 0))
	return out
