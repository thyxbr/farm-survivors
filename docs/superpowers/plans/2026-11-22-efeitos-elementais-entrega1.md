# Efeitos elementais — Entrega 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Arma encantada com fogo, gelo ou veneno tem chance de aplicar um status no monstro (queimadura, lentidão/congelamento, veneno de ticks), cortada pela resistência do Bestiário, controlado pelo servidor e visível no corpo do monstro para todos.

**Architecture:** Regras puras em `StatusRules` (testáveis no runner `-s`). Um nó `StatusEffects` em cada `Enemy` guarda os efeitos ativos e roda os ticks no dono (servidor ou solo); réplicas só recebem um bitmask pelo snapshot. O cliente que bate rola a chance e pede o status ao servidor (`client_apply_status`, no lugar de `client_mark_enemy`). `StatusAura` desenha contorno + partículas a partir do bitmask.

**Tech Stack:** Godot 4.7.2, GDScript. Testes: `tests/unit/run.gd` (unitários), `tests/smoke_test.gd`, `tests/net_test.gd`.

**Spec:** `docs/superpowers/specs/2026-11-22-efeitos-elementais-design.md`

## Global Constraints

- Só fogo, gelo e veneno ganham status nesta entrega. Raio, sombra e sagrado continuam exatamente como hoje (`EnchantHit.on_hit`/`scale`).
- `chance_final = chance_base × (1 − resistência)`; resistência do monstro = `clamp(1 − element_pct/100, 0, 1)`.
- "Resistiu" aparece só quando a resistência ≥ 1.0 barrou um efeito que teria rolado.
- O mesmo efeito não empilha: reaplicar renova a duração e fica o valor mais forte. Efeitos diferentes coexistem.
- Congelamento: 3 aplicações de gelo dentro da lentidão ativa → congela 1.0 s; depois 5.0 s sem poder congelar; chefes e elites nunca congelam.
- Ticks rodam só no dono; no servidor, o tick conta como acerto do peer que aplicou (`last_hitter`), inclusive morte/XP/loot. Se esse peer saiu, `last_hitter = 0`.
- A marca tóxica (`venom_amp`, `venom_timer`, `apply_venom`, `_mark_enemy`, `client_mark_enemy`) sai inteira.
- `SNAP_STRIDE` passa de 10 para 11; sem compatibilidade com cliente antigo.
- Scripts puros (`StatusRules`) não citam autoloads (`Game`, `Network`...): quebram o runner `-s`.
- Visual no estilo desenhado: puffs arredondados, sem espinhos; poucas partículas pequenas; conferir na câmera do jogo.
- Não mexer em `config/version` (o CI numera).

## Review Focus

1. **Monstro imune (Slime Explosivo + fogo):** nunca pega queimadura, nem com cliente mandando o pedido direto → teste no servidor (Task 4) e em `StatusRules.roll` (Task 1).
2. **Monstro morre por tick no multiplayer:** a morte dá XP/loot ao peer que aplicou, não some → checagem no `net_test` (Task 4).
3. **Chefe atingido por arma de gelo rápida:** fica lento, nunca travado → teste em `StatusRules.should_freeze` (Task 1) e no smoke (Task 3).
4. **Cliente mandando valor absurdo (total 1e9, secs 999, elemento "raio"):** servidor corta ao máximo da tabela ou recusa → `net_test` (Task 4).
5. **Horda grande toda em chamas:** no máximo `StatusAura.MAX_PARTICLE_AURAS` auras com partícula; o resto só contorno → teste do contador (Task 5).

---

### Task 1: `StatusRules` + números em `enchant.json`

**Files:**
- Create: `scripts/character/status_rules.gd`
- Modify: `data/balance/enchant.json` (bloco `effects`)
- Modify: `scripts/character/enchant_rules.gd` (`effect_text`, e comentário de `effect`)
- Test: `tests/unit/test_status_rules.gd` (novo), `tests/unit/test_enchant_rules.gd` (textos)

