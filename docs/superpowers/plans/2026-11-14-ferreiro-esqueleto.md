# Ferreiro com esqueleto — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Um ferreiro ("Doran, o Ferreiro") na vila, primeiro personagem com esqueleto do jogo, martelando numa bigorna, virando para o jogador e conversando, com animações provisórias feitas no script e depois trocadas pelas do Mixamo.

**Architecture:** `tools/blender/characters.py` gera a malha low-poly **e** uma armature com nomes de ossos do Mixamo, em pose T, com clipes provisórios por keyframes; o GLB é importado no Godot com `BoneMap` + `SkeletonProfileHumanoid`, o que renomeia os ossos para os nomes do perfil. As animações do Mixamo (FBX) são importadas com o mesmo perfil e salvas como `AnimationLibrary`, então qualquer clipe toca no ferreiro. `scripts/world/blacksmith.gd` estende `npc.gd` e controla estados por `AnimationPlayer.play(clip, blend)`.

**Tech Stack:** Godot 4.7.2 (GDScript), Blender 5.2 CLI (bpy/bmesh), glTF/GLB, FBX do Mixamo.

**Spec:** `docs/superpowers/specs/2026-11-14-ferreiro-esqueleto-design.md`

## Global Constraints

- Trabalhar na worktree `C:/Games/godot-3d-ferreiro`, branch `ferreiro`. Rodar `--import` nela antes de qualquer teste.
- Godot: `C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe`. Abaixo, `GODOT` = esse caminho.
- Blender (CLI, nunca pelo MCP): `ASSETS="<lista>" "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python tools/blender/build_assets.py`
- Frente do personagem = **-Y no Blender** (+Z no Godot).
- Ossos com nomes do Mixamo, prefixo `mixamorig:`, pose T.
- Nomes de clipe (contrato entre tarefas): `work_hammer` (loop), `work_pause`, `idle` (loop), `talk` (loop).
- NPC: `npc_id = "blacksmith"`, nome exibido `"Doran, o Ferreiro"`.
- Animação do ferreiro precisa rodar com a árvore pausada (diálogo no solo pausa; online só trava input).
- Headless (`DisplayServer.get_name() == "headless"`): sem animação, faíscas e som.
- FBX do Mixamo são commitados em `assets/animations/mixamo/` (decisão do usuário).
- Ao final, `config/version` no `project.godot` sobe de `0.7.6` para `0.7.7` (o CI exige versão nova quando o código do jogo muda).
- Mensagens de commit em português, no estilo do histórico (`Ferreiro: ...`).

## Review Focus

1. **Fechar o diálogo no meio de um golpe**: o ferreiro deve voltar a `work_hammer` e se virar de volta para a bigorna, sem ficar travado de frente para o lugar onde o jogador estava. Teste na Tarefa 4 (`ferreiro volta a trabalhar após o diálogo`).
2. **Jogador sai de perto sem falar**: depois de virar para o jogador, o ferreiro volta a martelar quando ele se afasta além de 7 m. Teste na Tarefa 4.
3. **Faísca/som com o jogador longe**: o golpe não deve tocar som além de `Sfx.FAR_DIST` (o `play_at` já descarta; o teste garante que o ferreiro usa `play_at`, não `play`). Teste na Tarefa 4.
4. **Contagem de interagíveis no smoke test**: o teste existente espera exatamente 2 NPCs; precisa passar a esperar 3, senão o CI quebra. Tarefa 4.
5. **Clipes do Mixamo ausentes** (antes do download, ou se o `.res` não existir): o ferreiro usa os clipes provisórios sem erro no console. Teste na Tarefa 4 (sem o `.res`) e na Tarefa 6 (com ele).

---

### Task 1: Modelo e esqueleto do ferreiro (Blender → GLB → Godot com perfil humanoide)

**Files:**
- Modify: `tools/blender/build_assets.py` (função `export`: `extra` passa a sobrescrever os padrões, ex. `export_animations=True`; registrar `"blacksmith": build_blacksmith` em `BUILDERS`)
- Modify: `tools/blender/characters.py` (nova `build_blacksmith()` no fim, depois do goblin)
- Create: `assets/models/blacksmith.glb` (gerado) e `assets/models/blacksmith.glb.import` (com BoneMap)
- Create: `tests/blacksmith_asset_test.gd`
- Modify: `.github/workflows/deploy.yml` (passo que roda o teste do asset, ao lado do smoke test)

