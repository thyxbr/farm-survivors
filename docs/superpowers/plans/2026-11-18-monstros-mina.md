# Monstros da Mina de Cristal — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Mina (nv 20–30) ganha Kobold Lanterneiro, Centopeia de Túnel, Golem de Cristal, Toupeira-Broca e a boss
Mãe-Verme, com os esqueletos restritos ao corredor norte e ao Salão do Cavaleiro.

**Architecture:** Cada monstro é uma entrada em `data/balance/enemies.json`. Os modelos novos são feitos em código em
`tools/blender/monsters.py` → `assets/models/<model>.glb`. A animação e a IA ficam em `scripts/enemies/enemy.gd`.
A lógica nova que dá para isolar (codificar o arremesso no snapshot, as fases de cavar) vai para scripts puros
(`ThrowRules`, `BurrowRules`) com testes unitários. Lembrete: nada de identificadores de autoload (`Game`,
`Balance`…) nesses scripts, senão o runner `-s` não compila. O multiplayer reaproveita o snapshot de 10 floats.
Tipos de ataque e estados novos são **acrescentados no fim** de `ATTACK_KINDS`/`STATES`, e a distância do
arremesso vai nos bits altos de `flags`.

**Tech Stack:** Godot 4.7.2 (GDScript), Blender 5.2 CLI (bpy), runner próprio `tests/unit/run.gd`.

**Spec:** `docs/superpowers/specs/2026-11-18-monstros-mina-design.md`

## Global Constraints

- Trabalhar só no worktree `C:/Games/godot-3d-monstros-mina` (branch `monstros-mina`); nunca no checkout principal.
- Godot: `G="C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe"`. Blender: `B="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"`.
- Modelos só pelo Blender CLI: `ASSETS=<nome> "$B" --background --factory-startup --python tools/blender/build_assets.py`. Nunca pelo MCP.
- Depois de cada build: `grep LOOSE` na saída tem de vir vazio (nenhuma peça solta).
- Estilo das feras: toon liso, `sloft`/`fera_*` (ver o cabeçalho de `monsters.py` e `tools/blender/STYLE.md`). Frente = −Y.
- **Uma rodada de validação por modelo:** antes da próxima task de modelo, mandar ao usuário uma captura dentro do
  jogo (`--geardemo --at=<x>,<z>,<yaw> --shot=<arquivo>`; a Mina fica em x ≈ 800) e esperar o "ok".
- Tipos e estados de rede: só acrescentar no fim de `Network.ATTACK_KINDS` / `Network.STATES` (cliente e servidor
  da mesma versão, mas o fim da lista mantém os índices antigos).
- Sem itens novos: o loot usa ids que já existem em `items.json`.
- Não mexer em `dg_mina.tscn`, nos outros mapas, em `quests.json` nem em `survival_mode.gd`.
- `project.godot` `config/version` sobe de `0.55.0` para `0.56.0` antes do PR.
- Scripts puros testáveis (`ThrowRules`, `BurrowRules`) sem nomes de autoload.

## Review Focus

1. **Réplica no cliente durante o cavar:** o cliente tem de esconder o modelo e mostrar o rastro enquanto o estado é
   `burrow`, e mostrar o aviso de emergir no mesmo ponto que o servidor. Coberto pelo teste
   `test_burrow_state_index_stable` (Task 4) e pela checagem manual com 2 clientes na Task 4.
2. **Acertar monstro debaixo da terra:** magias em área, flechas e o Turbilhão não podem causar dano nem puxar uma
   Toupeira ou a Mãe-Verme enterrada. Coberto por `test_burrowed_is_untargetable` (Task 4), que chama `take_damage`
   no estado `burrow`.
3. **Arremesso com o alvo fora de alcance ou atrás de parede:** a dinamite cai no ponto limitado por `throw_range`
   e nunca além. Coberto por `test_clamps_to_range` (Task 1).
4. **Estouro do Golem que mata o jogador depois que o Golem sumiu:** o dano é aplicado pelo servidor uma única vez
   (sem duplicar na réplica). Coberto pela checagem do smoke na Task 3 (log `death_blast` uma vez por morte).
5. **Boss sem ninguém por perto:** a Mãe-Verme volta à vida cheia e não sai do fosso. Coberto por
   `test_worm_resets_when_alone` e `test_emerge_point_inside_leash` (Task 5).

---

### Task 0: Preparar o worktree