**Interfaces:**
- Produces (`class_name StatusRules extends RefCounted`):
  - `const BITS := {"fogo": 1, "gelo": 2, "veneno": 4, "congelado": 8}` (16/32/64 reservados para raio/sombra/sagrado na entrega 2)
  - `const STATUS_ELEMENTS := ["fogo", "gelo", "veneno"]`
  - `static func enemy_resist(bt: BalanceTables, kind: String, el: String) -> float`
  - `static func final_chance(base: float, resist: float) -> float`
  - `static func roll(base: float, resist: float, r: float) -> String` — `"applied"`, `"resisted"` ou `"none"`
  - `static func chance(bt: BalanceTables, el: String, level: int) -> float`
  - `static func ticks(bt: BalanceTables, el: String) -> int`
  - `static func renew(cur: Dictionary, power: float, secs: float) -> Dictionary` — `{"power", "timer"}`
  - `static func should_freeze(stacks: int, need: int, protected: bool, cd_left: float) -> bool`
  - `static func cap_power(bt: BalanceTables, el: String, power: float) -> float` — limite do servidor
  - `static func cap_secs(bt: BalanceTables, el: String, secs: float) -> float`

- [ ] **Step 1: Valores novos em `enchant.json`**

```json
"fogo":   {"values": [0.15, 0.22, 0.30, 0.38, 0.45], "secs": 3, "ticks": 3, "chance": [0.25, 0.30, 0.35, 0.40, 0.45]},
"gelo":   {"values": [0.6, 0.9, 1.2, 1.6, 2.0], "chance": [0.30, 0.35, 0.40, 0.45, 0.50], "freeze_stacks": 3, "freeze_secs": 1.0, "freeze_cd": 5.0},
"veneno": {"values": [0.20, 0.27, 0.34, 0.42, 0.50], "secs": 5, "ticks": 5, "chance": [0.25, 0.30, 0.35, 0.40, 0.45]},
```
(raio, sagrado, sombra sem mudança). `values` de fogo e veneno = fração do dano do golpe espalhada nos ticks; de gelo = segundos de lentidão.

- [ ] **Step 2: Escrever `tests/unit/test_status_rules.gd`** (mesmo formato de `test_element_rules.gd`: `_tables()`, `_near`, `T.ok/T.eq`)

```gdscript
func test_resist_do_bestiario() -> void:
	var bt := _tables()
	T.ok(_near(StatusRules.enemy_resist(bt, "slime", "veneno"), 0.25), "afinidade 75 = 25% de resistência")
	T.ok(_near(StatusRules.enemy_resist(bt, "slime", "fogo"), 0.0), "fraco (125) não passa de 0")
	T.ok(_near(StatusRules.enemy_resist(bt, "slime_explosivo", "fogo"), 1.0), "imune = 100%")
	T.ok(_near(StatusRules.enemy_resist(bt, "goblin", "gelo"), 0.0), "sem entrada = 0")

func test_chance_final() -> void:
	T.ok(_near(StatusRules.final_chance(0.30, 0.5), 0.15), "30% com 50% de resistência = 15%")
	T.ok(_near(StatusRules.final_chance(0.30, 1.4), 0.0), "resistência acima de 100% = 0")
	T.ok(_near(StatusRules.final_chance(0.30, -0.2), 0.30), "resistência negativa não aumenta")

func test_roll() -> void:
	T.eq(StatusRules.roll(0.30, 0.5, 0.10), "applied", "abaixo da chance final")
	T.eq(StatusRules.roll(0.30, 0.5, 0.20), "none", "resistência parcial barrou: silencioso")
	T.eq(StatusRules.roll(0.30, 1.0, 0.10), "resisted", "imune barrou um que teria pego")
	T.eq(StatusRules.roll(0.30, 1.0, 0.50), "none", "nem a base pegou: nada")

func test_chance_por_nivel() -> void:
	var bt := _tables()
	T.ok(_near(StatusRules.chance(bt, "fogo", 1), 0.25), "fogo +1")
	T.ok(_near(StatusRules.chance(bt, "gelo", 5), 0.50), "gelo +5")
	T.ok(_near(StatusRules.chance(bt, "raio", 3), 0.0), "raio não é status nesta entrega")
	T.ok(_near(StatusRules.chance(bt, "fogo", 0), 0.0), "sem encanto")
	T.eq(StatusRules.ticks(bt, "veneno"), 5, "veneno em 5 ticks")
	T.eq(StatusRules.ticks(bt, "fogo"), 3, "fogo em 3 ticks")

func test_renova_sem_empilhar() -> void:
	var a := StatusRules.renew({}, 10.0, 3.0)
	T.ok(_near(a.power, 10.0) and _near(a.timer, 3.0), "primeiro")
	var b := StatusRules.renew({"power": 10.0, "timer": 1.0}, 6.0, 3.0)
	T.ok(_near(b.power, 10.0) and _near(b.timer, 3.0), "mais fraco renova tempo, mantém força")
	var c := StatusRules.renew({"power": 10.0, "timer": 2.5}, 14.0, 2.0)
	T.ok(_near(c.power, 14.0) and _near(c.timer, 2.5), "mais forte troca força, tempo fica o maior")

func test_congelamento() -> void:
	T.ok(StatusRules.should_freeze(3, 3, false, 0.0), "3 acúmulos congelam")
	T.ok(not StatusRules.should_freeze(2, 3, false, 0.0), "2 não")
	T.ok(not StatusRules.should_freeze(3, 3, true, 0.0), "chefe/elite nunca")
	T.ok(not StatusRules.should_freeze(3, 3, false, 2.0), "em recarga não")

func test_limites_do_servidor() -> void:
	var bt := _tables()
	T.ok(_near(StatusRules.cap_power(bt, "fogo", 1e9), 5000.0 * 0.45), "fogo: 5000 × maior value")
	T.ok(_near(StatusRules.cap_power(bt, "raio", 10.0), 0.0), "elemento sem status = 0")
	T.ok(_near(StatusRules.cap_secs(bt, "veneno", 999.0), 5.0), "veneno: secs da tabela")
	T.ok(_near(StatusRules.cap_secs(bt, "gelo", 999.0), 2.0), "gelo: maior value (segundos)")
	T.ok(_near(StatusRules.cap_power(bt, "fogo", NAN), 0.0), "lixo vira 0")
```

