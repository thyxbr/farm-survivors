class_name GreatswordSpinConfig
extends Resource
## Configuração do Ciclone de Aço (montante, tecla 1). Um só recurso para o dano (GreatswordSpinAbilities), o ritmo do
## giro (GreatswordSpinRules, a pose em GreatswordSpinAbilities.pose) e o visual (GreatswordSpinSlash): edite
## assets/vfx/greatsword_spin/greatsword_spin_config.tres no Inspector, sem mexer no código.

@export_group("Combate")
## Dano de cada corte: multiplica o dano corpo a corpo do herói (Game.melee_damage).
@export_range(0.05, 5.0, 0.05) var damage_mult := 0.35
## Intervalo mínimo entre dois cortes no mesmo inimigo (s): sem isso o giro feriria a cada quadro.
@export_range(0.05, 2.0, 0.01) var hit_interval := 0.35
## Alcance da lâmina em volta do herói (m, no chão).
@export_range(0.5, 8.0, 0.05) var radius := 3.1
## Diferença de altura máxima entre o herói e o inimigo (m).
@export_range(0.5, 6.0, 0.05) var height := 2.5
## O giro só corta acima desta fração da velocidade máxima (no começo e no fim lento a lâmina não fere).
@export_range(0.0, 1.0, 0.01) var hit_min_speed := 0.3
## Puxão para perto a cada corte (m/s; 0 = o empurrão padrão do golpe). Segura a horda dentro do giro.
@export_range(0.0, 6.0, 0.1) var pull := 2.0

@export_group("Movimento")
## Velocidade de andar enquanto gira: multiplica a de andar normal (0 = preso no lugar). O herói vai para onde a tecla
## de andar mandar (relativo à câmera); o giro do corpo continua o mesmo.
@export_range(0.0, 1.5, 0.05) var move_speed := 0.75
## Quão rápido ele pega e perde essa velocidade (1/s): alto = responde na hora, baixo = escorrega.
@export_range(1.0, 40.0, 0.5) var move_accel := 10.0

@export_group("Ritmo")
## Postura parada antes do giro (s). 0 = o giro começa assim que a habilidade é acionada (os braços vão à frente já
## girando). Com mais de 0 a esquiva cancela nessa postura.
@export_range(0.0, 2.0, 0.01) var stance_time := 0.0
## Aceleração: de parado até a velocidade máxima de giro (s).
@export_range(0.05, 3.0, 0.01) var accel_time := 0.35
## Giro na velocidade máxima (s).
@export_range(0.1, 6.0, 0.05) var spin_time := 4.4
## Desaceleração suave até parar (s).
@export_range(0.05, 4.0, 0.01) var decel_time := 0.9
## Volta à guarda normal depois de parar (s).
@export_range(0.05, 2.0, 0.01) var recover_time := 0.35
## Voltas completas do giro inteiro: a velocidade máxima sai daqui, e o herói termina virado para onde começou.
@export_range(1, 40) var turns := 12
## Inclinação do corpo para trás enquanto gira, contrapeso da espada esticada (rad): começa com o giro e volta ao
## normal no fim da animação (GreatswordSpinRules.lean_weight).
@export_range(0.0, 0.6, 0.01) var lean := 0.24

@export_group("Energia sombria")
## Quanto o rastro de energia que segue o corte da espada dura atrás dela (s): na velocidade máxima ~0,3 s cobre uns
## 250° do giro.
@export_range(0.05, 1.0, 0.01) var trail_time := 0.3
## A energia passa da ponta da lâmina este tanto (m): chega perto do alcance do dano (`radius`).
@export_range(0.0, 2.0, 0.05) var trail_reach := 0.8
## Brilho do rastro (fumaça escura e bordas violeta).
@export_range(0.0, 3.0, 0.05) var trail_intensity := 1.0
## Fiapos de fumaça escura, faíscas violeta e lascas carmesim soltos pela lâmina por segundo, no giro máximo.
@export_range(0.0, 200.0, 1.0) var wisps_per_second := 46.0
@export_range(0.0, 200.0, 1.0) var motes_per_second := 70.0
@export_range(0.0, 200.0, 1.0) var sparks_per_second := 40.0
## Altura da luz violeta do giro (m acima dos pés): a altura da lâmina.
@export_range(0.2, 2.5, 0.01) var slash_height := 1.1
## Tempo para o rastro, os fiapos e a luz sumirem depois de parar (Tween, s).
@export_range(0.05, 3.0, 0.05) var fade_time := 0.45

@export_group("Câmera")
## A câmera recua durante o giro (m).
@export_range(0.0, 4.0, 0.05) var camera_back := 0.8


## Duração de cada fase (s): [postura, aceleração, giro, desaceleração, volta].
func durations() -> Array[float]:
	return GreatswordSpinRules.durations(stance_time, accel_time, spin_time, decel_time, recover_time)


## Tempo total da habilidade no herói (s).
func total_time() -> float:
	var s := 0.0
	for d in durations():
		s += d
	return s