**Files:** nenhum (só ambiente)

- [ ] **Step 1: Importar o projeto no worktree**

Run: `cd /c/Games/godot-3d-monstros-mina && timeout 600 "$G" --headless --path . --import > "$TEMP/import.log" 2>&1; echo exit=$?`
Expected: `exit=0`

- [ ] **Step 2: Rodar os unitários como linha de base**

Run: `timeout 300 "$G" --headless --path . -s tests/unit/run.gd > "$TEMP/unit.log" 2>&1; echo exit=$?; tail -5 "$TEMP/unit.log"`
Expected: `exit=0`, sem falhas. Se algo falhar, anotar como falha anterior (não desta branch).

---

### Task 1: Kobold Lanterneiro + arremesso de dinamite

**Files:**
- Modify: `tools/blender/monsters.py` (`build_goblin()`: novas peças `opt("MinerHelmet")`, `opt("Pickaxe")`, `opt("DynamiteBelt")`)
- Create: `scripts/enemies/throw_rules.gd` (`class_name ThrowRules`)
- Modify: `scripts/enemies/enemy.gd` (`_begin_attack`, `_attack_duration`, `_hit_time`, `_update_attack`, `apply_snapshot`, `_puppet_process`)
- Modify: `scripts/autoload/network.gd` (`ATTACK_KINDS` + `"throw"`; `flags` em `_send_enemy_snapshot`)
- Modify: `data/balance/enemies.json` (entrada `kobold`)
- Test: `tests/unit/test_throw_rules.gd`; `tests/unit/test_enemy_gear.gd` (acrescentar `"kobold"` ao laço da linha ~80)

**Interfaces:**
- Produces:
  - `ThrowRules.target(from: Vector3, to: Vector3, max_range: float) -> Vector3`: ponto no chão (y = from.y), na direção de `to`, a no máximo `max_range`.
  - `ThrowRules.pack_flags(flags: int, dist: float) -> int` / `ThrowRules.unpack_dist(flags: int) -> float`: distância em passos de 0,25 m nos bits 2..9 (máx. 63,75 m); bits 0–1 (lento, enfurecido) intactos.
  - `ThrowRules.arc(from: Vector3, to: Vector3, t: float, height: float) -> Vector3`: posição da dinamite no voo (t 0..1), parábola com pico `height`.
  - Enemy: `var throw_point: Vector3` (servidor e réplica), `attack_kind == "throw"`.
  - JSON: chaves novas `"throw_every"` (int), `"throw_range"` (m) e `"blast"` (raio, já existente) num monstro **sem** `"ai": "bomber"`.

- [ ] **Step 1: Escrever os testes que falham** em `tests/unit/test_throw_rules.gd`

```gdscript
extends RefCounted

func test_target_inside_range() -> void:
	T.eq(ThrowRules.target(Vector3.ZERO, Vector3(0, 1, -5), 9.0), Vector3(0, 0, -5), "alvo perto: o próprio ponto, no chão de quem joga")

func test_clamps_to_range() -> void:
	T.eq(ThrowRules.target(Vector3.ZERO, Vector3(20, 0, 0), 9.0), Vector3(9, 0, 0), "longe: corta no alcance")

func test_flags_roundtrip_keeps_low_bits() -> void:
	var f := ThrowRules.pack_flags(3, 6.4)
	T.eq(f & 3, 3, "bits de lento/enfurecido ficam")
	T.ok(absf(ThrowRules.unpack_dist(f) - 6.5) < 0.001 or absf(ThrowRules.unpack_dist(f) - 6.25) < 0.001, "distância em passos de 0,25")

func test_flags_dist_caps() -> void:
	T.eq(ThrowRules.unpack_dist(ThrowRules.pack_flags(0, 999.0)), 63.75, "teto de 8 bits")

func test_arc_ends_and_peaks() -> void:
	var a := Vector3.ZERO
	var b := Vector3(0, 0, -8)
	T.eq(ThrowRules.arc(a, b, 0.0, 3.0), a, "sai da mão")
	T.eq(ThrowRules.arc(a, b, 1.0, 3.0), b, "cai no alvo")
	T.ok(absf(ThrowRules.arc(a, b, 0.5, 3.0).y - 3.0) < 0.001, "pico no meio")
```

E em `test_enemy_gear.gd`, acrescentar `"kobold"` à lista de tipos do laço que confere se o `gear` existe no `.glb`.

