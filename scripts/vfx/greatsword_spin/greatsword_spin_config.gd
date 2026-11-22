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

@export_group("Ritmo")
## Postura parada antes do giro (s). 0 = o giro começa assim que a habilidade é acionada (os braços vão à frente já
## girando). Com mais de 0 a esquiva cancela nessa postura.
@export_range(0.0, 2.0, 0.01) var stance_time := 0.0
## Aceleração: de parado até a velocidade máxima de giro (s).
@export_range(0.05, 3.0, 0.01) var accel_time := 0.35
## Giro na velocidade máxima (s).
@export_range(0.1, 6.0, 0.05) var spin_time := 1.4
## Desaceleração suave até parar (s).
@export_range(0.05, 4.0, 0.01) var decel_time := 0.9
## Volta à guarda normal depois de parar (s).
@export_range(0.05, 2.0, 0.01) var recover_time := 0.35
## Voltas completas do giro inteiro: a velocidade máxima sai daqui, e o herói termina virado para onde começou.
@export_range(1, 20) var turns := 5
## Inclinação do corpo para trás enquanto gira, contrapeso da espada esticada (rad): começa com o giro e volta ao
## normal no fim da animação (GreatswordSpinRules.lean_weight).
@export_range(0.0, 0.6, 0.01) var lean := 0.24

@export_group("Cortes (sprite sheet 8x8)")
## Brilho do anel de lâmina principal, que gira com a espada.
@export_range(0.0, 4.0, 0.05) var ring_intensity := 1.4
## Tamanho do anel: multiplica o diâmetro do alcance (`radius` x 2).
@export_range(0.3, 2.0, 0.01) var ring_scale := 1.0
## Altura do anel e dos cortes (m acima dos pés): a altura da lâmina.
@export_range(0.2, 2.5, 0.01) var slash_height := 1.0
## Ajuste do ângulo do desenho do anel em relação à lâmina (graus).
@export_range(-180.0, 180.0, 1.0) var ring_yaw_offset := 0.0
## Espelha o desenho (se o redemoinho da sheet girar ao contrário do herói).
@export var ring_flip := false
## Quadros da sheet (0..63): o começo (a espada e o primeiro crescente), o laço do giro e o apagar.
@export var frames_start := Vector2(0.0, 12.0)
@export var frames_loop := Vector2(12.0, 40.0)
@export var frames_end := Vector2(40.0, 63.0)
## Quadros por segundo do laço no giro máximo.
@export_range(1.0, 60.0, 0.5) var loop_fps := 24.0
## Cortes soltos por segundo no giro máximo (GPUParticles3D, cada um uma passada da sheet).
@export_range(0.0, 60.0, 0.5) var slashes_per_second := 14.0
## Brilho dos cortes soltos.
@export_range(0.0, 4.0, 0.05) var slash_intensity := 1.1
## Inclinação máxima dos cortes soltos em relação ao chão (graus): cortes em vários ângulos.
@export_range(0.0, 80.0, 1.0) var slash_tilt := 38.0
## Tempo para os cortes e a luz sumirem depois de parar (Tween, s).
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
