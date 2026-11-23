extends Node
## Banco de dados de itens, magias e missões (dados puros).
## As tabelas (ITEMS, CROPS, RECIPES, SPELLS, QUESTS, SHOP_STOCK, RARITY) moram em data/balance/*.json
## e são preenchidas pelo autoload Balance antes de qualquer _ready; aqui só ficam as `static var`.
## Campos de item (items.json): "class" sword (combo corpo a corpo, escala com FOR) · staff (projéteis
## mágicos, escala com INT) · bow (botão direito mira e puxa, esquerdo atira; escala com AGI); "shape" muda o modelo 3D;
## "two_handed" (espada) = montante: segura com as duas mãos, golpes lentos e largos, e a mão secundária fica vazia;
## "stats" = bônus do item (ver STAT_NAMES); "fx" = efeito ao acertar (slow, splash, pierce, multishot).

static var ITEMS: Dictionary = {}

## Culturas da horta. "time" = segundos para crescer sem regar (regada cresce 2x mais rápido).
static var CROPS: Dictionary = {}
const CROP_ORDER := ["carrot", "wheat", "tomato", "pepper", "mint", "pumpkin"]

## Receitas do caldeirão: comida -> ingredientes.
static var RECIPES: Dictionary = {}
const RECIPE_ORDER := ["bread", "carrot_stew", "spicy_soup", "dragon_chili", "mint_tea", "garden_salad", "pumpkin_pie", "valdoria_feast"]