- [ ] **Step 2: Rodar e ver falhar**

Run: `timeout 300 "$G" --headless --path . -s tests/unit/run.gd > "$TEMP/unit.log" 2>&1; grep -E "throw_rules|kobold|FAIL" "$TEMP/unit.log" | head`
Expected: falha (`ThrowRules` não existe / `kobold` sem entrada).

- [ ] **Step 3: Implementar `ThrowRules`** em `scripts/enemies/throw_rules.gd` com as assinaturas acima (static funcs, `extends RefCounted`).

- [ ] **Step 4: Peças do Kobold no goblin.** Em `build_goblin()`, três `opt(...)`:
  - `MinerHelmet`: casco de couro na cabeça com uma vela/lampião aceso na frente (material com `emit`), preso ao `Head`.
  - `Pickaxe`: picareta pequena na mão direita (dentro de `ElbowR`, como o `Club`).
  - `DynamiteBelt`: cinto com 4–5 bananas de dinamite (cilindros vermelhos com pavio), preso ao `Body`.

  Build: `cd /c/Games/godot-3d-monstros-mina && ASSETS=goblin "$B" --background --factory-startup --python tools/blender/build_assets.py 2>&1 | tee "$TEMP/b.log" | grep -E "LOOSE|Error"`
  Expected: nada impresso.

- [ ] **Step 5: Entrada `kobold` em `enemies.json`.** `model: "goblin"`, `gear: ["MinerHelmet", "Pickaxe", "DynamiteBelt"]`, `tint` terroso (marrom-acinzentado), `scale` ≈ 0.85, `throw_every: 3`, `throw_range: 9.0`, `blast: 2.8`, `ref_level: 2`. Números e loot calibrados pelo construtor (ex.: `goblin_ear`, `ember_core`).

- [ ] **Step 6: Ataque `"throw"` no `enemy.gd`.**
  - `_begin_attack`: no bloco padrão (antes do teste de `slam_every`), se `data.has("throw_every") and attack_count % int(data.throw_every) == 0` e o alvo estiver a mais de `data.reach`: `attack_kind = "throw"`, `throw_point = ThrowRules.target(global_position, _tgt.global_position, data.throw_range)`, vira o modelo para o ponto e chama `FX.telegraph(throw_point, data.blast, _hit_time())`.
  - `_hit_time` "throw" = 1.0; `_attack_duration` "throw" = 1.3.
  - `_update_attack`: no hit, `_dynamite_blast(false)`: `FXToon.blast(throw_point, data.blast)`, som `"explode"` e dano nos alvos a até `data.blast` de `throw_point`. **Não** chama `_die()`.
  - Visual do voo: um nó simples (cilindro vermelho) segue `ThrowRules.arc(mão, throw_point, t, 2.5)` entre o lançamento (t ≈ 0.35) e o hit.
  - `Network.ATTACK_KINDS`: acrescentar `"throw"` no fim. Em `_send_enemy_snapshot`, `flags = ThrowRules.pack_flags(flags, e.global_position.distance_to(e.throw_point))` quando `e.attack_kind == "throw"`.
  - `apply_snapshot`: quando entra um `"throw"`, `throw_point = global_position + model_forward() * ThrowRules.unpack_dist(flags)` (com `y` do monstro) e telegraph nesse ponto pelo tempo que falta. `_puppet_process`: no hit, `_dynamite_blast(true)`.

- [ ] **Step 7: Rodar os testes**

Run: `timeout 300 "$G" --headless --path . -s tests/unit/run.gd > "$TEMP/unit.log" 2>&1; echo exit=$?`
Expected: `exit=0`.

- [ ] **Step 8: Captura para o usuário.** Colocar temporariamente um spawn `kobold` (count 3) perto da entrada da Mina e capturar com `--geardemo --at=800,30,180 --shot=<scratchpad>/kobold.png`. Mostrar ao lado de uma captura do goblin. **Esperar aprovação**, ajustar se pedido. (O spawn temporário sai; os spawns reais são da Task 6.)

- [ ] **Step 9: Commit**

```bash
git add tools/blender/monsters.py assets/models/goblin.glb scripts/enemies/throw_rules.gd scripts/enemies/enemy.gd scripts/autoload/network.gd data/balance/enemies.json tests/unit/test_throw_rules.gd tests/unit/test_enemy_gear.gd
git commit -m "Kobold Lanterneiro: variante do goblin que arremessa dinamite"
```

