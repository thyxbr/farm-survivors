class_name PartyShieldRules
extends RefCounted
## Grito do Bastião: contas puras (sem nó nem autoload), para os testes unitários e para o servidor: quem do grupo
## recebe o buff, a defesa com o bônus percentual, o intervalo mínimo entre dois usos aceitos e o relógio da sprite
## sheet (formação) e da órbita dos escudos pequenos.

## Id da habilidade (ItemDB.ABILITIES) e do buff que ela dá (data/balance/buffs.json): o mesmo.
const ID := "sword_rally"
const BUFF := "sword_rally"

## Clipe do herói: "Sword And Shield Power Up" do Mixamo (KnightMoves.TAUNT_CAST, 2,36 s, tocado inteiro em tempo
## real). O grito sai na explosão do clipe (o peito abre e os braços vão para fora, KnightMoves.TAUNT_BURST) e o buff
## entra quando a animação termina (CLIP_END).
const SHOUT_AT := 0.55
const CLIP_END := 2.36

## Quadros da sprite sheet (assets/vfx/party_shield/party_shield_sheet.png, 8 x 8, realinhada por
## tools/party_shield_sheet_bake.gd): a formação (faísca, escudos subindo, anel fechando), tocada na aura do grito.
const FORM_FIRST := 1
const FORM_LAST := 18

## Duração (s) da animação do grito na velocidade `speed` (1 = o clipe original de CLIP_END s).
static func cast_time(speed: float) -> float:
	return CLIP_END / maxf(speed, 0.05)


## Folga (s) no intervalo do servidor para o atraso da rede.
const NET_SLACK := 0.5
## Menor multiplicador de recarga do jogo (Game.cooldown_mult) e folga do piso do buff (Game.ability_cooldown).
const MIN_CD_MULT := 0.4
const BUFF_CD_FLOOR := 4.0


## Defesa final: a fixa (`flat`) vezes 1 + o bônus percentual (`pct`, ex.: 0.25 = +25%). O percentual nunca tira
## mais que 95% (um bônus negativo de outra fonte não deixa a defesa negativa).
static func defense_with(flat: float, pct: float) -> float:
	return flat * (1.0 + maxf(pct, -0.95))


## Quem recebe o buff do `caster`: ele sempre; e cada membro do grupo dele (`party`, ids de peer; [] sem grupo) que
## está na mesma zona (`zone_peers`) e a até `radius` m dele no chão (`positions`: peer -> última posição; sem
## posição conhecida fica de fora). Sem repetir, o herói primeiro.
static func targets(caster: int, party: Array, zone_peers: Array, positions: Dictionary, radius: float) -> Array:
	var out := [caster]
	var origin: Vector3 = positions.get(caster, Vector3.INF)
	for pid in party:
		if pid == caster or pid in out or not (pid in zone_peers):
			continue
		var p: Vector3 = positions.get(pid, Vector3.INF)
		if not origin.is_finite() or not p.is_finite():
			continue
		if Vector2(p.x - origin.x, p.z - origin.z).length() <= radius:
			out.append(pid)
	return out


## Tem espada na mão e um escudo de espada na secundária? (`weapon_class` da arma, `offhand_needs` = o campo "needs"
## do item da mão secundária; "" sem nada nela)
static func has_kit(weapon_class: String, offhand_needs: String) -> bool:
	return weapon_class == "sword" and offhand_needs == "sword"


## Intervalo mínimo (s) entre dois usos aceitos pelo servidor: a menor recarga possível no cliente (recarga x o menor
## multiplicador, mas nunca abaixo da duração do buff + 4 s), menos a folga da rede.
static func min_interval(cooldown: float, buff_time: float) -> float:
	return maxf(cooldown * MIN_CD_MULT, buff_time + BUFF_CD_FLOOR) - NET_SLACK


static func interval_ok(last: float, now: float, cooldown: float, buff_time: float) -> bool:
	return now - last >= min_interval(cooldown, buff_time)


## Quadro (fracionário) da formação no instante `t` de uma formação de `dur` s: de FORM_FIRST a FORM_LAST.
static func form_frame(t: float, dur: float) -> float:
	var k := clampf(t / maxf(dur, 0.001), 0.0, 1.0)
	return lerpf(float(FORM_FIRST), float(FORM_LAST), k)


## Posição (relativa ao centro da órbita) do escudo `i` de `count` no instante `t`: espaçados por igual, girando a
## `speed` rad/s num círculo de raio `radius`, cada um subindo e descendo `bob` m fora de fase.
static func shield_offset(i: int, count: int, t: float, radius: float, speed: float, bob: float) -> Vector3:
	var a := TAU * float(i) / float(maxi(count, 1)) + t * speed
	return Vector3(cos(a) * radius, sin(t * 2.3 + float(i) * 1.7) * bob, sin(a) * radius)
