class_name StoryDialogue
extends RefCounted
## Roteiro da história "Um Herói Caiu na Vila" (comédia de aventura no estilo anime): o forasteiro chega a
## Valdoria e o Ancião Bram decide, na hora, que ele é o herói de uma profecia. Seis episódios, um por
## capítulo de quests.json, passando por todos os NPCs da vila (Bram, Mira, Doran, Pip, Kael) e pelo
## bilhete do acampamento goblin. Quem decide o que cada NPC diz é o estado das missões (StoryRules):
## entregar a missão pronta > oferecer a próxima > lembrar a ativa > conversa à toa (com os serviços).
##
## Página: {"text", "speaker"?: nome (padrão: o NPC; "" = narrador), "mood"?: "shout"|"whisper"|"think",
##   "fx"?: "boom"|"sparkle"|"end", "on_show"?: Callable, "choices"?: [{"text", "action"?: Callable,
##   "pages"?: Array}]}. Escolha com "pages" mostra essas páginas e segue o diálogo; sem, fecha e chama action.

const NAMES := {
	"elder": "Ancião Bram",
	"merchant": "Mira, a Mercadora",
	"blacksmith": "Doran, o Ferreiro",
	"alchemist": "Pip, a Alquimista",
	"rival": "Kael, a Lâmina Carmesim",
	"kael_pico": "Kael, a Lâmina Carmesim",
	"camp_note": "Bilhete Amassado",
	"lina": "Lina, da Guilda",
	"board": "Quadro de Contratos",
	"zelia": "Dona Zélia",
	"rufus": "Rufus, o Guarda",
	"guarda": "Guarda da Vila",
	"tonico": "Seu Tonico",
	"ravi": "Ravi, o Caçador",
	"osvaldo": "Sir Osvaldo",
	"sylvi": "Sylvi, a Patrulheira",
	"tico": "Tico",
	"bolgar": "Bolgar, o Minerador",
	"diario": "Diário Rasgado",
	"gato": "Sr. Bigodes",
	"coach": "Beto, o Cocheiro",
	"coach_bosque": "Beto, o Cocheiro",
	"coach_mina": "Beto, o Cocheiro",
	"coach_pico": "Beto, o Cocheiro",
	"santa": "Papai Noel",
}
## Cor da plaquinha de nome de cada um (a caixa de diálogo pinta a borda e o nome com ela).
const COLORS := {
	"elder": Color(0.95, 0.78, 0.36),
	"merchant": Color(0.45, 0.88, 0.7),
	"blacksmith": Color(1.0, 0.55, 0.25),
	"alchemist": Color(0.78, 0.6, 1.0),
	"rival": Color(1.0, 0.36, 0.38),
	"kael_pico": Color(1.0, 0.36, 0.38),
	"camp_note": Color(0.8, 0.68, 0.5),
	"lina": Color(0.5, 0.75, 1.0),
	"board": Color(0.8, 0.68, 0.5),
	"zelia": Color(1.0, 0.7, 0.75),
	"rufus": Color(0.7, 0.75, 0.85),
	"guarda": Color(0.7, 0.75, 0.85),
	"tonico": Color(0.75, 0.85, 0.35),
	"ravi": Color(0.55, 0.75, 0.45),
	"osvaldo": Color(0.85, 0.82, 0.7),
	"sylvi": Color(0.4, 0.9, 0.55),
	"tico": Color(1.0, 0.85, 0.4),
	"bolgar": Color(0.85, 0.6, 0.4),
	"diario": Color(0.65, 0.45, 0.85),
	"gato": Color(1.0, 0.6, 0.25),
	"coach": Color(0.75, 0.6, 0.45),
	"coach_bosque": Color(0.75, 0.6, 0.45),
	"coach_mina": Color(0.75, 0.6, 0.45),
	"coach_pico": Color(0.75, 0.6, 0.45),
	"santa": Color(1.0, 0.35, 0.3),
	"": Color(0.7, 0.72, 0.78),
}
const NARRATOR := ""


static func color_of(speaker: String) -> Color:
	for id in NAMES:
		if NAMES[id] == speaker:
			return COLORS[id]
	return COLORS[""]


## Se o NPC (ou objeto) está no mapa agora: o Kael troca a vila pelo Pico das Cinzas enquanto está com o
## Lich; o Tico volta para casa depois da Slime Rainha; o gato some quando é achado.
static func present(id: String) -> bool:
	var q: Dictionary = Game.quests
	match id:
		"rival":
			return not (StoryRules.state(q, "diario") == "done" and StoryRules.state(q, "lich") != "done")
		"kael_pico":
			return StoryRules.state(q, "diario") == "done"
		"tico":
			return StoryRules.state(q, "rainha") != "done"
		"gato":
			return StoryRules.state(q, "gato") != "done"
	return true


