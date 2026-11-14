# Habilidades por arma — Fase 2 (cajado e arco) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Completar os kits do cajado (ultimate Chuva de Meteoros, canalizada) e do arco (Tiro Triplo, Flecha Glacial e ultimate Flecha do Vendaval, carregada), para que nenhuma habilidade mostre mais "Em breve!" e o branch possa ir para o main sem tirar nada dos jogadores de arco.

**Architecture:** Mesma arquitetura da Fase 1. Cada classe de arma tem um módulo estático com a mesma API de `SwordAbilities` (`use / tick / pose / play_remote / can_dodge_cancel`, mais `release` para habilidades de segurar). `player.gd` deixa de citar `SwordAbilities` diretamente e despacha pelo módulo da classe da habilidade. A lista "habilidade pronta" passa a ser um campo `ready` em `ItemDB.ABILITIES` (fonte única). Efeitos com `FXEpic`/`FX`, dano pelo mesmo caminho do jogador (`take_damage` + `Game.on_damage_dealt`, ou `Game.add_fury_from_damage` onde as magias já usam), réplicas só visuais.

**Tech Stack:** Godot 4.7.2, GDScript, tudo por código.

**Spec:** `docs/superpowers/specs/2026-11-13-habilidades-armas-design.md` (Fase 1 já implementada no mesmo branch: `docs/superpowers/plans/2026-11-13-habilidades-fase1-espada.md`)

## Global Constraints

- Worktree `C:/Games/godot-3d-habilidades`, branch `habilidades`. Godot `C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe`. Smoke: `--headless --path . res://scenes/world.tscn -- --smoketest`.
- Ultimate na tecla 4, liberada no nível 8, exige fúria cheia; `cast()` é o único dono de recarga e fúria (zera fúria só quando o módulo devolve `true` em `use`).
- Acertos de ultimate **não** enchem fúria (`with_fury = false` / não chamar `add_fury_from_damage`).
- Magias do cajado gastam mana como hoje (a ultimate não gasta mana); arco só recarga.
- Dano do arco escala com `Game.melee_damage()` (já usa a fórmula do arco com a classe `bow`); cajado com `Game.spell_power()` como as magias atuais.
- Habilidades comuns com efeito contido; só a ultimate enche a tela. Nada de efeito no servidor dedicado. Réplicas: pose e efeito, sem dano, sem hit_stop.
- Anti-objetivo de desempenho: 4 ultimates ao mesmo tempo sem queda perceptível (medir).
- Funciona igual no Desafio da Horda e online (servidor dedicado: dano/lentidão/atordoamento pelo `Network.client_hit_enemy` com os tetos que já existem).
- Textos em português. Smoke test restaura nível, fúria, mana, equipamento e posição após cada bloco; esperas por condição (`wait_until`), não por tempo fixo.

## Review Focus

1. **Soltar a tecla 4 no meio da canalização/tensão, ou segurar além do tempo:** a Chuva para na hora; a Flecha do Vendaval dispara ao soltar (com carga mínima) e dispara sozinha na carga máxima. Teste nas Tasks 4 e 5.
2. **Morte, menu ou troca de arma durante a canalização/tensão (e esquiva, que só encerra a Chuva):** `end_ability()` encerra limpo, sem meteoro órfão caindo depois e sem flecha disparando. Teste nas Tasks 4 e 5.
3. **Mirar no céu ou longe demais:** a área da Chuva fica limitada a um alcance máximo no chão; a flecha do Vendaval segue a mira da câmera como as flechas normais. Teste nas Tasks 4 e 5.
4. **Flecha Glacial em chefe:** aplica lentidão, mas não prende (chefes já são imunes a atordoamento). Teste na Task 3.
5. **Tiro Triplo com arma "multishot":** não multiplica de novo (3 flechas, não 9). Teste na Task 2.

---

### Task 1: Integrar o main e despacho por módulo com fonte única de "pronta"

