class_name AegisConfig
extends Resource
## Configuração da Égide Cristalina (habilidade 1 da espada com escudo). Um só recurso para o visual
## (AegisBarrier e as peças dela) e para a defesa (AegisRules): edite assets/vfx/aegis/aegis_config.tres
## no Inspector. A defesa lê só o grupo "Integridade"; o resto é visual.

@export_group("Círculo mágico")
## Tempo para o círculo do chão se desenhar do centro para fora (s).
@export_range(0.05, 2.0, 0.01) var circle_form_time := 0.55
## Raio do círculo do chão (m).
@export_range(0.5, 6.0, 0.05) var circle_radius := 3.25
## Velocidade de rotação dos anéis (rad/s); os dois anéis giram em sentidos opostos.
@export_range(0.0, 6.0, 0.05) var ring_speed := 0.7
## Partículas de energia por segundo perto do chão.
@export_range(0, 120, 1) var ground_motes := 45

@export_group("Barreira")
## Tempo para a barreira crescer de baixo para cima, depois que o círculo aparece (s).
@export_range(0.1, 3.0, 0.01) var barrier_form_time := 0.8
## Altura do escudo (m, do chão ao topo).
@export_range(1.0, 5.0, 0.05) var shield_height := 2.6
## Largura do escudo (raio da coroa, m). 2,9 m cabe o herói e mais uns 4 personagens dentro.
@export_range(0.6, 6.0, 0.05) var shield_width := 2.9
## Quantidade de placas em losango (arredonda para fileiras completas).
@export_range(6, 120, 1) var plate_count := 36
## Fileiras da coroa (cada uma desencontrada meio losango da anterior, como na sprite sheet).
@export_range(1, 5, 1) var plate_rows := 2
## Brilho das bordas das placas.
@export_range(0.0, 6.0, 0.05) var plate_glow := 1.9
## Opacidade do preenchimento das placas (o personagem continua visível por dentro).
@export_range(0.0, 0.6, 0.01) var plate_fill := 0.12

@export_group("Integridade")
## Integridade máxima base do escudo (pontos de dano absorvidos).
@export_range(1.0, 2000.0, 1.0) var max_integrity := 70.0
## Integridade extra por nível do personagem.
@export_range(0.0, 100.0, 0.5) var integrity_per_level := 9.0
## Integridade extra por ponto de defesa do equipamento.
@export_range(0.0, 50.0, 0.5) var integrity_per_defense := 4.0
## Fração do dano (já reduzido pela defesa) que o escudo absorve; o resto passa para a vida.
@export_range(0.0, 1.0, 0.01) var absorb_ratio := 1.0
## Velocidade de andar enquanto segura o escudo (fração da normal). 0 = parado: a habilidade prende o herói no lugar.
@export_range(0.0, 1.0, 0.01) var walk_speed_mult := 0.0

@export_group("Rachaduras")
## Intensidade luminosa das rachaduras (multiplica o brilho).
@export_range(0.0, 8.0, 0.05) var crack_intensity := 1.9
## Quanto as rachaduras se espalham por dano recebido (1 = proporcional ao dano perdido).
@export_range(0.2, 3.0, 0.05) var crack_spread := 1.15
## Integridade (fração) abaixo da qual placas soltam fragmentos e algumas caem sozinhas.
@export_range(0.0, 1.0, 0.01) var shed_below := 0.4

@export_group("Quebra")
## Tempo entre a integridade zerar e o escudo estourar (a pulsação luminosa, s).
@export_range(0.0, 1.5, 0.01) var break_delay := 0.28
## Intensidade dos fragmentos (quantidade e velocidade).
@export_range(0.1, 3.0, 0.05) var shard_intensity := 1.0
## Tempo de dissipação dos fragmentos, partículas e do círculo do chão (s).
@export_range(0.2, 4.0, 0.05) var dissipate_time := 1.3

@export_group("Sprite sheet")
## Intensidade da sprite sheet tocada por cima da quebra (estilhaços partindo e se dissipando).
@export_range(0.0, 3.0, 0.05) var sheet_intensity := 0.9
