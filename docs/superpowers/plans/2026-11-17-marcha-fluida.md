# Marcha fluida Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** O corpo inteiro do cavaleiro participa da passada (cabeça estável, quadril girando, troca de peso, braços com arrasto), sem mexer nos modelos.

**Architecture:** Novas chaves de pose (`head_z`, `leg_yaw`) em `rest_pose()`/`POSE_KEYS`/`apply()`; `locomotion_pose()` passa a preencher `hip_twist`, `leg_yaw`, `head_y`, `head_z`, `body_shift` e a dar atraso a tronco e antebraço. Tudo multiplicado por `move`, então a pose parada não muda.

**Tech Stack:** Godot 4.7.2, GDScript. Godot: `C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe` (abaixo, `godot`).

**Spec:** `docs/superpowers/specs/2026-11-17-marcha-fluida-design.md`

## Global Constraints

- Só `scripts/player/knight_anim.gd` muda no jogo (mais `project.godot` para a versão). `player.gd` só se `hips_follow` ou outro código zerar `hip_twist` na locomoção.
- Convenções de sinal do topo de `knight_anim.gd`. Modelo olha para +Z; o lado esquerdo é +X. Fase 0 = pé esquerdo toca o chão à frente.
- Com `move = 0`, `locomotion_pose` devolve `hip_twist`, `leg_yaw`, `head_y`, `head_z`, `body_shift` iguais a 0.
- `config/version` 0.38.2 -> 0.38.3.
- Unit runner: scripts carregados por `-s` não podem citar autoloads. Se `KnightAnim` não compilar no runner, o Task 1 vira medições em `tools/gait_shot.gd` (mesmas contas, impressas e conferidas à mão).

## Review Focus

- Réplica de multiplayer (velocidade aos saltos): a cabeça não pode tremer; tudo depende só de `phase`/`move`/`run`, nada de derivadas.
- Golpe andando: `play_track`/`hips_follow` escrevem `twist`/`hip_twist` por cima; `leg_yaw` da locomoção não pode sobrar e girar as pernas no golpe (teste em Task 2).
- Arco mirando e cajado (`weapon_carry`, `_bow_ik`): escrevem braços depois da locomoção; cruzar o braço não pode vazar (conferir folha com `roupa` e no jogo).
- Corpo feminino (`knight_f.glb`) e roupas com pele (`PivotSkin`): `Head.rotation.z` e `Leg.rotation.y` novos precisam ser seguidos pelos ossos (PivotSkin copia a transformação do pivô; conferir visualmente).
- Transição parado -> andar: `blend()` mistura as chaves novas (precisam estar em `POSE_KEYS`).

---

### Task 0: Linha de base

- [ ] Rodar `godot --path . --import` e depois, para (2.5, 0), (5.2, 0), (7.5, 1): `godot --path . --resolution 2000x520 --script res://tools/gait_shot.gd -- <scratch>/antes_<vel>.png <vel> <corre>`. Guardar as linhas `duty ... desliza ...` impressas.

### Task 1: Testes da marcha

**Files:** Create `tests/unit/test_knight_gait.gd`

Ajudante `_cycle(move, run) -> Array` : instancia `knight.glb`, `KnightAnim.rig`, e para 48 fases chama `locomotion_pose` + `apply(r, p, 1.0)` duas vezes, guardando por fase: yaw no mundo de `Head`, `Body` e `Pelvis` (de `global_basis`), x no mundo de `AnkleL`, se a perna esquerda está em apoio (`u < gait_duty`), e x no mundo da mão esquerda (`ElbowL.global_transform * r.hand_l`).

- [ ] Escrever os testes (para `(1.0, 0.0)` e `(1.0, 1.0)`):
  - `test_head_stays_forward`: amplitude do yaw da cabeça <= 0.3 x amplitude do yaw do `Body`; idem para o roll.
  - `test_pelvis_counters_shoulders`: na fase 0, yaw da `Pelvis` < -0.03 e yaw do `Body` > 0.03; na fase PI, sinais trocados.
  - `test_stance_foot_no_side_slip`: x do `AnkleL` durante o apoio varia <= 0.012 m.
  - `test_hand_crosses_in_front`: |x| da mão esquerda no extremo à frente < |x| no extremo atrás.
  - `test_weight_over_stance_leg`: no meio do apoio esquerdo, `Body.position.x` > `r.body_x0`; no do direito, menor.
  - `test_still_pose_untouched`: `locomotion_pose(r, ph, 0.0, 0.0)` tem `hip_twist`, `leg_yaw`, `head_y`, `head_z`, `body_shift` == 0 para toda fase.