---

### Task 2: Centopeia de Túnel

**Files:**
- Modify: `tools/blender/monsters.py` (novo `build_centipede()`), `tools/blender/build_assets.py` (`BUILDERS["centipede"]`)
- Create: `assets/models/centipede.glb`
- Modify: `scripts/enemies/enemy_model.gd` (`MODELS["centipede"]`), `scripts/enemies/enemy.gd` (onde houver `data.model == "spider"` para peças, animação e som do bote, aceitar `"centipede"` também)
- Modify: `data/balance/enemies.json` (entrada `centopeia`)
- Create: `tests/unit/test_monster_pivots.gd`

**Interfaces:**
- Produces: `test_monster_pivots.gd` com `const REQUIRED := { "<model>": [pivôs] }`. As Tasks 3–5 acrescentam linhas nele.
- Pivôs do `centipede.glb`: exatamente os da tecelã: `Body`, `Abdomen`, `Head`, `Leg0L`..`Leg3L`, `Leg0R`..`Leg3R`.

- [ ] **Step 1: Teste que falha** em `tests/unit/test_monster_pivots.gd`

```gdscript
extends RefCounted
## Cada modelo de monstro tem os pivôs que o enemy.gd anima.

const SPIDER := ["Body", "Abdomen", "Head", "Leg0L", "Leg1L", "Leg2L", "Leg3L", "Leg0R", "Leg1R", "Leg2R", "Leg3R"]
const REQUIRED := {
	"spider": SPIDER,
	"centipede": SPIDER,
}

func test_models_have_pivots() -> void:
	for m in REQUIRED:
		var path := "res://assets/models/%s.glb" % m
		T.ok(ResourceLoader.exists(path), "%s existe" % path)
		if not ResourceLoader.exists(path):
			continue
		var root: Node = (load(path) as PackedScene).instantiate()
		var missing: Array = []
		for p in REQUIRED[m]:
			if root.find_child(p, true, false) == null:
				missing.append(p)
		T.eq(missing, [], "%s: pivôs" % m)
		root.free()
```

- [ ] **Step 2: Rodar e ver falhar** (`centipede.glb` não existe).

- [ ] **Step 3: `build_centipede()`.** Corpo longo de 7–9 segmentos em `sloft` (rente ao chão, ~2,2 m), quitina marrom-avermelhada com faixas escuras, cabeça com antenas e duas mandíbulas em gancho (`fera_tip`). Um par de patinhas por segmento. Cada patinha fica como filha do pivô `LegNx` mais próximo pela posição ao longo do corpo (os 4 pares de pivôs dividem o corpo em 4 trechos). Segmentos de trás dentro de `Abdomen`, cabeça e mandíbulas dentro de `Head`, tudo dentro de `Body`. Export `"centipede"`.

  Build: `ASSETS=centipede "$B" --background --factory-startup --python tools/blender/build_assets.py 2>&1 | grep -E "LOOSE|Error"` → nada.

- [ ] **Step 4: Ligar no jogo.** `MODELS["centipede"]` no `enemy_model.gd`. No `enemy.gd`, trocar `data.model == "spider"` por `data.model in ["spider", "centipede"]` em `_ready` (peças), `_animate` e no som do bote. Entrada `centopeia`: `model: "centipede"`, `ai: "pack"`, `speed` alta (~5), vida baixa, `chill: 1.5` (lentidão do veneno), cor verde-oliva, `ref_level: 2`, loot existente (ex.: `shadow_fang`).

- [ ] **Step 5: Rodar os testes** → `exit=0`.

- [ ] **Step 6: Captura** parada e andando (`--at=800,25,180`). **Esperar aprovação.**

- [ ] **Step 7: Commit** `"Centopeia de Túnel: malha nova com os pivôs da tecelã"`.

---

### Task 3: Golem de Cristal + estouro na morte

**Files:**
- Modify: `tools/blender/monsters.py` (`build_golem()`), `tools/blender/build_assets.py` (`BUILDERS["golem"]`)
- Create: `assets/models/golem.glb`
- Modify: `scripts/enemies/enemy_model.gd`, `scripts/enemies/enemy.gd` (`_animate_golem`, `_die`, `die_visual`)
- Modify: `data/balance/enemies.json` (`golem_cristal`)
- Modify: `tests/unit/test_monster_pivots.gd` (linha `"golem"`)