## Páginas do diálogo do NPC (Node com npc_id) agora.
## Prioridade: carruagem > entregar > história nova > história travada por rank > lembrete da história >
## secundárias (o quadro lista todas) > lembrete de secundária > conversa à toa (com os serviços).
static func build(npc: Node) -> Array:
	var id: String = npc.npc_id
	if id == "coach" or id.begins_with("coach_"):
		return _coach(id)
	var qt: Dictionary = ItemDB.QUESTS
	var quests: Dictionary = Game.quests
	var counts := _counts(qt)
	var rank := Game.rank()
	var pages: Array = []
	var done := StoryRules.turnable_at(qt, quests, id, counts)
	if done != "":
		pages.append_array(_complete_any(done))
		var nxt := StoryRules.after(qt, done)
		if nxt != "" and StoryRules.giver(qt, nxt) == id:
			if StoryRules.rank_ge(rank, StoryRules.needs_rank(qt, nxt)):
				pages.append_array(_offer_any(nxt))
			else:
				pages.append_array(_locked(nxt))
		elif nxt != "":
			pages.append_array(_hint(nxt, id))
		return _with_services(id, pages)
	var offer := StoryRules.offer_at(qt, quests, id, rank)
	if offer != "":
		return _offer_any(offer)
	var cur := StoryRules.current(qt, quests)
	if cur != "" and StoryRules.state(quests, cur) == "none" and StoryRules.giver(qt, cur) == id:
		pages.append_array(_locked(cur))   # a história segue com ele, mas falta rank
		return _with_services(id, pages)
	# lembrete da história primeiro; depois as secundárias novas; depois os lembretes das secundárias
	var side_reminders: Array = []
	for q in quests:
		if not qt.has(q) or quests[q].state == "done":
			continue
		if StoryRules.giver(qt, q) == id or StoryRules.turn_in(qt, q) == id:
			var r := _reminder_any(q, id)
			if r.is_empty():
				continue
			if StoryRules.is_side(qt, q):
				side_reminders.append_array(r)
			else:
				pages.append_array(r)
				return _with_services(id, pages)
	var sides := StoryRules.side_offers_at(qt, quests, id, rank)
	if id == "board":
		return _board(sides, side_reminders)
	if not sides.is_empty():
		# contrato novo, mas os serviços (loja, encanto, promoção) continuam a uma escolha de distância
		pages = _offer_any(sides[0])
		var last: Dictionary = pages[pages.size() - 1]
		var ch: Array = last.choices
		ch.remove_at(ch.size() - 1)   # "Agora não" volta no fim, depois dos serviços
		ch.append_array(_services(id))
		ch.append({"text": "Agora não", "action": Callable()})
		return pages
	if not side_reminders.is_empty():
		return _with_services(id, side_reminders)
	pages.append_array(_idle(id))
	return _with_services(id, pages)


# ================================================================ falas em dados (quests.json, "talk")
## Linha do roteiro em dados: prefixos (na ordem) "[reward]" entrega a missão ao aparecer, "[end]" cartão de
## fim, "[boom]"/"[sparkle]" efeito, "@id:" outro personagem fala ("@narr:" = narrador), e um destes:
## "!" grita, "~" sussurra, "*" pensamento do narrador, ">" narração. {n} vira o progresso da missão.
static func parse_line(line: String, q := "", n := "") -> Dictionary:
	var page := {}
	var t := line.strip_edges()
	var speaker = null
	var go := true
	while go:
		go = false
		for tag in ["[reward]", "[end]", "[boom]", "[sparkle]"]:
			if t.begins_with(tag):
				t = t.substr(tag.length()).strip_edges()
				go = true
				match tag:
					"[reward]":
						if q != "":
							page["on_show"] = _finish.bind(q)
					"[end]":
						page["fx"] = "end"
					_:
						page["fx"] = tag.trim_prefix("[").trim_suffix("]")
		if t.begins_with("@"):
			var colon := t.find(":")
			if colon > 0:
				var who := t.substr(1, colon - 1)
				speaker = NARRATOR if who == "narr" else NAMES.get(who, who)
				t = t.substr(colon + 1).strip_edges()
				go = true
	var mood := ""
	var narrated := false
	if t.begins_with("!"):
		mood = "shout"
	elif t.begins_with("~"):
		mood = "whisper"
	elif t.begins_with("*"):
		mood = "think"
		narrated = true
	elif t.begins_with(">"):
		narrated = true
	if mood != "" or narrated:
		t = t.substr(1).strip_edges()
	if narrated:
		speaker = NARRATOR
	var built := p(t.replace("{n}", n), speaker, mood)
	built.merge(page)
	return built


## Lista de linhas (strings ou {"choices": [[texto, [linhas]], ...]}, que vira escolha da página anterior).
static func parse_lines(lines: Array, q := "", n := "") -> Array:
	var out: Array = []
	for l in lines:
		if l is Dictionary and l.has("choices"):
			var ch: Array = []
			for c in l.choices:
				ch.append({"text": str(c[0]), "pages": parse_lines(c[1], q, n)})
			if out.is_empty():
				out.append(p("..."))
			out[out.size() - 1]["choices"] = ch
		else:
			out.append(parse_line(str(l), q, n))
	return out


static func _talk(q: String) -> Dictionary:
	return ItemDB.QUESTS.get(q, {}).get("talk", {})


static func _offer_any(q: String) -> Array:
	var t := _talk(q)
	if t.is_empty():
		return _offer(q)
	var pages := parse_lines(t.get("offer", []))
	var d: Dictionary = ItemDB.QUESTS[q]
	var last := narr("(%s. Recompensa: %d ouro, %d XP%s.)" % [d.objective, d.reward_gold, d.reward_xp, _pts_text(d)])
	last["choices"] = [
		{"text": str(t.get("accept", "Aceitar")), "action": _accept.bind(q)},
		{"text": "Agora não", "action": Callable()},
	]
	pages.append(last)
	return pages


static func _pts_text(d: Dictionary) -> String:
	if StoryRules.state(Game.quests, "registro") != "done":
		return ""
	var pts := 0
	if d.has("guild_pts"):
		pts = int(d.guild_pts)
	else:
		pts = int(_guild().get("default_pts", {}).get(CharRules.quest_type(d), 0))
	return ", %d pontos de guilda" % pts if pts > 0 else ""


static func _complete_any(q: String) -> Array:
	var t := _talk(q)
	if t.is_empty():
		return _complete(q)
	var pages := parse_lines(t.get("done", []), q)
	var has_reward := false
	for pg in pages:
		if pg.has("on_show"):
			has_reward = true
	if not has_reward and pages.size() > 0:
		pages[pages.size() - 1]["on_show"] = _finish.bind(q)
	return pages


