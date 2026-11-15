# Bram e Mira com esqueleto — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ancião Bram e Mira, a Mercadora, viram NPCs com esqueleto e animações do Mixamo (com substitutos), cada um com personalidade: Bram apoiado no cajado e animado ao conversar; Mira chamando clientes.

**Architecture:** O rig do ferreiro (armature `mixamorig:*` em pose T, pesos) sai de `build_blacksmith` para um módulo Blender compartilhado, usado por `build_elder`/`build_merchant`. No Godot, o que o `blacksmith.gd` faz de genérico vira `scripts/world/skinned_npc.gd`; `Blacksmith`, `Elder` e `Merchant` o estendem. Uma ferramenta gera uma `AnimationLibrary` por personagem a partir dos FBX do Mixamo, caindo em substitutos quando o FBX não existe.

**Tech Stack:** Godot 4.7.2 (GDScript), Blender 5.2 CLI (bpy/bmesh), glTF/GLB, FBX do Mixamo.

**Spec:** `docs/superpowers/specs/2026-11-14-bram-mira-esqueleto-design.md`

## Global Constraints

- Worktree `C:/Games/godot-3d-ferreiro`, branch `npcs-esqueleto`. Rodar `--import` antes de testar.
- Blender só por CLI (`ASSETS=<nomes> blender --background --factory-startup --python tools/blender/build_assets.py`); regenerar só os assets da tarefa.
- Frente = -Y no Blender. Ossos = `BS_BONES` com prefixo `mixamorig:`, pose T; import com `BoneMap` + `SkeletonProfileHumanoid` + renomear ossos + rest fixer, igual a `assets/models/blacksmith.glb.import`.
- `npc_id` continua `"elder"` e `"merchant"`; nomes exibidos inalterados.
- Nomes de clipe nas bibliotecas: Bram `idle`, `excited`, `talk`; Mira `idle`, `call`, `talk`. Bibliotecas: `res://assets/animations/elder_mixamo.res`, `res://assets/animations/merchant_mixamo.res`, carregadas como `"mixamo"`.
- FBX esperados em `assets/animations/mixamo/`: `elder_idle.fbx`, `elder_excited.fbx`, `elder_talk.fbx`, `merchant_idle.fbx`, `merchant_call.fbx`, `merchant_talk.fbx` (podem faltar).
- Substitutos: idle/talk faltando → clipe `idle`/`talk` de `blacksmith_mixamo.res`; `excited`/`call` faltando → clipe provisório do próprio GLB (feito no script).
- Bram: braço esquerdo sempre na pose `staff_hold` em todos os clipes da biblioteca dele.
- Mira chama entre 7 e 14 m do jogador local, intervalo mínimo 8 s; na loja fica em `idle`.
- Diálogo abre na hora do `interact()`; Bram toca `excited` uma vez e depois `talk`.
- Animação só com `PROCESS_MODE_ALWAYS` durante a conversa; headless sem `--smoketest` não anima.
- O ferreiro não pode mudar de comportamento: `tests/blacksmith_asset_test.gd` e os checks do ferreiro no smoke test continuam passando sem alteração de valores.
- `npc.gd` só muda se for inevitável (outra sessão mexe nele).
- Commits em português `Bram e Mira: ...` + linha `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Sem push.

## Review Focus

1. **Bram fecha o diálogo durante a reação**: deve voltar a `idle` sem ficar preso em `excited`/`talk`. Teste na Tarefa 5.
2. **Jogador abre a loja da Mira pelo diálogo**: ela sai de `talk` para `idle` e a loja abre normalmente. Teste na Tarefa 5.
3. **Jogador fica parado a 10 m da Mira**: ela chama de novo só depois de ≥ 8 s, nunca em sequência. Teste na Tarefa 5.
4. **Bibliotecas com substitutos**: com nenhum FBX novo presente, o jogo e os testes funcionam e a ferramenta diz a origem de cada clipe. Teste na Tarefa 4.
5. **Ferreiro depois do refactor**: mesmos estados, golpes, faíscas e testes. Teste na Tarefa 3 (suite existente intacta).

---

### Task 1: Rig compartilhado e Bram com esqueleto

**Files:**
- Create: `tools/blender/rig.py` (executado por `build_assets.py` antes de `characters.py`, ou no topo de `characters.py`, seguindo o padrão `exec` existente)
- Modify: `tools/blender/characters.py` (`build_blacksmith` passa a usar o rig compartilhado; `build_elder` reescrito em pose T com esqueleto)
- Modify: `tools/blender/build_assets.py` (exec do novo módulo, se preciso)
- Create/Modify: `assets/models/elder.glb` + `.import` (BoneMap como o do ferreiro)
- Create: `tests/npc_asset_test.gd`; Modify: `.github/workflows/deploy.yml` (passo do teste, ao lado do `blacksmith_asset_test`)

**Interfaces:**
- Produces (Blender): `mixamo_rig(body_objs, P, joints, hip_z, top) -> armature_object` em `rig.py` (cria `BS_BONES` em pose T, parenteia e aplica o modificador Armature); move para `rig.py` também `weigh`, `pose_fk`, `bake_clip`, `_ik` e `MIXAMO`/`BS_BONES`, sem mudar comportamento.
- Produces (asset): `elder.glb` com um `Skeleton3D` (ossos do perfil humanoide após import), malha *skinned*, objeto separado `Staff` (cajado, sem pesos, pivô na mão esquerda), e clipes `staff_hold` (1 quadro: braço esquerdo segurando o cajado de pé ao lado do corpo) e `excited` (provisório, ~1,5 s: ergue os dois braços / bate palmas, braço direito como dobradiça; o esquerdo pode sair da pose só se o cajado continuar coerente, senão animar só o direito e o tronco).

- [ ] **Step 1: Medir o Bram atual** (altura do topo da cabeça, largura de ombros, posição do topo do cajado) a partir do `elder.glb` atual e guardar como constantes no teste.
- [ ] **Step 2: Escrever `tests/npc_asset_test.gd`** (`extends SceneTree`, PASS/FAIL, `quit(1)` em falha):
  - `elder.glb`: um `Skeleton3D` com `Hips, Spine, Chest, Neck, Head, LeftUpperArm, LeftLowerArm, LeftHand, RightUpperArm, RightLowerArm, RightHand, LeftUpperLeg, LeftLowerLeg, LeftFoot, RightUpperLeg, RightLowerLeg, RightFoot`; alguma `MeshInstance3D` com `skin`; `Staff` existe e não tem `skin`; `AnimationPlayer` tem `staff_hold` e `excited`; altura no máximo 3 cm diferente da medida no Step 1; pés no chão (min y entre -0.02 e 0.03).
- [ ] **Step 3: Rodar e ver falhar** (`GODOT --headless --path . --script res://tests/npc_asset_test.gd` → FAIL: sem esqueleto).
- [ ] **Step 4: Extrair `rig.py`** e trocar `build_blacksmith` para usá-lo. Rodar `ASSETS=blacksmith`, `--import` e `tests/blacksmith_asset_test.gd`: tudo PASS (o ferreiro não muda).
- [ ] **Step 5: Reescrever `build_elder`** em pose T (mesmas peças, cores e proporções; túnica e manto com pesos em gradiente entre quadril e coxas para não rasgar), cajado como `Staff` separado, clipes `staff_hold` e `excited`, `export("elder", export_animations=True, export_skins=True, export_animation_mode='NLA_TRACKS')`. Configurar o `.import` com o BoneMap.
- [ ] **Step 6: Gerar, importar, rodar `npc_asset_test`**: PASS. Fotos antes/depois lado a lado (frente, lado, 3/4) com o Bram em `staff_hold` vs o atual: roupas, rosto, cabelo, cores e cajado batem. Foto do `excited` em 3 instantes: sem torção.
- [ ] **Step 7: CI e commit** — passo no `deploy.yml`; `Bram e Mira: rig compartilhado e Bram com esqueleto`.