## Habilidades de todas as armas. `slot` 1..SLOT_COUNT (tecla de mesmo número); o slot 4 é a ultimate.
## O slot 5 é opcional: o cetro (Julgamento de Luz), a espada com escudo (Grito do Bastião) e a montante (Fúria Picante,
## que sai da tecla 3 para a Dança do Abismo); a barra só o mostra para quem tem.
const SLOT_COUNT := 5
## `ready` = a habilidade já está implementada (fonte única; senão "Em breve"). `cost` é mana (0 = só recarga). `icon` é o desenho do IconPainter.
## `aim: "ground"` = a tecla só prepara: mostra o círculo de raio `aim_radius` no chão, a até `aim_range` m, e o
## clique esquerdo confirma (Player._arm_area / confirm_area).
const ABILITIES := {
	# a tecla 1 do cajado (a bola de fogo segue no clique do cajado). Dano, mana e ritmo: FlameChannelConfig
	"staff_flame": {"name": "Canalização de Fogo", "class": "staff", "slot": 1, "level": 1, "cooldown": 1.5, "cost": 8,
		"ready": true, "ultimate": false, "icon": "fireball", "desc": "Segure a tecla: o mago estende a mão livre, um círculo mágico de fogo se forma e gira na frente da palma, e dele irrompe uma labareda reta de 6,5 m. Cada inimigo na chama leva 4 + INT x 0,6 de dano de fogo 5 vezes por segundo. Gasta 14 de mana por segundo; ao soltar, o fogo se dissipa. Dá para andar devagar e virar com a câmera enquanto canaliza; a esquiva interrompe."},
	"frost_nova": {"name": "Nova Gélida", "class": "staff", "slot": 2, "level": 3, "cooldown": 7.0, "cost": 28,
		"ready": true, "ultimate": false, "icon": "frost", "desc": "Explosão de gelo ao redor: dano e lentidão."},
	"heal": {"name": "Cura", "class": "scepter", "slot": 1, "level": 1, "cooldown": 4.0, "cost": 20,
		"ready": true, "ultimate": false, "icon": "heal", "desc": "Prepara a cura: mire um aliado (ele ganha uma borda verde) e clique com o botão esquerdo para curá-lo; o botão direito cura você. Restaura 30 + INT x 4 de vida (mais o bônus de cura do cetro)."},
	"scepter_lance": {"name": "Lança de Luz", "class": "scepter", "slot": 2, "level": 2, "cooldown": 5.0, "cost": 15,
		"ready": true, "ultimate": false, "icon": "holy_lance", "desc": "Arremessa uma lança de luz sagrada no alvo mirado. Dano = 35 + INT x 4,5."},
	"scepter_ward": {"name": "Escudo de Luz", "class": "scepter", "slot": 3, "level": 3, "cooldown": 22.0, "cost": 30,
		"ready": true, "ultimate": false, "icon": "ward", "desc": "Por 12 s, em você e nos aliados a 8 m: +30 de vida máx., +4 de defesa e +3 de vida por segundo."},
	"scepter_judgment": {"name": "Julgamento de Luz", "class": "scepter", "slot": 5, "level": 5, "cooldown": 10.0, "cost": 28,
		"aim": "ground", "aim_range": 18.0, "aim_radius": 5.0,
		"ready": true, "ultimate": false, "icon": "radiant", "desc": "Prepara a área: a tecla mostra o círculo no chão (até 18 m), o clique esquerdo confirma. Uma coluna de luz cai ali: dano = 30 + INT x 3,5 e atordoa os inimigos a 5 m."},
	"scepter_ult": {"name": "Banquete do Herói", "class": "scepter", "slot": 4, "level": 8, "cooldown": 0.0, "cost": 0,
		"ready": true, "ultimate": true, "icon": "heal", "desc": "Ultimate: coluna de luz que cura por completo você e os aliados a 8 m e dá por 12 s +25% de dano, +12% de velocidade e -15% de recarga."},
	"staff_ember": {"name": "Bafo de Dragão", "class": "staff", "slot": 3, "level": 5, "cooldown": 30.0, "cost": 25,
		"ready": true, "ultimate": false, "icon": "ember", "desc": "Por 10 s: +20% de dano, +10% de crítico e -20% de recarga."},
	"meteor_rain": {"name": "Chuva de Meteoros", "class": "staff", "slot": 4, "level": 8, "cooldown": 0.0, "cost": 0,
		"ready": true, "ultimate": true, "icon": "fireball", "desc": "Ultimate: segure para canalizar uma chuva de meteoros sobre a área mirada."},
	"sword_charge": {"name": "Investida", "class": "sword", "slot": 1, "level": 1, "cooldown": 6.0, "cost": 0,
		"ready": true, "ultimate": false, "icon": "saber", "desc": "Avança sobre os inimigos à frente, causando dano."},
	# "offhand": só entra no kit com essa mão secundária, no lugar da habilidade do mesmo slot (ver kit())
	# "offhand": "two_handed" = com a montante nas mãos (Game.offhand_kind): troca a Investida na tecla 1
	"sword_spin": {"name": "Ciclone de Aço", "class": "sword", "offhand": "two_handed", "slot": 1, "level": 1, "cooldown": 9.0, "cost": 0,
		"ready": true, "ultimate": false, "icon": "cleaver", "desc": "Com a montante: aponta a espada para a frente, junta os pés e gira no próprio eixo, ganhando velocidade, com uma energia sombria seguindo o corte da espada enquanto gira. A lâmina varre tudo em volta (3,1 m): cada inimigo no alcance leva 0,35x o dano corpo a corpo a cada 0,35 s (cerca de 5x no giro todo, que dura 6 s) e é puxado para dentro dele. Depois o giro perde velocidade aos poucos até parar. Começa a girar assim que é acionada; dá para andar para qualquer lado enquanto gira (um pouco mais devagar) e a esquiva não cancela."},
	"sword_aegis": {"name": "Égide Cristalina", "class": "sword", "offhand": "shield", "slot": 1, "level": 1, "cooldown": 8.0, "cost": 0,
		"ready": true, "ultimate": false, "icon": "ward", "desc": "Com escudo: segure a tecla para fincar o escudo no chão (parado) e erguer uma coroa de placas de cristal em volta (cabe o grupo). Ao se formar ela empurra os monstros; até se partir nenhum monstro nem projétil entra, e os golpes nela gastam a integridade (70 + 9 por nível + 4 por defesa). Soltar a tecla desfaz a barreira. A recarga conta depois que ela acaba (mais longa se quebrar)."},
	# recarga: a do HammerConfig manda (cooldown_of); esta é só o valor padrão dela
	"sword_hammer": {"name": "Martelo de Energia", "class": "sword", "offhand": "shield", "slot": 4, "level": 3, "cooldown": 12.0, "cost": 0,
		"ready": true, "ultimate": false, "icon": "hammer", "desc": "Com escudo: ergue a espada e invoca um círculo mágico acima da cabeça; dele sai um martelo gigante de energia que cai à frente, causando dano em área (2,6x o dano corpo a corpo, raio de 7 m), atordoando e abrindo crateras pelo chão. Parado enquanto invoca; a esquiva antes da queda cancela."},
	"sword_quake": {"name": "Golpe Sísmico", "class": "sword", "slot": 2, "level": 3, "cooldown": 9.0, "cost": 0,
		"ready": true, "ultimate": false, "icon": "greatsword", "desc": "Golpe no chão: dano em área e atordoamento."},
	# recarga: a do EarthquakeConfig manda (cooldown_of); esta é só o valor padrão dela
	"sword_earthquake": {"name": "Terremoto Devastador", "class": "sword", "offhand": "shield", "slot": 2, "level": 3, "cooldown": 10.0, "cost": 0,
		"ready": true, "ultimate": false, "icon": "earthquake", "desc": "Com escudo: ergue o escudo e o bate com tudo no chão. Uma onda de choque circular corre pelo terreno até 4,5 m, rachando o chão, levantando placas de pedra e arremessando fragmentos; cada inimigo leva o golpe (2,2x o dano corpo a corpo) e fica atordoado quando a onda chega nele. Parado enquanto bate; a esquiva antes do escudo tocar o chão cancela."},
	# recarga: a do DarkTauntConfig manda (cooldown_of); esta é só o valor padrão dela
	"sword_taunt": {"name": "Círculo da Provocação Sombria", "class": "sword", "offhand": "shield", "slot": 3, "level": 5, "cooldown": 18.0, "cost": 0,
		"ready": true, "ultimate": false, "icon": "taunt", "desc": "Com escudo: o herói solta uma onda de energia sombria e um círculo mágico se desenha no chão em volta dele (raio de 6 m). Mãos sombrias saem do chão e agarram cada inimigo dentro dele, prendendo-os por 1,6 s; depois todos ficam provocados por 6 s, com olhos vermelhos sobre a cabeça: só perseguem e atacam você. Parado enquanto invoca; a esquiva antes das mãos agarrarem cancela."},
	# recarga: a do PartyShieldConfig manda (cooldown_of); esta é só o valor padrão dela. Slot 5: só com escudo (a
	# espada sem escudo não tem habilidade na tecla 5, e o kit() a acrescenta em vez de trocar alguma)
	"sword_rally": {"name": "Grito do Bastião", "class": "sword", "offhand": "shield", "slot": 5, "level": 6, "cooldown": 30.0, "cost": 0,
		"ready": true, "ultimate": false, "icon": "ward", "desc": "Com escudo: o herói reúne a energia numa aura azul e solta um grito de guerra. Ao terminar, todos do seu grupo por perto (até 30 m, você incluído) ganham o Bastião de Escudos por 15 s: pequenos escudos azuis giram em volta de cada um, dando +6 de defesa e +25% de defesa. Parado enquanto grita; a esquiva antes do grito terminar cancela."},
	# "offhand": "two_handed" = com a montante nas mãos (Game.offhand_kind): troca o Golpe Sísmico na tecla 2
	"sword_drag": {"name": "Corte do Abismo", "class": "sword", "offhand": "two_handed", "slot": 2, "level": 3, "cooldown": 9.0, "cost": 0,
		"ready": true, "ultimate": false, "icon": "greatsword", "desc": "Com a montante: solta a mão esquerda, desce a ponta da espada até o chão e dispara correndo, arrastando a lâmina atrás numa chuva de fagulhas, brasas e pedrinhas (até 7,5 m; para antes se chegar num inimigo ou numa parede). Então finca o pé e solta um corte violento de baixo para cima (1,6x o dano corpo a corpo no arco à frente, com empurrão), e três garras espectrais irrompem do chão em fila à frente (1,3x o dano corpo a corpo cada, atordoam). A esquiva durante a corrida cancela."},
	"sword_fury": {"name": "Fúria Picante", "class": "sword", "slot": 3, "level": 5, "cooldown": 28.0, "cost": 0,
		"ready": true, "ultimate": false, "icon": "fury", "desc": "Por 10 s: +30% de dano e cada abate cura 2."},
	# recarga: a do GreatswordDarkComboConfig manda (cooldown_of); esta é só o valor padrão dela.
	# "offhand": "two_handed" = com a montante nas mãos (Game.offhand_kind): troca a Fúria Picante na tecla 3 (a Fúria
	# vai para a tecla 5, sword_fury_great)
	"sword_dark_combo": {"name": "Dança do Abismo", "class": "sword", "offhand": "two_handed", "slot": 3, "level": 5, "cooldown": 12.0, "cost": 0,
		"ready": true, "ultimate": false, "icon": "greatsword", "desc": "Com a montante: um combo de quatro golpes envoltos em energia sombria, sempre começando pelo deslize. Escorrega de joelho para a frente e sobe girando num corte; gira o corpo inteiro num corte em volta; solta um corte rápido em diagonal; e avança girando até fechar num golpe de cima, que abre um anel de energia no chão e ergue garras sombrias em volta (atordoa). Cerca de 3,6x o dano corpo a corpo no combo inteiro, alcance de ~3 m em cada golpe. O herói anda com os golpes; a esquiva cancela a qualquer momento."},
	# a Fúria Picante na tecla 5 com a montante (a tecla 3 é da Dança do Abismo): o mesmo buff "sword_fury"
	# (SwordAbilities.FURY_IDS), só muda a tecla. Sem a montante ela fica de fora (é "offhand").
	"sword_fury_great": {"name": "Fúria Picante", "class": "sword", "offhand": "two_handed", "slot": 5, "level": 5, "cooldown": 28.0, "cost": 0,
		"ready": true, "ultimate": false, "icon": "fury", "desc": "Por 10 s: +30% de dano e cada abate cura 2."},
	"sword_whirl": {"name": "Turbilhão", "class": "sword", "slot": 4, "level": 8, "cooldown": 0.0, "cost": 0,
		"ready": true, "ultimate": true, "icon": "cleaver", "desc": "Ultimate: redemoinho de lâminas ao redor."},
	# "offhand": "two_handed" = com a montante nas mãos (Game.offhand_kind): troca o Turbilhão na tecla 4
	"sword_supreme": {"name": "Lâmina Suprema", "class": "sword", "offhand": "two_handed", "slot": 4, "level": 8, "cooldown": 0.0, "cost": 0,
		"ready": true, "ultimate": true, "icon": "greatsword", "desc": "Ultimate da montante: ergue a espada e fica parado enquanto uma energia sombria a cobre e vai crescendo (até cerca de 3x a sua altura); então a crava no chão à frente. Abre-se uma grande cratera em linha reta, de 3 m de largura, e almas saem voando de dentro dela, fugindo em todas as direções: 5x o dano corpo a corpo, atordoa e empurra quem está dentro da cratera ou no ponto do golpe. A esquiva durante a carga cancela."},
	"bow_triple": {"name": "Tiro Triplo", "class": "bow", "slot": 1, "level": 1, "cooldown": 5.0, "cost": 0,
		"ready": true, "ultimate": false, "icon": "bow", "desc": "Três flechas em leque."},
	"bow_frost": {"name": "Flecha Glacial", "class": "bow", "slot": 2, "level": 3, "cooldown": 8.0, "cost": 0,
		"ready": true, "ultimate": false, "icon": "frost", "desc": "Flecha de gelo: prende e atrasa o alvo atingido."},
	"bow_focus": {"name": "Olhos de Águia", "class": "bow", "slot": 3, "level": 5, "cooldown": 26.0, "cost": 0,
		"ready": true, "ultimate": false, "icon": "focus", "desc": "Por 10 s: +15% de crítico e +10% de velocidade."},
	"bow_gale": {"name": "Flecha do Vendaval", "class": "bow", "slot": 4, "level": 8, "cooldown": 0.0, "cost": 0,
		"ready": true, "ultimate": true, "icon": "bow", "desc": "Ultimate: o arqueiro agacha, tensiona e solta uma flecha que atravessa tudo em linha reta, rasgando o ar."},
}