static func _reminder_any(q: String, at: String) -> Array:
	var t := _talk(q)
	if t.is_empty():
		return _reminder(q, at)
	if not t.has("remind"):
		return []
	var qt: Dictionary = ItemDB.QUESTS
	var pr := StoryRules.progress(qt, Game.quests, q, _counts(qt))
	return [parse_line(str(t.remind), "", "%d/%d" % [pr[0], pr[1]])]


## A história segue com este NPC, mas falta rank: ele explica (e a Lina oferece a promoção, se der).
static func _locked(q: String) -> Array:
	var t := _talk(q)
	var need := StoryRules.needs_rank(ItemDB.QUESTS, q)
	return [parse_line(str(t.get("locked", "Ainda não é a hora. Volte quando for Rank %s." % need)))]


## O Quadro de Contratos: cada contrato disponível vira uma escolha que mostra o contrato e o aceite.
static func _board(sides: Array, reminders: Array) -> Array:
	var head := narr("(Quadro de Contratos da Guilda de Valdoria. Seu rank: %s, %d pontos de guilda.)" % [Game.rank(), Game.guild_points()])
	if sides.is_empty():
		var pages: Array = [head]
		pages.append_array(reminders)
		pages.append(narr("(Nenhum contrato novo para o seu rank agora. Volte mais tarde, ou suba de rank.)"))
		return pages
	var choices: Array = []
	for q in sides.slice(0, 4):
		var d: Dictionary = ItemDB.QUESTS[q]
		choices.append({"text": "[%s] %s" % [StoryRules.needs_rank(ItemDB.QUESTS, q), d.name], "pages": _offer_any(q)})
	choices.append({"text": "Só olhando", "action": Callable()})
	head["choices"] = choices
	return [head]


# ================================================================ guilda (Lina)
static func _guild() -> Dictionary:
	return Balance.tables.get_table("guild") if Balance.tables != null else {}


## Próximo rank no espelho do personagem ({} = já é S).
static func next_rank() -> Dictionary:
	var ranks: Array = _guild().get("ranks", [])
	var i := StoryRules.RANKS.find(Game.rank()) + 1
	return ranks[i] if i < ranks.size() else {}


## Por que a promoção ainda não sai ("" = pode), espelho de CharRules.rank_up_block.
static func rank_block() -> String:
	if StoryRules.state(Game.quests, "registro") != "done":
		return "Primeiro você precisa se registrar na guilda!"
	var nx := next_rank()
	if nx.is_empty():
		return "Você já é Rank S. Não existe Rank SS. Eu perguntei para a matriz. Duas vezes."
	if Game.guild_points() < int(nx.pts):
		return "Para o Rank %s faltam %d pontos de guilda. Os contratos do Quadro ajudam!" % [nx.id, int(nx.pts) - Game.guild_points()]
	if nx.has("requires") and StoryRules.state(Game.quests, str(nx.requires)) != "done":
		return "Para o Rank %s, além dos pontos, a matriz exige um feito lendário. Continue a história!" % nx.id
	return ""


static func _promote() -> void:
	Game.rank_up()


static func _lina_services() -> Array:
	var nx := next_rank()
	var card := "Rank %s · %d pontos de guilda" % [Game.rank(), Game.guild_points()]
	if not nx.is_empty():
		card += " · Rank %s com %d" % [nx.id, int(nx.pts)]
	var out: Array = []
	if StoryRules.state(Game.quests, "registro") == "done":
		out.append({"text": "Ver meu cartão", "pages": [narr("(Cartão da Guilda: %s.)" % card)]})
	if rank_block() == "" and not nx.is_empty():
		var promo := p("Os moradores vão saber disso até o fim do dia. A Mira já está atualizando os preços. Para cima.")
		promo["on_show"] = _promote
		out.push_front({"text": "Pedir promoção a Rank %s" % nx.id, "pages": [
			p("O exame de promoção! Formulário, carimbo, assinatura...", null, "shout"),
			_fx(p("Parabéns, {heroi}! A partir de hoje você é RANK %s: %s!" % [nx.id, nx.get("title", "")]), "sparkle"),
			promo,
		]})
	elif StoryRules.state(Game.quests, "registro") == "done" and not nx.is_empty():
		out.append({"text": "Quero ser promovido", "pages": [p(rank_block())]})
	if Game.char_class != "":
		out.append({"text": "Redistribuir talentos", "pages": _talent_reset_pages()})
	return out


## A Lina redistribui os talentos da classe: devolve todos os pontos por talent_reset_cost() de ouro.
static func _talent_reset_pages() -> Array:
	if Game.talents.is_empty():
		return [p("Seus pontos de talento estão todos guardados. Quando gastar algum e se arrepender, é só voltar aqui!")]
	var cost := Game.talent_reset_cost()
	var spent := Game.level - 1 - Game.talent_points()
	var price := "Até o nível 5 é de graça, cortesia da guilda!" if cost == 0 		else "A taxa da guilda é %d de ouro. Papelada não se carimba sozinha." % cost
	var head := p("Redistribuir talentos? Eu apago a ficha e você recebe os %d pontos de volta para gastar de novo. %s" % [spent, price])
	var label := "Redistribuir (grátis)" if cost == 0 else "Redistribuir (%d de ouro)" % cost
	head["choices"] = [{"text": label, "action": Game.reset_talents}, {"text": "Melhor não", "action": Callable()}]
	return [head]


