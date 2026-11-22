class_name GreatswordSupremeConfig
extends Resource
## Configuração da Lâmina Suprema (ultimate da montante, tecla 4). Um só recurso para o dano (GreatswordSupremeAbilities),
## o ritmo da animação (KnightAnim.great_cast_pose) e o visual (GreatswordSupremeSlash): edite
## assets/vfx/greatsword_supreme/greatsword_supreme_config.tres no Inspector, sem mexer no código.

@export_group("Combate")
## Dano: multiplica o dano corpo a corpo do herói (Game.melee_damage), como as outras ultimates.
@export_range(0.1, 12.0, 0.05) var damage_mult := 5.0
## Distância à frente do herói onde a ponta da espada de energia bate no chão (m). Perto do alcance da espada
## ajoelhada (comprimento + ~0,4 m), para ela não encolher ao tocar o chão.
@export_range(1.0, 12.0, 0.05) var impact_distance := 6.4
## Raio da área do impacto (m), em volta do ponto onde a ponta bate.
@export_range(0.5, 10.0, 0.05) var impact_radius := 4.0
## Meia-largura do corte (m): o caminho da lâmina do herói até o ponto do golpe também fere.
@export_range(0.0, 4.0, 0.05) var cut_half_width := 1.1
## Atordoamento de quem é atingido (s; 0 = nenhum).
@export_range(0.0, 3.0, 0.05) var stun_time := 1.0
## Empurrão para longe do ponto do golpe (m/s; 0 = o empurrão padrão do golpe).
@export_range(0.0, 30.0, 0.5) var knockback := 11.0

@export_group("Ritmo")
## Erguer a espada acima da cabeça (s).
@export_range(0.1, 3.0, 0.01) var raise_time := 0.55
## Carga: espada erguida enquanto a aura se forma até o tamanho todo (s). A esquiva até o fim dela cancela.
@export_range(0.2, 6.0, 0.05) var charge_time := 1.6
## O corte: a lâmina gira por trás, passa por cima da cabeça e crava no chão à frente (s).
@export_range(0.1, 2.0, 0.01) var slash_time := 0.6
## Ajoelhado com a lâmina no chão depois do impacto (s).
@export_range(0.0, 3.0, 0.01) var kneel_time := 0.55
## Levantar e voltar à guarda (s).
@export_range(0.1, 3.0, 0.01) var rise_time := 0.85

@export_group("Espada de energia")
## Comprimento da espada de energia (m, das mãos à ponta; o pomo passa 10% para trás): ~3x a altura do herói (~1,8 m).
@export_range(0.5, 14.0, 0.05) var sword_length := 6.0
## Largura da lâmina: multiplica a proporção da malha (1 = ~0,62 m com 6 m de comprimento).
@export_range(0.3, 3.0, 0.01) var sword_width := 1.0
## Brilho da espada (as partes mais quentes já passam de 1 no shader: o glow pega nelas).
@export_range(0.0, 4.0, 0.05) var sword_intensity := 1.0

@export_group("Impacto")
## Rachadura em linha reta no chão, na direção do golpe: começa `crack_start` m à frente dos pés do herói...
@export_range(0.0, 6.0, 0.05) var crack_start := 1.2
## ...e passa `crack_beyond` m da ponta da espada (m).
@export_range(0.0, 10.0, 0.05) var crack_beyond := 4.0
## Largura da rachadura no chão (Decal, m).
@export_range(0.3, 6.0, 0.05) var crack_width := 2.6
## Quanto a rachadura fica no chão antes de começar a sumir (s).
@export_range(0.0, 10.0, 0.1) var crack_hold := 2.5
## Tempo para a rachadura, a luz e as partículas sumirem (Tween, s).
@export_range(0.1, 5.0, 0.05) var fade_time := 1.6
## Multiplica a quantidade de pedras, terra, fumaça e fagulhas.
@export_range(0.0, 3.0, 0.05) var debris_amount := 1.0
## Velocidade das pedras arremessadas para os lados (m/s).
@export_range(1.0, 30.0, 0.5) var debris_speed := 10.0

@export_group("Câmera")
## Tremor da câmera no impacto (diminui com a distância até `shake_range`).
@export_range(0.0, 2.0, 0.01) var shake_strength := 0.9
@export_range(1.0, 80.0, 0.5) var shake_range := 26.0
## Congelamento curto no impacto (só de quem bateu, s).
@export_range(0.0, 0.25, 0.005) var hitstop_time := 0.08
## Quanto a câmera recua durante a habilidade (m): a espada de energia tem ~3x a altura do herói.
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


## Comprimento da rachadura no chão (m): de `crack_start` à frente do herói até `crack_beyond` além da ponta.
func crack_length() -> float:
	return maxf(impact_distance + crack_beyond - crack_start, 0.5)


## Onde fica o meio da rachadura em relação ao ponto do impacto, na direção do golpe (m; negativo = para o herói).
func crack_center_offset() -> float:
	return (crack_start + impact_distance + crack_beyond) * 0.5 - impact_distance
