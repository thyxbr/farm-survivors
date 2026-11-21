class_name HammerConfig
extends Resource
## Configuração do Martelo de Energia (habilidade 4 da espada com escudo). Um só recurso para o dano e a recarga
## (HammerAbilities, ItemDB.cooldown_of) e para o visual (HammerSkill e as peças dele): edite
## assets/vfx/hammer/hammer_config.tres no Inspector, sem mexer no código.

@export_group("Combate")
## Dano da habilidade: multiplica o dano corpo a corpo do herói (Game.melee_damage), como as outras da espada.
@export_range(0.1, 10.0, 0.05) var damage_mult := 2.6
## Raio de alcance do dano (m), em volta do ponto onde o martelo cai. O círculo de crateras e a onda de choque
## seguem este raio.
@export_range(1.0, 16.0, 0.1) var radius := 7.0
## Atordoamento de quem é atingido (s; 0 = nenhum).
@export_range(0.0, 3.0, 0.05) var stun_time := 0.6
## Tempo de recarga (s). Conta a partir do uso, como as outras habilidades.
@export_range(0.5, 120.0, 0.5) var cooldown := 12.0
## Distância à frente do herói onde o martelo cai (m). O círculo fica sobre esse ponto, acima da cabeça dele.
@export_range(0.0, 6.0, 0.05) var forward_offset := 2.2

@export_group("Círculo mágico")
## Altura do círculo mágico acima do chão (m).
@export_range(2.5, 16.0, 0.05) var circle_height := 9.5
## Raio do círculo mágico (m). 3,25 = o mesmo do círculo da Égide Cristalina (AegisConfig.circle_radius).
@export_range(0.5, 6.0, 0.05) var circle_radius := 3.25
## Tempo para o círculo se materializar (s).
@export_range(0.1, 2.0, 0.01) var circle_form_time := 0.5
## Velocidade de rotação do círculo (rad/s).
@export_range(0.0, 6.0, 0.05) var circle_spin := 0.9
## Tempo de fechamento do círculo depois que o martelo termina de sair (s).
@export_range(0.05, 2.0, 0.01) var circle_close_time := 0.4

@export_group("Martelo")
## Tamanho do martelo (comprimento total, m), proporcional ao círculo: 6,9 m com o raio 3,25 (a cabeça ocupa
## metade do diâmetro). O herói tem ~1,8 m.
@export_range(1.0, 14.0, 0.05) var hammer_size := 6.9
## Velocidade de formação: tempo (s) para o martelo sair inteiro do círculo, cabeça primeiro e cabo depois.
@export_range(0.1, 3.0, 0.01) var formation_time := 0.9
## Quanto o martelo sobe enquanto o círculo fecha (preparo antes da queda, m).
@export_range(0.0, 3.0, 0.01) var windup_lift := 1.0
## Velocidade de queda: aceleração (m/s²). Mais alta = cai mais rápido (com 42 a queda leva ~0,4 s).
@export_range(5.0, 200.0, 1.0) var fall_acceleration := 42.0
## Velocidade com que a queda começa (m/s).
@export_range(0.0, 20.0, 0.1) var fall_start_speed := 1.5
## Tempo de permanência do martelo cravado depois do impacto (s), perdendo o brilho e rachando.
@export_range(0.0, 4.0, 0.05) var linger_time := 0.7
## Tempo de dissolução do martelo (s): primeiro a cabeça, depois o cabo, virando partículas que sobem.
@export_range(0.1, 4.0, 0.05) var dissolve_time := 1.1

@export_group("Impacto")
## Intensidade da explosão (multiplica brilho, partículas, fragmentos e o tremor da câmera).
@export_range(0.0, 3.0, 0.05) var explosion_intensity := 1.0
## Quantidade de crateras em volta do ponto central.
@export_range(0, 40, 1) var crater_count := 14
## Distância máxima das crateras ao centro (m). Fica um pouco dentro do raio de dano.
@export_range(0.5, 16.0, 0.1) var crater_max_distance := 6.2
## Distância mínima das crateras ao centro (m): o miolo é da cratera principal, do impacto.
@export_range(0.0, 8.0, 0.1) var crater_min_distance := 2.4
## Raio de cada cratera (m; cada uma varia um pouco).
@export_range(0.2, 4.0, 0.05) var crater_size := 1.2
## Velocidade com que a força se espalha pelo chão (m/s): as crateras aparecem nessa onda, em sequência.
@export_range(2.0, 80.0, 0.5) var crater_wave_speed := 26.0
## Quanto tempo cada cratera fica antes de sumir aos poucos (s).
@export_range(0.5, 20.0, 0.1) var crater_life := 3.2

@export_group("Choque no chão")
## Tamanho da onda de choque da sprite sheet (hammer_shock_sheet.webp) em relação ao raio de dano: 1,8 = as
## fissuras desenhadas chegam perto da borda do raio.
@export_range(0.0, 4.0, 0.05) var shock_sheet_scale := 1.8
## Tempo para tocar a onda de choque inteira (s): clarão, explosão, fumaça e as fissuras esfriando.
@export_range(0.3, 4.0, 0.05) var shock_sheet_time := 1.7
## Tamanho das rachaduras projetadas (Decal) em relação ao raio de dano.
@export_range(0.2, 2.0, 0.05) var crack_decal_scale := 1.15
## Quanto tempo as rachaduras projetadas ficam no chão antes de sumir de vez (s).
@export_range(0.5, 20.0, 0.1) var crack_decal_life := 4.5
## Detritos, brasas e fumaça (GPUParticles3D): multiplica a quantidade de cada um.
@export_range(0.0, 3.0, 0.05) var debris_amount := 1.0
## Tremor da câmera no centro do impacto (diminui com a distância até `shake_range`).
@export_range(0.0, 2.0, 0.01) var shake_strength := 0.75
## Até que distância do impacto a câmera de quem vê treme (m).
@export_range(1.0, 80.0, 0.5) var shake_range := 28.0
## Congelamento curto no impacto (s; só no herói que usou; 0 = nenhum).
@export_range(0.0, 0.25, 0.005) var hitstop_time := 0.07

@export_group("Câmera")
## Quanto a câmera recua durante a habilidade (m), para o círculo no alto caber na tela.
@export_range(0.0, 10.0, 0.05) var camera_back := 5.0
## Quanto a câmera inclina para cima durante a habilidade (rad), para o círculo lá no alto caber na tela.
@export_range(0.0, 0.8, 0.01) var camera_tilt := 0.32


## Tempo do começo até o martelo tocar o chão (s): materializar, formar, fechar e cair.
func impact_time() -> float:
	return circle_form_time + formation_time + circle_close_time + fall_time()


## Duração da queda: da altura em que o martelo fica (pronto + preparo) até o chão.
func fall_time() -> float:
	return HammerRules.fall_time(fall_height(), fall_start_speed, fall_acceleration)


## Altura da cabeça do martelo acima do chão quando a queda começa (m).
func fall_height() -> float:
	return maxf(circle_height - hammer_size + windup_lift, 0.05)
