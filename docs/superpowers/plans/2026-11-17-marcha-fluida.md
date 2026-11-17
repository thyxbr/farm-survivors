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
- `KnightAnim` não compila em `--script`/`-s` (depende do autoload `ItemDB` via `KnightLook`): testes e ferramentas que o usam rodam como cena. Teste da marcha: `godot --headless --path . res://tests/gait_test.tscn` (PASS/FAIL por linha, código de saída 0/1).
- `leg_yaw` da locomoção é zerado em `hips_follow()`.

## Review Focus

- Réplica de multiplayer (velocidade aos saltos): a cabeça não pode tremer; tudo depende só de `phase`/`move`/`run`, nada de derivadas.
- Golpe andando: `play_track`/`hips_follow` escrevem `twist`/`hip_twist` por cima; `leg_yaw` da locomoção não pode sobrar e girar as pernas no golpe (teste em Task 2).
- Arco mirando e cajado (`weapon_carry`, `_bow_ik`): escrevem braços depois da locomoção; cruzar o braço não pode vazar (conferir folha com `roupa` e no jogo).
- Corpo feminino (`knight_f.glb`) e roupas com pele (`PivotSkin`): `Head.rotation.z` e `Leg.rotation.y` novos precisam ser seguidos pelos ossos (PivotSkin copia a transformação do pivô; conferir visualmente).
- Transição parado -> andar: `blend()` mistura as chaves novas (precisam estar em `POSE_KEYS`).

---

### Task 1: Ferramenta de passada consertada e testes da marcha

Contexto: `tools/gait_shot.gd` (script `extends SceneTree`, rodado com `--script`) não compila mais: `KnightAnim` depende de `KnightLook`, que usa o autoload `ItemDB`, e autoloads não existem em `--script`/`-s`. Pelo mesmo motivo os testes da marcha não podem ir em `tests/unit/`. As outras ferramentas já viraram cenas (`tools/pose_shot.tscn` + `tools/pose_shot.gd`, `extends Node3D`): seguir esse padrão.

**Files:**
- Modify: `tools/gait_shot.gd` (vira `extends Node3D`, lógica de `_initialize` em `_ready`, mesma saída e mesmos argumentos); Create: `tools/gait_shot.tscn`
- Create: `tests/gait_test.gd` (`extends Node`), `tests/gait_test.tscn`
- Modify: `.github/workflows/*.yml`: passo novo ao lado do `npc_asset_test`: `timeout 120 godot --headless --path . res://tests/gait_test.tscn`

**Interfaces:**
- Produces: `godot --path . --resolution 2000x520 res://tools/gait_shot.tscn -- <saida.png> [vel] [corre] [roupa]` (imprime as linhas `cadência ...`, `duty ... desliza ...`, `SHOT <saida>` sem nenhum `SCRIPT ERROR`).
- Produces: `godot --headless --path . res://tests/gait_test.tscn` imprime `PASS <nome>` / `FAIL <nome>: <valores medidos>` por verificação e sai com código 0 (tudo passou) ou 1.

Ajudante em `tests/gait_test.gd`, `_cycle(move, run) -> Array`: instancia `res://assets/models/knight.glb`, põe na árvore, `KnightAnim.rig`, e para 48 fases chama `locomotion_pose` + `apply(r, p, 1.0)` duas vezes, guardando por fase: yaw e roll no mundo de `Head`, `Body` e `Pelvis` (de `global_basis`), x no mundo de `AnkleL`, se a perna esquerda está em apoio (`u < KnightAnim.gait_duty(move, run)`, `u = fposmod(phase, TAU) / TAU`), `Body.position.x`, e x no mundo da mão esquerda (`ElbowL.global_transform * r.hand_l`). Chaves de pose que ainda não existem são lidas com `p.get(chave, 0.0)`.

- [ ] Converter `gait_shot` para cena e rodar `godot --path . --resolution 2000x520 res://tools/gait_shot.tscn -- <scratch>/x.png 5.2 0`: sem `SCRIPT ERROR`, com a linha `duty`.
- [ ] Escrever as verificações (cada uma para `(move, run)` = `(1.0, 0.0)` e `(1.0, 1.0)`):
  - `head_stays_forward`: amplitude (máx - mín) do yaw da cabeça <= 0.3 x amplitude do yaw do `Body`; idem para o roll.
  - `pelvis_counters_shoulders`: na fase 0, yaw da `Pelvis` < -0.03 e yaw do `Body` > 0.03; na fase PI, sinais trocados.
  - `stance_foot_no_side_slip`: x do `AnkleL` durante o apoio varia <= 0.012 m.
  - `hand_crosses_in_front`: |x| da mão esquerda na fase em que ela está mais à frente (maior z) é pelo menos 0.01 m menor que na fase em que está mais atrás.
  - `weight_over_stance_leg`: no meio do apoio esquerdo, `Body.position.x` > `r.body_x0`; no do direito, menor.
  - `still_pose_untouched`: `locomotion_pose(r, ph, 0.0, 0.0)` tem `hip_twist`, `leg_yaw`, `head_y`, `head_z`, `body_shift` == 0 para toda fase.