## Recarga base (s) de uma habilidade, antes dos bônus. O Martelo de Energia, o Círculo da Provocação Sombria e o
## Terremoto Devastador leem a do recurso de configuração deles (editável no Inspector); as outras, a da tabela acima.
const COOLDOWN_CONFIGS := {
	"sword_hammer": "res://assets/vfx/hammer/hammer_config.tres",
	"sword_taunt": "res://assets/vfx/dark_taunt/dark_taunt_config.tres",
	"sword_earthquake": "res://assets/vfx/earthquake/earthquake_config.tres",
	"sword_rally": "res://assets/vfx/party_shield/party_shield_config.tres",
	"sword_dark_combo": "res://assets/vfx/greatsword_dark/greatsword_dark_combo_config.tres",
}


static func cooldown_of(id: String) -> float:
	if COOLDOWN_CONFIGS.has(id):
		var cfg: Resource = load(COOLDOWN_CONFIGS[id])
		if cfg != null:
			return float(cfg.get("cooldown"))
	return float(ABILITIES[id].cooldown) if ABILITIES.has(id) else 0.0


## Ids das habilidades de uma classe de arma, ordenados por slot. `offhand` = tipo da mão secundária
## ("shield", ou "" sem): uma habilidade com "offhand" igual troca a do mesmo slot (espada + escudo: a Égide
## Cristalina no lugar da Investida) ou, num slot que a arma não usa, entra a mais (o Grito do Bastião na tecla 5);
## sem a mão secundária certa ela fica de fora.
static func kit(cls: String, offhand := "") -> Array[String]:
	var ids: Array[String] = []
	var alt := {}
	for id in ABILITIES:
		if ABILITIES[id]["class"] != cls:
			continue
		var need: String = ABILITIES[id].get("offhand", "")
		if need == "":
			ids.append(id)
		elif need == offhand:
			alt[int(ABILITIES[id].slot)] = id
	for i in ids.size():
		var s := int(ABILITIES[ids[i]].slot)
		if alt.has(s):
			ids[i] = alt[s]
			alt.erase(s)
	# as da mão secundária num slot que a arma não tem (o Grito do Bastião na tecla 5) entram a mais
	for s in alt:
		ids.append(alt[s])
	ids.sort_custom(func(a: String, b: String) -> bool: return ABILITIES[a].slot < ABILITIES[b].slot)
	return ids