- [ ] **Step 3: Rodar e ver falhar**

Run: `& "C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path . -s tests/unit/run.gd`
Expected: falha em `test_status_rules` ("StatusRules" não declarado).

- [ ] **Step 4: Implementar `StatusRules`**

`enemy_resist` usa `BestiaryRules.element_pct`. `chance`/`ticks`/caps leem `bt.get_table("enchant").effects`; `chance` devolve 0 para elemento fora de `STATUS_ELEMENTS` ou nível ≤ 0. `cap_power` = `clampf(power, 0, 5000 × max(values))` para fogo/veneno; para gelo o "power" não é usado (devolve 0). `cap_secs` = `secs` da tabela para fogo/veneno, maior `values` para gelo. Valores não finitos viram 0.

- [ ] **Step 5: Atualizar `EnchantRules.effect_text`** para fogo/gelo/veneno:
  - fogo: `"%s%% de chance — Queimadura: %s%% do dano em %s s"`
  - gelo: `"%s%% de chance — Lentidão por %s s; 3 acertos congelam"`
  - veneno: `"%s%% de chance — Veneno: %s%% do dano em %s s"`
  
  (chance de `StatusRules.chance`). Ajustar as asserções de texto em `tests/unit/test_enchant_rules.gd`.

- [ ] **Step 6: Rodar unitários**

Run: o mesmo do Step 3. Expected: todos passam (`test_balance.test_enchant_table` não confere `effects`, deve continuar passando).

- [ ] **Step 7: Commit**

```bash
git add scripts/character/status_rules.gd data/balance/enchant.json scripts/character/enchant_rules.gd tests/unit/test_status_rules.gd tests/unit/test_enchant_rules.gd
git commit -m "Status elementais: regras puras e chance por nível"
```

---

### Task 2: `StatusEffects` no monstro (solo) e remoção da marca tóxica

**Files:**
- Create: `scripts/enemies/status_effects.gd`
- Modify: `scripts/enemies/enemy.gd` (criar o nó, chamar `tick`, `apply_status`, tirar `venom_*`/`apply_venom`, `incoming()` sem veneno)
- Test: `tests/smoke_test.gd` (substituir a checagem da linha ~4059)

**Interfaces:**
- Consumes: `StatusRules` (Task 1).
- Produces:
  - `class_name StatusEffects extends Node`
  - `signal mask_changed(mask: int)`
  - `func apply(el: String, power: float, secs: float, applier: int) -> void` — só no dono
  - `func tick(delta: float) -> void` — só no dono
  - `func mask() -> int`
  - `func set_mask(m: int) -> void` — réplica
  - `func has(el: String) -> bool`
  - `Enemy.status: StatusEffects`
  - `Enemy.apply_status(el: String, power: float, secs: float) -> void` — réplica manda para a rede (Task 4), dono aplica com `applier = last_hitter`

