class_name GreatswordSupremeConfig
extends Resource
## Configuração da Lâmina Suprema (ultimate da montante, tecla 4). Um só recurso para o dano (GreatswordSupremeAbilities),
## o ritmo da animação (KnightAnim.great_cast_pose) e o visual (GreatswordSupremeSlash): edite
## assets/vfx/greatsword_supreme/greatsword_supreme_config.tres no Inspector, sem mexer no código.

@export_group("Combate")
## Dano: multiplica o dano corpo a corpo do herói (Game.melee_damage), como as outras ultimates.
@export_range(0.1, 12.0, 0.05) var damage_mult := 5.0
## Distância à frente do herói onde a ponta da espada de energia bate no chão (m). Perto do comprimento da espada de
## energia formada, para ela não encolher ao tocar o chão.
@export_range(1.0, 12.0, 0.05) var impact_distance := 5.6
## Raio da área em volta do ponto onde a ponta bate (m).
@export_range(0.5, 10.0, 0.05) var impact_radius := 2.6
## Meia largura da cratera (m): quem está dentro dela, do herói até a ponta da cratera, leva o golpe. A cratera tem
## `crack_width` de largura (3 m: meia largura de 1,5 m).
@export_range(0.0, 4.0, 0.05) var cut_half_width := 1.5
## Atordoamento de quem é atingido (s; 0 = nenhum).
@export_range(0.0, 3.0, 0.05) var stun_time := 1.0
## Empurrão para longe do ponto do golpe (m/s; 0 = o empurrão padrão do golpe).
@export_range(0.0, 30.0, 0.5) var knockback := 11.0

@export_group("Ritmo")
## Erguer a espada acima da cabeça (s).
@export_range(0.1, 3.0, 0.01) var raise_time := 0.55
## Carga: espada erguida enquanto a energia sombria a cobre e cresce até o tamanho todo (s). A esquiva até o fim dela
## cancela.
@export_range(0.2, 6.0, 0.05) var charge_time := 1.8
## O corte: a lâmina gira por trás, passa por cima da cabeça e crava no chão à frente (s).
@export_range(0.1, 2.0, 0.01) var slash_time := 0.6
## Ajoelhado com a lâmina no chão depois do impacto (s).
@export_range(0.0, 3.0, 0.01) var kneel_time := 0.55
## Levantar e voltar à guarda (s).
@export_range(0.1, 3.0, 0.01) var rise_time := 0.85

@export_group("Energia na espada")
## Comprimento da espada de energia formada (m, das mãos à ponta): começa do tamanho da montante e cresce até aqui.
@export_range(0.5, 14.0, 0.05) var sword_length := 5.4
## Largura da lâmina de energia: multiplica a proporção da malha (1 = ~0,57 m com 5,4 m de comprimento).
@export_range(0.3, 3.0, 0.01) var sword_width := 1.0
## Brilho da energia (as bordas e as veias passam de 1: o glow pega nelas).
@export_range(0.0, 4.0, 0.05) var sword_intensity := 1.0
## Fração da carga em que a energia termina de cobrir a lâmina (da guarda até a ponta): depois disso ela só cresce.
@export_range(0.05, 0.9, 0.01) var cover_frac := 0.3

@export_group("Cratera")
## A cratera em linha reta, na direção do golpe: começa `crack_start` m à frente dos pés do herói...
@export_range(0.0, 6.0, 0.05) var crack_start := 1.0
## ...e passa `crack_beyond` m da ponta da espada (m).
@export_range(0.0, 10.0, 0.05) var crack_beyond := 3.6
## Largura da cratera no chão (m).
@export_range(0.5, 8.0, 0.05) var crack_width := 3.0
## Quanto a cratera fica aberta antes de começar a fechar (s).
@export_range(0.0, 10.0, 0.1) var crack_hold := 2.8
## Tempo para a cratera fechar (as bordas afundam), a luz e as partículas sumirem (s).
@export_range(0.1, 5.0, 0.05) var fade_time := 1.4
## Velocidade com que a cratera se abre pelo chão, do herói para a frente (m/s).
@export_range(5.0, 120.0, 1.0) var open_speed := 42.0
## Placas de pedra partida levantadas em cada borda (por metro de cratera).
@export_range(0.0, 4.0, 0.05) var rim_density := 1.6
## Multiplica a quantidade de pedras, terra, fumaça e faíscas.
@export_range(0.0, 3.0, 0.05) var debris_amount := 1.0
## Velocidade das pedras arremessadas para os lados (m/s).
@export_range(1.0, 30.0, 0.5) var debris_speed := 10.0

@export_group("Almas")
## Quantas almas saem voando de dentro da cratera quando ela se abre.
@export_range(0, 40) var soul_count := 14
## Velocidade com que fogem (m/s) e quanto tempo cada uma dura (s).
@export_range(0.5, 20.0, 0.1) var soul_speed := 6.0
@export_range(0.5, 6.0, 0.05) var soul_life := 2.6
## As almas saem ao longo deste tempo depois do impacto (s), não todas juntas.
@export_range(0.0, 2.0, 0.05) var soul_stagger := 0.55
## Tamanho de cada alma (m, da cabeça à ponta da cauda).
@export_range(0.2, 3.0, 0.05) var soul_size := 1.25

@export_group("Câmera")
## Tremor da câmera no impacto (diminui com a distância até `shake_range`).
@export_range(0.0, 2.0, 0.01) var shake_strength := 0.9
@export_range(1.0, 80.0, 0.5) var shake_range := 26.0
## Congelamento curto no impacto (só de quem bateu, s).
@export_range(0.0, 0.25, 0.005) var hitstop_time := 0.08
## Quanto a câmera recua durante a habilidade (m): a espada de energia chega a ~3x a altura do herói.
@export_range(0.0, 10.0, 0.05) var camera_back := 4.0
## Quanto a câmera inclina para cima durante a carga (rad).
@export_range(0.0, 0.8, 0.01) var camera_tilt := 0.26


## Até o fim da carga (o corte ainda não começou).
func charge_end() -> float:
	return raise_time + charge_time


## Instante do impacto, desde o começo da habilidade.
func impact_time() -> float:
	return charge_end() + slash_time


## Duração total no herói.
func total_time() -> float:
	return impact_time() + kneel_time + rise_time


## Comprimento da cratera no chão (m): de `crack_start` à frente do herói até `crack_beyond` além da ponta.
func crack_length() -> float:
	return maxf(impact_distance + crack_beyond - crack_start, 0.5)


## Onde fica o meio da cratera em relação ao ponto do impacto, na direção do golpe (m; negativo = para o herói).
func crack_center_offset() -> float:
	return (crack_start + impact_distance + crack_beyond) * 0.5 - impact_distance
