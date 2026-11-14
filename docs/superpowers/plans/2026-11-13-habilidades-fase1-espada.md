# Habilidades por arma — Fase 1 (base de efeitos, fúria e kit da espada) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trocar as magias globais por kits de habilidade por arma, criar a barra de fúria com a ultimate na tecla 4 e entregar o kit completo da espada (Investida, Golpe Sísmico, Turbilhão) com a base nova de efeitos épicos.

**Architecture:** Os dados dos kits ficam em `ItemDB.ABILITIES` (por classe de arma); `Game` guarda a fúria e responde qual kit/habilidade está liberado; `player.gd` despacha a tecla para a habilidade do kit da arma atual; cada habilidade da espada vive num arquivo próprio (`scripts/player/abilities/sword_abilities.gd`) para não inchar `player.gd`; os efeitos novos ficam em `scripts/fx_epic.gd` (classe `FXEpic`), no mesmo estilo de `fx.gd`. Réplicas no multiplayer recebem eventos por `Network.send_event` e tocam pose e efeito localmente.

**Tech Stack:** Godot 4.7.2, GDScript, CPUParticles3D/MeshInstance3D/OmniLight3D criados por código.

**Spec:** `docs/superpowers/specs/2026-11-13-habilidades-armas-design.md`

## Global Constraints

- Trabalhar no worktree `C:/Games/godot-3d-habilidades`, branch `habilidades`.
- Godot: `C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe`. Smoke test: `--headless --path . res://scenes/world.tscn -- --smoketest` (sai com código 0 se passou).
- Tudo criado por código; nenhum efeito no servidor dedicado (`Network.is_server()` → não cria nada).
- Tecla da ultimate: `4` (ação `spell_4`). R continua sendo poção de vida.
- Liberação: habilidade 1 no nível 1, 2 no nível 3, 3 no nível 5, ultimate no nível 8.
- Habilidades do cajado gastam mana; espada e arco só têm recarga.
- Fúria 0–100; enche com dano causado e (mais devagar) recebido; não esvazia com o tempo; ultimate zera; trocar de arma mantém.
- Dano das habilidades da espada escala com `Game.melee_damage()` (FOR) e `Game.damage_mult()` onde as magias já usam.
- Habilidades comuns têm efeito contido; só a ultimate enche a tela.
- Funcionam igual no Desafio da Horda.
- Textos para o jogador em português.

## Review Focus

1. **Morrer, esquivar ou abrir menu no meio do Turbilhão:** o jogador sai do estado de habilidade limpo (sem ficar girando, sem velocidade travada, `Engine.time_scale` volta a 1.0). Teste na Task 6.
2. **Trocar de arma com a habilidade em recarga ou durante o efeito:** as recargas são por id de habilidade e continuam contando; a barra de ações mostra o kit novo na hora. Teste na Task 2.
3. **Apertar 4 com a fúria cheia mas abaixo do nível 8 (ou com fúria incompleta):** nada acontece além do aviso; a fúria não é gasta. Teste na Task 3.
4. **Réplica de outro jogador:** recebe o evento e toca pose e efeito sem causar dano (dano só do dono). Teste na Task 7 (net test).
5. **Hit stop com vários acertos no mesmo quadro:** `Engine.time_scale` nunca fica abaixo de 0,05 nem preso; acertos seguidos não empilham. Teste na Task 1.

---

### Task 1: Base de efeitos épicos (`FXEpic`)

**Files:**
- Create: `scripts/fx_epic.gd`
- Test: `tests/smoke_test.gd` (nova função `_test_fx_epic()` chamada no fluxo principal, antes de `_test_farm()`)