- [ ] **Step 1: Escrever a checagem no smoke** (substitui a da marca tóxica), num monstro de teste solo:

```gdscript
a.apply_status("fogo", 30.0, 3.0)
check(a.status.has("fogo") and a.status.mask() & StatusRules.BITS.fogo != 0, "fogo aplicado entra no bitmask")
var hp0 := a.hp
a.status.tick(1.01)
check(a.hp < hp0, "queimadura tira vida no primeiro tick")
a.status.tick(3.0)
check(not a.status.has("fogo"), "queimadura acaba")
for i in 3:
	a.apply_status("gelo", 0.0, 2.0)
check(a.status.has("congelado") and a.stagger > 0.0, "3 gelos congelam")
for i in 3:
	a.apply_status("gelo", 0.0, 2.0)
check(a.stagger <= 1.0, "em recarga não congela de novo")
```
mais um chefe: 3× gelo → `not boss.status.has("congelado")` e `boss.slow_timer > 0`.

- [ ] **Step 2: Rodar o smoke e ver falhar**

Run: `& "C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path . res://scenes/world.tscn -- --smoketest`
Expected: erro de `apply_status`/`status` não existente.

- [ ] **Step 3: Implementar `StatusEffects`**

Estado: `_fx := {el: {"power", "timer", "tick_t", "applier"}}`, `_ice_stacks`, `_freeze_t`, `_freeze_cd`. Em `apply`:
- fogo/veneno: `renew`; `tick_t = secs / ticks`; dano por tick = `power / ticks`.
- gelo: `enemy.slow_timer = max(slow_timer, secs)`; se já havia gelo ativo `_ice_stacks += 1` senão `= 1`; se `StatusRules.should_freeze(_ice_stacks, freeze_stacks, enemy.is_boss or enemy.elite or enemy.data.get("elite", false), _freeze_cd)` → `enemy.apply_stun(freeze_secs)`, `_freeze_t = freeze_secs`, `_freeze_cd = freeze_cd`, `_ice_stacks = 0`.

Em `tick`: cada tick chama, com `enemy.last_hitter = applier` (só se `Network.is_server()` e o peer ainda está em `Network.players`, senão 0) e restaura depois, `enemy.take_damage(per, enemy.global_position, false, 0.0, 0.0, 0.0, el)`; quando o servidor dá o tick, manda também `_enemy_hit_fx` aos peers como `_hit_enemy` faz (extrair o laço para um helper `Network.server_show_hit(e, amount, mix)`). Emite `mask_changed` só quando o bitmask muda. Um tick nunca rola status.

- [ ] **Step 4: Ligar no `Enemy`**: criar `status` no `_ready` (dono e réplica), chamar `status.tick(delta)` no `_physics_process` só no dono e não morto, `apply_status` como no Interfaces. Remover `venom_amp`, `venom_timer`, `apply_venom` e o fator de veneno em `incoming()`.

- [ ] **Step 5: Rodar o smoke** (rodar de novo se só fireball/spark/arrow falharem: flake conhecido). Expected: as checagens novas passam.

- [ ] **Step 6: Commit**

```bash
git add scripts/enemies/status_effects.gd scripts/enemies/enemy.gd tests/smoke_test.gd
git commit -m "Status elementais no monstro: ticks, lentidão e congelamento no dono"
```

---

### Task 3: Arma encantada aplica status com chance

**Files:**
- Modify: `scripts/player/enchant_hit.gd` (`on_hit`, remover `_burn` e `BURN_TICKS`)
- Modify: `scripts/enemies/enemy.gd` (`show_resisted(el: String)`, ao lado de `_element_immune`)
- Test: `tests/smoke_test.gd`

**Interfaces:**
- Consumes: `StatusRules.chance/enemy_resist/roll`, `Enemy.apply_status` (Task 2).
- Produces: `Enemy.show_resisted(el: String) -> void` — número "Resistiu" na cor `EnchantFX.ELEMENTS[el].color`, respeitando o mesmo `_hint_t`/`HINT_GAP` do "Imune".
- Produces: `EnchantHit.try_status(e: Enemy, dmg: float, fx: Dictionary, r: float) -> String` — devolve o resultado do `roll`, testável com `r` fixo.

