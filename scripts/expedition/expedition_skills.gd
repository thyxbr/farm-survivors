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