static var SPELLS: Dictionary = {}

static var QUESTS: Dictionary = {}

static var SHOP_STOCK: Array = []

# ---------------------------------------------------------------- equipamento
## Espaços de equipamento na ordem do "boneco" (esquerda de cima para baixo, depois direita; "back",
## capas e asas, fica sob o boneco).
const SLOTS := ["head", "amulet", "armor", "hands", "weapon", "offhand", "ring", "feet", "back", "pickaxe", "axe"]
## Espaços das ferramentas de coleta (não contam como equipamento de combate).
const TOOL_SLOTS := ["pickaxe", "axe"]
const SLOT_NAMES := {"weapon": "Arma", "offhand": "Mão secundária", "head": "Cabeça", "armor": "Peito",
	"hands": "Mãos", "feet": "Pés", "amulet": "Amuleto", "ring": "Anel", "back": "Costas", "pickaxe": "Picareta",
	"axe": "Machado"}
const CLASS_NAMES := {"sword": "Espada", "staff": "Cajado", "bow": "Arco", "scepter": "Cetro"}
const CLASS_HINT := {"sword": "Combo de 3 golpes · escala com Força",
	"staff": "Projéteis arcanos · escala com Inteligência",
	"bow": "Segure para tensionar, solte para atirar · escala com Agilidade",
	"scepter": "Cura aliados e castiga inimigos com luz sagrada · escala com Inteligência"}