**Interfaces:**
- Pivôs do `golem.glb`: `LegL`, `LegR`, `Body`, `Head`, `ArmL`, `ArmR`.
- JSON: `"death_blast": <raio>`, `"death_delay": <s>`.
- Enemy: `func _death_blast(visual: bool) -> void`.

- [ ] **Step 1: Teste que falha:** `"golem": ["LegL", "LegR", "Body", "Head", "ArmL", "ArmR"]` em `REQUIRED`. Rodar → falha.

- [ ] **Step 2: `build_golem()`.** Corpo de rocha escura (~2,4 m), tronco largo, braços enormes até quase o chão, pernas curtas e grossas. Aglomerados de cristal azul-ciano com `emit` saindo dos ombros e das costas, e um "rosto" de cristal brilhante. Cada cristal nasce da superfície da rocha (sem flutuar). Build + `grep LOOSE` vazio.

- [ ] **Step 3: Ligar no jogo.** `MODELS["golem"]`. `_animate_golem(hspeed, k)`: passada pesada (corpo balança de lado), braços pendulares; `slam` = ergue os dois braços e bate no chão no `_hit_time`. Entrada `golem_cristal`: `model: "golem"`, `slam_every: 2`, `speed` ~2.2, vida alta, `death_blast: 3.0`, `death_delay: 0.8`, cor ciano, loot `arcane_crystal`.

- [ ] **Step 4: Estouro.** Em `_die()` no servidor e no solo, se `data.has("death_blast")`, guardar a posição, chamar `FX.telegraph(pos, r, delay)` e, depois de `death_delay` (com `get_tree().create_timer`; não depende do nó do Golem, que some no shatter), dar dano aos alvos dentro de `r` e `FXToon.blast(pos, r)`. Escrever `print("death_blast ", kind)` uma vez por morte, para o smoke. Em `die_visual()` da réplica (`puppet`), só telegraph e blast visual, sem dano.

- [ ] **Step 5: Testes** → `exit=0`. Smoke rápido: `timeout 600 "$G" --headless --path . res://scenes/world.tscn -- --smoketest > "$TEMP/smoke.log" 2>&1; echo exit=$?` → `exit=0` (rodar de novo uma vez se falhar só no projétil, flake conhecido).

- [ ] **Step 6: Captura** do Golem e do estouro (`--at=800,-5,180`). **Esperar aprovação.**

- [ ] **Step 7: Commit** `"Golem de Cristal: modelo novo e estouro de estilhaços ao morrer"`.

---

### Task 4: Toupeira-Broca + mecânica de cavar e emergir

**Files:**
- Create: `scripts/enemies/burrow_rules.gd` (`class_name BurrowRules`)
- Modify: `tools/blender/monsters.py` (`build_mole()`), `build_assets.py` (`BUILDERS["mole"]`)
- Create: `assets/models/mole.glb`
- Modify: `scripts/enemies/enemy_model.gd`, `scripts/enemies/enemy.gd`, `scripts/autoload/network.gd` (`STATES` + `"burrow"`, `ATTACK_KINDS` + `"emerge"`)
- Modify: `data/balance/enemies.json` (`toupeira`)
- Test: `tests/unit/test_burrow_rules.gd`, `tests/unit/test_monster_pivots.gd` (linha `"mole"`)

**Interfaces:**
- Produces (usado pela Task 5):
  - `BurrowRules.should_dig(dist: float, surface_t: float, cfg: Dictionary) -> bool`: verdadeiro com `cfg.dig_min <= dist <= cfg.dig_max` e `surface_t >= cfg.surface_secs`.
  - `BurrowRules.dig_step(pos: Vector3, target: Vector3, speed: float, delta: float) -> Vector3`: anda por baixo da terra em linha reta, sem passar do alvo.
  - `BurrowRules.should_emerge(pos: Vector3, target: Vector3, dig_t: float, cfg: Dictionary) -> bool`: verdadeiro se chegou (≤ 0,6 m no plano) ou `dig_t >= cfg.dig_max_secs`.
  - `BurrowRules.clamp_to_leash(p: Vector3, home: Vector3, half_size: Vector2) -> Vector3`: limita ao retângulo (usado pela Task 5).
  - Enemy: estado `"burrow"`, `var dig_t`, `var surface_t`, ataque `"emerge"` (telegraph na própria posição, raio `data.emerge_radius`, `_hit_time` 1.0, duração 1.6).
  - `cfg` vem do JSON: `dig_min`, `dig_max`, `surface_secs`, `dig_max_secs`, `dig_speed`, `emerge_radius`.