**Interfaces:**
- Produces: `res://assets/models/blacksmith.glb` contendo um `Skeleton3D` com ossos nos nomes do **perfil humanoide do Godot** (`Hips`, `Spine`, `Chest`, `UpperChest`, `Neck`, `Head`, `LeftShoulder`, `LeftUpperArm`, `LeftLowerArm`, `LeftHand`, idem `Right*`, `LeftUpperLeg`, `LeftLowerLeg`, `LeftFoot`, `LeftToes`, idem `Right*`), um `AnimationPlayer` com os clipes `work_hammer`, `work_pause`, `idle`, `talk`, e o martelo como malha separada chamada `Hammer` (não ponderada; a Tarefa 4 a prende à mão).
- Produces: `build_blacksmith()` em `characters.py`.

- [ ] **Step 1: Escrever o teste do asset**

`tests/blacksmith_asset_test.gd` (`extends SceneTree`, roda em `_initialize`, imprime `PASS/FAIL` como o smoke test, `quit(1)` se houver falha):

```gdscript
var m: Node = load("res://assets/models/blacksmith.glb").instantiate()
var sks := m.find_children("*", "Skeleton3D")
check(sks.size() == 1, "ferreiro tem um Skeleton3D")
var sk := sks[0] as Skeleton3D
for b in ["Hips", "Spine", "Chest", "Neck", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand",
		"RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
		"RightUpperLeg", "RightLowerLeg", "RightFoot"]:
	check(sk.find_bone(b) >= 0, "osso do perfil humanoide: " + b)
var ap := m.find_children("*", "AnimationPlayer")[0] as AnimationPlayer
for c in ["work_hammer", "work_pause", "idle", "talk"]:
	check(ap.has_animation(c), "clipe provisório: " + c)
check(ap.get_animation("work_hammer").loop_mode == Animation.LOOP_LINEAR, "martelar está em loop")
check(m.find_child("Hammer", true, false) != null, "martelo é malha separada")
var mi := m.find_children("*", "MeshInstance3D")
check(mi.any(func(x): return x.skin != null), "malha do corpo é skinned")
# altura: topo da cabeça entre 1.6 e 1.95 m, como Bram/Mira
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `GODOT --headless --path . --script res://tests/blacksmith_asset_test.gd`
Expected: erro de carregamento de `blacksmith.glb` (não existe) e saída com código ≠ 0.

- [ ] **Step 3: Ajustar `export(fname, **extra)` em `build_assets.py`**

Montar os kwargs padrão num dict e aplicar `kw.update(extra)` antes de chamar `bpy.ops.export_scene.gltf`, para que `export("blacksmith", export_animations=True, export_skins=True)` funcione sem `TypeError` de argumento duplicado. Os outros assets continuam exportando igual (conferir que `ASSETS=elder` ainda gera o mesmo arquivo: `git diff --stat assets/models/elder.glb` vazio ou só bytes de metadados).

- [ ] **Step 4: Implementar `build_blacksmith()` em `characters.py`**

- Visual (spec, "Detalhes visuais"): ferreiro robusto, braços fortes, avental de couro sobre camisa de manga curta/arregaçada, luvas de couro grossas, barba cheia, cabelo curto ou careca; reaproveitar `human_head`, `hair_locks`, `limb`, `tbox`, `drape`, `hand`, `boot` e o padrão de materiais (`mat("b_...")`) do `build_elder`/`build_merchant`.
- Construir o corpo **em pose T** (braços em ±X, palmas para baixo), altura ~1.8 m, quadril ~0.95–1.0 m, proporções próximas ao Y Bot do Mixamo.
- Armature `Armature` com os ossos, nesta hierarquia: `mixamorig:Hips` → `Spine` → `Spine1` → `Spine2` → `Neck` → `Head` → `HeadTop_End`; `Spine2` → `LeftShoulder` → `LeftArm` → `LeftForeArm` → `LeftHand`; idem `Right*`; `Hips` → `LeftUpLeg` → `LeftLeg` → `LeftFoot` → `LeftToeBase` → `LeftToe_End`; idem `Right*`. Todos com prefixo `mixamorig:`.
- Juntar as peças por região em poucas malhas e ponderar: cada peça 100% no seu osso; mangas, calça e avental que cruzam juntas recebem gradiente entre os dois ossos (spec, "Pesos"). Se a dobra ficar feia no Step 7, voltar a 100% rígido.
- `Hammer` como objeto separado (cabo de madeira + cabeça de aço), sem pesos, posicionado na mão direita em pose T.
- Clipes provisórios por keyframes de rotação nos ossos (NLA: uma action por clipe, cada uma empurrada para uma faixa NLA com o nome do clipe, para o glTF exportar as quatro): `work_hammer` (~1.2 s: ergue o braço direito acima do ombro, desce até a altura da bigorna ~0.8 m na frente do corpo, pequeno recuo; tronco acompanha), `work_pause` (~2.5 s: endireita, mão no rosto/testa, volta), `idle` (~3 s: respiração leve), `talk` (~3 s: gestos com a mão esquerda, cabeça balançando).
- `export("blacksmith", export_animations=True, export_skins=True)` (e `export_nla_strips=True` se for preciso).