# ================================================================ carruagem
static func _coach(id: String) -> Array:
	var here := "vila" if id == "coach" else id.trim_prefix("coach_")
	if StoryRules.state(Game.quests, "registro") != "done":
		return [p("Opa! Sou o Beto, cocheiro da guilda. Só levo aventureiro registrado. Fala com a Lina primeiro, ali no quadro de avisos.")]
	var head := p("Pra onde vamos, chefe? A carruagem da guilda leva qualquer aventureiro registrado. Com o rank certo, claro.")
	if here != "vila":
		head = p("Pronto pra voltar? Ou quer conhecer outro lugar? Eu espero. Cocheiro bom espera. Cocheiro ótimo cobra a espera.")
	var choices: Array = []
	for r in Regions.ORDER:
		if r == here:
			continue
		var need: String = Regions.DATA[r].rank
		var label := Regions.display_name(r) if r != "vila" else "Voltar para Valdoria"
		if Regions.unlocked(r, Game.rank()):
			choices.append({"text": label, "action": _travel.bind(r)})
		else:
			choices.append({"text": "%s (Rank %s)" % [label, need], "pages": [
				p("Esse caminho é só para Rank %s, chefe. Regra da guilda, não minha." % need)]})
	choices.append({"text": "Fico por aqui", "action": Callable()})
	head["choices"] = choices
	return [head]


static func _travel(region: String) -> void:
	var w: Node = (Engine.get_main_loop() as SceneTree).current_scene
	if w and w.has_method("travel_to"):
		w.travel_to(region)


static func _counts(qt: Dictionary) -> Dictionary:
	var c := {}
	for id in qt:
		var q: Dictionary = qt[id]
		for item in StoryRules.count_ids(q):
			c[item] = Game.count_item(item)
	return c


static func hero() -> String:
	var n: String = str(Game.settings.get("player_name", ""))
	return n if n != "" else "Aventureiro"


static func p(text: String, speaker = null, mood := "") -> Dictionary:
	var d := {"text": text.replace("{heroi}", hero())}
	if speaker != null:
		d["speaker"] = speaker
	if mood != "":
		d["mood"] = mood
	return d


static func narr(text: String, mood := "think") -> Dictionary:
	return p(text, NARRATOR, mood)


## Escolha só de sabor: a resposta aparece e o diálogo segue.
static func flavor(a_text: String, a_pages: Array, b_text: String, b_pages: Array) -> Array:
	return [{"text": a_text, "pages": a_pages}, {"text": b_text, "pages": b_pages}]


static func _accept_page(text: String, q: String, yes: String) -> Dictionary:
	var page := p(text)
	page["choices"] = [
		{"text": yes, "action": _accept.bind(q)},
		{"text": "Agora não", "action": Callable()},
	]
	return page


static func _accept(q: String) -> void:
	Game.start_quest(q)
	Sfx.play("quest", 0.0)


static func _finish(q: String) -> void:
	Game.complete_quest(q)
	Sfx.play("quest", 0.0)


## Página que entrega a missão (recompensa) ao aparecer.
static func _reward(text: String, q: String, speaker = null, mood := "") -> Dictionary:
	var page := p(text, speaker, mood)
	page["on_show"] = _finish.bind(q)
	return page


static func _with_choices(page: Dictionary, choices: Array) -> Dictionary:
	page["choices"] = choices
	return page


## A última página ganha os serviços do NPC (loja, encantamento), se ainda não tiver escolhas.
static func _with_services(id: String, pages: Array) -> Array:
	var services := _services(id)
	if services.is_empty() or pages.is_empty():
		return pages
	var last: Dictionary = pages[pages.size() - 1]
	if not last.has("choices"):
		last["choices"] = services + [{"text": "Até logo", "action": Callable()}]
	return pages


static func _services(id: String) -> Array:
	match id:
		"lina":
			return _lina_services()
		"merchant":
			return [{"text": "Ver mercadorias", "action": _open_shop}]
		"alchemist":
			return [{"text": "Ver poções", "action": _open_shop}, {"text": "Alquimia", "action": _open_crafting.bind("alchemy")}]
		"blacksmith":
			return [{"text": "Encantar arma", "action": _open_enchant}, {"text": "Forjar", "action": _open_crafting.bind("forge")}]
	return []


static func _open_shop() -> void:
	var w: Node = (Engine.get_main_loop() as SceneTree).current_scene
	if w and w.has_method("open_shop"):
		w.open_shop()


static func _open_crafting(station: String) -> void:
	var w: Node = (Engine.get_main_loop() as SceneTree).current_scene
	if w and w.has_method("open_crafting"):
		w.open_crafting(station)


static func _open_enchant() -> void:
	var w: Node = (Engine.get_main_loop() as SceneTree).current_scene
	if w == null or not w.has_method("open_enchant"):
		return
	for n in w.get_tree().get_nodes_in_group("npc"):
		if n.npc_id == "blacksmith":
			w.open_enchant(n)
			return


# ================================================================ prólogo
## Narração da chegada (personagem novo, primeira vez no mundo): o anime abre antes do Bram.
static func intro() -> Array:
	return [
		narr("Valdoria. Uma vila pacata, com um poço, seis casas, uma ferraria barulhenta e um problema sério de slimes.", ""),
		narr("Pela estrada do sul chega um aventureiro. Sem mapa. Sem dinheiro. Com uma fome considerável.", ""),
		narr("Ele ainda não sabe, mas está prestes a virar o herói de uma profecia.", ""),
		narr("(Principalmente porque o Ancião Bram acabou de decidir isso.)"),
		narr("Fale com o Ancião Bram (!) perto do poço. Use E para interagir.", ""),
	]


