# Penteados na criação e cabelo sob capuzes — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** o herói escolhe um de 4 penteados por corpo na criação, e o cabelo aparece inteiro sob capuzes e chapéus.

**Architecture:** o cabelo sai dos estilos de cabeça (`h_*`) e vira um GLB próprio por penteado
(`gear/hair_<id>.glb` e a variante apertada `hair_<id>_tight.glb`, `_f` no corpo feminino), vestido por
`KnightLook.apply` como um equipamento. O penteado (`hair`) segue o mesmo caminho do corpo (`body`):
`CharState` → `choose_class` → criação/lista → visual na rede, com o servidor mandando o gravado.

**Tech Stack:** Godot 4.7.2 (GDScript), Blender 5.2 por CLI (`tools/blender/build_assets.py`), SQLite (servidor).

**Spec:** `docs/superpowers/specs/2026-11-18-penteados-design.md`

## Global Constraints

- Ids: `m_curto`, `m_penteado`, `m_franja`, `m_raspado` (m); `f_longo`, `f_chanel`, `f_curto`, `f_marias` (f). Padrões: `m_curto`, `f_longo`.
- `hair` vazio ou de outro corpo = padrão do corpo (personagens antigos).
- Servidor nunca aceita o penteado do visual do cliente; manda o gravado.
- Scripts puros (`scripts/character/*`) sem nomes de autoload (`Game`, `ItemDB`).
- Modelos sem peças soltas (`LOOSE` vazio no build); versão sobe antes do merge.

## Review Focus

- Personagem antigo sem `hair` gravado: entra com o penteado padrão do corpo (teste em Task 1).
- `choose_class` com penteado do outro corpo: falha `penteado_invalido` (teste em Task 1).
- Banco existente (v10) sobe para a coluna nova sem perder personagens (teste em Task 1).
- Trocar de chapéu para capuz e de volta: só um cabelo no modelo, sem sobra do anterior (Task 3, captura).
- Rabo de cavalo continua balançando com o penteado `f_longo` (Task 3, captura em movimento).

---

### Task 1: Penteado nos dados (regra, estado, banco, serviço, rede)

**Files:**
- Create: `scripts/character/hair_styles.gd` (`class_name HairStyles`)
- Modify: `scripts/character/char_state.gd`, `scripts/character/char_rules.gd` (`choose_class`),
  `scripts/character/character_service.gd` (`create_character`, `list_characters`),
  `scripts/server/migrations.gd` (nova versão: `ALTER TABLE characters ADD COLUMN hair TEXT NOT NULL DEFAULT ''`),
  `scripts/server/sqlite_char_store.gd` (`load_char`, `_write`, `list_chars`),
  `scripts/autoload/network.gd` (`char_create`, pedido "create", `_clean_look`, `server_hair`), `scripts/autoload/game.gd` (`Game.hair`)
- Test: `tests/unit/test_char_rules.gd`, `tests/unit/test_character_service.gd`

**Interfaces:**
- Produces: `HairStyles.STYLES: Dictionary` (corpo → Array de ids), `HairStyles.default_for(body: String) -> String`,
  `HairStyles.resolve(body: String, hair: String) -> String` (padrão quando vazio/inválido),
  `HairStyles.valid(body: String, hair: String) -> bool`; `CharState.hair: String`;
  `CharRules.choose_class(s, bt, cls, body, hair := "")`; evento `{"t": "class", ..., "hair": h}`;
  look com `"hair"`; `Network.char_create(name, cls, body, hair := "")`.

- [ ] Testes: `test_choose_class_hair_default` (sem hair → `s.hair == "m_curto"`), `test_choose_class_hair_valid`
  (`"f_chanel"` com corpo f → gravado), `test_choose_class_hair_wrong_body` (`"m_franja"` com f → `err == "penteado_invalido"`),
  `test_state_hair_roundtrip` (`to_dict`/`from_dict`), `test_state_old_save_no_hair` (dict sem a chave → `hair == ""`,
  `HairStyles.resolve("f", "") == "f_longo"`), `test_create_character_hair` no serviço (lista traz `hair`).
- [ ] Rodar `godot --headless --path . -s tests/unit/run.gd`: os novos falham.
- [ ] Implementar; o pedido "create" aceita 3 ou 4 argumentos (cliente antigo).
- [ ] Rodar os unitários: passam. Commit.

### Task 2: Modelos dos penteados

**Files:**
- Create: `tools/blender/hair.py` (penteados; carregado por `build_assets.py` depois de `female.py`)
- Modify: `tools/blender/gear.py` (`plain_head` nunca põe cabelo nos `h_*`), `tools/blender/female.py`
  (rabo de cavalo sai do `knight_f`), `tools/blender/build_assets.py` (`ASSETS=hair`)

**Interfaces:**
- Consumes: `anime_hair`, `anime_bun`, `_lock`, `_scalp` (anime.py); `g_export`/`_g_export_f`, `drop_head`.
- Produces: `assets/models/gear/hair_<id>.glb` e `hair_<id>_tight.glb` para os ids m; `hair_<id>_f.glb` e
  `hair_<id>_tight_f.glb` para os ids f. Malhas presas ao pivô `Head`; o rabo de cavalo e as
  marias-chiquinhas num nó `Ponytail` (origem no prendedor).

- [ ] `hair_style(id, tight)`: estilo de `anime_hair` por id + mechas extras (rabo, marias); `tight` reduz `lift`
  para 0,35, tira o volume de cima (`top` mais rente) e mantém franja, nuca e o que cai abaixo da orelha.
- [ ] Build `ASSETS=hair`: sem `LOOSE`; render das 8 cabeças nuas e lado a lado com as referências.
- [ ] Render de cada penteado `tight` sob `h_hood`, `h_wizard`, `h_void`: nada atravessa o tecido.
- [ ] Commit.

### Task 3: Vestir o penteado no jogo

**Files:**
- Modify: `scripts/player/knight_look.gd` (`HEAD_HAIR`, anexar o GLB do penteado, tirar `HIDE_PONYTAIL`),
  `scripts/player/knight_anim.gd` (achar o `Ponytail` vindo do equipamento a cada `apply`),
  `scripts/player/player.gd` (`l["hair"] = Game.hair`)

**Interfaces:**
- Consumes: look `"hair"`, `HairStyles.resolve`.
- Produces: `KnightLook.HEAD_HAIR: Dictionary` (estilo de cabeça → `"full"|"tight"|"none"`; ausente = `"full"`).

- [ ] Modos: `tight` para `h_hood`, `h_cap`, `h_wizard`, `h_archmage`, `h_sage`, `h_void`, `h_oracle`, `h_ember`,
  `h_lich`, `h_reaper` e chapéus de aba; `none` para `h_great`, `h_dragon`; os demais `full` (decidir `h_kettle` e
  `h_nasal` pelo render).
- [ ] Capturas `--geardemo` com `--equip=` de cada modo, nos dois corpos; smoke test.
- [ ] Commit.

### Task 4: Escolha na tela de criação

**Files:**
- Modify: `scripts/ui/char_create.gd` (fileira de penteados, `select_hair`, envia `hair`), a prévia
  (`show_hair`), `scripts/ui/char_select.gd` (modelo da lista com o penteado)

- [ ] Botões com o nome de cada penteado; trocar o corpo volta para o padrão do novo corpo.
- [ ] Captura `res://scenes/char_create.tscn -- --body=f --hair=f_marias --shot=...`.
- [ ] Smoke, vila, unitários; versão 0.49.0; guia `docs/ESTILO_TOON.md`. Commit.