**Interfaces:**
- Produces (todas `static`, retornam `void`, não fazem nada no servidor dedicado; usam `FX._scene()`):
  - `FXEpic.glow_burst(pos: Vector3, color: Color, amount := 40, speed := 6.0, size := 0.18, lifetime := 0.7, gravity := -4.0)` — partículas em quad billboard com material aditivo e textura radial suave (gerada uma vez e guardada em variável estática), cor desbotando pelo gradiente.
  - `FXEpic.sparks(pos: Vector3, dir: Vector3, color: Color, amount := 30, speed := 12.0, lifetime := 0.45)` — faíscas alongadas pela velocidade (`CPUParticles3D` com `particle_flag_align_y`), cone de 35° em `dir`.
  - `FXEpic.smoke(pos: Vector3, color := Color(0.35, 0.32, 0.3, 0.6), amount := 16, radius := 1.0, lifetime := 1.4)` — fumaça/poeira: quads alfa (não aditivos) que crescem e somem subindo devagar.
  - `FXEpic.flash(pos: Vector3, color: Color, energy := 4.0, range_m := 6.0, time := 0.25)` — `OmniLight3D` que apaga com tween e se libera.
  - `FXEpic.ground_mark(pos: Vector3, color: Color, radius: float, time := 2.5, kind := "crack")` — mancha no chão (`Decal` com textura gerada: `"crack"` rachaduras radiais, `"scorch"` mancha queimada, `"ring"` anel), some com fade.
  - `FXEpic.trail(target: Node3D, color: Color, width := 0.5, time := 1.0) -> void` — rastro de fita seguindo `target` (ImmediateMesh atualizada por um nó auxiliar filho da cena; guarda os últimos ~20 pontos da base e da ponta: `target.global_position` e `target.global_position + target.global_basis.y * width`), aditivo, some no fim.
  - `FXEpic.hit_stop(duration := 0.06, scale := 0.05) -> void` — põe `Engine.time_scale = scale` e volta para 1.0 depois de `duration` segundos reais (`get_tree().create_timer(duration, true, false, true)`); se já há um ativo, só estende o fim (não empilha). Roda em qualquer cliente (só afeta a tela local); não roda no servidor dedicado.
  - `FXEpic.ACTIVE_LIMIT := 900` — se a soma de `amount` dos emissores vivos passa disso, novos emissores reduzem `amount` pela metade (guarda contador estático, decrementado ao liberar).

- [ ] **Step 1: Escrever `_test_fx_epic()` em `tests/smoke_test.gd`**

```gdscript
func _test_fx_epic() -> void:
	var p := player.global_position
	var n0 := get_tree().current_scene.get_child_count()
	FXEpic.glow_burst(p, Color.ORANGE)
	FXEpic.sparks(p, Vector3.UP, Color.YELLOW)
	FXEpic.smoke(p)
	FXEpic.flash(p, Color.ORANGE)
	FXEpic.ground_mark(p, Color.BLACK, 2.0)
	FXEpic.trail(player.model, Color.ORANGE)
	check(get_tree().current_scene.get_child_count() >= n0 + 6, "efeitos épicos criados")
	FXEpic.hit_stop(0.05)
	FXEpic.hit_stop(0.05)
	check(Engine.time_scale >= 0.05 and Engine.time_scale < 1.0, "hit stop ativo (%.2f)" % Engine.time_scale)
	await get_tree().create_timer(0.3, true, false, true).timeout
	check(is_equal_approx(Engine.time_scale, 1.0), "hit stop volta para 1.0")
	await wait(2.0)
	check(get_tree().current_scene.get_child_count() <= n0 + 1, "efeitos épicos se liberam")
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://scenes/world.tscn -- --smoketest`
Expected: erro de parse "Identifier FXEpic not declared".

- [ ] **Step 3: Implementar `scripts/fx_epic.gd`** com as funções acima. Texturas geradas uma vez (`Image` 64×64 → `ImageTexture`) em variáveis estáticas. Cada emissor `one_shot` se libera com `finished.connect(queue_free)`.

- [ ] **Step 4: Rodar o smoke test** — Expected: termina com código 0 e as 5 checagens novas passam.

- [ ] **Step 5: Olhar de verdade.** Rodar o jogo (`--path .` sem `--headless`), chamar os efeitos por uma tecla de depuração temporária e tirar print; ajustar tamanhos/cores. Remover a tecla de depuração.

