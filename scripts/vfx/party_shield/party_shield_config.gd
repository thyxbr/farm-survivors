class_name PartyShieldConfig
extends Resource
## Configuração do Grito do Bastião (habilidade 5 da espada com escudo). Um só recurso para a regra
## (PartyShieldAbilities, ItemDB.cooldown_of, o servidor em Network._request_party_buff) e para o visual
## (PartyShieldCast no herói enquanto grita, PartyShieldBuff em cada aliado com o buff): edite
## assets/vfx/party_shield/party_shield_config.tres no Inspector, sem mexer no código.
## A duração do buff e o bônus de defesa ficam na tabela de balanceamento (data/balance/buffs.json, "sword_rally"),
## que o servidor e o cliente leem igual.

@export_group("Grupo")
## Distância máxima (m) entre o herói e cada membro do grupo para receber o buff, no momento em que o grito termina.
## O herói sempre recebe. Sem grupo, só ele.
@export_range(1.0, 200.0, 0.5) var radius := 30.0
## Tempo de recarga (s). Conta a partir do uso; nunca fica abaixo da duração do buff + 4 s (Game.ability_cooldown).
@export_range(0.5, 180.0, 0.5) var cooldown := 30.0

@export_group("Animação")
## Velocidade da animação do grito (o clipe "Sword And Shield Power Up", 2,36 s em 1x). 1,6 = 1,48 s até o buff.
## O grito, a aura e o buff acompanham (PartyShieldAbilities.total_time).
@export_range(0.5, 3.0, 0.05) var cast_speed := 1.6

@export_group("Aura do grito")
## Cor da aura azul em volta do herói enquanto a animação roda.
@export var aura_color := Color(0.35, 0.68, 1.0)
## Brilho da aura (1 = suave; 2 = forte).
@export_range(0.0, 3.0, 0.05) var aura_intensity := 1.0
## Tempo para a aura acender no começo (s) e para apagar no fim (s): suave nas duas pontas.
@export_range(0.05, 2.0, 0.01) var aura_fade_in := 0.45
@export_range(0.05, 2.0, 0.01) var aura_fade_out := 0.5
## Tamanho (m) do quadro da sprite sheet da formação (faísca, escudos subindo, anel fechando) em volta do herói.
@export_range(0.5, 6.0, 0.05) var cast_sheet_size := 2.6
## Raio máximo (m) da onda do grito no chão.
@export_range(0.5, 20.0, 0.1) var shout_wave_radius := 6.0
## Energia da luz azul que acompanha a aura (0 = sem luz).
@export_range(0.0, 6.0, 0.05) var light_energy := 1.6

@export_group("Escudos em volta de cada um")
## Quantos escudos pequenos giram em volta de cada personagem com o buff (o único visual do buff no corpo).
@export_range(0, 12, 1) var shield_count := 5
## Tamanho de cada escudo (m; ~ uma mão do herói).
@export_range(0.05, 0.8, 0.01) var shield_size := 0.22
## Raio da órbita (m) e altura do centro dela acima dos pés (m).
@export_range(0.2, 3.0, 0.01) var orbit_radius := 0.78
@export_range(0.0, 3.0, 0.01) var orbit_height := 1.0
## Velocidade da órbita (rad/s) e quanto cada escudo sobe e desce (m).
@export_range(-8.0, 8.0, 0.05) var orbit_speed := 1.5
@export_range(0.0, 0.5, 0.01) var orbit_bob := 0.07
## Brilho dos escudos.
@export_range(0.0, 3.0, 0.05) var buff_intensity := 1.4
## Tempo de entrada (s): os escudos crescem e acendem.
@export_range(0.05, 2.0, 0.01) var intro_time := 0.45

@export_group("Dissipação")
## Tempo (s) dos escudos se desfazendo em partículas azuis pequenas quando o buff acaba.
@export_range(0.1, 4.0, 0.05) var dissipate_time := 1.1
## Partículas soltas na dissipação (em volta da órbita).
@export_range(0, 200, 1) var dissipate_particles := 48

@export_group("Câmera")
## Quanto a câmera recua enquanto o herói grita (m).
@export_range(0.0, 10.0, 0.05) var camera_back := 1.2