# ================================================================ ofertas
static func _offer(q: String) -> Array:
	match q:
		"chegada":
			return [
				p("AH! ESSAS BOTAS GASTAS! ESSE OLHAR PERDIDO! ESSA... FOME EVIDENTE!", null, "shout"),
				_with_choices(p("Viajante, eu sou Bram, o ancião de Valdoria. E você... você é o HERÓI DA PROFECIA!"),
					flavor("Que profecia?", [
						p("A antiga! Escrita há... (ele olha para a palma da própria mão) ...muitos anos."),
						p("\"Quando a vila mais precisar, um forasteiro de botas chegará pela estrada.\" Você tem botas. Está provado."),
					], "Eu só queria um lanche.", [
						p("Todo herói começa com fome! Isso também está na profecia. Linha dois. Acabei de lembrar."),
					])),
				p("Os slimes devoram nossas plantações, goblins rondam a floresta, e eu juro que ouvi algo mastigando nas ruínas. Valdoria precisa de você!"),
				p("Primeiro, vá até a Mira, no empório a leste do poço. Ela vai te entregar o lendário KIT DO HERÓI!"),
				narr("(Ele piscou na direção do empório. A Mira não piscou de volta.)"),
				_accept_page("Aceita o destino que os céus escreveram para você? Que eu... que OS CÉUS escreveram?", q, "Aceitar o destino"),
			]
		"forja":
			return [
				p("O favor é o seguinte: o Doran, o ferreiro, está gritando há UMA HORA que quer \"sentir a paixão do herói\"."),
				narr("(Ao longe: \"PAIXÃÃÃÃO!\")"),
				p("Eu não consigo atender ninguém com esse barulho. A ferraria fica a sudoeste do poço. Vai lá e faz ele parar. Por favor. Pelo amor de todas as moedas."),
				_accept_page("E isso NÃO conta como abatimento da dívida, ouviu?", q, "Vou acalmar o Doran"),
			]
		"slimes":
			return [
				p("Agora PROVE essa chama! Os slimes estão comendo as plantações nos campos ao norte da vila!"),
				p("DERROTE CINCO DELES! CADA SLIME ESMAGADO É UMA FAÍSCA NA SUA ALMA!", null, "shout"),
				p("E depois vá contar ao Bram. Ele adora uma história. Vai chorar. Ele sempre chora."),
				_accept_page("E então? Sua alma está pegando fogo?", q, "PELA PAIXÃO!"),
			]
		"gel":
			return [
				p("Ah. O herói. Ouvi falar. Você é mais baixo do que a explosão... digo, do que eu imaginava."),
				p("Sou a Pip. Alquimista. Faço poções. Às vezes elas explodem. Às vezes de propósito."),
				_with_choices(p("Preciso de 5 Géis de Slime para uma poção nova. Totalmente segura. Uns 60% segura."),
					flavor("E os outros 40%?", [
						p("Os outros 40% são emoção."),
					], "Que poção é essa?", [
						p("Poção de Coragem Instantânea. Ou de Cabelo Instantâneo. Ainda não sei qual. É isso que deixa divertido."),
					])),
				p("Os slimes dos campos ao norte deixam cair o gel. Se você já tiver algum na mochila, melhor ainda."),
				_accept_page("Traz cinco. Eu espero aqui. Cochilando.", q, "Trago o gel"),
			]
		"rival":
			return [
				p("Outra coisa. Tem um cara de capa vermelha fazendo discursos no portão leste desde de manhã."),
				p("\"Eu sou a Lâmina Carmesim! Temam-me, criaturas das trevas!\"", null, "shout"),
				p("As criaturas das trevas não temem. Eu, sim, estou com dor de cabeça."),
				_accept_page("Vai lá ver quem é. E pede pra ele gritar mais baixo.", q, "Vou ver quem é"),
			]
		"goblins":
			return [
				p("E vamos resolver isso como verdadeiros heróis: uma COMPETIÇÃO!", null, "shout"),
				p("Há batedores goblins acampados na floresta a leste. Siga a trilha de terra. Quem derrotar mais é o verdadeiro herói de Valdoria!"),
				p("Você vai na frente. Eu vou logo atrás. Bem atrás. É estratégia, entende?"),
				_accept_page("Aceita o desafio, rival?", q, "Desafio aceito!"),
			]
		"bilhete":
			return [
				p("Ah, e... enquanto eu derrotava os quarenta e sete, vi um bilhete preso num caixote do acampamento. No lado oeste, perto do barril."),
				p("Eu mesmo iria buscar, mas estou... ocupado. Polindo a espada. É um processo muito delicado."),
				_accept_page("Considere uma honra eu te dar essa missão!", q, "Vou buscar o bilhete"),
			]
		"torta":
			return [
				p("Um bilhete do acampamento? Deixe-me ver..."),
				p("A TORTA?! ELES QUEREM A TORTA DE ABÓBORA?!", null, "shout"),
				p("Herói, a Torta de Abóbora de Valdoria é nosso maior tesouro. A receita é passada de ancião para ancião há gerações."),
				p("...É abóbora e trigo. Não conte a ninguém.", null, "whisper"),
				p("Tenho um plano GENIAL! Vamos assar uma torta e usar como isca! O Rei vai sair das ruínas só pelo cheiro!"),
				p("Tome estas sementes. Plante na Horta, saindo pelo portão sul. Regue para crescer mais rápido, colha e cozinhe a torta no caldeirão da Horta."),
				_accept_page("E por favor... não coma a torta no caminho.", q, "Hora de cozinhar!"),
			]
		"ossos":
			return [
				p("Mas a trilha das ruínas está cheia de esqueletos. Ninguém sabe por que eles estão lá."),
				p("Uns dizem que são antigos guardiões. Outros, que só gostam da vista."),
				_accept_page("Abra caminho: derrote 5 esqueletos na trilha ao norte. O Doran disse que tem uma surpresa para você na volta.", q, "Vou limpar a trilha"),
			]
		"goblin_king":
			return [
				p("E escute: o Bram mandou avisar. A TORTA FUNCIONOU! O Rei Goblin saiu do esconderijo!", null, "shout"),
				p("ELE ESTÁ NAS RUÍNAS AO NORTE, FAREJANDO O AR! É A HORA, HERÓI! A BATALHA FINAL!", null, "shout"),
				p("Leve poções. Leve coragem. Leve esse elmo. E se puder... traga a torta de volta. Ela é do Bram."),
				_accept_page("Está pronto?", q, "PELA TORTA!"),
			]
		"festa":
			return [
				p("Hoje à noite teremos FESTA! A Mira vai dar desconto (ela disse que não, mas vai). O Doran vai cantar (infelizmente)."),
				p("Ah, e o Kael está no portão leste. Disse que quer falar com você. Parecia nervoso. Ensaiando alguma coisa."),
				_accept_page("Vai lá antes que ele ensaie pela centésima vez.", q, "Vou ver o Kael"),
			]
	return []


