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
## Chaves de Game.run_mods que as melhorias podem somar (validate confere). As da segunda linha são da identidade
## das classes (ExpeditionClasses): só as bênçãos de classe e as passivas mexem nelas, e quem lê cada uma é:
##   regen             -> Game.hp_regen()             lifesteal   -> expedition_mode (cura por abate)
##   crowd_guard       -> Player.take_damage (Linha de Frente)
##   block_power/guard -> Player.take_damage (bloqueio com o escudo: dano segurado / fôlego poupado)
##   aegis_integrity   -> ShieldAbilities.use         aegis_burst -> ShieldAbilities._on_end (Estilhaços)
##   taunt_time        -> DarkTauntAbilities._on_captured
##   stun_bonus        -> EarthquakeAbilities / HammerAbilities (segundos a mais de atordoamento)
##   guard_dmg         -> Game.melee_damage (dano por ponto de defesa)
## e as do Ímpeto do Guerreiro (ExpeditionMomentum; estado em Game.momentum):
##   momentum_max      -> teto de acúmulos (0 = sem Ímpeto)   momentum_dmg/speed/crit -> Game (por acúmulo)
##   momentum_hold     -> segundos a mais antes de esvaziar    momentum_kill -> Ímpeto a mais por abate
##   momentum_stamina  -> fôlego por ganho                    momentum_heal -> vida por ganho
##   momentum_guard    -> Player.take_damage (corte por acúmulo)
##   momentum_burst    -> Player._do_hit (Explosão de Ímpeto no 3º golpe com o Ímpeto cheio)
##   momentum_charge   -> SwordAbilities (Investida que acerta)  momentum_fury -> SwordAbilities (Fúria Picante)
const RUN_MOD_KEYS := ["damage", "max_hp", "defense", "speed", "cdr",
	"regen", "lifesteal", "crowd_guard", "block_power", "block_guard", "aegis_integrity", "aegis_burst",
	"taunt_time", "stun_bonus", "guard_dmg",
	"momentum_max", "momentum_dmg", "momentum_speed", "momentum_hold", "momentum_kill", "momentum_stamina",
	"momentum_heal", "momentum_guard", "momentum_crit", "momentum_burst", "momentum_charge", "momentum_fury"]
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
## Bênçãos de classe (ExpeditionClasses): "class" = só saem para essa classe (e nunca no sorteio comum);
## "style" = estilo de build da carta; "needs" = só saem com pelo menos uma dessas habilidades levada dos altares;
## "max" = acúmulos máximos (senão MAX_STACKS).
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
	# ---------------------------------------------------------------- Tank (ExpeditionClasses)
	# defesa
	"muralha_viva": {
		"name": "Muralha Viva",
		"desc": "Linha de Frente: +2% de redução de dano por inimigo perto (teto de 40%).",
		"add": {"crowd_guard": 0.02},
		"icon": "armadura", "color": Color(0.55, 0.68, 0.9), "class": "tank", "style": "defesa", "max": 3,
	},
	"teimosia": {
		"name": "Teimosia de Pedra",
		"desc": "+1,5 de vida por segundo: quanto mais longa a luta, mais o Tank aguenta.",
		"add": {"regen": 1.5},
		"icon": "vigor", "color": Color(0.5, 0.85, 0.6), "class": "tank", "style": "defesa", "max": 3,
	},
	# escudo
	"guarda_ferro": {
		"name": "Guarda de Ferro",
		"desc": "Bloqueio (botão direito): o escudo segura +10% do golpe e gasta 20% menos fôlego.",
		"add": {"block_power": 0.10, "block_guard": 0.20},
		"icon": "armadura", "color": Color(0.7, 0.75, 0.82), "class": "tank", "style": "escudo", "max": 3,
	},
	"egide_reforcada": {
		"name": "Égide Reforçada",
		"desc": "+35% de integridade da Égide Cristalina.",
		"add": {"aegis_integrity": 0.35},
		"icon": "armadura", "color": Color(0.55, 0.85, 1.0), "class": "tank", "style": "escudo", "max": 3,
		"needs": ["sword_aegis"],
	},
	"estilhacos": {
		"name": "Estilhaços da Égide",
		"desc": "Ao desfazer ou quebrar, a Égide explode: inimigos a 4,5 m levam 60% do dano que ela segurou e são empurrados.",
		"add": {"aegis_burst": 0.6},
		"icon": "poder", "color": Color(0.45, 0.8, 1.0), "class": "tank", "style": "escudo", "max": 3,
		"needs": ["sword_aegis"],
	},
	# controle
	"correntes": {
		"name": "Correntes do Abismo",
		"desc": "Círculo da Provocação: +35% de tempo preso pelas mãos e provocado.",
		"add": {"taunt_time": 0.35},
		"icon": "celeridade", "color": Color(0.7, 0.45, 0.95), "class": "tank", "style": "controle", "max": 3,
		"needs": ["sword_taunt"],
	},
	"abalo": {
		"name": "Abalo Persistente",
		"desc": "Terremoto Devastador e Martelo de Energia: +0,5 s de atordoamento.",
		"add": {"stun_bonus": 0.5},
		"icon": "poder", "color": Color(0.85, 0.7, 0.45), "class": "tank", "style": "controle", "max": 3,
		"needs": ["sword_earthquake", "sword_hammer"],
	},
	# ataque
	"revide": {
		"name": "Revide do Bastião",
		"desc": "+1% de dano em ataques e habilidades por ponto de defesa.",
		"add": {"guard_dmg": 0.01},
		"icon": "poder", "color": Color(0.95, 0.55, 0.35), "class": "tank", "style": "ataque", "max": 3,
	},
	"sede": {
		"name": "Sede da Muralha",
		"desc": "Cada inimigo abatido cura 4 de vida.",
		"add": {"lifesteal": 4.0},
		"icon": "vigor", "color": Color(0.9, 0.35, 0.4), "class": "tank", "style": "ataque", "max": 3,
	},
	# ---------------------------------------------------------------- Guerreiro (Ímpeto, ExpeditionMomentum)
	# agressivo
	"golpes_encadeados": {
		"name": "Golpes Encadeados",
		"desc": "Ímpeto: +1 acúmulo máximo e +1% de dano por acúmulo.",
		"add": {"momentum_max": 1.0, "momentum_dmg": 0.01},
		"icon": "poder", "color": Color(1.0, 0.5, 0.25), "class": "warrior", "style": "agressivo", "max": 2,
	},
	"pressao_implacavel": {
		"name": "Pressão Implacável",
		"desc": "O Ímpeto leva +1 s a mais para começar a se esvair.",
		"add": {"momentum_hold": 1.0},
		"icon": "celeridade", "color": Color(1.0, 0.62, 0.3), "class": "warrior", "style": "agressivo", "max": 2,
	},
	"lamina_faminta": {
		"name": "Lâmina Faminta",
		"desc": "Cada abate dá +1 de Ímpeto a mais.",
		"add": {"momentum_kill": 1.0},
		"icon": "poder", "color": Color(0.95, 0.35, 0.25), "class": "warrior", "style": "agressivo", "max": 2,
	},
	# veloz
	"passo_lobo": {
		"name": "Passo do Lobo",
		"desc": "+1,2% de velocidade de movimento por acúmulo de Ímpeto (teto de 25%): cole no próximo alvo.",
		"add": {"momentum_speed": 0.012},
		"icon": "botas", "color": Color(0.55, 0.9, 1.0), "class": "warrior", "style": "veloz", "max": 3,
	},
	"folego_batalha": {
		"name": "Fôlego de Batalha",
		"desc": "Cada Ímpeto ganho devolve 3 de fôlego: mais golpes e esquivas sem parar.",
		"add": {"momentum_stamina": 3.0},
		"icon": "celeridade", "color": Color(0.6, 0.95, 0.75), "class": "warrior", "style": "veloz", "max": 2,
	},
	"investida_predadora": {
		"name": "Investida Predadora",
		"desc": "A Investida que acerta alguém dá +2 de Ímpeto: avance sobre o próximo grupo sem perder o embalo.",
		"add": {"momentum_charge": 2.0},
		"icon": "botas", "color": Color(1.0, 0.85, 0.5), "class": "warrior", "style": "veloz", "max": 2,
		"needs": ["sword_charge"],
	},
	# resistente
	"sangue_brasa": {
		"name": "Sangue em Brasa",
		"desc": "Cada Ímpeto ganho cura 0,8 de vida: quem não para de bater não cai.",
		"add": {"momentum_heal": 0.8},
		"icon": "vigor", "color": Color(0.95, 0.4, 0.35), "class": "warrior", "style": "resistente", "max": 3,
	},
	"couraca_embalo": {
		"name": "Couraça do Embalo",
		"desc": "-2% de dano recebido por acúmulo de Ímpeto (teto de 20%).",
		"add": {"momentum_guard": 0.02},
		"icon": "armadura", "color": Color(0.8, 0.6, 0.45), "class": "warrior", "style": "resistente", "max": 2,
	},
	# explosivo
	"explosao_impeto": {
		"name": "Explosão de Ímpeto",
		"desc": "Com o Ímpeto cheio, o 3º golpe do combo solta tudo: explosão de 3,5 m com 90% do dano corpo a corpo e empurrão. O Ímpeto volta a zero.",
		"add": {"momentum_burst": 0.9},
		"icon": "poder", "color": Color(1.0, 0.45, 0.15), "class": "warrior", "style": "explosivo", "max": 3,
	},
	"brecha": {
		"name": "Brecha",
		"desc": "+2% de chance de crítico por acúmulo de Ímpeto (teto de 20%).",
		"add": {"momentum_crit": 0.02},
		"icon": "poder", "color": Color(1.0, 0.8, 0.35), "class": "warrior", "style": "explosivo", "max": 2,
	},
	"furia_desperta": {
		"name": "Fúria Desperta",
		"desc": "Fúria Picante enche o Ímpeto na hora e o segura enquanto dura.",
		"add": {"momentum_fury": 1.0},
		"icon": "poder", "color": Color(0.95, 0.3, 0.2), "class": "warrior", "style": "explosivo", "max": 1,
		"needs": ["sword_fury", "sword_fury_great"],
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
	if is_ability_upgrade(id):
		return ABILITY_MAX_STACKS
	return int(DATA.get(id, {}).get("max", MAX_STACKS))


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


## Entra no sorteio comum das bênçãos (as de evento, "pool": false, e as de classe não).
static func in_pool(id: String) -> bool:
	return DATA.has(id) and bool(DATA[id].get("pool", true)) and class_of(id) == ""


## Classe de uma bênção de classe ("" para as comuns).
static func class_of(id: String) -> String:
	return str(DATA.get(id, {}).get("class", ""))


## Estilo de build de uma bênção de classe ("defesa", "escudo"...; "" para as comuns).
static func style_of(id: String) -> String:
	return str(DATA.get(id, {}).get("style", ""))


## "Tank · Escudo" para uma bênção de classe; "" para as comuns e as melhorias de habilidade.
static func style_text(id: String) -> String:
	return ExpeditionClasses.style_text(class_of(id), style_of(id))


## Bênção de classe que pode sair para a classe `cls` com as habilidades `skills` (as levadas dos altares): é da
## classe e, se pede habilidades ("needs"), pelo menos uma delas já foi levada.
static func in_class_pool(id: String, cls: String, skills: Array) -> bool:
	if cls == "" or class_of(id) != cls or not bool(DATA[id].get("pool", true)):
		return false
	var needs: Array = DATA[id].get("needs", [])
	if needs.is_empty():
		return true
	for s in needs:
		if skills.has(s):
			return true
	return false


## Sorteia até `n` melhorias diferentes do sorteio que ainda não chegaram ao máximo. Com o mesmo `rng` (mesma semente)
## sai a mesma lista. Vazia só se todas estiverem no máximo.
## `ctx` (opcional) = {"class": id da classe, "skills": habilidades levadas}: com uma classe que tem bênçãos
## (ExpeditionClasses), elas entram no sorteio e a primeira opção é sempre uma delas (se houver alguma possível),
## para a build da classe aparecer em toda escolha. Sem `ctx` o sorteio é o comum, igual ao de antes.
static func roll(rng: RandomNumberGenerator, taken: Dictionary, n := CHOICES, ctx := {}) -> Array[String]:
	var pool: Array[String] = []
	for id in DATA:
		if in_pool(id) and can_take(id, taken):
			pool.append(id)
	pool.sort()   # ordem estável antes de sortear (independe da ordem do dicionário)
	var out: Array[String] = []
	var cls := str(ctx.get("class", ""))
	if cls != "":
		var skills: Array = ctx.get("skills", [])
		var cpool: Array[String] = []
		for id in DATA:
			if in_class_pool(id, cls, skills) and can_take(id, taken):
				cpool.append(id)
		cpool.sort()
		if not cpool.is_empty() and n > 0:
			out.append(cpool.pop_at(rng.randi_range(0, cpool.size() - 1)))
		pool.append_array(cpool)
		pool.sort()
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
		var cls := str(d.get("class", ""))
		if cls != "" and not ExpeditionClasses.has_identity(cls):
			out.append("melhoria '%s' é de uma classe sem identidade na expedição ('%s')" % [id, cls])
		if d.has("style") and not ExpeditionClasses.STYLES.has(str(d.style)):
			out.append("melhoria '%s' com estilo desconhecido '%s'" % [id, str(d.style)])
		for s in d.get("needs", []):
			if not ItemDB.ABILITIES.has(str(s)):
				out.append("melhoria '%s' pede a habilidade '%s', que não existe" % [id, str(s)])
		if int(d.get("max", MAX_STACKS)) < 1:
			out.append("melhoria '%s' com máximo de acúmulos inválido" % id)
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