- [ ] **Step 1: Testes que falham** em `tests/unit/test_burrow_rules.gd`

```gdscript
extends RefCounted

const CFG := {"dig_min": 4.0, "dig_max": 14.0, "surface_secs": 3.0, "dig_max_secs": 4.0}

func test_digs_only_mid_range_after_surface_time() -> void:
	T.ok(BurrowRules.should_dig(8.0, 3.5, CFG), "média distância depois da janela")
	T.ok(not BurrowRules.should_dig(2.0, 5.0, CFG), "colado: luta na superfície")
	T.ok(not BurrowRules.should_dig(8.0, 1.0, CFG), "ainda na janela vulnerável")

func test_dig_step_does_not_overshoot() -> void:
	T.eq(BurrowRules.dig_step(Vector3.ZERO, Vector3(1, 0, 0), 6.0, 1.0), Vector3(1, 0, 0), "para no alvo")

func test_emerges_on_arrival_or_timeout() -> void:
	T.ok(BurrowRules.should_emerge(Vector3(0.3, 0, 0), Vector3.ZERO, 0.5, CFG), "chegou")
	T.ok(BurrowRules.should_emerge(Vector3(9, 0, 0), Vector3.ZERO, 4.0, CFG), "tempo esgotado")
	T.ok(not BurrowRules.should_emerge(Vector3(9, 0, 0), Vector3.ZERO, 1.0, CFG), "ainda indo")

func test_clamp_to_leash() -> void:
	T.eq(BurrowRules.clamp_to_leash(Vector3(30, 0, 0), Vector3.ZERO, Vector2(20, 15)), Vector3(20, 0, 0), "corta na borda")

func test_burrow_state_index_stable() -> void:
	# os índices antigos de rede não mudam; os novos ficam no fim
	var states := ["idle", "wander", "chase", "return", "attack", "dead", "burrow"]
	T.eq(load("res://scripts/autoload/network.gd").STATES, states, "estado burrow no fim")
```

E `test_burrowed_is_untargetable` no mesmo arquivo: instancia `Enemy` com `kind = "toupeira"` sem árvore de cena, se o runner permitir. Senão, transformar a regra em `BurrowRules.takes_damage(state: String) -> bool` e testar `takes_damage("burrow") == false`, `takes_damage("chase") == true`. Usar a segunda forma se a primeira esbarrar em autoload.

`"mole": ["LegL", "LegR", "Body", "Head", "ArmL", "ArmR"]` em `test_monster_pivots.gd`.

- [ ] **Step 2: Rodar e ver falhar.**

- [ ] **Step 3: Implementar `BurrowRules`** (static, puro).

- [ ] **Step 4: `build_mole()`.** Toupeira robusta (~1,3 m), pelo cinza-escuro, garras de pá enormes nas patas da frente (`ArmL`/`ArmR`), focinho de broca de metal enferrujado em espiral (peça `Drill` dentro de `Head`, que gira) e óculos de mineiro na testa. Build + `LOOSE` vazio.

- [ ] **Step 5: IA `"burrow"` no `enemy.gd`.**
  - Em `chase`, se `BurrowRules.should_dig(...)`: `_set_state("burrow")`, `dig_t = 0`, `collision_layer = 0`, esconde `model`, liga o rastro de terra (partículas simples ou um monte de terra que segue o chão).
  - Em `burrow`: `global_position = BurrowRules.dig_step(...)` até `should_emerge`; aí `_set_state("attack")`, `attack_kind = "emerge"`, `FX.telegraph(global_position, data.emerge_radius, 1.0)`.
  - No hit do `emerge`: mostra o modelo, restaura a colisão, dano em área `emerge_radius`, `FXToon.slam`, `surface_t = 0`.
  - `take_damage` e `apply_stun` retornam cedo em `burrow` (`BurrowRules.takes_damage`).
  - Rede: `STATES` + `"burrow"`, `ATTACK_KINDS` + `"emerge"`. Em `_set_state` na réplica: `burrow` esconde o modelo e liga o rastro; `apply_snapshot` com `emerge` faz o telegraph na posição do snapshot.
  - Entrada `toupeira`: `model: "mole"`, `ai: "burrow"`, `dig_min: 4`, `dig_max: 14`, `surface_secs: 3`, `dig_max_secs: 4`, `dig_speed: 7`, `emerge_radius: 2.6`, loot existente (ex.: `iron_ore` ou o que existir de minério).
  - `_animate_mole`: anda curvada; `swing` = patada com as garras; a `Drill` gira sempre.