const TWO_HAND_HINT := "Combo de 3 golpes lentos e largos com as duas mãos · escala com Força"
const FX_NAMES := {"slow": "Golpes deixam o alvo lento", "splash": "Projéteis explodem em área",
	"pierce": "Flechas perfuram inimigos", "multishot": "Disparo tensionado: 3 flechas",
	"vortex": "Disparo tensionado: fenda do Abismo que puxa e implode",
	"solar": "A 3ª flecha no mesmo alvo derruba uma coluna de sol",
	"dragonfire": "Disparo tensionado: chuva de flechas de fogo",
	"gale": "Flechas empurram; o disparo tensionado ricocheteia e o vento te lança para trás",
	"crescent": "Solte no instante da tensão máxima: crítico e flecha fantasma",
	"bramble": "Disparo tensionado: espinheiro que fere e prende; abates fazem nascer flores que curam"}

static var RARITY: Dictionary = {}
## Buffs (comida e habilidades): {id: {name, time, add, aura, icon, desc, color}}.
static var BUFFS: Dictionary = {}

## Bônus que os itens podem dar. [nome, formato] (formato "%" multiplica por 100).
const STAT_NAMES := {
	"str": ["Força", ""], "int": ["Inteligência", ""], "vit": ["Vitalidade", ""], "agi": ["Agilidade", ""],
	"hp": ["Vida máxima", ""], "mp": ["Mana máxima", ""], "spell": ["Poder mágico", ""],
	"crit": ["Chance de crítico", "%"], "speed": ["Velocidade", "%"], "cdr": ["Recarga de magias", "-%"],
	"leech": ["Roubo de vida", "%"],
}
const STAT_ORDER := ["str", "int", "vit", "agi", "hp", "mp", "spell", "crit", "speed", "cdr", "leech"]


