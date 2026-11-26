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
##
## Melhorias de habilidade (só do Altar Ancestral, ExpeditionSkills.roll_evolution): id "<tipo>@<habilidade>"
## (ex.: "potencia@sword_vortex"), acumulam até ABILITY_MAX_STACKS e entram em run_mods nas chaves por habilidade
## que o Game já lê junto com os talentos:
##   potencia     -> "ability_dmg:<id>"  (Game.ability_dmg_mult: só nas habilidades que usam esse multiplicador)
##   recarga      -> "ability_cd:<id>"   (Game.cooldown_mult(id): fração a menos na recarga desta habilidade)
##   persistencia -> "ability_time:<id>" (Game.ability_time_bonus: segundos a mais no buff da habilidade; o valor é
##                   uma fração da duração base, convertida em segundos com `buff_times`)
## Quem diz que habilidade aceita que tipo é ExpeditionSkills.supports.

## Acúmulos máximos de uma mesma melhoria numa run.
const MAX_STACKS := 5
## Quantas opções a recompensa mostra.
const CHOICES := 3
## Chaves de Game.run_mods que as melhorias podem somar (validate confere).
const RUN_MOD_KEYS := ["damage", "max_hp", "defense", "speed", "cdr"]
## Acúmulos máximos de uma melhoria de habilidade (cada tipo, em cada habilidade).
const ABILITY_MAX_STACKS := 3
## Separador do id de melhoria de habilidade: "<tipo>@<habilidade>".
const SEP := "@"

## Tipos de melhoria de habilidade. "key": prefixo da chave de run_mods; "add": quanto cada acúmulo soma (fração).
const ABILITY_KINDS := {
	"potencia": {
		"label": "Potência", "key": "ability_dmg", "add": 0.15,
		"desc": "+15% de dano causado por esta habilidade.", "value": "+%d%% de dano",
		"icon": "poder", "color": Color(1.0, 0.55, 0.35),
	},
	"recarga": {
		"label": "Recuperação", "key": "ability_cd", "add": 0.10,
		"desc": "-10% de recarga desta habilidade.", "value": "-%d%% de recarga",
		"icon": "celeridade", "color": Color(0.7, 0.6, 1.0),
	},
	"persistencia": {
		"label": "Persistência", "key": "ability_time", "add": 0.20,
		"desc": "+20% de duração do efeito desta habilidade.", "value": "+%d%% de duração",
		"icon": "vigor", "color": Color(0.55, 0.95, 0.7),
	},
}

## icon: desenho do SkillIcon (mesmos ids das passivas da Horda); color: cor da carta. "pool": false = não sai no
## sorteio das bênçãos (só vem de um evento: ExpeditionEvents), mas soma e some igual às outras.
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
	# só do Santuário Abandonado (ExpeditionEvents "santuario")
	"pacto_sangue": {
		"name": "Pacto de Sangue",
		"desc": "+25% de dano em ataques e habilidades.",
		"add": {"damage": 0.25},
		"icon": "poder", "color": Color(0.85, 0.15, 0.2), "pool": false,
	},
	"veu_deusa": {
		"name": "Véu da Deusa",
		"desc": "+8 de defesa: a Deusa amortece cada golpe.",
		"add": {"defense": 8.0},
		"icon": "armadura", "color": Color(0.6, 0.9, 1.0), "pool": false,
	},
}


static func has(id: String) -> bool:
	return DATA.has(id) or is_ability_upgrade(id)


## `id` é uma melhoria de habilidade válida ("<tipo>@<habilidade>" de um tipo conhecido que a habilidade aceita).
static func is_ability_upgrade(id: String) -> bool:
	var p := id.split(SEP)
	return p.size() == 2 and ABILITY_KINDS.has(p[0]) and ExpeditionSkills.supports(p[1], p[0])


## Id da melhoria de habilidade do tipo `kind` em `ability`.
static func ability_upgrade(kind: String, ability: String) -> String:
	return kind + SEP + ability


## Tipo ("potencia", ...) de uma melhoria de habilidade; "" se não é uma.
static func kind_of(id: String) -> String:
	return id.get_slice(SEP, 0) if is_ability_upgrade(id) else ""


## Habilidade de uma melhoria de habilidade; "" se não é uma.
static func ability_of(id: String) -> String:
	return id.get_slice(SEP, 1) if is_ability_upgrade(id) else ""


## Acúmulos máximos de `id` numa run.
static func max_stacks(id: String) -> int:
	return ABILITY_MAX_STACKS if is_ability_upgrade(id) else MAX_STACKS