- [ ] **Step 5: Gerar e importar**

Run: `ASSETS=blacksmith "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python tools/blender/build_assets.py` e depois `GODOT --headless --path . --import`
Expected: linha `EXPORT blacksmith`; import sem erro sobre `blacksmith.glb`.

- [ ] **Step 6: Configurar o retarget no import**

No `blacksmith.glb.import`, em `_subresources` do `Skeleton3D`: `retarget/bone_map` = `BoneMap` com `profile = SkeletonProfileHumanoid`, mapeando os `mixamorig:*` (o auto-mapeamento do Godot reconhece esses nomes; conferir que todos os ossos do Step 1 ficaram mapeados), `retarget/bone_renamer/rename_bones = true`, `retarget/rest_fixer/overwrite_axis = true`. Os loops (`work_hammer`, `idle`, `talk`) entram como `loop_mode` nas opções de animação do import. Rodar `--import` de novo.

- [ ] **Step 7: Rodar o teste e conferir visualmente**

Run: `GODOT --headless --path . --script res://tests/blacksmith_asset_test.gd`
Expected: só `PASS`, código 0.
Visual: render com `tools/blender/preview_characters.py` (ou o screenshot da Tarefa 5) do ferreiro ao lado de Bram e Mira; o estilo precisa bater (anti-objetivo do spec).

- [ ] **Step 8: Adicionar o teste ao CI e commitar**

Em `.github/workflows/deploy.yml`, um passo logo após o smoke test: `timeout 120 godot --headless --path . --script res://tests/blacksmith_asset_test.gd`.

```bash
git add tools/blender/build_assets.py tools/blender/characters.py assets/models/blacksmith.glb assets/models/blacksmith.glb.import tests/blacksmith_asset_test.gd .github/workflows/deploy.yml
git commit -m "Ferreiro: modelo com esqueleto Mixamo e clipes provisórios"
```

---

### Task 2: Bigorna e forja

**Files:**
- Modify: `tools/blender/props.py` (novas `build_anvil()` e `build_forge()`, registradas em `PROP_BUILDERS`)
- Create: `assets/models/anvil.glb`, `assets/models/forge.glb` (+ `.import`)
- Modify: `tests/blacksmith_asset_test.gd`

**Interfaces:**
- Produces: `res://assets/models/anvil.glb` com um `Marker3D`/empty chamado `StrikePoint` no centro do topo da bigorna (altura ~0.8 m, o golpe de `work_hammer` mira aqui); `res://assets/models/forge.glb` com um empty `Embers` no meio das brasas.

- [ ] **Step 1: Teste**: no `blacksmith_asset_test.gd`, `anvil.glb` instancia e tem `StrikePoint` com `position.y` entre 0.7 e 0.9; `forge.glb` instancia e tem `Embers`.
- [ ] **Step 2: Rodar e ver falhar** (mesmo comando da Tarefa 1; esperado FAIL nesses checks).
- [ ] **Step 3: Implementar** `build_anvil()` (bigorna de aço sobre tora de madeira, chifre para a frente) e `build_forge()` (forja baixa de pedra com brasas em material emissivo laranja, fole de couro ao lado), no estilo dos props existentes em `props.py`.
- [ ] **Step 4: Gerar** com `ASSETS=anvil,forge ...` + `--import`; **rodar o teste**: só PASS.
- [ ] **Step 5: Commit** `Ferreiro: bigorna e forja`.

---

### Task 3: Som da bigorna

**Files:**
- Modify: `scripts/autoload/sfx.gd` (novo gerador `_anvil(t: float, d: float) -> float` e registro do som `"anvil"` no `_ready`, como os outros)
- Modify: `tests/smoke_test.gd`

