class_name FlameChannelConfig
extends Resource
## Configuração da Canalização de Fogo (mago com cajado, tecla 1). Um só recurso para o dano e a mana
## (FlameChannelAbilities), o ritmo (FlameChannelRules) e o visual (FlameChanneling): edite
## assets/vfx/flame_channel/flame_channel_config.tres no Inspector, sem mexer no código.

@export_group("Combate")
## Dano de cada tique em cada inimigo na labareda: base + poder mágico (INT + bônus de magia do equipamento) x este.
@export_range(0.0, 50.0, 0.5) var tick_damage := 4.0
@export_range(0.0, 5.0, 0.05) var tick_damage_int := 0.6
## Intervalo entre dois tiques no mesmo inimigo (s): 0,2 s = 5 tiques por segundo.
@export_range(0.05, 1.0, 0.01) var hit_interval := 0.2
## Alcance da labareda a partir da palma (m).
@export_range(1.0, 10.0, 0.05) var length := 6.5
## Raio do cone de dano na palma e na ponta (m, no chão): a chama abre à frente.
@export_range(0.05, 3.0, 0.05) var radius_start := 0.45
@export_range(0.2, 4.0, 0.05) var radius_end := 1.5
## Altura do cone de dano: até onde abaixo e acima dos pés do mago o inimigo ainda é atingido (m).
@export_range(0.2, 6.0, 0.05) var height_below := 2.5
@export_range(0.2, 6.0, 0.05) var height_above := 3.0
## Empurrão de cada tique para longe do mago (m/s): leve, para a horda não sair da labareda (o padrão de um golpe é 4).
@export_range(0.0, 6.0, 0.1) var push := 1.0
## Mana gasta por segundo enquanto canaliza (a habilidade gasta o `cost` do ItemDB ao começar). Sem mana, a chama apaga.
@export_range(0.0, 100.0, 0.5) var mana_per_second := 14.0

@export_group("Ritmo")
## O braço se estende e o círculo se forma antes do fogo sair (s): sem dano nesse tempo.
@export_range(0.05, 1.5, 0.01) var windup_time := 0.28
## Um toque na tecla ainda canaliza este tanto (s, contando do começo).
@export_range(0.1, 3.0, 0.05) var min_time := 0.7
## Canalização máxima (s): depois disso a chama apaga sozinha.
@export_range(1.0, 30.0, 0.5) var max_time := 8.0
## Fade-out do círculo e da labareda ao soltar a tecla (Tween, s). As partículas já soltas terminam o voo.
@export_range(0.05, 2.0, 0.01) var fade_time := 0.45
## Velocidade de andar canalizando: multiplica a de andar normal (0 = preso no lugar).
@export_range(0.0, 1.0, 0.05) var move_speed := 0.4
## Quão rápido o mago vira para onde a câmera olha (1/s): a labareda segue a mira.
@export_range(1.0, 40.0, 0.5) var turn_rate := 9.0

@export_group("Círculo mágico")
## Diâmetro do círculo (m) e a distância dele à frente da palma.
@export_range(0.2, 3.0, 0.05) var circle_size := 0.95
@export_range(0.0, 1.0, 0.01) var circle_offset := 0.16
## Giro rápido do desenho em volta do eixo do jato (rad/s), além do giro da própria sheet.
@export_range(-30.0, 30.0, 0.5) var circle_spin := 7.5
## Quadros da formação (tocados uma vez em `form_time`) e do laço enquanto canaliza (sheet A).
@export var form_frames := Vector2i(1, 18)
@export_range(0.05, 2.0, 0.01) var form_time := 0.32
@export var loop_frames := Vector2i(27, 50)
## Quadros por segundo do laço.
@export_range(1.0, 60.0, 1.0) var loop_fps := 26.0
## Quadros do anel se desfazendo, tocados no fade-out.
@export var end_frames := Vector2i(56, 63)
@export_range(0.0, 5.0, 0.05) var circle_intensity := 1.0

@export_group("Labareda")
## Vida de cada pedaço de chama (s): a velocidade sai do alcance (`length`) dividido por ela.
@export_range(0.15, 2.0, 0.01) var jet_lifetime := 0.55
## Escala dos pedaços de chama no fim do voo (m): a largura do jato na ponta.
@export_range(0.2, 5.0, 0.05) var jet_scale := 2.0
## Pedaços de chama vivos ao mesmo tempo (o volume do jato) e brasas.
@export_range(8, 400) var jet_amount := 56
@export_range(0, 400) var ember_amount := 110
@export_range(0, 120) var smoke_amount := 26
@export_range(0.0, 5.0, 0.05) var jet_intensity := 1.0
## Luz laranja no meio do jato.
@export_range(0.0, 20.0, 0.1) var light_energy := 4.0
## Distorção de calor na ponta (0 = sem).
@export_range(0.0, 3.0, 0.05) var heat_strength := 1.0

@export_group("Câmera")
## A câmera recua canalizando (m) e treme de leve (amplitude contínua e a mais nos tiques que acertam).
@export_range(0.0, 4.0, 0.05) var camera_back := 0.7
@export_range(0.0, 0.5, 0.005) var shake := 0.035
@export_range(0.0, 0.5, 0.005) var hit_shake := 0.06


## Dano de um tique para o poder mágico `spell_power` (sem os multiplicadores do herói).
func damage_for(spell_power: float) -> float:
	return tick_damage + spell_power * tick_damage_int
