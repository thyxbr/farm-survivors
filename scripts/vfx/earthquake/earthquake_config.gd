class_name EarthquakeConfig
extends Resource
## Configuração do Terremoto Devastador (habilidade 2 da espada com escudo). Um só recurso para o dano e a recarga
## (EarthquakeAbilities, EarthquakeDamage, ItemDB.cooldown_of) e para o visual (EarthquakeSkill e as peças dele):
## edite assets/vfx/earthquake/earthquake_config.tres no Inspector, sem mexer no código.

@export_group("Combate")
## Dano da habilidade: multiplica o dano corpo a corpo do herói (Game.melee_damage), como as outras da espada.
@export_range(0.1, 10.0, 0.05) var damage_mult := 2.2
## Raio máximo da onda de choque (m), em volta do ponto onde o escudo bate. Quem estiver dentro leva o golpe
## quando a onda chega nele; quem estiver fora, nada.
@export_range(2.0, 20.0, 0.1) var radius := 9.0
## Velocidade de expansão da onda (m/s) no começo; ela desacelera perto do raio máximo
## (EarthquakeRules.wave_radius).
@export_range(2.0, 60.0, 0.5) var expansion_speed := 16.0
## Atordoamento de quem é atingido (s; 0 = nenhum).
@export_range(0.0, 3.0, 0.05) var stun_time := 0.8
## Tempo de recarga (s). Conta a partir do uso, como as outras habilidades.
@export_range(0.5, 120.0, 0.5) var cooldown := 10.0

@export_group("Movimento do escudo")
## Tempo para erguer o escudo bem alto (s): o chão vai acumulando pressão (rachaduras pequenas e pedrinhas
## tremendo).
@export_range(0.15, 2.0, 0.01) var windup_time := 0.55
## Tempo da descida do escudo até tocar o chão (s): o impacto é no fim dela.
@export_range(0.05, 0.6, 0.01) var slam_time := 0.13
## Tempo que o herói fica agachado com o escudo cravado depois do impacto (s).
@export_range(0.0, 1.5, 0.01) var hold_time := 0.3
## Tempo para voltar à postura normal (s).
@export_range(0.05, 1.5, 0.01) var recover_time := 0.35
## Distância à frente do herói onde a borda do escudo toca o chão (m): o centro da onda.
@export_range(0.0, 2.0, 0.01) var forward_offset := 0.75

@export_group("Impacto")
## Intensidade da explosão inicial (multiplica clarão, partículas, fragmentos e o tremor da câmera).
@export_range(0.0, 3.0, 0.05) var impact_intensity := 1.0
## Tremor da câmera no centro do impacto (diminui com a distância até `shake_range`).
@export_range(0.0, 2.0, 0.01) var shake_strength := 0.85
## Até que distância do impacto a câmera de quem vê treme (m).
@export_range(1.0, 80.0, 0.5) var shake_range := 30.0
## Congelamento curto no impacto (s; só no herói que usou; 0 = nenhum).
@export_range(0.0, 0.25, 0.005) var hitstop_time := 0.075

@export_group("Rachaduras")
## Quantidade de rachaduras principais saindo do centro (cada uma ainda abre ramificações).
@export_range(0, 40, 1) var crack_count := 14
## Comprimento das rachaduras em relação ao raio (1 = até a borda da onda).
@export_range(0.1, 1.2, 0.01) var crack_length := 0.92
## Chance de cada trecho abrir uma ramificação (0 = rachaduras retas, sem galhos).
@export_range(0.0, 1.0, 0.01) var crack_branching := 0.45
## Largura das rachaduras principais junto ao centro (m); afinam até a ponta.
@export_range(0.05, 1.0, 0.01) var crack_width := 0.34
## Placas de pedra que se levantam ao redor das rachaduras.
@export_range(0, 60, 1) var plate_count := 22
## Tamanho médio das placas (m).
@export_range(0.2, 2.5, 0.05) var plate_size := 0.85
## Explosões secundárias nas pontas de algumas rachaduras.
@export_range(0, 16, 1) var secondary_count := 6

@export_group("Fragmentos e poeira")
## Quantidade de fragmentos de pedra lançados (somando o impacto, a onda e as explosões secundárias).
@export_range(0, 400, 1) var debris_count := 140
## Altura dos fragmentos (m): quanto as pedras maiores sobem no impacto (as outras sobem proporcionalmente).
@export_range(0.2, 12.0, 0.1) var debris_height := 4.5
## Intensidade da poeira (multiplica a quantidade e a densidade da poeira no chão e na frente da onda).
@export_range(0.0, 3.0, 0.05) var dust_intensity := 1.0

@export_group("Dissipação")
## Tempo de dissipação depois que a onda chega ao raio máximo (s): o anel apaga, as rachaduras esfriam, as placas
## voltam ao chão, as pedras somem e a poeira assenta, cada um no seu ritmo (nada some de uma vez).
@export_range(0.5, 12.0, 0.1) var dissipation_time := 3.2

@export_group("Câmera")
## Quanto a câmera recua durante a habilidade (m), para a onda inteira caber na tela.
@export_range(0.0, 10.0, 0.05) var camera_back := 2.5


## Tempo do começo da habilidade até o escudo tocar o chão (s).
func impact_time() -> float:
	return windup_time + slam_time


## Tempo do herói na habilidade (s): ergue, bate, segura e volta.
func total_time() -> float:
	return impact_time() + hold_time + recover_time


## Quanto a onda leva do impacto até o raio máximo (s).
func expansion_time() -> float:
	return EarthquakeRules.expansion_time(radius, expansion_speed)