- [ ] **Step 6: Testes** → `exit=0`.

- [ ] **Step 7: Multiplayer manual.** Servidor + 2 clientes (comandos da skill `smoke-check`, matando o servidor pelo PID `kill $S`, nunca todos os Godot). Ir à Mina com os dois e conferir nos dois: o modelo some, o rastro aparece e o aviso fica no mesmo lugar. Anotar o resultado no commit.

- [ ] **Step 8: Captura** (Toupeira na superfície + aviso de emergir, `--at=845,-40,180`). **Esperar aprovação.**

- [ ] **Step 9: Commit** `"Toupeira-Broca e a mecânica de cavar e emergir"`.

---

### Task 5: Boss Mãe-Verme das Profundezas

**Files:**
- Modify: `tools/blender/monsters.py` (`build_worm()`), `build_assets.py` (`BUILDERS["worm"]`)
- Create: `assets/models/worm.glb`
- Modify: `scripts/enemies/enemy_model.gd`, `scripts/enemies/enemy.gd` (IA `"worm"`, `_animate_worm`)
- Modify: `scripts/enemies/burrow_rules.gd` (`worm_should_reset`)
- Modify: `data/balance/enemies.json` (`mae_verme`)
- Test: `tests/unit/test_burrow_rules.gd`, `tests/unit/test_monster_pivots.gd` (linha `"worm"`)

**Interfaces:**
- Consumes: tudo de `BurrowRules` da Task 4; estado `burrow` e ataque `emerge`.
- Produces: `BurrowRules.worm_should_reset(players_in_leash: int, hp: float, max_hp: float) -> bool` (verdadeiro com 0 jogadores e `hp < max_hp`).
- JSON: `ai: "worm"`, `boss: true`, `leash: [20, 15]` (meio-tamanho do retângulo do fosso), `surface_attacks: 3`, `shot: "acid"`, `summon: "centopeia"`, mais as chaves de cavar da Task 4.
- Pivôs do `worm.glb`: `Body`, `Neck`, `Head`, `Jaw`.

- [ ] **Step 1: Testes que falham**

```gdscript
func test_worm_resets_when_alone() -> void:
	T.ok(BurrowRules.worm_should_reset(0, 500.0, 3000.0), "sozinha e ferida: volta")
	T.ok(not BurrowRules.worm_should_reset(1, 500.0, 3000.0), "com jogador: luta")
	T.ok(not BurrowRules.worm_should_reset(0, 3000.0, 3000.0), "cheia: nada a fazer")

func test_emerge_point_inside_leash() -> void:
	var home := Vector3(-45, 0, -40)
	var p := BurrowRules.clamp_to_leash(Vector3(10, 0, -40), home, Vector2(20, 15))
	T.ok(absf(p.x - home.x) <= 20.0 and absf(p.z - home.z) <= 15.0, "emerge dentro do fosso")
```

Mais `"worm": ["Body", "Neck", "Head", "Jaw"]` no `REQUIRED`. Rodar → falha.

- [ ] **Step 2: Implementar `worm_should_reset`.**

- [ ] **Step 3: `build_worm()`.** Só a parte que sai do chão (~5 m de altura, 1,4 m de diâmetro): segmentos de couraça de pedra com cristais incrustados, base larga com um anel de terra revirada (a junção com o chão, para não parecer cortado), boca circular com 3–4 anéis de dentes e lábios que abrem em pétalas (`Jaw`). `Neck` no meio do corpo, `Head` no topo. Build + `LOOSE` vazio.

