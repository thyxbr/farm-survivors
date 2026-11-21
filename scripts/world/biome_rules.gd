class_name BiomeRules
extends RefCounted
## Bioma de cada mapa (puro, sem autoload): cor do chão e do capim, o que nasce no meio do capim, a serra em volta
## (rocha, mata, neve e as árvores da encosta), o céu, a névoa, o sol e o clima. O Vale é o padrão; os mapas de
## viagem trocam tudo para ficarem com cara própria:
##   bosque = Pântano Sussurrante: lama e capim escuro, juncos e cogumelos, névoa verde e água no chão;
##   mina   = Geleira de Cristal: neve cobrindo tudo, nevando sempre, céu claro e frio, pinheiros congelados;
##   pico   = Vulcão das Cinzas: chão de cinza e basalto, sem capim, cinza caindo, céu vermelho e névoa escura.
## As dungeons usam o bioma do mapa de onde se entra.
##
## Cores em sRGB (como no Inspector). Quem lê: ground.gd (chão, capim, serra), WeatherFX (céu, névoa, sol e clima).

const VALE := {
	"grass": [Color(0.2, 0.37, 0.13), Color(0.37, 0.55, 0.2), Color(0.16, 0.42, 0.14), Color(0.55, 0.55, 0.26)],
	"plants": {"fern": "fern", "bush": "bush", "bush_berry": "bush_berry"},
	"flowers": true,
	"ring_grass": [Color(0.27, 0.45, 0.16), Color(0.2, 0.37, 0.13)],
	"ring_wood": Color(0.16, 0.3, 0.14),
	"ring_rock": [Color(0.47, 0.44, 0.4), Color(0.33, 0.31, 0.3)],
	"ring_snow": [Color(0.9, 0.92, 0.96), Color(0.78, 0.82, 0.9)],
	"snow_line": 0.62,
	"ring_trees": {"tree_fir": 0.65, "tree_pine": 0.35},
	"ring_tint": Color(1, 1, 1, 0),
	"autumn": true,   # o outono pinta folhas e grama (sem folhas caindo na neve nem na cinza)
}

const DATA := {
	"bosque": {
		"name": "pântano",
		"grass": [Color(0.17, 0.24, 0.1), Color(0.3, 0.36, 0.15), Color(0.13, 0.26, 0.13), Color(0.36, 0.33, 0.18)],
		"plants": {"fern": "reeds", "bush": "fern", "bush_berry": "mushrooms"},
		"flowers": false,
		"ring_grass": [Color(0.22, 0.28, 0.13), Color(0.17, 0.22, 0.11)],
		"ring_wood": Color(0.12, 0.18, 0.1),
		"ring_rock": [Color(0.36, 0.35, 0.3), Color(0.25, 0.25, 0.22)],
		"ring_snow": [],
		"snow_line": 9.0,
		"ring_trees": {"tree_swamp": 0.55, "tree_dead": 0.15, "tree_fir": 0.3},
		"ring_tint": Color(1, 1, 1, 0),
		"sky_top": Color(0.42, 0.5, 0.46), "sky_hz": Color(0.66, 0.72, 0.6), "ground_hz": Color(0.5, 0.56, 0.45),
		"fog": Color(0.5, 0.6, 0.46), "fog_density": 0.012,
		"sun": 0.8, "sun_color": Color(0.95, 0.95, 0.78), "ambient": 1.05, "saturation": 0.92,
		# clima: sempre úmido (poças), nunca neva
		"weather": {"wet_min": 0.55, "no_snow": true},
		"motes": "fireflies",
	},
	"mina": {
		"name": "geleira",
		"grass": [Color(0.62, 0.7, 0.74), Color(0.78, 0.85, 0.88), Color(0.55, 0.66, 0.72), Color(0.8, 0.8, 0.78)],
		"plants": {},
		"flowers": false,
		"ring_grass": [Color(0.82, 0.87, 0.93), Color(0.72, 0.79, 0.88)],
		"ring_wood": Color(0.2, 0.32, 0.3),
		"ring_rock": [Color(0.44, 0.5, 0.58), Color(0.32, 0.37, 0.46)],
		"ring_snow": [Color(0.93, 0.95, 0.99), Color(0.8, 0.86, 0.95)],
		"snow_line": 0.25,
		"ring_trees": {"tree_frost": 0.6, "tree_fir": 0.4},
		"ring_tint": Color(1, 1, 1, 0),
		"sky_top": Color(0.42, 0.6, 0.86), "sky_hz": Color(0.86, 0.92, 0.98), "ground_hz": Color(0.82, 0.88, 0.95),
		"fog": Color(0.82, 0.88, 0.96), "fog_density": 0.004,
		"sun": 1.0, "sun_color": Color(0.92, 0.96, 1.0), "ambient": 1.15, "saturation": 1.0,
		# clima: neve cobrindo o chão sempre e nevando, nunca chove
		"weather": {"cover": 1.0, "snow_min": 0.45, "no_rain": true},
		"autumn": false,
		"motes": "",
	},
	"pico": {
		"name": "vulcão",
		"grass": [Color(0.17, 0.15, 0.14), Color(0.27, 0.24, 0.22), Color(0.13, 0.12, 0.12), Color(0.33, 0.27, 0.22)],
		"plants": {},
		"flowers": false,
		"ring_grass": [Color(0.2, 0.18, 0.17), Color(0.15, 0.13, 0.13)],
		"ring_wood": Color(0.11, 0.1, 0.1),
		"ring_rock": [Color(0.24, 0.21, 0.2), Color(0.15, 0.13, 0.13)],
		"ring_snow": [],
		"snow_line": 9.0,
		"ring_trees": {"tree_dead": 1.0},
		"ring_tint": Color(1, 1, 1, 0),
		"sky_top": Color(0.32, 0.12, 0.1), "sky_hz": Color(0.85, 0.42, 0.22), "ground_hz": Color(0.4, 0.2, 0.14),
		"fog": Color(0.5, 0.3, 0.22), "fog_density": 0.007,
		"sun": 1.15, "sun_color": Color(1.0, 0.74, 0.52), "ambient": 1.35, "saturation": 1.05,
		# clima: seco, sem chuva nem neve (cinza caindo e brasas no lugar)
		"weather": {"no_rain": true, "no_snow": true, "cloud_min": 0.15},
		"autumn": false,
		"motes": "ash",
	},
}