func get_item(id: String) -> Dictionary:
	return ITEMS.get(id, {})


## A linha de poções de `base` (ela mesma + as com `potion_line` == base), da que cura menos para a que cura mais.
func potion_line(base: String) -> Array:
	var out: Array = [base]
	for id in ITEMS:
		if str(ITEMS[id].get("potion_line", "")) == base:
			out.append(id)
	out.sort_custom(func(a, b): return float(get_item(a).get("heal_hp", 0)) < float(get_item(b).get("heal_hp", 0)))
	return out


func is_stackable(id: String) -> bool:
	return get_item(id).get("stack", false)


## Espaço de equipamento do item ("" se não for equipável).
func slot_of(id: String) -> String:
	var it := get_item(id)
	match it.get("type", ""):
		"weapon":
			return "weapon"
		"armor":
			return "armor"
		"gear":
			return it.get("slot", "")
		"tool":
			return str(it.get("tool", ""))   # picareta e machado têm espaço próprio
	return ""


func is_equippable(id: String) -> bool:
	return slot_of(id) != ""


func weapon_class(id: String) -> String:
	return get_item(id).get("class", "sword") if id != "" else "sword"


## Arma de duas mãos (montante): ocupa a mão secundária também.
func is_two_handed(id: String) -> bool:
	return id != "" and bool(get_item(id).get("two_handed", false))


func rarity_of(id: String) -> String:
	var it := get_item(id)
	if it.has("rarity"):
		return it.rarity
	return "common"


func rarity_color(id: String) -> Color:
	return RARITY[rarity_of(id)].color


func item_stats(id: String) -> Dictionary:
	return get_item(id).get("stats", {})


func format_stat(k: String, v: float, signed := true) -> String:
	var fmt: String = STAT_NAMES[k][1]
	var nm: String = STAT_NAMES[k][0]
	if fmt == "%":
		return "%s%d%% %s" % ["+" if signed and v >= 0 else "", int(round(v * 100)), nm]
	if fmt == "-%":
		return "%s%d%% %s" % ["−" if v >= 0 else "+", int(round(abs(v) * 100)), nm]
	return "%s%d %s" % ["+" if signed and v >= 0 else "", int(round(v)), nm]