---

### Task 2: Mira com esqueleto

**Files:**
- Modify: `tools/blender/characters.py` (`build_merchant`)
- Modify: `assets/models/merchant.glb` + `.import`
- Modify: `tests/npc_asset_test.gd`

**Interfaces:**
- Consumes: `mixamo_rig(...)` (Tarefa 1).
- Produces: `merchant.glb` com esqueleto do perfil, malha *skinned* e clipe provisório `call` (~1,5 s: acena/chama com a mão direita, braço como dobradiça).

- [ ] **Step 1: Medir a Mira atual** (altura) e **adicionar ao teste** os mesmos checks do Bram (sem `Staff`), com `call` no `AnimationPlayer`.
- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Reescrever `build_merchant`** em pose T (mesmo visual; saia/capa/mantelete com pesos em gradiente), clipe `call`, export com skins/animações, `.import` com BoneMap.
- [ ] **Step 4: Gerar, importar, teste PASS; fotos antes/depois e do `call`.**
- [ ] **Step 5: Commit** `Bram e Mira: Mira com esqueleto`.

---

### Task 3: Base `SkinnedNPC` no Godot (refactor do ferreiro)

**Files:**
- Create: `scripts/world/skinned_npc.gd`
- Modify: `scripts/world/blacksmith.gd`