**Interfaces:**
- Produces: `Sfx.play_at("anvil", pos)` funcionando.

- [ ] **Step 1: Teste** no smoke test, junto dos checks de som: `Sfx.play_at("anvil", player.global_position + Vector3(2, 0, 0))` ocupa um slot (`Sfx._next_3d` muda) — mesmo padrão do check de `"hit"`.
- [ ] **Step 2: Rodar e ver falhar**: `GODOT --headless --path . res://scenes/world.tscn -- --smoketest` → FAIL nesse check (som desconhecido).
- [ ] **Step 3: Implementar `_anvil`**: tinido metálico curto (~0.35 s): ataque instantâneo, duas ou três parciais inarmônicas agudas (~1.1 kHz, ~2.7 kHz, ~4.3 kHz) decaindo rápido, mais um clique de ruído no início; usar `_tone`, `_noise`, `_env` existentes.
- [ ] **Step 4: Rodar**: PASS.
- [ ] **Step 5: Commit** `Ferreiro: som da bigorna`.

---

### Task 4: NPC ferreiro (estados, virar, golpe, diálogo)

**Files:**
- Create: `scripts/world/blacksmith.gd`
- Modify: `scripts/world/npc.gd` (`MODELS["blacksmith"]`, nome `"Doran, o Ferreiro"`, ramo `blacksmith` em `_build_dialogue`; transformar o nome por id num dict para não crescer o ternário)
- Modify: `tests/smoke_test.gd`

**Interfaces:**
- Consumes: `blacksmith.glb` (Tarefa 1: clipes, ossos do perfil, `Hammer`), `anvil.glb`/`StrikePoint` (Tarefa 2), `Sfx.play_at("anvil", pos)` (Tarefa 3).
- Produces: `class_name Blacksmith extends "res://scripts/world/npc.gd"` com:
  - `enum State { WORK, PAUSE, IDLE, TALK }` e `var state: State`
  - `const NEAR := 7.0` (mesmo raio do `npc.gd`), `const BLEND := 0.25`
  - `const STRIKES := {"work_hammer": [<tempo do impacto em s>]}` — tempos de impacto por clipe; em `_ready` o script injeta uma *method track* chamando `_on_strike` nesses tempos (funciona igual para clipes provisórios e do Mixamo)
  - `var strikes := 0` (contador, usado no teste)
  - `func _on_strike() -> void` (faíscas no `StrikePoint` + `Sfx.play_at("anvil", strike_pos)`)
  - `func clip(name: String) -> String` — devolve `"mixamo/" + name` se a biblioteca `mixamo` existir e tiver o clipe, senão `name` (Tarefa 6 adiciona a biblioteca)
  - override de `face_point()` usando a pose global do osso `Head` do `Skeleton3D`
  - `var anvil: Node3D` (a Tarefa 5 cria e atribui antes de `add_child`)

**Comportamento** (spec, "Comportamento"):
- `WORK`: toca `work_hammer` em loop; a cada 3–5 ciclos (aleatório) vai para `PAUSE` (`work_pause` uma vez) e volta a `WORK`. Modelo virado para a bigorna (`_base_yaw`).
- Jogador a menos de `NEAR`: `IDLE` (`idle`), vira para o jogador com o mesmo `lerp_angle` do `npc.gd`. Se o jogador sair de `NEAR`, volta a `WORK` e se vira de volta para a bigorna.
- `interact()`: `TALK` (`talk`) e chama o diálogo do `npc.gd`. Ao fechar o diálogo, volta a `IDLE` se o jogador ainda estiver perto, senão `WORK`. Detectar o fechamento pelo mesmo caminho que o mundo usa (`world.modal` volta a `null`), sem mexer no sistema de diálogo.
- Durante a conversa no solo a árvore está pausada: `AnimationPlayer`, as faíscas e o próprio Blacksmith (para a checagem de estado) usam `process_mode = PROCESS_MODE_ALWAYS`; o `lerp` de virar continua só fora da pausa (o `turn_to` do `npc.gd` já vira na hora).
- `Hammer` preso à mão direita por `BoneAttachment3D` (`bone_name = "RightHand"`), reparentado no `_ready`.
- Faíscas: `GPUParticles3D` (ou `CPUParticles3D` se o projeto usar esse) de uma rajada, ~20 partículas laranja-amarelas curtas, emitidas no `StrikePoint`; ver como `scripts/fx.gd` faz efeitos e reaproveitar se couber.
- Headless: `_ready` para o `AnimationPlayer` e não cria faíscas; `_on_strike` não faz nada.
- Diálogo (ambientação, 2–3 páginas, sem escolhas além de "Até logo"), tom da vila. Ex.: "Mais um golpe e essa lâmina fica pronta. Ferro bom vem das minas do norte, mas o carvão... esse está cada vez mais caro." / "Se a Mira te vendeu alguma espada, pode apostar que passou por esta bigorna."
- Marcador `!`/`?`: nenhum (o `_update_marker` já zera para quem não é o ancião).