# ================================================================ entregas
static func _complete(q: String) -> Array:
	match q:
		"chegada":
			return [
				p("Kit do Herói? Ele te mandou aqui pra isso?"),
				p("BRAM! EU NÃO TENHO NENHUM KIT DO HERÓI!", null, "shout"),
				narr("(Lá do poço, o ancião finge que está muito interessado numa nuvem.)"),
				p("...Tá. Tá bom. Toma essas poções. NÃO é porque eu fiquei com pena de você, tá? É um investimento."),
				_reward("Vou anotar no meu caderninho: \"{heroi}: deve 2 poções, 20 moedas e um favor.\" Juros de zero por cento. Por enquanto.", q),
				_with_choices(p("O que foi? Por que essa cara?"),
					flavor("Obrigado, Mira!", [
						p("N-não precisa agradecer! Só não morre antes de me pagar."),
					], "Que favor?", [
						p("Ah. Que bom que perguntou."),
					])),
			]
		"forja":
			return [
				p("ENTÃO VOCÊ É O HERÓI!", null, "shout"),
				p("Deixe-me olhar nos seus olhos... Hmm... Hmmmmmm..."),
				p("SIM! EU VEJO! UMA CHAMA! PEQUENA, MAS TEIMOSA! COMO BRASA DE CARVÃO BARATO!", null, "shout"),
				_reward("Isso me lembra de mim mesmo, aos sete anos, quando forjei meu primeiro escudo. Tome! Agora ele é seu!", q),
				_with_choices(narr("(É um escudo de madeira. Tem um dragão sorridente desenhado com giz de cera.)"),
					flavor("...Obrigado?", [
						p("NÃO AGRADEÇA! HONRE-O!", null, "shout"),
					], "Isso é um escudo de criança.", [
						p("É um escudo de CORAÇÃO! ...Mas sim, é de criança."),
					])),
			]
		"slimes":
			return [
				p("VOCÊ VOLTOU! E COBERTO DE GOSMA! EXATAMENTE COMO NA PROFECIA!", null, "shout"),
				p("...que eu vou atualizar agora mesmo. \"E o herói voltará grudento.\" Lindo. Poético."),
				narr("(Bram enxuga uma lágrima. Lá da ferraria, o Doran também.)"),
				_reward("Os fazendeiros já voltaram aos campos. Tome, você mereceu!", q),
			]
		"gel":
			return [
				p("Cinco géis. Perfeito. Agora fica parado aí."),
				_with_choices(p("..."),
					flavor("(Ficar parado)", [
						_fx(narr("KABUM!", "shout"), "boom"),
						p("...Hm. Era a poção de Cabelo Instantâneo. Você está... volumoso."),
					], "(Dar três passos para trás)", [
						_fx(narr("KABUM! (Você, sabiamente, estava longe.)", "shout"), "boom"),
						p("Hm. Você ouviu o Bram. Chato. Mas inteligente."),
					])),
				_reward("O experimento foi um sucesso. Ou um fracasso. Toma essas poções de mana. Essas eu sei fazer sem explodir.", q),
			]
		"rival":
			return [
				p("ALTO AÍ! Você está diante de KAEL, A LÂMINA CARMESIM! Aventureiro de rank S!", null, "shout"),
				narr("(O distintivo no peito dele diz \"Rank D\". Escrito à mão. Com um S desenhado por cima.)"),
				_with_choices(p("Então VOCÊ é o tal herói da profecia? Ha! Eu vim de muito longe salvar esta vila e o velho nem olhou pra mim!"),
					flavor("Prazer, Kael.", [
						p("N-não seja simpático! Rivais não são simpáticos! ...Prazer."),
					], "Rank S, é?", [
						p("S de... Super. Rank Super-D. É uma categoria nova. Muito exclusiva."),
					])),
				_fx(_reward("Pois saiba que de hoje em diante você é meu RIVAL ETERNO!", q, null, "shout"), "sparkle"),
			]
		"goblins":
			return [
				p("Ah! Voltou! Quantos? Quatro?! Hah! Eu derrotei QUARENTA E SETE!", null, "shout"),
				narr("(Kael tem um galo enorme na testa e marcas de dentinhos na capa. Parece que perdeu uma briga para UM goblin.)"),
				_with_choices(p("O que foi? Não acredita?"),
					flavor("Quarenta e sete, é?", [
						p("...Quarenta e sete é um número aproximado. Arredondado. Para cima. Bastante."),
					], "Esse galo aí tá doendo?", [
						p("Isso é uma marca de batalha! Muito nobre! Não encosta."),
					])),
				_reward("Tá. Tá bom. Toma, uma cota de malha. Achei no acampamento e ficou grande em mim. NÃO é um presente! É uma trégua temporária.", q),
			]
		"bilhete":
			return [
				narr("(Um papel amassado, preso no caixote com uma faca de manteiga. Cheira a cebola. A letra é horrível.)"),
				p("LISTA DO REI GOBLIN — NÃO LER!!!", null, "shout"),
				p("1. Dominar Valdoria.\n2. Comer a TORTA DE ABÓBORA da vila (dizem q é a melhor do mundo!!!)\n3. Lavar a coroa (tá grudenta)\n4. Dominar Valdoria de novo, caso o item 1 dê errado."),
				narr("(No verso, um desenho de uma torta cercada de coraçõezinhos.)"),
				_reward("(...O Rei Goblin quer invadir a vila por causa de uma TORTA? Melhor contar isso ao Ancião Bram.)", q, NARRATOR, "think"),
			]
		"torta":
			return [
				p("Esse cheiro... ESSE CHEIRO! É ela! A lendária Torta de Abóbora!", null, "shout"),
				narr("(Bram dá uma mordida enorme na isca.)"),
				_with_choices(p("Mmmmmh!"),
					flavor("Bram! Era a isca!", [
						p("Eu estava verificando a qualidade! Todo bom plano precisa de controle de qualidade!"),
					], "(Olhar em silêncio)", [
						p("...Não me olhe assim. Ainda sobraram três quartos."),
					])),
				_reward("Vou deixar a torta na janela, virada para o norte. Tome, este amuleto era do meu avô. Ele também comia as iscas.", q),
			]
		"ossos":
			return [
				p("VOCÊ VOLTOU INTEIRO! E COM CHEIRO DE OSSO VELHO!", null, "shout"),
				p("Enquanto você lutava, eu forjei a noite toda. Sem parar. Sem dormir. Chorei duas vezes."),
				_reward("Aqui está! Um elmo de ferro DE VERDADE! Nada de giz de cera dessa vez!", q),
				narr("(Por dentro do elmo, gravado com muito carinho: um dragão sorridente.)"),
			]
		"goblin_king":
			return [
				p("O REI GOBLIN... DERROTADO?! EU MAL POSSO ACREDITAR!", null, "shout"),
				p("Eu sabia! Eu sempre soube! A profecia nunca erra!"),
				narr("(Ele segura o papel da profecia. Dá para ver umas sete versões riscadas.)"),
				_with_choices(p("O que foi, herói? Pode perguntar."),
					flavor("E a torta?", [
						p("Ah... o Rei comeu. Mas deixou um bilhete: \"Melhor torta do mundo. Nota 10. Voltarei.\" Que educado!"),
					], "A profecia foi inventada, né?", [
						p("Toda profecia foi inventada por alguém, jovem herói. A minha só foi inventada... recentemente."),
					])),
				_fx(_reward("Tome! Placas reais, dignas de quem salvou Valdoria!", q), "sparkle"),
			]
		"festa":
			return [
				p("Ah. É você. Eu... ahem. Ahem!"),
				p("HERÓI DA PROFECIA! EU, KAEL, A LÂMINA CARMESIM, RECONHEÇO QUE VOCÊ... É...", null, "shout"),
				_with_choices(p("...um rival aceitável. Pronto. Falei."),
					flavor("Você também, Kael.", [
						p("N-não fala assim que eu choro! Lâminas Carmesins não choram! ...Estou suando pelos olhos."),
					], "Aceitável? Só isso?", [
						p("TÁ BOM! Um rival EXCELENTE! Satisfeito?! Argh!", null, "shout"),
					])),
				_reward("Toma. É um anel do vento. Comprei com muito esforço. A Mira me deu desconto de rival.", q),
				p("Mas não pense que acabou! Um dia eu vou ser rank S de verdade, e aí teremos a nossa REVANCHE!", null, "shout"),
				narr("E assim Valdoria voltou a ter paz. Os slimes continuaram gosmentos, a Pip continuou explodindo coisas e a Mira ainda guarda o caderninho.", ""),
				_fx(narr("FIM DO PRIMEIRO ARCO. Obrigado por jogar! Valdoria continua aberta para caçar, plantar, cozinhar e desafiar a Horda.", ""), "end"),
			]
	return []


