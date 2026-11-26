class_name ExpeditionSkills
extends RefCounted
## Kit temporário de habilidades da expedição (puro: sem cena, sem autoload; lê só a constante ItemDB.ABILITIES).
##
## Regra do roguelite: a expedição começa só com o ataque básico. Cada Altar da Deusa (skill_altar.gd) oferece
## CHOICES habilidades do kit que o personagem teria agora fora da expedição (ItemDB.kit da classe, da arma e da
## mão secundária: Game.full_ability_kit) e o jogador leva uma. As escolhidas ficam no ExpeditionRun.skills e o
## Game.run_kit espelha a lista enquanto a expedição dura; nada disso é salvo no personagem.
##
## Ficam de fora da oferta: ultimates (dependem da fúria e do anel da tecla 4 — fica para uma etapa futura),
## habilidades ainda não implementadas ("ready": false) e as que o jogador já levou.
## O nível da habilidade não conta aqui: na expedição é o altar que libera (Game.knows_ability).

## Quantas opções um altar mostra.
const CHOICES := 3
## Teto do kit temporário (as teclas 1..6 da barra de ações).
const MAX_SKILLS := 6


## Habilidades que um altar pode oferecer: do `full_kit` (ids na ordem da barra), implementadas, não ultimate e
## ainda não levadas (`owned`).
static func pool(full_kit: Array, owned: Array) -> Array[String]:
	var out: Array[String] = []
	if owned.size() >= MAX_SKILLS:
		return out
	for id in full_kit:
		var sid := str(id)
		if can_offer(sid) and not owned.has(sid) and not out.has(sid):
			out.append(sid)
	return out


## A habilidade pode sair num altar (existe, está pronta e não é ultimate).
static func can_offer(id: String) -> bool:
	if not ItemDB.ABILITIES.has(id):
		return false
	var a: Dictionary = ItemDB.ABILITIES[id]
	return bool(a.get("ready", false)) and not bool(a.get("ultimate", false))


## Sorteia até CHOICES opções do pool (sem repetir). Menos opções se o pool for menor; [] se não sobrou nada.
static func roll(rng: RandomNumberGenerator, full_kit: Array, owned: Array) -> Array[String]:
	var left := pool(full_kit, owned)
	var out: Array[String] = []
	while not left.is_empty() and out.size() < CHOICES:
		var i := rng.randi_range(0, left.size() - 1)
		out.append(left[i])
		left.remove_at(i)
	return out


## Kit que vale agora na expedição: as levadas (`owned`, na ordem em que foram escolhidas) que o personagem ainda
## pode usar com a arma de agora (estão no `full_kit`). Trocar de arma no meio da run some com as incompatíveis.
static func active_kit(full_kit: Array, owned: Array) -> Array[String]:
	var out: Array[String] = []
	for id in owned:
		if full_kit.has(id) and not out.has(str(id)):
			out.append(str(id))
	return out


# ================================================================ evolução da build (Altar Ancestral)
## Habilidades cujo dano passa por Game.ability_dmg_mult -> a chave usada ("ability_dmg:<chave>"). Só estas aceitam
## a Potência (nas outras o multiplicador não chega ao golpe e a melhoria não faria nada). O Vórtice da montante usa
## a mesma chave do Vórtice da espada.
const DMG_KEY := {
	"staff_flame": "staff_flame",
	"sword_spin": "sword_spin",
	"sword_drag": "sword_drag",
	"sword_dark_combo": "sword_dark_combo",
	"sword_hammer": "sword_hammer",
	"sword_earthquake": "sword_earthquake",
	"sword_vortex": "sword_vortex",
	"sword_vortex_great": "sword_vortex",
}
## Habilidades de buff (duração em buffs.json, lida por Game.buff_duration) -> a chave "ability_time:<chave>".
## Só estas aceitam a Persistência. A Fúria Picante da montante é o mesmo buff da Fúria da espada.
const TIME_KEY := {
	"sword_fury": "sword_fury",
	"sword_fury_great": "sword_fury",
	"bow_focus": "bow_focus",
	"staff_ember": "staff_ember",
	"scepter_ward": "scepter_ward",
	"sword_rally": "sword_rally",
}
## Ordem dos tipos de melhoria de habilidade (ExpeditionUpgrades.ABILITY_KINDS) ao montar as opções.
const UPGRADE_KINDS := ["potencia", "recarga", "persistencia"]