- [ ] **Step 1: Testes no smoke test** (depois do bloco do ancião; o jogador volta ao fim para onde estava):

```gdscript
check(get_tree().get_nodes_in_group("interactable").size() == 4 + Game.FARM_PLOTS + 1,
	"3 NPCs + portal + %d canteiros + caldeirão interagíveis" % Game.FARM_PLOTS)   # substitui o check de 2 NPCs
var smith: Blacksmith = <achar por npc_id == "blacksmith">
check(smith.state == Blacksmith.State.WORK, "ferreiro começa trabalhando")
# jogador longe: golpes acontecem mas o som não toca (fora de FAR_DIST)
player.global_position = smith.global_position + Vector3(Sfx.FAR_DIST + 5.0, 0, 0)
var s0 := smith.strikes; var slot := Sfx._next_3d
await wait(2.6)
check(smith.strikes > s0, "ferreiro bate na bigorna (%d golpes)" % (smith.strikes - s0))
check(Sfx._next_3d == slot, "som do golpe não toca com o jogador longe")
# chega perto: para e vira
player.global_position = smith.global_position + <2 m na frente da bigorna>
await wait(0.6)
check(smith.state == Blacksmith.State.IDLE, "ferreiro para quando o jogador chega")
# conversa: anima com o jogo pausado
smith.interact(player); await wait(0.1)
check(smith.state == Blacksmith.State.TALK and get_tree().paused, "ferreiro conversa com o jogo pausado")
var ap := <AnimationPlayer do ferreiro>; var p0 := ap.current_animation_position
await wait(0.3)
check(ap.current_animation_position != p0, "ferreiro continua animando durante o diálogo")
world.modal._choose(Callable()); await wait(0.1)   # fechar como o teste do ancião fecha
check(smith.state == Blacksmith.State.IDLE, "ferreiro volta a ouvir após o diálogo")
# sai de perto: volta a martelar e vira para a bigorna
player.global_position = smith.global_position + Vector3(NEAR + 3.0, 0, 0); await wait(1.0)
check(smith.state == Blacksmith.State.WORK, "ferreiro volta a trabalhar quando o jogador sai")
check(absf(angle_difference(smith.model.rotation.y, smith._base_yaw)) < 0.2, "ferreiro vira de volta para a bigorna")
check(smith.clip("work_hammer") == "work_hammer", "sem biblioteca Mixamo, usa clipe provisório")
```

(Fechar o diálogo: usar a mesma chamada que o teste do ancião usa para fechar; se `_choose(Callable())` não fechar, chamar o fechamento que o `world` expõe.)

- [ ] **Step 2: Rodar e ver falhar**: `GODOT --headless --path . res://scenes/world.tscn -- --smoketest` → FAIL (classe `Blacksmith` não existe / 2 NPCs).

Obs.: no smoke test o jogo roda headless, então o `_ready` desliga a animação. Para os checks acima, o `Blacksmith` lê uma flag `Game.smoketest` (ou `"--smoketest" in OS.get_cmdline_user_args()`) que **mantém a animação e a lógica de golpe ligadas no teste**, e só o som/faíscas seguem as regras normais. Assim o headless real (servidor) continua economizando.

- [ ] **Step 3: Implementar `blacksmith.gd`** com as interfaces acima e as mudanças em `npc.gd`.
- [ ] **Step 4: Rodar o smoke test**: todos PASS (os antigos também).
- [ ] **Step 5: Commit** `Ferreiro: NPC com estados, golpe sincronizado e diálogo`.

---

### Task 5: Ferreiro na vila + foto de conferência + versão

**Files:**
- Modify: `scripts/world/world.gd` (criar o ferreiro, a bigorna e a forja junto dos NPCs, ~linha 223; registrar a área em `_avoid` e `_no_grass` pelo `prop()`)
- Create: `tools/blacksmith_shot.gd` + `tools/blacksmith_shot.tscn` (foto do ferreiro com a luz do jogo, no padrão de `tools/look_shot.gd`: `-- <saida.png> [work|idle|talk] [t]` pausa o clipe no tempo `t`)
- Modify: `project.godot` (`config/version="0.7.7"`)
- Modify: `tests/debug_dialogue.gd` se ele contar NPCs