**Interfaces:**
- Produces: `class_name SkinnedNPC extends "res://scripts/world/npc.gd"` com:
  - `const BLEND := 0.25`; `var anim: AnimationPlayer`; `var skeleton: Skeleton3D`; `var _animate: bool`
  - `func library_path() -> String` (sobrescrito; `""` = sem biblioteca)
  - `func clip(clip_name: String) -> String` (mesma regra de hoje: `"mixamo/" + nome` se existir na biblioteca)
  - `func _play(clip_name: String, blend := BLEND) -> void`
  - `func _set_always(on: bool) -> void`
  - `func attach_to_bone(node_name: String, bone: String) -> void` (generaliza `_attach_tools`)
  - `func _add_rest_tracks(clips: Array) -> void` (generaliza o atual, para os clipes dados)
  - `func face_point() -> Vector3` (osso `Head`)
  - `func dialogue_open() -> bool` (a detecção atual de `world.modal` + `is_instance_valid`)
  - `_ready()` cuida de: achar `anim`/`skeleton`, carregar a biblioteca como `"mixamo"`, decidir `_animate` (headless sem `--smoketest` → falso, parar o `AnimationPlayer`).
- `Blacksmith extends SkinnedNPC` mantém só o que é do ferreiro (estados, golpes, faíscas, bigorna, encantamento).

- [ ] **Step 1: Rodar a suite atual** (smoke + `blacksmith_asset_test`) e guardar o resultado como referência (é a rede de segurança deste refactor).
- [ ] **Step 2: Extrair `SkinnedNPC`** e reduzir `blacksmith.gd` a ele + o específico. Nenhum valor ou nome público do ferreiro muda (`State`, `strikes`, `STRIKES`, `ANVIL_OFFSET`, `clip()`, `strike_pos()`, `enchant_strike()` etc.).
- [ ] **Step 3: Rodar a suite**: os mesmos PASS de antes, nenhum check do ferreiro alterado.
- [ ] **Step 4: Commit** `Bram e Mira: base SkinnedNPC extraída do ferreiro`.

---

### Task 4: Bibliotecas de animação com substitutos

**Files:**
- Create: `tools/build_npc_mixamo.gd` (generaliza `tools/build_blacksmith_mixamo.gd`; o ferreiro passa a ser uma das entradas e o arquivo antigo é removido ou vira chamada da nova)
- Create: `assets/animations/elder_mixamo.res`, `assets/animations/merchant_mixamo.res`
- Modify: `tests/npc_asset_test.gd`

**Interfaces:**
- Consumes: `elder.glb` (`staff_hold`, `excited`), `merchant.glb` (`call`), `blacksmith_mixamo.res` (`idle`, `talk`).
- Produces: as duas bibliotecas com os nomes de Global Constraints; loops: `idle` e `talk` em loop, `excited` e `call` uma vez. Na do Bram, as trilhas de `LeftShoulder`, `LeftUpperArm`, `LeftLowerArm`, `LeftHand` de todos os clipes são substituídas pela pose de `staff_hold` (constante).
- A ferramenta imprime, por clipe, `FBX` ou `SUBSTITUTO (<origem>)`.

- [ ] **Step 1: Testes** no `npc_asset_test.gd`: cada biblioteca tem exatamente os 3 nomes; loops certos; todas as trilhas em ossos do perfil (`%GeneralSkeleton:` sem `mixamorig`); no Bram, a rotação de `LeftLowerArm` é igual em t=0 e no meio de cada clipe (constante = `staff_hold`).
- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Implementar** e gerar as bibliotecas (hoje, sem os FBX novos, tudo sai de substitutos). `blacksmith_mixamo.res` gerado de novo tem os mesmos clipes de antes.
- [ ] **Step 4: Teste PASS; `blacksmith_asset_test` PASS. Commit** `Bram e Mira: bibliotecas de animação com substitutos`.

