# Tela de criação de herói (versão A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refazer `char_create` no layout "Palco central": coluna de classes com emblema, herói grande no
centro com aparência (sexo + miniaturas de penteado), ficha com história, perfil e habilidades com ícone, e
rodapé com nome validado ao vivo.

**Architecture:** Dados novos em `classes.json`; três componentes de UI pequenos e reaproveitáveis
(`ClassEmblem`, `HairPicker`, `SkillStrip`); `char_create.gd` reescrito só como montagem e fluxo, mantendo a
API que os testes usam. `CharPreview` ganha um modo retrato para as miniaturas.

**Tech Stack:** Godot 4.7.2, GDScript, testes em `tests/unit` (`T.eq`/`T.ok`) e `tests/smoke_test.gd`.

**Spec:** `docs/superpowers/specs/2026-11-18-criacao-heroi-design.md` (mockup:
https://claude.ai/artifact/QMceNMwcbppqf754CNpQs5, aba "A · Palco central").

## Global Constraints

- Tela de referência 1600×900 (`canvas_items`, `expand`); conferir também 1280×720 sem nada cortado.
- Tema escuro (`UITheme.get_theme()`, `GOLD`, `TEXT`, `DIM`), não o pergaminho.
- Scripts puros testados por `tests/unit/run.gd` (`-s`) não podem citar autoloads (`Game`, `ItemDB`…).
- Nome: regras de `CharacterService` (`NAME_MIN` 3, `NAME_MAX` 16, `clean_name`, `explain_create`).
- Não mexer em `CharRules`, `CharacterService`, rede nem no fluxo de "Começar"/"Voltar"/Esc.
- PR sobe `config/version` de `0.50.0` para `0.51.0` (ou a próxima livre no main na hora do merge).
- Comentários e textos em português, no estilo dos arquivos vizinhos.

## Review Focus

- Classe sem os campos novos no JSON (tabela antiga vinda do servidor): a ficha tem que abrir sem erro,
  escondendo o que falta. → teste em Task 1.
- Trocar sexo várias vezes rápido: miniaturas certas do corpo novo, nenhuma prévia órfã, penteado padrão.
  → smoke em Task 5.
- Habilidade sem PNG (Lança de Luz, Julgamento de Luz): ícone do `IconPainter`, não espaço vazio. → smoke
  em Task 5.
- Nome com espaço, acento só, 2 letras, 17 letras: mensagem certa e "Começar" não envia. → smoke em Task 5.
- Personagem antigo (`Game.is_old_character()`): aviso continua visível e começa na classe da arma.
  → já coberto pelo smoke existente; conferir que segue passando.

---

### Task 1: Dados das classes e emblema

**Files:**
- Modify: `data/balance/classes.json`
- Create: `scripts/ui/class_emblem.gd`
- Create: `tests/unit/test_class_emblem.gd`

**Interfaces:**
- Produces: `class_name ClassEmblem extends Control` com `var kind := ""`, `var color := Color.WHITE`,
  `const KINDS := ["warrior", "archer", "mage", "healer"]`,
  `static func draw(ci: CanvasItem, kind: String, color: Color, r: Rect2) -> void`,
  `static func for_class(row: Dictionary, size: float) -> ClassEmblem`.
- Produces (JSON, por classe): `lore: String`, `role: String`, `style: String`, `difficulty: int (1..3)`,
  `profile: {dano, resistencia, alcance, mobilidade, suporte: int 0..5}`, `emblem: String`.

- [ ] **Step 1: Teste que falha** — `tests/unit/test_class_emblem.gd`, carregando
  `BalanceTables.load_dir("res://data/balance")`:
  - `test_every_class_has_card_data`: para cada id em `CharRules.CLASS_IDS`: `emblem in ClassEmblem.KINDS`;
    `lore`, `role`, `style` não vazios; `difficulty` entre 1 e 3; `profile` tem exatamente as 5 chaves, cada
    valor inteiro entre 0 e 5.
  - `test_for_class_tolerates_missing_fields`: `ClassEmblem.for_class({}, 46)` devolve nó com `kind == ""`
    e `custom_minimum_size == Vector2(46, 46)` (desenha só o escudo).
- [ ] **Step 2:** `godot --headless --path . -s tests/unit/run.gd` → falha (classe inexistente).
- [ ] **Step 3: JSON.** Acrescentar os campos com os valores do mockup:

  | id | role | style | difficulty | profile (dano, resist., alcance, mobil., suporte) |
  |---|---|---|---|---|
  | warrior | Corpo a corpo | Linha de frente | 1 | 4, 5, 1, 3, 1 |
  | archer | Distância | Dano contínuo | 2 | 4, 2, 5, 4, 1 |
  | mage | Distância | Dano em área | 3 | 5, 1, 4, 2, 1 |
  | healer | Suporte | Cura e proteção | 2 | 2, 3, 3, 2, 5 |

  `lore`: os textos da aba A do mockup, sem as tags `<em>`. `emblem` = o próprio id.
- [ ] **Step 4: `ClassEmblem`.** `_draw()` chama `draw(self, kind, color, Rect2(Vector2.ZERO, size))`.
  `draw`: escudo (polígono: topo reto com pontas, laterais retas até a metade, base em curva até a ponta)
  preenchido `Color(0.07, 0.05, 0.04)`, borda dourada `Color(0.86, 0.68, 0.32)` (o valor de `UITheme.GOLD`,
  escrito direto para o script ficar puro no executor `-s`); borda interna fina na cor da classe com alfa 0.55; símbolo na cor da classe,
  centrado a 68% do escudo: warrior = espada vertical com guarda e pomo; archer = arco em curva com corda e
  flecha horizontal; mage = cajado diagonal com estrela de 4 pontas; healer = sol (disco + 8 raios).
  Coordenadas de referência: os SVGs de `EMB` no mockup (caixa 64×64). `kind` desconhecido = só escudo.
- [ ] **Step 5:** rodar os unitários → PASS.
- [ ] **Step 6: Commit** `Classes com história, perfil e emblema (ClassEmblem)`.

### Task 2: Rabo de cavalo sem erro e prévia em modo retrato

**Files:**
- Modify: `scripts/player/knight_anim.gd` (`sway_ponytail`, ~linha 252)
- Modify: `scripts/ui/char_preview.gd`

**Interfaces:**
- Produces: `CharPreview.cam: Camera3D` (hoje variável local em `_ready`),
  `func frame_face() -> void` (câmera no rosto, para de balançar),
  `func freeze_after(frames: int) -> void` (renderiza `frames` quadros e passa o viewport para
  `UPDATE_DISABLED`).

- [ ] **Step 1:** em `sway_ponytail`, trocar `get_meta("ponytail", null)` por
  `get_meta("ponytail") if model.has_meta("ponytail") else null` (o padrão `null` conta como "sem padrão" no
  Godot e gera o erro visto nas capturas).
- [ ] **Step 2:** `frame_face()`: `cam.fov = 30`, `cam.position = Vector3(0, 1.7, 1.3)`,
  `cam.look_at(Vector3(0, 1.64, 0))`, `pivot.rotation.y = -0.75`, `_user_turned = true`. Para o corpo
  feminino, mesma câmera (o recorte do mockup só deslocou a imagem; aqui a altura vem do modelo: se a cabeça
  cortar, usar a posição do osso `Head` do `_rig` em vez de 1.64).
- [ ] **Step 3:** abrir `res://scenes/char_create.tscn -- --class=warrior --body=f --hair=f_longo` com o
  console aberto, trocar Feminino/Masculino três vezes: nenhuma linha `ponytail` no console.
- [ ] **Step 4: Commit** `Prévia: modo retrato e rabo de cavalo sem erro de meta`.

### Task 3: Seletor de penteado com miniaturas

**Files:**
- Create: `scripts/ui/hair_picker.gd`

**Interfaces:**
- Consumes: `CharPreview.frame_face()`, `freeze_after()`, `show_body()`, `show_hair()`, `show_weapon()`;
  `HairStyles.STYLES`, `HairStyles.NAMES`, `HairStyles.default_for()`.
- Produces: `class_name HairPicker extends GridContainer`, `signal chosen(hair_id: String)`,
  `func set_body(body: String) -> void` (refaz as miniaturas), `func select(hair_id: String) -> void`
  (só marca, sem emitir), `var buttons := {}` (id → Button).

- [ ] **Step 1:** `columns = 2`, separação 8. `set_body` apaga os filhos e, para cada id de
  `HairStyles.STYLES[body]`, cria um `Button` toggle num `ButtonGroup`, mínimo 84×104, com um `CharPreview`
  de 80×80 (`mouse_filter = IGNORE`, `show_body(body)`, `show_hair(id)`, `show_weapon("")`, `frame_face()`,
  `freeze_after(4)`) e o nome (`HairStyles.NAMES`, 12 px, `UITheme.DIM`; o escolhido `UITheme.TEXT` e borda
  `UITheme.GOLD`). `pressed` emite `chosen(id)`.
- [ ] **Step 2:** conferido pela Task 5 (smoke) e pela captura da Task 6.
- [ ] **Step 3: Commit** `HairPicker: penteados como miniaturas do rosto`.

### Task 4: Fileira de habilidades com detalhe

**Files:**
- Create: `scripts/ui/skill_strip.gd`

**Interfaces:**
- Consumes: `ItemSlot.new(size)`, `icon_kind`, `icon_tex`, `key_text`, `ItemSlot.skill_art(id)`,
  `ItemDB.ABILITIES`, `ItemDB.kit(weapon_class)`.
- Produces: `class_name SkillStrip extends VBoxContainer`, `func show_kit(weapon_class: String) -> void`,
  `var slots: Array[ItemSlot]`, `func detail_text() -> String` (texto do detalhe mostrado).

- [ ] **Step 1:** linha de `ItemSlot.new(58)` na ordem de `ItemDB.kit()`: `icon_tex = skill_art(id)`,
  `icon_kind = a.icon` (reserva), `key_text = str(a.slot)`; selo "Nv N" no canto inferior direito quando
  `level > 1`; ultimate com borda `UITheme.GOLD`. `mouse_entered` e clique trocam o detalhe; começa no
  primeiro.
- [ ] **Step 2:** detalhe num `PanelContainer` (`UITheme.kit_inset(10)`): nome (16 px, dourado se
  ultimate), linha "Tecla N · desde o nível 1|libera no nível N · recarga X s · N mana" (sem mana quando
  `cost == 0`, "ultimate" no lugar da recarga quando `ultimate`), descrição em 13 px `DIM` com quebra.
- [ ] **Step 3: Commit** `SkillStrip: habilidades com ícone e detalhe`.

### Task 5: Montar a tela nova

**Files:**
- Modify (reescrita do `_ready` e da montagem): `scripts/ui/char_create.gd`
- Modify: `tests/smoke_test.gd` (`_test_char_create`, ~linha 3560)

**Interfaces:**
- Consumes: Tasks 1–4.
- Mantém: `enter_world`, `finished`, `cls`, `body`, `hair`, `busy`, `title_label`, `old_note`, `cards`
  (id → botão da coluna), `preview`, `class_name_label`, `name_edit`, `start_btn`, `status`,
  `select_class()`, `select_body()`, `select_hair()`, `kit_names()`, `_start()`, `_back()`, os argumentos
  `--class= --body= --hair=`.
- Produces: `hair_picker: HairPicker`, `skill_strip: SkillStrip`, `name_rule: Label`,
  `const RANDOM_NAMES := ["Arvelin", "Tessa", "Brannoc", "Ilyra", "Doran", "Maelis", "Corvo", "Selene",
  "Theodric", "Ayla"]`.

- [ ] **Step 1: smoke que falha.** Em `_test_char_create`, depois de abrir a tela:
  - `cc.cards.size() == 4` e cada valor tem um `ClassEmblem` filho;
  - `cc.hair_picker.buttons.size() == 4`; `cc.select_body("f")` → chaves de `buttons` iguais a
    `HairStyles.STYLES["f"]` e `cc.hair == HairStyles.default_for("f")`; apertar o botão `f_marias` →
    `cc.hair == "f_marias"` e `cc.preview.hair_override == "f_marias"`;
  - `cc.select_class("healer")` → `cc.skill_strip.slots.size() == ItemDB.kit("scepter").size()` e o slot de
    `scepter_lance` tem `icon_tex == null and icon_kind != ""`;
  - online não roda no smoke: testar a validação pela função pura `_name_rule(text) -> Array` (`[ok: bool,
    msg: String]`): `"Ab"` e `"Ana Luz"` e `"Abcdefghijklmnopq"` → `false`; `"Ayla"` → `true`.
  Rodar o smoke → falha.
- [ ] **Step 2: layout** (tela inteira, sem `CenterContainer`/painel):
  - fundo: o `_build_backdrop` atual; brilho radial atrás do herói tingido com a cor da classe (alfa 0.35).
  - coluna esquerda 140 px (`ScrollContainer` vertical): "CLASSES" em `GOLD_DIM` 13 px; um botão toggle por
    classe, 112×84, `ClassEmblem` 46 px + nome 11 px; o escolhido com `StyleBoxFlat` borda na cor da classe.
  - palco: título "Crie seu herói" 34 px e "A classe é para sempre. A aparência você escolhe agora." 14 px
    `DIM` no topo esquerdo; coluna "Aparência" (~180 px): rótulo, botões Masculino/Feminino, rótulo
    "Cabelo", `HairPicker`; `CharPreview` ~620×660 preenchendo o resto; botões ⟲ ⟳ embaixo (giram
    `preview.pivot` ±0.6 rad e marcam `_user_turned`) com "arraste para girar".
  - placa de nome sobre a prévia (overlay `Control` no topo da prévia): nome (17 px, branco, contorno) só no
    online, mostrando `name_edit.text` ou "Seu nome"; linha `ClassEmblem` 14 px + "Nv 1 · <Classe>" na cor
    da classe; barra de vida 110×5 `UITheme.HP`.
  - ficha à direita ~700 px: `ClassEmblem` 72 + nome 38 px na cor da classe + selos `role`, `style` e
    "Dificuldade" com losangos (1..3, cheios na cor da classe); `lore` em `UITheme.serif()` 19 px;
    `UITheme.section("Arma e atributos")`; linha "<arma> · escala com <atributo> · começa com <arma inicial>";
    grade 2 colunas com as 5 barras de 5 pontos (Dano, Resistência, Alcance, Mobilidade, Suporte);
    `UITheme.section("Habilidades")`; `SkillStrip`. Campo ausente no JSON = linha escondida.
  - aviso de personagem antigo: faixa acima do rodapé, mesmo texto de hoje.
  - rodapé 84 px: online, `name_edit` (320×40, `max_length = NAME_MAX`) + contador "n/16" + botão de dado
    (sorteia de `RANDOM_NAMES`) e `name_rule` embaixo (`DIM` vazio, `GOOD` ok, `BAD` erro, a cada
    `text_changed`); `status` no meio; "Voltar" e "Começar a jornada".
- [ ] **Step 3:** `_name_rule(text)`: vazio → `[false, "%d a %d letras ou números, sem espaços" % …]`;
  `CharacterService.clean_name(text) == ""` → `[false, CharacterService.explain_create("nome_invalido")]`;
  senão `[true, "Nome válido (a disponibilidade é vista ao criar)"]`. `_start()` usa o mesmo.
- [ ] **Step 4:** `select_body` chama `hair_picker.set_body(b)` antes de `select_hair(default_for(b))`;
  `select_hair` chama `hair_picker.select(h)`; o `--hair=` inicial marca a miniatura certa.
- [ ] **Step 5:** smoke → PASS (o resto de `_test_char_create`, inclusive "Começar", continua passando).
- [ ] **Step 6: Commit** `Criação de herói: palco central, ficha da classe e nome validado`.

### Task 6: Capturas, versão e testes completos

**Files:**
- Modify: `project.godot` (`config/version`)

- [ ] **Step 1:** capturas a 1600×900: `res://scenes/char_create.tscn -- --class=<c> --body=<b> --shot=…`
  para as 4 classes × m/f; uma a 1280×720. Comparar lado a lado com o mockup (coluna, herói, ficha, rodapé)
  e conferir que nada corta e que a miniatura escolhida bate com o cabelo do herói.
- [ ] **Step 2:** `config/version="0.51.0"`.
- [ ] **Step 3:** `/smoke-check` (unitários, smoke, vila, multiplayer) → PASSOU em tudo (projéteis: rodar de
  novo antes de culpar a mudança).
- [ ] **Step 4: Commit** `Versão 0.51.0` e abrir PR com as capturas.