**Interfaces:**
- Consumes: `Blacksmith` (Tarefa 4: `anvil` atribuído antes do `add_child`), `anvil.glb`, `forge.glb`.

- [ ] **Step 1: Escolher o local**: dentro do anel da vila (`_avoid` em `Vector2(0, 4)`, raio 26), livre de casas, poço `(0,0)`, ancião `(-3,0,-2.5)`, Mira `(6.8,0,1.6)`, portal `(-8,0,-9.5)`, lampiões e caminhos; visível da praça. Bigorna à frente do ferreiro (StrikePoint alinhado ao alcance do golpe de `work_hammer`), forja atrás ou ao lado. `prop("anvil", ...)` e `prop("forge", ...)` com colisão.
- [ ] **Step 2: Fotos**: `GODOT --path . --resolution 1600x900 res://tools/blacksmith_shot.tscn -- <scratchpad>/smith_work.png work 0.6` (e `idle`, `talk`); uma foto do jogo de longe com a vila. Conferir: martelo bate no topo da bigorna, pés no chão, nenhum membro torcido, estilo bate com Bram/Mira. Ajustar posição/`STRIKES`/clipes até bater.
- [ ] **Step 3: Rodar a suíte local** (skill `smoke-check`: import, smoke test, colônia, multiplayer da horda e da cidade). Esperado: todos PASSOU.
- [ ] **Step 4: Subir a versão** para `0.7.7` e **commitar** `Ferreiro: na vila, com bigorna e forja`.

---

### Task 6: Trocar pelos clipes do Mixamo (depende do download do usuário)

**Files:**
- Create: `assets/animations/mixamo/*.fbx` (+ `.import` com o mesmo `BoneMap`/perfil da Tarefa 1)
- Create: `assets/animations/blacksmith_mixamo.res` (`AnimationLibrary` com `work_hammer`, `work_pause`, `idle`, `talk`)
- Modify: `scripts/world/blacksmith.gd` (carregar a biblioteca como `"mixamo"` se o arquivo existir; atualizar `STRIKES` com os tempos dos clipes novos, por nome qualificado)
- Modify: `tests/blacksmith_asset_test.gd`, `tests/smoke_test.gd`

- [ ] **Step 1: Mandar ao usuário a lista de download** (do spec, "Animações a baixar"): martelar em pé, uma pausa de trabalho, idle, falando. Formato FBX Binary, **Without Skin**, 30 fps, *In Place* quando houver. Pedir que salve em `assets/animations/mixamo/` com os nomes `work_hammer.fbx`, `work_pause.fbx`, `idle.fbx`, `talk.fbx`. Se o Mixamo não tiver um clipe bom de martelar ou de pausa, manter o provisório para ele (decisão do usuário) e seguir com os outros.
- [ ] **Step 2: Teste**: `blacksmith_mixamo.res` carrega como `AnimationLibrary` e tem os clipes baixados; no smoke test, com o arquivo presente, `smith.clip("talk") == "mixamo/talk"`.
- [ ] **Step 3: Rodar e ver falhar.**
- [ ] **Step 4: Importar** cada FBX com `BoneMap` (`SkeletonProfileHumanoid`, renomear ossos, *rest fixer*), loops nos clipes certos, e salvar as animações numa `AnimationLibrary` (`blacksmith_mixamo.res`). Medir o tempo do impacto em `work_hammer` e atualizar `STRIKES`.
- [ ] **Step 5: Rodar os testes**: só PASS. **Fotos** da Tarefa 5 de novo com os clipes do Mixamo; conferir mãos no martelo/bigorna e pés no chão.
- [ ] **Step 6: Commit** `Ferreiro: animações do Mixamo` (FBX incluídos, decisão do usuário).

---

## Nota sobre o spec

O spec propunha `AnimationTree` com `StateMachine`. O plano usa `AnimationPlayer.play(clip, BLEND)` com um `enum` no script. São só quatro estados sem mistura entre eles, então o resultado na tela é o mesmo, e a lógica fica num lugar só e é testável pelo smoke test. Foi uma decisão minha no spec; se for preciso misturar (ex.: falar enquanto martela), dá para trocar por `AnimationTree` depois.