## Nome de uma habilidade (ItemDB.ABILITIES) ou o próprio id.
static func ability_name(id: String) -> String:
	return str(ItemDB.ABILITIES.get(id, {}).get("name", id))


static func dmg_key(id: String) -> String:
	return str(DMG_KEY.get(id, id))


static func time_key(id: String) -> String:
	return str(TIME_KEY.get(id, id))


## A habilidade `id` aceita a melhoria do tipo `kind`: tem que poder sair num altar (não ultimate, pronta) e o tipo
## tem que mexer em algo que ela usa (dano pelo multiplicador, recarga própria, buff com duração).
static func supports(id: String, kind: String) -> bool:
	if not can_offer(id):
		return false
	match kind:
		"potencia":
			return DMG_KEY.has(id)
		"recarga":
			return float(ItemDB.ABILITIES[id].get("cooldown", 0.0)) > 0.0
		"persistencia":
			return TIME_KEY.has(id)
	return false


## Melhorias de habilidade que dá para oferecer agora: para cada habilidade do kit ativo (`active` = active_kit),
## cada tipo que ela aceita e que ainda não chegou ao máximo em `taken` (ExpeditionRun.modifiers).
static func upgrade_pool(active: Array, taken: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for ab in active:
		for kind in UPGRADE_KINDS:
			var id := ExpeditionUpgrades.ability_upgrade(kind, str(ab))
			if supports(str(ab), kind) and ExpeditionUpgrades.can_take(id, taken):
				out.append(id)
	return out


## As opções do Altar Ancestral (ids misturados): habilidade nova (id de ItemDB.ABILITIES), melhoria de habilidade
## ("potencia@sword_vortex"...) e bênção de run (ExpeditionUpgrades.DATA, só as do sorteio). Sorteio controlado pela
## build: primeiro uma de cada categoria que tem opção (nova habilidade, melhoria, bênção), e as vagas que sobram
## saem das categorias que ainda têm opção, preferindo melhoria de uma habilidade ainda não sorteada. Nunca repete
## nem oferece algo inválido (já levada, ultimate, no máximo); [] só se não sobrar nada em categoria nenhuma.
## `ctx` (opcional): o contexto da classe para as bênçãos (ExpeditionUpgrades.roll; ExpeditionRun.roll_context):
## com ele, a bênção que sai é de preferência uma da classe.
static func roll_evolution(rng: RandomNumberGenerator, full_kit: Array, owned: Array, taken: Dictionary,
		n := CHOICES, ctx := {}) -> Array[String]:
	var news := _shuffled(rng, pool(full_kit, owned))
	var ups := _shuffled(rng, upgrade_pool(active_kit(full_kit, owned), taken))
	var boons := ExpeditionUpgrades.roll(rng, taken, n, ctx)
	var out: Array[String] = []
	for cat in [news, ups, boons]:
		if out.size() < n and not (cat as Array).is_empty():
			out.append((cat as Array).pop_front())
	while out.size() < n and not (ups.is_empty() and news.is_empty() and boons.is_empty()):
		if not ups.is_empty():
			# outra melhoria: de preferência de outra habilidade (variedade); senão a próxima da lista
			var pick := 0
			for i in ups.size():
				if not _has_ability(out, ExpeditionUpgrades.ability_of(ups[i])):
					pick = i
					break
			out.append(ups.pop_at(pick))
		elif not news.is_empty():
			out.append(news.pop_front())
		else:
			out.append(boons.pop_front())
	return out


## Categoria de uma opção de altar: "skill" (habilidade nova), "ability" (melhoria de habilidade), "boon" (bênção de
## run) ou "" (inválida).
static func option_kind(id: String) -> String:
	if ItemDB.ABILITIES.has(id):
		return "skill"
	if ExpeditionUpgrades.is_ability_upgrade(id):
		return "ability"
	if ExpeditionUpgrades.has(id):
		return "boon"
	return ""


static func _has_ability(opts: Array, ability: String) -> bool:
	for o in opts:
		if ExpeditionUpgrades.ability_of(str(o)) == ability:
			return true
	return false


static func _shuffled(rng: RandomNumberGenerator, ids: Array) -> Array[String]:
	var left: Array[String] = []
	for id in ids:
		left.append(str(id))
	var out: Array[String] = []
	while not left.is_empty():
		out.append(left.pop_at(rng.randi_range(0, left.size() - 1)))
	return out
