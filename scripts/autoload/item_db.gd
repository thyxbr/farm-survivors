extends Node
## Banco de dados de itens, magias e missões (dados puros).

const ITEMS := {
	# ================================================================ ARMAS
	# "class": sword (combo corpo a corpo, escala com FOR) · staff (projéteis mágicos, escala com INT)
	#          bow (segure para tensionar e solte, escala com AGI). "shape" muda o modelo 3D.
	# "stats": bônus do item (ver STAT_NAMES). "fx": efeito ao acertar (slow, splash, pierce, multishot).
	# ---- espadas
	"wooden_sword": {"name": "Espada de Madeira", "type": "weapon", "class": "sword", "rarity": "common",
		"damage": 6, "price": 10, "color": Color(0.55, 0.38, 0.2), "shape": "wood",
		"desc": "Uma espada de treino. Melhor que nada."},
	"iron_sword": {"name": "Espada de Ferro", "type": "weapon", "class": "sword", "rarity": "common",
		"damage": 12, "price": 60, "color": Color(0.8, 0.82, 0.86),
		"desc": "Lâmina confiável forjada na vila."},
	"steel_saber": {"name": "Sabre de Aço", "type": "weapon", "class": "sword", "rarity": "uncommon",
		"damage": 16, "price": 110, "color": Color(0.85, 0.9, 0.95), "shape": "saber",
		"stats": {"agi": 2, "speed": 0.04}, "desc": "Leve e curvo. Feito para quem não para quieto."},
	"knight_blade": {"name": "Lâmina do Cavaleiro", "type": "weapon", "class": "sword", "rarity": "rare",
		"damage": 20, "price": 150, "color": Color(0.6, 0.8, 1.0), "glow": 0.6,
		"stats": {"str": 2, "vit": 1}, "desc": "Aço temperado com runas azuladas."},
	"frost_brand": {"name": "Marca Gélida", "type": "weapon", "class": "sword", "rarity": "rare",
		"damage": 23, "price": 240, "color": Color(0.55, 0.9, 1.0), "glow": 1.2, "fx": "slow",
		"stats": {"str": 2, "int": 2}, "desc": "O gelo da lâmina nunca derrete. Golpes deixam o alvo lento."},
	"goblin_cleaver": {"name": "Cutelo do Rei Goblin", "type": "weapon", "class": "sword", "rarity": "epic",
		"damage": 30, "price": 220, "color": Color(0.9, 0.35, 0.15), "glow": 0.6, "shape": "cleaver",
		"stats": {"str": 3, "crit": 0.05}, "desc": "Pesado, brutal e ainda quente de batalha."},
	"guardian_greatsword": {"name": "Montante do Guardião", "type": "weapon", "class": "sword", "rarity": "epic",
		"damage": 34, "price": 420, "color": Color(0.95, 0.85, 0.55), "glow": 0.5, "shape": "great",
		"stats": {"str": 4, "vit": 3, "hp": 25}, "desc": "Forjado para os guardiões das ruínas antigas."},
	"dragonfang": {"name": "Presa do Dragão", "type": "weapon", "class": "sword", "rarity": "legendary",
		"damage": 42, "price": 900, "color": Color(1.0, 0.4, 0.12), "glow": 2.0, "shape": "great",
		"stats": {"str": 5, "crit": 0.08, "leech": 0.04}, "desc": "Esculpida do dente de um dragão ancião. Cada golpe bebe vida."},
	# ---- espadas modeladas no Blender ("model" = assets/models/<model>.glb; "shape" só escolhe o ícone)
	"azure_edge": {"name": "Gume Celeste", "type": "weapon", "class": "sword", "rarity": "common",
		"damage": 8, "price": 20, "color": Color(0.33, 0.86, 0.96), "model": "w_azure_edge",
		"desc": "Lâmina leve de aço com fio azul-celeste. A primeira espada de todo aventureiro de Valdoria."},
	"thorn_root": {"name": "Espinho da Raiz", "type": "weapon", "class": "sword", "rarity": "common",
		"damage": 11, "price": 55, "color": Color(0.92, 0.9, 0.85), "model": "w_thorn_root",
		"stats": {"vit": 1}, "desc": "Osso afiado envolto em cipós que ainda crescem."},
	"venom_leaf": {"name": "Folha Peçonhenta", "type": "weapon", "class": "sword", "rarity": "uncommon",
		"damage": 15, "price": 100, "color": Color(0.8, 0.83, 0.23), "model": "w_venom_leaf",
		"stats": {"agi": 2}, "desc": "Folha de metal serrilhada que arde ao corte."},
	"crimson_reed": {"name": "Junco Carmesim", "type": "weapon", "class": "sword", "rarity": "uncommon",
		"damage": 15, "price": 120, "color": Color(0.86, 0.3, 0.36), "shape": "saber", "model": "w_crimson_reed",
		"stats": {"agi": 2, "speed": 0.05}, "desc": "Fina como um junco e rápida como o vento do rio."},
	"amber_fang": {"name": "Presa de Âmbar", "type": "weapon", "class": "sword", "rarity": "uncommon",
		"damage": 17, "price": 130, "color": Color(0.95, 0.64, 0.26), "shape": "saber", "model": "w_amber_fang",
		"stats": {"str": 1, "crit": 0.03}, "desc": "Lâmina cor de âmbar presa num cabo cheio de espinhos."},
	"rose_flame": {"name": "Chama Rosada", "type": "weapon", "class": "sword", "rarity": "rare",
		"damage": 21, "price": 190, "color": Color(0.93, 0.3, 0.62), "glow": 0.4, "model": "w_rose_flame",
		"stats": {"str": 2, "crit": 0.04}, "desc": "Labaredas rosadas congeladas no aço."},
	"crystal_frost": {"name": "Lâmina de Cristal", "type": "weapon", "class": "sword", "rarity": "rare",
		"damage": 22, "price": 230, "color": Color(0.66, 0.93, 0.91), "glow": 0.6, "fx": "slow", "model": "w_crystal_frost",
		"stats": {"int": 2, "str": 1}, "desc": "Cristal de gelo lapidado. Golpes deixam o alvo lento."},
	"moon_crescent": {"name": "Crescente Lunar", "type": "weapon", "class": "sword", "rarity": "rare",
		"damage": 22, "price": 220, "color": Color(0.78, 0.8, 0.84), "shape": "saber", "model": "w_moon_crescent",
		"stats": {"agi": 3, "crit": 0.04}, "desc": "Curva como a lua nova, com um coração de quartzo rosa."},
	"neon_edge": {"name": "Lâmina Neon", "type": "weapon", "class": "sword", "rarity": "rare",
		"damage": 24, "price": 260, "color": Color(0.19, 0.86, 0.92), "glow": 0.8, "model": "w_neon_edge",
		"stats": {"str": 2, "speed": 0.05}, "desc": "Relíquia de uma era esquecida. O fio ainda zumbe."},
	"pale_crescent": {"name": "Foice Pálida", "type": "weapon", "class": "sword", "rarity": "epic",
		"damage": 30, "price": 360, "color": Color(0.87, 0.89, 0.93), "shape": "saber", "model": "w_pale_crescent",
		"stats": {"agi": 3, "crit": 0.07}, "desc": "Lâmina em gancho com guarda de anel. Colhe o que ousa chegar perto."},
	"coral_spine": {"name": "Espinha Coral", "type": "weapon", "class": "sword", "rarity": "epic",
		"damage": 31, "price": 380, "color": Color(0.85, 0.24, 0.61), "glow": 0.4, "model": "w_coral_spine",
		"stats": {"str": 3, "crit": 0.06}, "desc": "Crista serrilhada de coral do fundo do mar."},
	"scarlet_talon": {"name": "Garra Escarlate", "type": "weapon", "class": "sword", "rarity": "epic",
		"damage": 32, "price": 410, "color": Color(0.92, 0.35, 0.18), "glow": 0.5, "shape": "cleaver",
		"model": "w_scarlet_talon", "stats": {"str": 3, "leech": 0.03}, "desc": "Garra curva de uma fera escarlate. Bebe um pouco de cada ferida."},
	"titan_cleaver": {"name": "Cutelo do Titã", "type": "weapon", "class": "sword", "rarity": "epic",
		"damage": 33, "price": 400, "color": Color(0.78, 0.8, 0.83), "shape": "cleaver", "model": "w_titan_cleaver",
		"stats": {"str": 4, "hp": 30}, "desc": "Uma placa de aço que só um titã chamaria de espada."},
	"ivory_wing": {"name": "Asa de Marfim", "type": "weapon", "class": "sword", "rarity": "legendary",
		"damage": 44, "price": 950, "color": Color(0.95, 0.95, 0.93), "glow": 0.3, "shape": "great", "model": "w_ivory_wing",
		"stats": {"str": 4, "vit": 3, "hp": 30}, "desc": "Montante branco com guarda de penas. Leve como uma asa."},
	"royal_wings": {"name": "Asa Real", "type": "weapon", "class": "sword", "rarity": "legendary",
		"damage": 46, "price": 1000, "color": Color(0.89, 0.22, 0.44), "glow": 1.0, "shape": "great", "model": "w_royal_wings",
		"stats": {"str": 5, "crit": 0.06, "leech": 0.03}, "desc": "Espada dos antigos reis, com asas de ouro e um núcleo que pulsa."},
	# ---- cajados
	"apprentice_staff": {"name": "Cajado de Aprendiz", "type": "weapon", "class": "staff", "rarity": "common",
		"damage": 8, "price": 30, "color": Color(0.55, 0.75, 1.0), "wood": Color(0.5, 0.34, 0.18),
		"stats": {"spell": 3, "mp": 10}, "desc": "Dispara faíscas arcanas. Ninguém nasce arquimago."},
	"oak_staff": {"name": "Cajado de Carvalho Antigo", "type": "weapon", "class": "staff", "rarity": "uncommon",
		"damage": 13, "price": 100, "color": Color(0.5, 1.0, 0.55), "wood": Color(0.38, 0.26, 0.14),
		"stats": {"int": 2, "spell": 6}, "desc": "Talhado de um carvalho que viu mil invernos."},
	"ember_staff": {"name": "Cajado das Brasas", "type": "weapon", "class": "staff", "rarity": "rare",
		"damage": 18, "price": 220, "color": Color(1.0, 0.45, 0.1), "wood": Color(0.22, 0.12, 0.08), "fx": "splash",
		"stats": {"int": 3, "spell": 10}, "desc": "Os projéteis explodem e queimam em área."},
	"frost_scepter": {"name": "Cetro da Geada", "type": "weapon", "class": "staff", "rarity": "rare",
		"damage": 17, "price": 220, "color": Color(0.6, 0.92, 1.0), "wood": Color(0.75, 0.82, 0.9), "fx": "slow",
		"stats": {"int": 3, "spell": 10, "mp": 15}, "desc": "Cristal de gelo eterno. Os projéteis deixam inimigos lentos."},
	"archmage_staff": {"name": "Cajado do Arquimago", "type": "weapon", "class": "staff", "rarity": "legendary",
		"damage": 30, "price": 950, "color": Color(0.85, 0.5, 1.0), "wood": Color(0.15, 0.1, 0.2), "fx": "splash",
		"stats": {"int": 6, "spell": 20, "mp": 40, "cdr": 0.15}, "desc": "Pertenceu ao último arquimago de Valdoria."},
	# ---- arcos
	"short_bow": {"name": "Arco Curto", "type": "weapon", "class": "bow", "rarity": "common",
		"damage": 9, "price": 30, "color": Color(0.6, 0.42, 0.22),
		"desc": "Simples, mas atira longe. Segure o ataque para tensionar."},
	"hunter_bow": {"name": "Arco do Caçador", "type": "weapon", "class": "bow", "rarity": "uncommon",
		"damage": 15, "price": 100, "color": Color(0.45, 0.3, 0.16),
		"stats": {"agi": 2}, "desc": "Teixo curado na fumaça. O favorito dos caçadores da vila."},
	"elven_bow": {"name": "Arco Élfico", "type": "weapon", "class": "bow", "rarity": "rare",
		"damage": 21, "price": 240, "color": Color(0.85, 0.9, 0.7), "glow": 0.4,
		"stats": {"agi": 4, "crit": 0.06}, "desc": "Leve como uma folha. Flechas tensionadas atravessam inimigos."},
	"goblin_warbow": {"name": "Arco de Guerra Goblin", "type": "weapon", "class": "bow", "rarity": "epic",
		"damage": 27, "price": 380, "color": Color(0.5, 0.55, 0.2), "fx": "pierce",
		"stats": {"str": 2, "agi": 3, "crit": 0.04}, "desc": "Feio, torto e mortal. Toda flecha perfura."},
	"storm_bow": {"name": "Arco da Tempestade", "type": "weapon", "class": "bow", "rarity": "legendary",
		"damage": 34, "price": 950, "color": Color(0.55, 0.75, 1.0), "glow": 1.6, "fx": "multishot",
		"stats": {"agi": 6, "crit": 0.1, "speed": 0.05}, "desc": "Disparos tensionados liberam três flechas de relâmpago."},

	# ================================================================ ARMADURAS (peito)
	"leather_armor": {"name": "Armadura de Couro", "type": "armor", "rarity": "common", "defense": 3, "price": 40,
		"color": Color(0.45, 0.28, 0.13), "style": "a_leather", "color2": Color(0.2, 0.12, 0.06), "pants": Color(0.3, 0.24, 0.18), "desc": "Couro curtido. Leve e flexível."},
	"chain_mail": {"name": "Cota de Malha", "type": "armor", "rarity": "uncommon", "defense": 7, "price": 120,
		"color": Color(0.55, 0.58, 0.65), "metal": true, "stats": {"vit": 1}, "style": "a_mail", "pants": Color(0.26, 0.24, 0.23), "desc": "Anéis de aço entrelaçados."},
	"mage_robe": {"name": "Manto Arcano", "type": "armor", "rarity": "rare", "defense": 3, "price": 200,
		"color": Color(0.3, 0.25, 0.65), "stats": {"int": 4, "mp": 30}, "style": "a_robe", "color2": Color(0.17, 0.13, 0.38), "pants": Color(0.2, 0.18, 0.25), "desc": "Bordado com fios que brilham na escuridão."},
	"ranger_vest": {"name": "Gibão do Patrulheiro", "type": "armor", "rarity": "rare", "defense": 6, "price": 200,
		"color": Color(0.25, 0.4, 0.22), "stats": {"agi": 4, "crit": 0.03}, "style": "a_leather", "color2": Color(0.24, 0.16, 0.08), "pants": Color(0.3, 0.25, 0.17), "desc": "Couro reforçado em tons de floresta."},
	"royal_plate": {"name": "Placas Reais", "type": "armor", "rarity": "epic", "defense": 12, "price": 300,
		"color": Color(0.85, 0.7, 0.35), "metal": true, "stats": {"vit": 3, "hp": 20}, "desc": "Armadura de placas digna de um herói."},
	"traveler_tunic": {"name": "Túnica de Viajante", "type": "armor", "rarity": "common", "defense": 2, "price": 30,
		"color": Color(0.55, 0.16, 0.13), "color2": Color(0.18, 0.3, 0.22), "pants": Color(0.36, 0.28, 0.2),
		"style": "a_tunic", "stats": {"agi": 1}, "desc": "Lã grossa em duas cores, com bandoleira e bolsa."},
	"guard_surcoat": {"name": "Sobreveste da Guarda", "type": "armor", "rarity": "rare", "defense": 9, "price": 260,
		"color": Color(0.9, 0.87, 0.78), "color2": Color(0.64, 0.13, 0.16), "pants": Color(0.22, 0.2, 0.2),
		"style": "a_surcoat", "cape": true, "stats": {"vit": 2, "str": 2},
		"desc": "Cota de malha sob o tabardo com a cruz da guarda de Valdoria."},
	"dragon_plate": {"name": "Couraça de Escamas de Dragão", "type": "armor", "rarity": "legendary", "defense": 17,
		"price": 1000, "color": Color(0.6, 0.12, 0.1), "metal": true, "glow": 0.4,
		"stats": {"vit": 5, "str": 2, "hp": 40}, "desc": "Escamas que nem o fogo atravessa."},

	# ================================================================ EQUIPAMENTOS (outros espaços)
	# ---- cabeça
	"leather_cap": {"name": "Capuz de Couro", "type": "gear", "slot": "head", "rarity": "common", "defense": 1, "price": 25,
		"color": Color(0.45, 0.3, 0.15), "style": "h_cap", "desc": "Protege do sol e de pedradas leves."},
	"iron_helm": {"name": "Elmo de Ferro", "type": "gear", "slot": "head", "rarity": "uncommon", "defense": 3, "price": 90,
		"color": Color(0.7, 0.72, 0.78), "metal": true, "stats": {"hp": 10}, "style": "h_nasal", "desc": "Amassado em alguns lugares. Ainda funciona."},
	"wizard_hat": {"name": "Chapéu do Mago", "type": "gear", "slot": "head", "rarity": "rare", "defense": 1, "price": 180,
		"color": Color(0.3, 0.22, 0.6), "stats": {"int": 3, "mp": 20}, "style": "h_wizard", "color2": Color(0.92, 0.74, 0.3), "desc": "Pontudo como deve ser."},
	"ranger_hood": {"name": "Capuz do Patrulheiro", "type": "gear", "slot": "head", "rarity": "rare", "defense": 2, "price": 180,
		"color": Color(0.22, 0.38, 0.2), "stats": {"agi": 3, "crit": 0.03}, "style": "h_hood", "desc": "Some na folhagem."},
	"knight_helm": {"name": "Elmo do Cavaleiro", "type": "gear", "slot": "head", "rarity": "epic", "defense": 5, "price": 320,
		"color": Color(0.85, 0.7, 0.35), "metal": true, "stats": {"vit": 2, "str": 2}, "desc": "Penacho vermelho, viseira dourada."},
	"wool_hood": {"name": "Capuz de Lã", "type": "gear", "slot": "head", "rarity": "common", "defense": 1, "price": 20,
		"color": Color(0.46, 0.34, 0.22), "style": "h_hood", "desc": "Quente e simples. Cheira a ovelha."},
	"kettle_hat": {"name": "Chapéu de Ferro", "type": "gear", "slot": "head", "rarity": "uncommon", "defense": 3,
		"price": 85, "color": Color(0.6, 0.63, 0.68), "metal": true, "style": "h_kettle", "stats": {"vit": 1},
		"desc": "Aba larga sobre cota de malha. Flechas escorregam."},
	"guard_greathelm": {"name": "Elmo Fechado da Guarda", "type": "gear", "slot": "head", "rarity": "epic", "defense": 6,
		"price": 340, "color": Color(0.62, 0.65, 0.7), "color2": Color(0.95, 0.75, 0.3), "metal": true,
		"style": "h_great", "stats": {"vit": 3, "hp": 15}, "desc": "Fenda estreita, cruz dourada. Ninguém vê seu medo."},
	# ---- mãos
	"leather_gloves": {"name": "Luvas de Couro", "type": "gear", "slot": "hands", "rarity": "common", "defense": 1, "price": 20,
		"color": Color(0.42, 0.28, 0.14), "style": "g_gloves", "desc": "Evita bolhas no cabo da espada."},
	"iron_gauntlets": {"name": "Manoplas de Ferro", "type": "gear", "slot": "hands", "rarity": "uncommon", "defense": 2, "price": 80,
		"color": Color(0.65, 0.67, 0.72), "metal": true, "stats": {"str": 2}, "desc": "Socos que doem dos dois lados."},
	"archer_bracers": {"name": "Braçadeiras do Arqueiro", "type": "gear", "slot": "hands", "rarity": "uncommon", "defense": 1, "price": 80,
		"color": Color(0.35, 0.45, 0.25), "stats": {"agi": 2, "crit": 0.03}, "style": "g_bracers", "color2": Color(0.24, 0.15, 0.08), "desc": "A corda do arco nunca mais vai arder."},
	"spellweaver_gloves": {"name": "Luvas do Tecelão", "type": "gear", "slot": "hands", "rarity": "rare", "defense": 1, "price": 170,
		"color": Color(0.5, 0.3, 0.7), "stats": {"int": 2, "cdr": 0.06}, "style": "g_gloves", "color2": Color(0.85, 0.68, 0.3), "desc": "Os dedos tecem runas mais rápido."},
	# ---- pés
	"leather_boots": {"name": "Botas de Couro", "type": "gear", "slot": "feet", "rarity": "common", "defense": 1, "price": 25,
		"color": Color(0.4, 0.26, 0.13), "stats": {"speed": 0.03}, "style": "f_boots", "desc": "Confortáveis para longas caminhadas."},
	"iron_greaves": {"name": "Grevas de Ferro", "type": "gear", "slot": "feet", "rarity": "uncommon", "defense": 3, "price": 90,
		"color": Color(0.65, 0.67, 0.72), "metal": true, "stats": {"vit": 1}, "desc": "Barulhentas, mas resistentes."},
	"swift_boots": {"name": "Botas Velozes", "type": "gear", "slot": "feet", "rarity": "rare", "defense": 1, "price": 200,
		"color": Color(0.3, 0.75, 0.85), "glow": 0.4, "stats": {"agi": 2, "speed": 0.08}, "style": "f_boots", "color2": Color(0.9, 0.85, 0.7), "desc": "Asas bordadas no calcanhar."},
	"reinforced_boots": {"name": "Botas Reforçadas", "type": "gear", "slot": "feet", "rarity": "uncommon", "defense": 2,
		"price": 70, "color": Color(0.38, 0.25, 0.13), "color2": Color(0.66, 0.69, 0.75), "style": "f_plated",
		"stats": {"vit": 1}, "desc": "Couro com greva e biqueira de aço."},
	# ---- mão secundária (escudo exige espada, orbe exige cajado, aljava exige arco)
	"wooden_shield": {"name": "Escudo de Madeira", "type": "gear", "slot": "offhand", "needs": "sword", "rarity": "common",
		"defense": 2, "price": 30, "color": Color(0.5, 0.34, 0.18), "desc": "Tábuas e pregos. Segura uma pancada ou duas."},
	"knight_shield": {"name": "Escudo do Cavaleiro", "type": "gear", "slot": "offhand", "needs": "sword", "rarity": "rare",
		"defense": 5, "price": 190, "color": Color(0.64, 0.13, 0.16), "stats": {"vit": 2}, "desc": "O brasão da guarda de Valdoria."},
	"arcane_orb": {"name": "Orbe Arcano", "type": "gear", "slot": "offhand", "needs": "staff", "rarity": "uncommon",
		"price": 110, "color": Color(0.6, 0.45, 1.0), "glow": 2.0, "stats": {"spell": 6, "mp": 20},
		"desc": "Flutua sobre a mão. Exige um cajado."},
	"hunter_quiver": {"name": "Aljava do Caçador", "type": "gear", "slot": "offhand", "needs": "bow", "rarity": "uncommon",
		"price": 110, "color": Color(0.45, 0.28, 0.12), "stats": {"agi": 2, "crit": 0.04},
		"desc": "Penas bem aparadas voam mais retas. Exige um arco."},
	# ---- acessórios
	"life_amulet": {"name": "Amuleto da Vida", "type": "gear", "slot": "amulet", "rarity": "uncommon", "price": 120,
		"color": Color(1.0, 0.35, 0.35), "stats": {"vit": 1, "hp": 30}, "desc": "Pulsa no ritmo do coração."},
	"sage_amulet": {"name": "Amuleto do Sábio", "type": "gear", "slot": "amulet", "rarity": "rare", "price": 220,
		"color": Color(0.4, 0.6, 1.0), "stats": {"int": 3, "mp": 25, "cdr": 0.05}, "desc": "Sussurra fórmulas esquecidas."},
	"strength_ring": {"name": "Anel da Força", "type": "gear", "slot": "ring", "rarity": "uncommon", "price": 110,
		"color": Color(1.0, 0.55, 0.3), "stats": {"str": 3}, "desc": "Um rubi bruto num aro de ferro."},
	"wind_ring": {"name": "Anel do Vento", "type": "gear", "slot": "ring", "rarity": "uncommon", "price": 110,
		"color": Color(0.6, 1.0, 0.8), "stats": {"agi": 2, "speed": 0.05}, "desc": "Sempre parece haver uma brisa."},
	"vampire_ring": {"name": "Anel do Vampiro", "type": "gear", "slot": "ring", "rarity": "epic", "price": 400,
		"color": Color(0.75, 0.05, 0.15), "stats": {"leech": 0.05, "crit": 0.03}, "desc": "Frio ao toque. Cada golpe devolve um pouco de vida."},
	"health_potion": {"name": "Poção de Vida", "type": "consumable", "heal_hp": 60, "price": 15,
		"stack": true, "desc": "Restaura 60 de vida."},
	"mana_potion": {"name": "Poção de Mana", "type": "consumable", "heal_mp": 40, "price": 15,
		"stack": true, "desc": "Restaura 40 de mana."},
	"slime_gel": {"name": "Gel de Slime", "type": "material", "price": 4, "stack": true,
		"desc": "Gosmento. Os mercadores pagam por isso."},
	"goblin_ear": {"name": "Orelha de Goblin", "type": "material", "price": 8, "stack": true,
		"desc": "Prova de caça. Eca."},
	"goblin_crown": {"name": "Coroa do Rei Goblin", "type": "material", "price": 150, "stack": true,
		"desc": "Ouro sujo, mas ainda é ouro."},

	# ---------------------------------------------------------------- horta: sementes
	"seed_carrot": {"name": "Semente de Cenoura", "type": "seed", "crop": "carrot", "price": 4, "stack": true,
		"desc": "Cresce rápido. Base de ensopados e saladas."},
	"seed_wheat": {"name": "Semente de Trigo", "type": "seed", "crop": "wheat", "price": 4, "stack": true,
		"desc": "Rende bastante. Vira pão e massa de torta."},
	"seed_tomato": {"name": "Semente de Tomate", "type": "seed", "crop": "tomato", "price": 6, "stack": true,
		"desc": "Suculento. Vai bem em sopas."},
	"seed_pepper": {"name": "Semente de Pimenta-de-Fogo", "type": "seed", "crop": "pepper", "price": 10, "stack": true,
		"desc": "Dizem que um goblin chorou só de cheirar."},
	"seed_mint": {"name": "Semente de Menta Gélida", "type": "seed", "crop": "mint", "price": 10, "stack": true,
		"desc": "Folhas que brilham frias ao luar."},
	"seed_pumpkin": {"name": "Semente de Abóbora", "type": "seed", "crop": "pumpkin", "price": 14, "stack": true,
		"desc": "Demora, mas cresce enorme."},

	# ---------------------------------------------------------------- horta: colheitas (comíveis cruas)
	"carrot": {"name": "Cenoura", "type": "crop", "price": 6, "stack": true, "raw_hp": 12,
		"desc": "Crocante. Crua cura 12 de vida."},
	"wheat": {"name": "Trigo", "type": "crop", "price": 5, "stack": true,
		"desc": "Não dá para comer assim. Leve ao caldeirão."},
	"tomato": {"name": "Tomate", "type": "crop", "price": 8, "stack": true, "raw_hp": 15,
		"desc": "Cru cura 15 de vida."},
	"pepper": {"name": "Pimenta-de-Fogo", "type": "crop", "price": 12, "stack": true, "raw_hp": 5,
		"desc": "Crua cura 5 de vida... e queima a língua."},
	"mint": {"name": "Menta Gélida", "type": "crop", "price": 12, "stack": true, "raw_mp": 15,
		"desc": "Mastigar restaura 15 de mana."},
	"pumpkin": {"name": "Abóbora", "type": "crop", "price": 24, "stack": true, "raw_hp": 30,
		"desc": "Enorme. Crua cura 30 de vida."},

	# ---------------------------------------------------------------- horta: comidas (caldeirão)
	"bread": {"name": "Pão Rústico", "type": "food", "price": 18, "stack": true, "heal_hp": 35,
		"buff": {"name": "Barriga Cheia", "time": 60.0, "add": {"regen": 1.5}, "desc": "+1,5 de vida por segundo"},
		"color": Color(0.9, 0.7, 0.4), "desc": "Simples e honesto."},
	"carrot_stew": {"name": "Ensopado de Cenoura", "type": "food", "price": 30, "stack": true, "heal_hp": 60,
		"buff": {"name": "Vigor da Horta", "time": 90.0, "add": {"max_hp_flat": 30.0, "defense": 2.0}, "desc": "+30 de vida máxima e +2 de defesa"},
		"color": Color(1.0, 0.55, 0.2), "desc": "Receita da avó do Bram."},
	"spicy_soup": {"name": "Sopa Picante", "type": "food", "price": 40, "stack": true, "heal_hp": 30,
		"buff": {"name": "Fúria Picante", "time": 45.0, "add": {"damage": 0.3}, "desc": "+30% de dano"},
		"color": Color(1.0, 0.3, 0.15), "desc": "Esquenta o sangue."},
	"dragon_chili": {"name": "Chili do Dragão", "type": "food", "price": 45, "stack": true, "heal_hp": 20,
		"special": "fire_nova",
		"buff": {"name": "Bafo de Dragão", "time": 30.0, "add": {"damage": 0.2, "crit": 0.1}, "desc": "+20% de dano e +10% de crítico"},
		"color": Color(1.0, 0.4, 0.05), "desc": "Ao comer: explosão de fogo ao seu redor!"},
	"mint_tea": {"name": "Chá de Menta Gélida", "type": "food", "price": 30, "stack": true, "heal_mp": 40,
		"special": "frost_nova",
		"buff": {"name": "Mente Fresca", "time": 60.0, "add": {"cooldown": -0.2, "speed": 0.1}, "desc": "−20% de recarga e +10% de velocidade"},
		"color": Color(0.5, 0.95, 1.0), "desc": "Ao comer: congela os inimigos próximos."},
	"garden_salad": {"name": "Salada da Horta", "type": "food", "price": 36, "stack": true, "heal_hp": 40,
		"buff": {"name": "Olhos de Águia", "time": 90.0, "add": {"xp": 0.3, "magnet": 0.6}, "desc": "+30% de XP das gemas e +60% de raio de coleta"},
		"color": Color(0.5, 1.0, 0.45), "desc": "Fresquinha. Ótima para subir de nível na Horda."},
	"pumpkin_pie": {"name": "Torta de Abóbora", "type": "food", "price": 55, "stack": true, "heal_hp": 120,
		"buff": {"name": "Casca Dura", "time": 90.0, "add": {"defense": 5.0, "lifesteal": 2.0}, "desc": "+5 de defesa e cada abate cura 2"},
		"color": Color(1.0, 0.6, 0.15), "desc": "Pesada, quentinha e reconfortante."},
	"valdoria_feast": {"name": "Banquete de Valdoria", "type": "food", "price": 120, "stack": true, "heal_full": true,
		"buff": {"name": "Banquete do Herói", "time": 120.0,
			"add": {"damage": 0.25, "max_hp_flat": 40.0, "speed": 0.12, "gold": 0.4, "cooldown": -0.15},
			"desc": "+25% de dano, +40 de vida máx., +12% de velocidade, −15% de recarga, +40% de ouro"},
		"color": Color(1.0, 0.85, 0.3), "desc": "Cura total. Um prato digno de lenda."},
}

