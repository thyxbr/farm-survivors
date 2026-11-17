class_name PartyRules
extends RefCounted
## Recompensa de abate com grupo (puro, sem autoload; usado pelo servidor no Network.server_enemy_killed).
##
## - Cada grupo (ou jogador sem grupo) que acertou o monstro recebe UMA vez o XP dele, dividido em partes
##   iguais entre os membros do grupo que estão na mesma zona do monstro (Valdoria). Quem está em outra zona
##   (ainda carregando o mapa) não recebe.
## - O abate (contagem, progresso de missão, chefe derrotado) conta para quem acertou e para os membros do
##   grupo perto do combate (até SHARE_RANGE metros do monstro, medido no chão). Longe: só o XP.
## - O loot continua um sorteio para cada jogador que acertou (como sem grupo).

## Distância (m, no plano) do monstro até onde o membro do grupo "está no combate".
const SHARE_RANGE := 45.0
## Buffs mostrados no quadro do grupo: no máximo tantos, e cada um com no máximo tantos segundos.
const MAX_BUFFS := 6
const MAX_BUFF_SECS := 3600


## Recompensas de um abate: peer -> {"xp": int, "kill": bool, "loot": bool}.
##   xp            XP do monstro (data.xp)
##   contributors  quem acertou (já filtrados pela zona do monstro)
##   teams         peer -> [membros do grupo dele, incluindo ele]; sem grupo = ausente (ou vazio)
##   pos_of        peer -> última posição conhecida (Vector3)
##   zone_of       peer -> zona ("world" ou "loading")
##   at, zone      posição e zona do monstro
static func kill_rewards(xp: int, contributors: Array, teams: Dictionary, pos_of: Dictionary,
		zone_of: Dictionary, at: Vector3, zone: String) -> Dictionary:
	var out := {}
	xp = maxi(0, xp)
	for c in contributors:
		if out.has(c):
			continue   # já recebeu pelo grupo de outro que acertou
		var team: Array = teams.get(c, [])
		if team.is_empty() or not (c in team):
			team = [c]
		var eligible: Array = []
		for p in team:
			if p == c or p in contributors or str(zone_of.get(p, "")) == zone:
				eligible.append(p)
		var share := ceili(float(xp) / eligible.size()) if xp > 0 else 0
		for p in eligible:
			out[p] = {"xp": share, "kill": p in contributors or near(pos_of.get(p), at),
				"loot": p in contributors}
	return out


## Nível de referência de cada quem recebe XP de um abate (para o ajuste por diferença de nível):
## o maior nível entre os que recebem e são do mesmo grupo dele. Quem não tem grupo usa o próprio nível;
## outro jogador que só acertou o mesmo monstro (sem grupo em comum) não conta.
##   recipients  quem recebe (chaves de kill_rewards)
##   teams       peer -> [membros do grupo dele, incluindo ele]
##   level_of    peer -> nível (sem a chave = 1)
static func group_levels(recipients: Array, teams: Dictionary, level_of: Dictionary) -> Dictionary:
	var out := {}
	for p in recipients:
		var best := int(level_of.get(p, 1))
		var team: Array = teams.get(p, [])
		if p in team:
			for m in team:
				if m in recipients:
					best = maxi(best, int(level_of.get(m, 1)))
		out[p] = best
	return out


## Buffs que um cliente declarou para o quadro do grupo ({id do buff: segundos restantes}), limpos:
## só ids da tabela `buffs` (comida e habilidades), segundos inteiros entre 1 e MAX_BUFF_SECS, no máximo MAX_BUFFS.
## É só visual (o efeito do buff roda no cliente), mas o dicionário vem da rede e vai para os outros jogadores.
static func clean_buffs(buffs, buff_table: Dictionary) -> Dictionary:
	var out := {}
	if not (buffs is Dictionary):
		return out
	var ids: Array = buffs.keys()
	ids.sort()
	for id in ids:
		if out.size() >= MAX_BUFFS:
			break
		var secs = buffs[id]
		if not (id is String) or not buff_table.has(id):
			continue
		if not (secs is int or secs is float) or not is_finite(float(secs)):
			continue
		var t := clampi(int(ceil(float(secs))), 0, MAX_BUFF_SECS)
		if t > 0:
			out[id] = t
	return out


## Se a posição está perto do combate (null/INF = posição desconhecida = longe).
static func near(pos, at: Vector3) -> bool:
	if not (pos is Vector3) or not (pos as Vector3).is_finite():
		return false
	var d := Vector2(pos.x - at.x, pos.z - at.z)
	return d.length() <= SHARE_RANGE
