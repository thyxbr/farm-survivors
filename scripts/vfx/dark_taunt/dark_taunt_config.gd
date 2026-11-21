class_name DarkTauntConfig
extends Resource
## Configuração do Círculo da Provocação Sombria (habilidade 3 da espada com escudo). Um só recurso para a regra
## (DarkTauntAbilities, ItemDB.cooldown_of, o servidor em Network._taunt_enemy) e para o visual (DarkTauntSkill e as
## peças dele): edite assets/vfx/dark_taunt/dark_taunt_config.tres no Inspector, sem mexer no código.

@export_group("Combate")
## Raio do círculo mágico (m): quem estiver dentro quando ele termina de se formar é agarrado e provocado.
@export_range(1.0, 14.0, 0.1) var radius := 6.0
## Duração da imobilização (s): as mãos seguram o inimigo; ele não anda nem ataca. Chefes não ficam presos
## (só são provocados), como no atordoamento.
@export_range(0.0, 6.0, 0.05) var hold_time := 1.6
## Duração da provocação (s), contada depois que as mãos soltam: o inimigo só persegue e ataca o herói.
@export_range(0.5, 30.0, 0.5) var taunt_time := 6.0
## Tempo de recarga (s). Conta a partir do uso, como as outras habilidades.
@export_range(0.5, 120.0, 0.5) var cooldown := 18.0

@export_group("Círculo mágico")
## Tempo para o círculo se desenhar no chão (s), depois que o herói solta a energia.
@export_range(0.1, 3.0, 0.01) var circle_form_time := 0.7
## Velocidade de rotação dos anéis (rad/s; o de dentro gira ao contrário).
@export_range(0.0, 4.0, 0.05) var circle_spin := 0.45
## Quanto tempo o círculo fica no chão, já apagando, depois que as mãos soltam (s).
@export_range(0.0, 4.0, 0.05) var circle_linger := 0.6

@export_group("Mãos sombrias")
## Quantidade de mãos. Cada inimigo agarrado ganha a sua; as que sobram surgem em pontos vazios do círculo e
## arranham o ar. Com mais inimigos que mãos, cada um ainda ganha a sua (até MAX_HANDS).
@export_range(0, 24, 1) var hand_count := 8
## Velocidade de emergência das mãos (multiplica a subida: 2 = sobe na metade do tempo).
@export_range(0.25, 4.0, 0.05) var hand_rise_speed := 1.0
## Tamanho das mãos (escala; 1 = braço de ~1,5 m para um inimigo do tamanho do herói).
@export_range(0.3, 3.0, 0.05) var hand_size := 1.0

@export_group("Efeitos")
## Tempo de dissipação dos efeitos (s): mãos afundando em fumaça, runas virando partículas, anéis se contraindo.
@export_range(0.2, 4.0, 0.05) var dissipate_time := 1.2
## Intensidade da energia sombria (brilho do círculo, das mãos e quantidade de partículas e fumaça).
@export_range(0.0, 3.0, 0.05) var energy_intensity := 1.0

@export_group("Olhos da provocação")
## Altura dos olhos acima da cabeça do inimigo (m), somada ao topo dele.
@export_range(-1.0, 3.0, 0.01) var eye_height := 0.28
## Tamanho dos olhos (largura do par, m, para um inimigo do tamanho do herói; escala com o inimigo).
@export_range(0.1, 2.0, 0.01) var eye_size := 0.42
## Tempo para os olhos sumirem quando a provocação acaba (s).
@export_range(0.05, 3.0, 0.05) var eye_fade_time := 0.6

@export_group("Câmera")
## Quanto a câmera recua durante a invocação (m), para o círculo inteiro caber na tela.
@export_range(0.0, 10.0, 0.05) var camera_back := 2.5

## Teto de mãos por ativação (desempenho), mesmo com muitos inimigos.
const MAX_HANDS := 20
## O herói recolhe os braços e explode a energia (KnightMoves.TAUNT_BURST): o círculo começa aí.
const CAST_LEAD := 0.5


## Tempo da subida das mãos (s), pela velocidade.
func rise_time() -> float:
	return 0.55 / maxf(hand_rise_speed, 0.05)


## Do começo da habilidade até as mãos fecharem nos alvos (s): a captura e a provocação começam aí.
func grab_at() -> float:
	return CAST_LEAD + circle_form_time + rise_time() + DarkTauntRules.REACH_TIME


## Do começo até as mãos soltarem (s).
func release_at() -> float:
	return grab_at() + hold_time