## Debaixo da terra (dungeons): sem sol nem céu, névoa preta que engole o que está a uns 15 m, pouca luz
## ambiente (quem ilumina são as tochas e os braseiros), sem clima.
const UNDERGROUND := {
	"sky_top": Color(0.02, 0.02, 0.025), "sky_hz": Color(0.035, 0.03, 0.035), "ground_hz": Color(0.03, 0.025, 0.03),
	"fog": Color(0.025, 0.02, 0.025), "fog_density": 0.085,
	"sun": 0.0, "sun_color": Color(1, 1, 1), "ambient": 0.6, "saturation": 0.95, "rim": 0.2,
	"autumn": false, "motes": "dust",
}
## Cor da névoa de cada dungeon: verde podre no Covil, azul gelado nas Galerias, brasa na Cripta, sangue no Abismo.
const DUNGEON_FOG := {"dg_bosque": Color(0.035, 0.05, 0.03), "dg_mina": Color(0.03, 0.04, 0.06),
	"dg_pico": Color(0.07, 0.03, 0.02), "dg_final": Color(0.07, 0.015, 0.03)}


## Céu, névoa, luz e partículas do lugar `map_id`: o bioma nos mapas, debaixo da terra nas dungeons.
static func atmo(map_id: String) -> Dictionary:
	if Regions.is_dungeon(map_id):
		var u := UNDERGROUND.duplicate()
		u.fog = DUNGEON_FOG.get(map_id, u.fog)
		u.sky_hz = (u.fog as Color) * 1.2
		return u
	return of(map_id) if has_sky(map_id) else {}


## Bioma do mapa `map_id` (dungeon: o do mapa de fora). Sem bioma próprio: o Vale.
static func of(map_id: String) -> Dictionary:
	var id := str(Regions.DATA.get(map_id, {}).get("parent", map_id))
	var d: Dictionary = VALE.duplicate()
	d.merge(DATA.get(id, {}), true)
	return d


## Tem céu/clima próprio (o Vale e a Arena usam o de sempre).
static func has_sky(map_id: String) -> bool:
	return of(map_id).has("sky_top")


## Clima do jogo `s` (Weather.state) passado pelo bioma: o pântano fica sempre úmido, a geleira coberta de neve
## e nevando, o vulcão seco. Devolve uma cópia.
static func weather(map_id: String, s: Dictionary) -> Dictionary:
	var o := s.duplicate()
	if Regions.is_dungeon(map_id):   # debaixo da terra: nada de chuva, neve, poça nem vento
		for k in ["rain", "snow", "cover", "wet", "cloud", "wind"]:
			o[k] = 0.0
		return o
	var w: Dictionary = of(map_id).get("weather", {})
	if w.is_empty():
		return o
	if w.get("no_rain", false):
		o.rain = 0.0
		o.wet = minf(float(o.get("wet", 0.0)), 0.1)
	if w.get("no_snow", false):
		o.snow = 0.0
		o.cover = 0.0
	if w.has("wet_min"):
		o.wet = maxf(float(o.get("wet", 0.0)), float(w.wet_min))
	if w.has("cover"):
		o.cover = float(w.cover)
	if w.has("snow_min"):
		o.snow = maxf(float(o.get("snow", 0.0)), float(w.snow_min))
		o.cloud = maxf(float(o.get("cloud", 0.0)), 0.35)
	if w.has("cloud_min"):
		o.cloud = maxf(float(o.get("cloud", 0.0)), float(w.cloud_min))
	return o