static func _fx(page: Dictionary, fx: String) -> Dictionary:
	page["fx"] = fx
	return page


## Quem entregou a missão aponta o próximo NPC da história.
static func _hint(q: String, from: String) -> Array:
	var who := StoryRules.giver(ItemDB.QUESTS, q)
	if ItemDB.QUESTS.get(q, {}).has("hint"):
		return [narr(str(ItemDB.QUESTS[q].hint))]
	match q:
		"gel":
			return [
				p("Ah! A Pip, nossa alquimista, perguntou por você. Ela quer o gel desses slimes para um... experimento."),
				p("Dica de ancião: quando ela disser \"fica parado aí\", NÃO fique parado aí.", null, "whisper"),
				p("A botica fica a oeste do poço."),
			]
		"torta":
			return [narr("(Leve o bilhete ao Ancião Bram, perto do poço da vila.)")]
		"goblin_king":
			return [p("Agora vá ver o Doran. Ele tem uma coisa para você.")]
	if who != from and NAMES.has(who):
		return [narr("(Próximo passo: fale com %s.)" % NAMES[who])]
	return []


# ================================================================ lembretes
static func _reminder(q: String, at: String) -> Array:
	var qt: Dictionary = ItemDB.QUESTS
	var prog := StoryRules.progress(qt, Game.quests, q, _counts(qt))
	var n := "%d/%d" % [prog[0], prog[1]]
	match [q, at]:
		["chegada", "elder"]:
			return [p("A Mira está no empório, a leste do poço. Diga que fui eu que mandei! ...Na verdade, não diga.")]
		["forja", "merchant"]:
			return [p("Ainda dá pra ouvir o Doran daqui. Ferraria, sudoeste do poço. Vai logo!")]
		["slimes", "blacksmith"]:
			return [p("OS CAMPOS AO NORTE, HERÓI! %s SLIMES! SUA CHAMA PODE ARDER MAIS!" % n, null, "shout")]
		["slimes", "elder"]:
			return [p("O Doran me contou que você está caçando slimes ao norte! Que coragem! Que gosma! (%s)" % n)]
		["gel", "alchemist"]:
			return [p("Gel de Slime: %s. ...Zzz. Hm? Ah, sim. Os slimes dos campos ao norte." % n)]
		["rival", "alchemist"]:
			return [p("Ainda dá pra ouvir ele. Portão leste. Eu jogaria uma poção nele, mas tô sem gel.")]
		["goblins", "rival"]:
			return [p("Ainda aqui? Eu já derrotei... muitos. Vários. %s, é isso? Hah! Amador! O acampamento fica no fim da trilha leste." % n)]
		["bilhete", "rival"]:
			return [p("O bilhete está num caixote no lado oeste do acampamento goblin, perto do barril. Eu iria, mas... a espada. Polindo.")]
		["torta", "elder"]:
			return [p("Abóbora e trigo, na Horta ao sul! Plante, regue, colha e cozinhe no caldeirão. E NÃO coma a torta. Eu sei que é tentador.")]
		["ossos", "elder"]:
			return [p("Os esqueletos ficam na trilha das ruínas, bem ao norte. (%s)" % n)]
		["ossos", "blacksmith"]:
			return [p("OSSOS, HERÓI! ESQUELETOS NA TRILHA DAS RUÍNAS! %s! TRANSFORME-OS EM FARINHA!" % n, null, "shout")]
		["goblin_king", "blacksmith"]:
			return [p("AS RUÍNAS AO NORTE! O REI TE ESPERA! E A TORTA TAMBÉM!", null, "shout")]
		["goblin_king", "elder"]:
			return [p("O Rei está nas ruínas, bem ao norte! Seja corajoso! E traga a torta, se puder.")]
		["festa", "elder"]:
			return [p("O Kael está no portão leste. Vai lá antes que ele ensaie o discurso pela centésima vez.")]
	return []


