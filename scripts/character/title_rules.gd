class_name TitleRules
extends RefCounted
## Títulos do personagem: aparecem acima do nome (em cima da cabeça, para todos) e na ficha (C).
## Cada título se libera por progresso que já fica gravado no personagem (nível, rank da guilda,
## recordes da Horda e da Cidade). O título escolhido fica em flags["title"] ("" = sem título).
## Regras puras (sem autoload): o servidor/solo valida o pedido e o cliente lista os liberados.

## id -> {"name", "desc", "level"?, "rank"?, "horde"? (rodada), "city"? (noites), "bestiary"? (família)}. A ordem é a da lista.
const TITLES := {
	"recem_chegado": {"name": "Recém-chegado", "desc": "Chegou a Valdoria."},
	"aventureiro": {"name": "Aventureiro", "desc": "Alcance o nível 10.", "level": 10},
	"veterano": {"name": "Veterano", "desc": "Alcance o nível 25.", "level": 25},
	"lenda_valdoria": {"name": "Lenda de Valdoria", "desc": "Alcance o nível 50.", "level": 50},
	"membro_guilda": {"name": "Membro da Guilda", "desc": "Chegue ao rank C da guilda.", "rank": "C"},
	"lamina_guilda": {"name": "Lâmina da Guilda", "desc": "Chegue ao rank B da guilda.", "rank": "B"},
	"campeao_guilda": {"name": "Campeão da Guilda", "desc": "Chegue ao rank A da guilda.", "rank": "A"},
	"mito_guilda": {"name": "Mito da Guilda", "desc": "Chegue ao rank S da guilda.", "rank": "S"},
	"sobrevivente": {"name": "Sobrevivente da Horda", "desc": "Passe da rodada 10 do Desafio da Horda.", "horde": 10},
	"flagelo_horda": {"name": "Flagelo da Horda", "desc": "Passe da rodada 25 do Desafio da Horda.", "horde": 25},
	"guardiao_noite": {"name": "Guardião da Noite", "desc": "Defenda a cidade por 10 noites.", "city": 10},
	# bestiário (BestiaryRules grava flags["bst_<família>"] quando a família fica completa)
	"flagelo_slimes": {"name": "Flagelo dos Slimes", "desc": "Complete os Slimes no Bestiário.", "bestiary": "slimes"},
	"terror_goblins": {"name": "Terror dos Goblins", "desc": "Complete os Goblins no Bestiário.", "bestiary": "goblins"},
	"exorcista": {"name": "Exorcista", "desc": "Complete os Mortos-vivos no Bestiário.", "bestiary": "mortos"},
	"cacador_vale": {"name": "Caçador do Vale", "desc": "Complete as Feras do Vale no Bestiário.", "bestiary": "feras"},
	"rato_caverna": {"name": "Rato de Caverna", "desc": "Complete as Cavernas no Bestiário.", "bestiary": "cavernas"},
	"lobo_gelo": {"name": "Lobo do Gelo", "desc": "Complete as Terras Geladas no Bestiário.", "bestiary": "gelo"},
	"matador_chefes": {"name": "Matador de Chefes", "desc": "Complete os Chefes no Bestiário.", "bestiary": "chefes"},
	"mestre_bestiario": {"name": "Mestre do Bestiário", "desc": "Complete o Bestiário inteiro.", "bestiary": "all"},
}

const RANKS := ["D", "C", "B", "A", "S"]


## O título `id` está liberado para quem tem esse nível e essas flags (rank, horde_best, city_best)?
static func is_unlocked(id: String, level: int, flags: Dictionary) -> bool:
	if not TITLES.has(id):
		return false
	var t: Dictionary = TITLES[id]
	if level < int(t.get("level", 0)):
		return false
	if t.has("rank") and RANKS.find(str(flags.get("rank", "D"))) < RANKS.find(str(t.rank)):
		return false
	if t.has("horde") and horde_round(flags) < int(t.horde):
		return false
	if t.has("city") and int(flags.get("city_best", 0)) < int(t.city):
		return false
	if t.has("bestiary") and not flags.get("bst_" + str(t.bestiary), false):
		return false
	return true


## Ids liberados, na ordem de TITLES.
static func unlocked(level: int, flags: Dictionary) -> Array:
	var out: Array = []
	for id in TITLES:
		if is_unlocked(id, level, flags):
			out.append(id)
	return out


## Melhor rodada da Horda gravada (o recorde é {"round", ...}; gravações antigas guardavam só o número).
static func horde_round(flags: Dictionary) -> int:
	var b = flags.get("horde_best", 0)
	if b is Dictionary:
		return int(b.get("round", 0))
	return int(b) if (b is int or b is float) else 0


## Nome mostrado do título `id` ("" para sem título ou id desconhecido).
static func label(id: String) -> String:
	return str(TITLES[id].name) if TITLES.has(id) else ""


## Título escolhido que ainda vale (id), ou "" se nenhum ou se deixou de valer.
static func current(level: int, flags: Dictionary) -> String:
	var id := str(flags.get("title", ""))
	return id if is_unlocked(id, level, flags) else ""


## Op "set_title": escolhe o título `id` ("" tira o título). Só títulos liberados.
static func set_title(s: CharState, id: String) -> Dictionary:
	if id == "":
		s.flags.erase("title")
		return {"ok": true, "err": "", "events": []}
	if not TITLES.has(id):
		return {"ok": false, "err": "titulo_invalido", "events": []}
	if not is_unlocked(id, s.level, s.flags):
		return {"ok": false, "err": "titulo_bloqueado", "events": []}
	s.flags["title"] = id
	return {"ok": true, "err": "", "events": []}