- [ ] `godot --headless --path . -s tests/unit/run.gd` : os testes novos aparecem e falham (exceto, talvez, o do pé). Se o arquivo não aparecer na saída, aplicar a regra do runner em Global Constraints.
- [ ] Commit.

### Task 2: Chaves de pose novas, cabeça e quadril

**Files:** Modify `scripts/player/knight_anim.gd` (`POSE_KEYS`, `rest_pose`, `locomotion_pose`, `apply`)

- [ ] `rest_pose()` e `POSE_KEYS` ganham `"head_z": 0.0` e `"leg_yaw": 0.0`. Em `apply`: `r.Head.rotation.z` vai até `p.get("head_z", 0.0)` e `r.LegL/LegR.rotation.y` até `p.get("leg_yaw", 0.0)`, com o mesmo `f.call` das outras chaves.
- [ ] Constantes: `PELVIS_TWIST_WALK := 0.07`, `PELVIS_TWIST_RUN := 0.12`, `HEAD_STEADY := 0.85`, `TORSO_LAG := 0.2` (rad de fase).
- [ ] Em `locomotion_pose`: `p.hip_twist = -lerpf(PELVIS_TWIST_WALK, PELVIS_TWIST_RUN, run) * move * cos(phase)`; `p.leg_yaw = -p.hip_twist` (as pernas continuam balançando para a frente, o pé não escorrega de lado); `p.twist` passa a usar `cos(phase - TORSO_LAG)`; `p.head_y = -HEAD_STEADY * p.twist`; `p.head_z = -HEAD_STEADY * p.body_z`.
- [ ] Conferir quem chama `hips_follow`/`reset_twist` em `player.gd`, `knight_npc.gd`, `village_guard.gd`: na locomoção pura `hip_twist` não pode ser sobrescrito; nos golpes (`play_track`) `leg_yaw` tem de ir a 0. Acrescentar ao teste: depois de `KnightAnim.sword_pose(p, 1, 0.5, 1.0)` + `hips_follow(p)`, `p.leg_yaw == 0`.
- [ ] Rodar os unitários: cabeça, quadril, pé e parado passam. Commit.

### Task 3: Troca de peso e braços

**Files:** Modify `scripts/player/knight_anim.gd` (`locomotion_pose`)

- [ ] Constantes: `WEIGHT_SHIFT_WALK := 0.012`, `WEIGHT_SHIFT_RUN := 0.006` (m), `FOREARM_LAG := 0.35` (rad de fase), `ARM_CROSS_WALK := 0.08`, `ARM_CROSS_RUN := 0.14` (rad).
- [ ] `p.body_shift = lerpf(WEIGHT_SHIFT_WALK, WEIGHT_SHIFT_RUN, run) * move * sin(phase)` (sinal conferido por `test_weight_over_stance_leg`).
- [ ] Cotovelos usam `-cos(phase - ARM_LAG - FOREARM_LAG)` no lugar de `sl`. Braço que vai à frente fecha para dentro: soma em `arm_l.z`/`arm_r.z` de `ARM_CROSS * move * max(±sl, 0)` no sentido de fechar (L: menos; R: mais).
- [ ] Rodar os unitários: todos passam. Commit.

### Task 4: Conferência e versão

- [ ] Repetir as três folhas do Task 0 como `depois_*.png`; comparar as linhas `desliza`/`pé mais baixo` (não podem piorar) e olhar as imagens lado a lado (também com `roupa`).
- [ ] `project.godot`: `config/version="0.38.3"`.
- [ ] Skill `smoke-check` (import, unitários, smoke, vila, horda). Lembrar das falhas intermitentes conhecidas (projéteis; testes de auth com sessões paralelas): rodar de novo antes de culpar a mudança.
- [ ] Commit. Mostrar antes/depois ao Henrique e pedir que teste no jogo.