## Culturas da horta. "time" = segundos para crescer sem regar (regada cresce 2x mais rápido).
const CROPS := {
	"carrot": {"name": "Cenoura", "seed": "seed_carrot", "time": 40.0, "yield": [2, 3], "color": Color(1.0, 0.5, 0.1)},
	"wheat": {"name": "Trigo", "seed": "seed_wheat", "time": 50.0, "yield": [3, 4], "color": Color(0.95, 0.8, 0.3)},
	"tomato": {"name": "Tomate", "seed": "seed_tomato", "time": 65.0, "yield": [2, 4], "color": Color(0.9, 0.12, 0.08)},
	"pepper": {"name": "Pimenta-de-Fogo", "seed": "seed_pepper", "time": 80.0, "yield": [2, 3], "color": Color(1.0, 0.22, 0.04)},
	"mint": {"name": "Menta Gélida", "seed": "seed_mint", "time": 80.0, "yield": [2, 3], "color": Color(0.45, 0.95, 1.0)},
	"pumpkin": {"name": "Abóbora", "seed": "seed_pumpkin", "time": 110.0, "yield": [1, 2], "color": Color(1.0, 0.52, 0.08)},
}
const CROP_ORDER := ["carrot", "wheat", "tomato", "pepper", "mint", "pumpkin"]

