class_name PartyBook
extends RefCounted
## Grupos do multiplayer (puro: só ids de peer; o autoload Party guarda um no servidor e cuida da rede).
##
## Quem não tem grupo convida qualquer jogador sem grupo; quando o convidado aceita, nasce o grupo com quem
## convidou como líder. Num grupo só o líder convida e expulsa. Quem sai passa a liderança para o próximo
## membro; um grupo que fica com uma pessoa só se desfaz. Convites expiram em INVITE_TIME segundos.
## Os métodos que mudam algo devolvem "" (deu certo) ou o código do erro (texto em `explain`).

const MAX_MEMBERS := 4
const INVITE_TIME := 30.0

## party_id -> {"leader": peer, "members": [peers]}
var parties := {}
## peer -> party_id
var party_of := {}
## convidado -> {"from": peer, "t": segundos restantes}
var invites := {}
var _next_id := 1


## Membros do grupo do peer (incluindo ele); [] sem grupo.
func members(peer: int) -> Array:
	var id := int(party_of.get(peer, 0))
	return (parties[id].members as Array).duplicate() if parties.has(id) else []


func leader(peer: int) -> int:
	var id := int(party_of.get(peer, 0))
	return int(parties[id].leader) if parties.has(id) else 0


func in_party(peer: int) -> bool:
	return party_of.has(peer)


## peer -> [membros] de todos os peers com grupo (o formato de PartyRules.kill_rewards).
func teams() -> Dictionary:
	var out := {}
	for peer in party_of:
		out[peer] = members(peer)
	return out


func invite(from: int, to: int) -> String:
	if from == to:
		return "voce_mesmo"
	if in_party(to):
		return "ja_no_seu_grupo" if members(to).has(from) else "ja_em_grupo"
	if in_party(from):
		if leader(from) != from:
			return "nao_lider"
		if members(from).size() >= MAX_MEMBERS:
			return "cheio"
	if invites.has(to):
		return "convite_pendente"
	invites[to] = {"from": from, "t": INVITE_TIME}
	return ""


## O convidado aceita: entra no grupo de quem convidou (ou cria um com ele de líder).
func accept(to: int) -> String:
	if not invites.has(to):
		return "sem_convite"
	var from := int(invites[to].from)
	invites.erase(to)
	if in_party(to):
		return "ja_em_grupo"
	if in_party(from):
		var id := int(party_of[from])
		if (parties[id].members as Array).size() >= MAX_MEMBERS:
			return "cheio"
		parties[id].members.append(to)
		party_of[to] = id
		return ""
	var nid := _next_id
	_next_id += 1
	parties[nid] = {"leader": from, "members": [from, to]}
	party_of[from] = nid
	party_of[to] = nid
	return ""


## Recusa o convite; devolve quem tinha convidado (0 = não havia convite).
func decline(to: int) -> int:
	if not invites.has(to):
		return 0
	var from := int(invites[to].from)
	invites.erase(to)
	return from


func leave(peer: int) -> String:
	var id := int(party_of.get(peer, 0))
	if not parties.has(id):
		return "sem_grupo"
	var p: Dictionary = parties[id]
	p.members.erase(peer)
	party_of.erase(peer)
	if (p.members as Array).size() < 2:
		for m in p.members:
			party_of.erase(m)
		parties.erase(id)
	elif int(p.leader) == peer:
		p.leader = p.members[0]
	return ""


func kick(by: int, target: int) -> String:
	if not in_party(by):
		return "sem_grupo"
	if leader(by) != by:
		return "nao_lider"
	if by == target or not members(by).has(target):
		return "fora_do_grupo"
	return leave(target)


## Peer saiu do servidor: sai do grupo e os convites dele (feitos e recebidos) somem.
func drop(peer: int) -> void:
	leave(peer)
	invites.erase(peer)
	for to in invites.keys():
		if int(invites[to].from) == peer:
			invites.erase(to)


## Conta o tempo dos convites; devolve os convidados cujo convite expirou.
func tick(delta: float) -> Array:
	var out: Array = []
	for to in invites.keys():
		invites[to].t -= delta
		if invites[to].t <= 0.0:
			invites.erase(to)
			out.append(to)
	return out


static func explain(err: String) -> String:
	match err:
		"voce_mesmo": return "Você não pode convidar a si mesmo."
		"ja_em_grupo": return "Esse jogador já está em outro grupo."
		"ja_no_seu_grupo": return "Esse jogador já está no seu grupo."
		"nao_lider": return "Só o líder do grupo pode fazer isso."
		"cheio": return "O grupo está cheio (máximo %d)." % MAX_MEMBERS
		"convite_pendente": return "Esse jogador já tem um convite esperando resposta."
		"sem_convite": return "O convite expirou."
		"sem_grupo": return "Você não está em um grupo."
		"fora_do_grupo": return "Esse jogador não está no seu grupo."
		"sem_jogador": return "Jogador não encontrado."
	return err