- [ ] **Step 6: Commit** — `git commit -m "FXEpic: partículas com brilho, faíscas, fumaça, luz, marcas no chão, rastro e hit stop"`

---

### Task 2: Kits de habilidade por arma (substitui `SPELLS`)

**Files:**
- Modify: `scripts/autoload/item_db.gd` (`SPELLS` → `ABILITIES` + `KITS`)
- Modify: `scripts/autoload/game.gd` (`knows_spell` → `knows_ability`, nova `ability_kit`, ação `spell_4`)
- Modify: `scripts/player/player.gd` (`cooldowns`, leitura das teclas, `cast`)
- Modify: `scripts/ui/hud.gd` (barra de ações monta/remonta pelo kit), `scripts/ui/game_menu.gd:477` (lista de habilidades)
- Create: `scripts/player/abilities/sword_abilities.gd` (vazio por enquanto: só a classe `SwordAbilities` com `static func use(player, id: String) -> bool` retornando `false`)
- Test: `tests/smoke_test.gd` (bloco "--- magia" passa a usar o kit)

**Interfaces:**
- Produces:
  - `ItemDB.ABILITIES: Dictionary` — id → `{"name", "class", "slot" (1..4), "level", "cooldown", "cost" (0 se sem mana), "ultimate": bool, "desc"}`. Ids: `fireball`, `frost_nova`, `heal` (classe `staff`, slots 1/2/3, níveis 1/3/5, custos/recargas atuais), `meteor_rain` (staff, slot 4, nível 8, ultimate), `sword_charge` (sword, 1, nível 1, recarga 6 s), `sword_quake` (sword, 2, nível 3, recarga 9 s), `sword_whirl` (sword, 4, nível 8, ultimate), `bow_triple` (bow, 1, nível 1), `bow_frost` (bow, 2, nível 3), `bow_gale` (bow, 4, nível 8, ultimate). As do cajado/arco além das atuais ficam declaradas mas `player.cast` responde "Em breve" até a Fase 2.
  - `ItemDB.kit(cls: String) -> Array[String]` — ids da classe ordenados por slot.
  - `Game.ability_kit() -> Array[String]` — `ItemDB.kit(weapon_class())`.
  - `Game.knows_ability(id: String) -> bool` — `level >= ABILITIES[id].level`.
  - `player.cooldowns` vira dicionário com **todos** os ids de `ABILITIES` (recarga continua ao trocar de arma).
  - `player.use_slot(slot: int) -> void` — pega o id do slot no kit atual e chama `cast(id)`; slot sem habilidade não faz nada.
  - `player.cast(id)` mantém as checagens atuais; custo de mana só se `cost > 0`; despacha `"sword_*"` para `SwordAbilities.use(self, id)`.
  - Sinal `Game.kit_changed` emitido quando `weapon_class()` muda (no equipar); `hud.gd` reconstrói os ícones dos slots 1–3 e 4 ao recebê-lo.
- Consumes: nada de tarefas anteriores.

- [ ] **Step 1: Atualizar o smoke test** (bloco "--- magia" e um bloco novo após equipar a espada):

```gdscript
	# jogador começa sem arma ou de espada: weapon_class() == "sword"
	check(Game.ability_kit() == ["sword_charge", "sword_quake", "sword_whirl"], "kit da espada (%s)" % [Game.ability_kit()])
	check(not Game.knows_ability("sword_quake") and Game.knows_ability("sword_charge"), "liberação por nível")
	player.cooldowns.sword_charge = 3.0
	Game.add_item("apprentice_staff")   # ou o nome de adicionar item que game.gd usa
	Game.equip("apprentice_staff")
	await wait(0.1)
	check(Game.ability_kit() == ["fireball", "frost_nova", "heal", "meteor_rain"], "trocar de arma troca o kit")
	check(player.cooldowns.sword_charge > 2.5, "recarga continua depois de trocar de arma")
	check(hud_slot_ids() == Game.ability_kit(), "barra de ações mostra o kit novo")
```

