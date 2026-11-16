# Classes — Partes 2, 3 e 4 — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Buffs de comida viram habilidades de classe (comida fica com bônus genérico), árvore de talentos por classe e corpo feminino com cabelo longo e silhueta feminina.

**Architecture:** Um sistema de buffs único (`Game.buffs` + `buffs.json`) atende comida e habilidades; buffs em aliados reaproveitam o caminho servidor da Cura (`HealRules`). Talentos são estado do personagem validado em `CharRules` (como `passives`), somados em `mod()`. O corpo feminino é um segundo GLB com o mesmo esqueleto, escolhido por `body`.

**Tech Stack:** Godot 4.7 GDScript, JSON em `data/balance`, SQLite (servidor), Blender 5.2 CLI.

**Spec:** `docs/superpowers/specs/2026-11-16-classes-partes-2-a-4-design.md` (base: `docs/superpowers/specs/2026-11-15-classes-e-criacao-design.md`)

## Global Constraints

- Worktree `C:/Games/godot-3d-classes2`, branch `classes-partes-2-4` (empilhada em `classes-criacao`). Nunca mexer em `C:/Games/godot-3d` nem em outras branches; não fazer push.
- GODOT = `C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe`; worktree novo: `--import` antes dos testes; script `class_name` novo também pede `--import`.
- Testes: unit `-s tests/unit/run.gd`; smoke `res://scenes/world.tscn -- --smoketest`; vila `-- --vilatest`; assets `--script res://tests/blacksmith_asset_test.gd` e `npc_asset_test.gd`; net como em `.github/workflows` (servidor `--test` em segundo plano em porta própria, matar só o PID dele, `--horde-pick=5`).
- Falhas aleatórias conhecidas: projéteis/flechas e Turbilhão no smoke, arquivos user:// compartilhados no unit, tempo no net — rodar de novo uma vez antes de culpar a mudança. `test_audio_files.gd` não compila também no main.
- Scripts puros (CharRules, CharState, LootRules, HealRules, PartyRules, CharacterService) não usam nomes de autoload (`Game`, `ItemDB`...).
- Mudou tabela em `data/balance`: regenerar `tests/unit/fixtures/balance_snapshot.bin` com `tools/balance_snapshot.gd -- <tabelas>` e incluir tabela nova na lista `BalanceTables.NAMES`.
- Textos em português. Commits terminam com `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Modelos: Blender CLI em background (nunca MCP), sem peças soltas (`LOOSE` vazio), estilo toon (cel + `_flat`), capturas com `--geardemo` (nunca abrir hub/colony direto).
- Raio dos buffs de aliado = o da Cura (8 m, `HealRules.RADIUS`), mais o bônus do talento `h_grace`.
- Versão final: `config/version` = próxima menor acima da do main na hora do fim (hoje main 0.25.x e a parte 1 0.26.0 → 0.27.0).

## Review Focus

1. Personagem salvo com buff de comida ativo (sessão) ou save antigo com `talents` ausente → carrega sem erro, pontos retroativos certos (Task 4).
2. Cliente pedindo buff de aliado sem ser healer, rápido demais, ou buff id arbitrário → servidor ignora; cliente só aplica ids de `buffs.json` (Task 3).
3. Talento acima do nível máximo, sem pontos, linha bloqueada, classe errada, vindo da rede → recusado sem mudar estado (Task 4).
4. Corpo feminino com armadura completa: nada atravessa busto/cabelo; animações (andar, atacar, esquiva, emotes, capa) funcionam iguais (Tasks 7–8).
5. Réplica de outro jogador feminino aparece feminina; trocar equipamento não volta para o corpo masculino (Task 8).

---

### Task 1: Sistema de buffs único e comida com bônus genérico

**Files:** Create `data/balance/buffs.json`; Modify `data/balance/items.json` (8 comidas: `"buff": "<id>"`, sem `special`), `scripts/autoload/game.gd` (`food_buffs`→`buffs`, `food_mods`→`buff_mods`, `_recalc_buff_mods`, `add_buff(id, secs := -1.0)`, `tick_buffs`, `clear_buffs`), `scripts/autoload/item_db.gd` (descrição da comida), `scripts/vfx/buff_aura.gd` (`style_for(buff_id)` lê `aura` da tabela), `scripts/character/party_rules.gd` (`clean_buffs(buffs, buff_table)`), `scripts/autoload/party.gd`, `scripts/ui/party_frames.gd`, `scripts/ui/hud.gd`, `scripts/character/char_rules.gd` (aviso do consumo), `scripts/player/player.gd` (`--buffs=`), `scripts/balance/*` se houver carga de tabelas; testes `tests/unit/test_party.gd`, `tests/unit/test_char_rules.gd`, `tests/smoke_test.gd`, `tests/net_test.gd`.

**Interfaces — Produces:** `buffs.json` `{id: {"name", "time", "add": {stat: float}, "aura", "desc", "color"}}` com os 8 `food_*` do spec + as 5 de habilidade (`sword_fury`, `bow_focus`, `staff_ember`, `scepter_ward`, `scepter_feast`) com os números do spec; `Game.buffs: Dictionary`, `Game.buff_mods: Dictionary`, `Game.add_buff(id: String, secs := -1.0) -> void` (secs < 0 = `time` da tabela; renova se já ativo), `Game.has_buff(id) -> bool`; `PartyRules.clean_buffs(buffs, buff_table: Dictionary) -> Dictionary`.

- [ ] Testes que falham: comer `spicy_soup` adiciona `food_warm` e `Game.mod("gold")` sobe 0,05 e `mod("damage")` não muda; `clean_buffs` aceita `sword_fury`/`food_feast`, recusa id fora da tabela; nenhum item `food` tem `special` nem `buff.add` de combate (`damage`, `crit`, `defense`, `lifesteal`, `cooldown`, `speed`, `max_hp_flat`, `regen`).
- [ ] Rodar → falha. Implementar. Rodar unit + smoke + net → passa. Commit `feat: buffs numa tabela só; comida dá bônus genérico`.

### Task 2: Habilidades de buff do guerreiro, arqueiro e mago (slot 3)

**Files:** `scripts/autoload/item_db.gd` (`ABILITIES`: `sword_fury` sword slot 3 nível 5 recarga 28; `bow_focus` bow slot 3 nível 5 recarga 26; `staff_ember` staff slot 3 nível 5 recarga 30 custo 25), `scripts/player/abilities/{sword,bow,staff}_abilities.gd` (`use` aplica `Game.add_buff`, pose curta, `send_event` para o visual remoto, `play_remote` mostra a aura), `scripts/ui/skill_icon.gd`/`icon_painter` (ícones), `tests/smoke_test.gd`.

**Interfaces — Consumes:** `Game.add_buff` (Task 1). **Produces:** ids de habilidade = ids de buff para `sword_fury`/`bow_focus`/`staff_ember`.

- [ ] Smoke que falha: em cada classe no nível 5, `use_slot(3)` dá o buff, `mod` certo sobe, recarga entra; no nível 4 fica bloqueada.
- [ ] Implementar; unit + smoke + vila → passa. Commit `feat: habilidades de buff no slot 3`.

### Task 3: Escudo de Luz e Banquete do Herói (healer, aliados)

**Files:** `scripts/autoload/item_db.gd` (`scepter_ward` ready, slot 2, nível 3, recarga 22, custo 30; `scepter_ult` ready, ultimate, nome "Banquete do Herói"), `scripts/player/abilities/scepter_abilities.gd`, `scripts/server/heal_rules.gd` (intervalo por id: `MIN_INTERVAL` por habilidade = recarga × 0,4 − 0,2, ult sem intervalo além da fúria, `RADIUS` + bônus), `scripts/autoload/network.gd` (`request_ally_buff(ability_id)`, `_you_got_buff(buff_id)`), `tests/unit/test_heal_rules.gd`, `tests/net_test.gd`.

**Interfaces — Produces:** `Network.request_ally_buff(ability_id: String) -> void` (cliente→servidor; servidor confere classe healer, vivo, intervalo, ability id em `{"scepter_ward","scepter_ult"}`); RPC `_you_got_buff(buff_id: String)` (authority; cliente aplica só ids de `buffs.json`); ult: servidor também manda `_you_were_healed(ULT_HEAL=9999, from)`. Solo: aplica em si direto.

- [ ] Testes que falham: unit de intervalo por id; net: Ana healer usa `scepter_ward` e Beto perto recebe `scepter_ward`; guerreiro pedindo nada recebe; ult cura Beto ao máximo e dá `scepter_feast`.
- [ ] Implementar; unit + smoke + net → passa. Commit `feat: Escudo de Luz e Banquete do Herói no grupo`.

### Task 4: Talentos — regras, dados e persistência

**Files:** Create `data/balance/talents.json` (as 4 árvores do spec: `{class: {"branches": [{"id","name","talents":[{"id","name","row":1..3,"max":3,"add":{stat:valor},"desc"}]}]}}`); Modify `scripts/character/char_state.gd` (`talents: Dictionary`), `scripts/character/char_rules.gd` (`talent_points(s, bt) -> int`, `learn_talent(s, bt, id) -> Dictionary`, `reset_talents(s, bt) -> Dictionary`, `talent_mods(bt, s) -> Dictionary`, `reset_cost(s) -> int` = 0 até nível 5, senão 50×nível), `scripts/character/character_service.gd` (ops `learn_talent` [String], `reset_talents` []), `scripts/server/migrations.gd` + `sqlite_char_store.gd` (coluna `talents` TEXT default `'{}'`, próxima versão), `scripts/character/file_char_store.gd` se precisar; testes `tests/unit/test_char_rules.gd`, `test_character_service.gd`, `test_db.gd`/store.

**Interfaces — Produces:** as funções acima; erros `"sem_pontos"`, `"talento_invalido"`, `"talento_bloqueado"`, `"talento_maximo"`, `"sem_ouro"`; evento `{"t": "talent", "id", "level"}`.

- [ ] Testes que falham: nível 1 → 0 pontos; nível 4 → 3 pontos; aprender linha 2 sem 3 pontos no ramo falha; talento de outra classe falha; 4º nível falha; reset devolve pontos e cobra `reset_cost`; grátis no nível ≤5; save sem `talents` carrega `{}`; SQLite grava e relê.
- [ ] Implementar; unit → passa. Commit `feat: árvore de talentos nas regras do personagem`.

### Task 5: Talentos no jogo (bônus e chaves de habilidade)

**Files:** `scripts/autoload/game.gd` (`talent_mods` recalculado em `apply_state`, somado em `mod()`; `ability_time_bonus(id) -> float`), módulos de habilidade (duração de `sword_fury`/`bow_focus`/`staff_ember`/`scepter_ward`/`scepter_feast` + talento; dano do Turbilhão/Vendaval/Meteoros × (1 + bônus); atordoamento da Nova), `CharRules.heal_amount` (× `heal_power`), `HealRules`/`network.gd` (raio + `h_grace` do personagem no servidor), `tests/smoke_test.gd`, `tests/unit/*`.

**Interfaces — Consumes:** `CharRules.talent_mods` (Task 4). Chaves novas: `heal_power`, `mp_pct`, `mp_regen`, `ability_time:<id>`, `ability_dmg:<id>`, `nova_stun`, `ally_radius`.

- [ ] Testes que falham: guerreiro com `w_edge` 3 tem `mod("damage")` +0,12; healer com `h_heal` 2 cura ×1,12 (`heal_amount`); `w_rage` 1 deixa Fúria Picante com 12 s.
- [ ] Implementar; unit + smoke → passa. Commit `feat: talentos valem no combate`.

### Task 6: Aba Talentos e redistribuir na guilda

**Files:** `scripts/ui/game_menu.gd` (aba "Talentos"), novo `scripts/ui/talent_panel.gd`, NPC da guilda (diálogo/opção "Redistribuir talentos", procurar onde fica o Mestre da Guilda em `scripts/hub` ou `scripts/story`), HUD (aviso de ponto livre ao subir de nível), `tests/smoke_test.gd`.

- [ ] Smoke que falha: abrir a aba, aprender um talento pelo botão, ver `x/3`; linha bloqueada desabilitada; redistribuir pela guilda devolve pontos.
- [ ] Implementar; captura da aba (1280×720, sem sobreposição); unit + smoke + vila → passa. Commit `feat: aba de talentos e redistribuir na guilda`.

### Task 7: Modelo feminino (Blender)

**Files:** `tools/blender/characters.py` (`build_knight(female=False)` ou `build_knight_f()`, mesmos nomes de ossos/nós), `tools/blender/build_assets.py` (grupo), `tools/blender/anime_body.py`/`body.py`/`head.py` só onde precisar de parâmetro; Create `assets/models/knight_f.glb`.

- [ ] Gerar com proporções, busto, rosto e cabelo do spec (Parte 4). `LOOSE` vazio. Conferir que o GLB tem o mesmo esqueleto/nós do `knight.glb` (listar e comparar nomes).
- [ ] Capturas Blender: frente, perfil, 3/4, costas, lado a lado com o masculino. Critério: de costas e de perfil lê como mulher (cabelo longo + rabo de cavalo + cintura/quadril/busto). Até 3 rodadas de ajuste comparando capturas.
- [ ] Commit `feat: corpo feminino do herói`.

### Task 8: Corpo feminino no jogo

**Files:** `scripts/player/knight_look.gd` (escolhe `knight_f.glb` por `body`; escala por peça no feminino para peitoral/ombreiras/capa), `scripts/player/player.gd` (`_build_model` local e réplicas pelo `look.body`), `scripts/ui/char_preview.gd` (prévia por corpo), `scripts/ui/char_create.gd` (prévia troca ao escolher sexo; remove o aviso "chega em breve"), `scripts/player/cape_rig.gd` se o cabelo/rabo precisar balançar, `game.gd` `--geardemo` com `--body=f`, `tests/smoke_test.gd`, `tests/net_test.gd`.

- [ ] Testes que falham: smoke com `--body=f` carrega `knight_f`; trocar arma/armadura mantém o corpo; net: Beto vê Ana feminina.
- [ ] Capturas no jogo (`--geardemo --body=f`): sem armadura, com armadura completa de 3 conjuntos diferentes, segurando cada tipo de arma, correndo; nada atravessa busto/cabelo.
- [ ] Unit + smoke + vila + net → passa. Commit `feat: corpo feminino no jogo`.

### Task 9: Versão e verificação final

- [ ] `git fetch`; se o main andou, avisar o controlador (não fazer merge aqui). `config/version` = 0.27.0 (ou a próxima menor acima do main).
- [ ] CI completo (import, unit, smoke, assets, vila, net). Commit `Classes partes 2 a 4: habilidades, talentos e corpo feminino; versão 0.27.0`.