- [ ] **Step 1: Checagens no smoke**, com arma de fogo +5 equipada:

```gdscript
check(EnchantHit.try_status(slime, 100.0, fx_fogo5, 0.10) == "applied" and slime.status.has("fogo"), "fogo pega no slime")
check(EnchantHit.try_status(explosivo, 100.0, fx_fogo5, 0.10) == "resisted" and not explosivo.status.has("fogo"), "imune resiste")
check(EnchantHit.try_status(slime2, 100.0, fx_fogo5, 0.99) == "none", "rolagem alta não pega")
```

- [ ] **Step 2: Rodar o smoke e ver falhar.** Run: igual à Task 2. Expected: `try_status` não existe.

- [ ] **Step 3: Implementar.** `on_hit`: para `fx.el` em `StatusRules.STATUS_ELEMENTS` chama `try_status(e, dmg, fx, randf())`. `try_status`: `base = StatusRules.chance(Balance.tables, el, fx_level)` (a ficha de `Game.weapon_enchant().lv`), `resist = StatusRules.enemy_resist(Balance.tables, e.kind, el)`; em `"applied"` → `e.apply_status(el, dmg * fx.value, secs)` (gelo: `power = 0`, `secs = fx.value`); em `"resisted"` → `e.show_resisted(el)`. Raio, sombra e sagrado ficam como estão.

- [ ] **Step 4: Rodar o smoke.** Expected: passa.

- [ ] **Step 5: Commit**

```bash
git add scripts/player/enchant_hit.gd scripts/enemies/enemy.gd tests/smoke_test.gd
git commit -m "Arma encantada: chance de status cortada pela resistência"
```

---

### Task 4: Rede — pedido ao servidor, crédito dos ticks e bitmask no snapshot

**Files:**
- Modify: `scripts/autoload/network.gd` (`SNAP_STRIDE` 11, `_send_enemy_snapshot`, `_enemy_snapshot`, `client_apply_status`/`_apply_status` no lugar de `client_mark_enemy`/`_mark_enemy`, helper `server_show_hit`)
- Modify: `scripts/enemies/enemy.gd` (`apply_snapshot(..., flags: int, status_mask: int)`)
- Test: `tests/net_test.gd` (substituir o bloco da linha ~411)

**Interfaces:**
- Consumes: `StatusEffects.apply/mask/set_mask`, `StatusRules.cap_power/cap_secs/enemy_resist`.
- Produces: `Network.client_apply_status(net_id: int, el: String, power: float, secs: float) -> void`; `Network.server_show_hit(e: Enemy, amount: float, mix: Dictionary) -> void`.

- [ ] **Step 1: Checagens no `net_test`** (no lugar do `client_mark_enemy(vt.net_id, 5.0, 99.0)`):
  - cliente pede `("fogo", 1e9, 99.0)` num alvo vivo → no servidor `vt.status.has("fogo")` e a força guardada ≤ `StatusRules.cap_power(bt, "fogo", 1e9)`, tempo ≤ 3.0;
  - cliente pede `("raio", 10.0, 1.0)` → servidor ignora (`mask() == 0` para esse alvo novo);
  - cliente pede fogo num `slime_explosivo` → servidor ignora;
  - réplica no cliente recebe o bit de fogo pelo snapshot (`vt_replica.status.has("fogo")` em até ~0.5 s);
  - monstro com pouca vida morre por tick → o abate conta para o peer que aplicou (mesmo sinal/contador que o `net_test` já usa para XP/loot de abate).

- [ ] **Step 2: Rodar o `net_test` e ver falhar** (servidor por PID, `--horde-pick=5`, nunca matar todos os Godot; ver o comando de sempre do projeto). Expected: `client_apply_status` não existe.

- [ ] **Step 3: Implementar.** `_apply_status` (any_peer, reliable): mesmas conferências de `_mark_enemy` (sender em `players`, alvo vivo, zona "world", `HitGuard.accepts(0.0, ...)`); recusa elemento fora de `STATUS_ELEMENTS`, `enemy_resist ≥ 1.0` e valores não finitos; aplica `e.status.apply(el, cap_power(...), cap_secs(...), id)`. No snapshot, a 11ª coluna é `e.status.mask()`; `_enemy_snapshot` passa `int(snap[i + 10])` e `apply_snapshot` chama `status.set_mask`. `Enemy.apply_status` numa réplica chama `Network.client_apply_status`.