(`hud_slot_ids()` é um helper novo no teste que lê os ids dos slots 1–4 da HUD; ajustar o nome da função de equipar ao que `game.gd` já usa. O bloco antigo de `player.cast("fireball")` passa a rodar depois de equipar o cajado.)

- [ ] **Step 2: Rodar e ver falhar** — Expected: "Invalid call. Nonexistent function 'ability_kit'".
- [ ] **Step 3: Implementar** os itens da Interface; registrar `"spell_4": [KEY_4]` em `game.gd:194`; `player.gd:323` passa a ler `spell_1..4` e chamar `use_slot(i + 1)`. Atualizar todo uso de `ItemDB.SPELLS`/`knows_spell` (`grep -rn "SPELLS\|knows_spell" scripts tests .claude/skills`), incluindo `survival_mode.gd` e o `dump_data.gd` do balance-check.
- [ ] **Step 4: Rodar o smoke test** — Expected: código 0.
- [ ] **Step 5: Commit** — `git commit -m "Habilidades por arma: kits em ItemDB.ABILITIES, tecla 4, HUD troca com a arma"`

---

### Task 3: Barra de fúria e slot da ultimate

**Files:**
- Modify: `scripts/autoload/game.gd` (fúria), `scripts/player/player.gd` (dano recebido, checagem da ultimate), `scripts/ui/hud.gd` (slot 4 com anel de fúria)
- Create: `scripts/ui/fury_ring.gd` (Control que desenha o anel em volta do slot 4)
- Test: `tests/smoke_test.gd`

**Interfaces:**
- Produces:
  - `Game.fury: float` (0..100, salvo no save como os outros campos de `Game`), `const FURY_MAX := 100.0`.
  - `Game.add_fury(amount: float) -> void` — soma com clamp e emite `stats_changed`.
  - `Game.fury_full() -> bool`.
  - Ganho: em `Game.on_damage_dealt(amount)` soma `clampf(amount / max(1.0, alvo_hp_max) * 50.0, 0.5, 6.0)` — como `on_damage_dealt` não recebe o alvo, mudar a assinatura para `on_damage_dealt(amount: float, target_max_hp := 100.0)` e passar `e.max_hp` (campo de `enemy.gd`) nos chamadores. Dano recebido em `player.take_damage`: `Game.add_fury(amount / Game.max_hp() * 25.0)`.
  - Em `player.cast(id)` para ultimate: se `not Game.fury_full()` → aviso "Fúria incompleta!" e retorna sem gastar; se nível baixo → aviso de nível (já existe); ao usar → `Game.fury = 0`.
  - HUD: slot 4 com `FuryRing` (arco de 0 a 360° proporcional à fúria, cor laranja-vermelha, pulsa e brilha quando cheio; selo de tecla "4").
- Consumes: `ItemDB.ABILITIES[..].ultimate`, `player.use_slot` (Task 2).

- [ ] **Step 1: Teste**

```gdscript
	Game.fury = 0.0
	var e := _nearest("slime")
	e.take_damage(5.0, player.global_position, false)   # pelo caminho do jogador: usar player._do_hit() perto do slime
	check(Game.fury > 0.0, "fúria sobe ao causar dano (%.1f)" % Game.fury)
	Game.level = 8
	Game.fury = 50.0
	player.use_slot(4)
	check(Game.fury == 50.0, "ultimate não sai com fúria incompleta")
	Game.level = 2
	Game.fury = 100.0
	player.use_slot(4)
	check(Game.fury == 100.0, "ultimate não sai abaixo do nível 8")
```

- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Rodar o smoke test** — código 0. Rodar o jogo e conferir o anel da HUD visualmente (print).
- [ ] **Step 5: Commit** — `git commit -m "Barra de fúria e slot da ultimate"`

---

### Task 4: Investida (espada, slot 1)

