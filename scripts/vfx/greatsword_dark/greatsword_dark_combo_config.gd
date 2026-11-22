class_name GreatswordDarkComboConfig
extends Resource
## Configuração da Dança do Abismo (montante, tecla 3). Um só recurso para o dano e o ritmo (GreatswordDarkComboAbilities,
## GreatswordDarkComboRules) e o visual (GreatswordDarkComboFX): edite
## assets/vfx/greatsword_dark/greatsword_dark_combo_config.tres no Inspector, sem mexer no código.
## Os golpes são os quatro clipes de KnightMovesGreatDark, sempre na ordem: deslize, corte girando, corte rápido e giro
## alto. Os acertos são listas paralelas (um índice = um acerto).

@export_group("Combate")
## Recarga (s). ItemDB.cooldown_of lê daqui.
@export_range(1.0, 60.0, 0.5) var cooldown := 12.0
## Em que golpe (0..3) e em que fração do clipe dele cada acerto acontece (os picos de velocidade da ponta da lâmina,
## medidos por tools/retarget_great_dark_combo.gd).
@export var hit_segment := PackedInt32Array([0, 1, 1, 2, 3, 3])
@export var hit_at := PackedFloat32Array([0.7, 0.45, 0.86, 0.5, 0.25, 0.61])
## Dano de cada acerto: multiplica o dano corpo a corpo do herói (Game.melee_damage).
@export var hit_mult := PackedFloat32Array([0.6, 0.55, 0.3, 0.6, 0.5, 1.1])
## Alcance (m, no chão) e arco (graus; 360 = em volta) de cada acerto.
@export var hit_reach := PackedFloat32Array([3.2, 3.3, 3.0, 3.2, 3.3, 3.6])
@export var hit_arc := PackedFloat32Array([170.0, 360.0, 150.0, 160.0, 360.0, 200.0])
## Empurrão de cada acerto (m/s; 0 = o padrão do golpe).
@export var hit_knockback := PackedFloat32Array([3.0, 4.0, 2.0, 3.5, 4.0, 9.0])
## Atordoamento do último acerto (s): o golpe de cima que fecha o combo e abre as garras.
@export_range(0.0, 3.0, 0.05) var final_stun := 0.9
## O último acerto também ergue garras sombrias em volta do herói: quantas e a que distância (m).
@export_range(0, 16) var final_claws := 7
@export_range(0.5, 5.0, 0.05) var final_claw_radius := 2.3

@export_group("Ritmo")
## Velocidade dos clipes do Mixamo (1 = o ritmo original).
@export_range(0.5, 2.5, 0.05) var speed := 1.25
## Fração do clipe em que o golpe seguinte começa (a volta à guarda do anterior fica de fora), por golpe.
@export var chain := PackedFloat32Array([0.9, 0.9, 0.92, 1.0])
## Mistura de um golpe para o outro (s): o corpo e a lâmina saem da pose em que o anterior parou.
@export_range(0.0, 0.5, 0.01) var blend_time := 0.16
## Volta à guarda de carregar no fim do último golpe (s).
@export_range(0.05, 1.0, 0.01) var back_time := 0.35
## Multiplica o quanto o herói anda com os clipes (o deslize vai ~3,4 m à frente).
@export_range(0.0, 2.0, 0.05) var move_scale := 1.0

@export_group("Energia sombria")
## Quanto o rastro de energia que segue o corte dura atrás da lâmina (s) e quanto passa da ponta (m).
@export_range(0.05, 1.0, 0.01) var trail_time := 0.26
@export_range(0.0, 2.0, 0.05) var trail_reach := 0.55
## Brilho do rastro.
@export_range(0.0, 3.0, 0.05) var trail_intensity := 1.1
## Velocidade da ponta (m/s) em que o rastro começa a aparecer e em que fica cheio.
@export_range(0.0, 30.0, 0.5) var trail_min_speed := 6.0
@export_range(0.5, 40.0, 0.5) var trail_full_speed := 15.0

@export_group("Câmera")
## A câmera recua durante o combo (m).
@export_range(0.0, 4.0, 0.05) var camera_back := 1.0
## Tremor da câmera no último acerto.
@export_range(0.0, 1.0, 0.01) var final_shake := 0.35


## Quantos acertos o combo tem (o menor tamanho das listas).
func hit_count() -> int:
	return mini(mini(hit_segment.size(), hit_at.size()), mini(hit_mult.size(), mini(hit_reach.size(),
		mini(hit_arc.size(), hit_knockback.size()))))


## Duração de cada clipe na velocidade da configuração (s).
func lengths() -> Array[float]:
	return GreatswordDarkComboRules.segment_lengths(KnightMovesGreatDark.CLIP_TIME, speed)


## Instante em que cada golpe começa (s).
func starts() -> Array[float]:
	return GreatswordDarkComboRules.segment_starts(lengths(), Array(chain))


## Duração total da habilidade (s).
func total_time() -> float:
	return GreatswordDarkComboRules.total_time(lengths(), starts())