## Categoria usada pelos filtros do inventário e da loja.
func category(id: String) -> String:
	var t: String = get_item(id).get("type", "")
	if t in ["weapon", "armor", "gear", "tool"]:
		return "equip"
	if t in ["consumable", "food", "crop"]:
		return "use"
	return "misc"


## Pontuação simples para ordenar e comparar itens.
func power_score(id: String) -> float:
	var it := get_item(id)
	var s := float(it.get("damage", 0)) * 1.5 + float(it.get("defense", 0)) * 2.0
	var st := item_stats(id)
	for k in st:
		var v := float(st[k])
		s += v * (100.0 if STAT_NAMES[k][1] != "" else (0.25 if k in ["hp", "mp"] else 1.0))
	return s


## Linha da ferramenta de coleta: tipo, nível, força e o que a maestria faz.
func tool_text(id: String) -> String:
	var it := get_item(id)
	var kind := str(it.get("tool", ""))
	var pname := "Mineração" if kind == "pickaxe" else "Lenhador"   # sem autoload aqui (os testes compilam o ItemDB)
	return "%s nível %d — Força %.1f [F perto do recurso] · Maestria em %s aumenta força e ritmo" % [
		"Picareta" if kind == "pickaxe" else "Machado", int(it.get("tier", 1)), float(it.get("power", 1.0)), pname]


func item_summary(id: String) -> String:
	var it := get_item(id)
	if it.is_empty():
		return ""
	var lines: Array[String] = [it.name]
	match it.type:
		"weapon":
			lines.append("%s — Dano %d" % ["Montante (duas mãos)" if is_two_handed(id) else CLASS_NAMES[weapon_class(id)], it.damage])
		"armor", "gear":
			lines.append("%s — Defesa %d" % [SLOT_NAMES[slot_of(id)], it.get("defense", 0)])
		"consumable":
			lines.append("Consumível")
		"tool":
			lines.append(tool_text(id))
		"material":
			lines.append("Material de craft")
		"scroll":
			lines.append("Pergaminho de receita — use para aprender")
		"seed":
			var c: Dictionary = CROPS[it.crop]
			lines.append("Semente — %ds para crescer (regada: %ds) · rende %d–%d" % [
				int(c.time), int(c.time / 2.0), c.yield[0], c.yield[1]])
			if int(c.get("level", 1)) > 1:
				lines.append("Pede Fazenda nível %d para plantar" % int(c.level))
		"crop":
			lines.append("Colheita — ingrediente do caldeirão")
			var uses: Array[String] = []
			for r in RECIPE_ORDER:
				if RECIPES[r].has(id):
					uses.append(ITEMS[r].name)
			if not uses.is_empty():
				lines.append("Receitas: " + ", ".join(uses))
		"food":
			lines.append("Comida [Q] — " + food_effect_text(id))
	var st := item_stats(id)
	for k in STAT_ORDER:
		if st.has(k):
			lines.append(format_stat(k, float(st[k])))
	if it.has("fx"):
		lines.append(FX_NAMES[it.fx])
	if it.has("quality"):
		lines.append("Qualidade: %s" % ItemQuality.NAMES.get(it.quality, it.quality))
	if it.has("affix"):
		lines.append("Bônus de ofício: %s (já somado)" % format_stat(str(it.affix_stat), float(it.affix_value)))
	lines.append(it.desc)
	lines.append("Valor: %d ouro" % it.price)
	return "\n".join(lines)


## "Cura 60 · Vigor da Horta (90s): +30 de vida máxima..."
func food_effect_text(id: String) -> String:
	var it := get_item(id)
	var parts: Array[String] = []
	if it.get("heal_full", false):
		parts.append("Cura total")
	elif it.has("heal_hp"):
		parts.append("Cura %d" % it.heal_hp)
	if it.has("heal_mp"):
		parts.append("+%d mana" % it.heal_mp)
	var txt := " · ".join(parts)
	if it.has("buff"):
		var b: Dictionary = BUFFS.get(it.buff, {})
		if not b.is_empty():
			txt += ("\n" if txt != "" else "") + "%s (%ds): %s" % [b.name, int(b.time), b.desc]
	return txt