**Files:**
- Modify: `scripts/player/abilities/sword_abilities.gd`, `scripts/player/player.gd` (estado `ability`, pose, evento remoto), `scripts/player/knight_moves.gd` (trilha `CHARGE`)
- Test: `tests/smoke_test.gd`

**Interfaces:**
- Produces (usadas também pelas Tasks 5 e 6):
  - `player.ability: String` (id em execução, `""` se nenhum) e `player.ability_t: float` (tempo desde o início). Enquanto `ability != ""`: bloqueia ataque, outras habilidades, arco; `_physics_process` chama `SwordAbilities.tick(self, delta)`.
  - `player.end_ability() -> void` — limpa estado, velocidade especial e `Engine.time_scale`; chamado no fim normal, em `die()`, ao abrir menu (`build_lock`/controle bloqueado) e ao trocar de arma.
  - Flag de rede nova `NF_ABILITY` em `_player_state`; a réplica usa o evento para saber qual.
  - `SwordAbilities.tick(player, delta) -> void`, `SwordAbilities.play_remote(player, kind: String, a: Vector3, b: Vector3) -> void`.
- Comportamento: 0,15 s de preparo (agacha, espada para trás) → avança 5 m em 0,25 s na direção `facing()` (para em parede), dano `Game.melee_damage() * 1.6` a cada inimigo no caminho (uma vez cada, raio 1,4 m) → 0,2 s de recuperação. Efeitos: `FXEpic.trail` na espada, `sparks` contínuas no chão, `smoke` de poeira na saída e na chegada, `flash` leve no impacto. Esquiva **cancela** só durante o preparo.
- Rede: `Network.send_event("sword_charge", origem, direção)`.

- [ ] **Step 1: Teste** — slime a 3 m à frente; `player.use_slot(1)`; após 0,6 s: `slime.hp < hp0`, `player.global_position` andou entre 3 e 5,5 m, `player.ability == ""`, `player.cooldowns.sword_charge > 0`.
- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Implementar** (trilha em `KnightMoves.CHARGE` no formato das trilhas existentes, tocada com `KnightAnim.play_track` em `_animate` quando `ability == "sword_charge"`).
- [ ] **Step 4: Smoke test verde + olhar no jogo** (print do meio da investida).
- [ ] **Step 5: Commit** — `git commit -m "Espada: Investida"`

---

### Task 5: Golpe Sísmico (espada, slot 2)

**Files:** `scripts/player/abilities/sword_abilities.gd`, `scripts/player/knight_moves.gd` (trilha `QUAKE`), `tests/smoke_test.gd`

**Interfaces:** Consumes `player.ability`, `end_ability`, `SwordAbilities.tick/play_remote` (Task 4); `FXEpic.*` (Task 1).

- Comportamento: 0,35 s erguendo a espada com as duas mãos (pula de leve) → golpe no chão aos 0,35 s → cone de 70° e 6 m à frente: dano `Game.melee_damage() * 2.0`, atordoamento de 1,0 s (usar o mesmo parâmetro de lentidão de `take_damage` com valor alto, ou um `stun` se o inimigo já tiver) → 0,3 s de recuperação. Efeitos: `ground_mark("crack")` no ponto de impacto, 5 `smoke` + pedras (`glow_burst` com cor de pedra, gravidade alta, sem aditivo) ao longo do cone em sequência (onda que avança ~0,08 s por metro), `flash` e `hit_stop(0.05)` se acertou alguém, `add_shake(0.3)`.
- Rede: `Network.send_event("sword_quake", ponto, direção)`.

- [ ] **Step 1: Teste** — `Game.level = 3`; slime a 3 m à frente e outro a 3 m atrás; `use_slot(2)`; após 0,8 s o da frente perdeu vida, o de trás não.
- [ ] **Step 2: Ver falhar.** - [ ] **Step 3: Implementar.** - [ ] **Step 4: Verde + olhar no jogo.**
- [ ] **Step 5: Commit** — `git commit -m "Espada: Golpe Sísmico"`

---