# ================================================================ conversa à toa
static func _idle(id: String) -> Array:
	var qt: Dictionary = ItemDB.QUESTS
	var story_over := StoryRules.current(qt, Game.quests) == ""
	var met_rival := StoryRules.state(Game.quests, "rival") != "none"
	var lines: Array = []
	match id:
		"elder":
			lines = ["A profecia diz que o herói vai visitar o velho Bram de vez em quando. Linha 47. Acabei de escrever.",
				"Já provou a torta da vila? Não? Ótimo, sobra mais para... para a vila. Para a vila.",
				"Quando eu era jovem, também fui aventureiro. Durou uma tarde. Choveu."]
			if story_over:
				lines.append("Herói de Valdoria! As crianças já cantam canções sobre você. Desafinadas, mas cantam.")
		"merchant":
			lines = ["Olá, freguê... ah, é você. Seu saldo no caderninho continua negativo, viu?",
				"Poções, lâminas e armaduras. Preço justo. Para você, preço justo mais juros.",
				"Também compro o que você trouxer da mata. Gosma inclusa. Não pergunte para quê."]
		"blacksmith":
			lines = ["Mais um golpe e essa lâmina fica pronta. Ferro bom vem das minas do norte, mas o carvão... cada vez mais caro.",
				"Se a Mira te vendeu alguma espada, pode apostar que passou por esta bigorna!",
				"Traga minério e o que a mata dá, e eu ponho um encanto na sua arma. Ferro frio não morde; ferro encantado, SIM!"]
		"alchemist":
			lines = ["Hm. Oi. Quer ver uma poção que muda de cor? ...Ela também explode.",
				"Eu durmo doze horas por dia. É por isso que sou genial.",
				"Não toca naquele frasco roxo. Nem naquele verde. Na verdade, não toca em nada."]
		"rival":
			if not met_rival:
				lines = ["Ei, você aí! Não atrapalhe! Estou ensaiando minha pose heroica.",
					"Silêncio, plebeu. A Lâmina Carmesim está... meditando. Com os olhos abertos."]
			else:
				lines = ["Rival! Pronto para o nosso duelo? ...Hoje não, estou com cãibra.",
					"Eu treinei a noite toda. Bem, treinei a pose. A espada fica para amanhã.",
					"A Pip me ofereceu uma poção de coragem. Recusei. Por coragem."]
		"santa":
			lines = ["Ho, ho, ho! O trenó está carregado e as renas descansadas. Feliz Natal, {heroi}!",
				"As renas adoraram as cenouras da Horta. A Rodolfa comeu doze. Doze!",
				"Já fiz a lista de quem foi bonzinho este ano. Você está nela. Em letra grande.",
				"Ho, ho... ho? Alguém viu meu gorro reserva? Ah, está na cabeça. Ho, ho, ho!"]
		"camp_note":
			if StoryRules.state(Game.quests, "bilhete") == "done":
				return [narr("(Só restou a faca de manteiga presa no caixote. Ainda cheira a cebola.)")]
			return [narr("(Um papel amassado, preso no caixote com uma faca de manteiga. Não parece importante... por enquanto.)")]
	if lines.is_empty():
		return [narr("...")]
	return [p(lines.pick_random())]
