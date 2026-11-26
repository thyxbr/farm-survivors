class_name ExpeditionEvents
extends RefCounted
## Eventos das salas de evento da expedição (puro: sem cena, sem autoload). Um evento é uma escolha única com
## consequência só dentro da run: o santuário da sala (run_shrine.gd) abre a tela (expedition_event_ui.gd) e o modo
## da expedição aplica a opção escolhida. Cada opção pode:
##   "hp_cost": fração da vida ATUAL que o jogador perde ao escolher (nunca mata: sobra pelo menos 1)
##   "upgrade": id de uma bênção do ExpeditionUpgrades (normalmente de evento, "pool": false), que vale até o fim
##              da expedição como as outras (ExpeditionRun.modifiers -> Game.run_mods)
## Opção sem nada = recusar e seguir. Nada aqui toca o save, o inventário ou os atributos permanentes.

const DATA := {
	"santuario": {
		"title": "Santuário Abandonado",
		"text": "Uma estátua da Deusa jaz partida entre as ruínas, coberta de raízes. Na bacia aos pés dela, sangue "
			+ "seco e uma inscrição: \"Quem dá de si, recebe da terra.\"",
		"options": [
			{"id": "sangue", "name": "Oferecer sangue",
				"desc": "Perca 25% da vida atual. Ganhe Pacto de Sangue: +25% de dano até o fim da expedição.",
				"hp_cost": 0.25, "upgrade": "pacto_sangue", "color": Color(0.95, 0.3, 0.3)},
			{"id": "prece", "name": "Rezar pela proteção",
				"desc": "Ganhe Véu da Deusa: +8 de defesa até o fim da expedição.",
				"upgrade": "veu_deusa", "color": Color(0.6, 0.9, 1.0)},
			{"id": "recusar", "name": "Deixar a oferenda",
				"desc": "Não toque em nada e siga em frente.", "color": Color(0.75, 0.75, 0.7)},
		],
	},
}


static func has(id: String) -> bool:
	return DATA.has(id)


static func info(id: String) -> Dictionary:
	return DATA.get(id, {})


static func options(id: String) -> Array:
	return info(id).get("options", [])


## Opção `option` do evento `id` ({} se não existe).
static func option(id: String, option_id: String) -> Dictionary:
	for o in options(id):
		if str(o.get("id", "")) == option_id:
			return o
	return {}


## Vida que sobra depois de pagar `cost` (fração da vida atual `hp`); nunca abaixo de 1.
static func hp_after(hp: float, cost: float) -> float:
	if cost <= 0.0:
		return hp
	return maxf(1.0, hp - hp * clampf(cost, 0.0, 1.0))


## Problemas da tabela ([] = ok): título, ao menos 2 opções com id único, bênçãos que existem e custo válido.
static func validate() -> PackedStringArray:
	var out := PackedStringArray()
	for id in DATA:
		var d: Dictionary = DATA[id]
		if str(d.get("title", "")) == "" or str(d.get("text", "")) == "":
			out.append("evento '%s' sem título ou texto" % id)
		var opts: Array = d.get("options", [])
		if opts.size() < 2:
			out.append("evento '%s' com menos de 2 opções" % id)
		var seen := {}
		for o in opts:
			var oid := str(o.get("id", ""))
			if oid == "" or seen.has(oid):
				out.append("evento '%s': opção sem id ou repetida (%s)" % [id, oid])
			seen[oid] = true
			if str(o.get("name", "")) == "" or str(o.get("desc", "")) == "":
				out.append("evento '%s': opção '%s' sem nome ou descrição" % [id, oid])
			var up := str(o.get("upgrade", ""))
			if up != "" and not ExpeditionUpgrades.has(up):
				out.append("evento '%s': opção '%s' dá a bênção '%s', que não existe" % [id, oid, up])
			var cost := float(o.get("hp_cost", 0.0))
			if cost < 0.0 or cost >= 1.0:
				out.append("evento '%s': opção '%s' com custo de vida fora de [0, 1)" % [id, oid])
	return out