### Task 6: Turbilhão (ultimate da espada)

**Files:** `scripts/player/abilities/sword_abilities.gd`, `scripts/player/knight_anim.gd` (pose de giro), `scripts/player/player.gd`, `tests/smoke_test.gd`

**Interfaces:** Consumes Tasks 1, 3, 4.

- Comportamento (total ~2,1 s):
  - **Preparo 0,4 s:** abaixa o corpo, espada para trás com as duas mãos, `glow_burst` de brasas subindo ao redor, `flash` crescente, câmera recua um pouco.
  - **Giro 1,5 s:** `model.rotation.y` gira 4 voltas (acelera e mantém), braços estendidos com a lâmina horizontal, tronco inclinado; anda devagar (40% da velocidade) seguindo o input. A cada volta: dano `Game.melee_damage() * 1.2` em raio 3,5 m, puxa inimigos para dentro (impulso de ~3 m/s em direção ao jogador), `sparks` nos acertos, `hit_stop(0.03)`. Efeitos contínuos: `trail` de fogo na ponta da espada, anel de poeira `smoke` no chão a cada 0,25 s, `ground_mark("scorch")` se arrastando, luz laranja pulsando presa ao jogador.
  - **Final 0,2 s:** golpe final para baixo, `glow_burst` grande, onda `FX.ring` de 5 m, `hit_stop(0.08)`, `add_shake(0.4)`, dano `* 2.5` em raio 4 m.
- Imune a empurrão durante o giro; esquiva não cancela; morte, menu e troca de arma chamam `end_ability()`.
- Rede: `send_event("sword_whirl", posição, Vector3.ZERO)` no início; réplicas tocam o giro e os efeitos por 2,1 s (sem dano).

- [ ] **Step 1: Teste**

```gdscript
	Game.level = 8
	Game.fury = 100.0
	var s1 := _nearest("slime")
	player.global_position = s1.global_position + Vector3(2.5, 0.3, 0)
	var h1: float = s1.hp
	player.use_slot(4)
	check(Game.fury == 0.0 and player.ability == "sword_whirl", "Turbilhão começa e gasta a fúria")
	await wait(1.0)
	check(s1.hp < h1, "Turbilhão causa dano durante o giro")
	player._die()
	await wait(0.1)
	check(player.ability == "" and is_equal_approx(Engine.time_scale, 1.0), "morrer no meio limpa o estado")
	player.revive(player.global_position)
```

- [ ] **Step 2: Ver falhar.** - [ ] **Step 3: Implementar.**
- [ ] **Step 4: Verde + olhar no jogo** com o Montante do Guardião e com a espada inicial; gravar prints do preparo, giro e final. Medir FPS com o monitor do Godot durante o giro numa clareira com 10+ inimigos: sem queda perceptível em relação a parado.
- [ ] **Step 5: Commit** — `git commit -m "Espada: ultimate Turbilhão"`

---

### Task 7: Réplicas no multiplayer e fechamento da fase

**Files:** `scripts/player/player.gd` (`play_remote_event` → `SwordAbilities.play_remote` para `"sword_*"`), `tests/net_test.gd`

- [ ] **Step 1: Teste no net test:** o peer "Ana" usa as três habilidades da espada (forçar nível 8 e fúria 100); o outro peer confere que a réplica de Ana entrou no estado de habilidade (`ability != ""` na réplica por um instante) e que o servidor não criou nós de efeito. Rodar como no CI (`--server --port=7790 ...` + 2 peers), matando o servidor pelo PID ao fim.
- [ ] **Step 2: Ver falhar.** - [ ] **Step 3: Implementar.** - [ ] **Step 4: Rodar a skill `smoke-check`** — todos PASSOU.
- [ ] **Step 5: Commit** — `git commit -m "Habilidades da espada replicadas no multiplayer"`
- [ ] **Step 6: Entregar ao usuário para testar** o "nível de épico" antes da Fase 2 (cajado e arco). Não abrir PR sem o ok dele.