## Receitas do caldeirão: comida -> ingredientes.
const RECIPES := {
	"bread": {"wheat": 2},
	"carrot_stew": {"carrot": 2, "tomato": 1},
	"spicy_soup": {"tomato": 2, "pepper": 1},
	"dragon_chili": {"pepper": 2, "carrot": 1},
	"mint_tea": {"mint": 2},
	"garden_salad": {"carrot": 1, "tomato": 1, "mint": 1},
	"pumpkin_pie": {"pumpkin": 1, "wheat": 2},
	"valdoria_feast": {"pumpkin": 1, "pepper": 1, "mint": 1, "wheat": 1, "tomato": 1},
}
const RECIPE_ORDER := ["bread", "carrot_stew", "spicy_soup", "dragon_chili", "mint_tea", "garden_salad", "pumpkin_pie", "valdoria_feast"]

const SPELLS := {
	"fireball": {"name": "Bola de Fogo", "key": "1", "cost": 12, "level": 1, "cooldown": 0.9,
		"desc": "Projétil flamejante. Dano = 18 + INT x 2.5"},
	"heal": {"name": "Cura", "key": "2", "cost": 20, "level": 2, "cooldown": 4.0,
		"desc": "Restaura 30 + INT x 4 de vida."},
	"frost_nova": {"name": "Nova Gélida", "key": "3", "cost": 28, "level": 4, "cooldown": 7.0,
		"desc": "Explosão de gelo ao redor: dano e lentidão."},
}

