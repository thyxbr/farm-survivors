class_name SeismicSpikesConfig
extends Resource
## Configuração das Estacas Sísmicas (habilidade 3 da montante). Um só recurso para o dano e a recarga
## (SeismicSpikesAbilities, SeismicSpikesDamage, ItemDB.cooldown_of), para a animação do herói e para o visual
## (SeismicSpikesAoE): edite assets/vfx/seismic_spikes/seismic_spikes_config.tres no Inspector, sem mexer no código.
## Linha do tempo (a partir da tecla): ergue a espada de ponta para baixo (windup) -> crava (plunge, IMPACTO) ->
## rachaduras se espalham até o raio (crack_time, fase 1) -> intervalo (quake_delay) -> a terra começa a TREMER (fase
## 2, o dano corre do centro até a borda) -> treme enquanto o herói segura a espada cravada (quake_hold) -> arranca a
## espada (pull_time; o tremor para quando ela sai) -> volta à guarda (recover_time). Com a espada fora do chão o
## visual some em fade_time e o nó se libera.

@export_group("Combate")
## Dano do tremor: multiplica o dano corpo a corpo do herói (Game.melee_damage), como as outras da espada.
@export_range(0.1, 10.0, 0.05) var damage_mult := 2.4
## Raio da área (m) em volta do ponto onde a espada crava: as rachaduras e o tremor chegam até aqui.
@export_range(1.0, 15.0, 0.1) var radius := 4.5
## Atordoamento de quem é atingido pelo tremor (s; 0 = nenhum).
@export_range(0.0, 3.0, 0.05) var stun_time := 0.9
## Tempo de recarga (s). Conta a partir do uso, como as outras habilidades.
@export_range(0.5, 120.0, 0.5) var cooldown := 12.0

@export_group("Movimento do herói")
## Erguer a montante virando a ponta para baixo, as duas mãos no cabo acima da cintura (s). A esquiva cancela.
@export_range(0.1, 2.0, 0.01) var windup_time := 0.5
## Descer e cravar a espada no chão (s): o impacto é no fim.
@export_range(0.04, 0.6, 0.01) var plunge_time := 0.14
## Arrancar a espada do chão (s).
@export_range(0.1, 2.0, 0.01) var pull_time := 0.5
## Voltar à guarda (s).
@export_range(0.05, 1.5, 0.01) var recover_time := 0.4
## A ponta da espada crava esta distância à frente dos pés (m): o centro da área.
@export_range(0.2, 2.0, 0.01) var forward_offset := 0.8
## Quanto a ponta entra no chão (m).
@export_range(0.0, 0.8, 0.01) var plunge_depth := 0.25

@export_group("Fase 1: rachaduras")
## Tempo para as rachaduras irem do centro até a borda (s).
@export_range(0.1, 3.0, 0.01) var crack_time := 0.7
## Lado do chão rachado animado (m), deitado no chão (a sheet é vista de cima e preenche o quadro): ~2x o raio.
@export_range(1.0, 30.0, 0.1) var crack_size := 9.6
## Opacidade do chão rachado animado (0..1): menos = a grama de verdade aparece mais por baixo.
@export_range(0.0, 1.0, 0.01) var crack_opacity := 0.9
## Opacidade da poeira que sobe durante o tremor e assenta no fim (os quadros de poeira da sheet).
@export_range(0.0, 1.0, 0.01) var dust_opacity := 0.55
## Decal das fissuras (projetado no terreno, acompanha o relevo): opacidade e brilho das brasas dentro delas.
@export_range(0.0, 1.0, 0.01) var decal_opacity := 0.9
@export_range(0.0, 4.0, 0.05) var decal_glow := 0.8

@export_group("Fase 2: terremoto")
## Intervalo entre as rachaduras chegarem na borda e a terra começar a tremer (s).
@export_range(0.0, 3.0, 0.01) var quake_delay := 0.3
## Quanto tempo a terra treme com a espada cravada, antes de o herói começar a arrancá-la (s). O tremor continua
## durante o arrancar e para quando a espada sai do chão.
@export_range(0.2, 6.0, 0.05) var quake_hold := 1.6
## Quanto o tremor leva do centro até a borda (s): o dano acompanha (os de perto antes dos de longe).
@export_range(0.0, 1.5, 0.01) var quake_propagate := 0.35
## Tremor contínuo da câmera de quem está perto (0..1); `quake_pulse` é o tranco a mais em cada abalo.
@export_range(0.0, 1.0, 0.01) var quake_shake := 0.16
@export_range(0.0, 1.0, 0.01) var quake_pulse := 0.22
## Intervalo médio entre os abalos (s): tranco na câmera, pedrinhas pulando e ronco.
@export_range(0.1, 2.0, 0.01) var quake_beat := 0.35
## Quanto o chão rachado e as fissuras sacodem (m).
@export_range(0.0, 0.3, 0.005) var ground_jitter := 0.045
## Pedrinhas (malha 3D) pulando no chão durante o tremor, por segundo (0 = nenhuma).
@export_range(0, 300, 1) var pebble_rate := 70
## Nuvens de poeira subindo do chão durante o tremor, por segundo (0 = nenhuma).
@export_range(0, 60, 1) var dust_rate := 14

@export_group("Impacto e câmera")
## Tranco da câmera ao cravar e quando o tremor começa.
@export_range(0.0, 2.0, 0.01) var shake_strength := 0.55
## Até que distância do ponto do golpe a câmera de quem vê treme (m).
@export_range(1.0, 60.0, 0.5) var shake_range := 18.0
## Congelamento curto ao cravar (s; só no herói que usou; 0 = nenhum).
@export_range(0.0, 0.25, 0.005) var hitstop_time := 0.06
## Quanto a câmera recua durante a habilidade (m), para a área inteira caber na tela.
@export_range(0.0, 10.0, 0.05) var camera_back := 1.2

@export_group("Dissipação")
## Com a espada fora do chão, as rachaduras e a poeira somem suavemente neste tempo (s); depois o nó se libera.
@export_range(0.1, 5.0, 0.05) var fade_time := 0.7


## Do começo até a espada tocar o chão (s).
func impact_time() -> float:
	return windup_time + plunge_time


## Do começo até as rachaduras chegarem na borda (s).
func cracks_done_time() -> float:
	return impact_time() + crack_time


## Do começo até a terra começar a tremer (s): o impacto, a expansão das rachaduras e o intervalo.
func quake_time() -> float:
	return cracks_done_time() + quake_delay


## Do começo até o herói começar a arrancar a espada (s).
func pull_start() -> float:
	return quake_time() + quake_hold


## Do começo até a espada sair do chão (s): o tremor para e o visual começa a sumir aqui.
func pull_end() -> float:
	return pull_start() + pull_time


## Tempo do herói na habilidade (s).
func total_time() -> float:
	return pull_end() + recover_time


## Duração das fases da pose [erguer, cravar, segurar, arrancar, voltar] (SeismicSpikesRules.PHASES).
func pose_durations() -> Array[float]:
	return SeismicSpikesRules.durations(windup_time, plunge_time, crack_time + quake_delay + quake_hold, pull_time, recover_time)