- [ ] **Step 4: Rodar o `net_test`.** Expected: passa (se o teste da colônia ou da autenticação falhar uma vez, rodar de novo antes de culpar a mudança).

- [ ] **Step 5: Commit**

```bash
git add scripts/autoload/network.gd scripts/enemies/enemy.gd tests/net_test.gd
git commit -m "Status elementais na rede: servidor decide, ticks creditados, bitmask no snapshot"
```

---

### Task 5: `StatusAura` — o efeito no corpo do monstro

**Files:**
- Create: `scripts/vfx/status_aura.gd`
- Modify: `scripts/enemies/enemy.gd` (criar a aura como filha do modelo, ligar em `status.mask_changed`)
- Modify: `tools/element_shot.gd` (argumento `--status=tipo:el,...`)
- Test: `tests/unit/test_status_aura.gd` (só o contador, sem cena) ou checagem no smoke se a aura precisar de árvore

**Interfaces:**
- Consumes: `StatusEffects.mask_changed`, `StatusRules.BITS`, `EnchantFX.ELEMENTS[el].color/spark`, `shaders/aura_rim.gdshader` (mesmo do `BuffAura`).
- Produces: `class_name StatusAura extends Node3D`; `func set_mask(m: int) -> void`; `const MAX_PARTICLE_AURAS := 12`; `static func particle_slots_used() -> int`.

- [ ] **Step 1: Teste do teto de partículas:** 15 auras com `set_mask(BITS.fogo)` → `particle_slots_used() == 12`; `set_mask(0)` em 5 das que têm partícula → `particle_slots_used() == 7`; chamar `set_mask(BITS.fogo)` de novo nas 3 que estavam só com contorno → `== 10` (uma aura sem vaga só tenta de novo no próximo `set_mask` dela).

- [ ] **Step 2: Rodar e ver falhar.**

- [ ] **Step 3: Implementar.** Contorno de luz com `aura_rim.gdshader` na cor do efeito de maior prioridade: `congelado > fogo > veneno > gelo`. Partículas (CPUParticles3D, poucas, pequenas, puffs redondos) só para esse efeito e só se houver vaga:
  - fogo: chamas arredondadas subindo do corpo, laranja;
  - gelo: névoa fria e cristais pequenos, azul-claro;
  - congelado: casca de gelo (contorno forte branco-azulado) sem partícula extra;
  - veneno: bolhas verdes subindo e gotas pingando.
  
  Some com a máscara 0 (libera a vaga). Nada no servidor headless.

- [ ] **Step 4: `--status=` no `element_shot`** (`slime:fogo,slime_veloz:veneno,goblin:gelo,goblin:congelado`) aplicando direto no `status`.

- [ ] **Step 5: Foto na câmera do jogo e conferir**

Run: `& "C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe" --path . --resolution 1280x720 res://tools/element_shot.tscn -- --status=slime:fogo,slime_veloz:veneno,goblin:gelo,goblin_bruto:congelado --out=status_shot.png`
Expected: cada monstro legível com o elemento, sem cobrir o modelo, chamas arredondadas. Mostrar a foto ao usuário antes do PR.

- [ ] **Step 6: Commit**

```bash
git add scripts/vfx/status_aura.gd scripts/enemies/enemy.gd tools/element_shot.gd tests/unit/test_status_aura.gd
git commit -m "Status elementais: aura no corpo do monstro"
```

---

### Task 6: Fechamento

- [ ] **Step 1:** `grep -rn "venom_amp\|apply_venom\|mark_enemy\|enchant_burn\|Marca tóxica" scripts tests data` → nada (fora do changelog).
- [ ] **Step 2:** Rodar unitários + smoke uma vez (suíte inteira só se o usuário pedir; o CI roda no PR).
- [ ] **Step 3:** Abrir PR do branch `efeitos-elementais` para `main`, com a foto da Task 5 e a lista do que mudou para o jogador (veneno virou dano por tick; fogo/gelo/veneno agora têm chance).