static func info(id: String) -> Dictionary:
	if is_ability_upgrade(id):
		var k: Dictionary = ABILITY_KINDS[kind_of(id)]
		var ab := ability_of(id)
		return {"name": "%s — %s" % [ExpeditionSkills.ability_name(ab), k.label], "desc": k.desc,
			"icon": k.icon, "color": k.color, "kind": kind_of(id), "ability": ab}
	return DATA.get(id, {})


static func display_name(id: String) -> String:
	return str(info(id).get("name", id))


## Ainda pode ganhar mais um acúmulo de `id` com as melhorias `taken` ({id: acúmulos})?
static func can_take(id: String, taken: Dictionary) -> bool:
	return has(id) and int(taken.get(id, 0)) < max_stacks(id)


## Entra no sorteio das bênçãos (as de evento, "pool": false, não).
static func in_pool(id: String) -> bool:
	return DATA.has(id) and bool(DATA[id].get("pool", true))


## Sorteia até `n` melhorias diferentes do sorteio que ainda não chegaram ao máximo. Com o mesmo `rng` (mesma semente)
## sai a mesma lista. Vazia só se todas estiverem no máximo.
static func roll(rng: RandomNumberGenerator, taken: Dictionary, n := CHOICES) -> Array[String]:
	var pool: Array[String] = []
	for id in DATA:
		if in_pool(id) and can_take(id, taken):
			pool.append(id)
	pool.sort()   # ordem estável antes de sortear (independe da ordem do dicionário)
	var out: Array[String] = []
	while out.size() < n and not pool.is_empty():
		out.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return out


## Soma de tudo que as melhorias `taken` dão: chave de run_mods -> valor a somar. `buff_times` = duração base (s)
## de cada buff de habilidade (ExpeditionSkills.time_key -> segundos), para a Persistência virar segundos.
static func total_mods(taken: Dictionary, buff_times := {}) -> Dictionary:
	var out := {}
	for id in taken:
		if not has(id):
			continue
		var stacks := clampi(int(taken[id]), 0, max_stacks(id))
		if is_ability_upgrade(id):
			var key := ability_mod_key(id)
			var v := float(ABILITY_KINDS[kind_of(id)].add) * stacks
			if kind_of(id) == "persistencia":
				v *= float(buff_times.get(ExpeditionSkills.time_key(ability_of(id)), 0.0))
			if key != "" and v > 0.0:
				out[key] = float(out.get(key, 0.0)) + v
			continue
		var add: Dictionary = DATA[id].add
		for k in add:
			out[k] = float(out.get(k, 0.0)) + float(add[k]) * stacks
	return out


## Chave de run_mods de uma melhoria de habilidade ("ability_dmg:sword_vortex"...); "" se não é uma.
static func ability_mod_key(id: String) -> String:
	if not is_ability_upgrade(id):
		return ""
	var ab := ability_of(id)
	match kind_of(id):
		"potencia":
			return "ability_dmg:" + ExpeditionSkills.dmg_key(ab)
		"persistencia":
			return "ability_time:" + ExpeditionSkills.time_key(ab)
	return "ability_cd:" + ab


## `base` (um run_mods zerado) com as melhorias somadas por cima. Não mexe em `base`.
static func apply_to(base: Dictionary, taken: Dictionary, buff_times := {}) -> Dictionary:
	var out := base.duplicate()
	var add := total_mods(taken, buff_times)
	for k in add:
		out[k] = float(out.get(k, 0.0)) + float(add[k])
	return out


## Texto do nível na carta: "Nv 1/5" para a primeira, "Nv 3/5" para o terceiro acúmulo.
static func level_text(id: String, taken: Dictionary) -> String:
	return "Nv %d/%d" % [mini(int(taken.get(id, 0)) + 1, max_stacks(id)), max_stacks(id)]


## Valor da melhoria de habilidade com `stacks` acúmulos, para a carta: "+15% de dano", "-20% de recarga"...
static func value_text(id: String, stacks := 1) -> String:
	if not is_ability_upgrade(id):
		return ""
	var k: Dictionary = ABILITY_KINDS[kind_of(id)]
	return str(k.value) % roundi(float(k.add) * 100.0 * stacks)


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
	for kind in ABILITY_KINDS:
		var k: Dictionary = ABILITY_KINDS[kind]
		if str(k.get("label", "")) == "" or str(k.get("desc", "")) == "" or float(k.get("add", 0.0)) <= 0.0:
			out.append("melhoria de habilidade '%s' sem nome, descrição ou valor" % kind)
	var pooled := DATA.keys().filter(in_pool).size()
	if pooled < CHOICES:
		out.append("menos melhorias (%d) do que opções na recompensa (%d)" % [pooled, CHOICES])
	return out