---

### Task 5: Comportamento de Bram e Mira no jogo

**Files:**
- Create: `scripts/world/elder.gd`, `scripts/world/merchant.gd`
- Modify: `scripts/world/world.gd` (criar Bram/Mira por essas classes, mesmas posições e `npc_id`)
- Modify: `scripts/world/npc.gd` só se inevitável (ex.: deixar de achar `Head` como `Node3D`)
- Modify: `tests/smoke_test.gd`

**Interfaces:**
- Produces: `class_name Elder extends SkinnedNPC` — `enum State { IDLE, EXCITED, TALK }`, `var state`; `interact()` abre o diálogo (via `npc.gd`) e toca `excited` uma vez → `talk` em loop até `dialogue_open()` ficar falso → `idle`. `Staff` preso a `LeftHand` por `attach_to_bone`.
- Produces: `class_name Merchant extends SkinnedNPC` — `enum State { IDLE, CALL, TALK }`, `var state`, `var calls := 0`, `const CALL_MIN := 7.0`, `const CALL_MAX := 14.0`, `const CALL_COOLDOWN := 8.0`; com o jogador local entre 7 e 14 m e cooldown vencido, toca `call` uma vez virada para ele; `interact()` → `talk`; ao abrir a loja ou fechar o diálogo → `idle`.
- Os dois mantêm o marcador e o virar a < 7 m do `npc.gd`.

- [ ] **Step 1: Testes no smoke test** (ao lado dos do ancião e da Mira):
  - Bram: começa `IDLE`; `interact()` → `world.modal` aberto na hora e `state == EXCITED`; depois de ~2 s `state == TALK` e o `AnimationPlayer` avança com o jogo pausado; fechar o diálogo **durante** `EXCITED` → `IDLE` (Review Focus 1); o fluxo de missão do ancião já existente continua passando.
  - Mira: jogador a 10 m → `state == CALL` e `calls == 1` em até ~1 s; parado ali 5 s → `calls` continua 1; depois de 9 s → `calls == 2` (Review Focus 3); jogador a 20 m → sem chamado; `interact()` → `TALK`; escolher "Ver mercadorias" → loja abre e `state == IDLE` (Review Focus 2).
  - Contagem de interagíveis inalterada.
- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Implementar** `elder.gd`, `merchant.gd`, `world.gd`.
- [ ] **Step 4: Smoke PASS** (todos os antigos também).
- [ ] **Step 5: Vídeo e fotos** com a cena de vídeo do ferreiro adaptada (`.superpowers/.../movie/`): Bram parado, reação e conversa; Mira parada, chamando e conversando. Conferir anti-objetivos do spec (túnica/saia sem pernas atravessando, cajado firme, sem torção).
- [ ] **Step 6: Commit** `Bram e Mira: comportamento no jogo`.

---

### Task 6: Animações do dono, versão e bateria completa

**Files:**
- Create: `assets/animations/mixamo/elder_*.fbx`, `merchant_*.fbx` (+ `.import` com BoneMap) — os que o dono baixar
- Modify: `assets/animations/elder_mixamo.res`, `merchant_mixamo.res`; `export_presets.cfg` (FBX fora do export, como os do ferreiro); `project.godot` (versão)

- [ ] **Step 1: Importar os FBX presentes** e regerar as bibliotecas; a ferramenta lista o que veio do FBX e o que ficou no substituto.
- [ ] **Step 2: Testes** (`npc_asset_test`, smoke) PASS; vídeos novos dos dois; conferir anti-objetivos; se um clipe do dono quebrar o cajado ou a túnica de forma feia, voltar ao substituto daquele clipe e dizer no relatório.
- [ ] **Step 3: Merge do `origin/main` se ele andou, versão uma acima da do `main`, bateria completa do CI** (como `deploy.yml`, servidores de teste mortos só pelo PID).
- [ ] **Step 4: Commit** `Bram e Mira: animações do Mixamo`.
