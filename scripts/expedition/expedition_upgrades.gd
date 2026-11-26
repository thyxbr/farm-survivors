class_name ExpeditionUpgrades
extends RefCounted
## Melhorias temporárias da expedição (puro: sem cena, sem autoload). Depois de certas salas de luta
## (ExpeditionDefs, "reward": true) o jogador escolhe 1 de 3; a escolha fica no ExpeditionRun.modifiers
## ({id: acúmulos}) e o modo da expedição traduz isso em Game.run_mods (total_mods), que o personagem já lê:
##   damage  -> Game.mod("damage")   (ataque básico, habilidades, encanto)
##   max_hp  -> Game.max_hp()        (multiplicador da vida máxima)
##   defense -> Game.defense()       (defesa fixa somada à da armadura)
##   speed   -> Game.speed_multiplier()
##   cdr     -> Game.cooldown_mult() (fração a menos na recarga das habilidades)
## Os valores somam como as cartas da Horda: run_mods começa em 1.0 (multiplicadores) ou 0.0 (fixos) e cada
## acúmulo soma o "add". Nada aqui é salvo: run_mods volta ao padrão quando a expedição termina.

## Acúmulos máximos de uma mesma melhoria numa run.
const MAX_STACKS := 5
## Quantas opções a recompensa mostra.
const CHOICES := 3
## Chaves de Game.run_mods que as melhorias podem somar (validate confere).
const RUN_MOD_KEYS := ["damage", "max_hp", "defense", "speed", "cdr"]

## icon: desenho do SkillIcon (mesmos ids das passivas da Horda); color: cor da carta.
const DATA := {
	"furia": {
		"name": "Fúria do Pântano",
		"desc": "+12% de dano em ataques e habilidades.",
		"add": {"damage": 0.12},
		"icon": "poder", "color": Color(1.0, 0.48, 0.3),
	},
	"seiva": {
		"name": "Seiva Vital",
		"desc": "+15% de vida máxima. A vida ganha já vem cheia.",
		"add": {"max_hp": 0.15},
		"icon": "vigor", "color": Color(0.95, 0.36, 0.42),
	},
	"casca": {
		"name": "Casca de Raiz",
		"desc": "+5 de defesa: menos dano recebido de cada golpe.",
		"add": {"defense": 5.0},
		"icon": "armadura", "color": Color(0.62, 0.72, 0.5),
	},
	"nevoa": {
		"name": "Passos de Névoa",
		"desc": "+8% de velocidade de movimento.",
		"add": {"speed": 0.08},
		"icon": "botas", "color": Color(0.55, 0.85, 0.95),
	},
	"sussurro": {
		"name": "Foco Sussurrante",
		"desc": "-8% de recarga das habilidades.",
		"add": {"cdr": 0.08},
		"icon": "celeridade", "color": Color(0.75, 0.6, 1.0),
	},
}


static func has(id: String) -> bool:
	return DATA.has(id)


static func info(id: String) -> Dictionary:
	return DATA.get(id, {})


static func display_name(id: String) -> String:
	return str(info(id).get("name", id))


## Ainda pode ganhar mais um acúmulo de `id` com as melhorias `taken` ({id: acúmulos})?
static func can_take(id: String, taken: Dictionary) -> bool:
	return has(id) and int(taken.get(id, 0)) < MAX_STACKS


## Sorteia até `n` melhorias diferentes que ainda não chegaram ao máximo. Com o mesmo `rng` (mesma semente)
## sai a mesma lista. Vazia só se todas estiverem no máximo.
static func roll(rng: RandomNumberGenerator, taken: Dictionary, n := CHOICES) -> Array[String]:
	var pool: Array[String] = []
	for id in DATA:
		if can_take(id, taken):
			pool.append(id)
	pool.sort()   # ordem estável antes de sortear (independe da ordem do dicionário)
	var out: Array[String] = []
	while out.size() < n and not pool.is_empty():
		out.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return out


## Soma de tudo que as melhorias `taken` dão: chave de run_mods -> valor a somar.
static func total_mods(taken: Dictionary) -> Dictionary:
	var out := {}
	for id in taken:
		if not has(id):
			continue
		var stacks := clampi(int(taken[id]), 0, MAX_STACKS)
		var add: Dictionary = DATA[id].add
		for k in add:
			out[k] = float(out.get(k, 0.0)) + float(add[k]) * stacks
	return out


## `base` (um run_mods zerado) com as melhorias somadas por cima. Não mexe em `base`.
static func apply_to(base: Dictionary, taken: Dictionary) -> Dictionary:
	var out := base.duplicate()
	var add := total_mods(taken)
	for k in add:
		out[k] = float(out.get(k, 0.0)) + float(add[k])
	return out


## Texto do nível na carta: "Nv 1/5" para a primeira, "Nv 3/5" para o terceiro acúmulo.
static func level_text(id: String, taken: Dictionary) -> String:
	return "Nv %d/%d" % [mini(int(taken.get(id, 0)) + 1, MAX_STACKS), MAX_STACKS]


## Problemas da tabela ([] = ok): nome, descrição, só chaves conhecidas de run_mods e valores positivos.
static func validate() -> PackedStringArray:
	var out := PackedStringArray()
	for id in DATA:
		var d: Dictionary = DATA[id]
		if str(d.get("name", "")) == "" or str(d.get("desc", "")) == "":
			out.append("melhoria '%s' sem nome ou descrição" % id)
		var add: Dictionary = d.get("add", {})
		if add.is_empty():
			out.append("melhoria '%s' não dá nada" % id)
		for k in add:
			if not k in RUN_MOD_KEYS:
				out.append("melhoria '%s' mexe em '%s', que não é de run_mods" % [id, k])
			elif float(add[k]) <= 0.0:
				out.append("melhoria '%s' com valor não positivo em '%s'" % [id, k])
	if DATA.size() < CHOICES:
		out.append("menos melhorias (%d) do que opções na recompensa (%d)" % [DATA.size(), CHOICES])
	return out