- [ ] **Step 4: IA `"worm"`.**
  - `home` = ponto de spawn. Fica em `burrow` entre aparições, com o alvo limitado por `BurrowRules.clamp_to_leash(alvo, home, leash)`.
  - Emerge (`emerge`, reaproveitado) sob o alvo limitado. Na superfície, alterna `slam` (mordida em área à frente) e `shoot` com `shot: "acid"` (projétil verde: no `_shoot`, `"acid"` usa a cor verde e o mesmo caminho do `bolt`). Depois de `surface_attacks` ataques, volta a cavar.
  - Não anda na superfície (velocidade 0). Debaixo da terra, mergulhos curtos (`dig_max_secs` ≈ 2.5).
  - A cada ~1 s em `burrow`/`idle`, conta jogadores dentro do retângulo; se `worm_should_reset`, `hp = max_hp`, `enraged = false`, `summoned = false`, fica enterrada.
  - O `summon` e o `enraged` em 50% já vêm do caminho de chefe (`is_boss`).
  - A barra de chefe continua visível em `burrow`.
  - Entrada `mae_verme`: `model: "worm"`, `scale` ~1, vida de chefe da faixa 28–30 (comparar com o Rei Goblin e o Lich via `balance-check`), loot de chefe com itens e pergaminhos existentes da faixa.

- [ ] **Step 5: Testes** → `exit=0`.

- [ ] **Step 6: Captura** da boss emergindo e da boca aberta (`--at=755,-40,180`). **Esperar aprovação.**

- [ ] **Step 7: Commit** `"Mãe-Verme das Profundezas: boss do fosso da Mina"`.

---

### Task 6: Spawns da Mina, região, balanceamento e PR

**Files:**
- Modify: `scenes/maps/mina.tscn` (nós sob `Monstros`)
- Modify: `data/balance/regions.json` (`fosso_brutos.name` → `"Fosso da Mãe-Verme"`)
- Modify: `tests/smoke_test.gd` (checagem da Mina, se o smoke carregar a Mina; senão, um teste unitário que lê o `.tscn`)
- Modify: `project.godot` (`config/version="0.56.0"`)
- Possível: `tests/unit/fixtures/balance_snapshot.bin` (regenerar como o próprio teste indica)

**Interfaces:**
- Coordenadas locais do mapa: Galeria de Entrada z ≈ 20; Veio z ≈ −10; corredor norte z −20 a −35; Fosso leste x +45 z −40; Fosso oeste x −45 z −40; Salão z −45.

- [ ] **Step 1: Teste da distribuição.** `tests/unit/test_mina_spawns.gd` lê `res://scenes/maps/mina.tscn` (instancia o `PackedScene`, percorre os `EnemySpawn` em `Monstros`) e confere:
  - Cada um de `kobold`, `centopeia`, `golem_cristal`, `toupeira` tem ≥ 2 pontos.
  - Existe exatamente 1 `mae_verme`, com x < 0 e z perto de −40.
  - Os esqueletos (`esqueleto*`) só existem com z ≤ −18.
  - Soma de `count` dos `esqueleto`/`esqueleto_arqueiro`/`esqueleto_mago` no corredor norte ≥ 8.
  - `goblin_bruto` só no bando perto de (x +30, z 0).

  Rodar → falha.

- [ ] **Step 2: Editar `mina.tscn`** conforme a tabela da spec. Tirar os bandos de esqueleto e de bruto da Galeria de Entrada e dos Fossos. Pôr bandos de `kobold` (count 3–4) e `centopeia` na Entrada, `golem_cristal` e alguns `kobold` no Veio, `toupeira` nos dois Fossos, `mae_verme` (respawn 300) no Fosso oeste, 1 bando de `goblin_bruto` em (30, 0). Os `level`/`level_max` seguem a região (0 = faixa da região).

- [ ] **Step 3: Nome da região** em `regions.json`.

- [ ] **Step 4: Testes** → `exit=0`. Regenerar o snapshot de balanceamento se o teste dele pedir.

- [ ] **Step 5: Balanceamento.** Rodar a skill `balance-check` com foco nos 5 tipos novos contra a faixa 20–30, ajustar números e repetir até não haver outlier.

- [ ] **Step 6: Versão** `0.56.0` no `project.godot`.

- [ ] **Step 7: Bateria completa.** Rodar a skill `smoke-check` (import, unitários, smoke, vila, multiplayer). Todos PASSOU; flakes conhecidos rodam de novo uma vez.

- [ ] **Step 8: Captura final** do mapa da Mina com os bandos (uma por região). Mostrar ao usuário.

- [ ] **Step 9: Commit, push e PR** (só depois do "ok" do usuário). Título `"Monstros da Mina de Cristal"`; corpo com a lista dos 5 monstros, a divisão do mapa e o resultado do smoke-check; terminar com a linha de atribuição. Depois do merge, apagar a branch local e remota.