**Files:**
- Merge: `origin/main` no branch (há o PR #40 novo); resolver conflitos mantendo os dois lados.
- Modify: `scripts/autoload/item_db.gd` (campo `ready` em cada entrada de `ABILITIES`: `true` para as 6 da Fase 1, `false` para `meteor_rain`, `bow_*`)
- Modify: `scripts/autoload/game.gd` (`ability_implemented(id)` passa a ler `ABILITIES[id].ready`)
- Modify: `scripts/player/player.gd` (remover a lista fixa de ~linha 704; trocar todas as chamadas `SwordAbilities.*` por `_ab_module(id_ou_kind).*`; ler soltura da tecla)
- Create: `scripts/player/abilities/staff_abilities.gd` (`StaffAbilities`) e `scripts/player/abilities/bow_abilities.gd` (`BowAbilities`), com a mesma API e `use` devolvendo `false`
- Test: `tests/smoke_test.gd`

**Interfaces:**
- Produces:
  - `ItemDB.ABILITIES[id].ready: bool`.
  - `player._ab_module(id: String) -> Object` — devolve `SwordAbilities`, `StaffAbilities` ou `BowAbilities` pela `class` de `ABILITIES[id]` (para `kind` de evento remoto, o mesmo id).
  - API de módulo (todas `static`): `use(player, id) -> bool`, `tick(player, delta, move_dir := Vector3.ZERO, move_speed := 0.0)`, `pose(player, p: Dictionary)`, `play_remote(player, kind, a, b)`, `can_dodge_cancel(player) -> bool`, **novo** `release(player) -> void` (chamado quando a tecla do slot da habilidade em execução é solta; `SwordAbilities.release` não faz nada).
  - `player.ability_slot: int` — slot (1–4) da tecla que começou a habilidade; `_physics_process` chama `_ab_module(ability).release(self)` quando `Input.is_action_just_released("spell_%d" % ability_slot)`.
  - `cast()`: as magias antigas (`fireball`, `heal`, `frost_nova`) continuam no `match` atual; qualquer outra habilidade com `ready == false` → "Em breve!"; com `ready == true` e não sendo magia antiga → `_ab_module(id).use(self, id)`.
- Consumes: Fase 1 inteira.

- [ ] **Step 1: Merge** `git merge origin/main`; rodar smoke, colony e net test da Horda; tudo verde antes de seguir (commit do merge).
- [ ] **Step 2: Teste**

```gdscript
	for id in ItemDB.ABILITIES:
		check(Game.ability_implemented(id) == ItemDB.ABILITIES[id].ready, "fonte única de 'pronta' (%s)" % id)
	check(player._ab_module("sword_whirl") == SwordAbilities and player._ab_module("bow_gale") == BowAbilities
		and player._ab_module("meteor_rain") == StaffAbilities, "despacho por módulo da classe")
```

- [ ] **Step 3: Ver falhar. Step 4: Implementar. Step 5: Smoke verde (todos os checks da Fase 1 continuam passando).**
- [ ] **Step 6: Commit** — `git commit -m "Habilidades: despacho por módulo da arma e fonte única de 'pronta'"`

---

### Task 2: Tiro Triplo (arco, slot 1)

**Files:** `scripts/player/abilities/bow_abilities.gd`, `scripts/player/knight_moves.gd` ou `knight_anim.gd` (pose curta de disparo rápido), `scripts/autoload/item_db.gd` (`ready = true`), `tests/smoke_test.gd`

**Interfaces:** Consumes Task 1 API; `player._spawn_projectile(kind, origin, d, dmg, crit, pierce, spd)`; `player.aim_dir(origin)`.

- Comportamento: 0,12 s puxando a corda (pose de `bow_draw_pose` acelerada até carga 1) → dispara 3 flechas em leque de ±12° no plano horizontal a partir de `aim_dir`, velocidade de flecha cheia (42), dano de cada uma `Game.melee_damage() * 0.8`, `pierce` 0 (+2 se a arma tiver fx `"pierce"`), crit normal → 0,25 s de recuperação (`bow_release_pose`). Ignora fx `"multishot"` da arma (sem multiplicar). Efeito contido: `FXEpic.sparks` curtas na mão do arco e um `flash` fraco. Esquiva cancela só antes do disparo.
- Rede: `send_event("bow_triple", origem, direção_central)`; réplica cria as 3 flechas `visual_only` (o mesmo que o evento `"arrow"` já faz).

- [ ] **Step 1: Teste** — com arco equipado, slime a 6 m na mira: `use_slot(1)`; após `wait_until(ability == "")`: 3 projéteis criados no disparo (contar filhos `Projectile` logo após o disparo), slime perdeu vida, recarga > 0; com uma arma de fx `"multishot"` (se existir em `ItemDB`; senão, forçar o fx) continuam 3 projéteis. Restaurar equipamento.
- [ ] **Step 2: Ver falhar. Step 3: Implementar. Step 4: Smoke verde + print do disparo.**
- [ ] **Step 5: Commit** — `git commit -m "Arco: Tiro Triplo"`

---

### Task 3: Flecha Glacial (arco, slot 2)

**Files:** `scripts/player/abilities/bow_abilities.gd`, `scripts/player/projectile.gd` (novo `kind` ou fx `"glacial"`), `scripts/autoload/item_db.gd` (`ready = true`), `tests/smoke_test.gd`

**Interfaces:** Consumes Task 1–2; `take_damage(dmg, from, crit, slow, stun)` (atordoamento já vai ao servidor; chefes imunes ao atordoamento).

- Comportamento: tensão de 0,35 s com a flecha brilhando em azul-gelo (glow na ponta) → flecha única, velocidade 40, dano `Game.melee_damage() * 1.4`, `pierce` 0. No primeiro inimigo atingido: `stun` 1,5 s (prende) + `slow` 3,0 s; efeito de gelo no alvo (cristais: `FX.burst` azul-claro não aditivo + `FXEpic.glow_burst` frio + `ground_mark("ring")` azul por 1,5 s). Rastro de flocos (`FXEpic.trail` azul) no voo. Chefe: só o slow.
- Rede: `send_event("bow_frost", origem, direção)`; réplica cria a flecha `visual_only` com o mesmo visual.

- [ ] **Step 1: Teste** — `Game.level = 3`, arco, slime na mira: `use_slot(2)`; `wait_until(slime.hp < hp0)`; `slime.stagger > 0.8` e `slime.slow_timer > 1.5`; depois, num chefe (se houver um spawnável no smoke; senão um inimigo com `boss = true` forçado): `stagger <= 0.35` (só o tranco normal) e `slow_timer > 0`.
- [ ] **Step 2: Ver falhar. Step 3: Implementar. Step 4: Verde + print do impacto.**
- [ ] **Step 5: Commit** — `git commit -m "Arco: Flecha Glacial"`

---

### Task 4: Flecha do Vendaval (ultimate do arco, segurar e soltar)

**Files:** `scripts/player/abilities/bow_abilities.gd`, `scripts/player/knight_anim.gd` (pose agachada e inclinada para trás), `scripts/autoload/item_db.gd` (`ready = true`), `tests/smoke_test.gd`

**Interfaces:** Consumes Tasks 1–3 (`release`), `FXEpic.*`, `player.cam_back`, `end_ability`.

- Comportamento:
  - **Tensão (segurando 4):** de 0 a 1,2 s a carga vai de 0 a 1. Pose: agacha (joelhos dobram até ~0,9 rad), tronco inclina para trás (~0,35 rad), braço da corda puxa além do normal; o arco treme (ruído pequeno no `wrist`) crescendo com a carga. Efeitos: vento espiralando em volta do jogador (stream de partículas finas puxadas para a flecha), luz branco-azulada crescendo na ponta, poeira girando no chão, câmera recua (`cam_back` até 0,7) e leve zoom/FOV. Anda a 0% (parado). Esquiva não cancela (`can_dodge_cancel` false): a fúria já foi gasta em `use`.
  - **Disparo:** ao soltar a tecla com carga ≥ 0,25, ou automaticamente ao chegar a 1,0. Carga < 0,25 ao soltar → continua tensionando até 0,25 e dispara. A flecha é um raio contínuo (não física): percorre 40 m na direção de `aim_dir` em 0,25 s, atravessando todos os inimigos (cada um uma vez) e parando em parede. Dano `Game.melee_damage() * lerp(3.0, 6.0, carga)`, empurrão para os lados da linha. Efeitos: onda de choque no disparo (`FX.ring` + `glow_burst` branco), recuo forte do corpo, rastro de vento em espiral ao longo da linha (`trail` + `sparks` alinhadas), linhas de velocidade, `hit_stop(0.06)` no primeiro acerto, `add_shake(0.35)`, marca no chão ao longo da linha (`ground_mark("scorch")` em 3–4 pontos com cor de vento/poeira).
  - **Recuperação:** 0,4 s.
- Acertos da ultimate não enchem fúria. Morte/menu/troca de arma durante a tensão: `end_ability()` sem disparar.
- Rede: `send_event("bow_gale", posição, Vector3.ZERO)` no início (réplica toca a tensão); `send_event("bow_gale_fire", origem, direção * carga)` no disparo (réplica toca o disparo e o raio visual, sem dano).

- [ ] **Step 1: Teste** — `Game.level = 8`, fúria 100, arco; 3 slimes em linha a 5/10/15 m na mira e um fora da linha: `use_slot(4)`; simular soltura chamando `BowAbilities.release(player)` após 0,6 s; `wait_until(ability == "")`: os 3 em linha perderam vida, o de fora não; fúria == 0 depois (acertos não recarregam). Segundo caso: sem soltar, dispara sozinha em ≤ 1,4 s. Terceiro: `_die()` durante a tensão → nenhum slime perde vida, `ability == ""`, `Engine.time_scale == 1.0`, `cam_back` volta; `revive`.
- [ ] **Step 2: Ver falhar. Step 3: Implementar. Step 4: Verde + prints (tensão no começo/meio/cheia, disparo, linha) + medir FPS com 4 ultimates (mesma medição da Fase 1).**
- [ ] **Step 5: Commit** — `git commit -m "Arco: ultimate Flecha do Vendaval"`

---

### Task 5: Chuva de Meteoros (ultimate do cajado, canalizada)

**Files:** `scripts/player/abilities/staff_abilities.gd`, `scripts/player/knight_anim.gd` (pose de canalizar), `scripts/autoload/item_db.gd` (`ready = true`), `tests/smoke_test.gd`

**Interfaces:** Consumes Tasks 1 (`release`), `FXEpic.*`, `player.aim_dir`, `end_ability`.

- Comportamento:
  - **Área:** centro no ponto do chão para onde a câmera mira, limitado a 14 m do jogador (raio da área 5 m). Fixada no início da canalização. Marca no chão: anel vermelho pulsando (`ground_mark("ring")`) durante a chuva.
  - **Preparo 0,5 s:** cajado erguido com as duas mãos, gema brilhando, círculo de runas/brasas subindo do chão em volta do mago, luz laranja-avermelhada.
  - **Canalização (segurando 4, até 4,0 s):** o mago fica parado (anda 0%), corpo treme levemente, cajado aceso. Sobre a área: o "céu escurece" — um disco escuro translúcido no alto (MeshInstance3D com material alfa, ~12 m acima) mais uma luz direcional/omni avermelhada local e fumaça escura girando. A cada 0,18 s cai um meteoro num ponto aleatório da área: rocha incandescente (malha simples com material emissivo) descendo em diagonal em 0,45 s com rastro de fogo e fumaça, explosão no impacto (raio 2,2 m, dano `(14.0 + Game.spell_power() * 1.6) * Game.damage_mult()`, empurrão para fora), `glow_burst` + `sparks` + `smoke` + `ground_mark("scorch")` + brasas no chão; `add_shake(0.08)` por impacto, `flash` curto.
  - **Fim:** soltar a tecla, esquivar, morrer, menu, troca de arma ou 4,0 s de canalização. Se a canalização terminou por soltar, tempo ou esquiva, os meteoros já no ar terminam a queda e causam dano. Se terminou por morte, menu ou troca de arma, `end_ability` remove os meteoros no ar sem dano. Esquiva encerra a canalização (`can_dodge_cancel` true durante a canalização, false no preparo).
- Acertos não enchem fúria; não gasta mana.
- Rede: `send_event("meteor_rain", centro, Vector3(seed, 0, 0))` no início (a réplica gera os mesmos pontos com `RandomNumberGenerator` semeado) e `send_event("meteor_rain_end", ...)` no fim (a réplica para de gerar). Réplica: visual completo, sem dano.

- [ ] **Step 1: Teste** — `Game.level = 8`, fúria 100, cajado; 3 slimes dentro da área mirada e 1 fora: `use_slot(4)`; `wait_until(algum slime da área perdeu vida, 3 s)`; soltar (`StaffAbilities.release(player)`) aos 2,0 s; após `wait_until(ability == "")` + 0,6 s: nenhum meteoro novo nasce (contar nós de meteoro), os da área perderam vida, o de fora não, fúria == 0, mana não mudou. Segundo caso: sem soltar, termina sozinha em ≤ 4,6 s. Terceiro: mirar no céu → centro a ≤ 14 m do jogador. Quarto: `_die()` no meio → meteoros no ar removidos, nenhum dano depois, `time_scale == 1.0`; `revive`.
- [ ] **Step 2: Ver falhar. Step 3: Implementar. Step 4: Verde + prints (preparo, chuva de longe e de perto, impacto) + medir FPS com 4 Chuvas ao mesmo tempo e 12+ inimigos.**
- [ ] **Step 5: Commit** — `git commit -m "Cajado: ultimate Chuva de Meteoros"`

---

### Task 6: Multiplayer e fechamento da Fase 2

**Files:** `tests/net_test.gd`, ajustes onde a rede mostrar problema.

- [ ] **Step 1: Net test** — peer Ana troca para arco (nível 8, fúria 100) e usa Tiro Triplo, Flecha Glacial e Flecha do Vendaval; troca para cajado e usa a Chuva de Meteoros (soltando a tecla por código). Beto confirma que a réplica de Ana entrou em cada habilidade (`ability != ""` observado) e voltou ao normal. Restaurar nível e equipamento de Ana.
- [ ] **Step 2: Ver falhar. Step 3: Implementar o que faltar.**
- [ ] **Step 4: Rodar tudo como o CI** — smoke, colônia, net test da Horda (7790) e da cidade em grupo (7791), matando só os PIDs iniciados. Tudo PASSOU.
- [ ] **Step 5: Commit** — `git commit -m "Habilidades do cajado e do arco replicadas no multiplayer"`
- [ ] **Step 6: Entregar ao usuário para testar as 3 ultimates e decidir o PR.** Não abrir PR sem o ok dele.