const QUESTS := {
	"slimes": {
		"name": "Praga Gosmenta",
		"giver": "Ancião Bram",
		"desc": "Os slimes estão devorando as plantações ao norte da vila. Derrote 5 deles.",
		"target": "slime", "count": 5,
		"reward_xp": 120, "reward_gold": 50, "reward_items": {"health_potion": 3},
	},
	"goblins": {
		"name": "Batedores Goblins",
		"giver": "Ancião Bram",
		"desc": "Goblins acamparam na floresta a leste. Derrote 4 batedores.",
		"target": "goblin", "count": 4,
		"reward_xp": 250, "reward_gold": 80, "reward_items": {"chain_mail": 1},
	},
	"goblin_king": {
		"name": "O Rei das Ruínas",
		"giver": "Ancião Bram",
		"desc": "O Rei Goblin comanda tudo das ruínas antigas ao norte. Acabe com ele.",
		"target": "goblin_king", "count": 1,
		"reward_xp": 600, "reward_gold": 300, "reward_items": {"royal_plate": 1},
	},
}

const SHOP_STOCK := ["health_potion", "mana_potion",
	"iron_sword", "steel_saber", "knight_blade",
	# as 15 espadas modeladas no Blender (assets/models/w_*.glb), em ordem de preço
	"azure_edge", "thorn_root", "venom_leaf", "crimson_reed", "amber_fang", "rose_flame", "moon_crescent",
	"crystal_frost", "neon_edge", "pale_crescent", "coral_spine", "titan_cleaver", "scarlet_talon", "ivory_wing",
	"royal_wings",
	"apprentice_staff", "oak_staff", "short_bow", "hunter_bow",
	"traveler_tunic", "leather_armor", "chain_mail", "wool_hood", "leather_cap", "kettle_hat", "iron_helm", "leather_gloves", "iron_gauntlets", "archer_bracers",
	"leather_boots", "reinforced_boots", "iron_greaves", "wooden_shield", "arcane_orb", "hunter_quiver", "life_amulet", "strength_ring", "wind_ring"]