- [ ] Rodar `godot --headless --path . res://tests/gait_test.tscn`: roda até o fim, código de saída 1. Esperado nesta tarefa: FAIL em `head_stays_forward`, `pelvis_counters_shoulders`, `hand_crosses_in_front`, `weight_over_stance_leg`; PASS em `stance_foot_no_side_slip` e `still_pose_untouched`. Qualquer outro resultado: relatar.
- [ ] Commit (testes vermelhos de propósito; o passo do CI entra junto).

### Task 2: Chaves de pose novas, cabeça e quadril

**Files:** Modify `scripts/player/knight_anim.gd` (`POSE_KEYS`, `rest_pose`, `locomotion_pose`, `apply`)

- [ ] `rest_pose()` e `POSE_KEYS` ganham `"head_z": 0.0` e `"leg_yaw": 0.0`. Em `apply`: `r.Head.rotation.z` vai até `p.get("head_z", 0.0)` e `r.LegL/LegR.rotation.y` até `p.get("leg_yaw", 0.0)`, com o mesmo `f.call` das outras chaves.
- [ ] Constantes: `PELVIS_TWIST_WALK := 0.07`, `PELVIS_TWIST_RUN := 0.12`, `HEAD_STEADY := 0.85`, `TORSO_LAG := 0.2` (rad de fase).
- [ ] Em `locomotion_pose`: `p.hip_twist = -lerpf(PELVIS_TWIST_WALK, PELVIS_TWIST_RUN, run) * move * cos(phase)`; `p.leg_yaw = -p.hip_twist` (as pernas continuam balançando para a frente, o pé não escorrega de lado); `p.twist` passa a usar `cos(phase - TORSO_LAG)`; `p.head_y = -HEAD_STEADY * p.twist`; `p.head_z = -HEAD_STEADY * p.body_z`.
- [ ] Conferir quem chama `hips_follow`/`reset_twist` em `player.gd`, `knight_npc.gd`, `village_guard.gd`: na locomoção pura `hip_twist` não pode ser sobrescrito; nos golpes (`play_track`) `leg_yaw` tem de ir a 0. Zerar `leg_yaw` em `hips_follow()`. Acrescentar a `tests/gait_test.gd` a verificação `attack_resets_leg_yaw`: depois de `KnightAnim.sword_pose(p, 1, 0.5, 1.0)` + `hips_follow(p)`, `p.leg_yaw == 0`.
- [ ] Rodar o teste da marcha: `head_stays_forward`, `pelvis_counters_shoulders`, `stance_foot_no_side_slip`, `still_pose_untouched` passam (peso e mão ainda falham até o Task 3). Commit.

### Task 3: Troca de peso e braços

**Files:** Modify `scripts/player/knight_anim.gd` (`locomotion_pose`)

- [ ] Constantes: `WEIGHT_SHIFT_WALK := 0.012`, `WEIGHT_SHIFT_RUN := 0.006` (m), `FOREARM_LAG := 0.35` (rad de fase), `ARM_CROSS_WALK := 0.08`, `ARM_CROSS_RUN := 0.14` (rad).
- [ ] `p.body_shift = lerpf(WEIGHT_SHIFT_WALK, WEIGHT_SHIFT_RUN, run) * move * sin(phase)` (sinal conferido por `test_weight_over_stance_leg`).
- [ ] Cotovelos usam `-cos(phase - ARM_LAG - FOREARM_LAG)` no lugar de `sl`. Braço que vai à frente fecha para dentro: soma em `arm_l.z`/`arm_r.z` de `ARM_CROSS * move * max(±sl, 0)` no sentido de fechar (L: menos; R: mais).
- [ ] Rodar o teste da marcha: tudo PASS, código de saída 0. Commit.

### Task 4: Conferência e versão

- [ ] Folhas `depois_*.png` com `res://tools/gait_shot.tscn` para (2.5, 0), (5.2, 0), (7.5, 1), contra as `antes_*.png` tiradas pelo controlador logo após o Task 1; comparar as linhas `desliza`/`pé mais baixo` (não podem piorar) e olhar as imagens lado a lado (também com `roupa`).
- [ ] `project.godot`: `config/version="0.38.3"`.
- [ ] Skill `smoke-check` (import, unitários, smoke, vila, horda). Lembrar das falhas intermitentes conhecidas (projéteis; testes de auth com sessões paralelas): rodar de novo antes de culpar a mudança.
- [ ] Commit. Mostrar antes/depois ao Henrique e pedir que teste no jogo.
