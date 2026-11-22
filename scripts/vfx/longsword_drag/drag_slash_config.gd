class_name DragSlashConfig
extends Resource
## Configuração do Corte do Abismo (montante, tecla 2). Um só recurso para o dano e o movimento (DragSlashAbilities), o
## ritmo da animação (DragSlashAbilities.pose) e o visual (DragAndSlash): edite
## assets/vfx/longsword_drag/drag_slash_config.tres no Inspector, sem mexer no código.

@export_group("Corrida")
## Preparo: a ponta da montante desce até o chão e o herói arranca (s). A esquiva cancela até o corte.
@export_range(0.05, 0.6, 0.01) var windup_time := 0.16
## Distância máxima da corrida (m).
@export_range(1.0, 16.0, 0.1) var dash_distance := 7.5
## Velocidade da corrida (m/s): bem acima do correr normal (8,6).
@export_range(4.0, 30.0, 0.5) var dash_speed := 14.0
## Tempo máximo correndo (s; segurança se algo prender o herói).
@export_range(0.2, 2.0, 0.05) var dash_max_time := 0.85
## A corrida para antes se houver um inimigo no caminho a esta distância (m) da frente do herói: o corte sai nele.
@export_range(0.3, 4.0, 0.05) var stop_distance := 1.6
## Meia-largura do caminho onde um inimigo faz a corrida parar (m).
@export_range(0.2, 3.0, 0.05) var lane_half_width := 1.0

@export_group("Corte")
## Último passo: o herói finca o pé, abaixa e enrola o tronco com a lâmina ainda raspando (s).
@export_range(0.05, 0.6, 0.01) var plant_time := 0.14
## O corte de baixo para cima, da lâmina atrás até o alto (s). O acerto é em `hit_at` dele.
@export_range(0.06, 0.6, 0.01) var rise_time := 0.2
## Fração do corte em que a lâmina passa à frente e acerta (0..1).
@export_range(0.2, 1.0, 0.01) var hit_at := 0.62
## Segura a espada no alto (s).
@export_range(0.0, 1.0, 0.01) var hold_time := 0.2
## Volta para a guarda (s).
@export_range(0.1, 1.5, 0.01) var recover_time := 0.45
## Dano do corte: multiplica o dano corpo a corpo (Game.melee_damage).
@export_range(0.1, 8.0, 0.05) var slash_mult := 1.6
## Alcance do corte à frente (m) e meio ângulo do arco (graus).
@export_range(0.5, 6.0, 0.05) var slash_radius := 2.8
@export_range(10.0, 180.0, 1.0) var slash_half_angle := 70.0
## Empurrão do corte para longe do herói (m/s) e atordoamento (s).
@export_range(0.0, 20.0, 0.5) var slash_knockback := 5.0
@export_range(0.0, 2.0, 0.05) var slash_stun := 0.3

@export_group("Garras")
## Quantas garras espectrais irrompem do chão à frente (em fila, na direção do corte).
@export_range(1, 6, 1) var claw_count := 3
## Distância da primeira garra (m) e entre uma e outra (m); a fila alterna `claw_spread` m para os lados.
@export_range(0.5, 6.0, 0.05) var claw_first := 2.0
@export_range(0.3, 4.0, 0.05) var claw_step := 1.8
@export_range(0.0, 2.0, 0.05) var claw_spread := 0.45
## Atraso entre uma garra e a seguinte (s): elas saem do chão em onda.
@export_range(0.0, 0.4, 0.01) var claw_stagger := 0.085
## Raio da área de cada garra no chão (m).
@export_range(0.3, 4.0, 0.05) var claw_radius := 1.5
## Dano das garras (multiplica o dano corpo a corpo; cada inimigo leva no máximo uma garra) e atordoamento (s).
@export_range(0.1, 8.0, 0.05) var claw_mult := 1.3
@export_range(0.0, 3.0, 0.05) var claw_stun := 0.7
## Altura da garra desenhada (m) e quanto ela dura até se desfazer (s).
@export_range(0.5, 6.0, 0.05) var claw_height := 4.2
@export_range(0.3, 3.0, 0.05) var claw_life := 1.15

@export_group("Visual")
## Quadros por segundo das sprite sheets.
@export_range(4.0, 60.0, 1.0) var sheet_fps := 22.0
## Tamanho das fagulhas da sprite sheet atrás da ponta (m: comprimento para trás x altura).
@export var spark_sheet_size := Vector2(3.0, 1.5)
## Multiplica a quantidade de fagulhas, brasas, pedrinhas e poeira da corrida.
@export_range(0.0, 3.0, 0.05) var spark_amount := 1.0
## Altura do arco de energia do corte (m).
@export_range(0.5, 6.0, 0.05) var arc_height := 3.3
## Quanto o rastro incandescente da lâmina fica no ar (s).
@export_range(0.05, 1.0, 0.01) var trail_life := 0.2
## Quanto o sulco em brasa no chão fica aceso (s).
@export_range(0.1, 4.0, 0.05) var groove_life := 1.2

@export_group("Câmera")
## Tremor da câmera no corte e em cada garra (diminui com a distância até `shake_range`).
@export_range(0.0, 2.0, 0.01) var shake_strength := 0.35
@export_range(1.0, 60.0, 0.5) var shake_range := 22.0
## Congelamento curto no acerto do corte (só de quem bateu, s).
@export_range(0.0, 0.2, 0.005) var hitstop_time := 0.05


## Do começo do corte (o fim da corrida) até o acerto (s).
func hit_time() -> float:
	return plant_time + rise_time * hit_at


## Duração do corte inteiro no herói, do fim da corrida até voltar à guarda (s).
func slash_total() -> float:
	return plant_time + rise_time + hold_time + recover_time