# ---------------------------------------------------------------- equipamento
## Espaços de equipamento na ordem do "boneco" (esquerda de cima para baixo, depois direita).
const SLOTS := ["head", "amulet", "armor", "hands", "weapon", "offhand", "ring", "feet"]
const SLOT_NAMES := {"weapon": "Arma", "offhand": "Mão secundária", "head": "Cabeça", "armor": "Peito",
	"hands": "Mãos", "feet": "Pés", "amulet": "Amuleto", "ring": "Anel"}
const CLASS_NAMES := {"sword": "Espada", "staff": "Cajado", "bow": "Arco"}
const CLASS_HINT := {"sword": "Combo de 3 golpes · escala com Força",
	"staff": "Projéteis arcanos · escala com Inteligência",
	"bow": "Segure para tensionar, solte para atirar · escala com Agilidade"}
const FX_NAMES := {"slow": "Golpes deixam o alvo lento", "splash": "Projéteis explodem em área",
	"pierce": "Flechas perfuram inimigos", "multishot": "Disparo tensionado: 3 flechas"}

const RARITY := {
	"common": {"name": "Comum", "color": Color(0.85, 0.85, 0.82), "rank": 0},
	"uncommon": {"name": "Incomum", "color": Color(0.38, 0.9, 0.38), "rank": 1},
	"rare": {"name": "Raro", "color": Color(0.35, 0.62, 1.0), "rank": 2},
	"epic": {"name": "Épico", "color": Color(0.74, 0.42, 1.0), "rank": 3},
	"legendary": {"name": "Lendário", "color": Color(1.0, 0.6, 0.15), "rank": 4},
}

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
	return ""


func is_equippable(id: String) -> bool:
	return slot_of(id) != ""


func weapon_class(id: String) -> String:
	return get_item(id).get("class", "sword") if id != "" else "sword"


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
	if t in ["weapon", "armor", "gear"]:
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


func item_summary(id: String) -> String:
	var it := get_item(id)
	if it.is_empty():
		return ""
	var lines: Array[String] = [it.name]
	match it.type:
		"weapon":
			lines.append("%s — Dano %d" % [CLASS_NAMES[weapon_class(id)], it.damage])
		"armor", "gear":
			lines.append("%s — Defesa %d" % [SLOT_NAMES[slot_of(id)], it.get("defense", 0)])
		"consumable":
			lines.append("Consumível")
		"material":
			lines.append("Material")
		"seed":
			var c: Dictionary = CROPS[it.crop]
			lines.append("Semente — %ds para crescer (regada: %ds) · rende %d–%d" % [
				int(c.time), int(c.time / 2.0), c.yield[0], c.yield[1]])
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
		var b: Dictionary = it.buff
		txt += ("\n" if txt != "" else "") + "%s (%ds): %s" % [b.name, int(b.time), b.desc]
	return txt
