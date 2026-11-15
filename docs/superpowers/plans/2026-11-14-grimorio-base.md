# Grimório, etapa 1 (base) — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transformar o teste do inventário em livro numa base reaproveitável: um componente `BookWindow`, um tema de papel completo, fonte embutida e ícones 3D guardados em disco, sem as peças de aço do primeiro teste.

**Architecture:** As medidas do livro e a regra "cabe na página" ficam num script puro (`BookLayout`), testado no executor unitário. `BookWindow` (um `Control`) desenha o livro, as abas de marcador e o botão de fechar, empilha as páginas e avisa quando uma não cabe. `game_menu.gd` passa a só construir as páginas e entregá-las ao `BookWindow`. O tema de papel e a fonte vivem em `UITheme`; os ícones 3D ganham um cache em `user://`.

**Tech Stack:** Godot 4.7.2 (GDScript), Blender 5.2 em modo `--background` para as imagens, testes em `tests/unit` (executor `-s`) e `tests/smoke_test.gd`.

**Spec:** `docs/INTERFACE_GRIMORIO.md`

## Global Constraints

- Trabalhar na worktree `C:\Games\godot-3d-ui`, branch `ui-teste`. Nunca `git stash` nem trocar de branch na pasta principal.
- O HUD de jogo não muda: `hud.gd`, `hub_hud.gd`, `survival_hud.gd`, `colony_hud.gd`, `chat_ui.gd`, `stat_orb.gd`, `fury_ring.gd`, `horde_icon.gd`.
- Livro: imagem única de 1408×800. Margens das páginas: 88 px nos lados, 62 em cima e embaixo, 84 de lombada.
- Sobre papel o texto é tinta sem contorno: `INK` (0.2, 0.125, 0.065), `INK_DIM` (0.42, 0.31, 0.19), `INK_RED` (0.55, 0.11, 0.07).
- Script puro (carregado pelo executor unitário com `-s`) não pode citar autoload (`Game`, `ItemDB`, ...): o arquivo deixa de compilar e o teste some em silêncio.
- A mochila precisa ter 54 espaços ou mais (`tests/smoke_test.gd:2356`).
- Comentários, nomes de teste e mensagens em português, como no resto do projeto.
- Comandos: `G="C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe"`, `B="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"`. Depois de criar ou trocar imagem ou fonte: `"$G" --headless --path . --import`.
- Não matar todos os processos do Godot; encerrar só o PID que o próprio passo abriu.
- Teste de projétil do smoke test falha cerca de 1 vez em 4 sem relação com a mudança: rodar de novo antes de culpar o código.

## Review Focus

1. **Janela menor que 1600×900:** o livro inteiro encolhe por escala e continua inteiro na tela (teste na Task 2).
2. **Servidor dedicado e testes sem janela (`--headless`):** `ItemIcons` não cria `SubViewport` nem grava nada; o espaço mostra o ícone pintado (teste na Task 6).
3. **Arquivo de ícone corrompido ou de outra versão do jogo no cache:** é ignorado e o ícone é refeito, sem erro (teste na Task 6).
4. **Fonte ausente ou que não carrega:** títulos e texto caem na fonte do sistema, sem erro (teste na Task 5).
5. **Página que pede mais espaço que o livro:** nada passa das margens; a página rola e um aviso sai no log (testes nas Tasks 2 e 3).

---

### Task 1: Ponto de partida limpo

Registra o teste como está e tira as peças de aço, que nenhuma tela usa mais.

**Files:**
- Modify: `scripts/ui/ui_theme.gd` (remover `STEEL_TEXT`, `window_box`, `forged_inset`, `forged_theme`, `_forged`)
- Modify: `scripts/ui/item_slot.gd` (remover `forged`, `_forged_box`, `_draw_forged`)
- Modify: `scripts/ui/game_menu.gd` (`_inset()` volta a `UITheme.inset_box(14)`; tema raiz volta a `UITheme.get_theme()`)
- Modify: `tools/blender/ui_kit.py` (remover `window`, `inset`, `slot`, `button`, `crest`, `corner`, `bracket`, `hook`, `blade`, `hexa`, `gem`, `enamel`, os três `STEEL*`; o script passa a gerar só o livro e as abas, sem a opção `--book`)
- Delete: `assets/ui/window.png`, `inset.png`, `slot.png`, `button_*.png`, `crest.png` e os `.import` deles; pasta `shots/`
- Modify: `.gitignore` (acrescentar `/shots/`)

- [ ] **Step 1:** Commit do teste como está: `git add -A && git commit -m "Teste do grimório no inventário (descartável)"`.
- [ ] **Step 2:** Fazer as remoções acima. `tex()` e `_tex_box()` ficam em `UITheme`.
- [ ] **Step 3:** Verificar que não sobrou uso: `grep -rn "forged\|STEEL_TEXT\|window_box" scripts tools` não devolve nada.
- [ ] **Step 4:** `"$G" --headless --path . --import 2>&1 | grep -c "SCRIPT ERROR"` devolve `0`.
- [ ] **Step 5:** Regenerar as imagens e conferir que o script ainda roda: `"$B" --background --factory-startup --python tools/blender/ui_kit.py -- "$PWD/assets/ui"` imprime `UI_KIT_OK`.
- [ ] **Step 6:** Commit: `git commit -am "Grimório: remove as peças de aço do primeiro teste"`.

---

### Task 2: `BookLayout`, as medidas do livro

**Files:**
- Create: `scripts/ui/book_layout.gd`
- Test: `tests/unit/test_book_layout.gd`

**Interfaces:**
- Produces (script puro, `class_name BookLayout extends RefCounted`):
  - `const SIZE := Vector2(1408, 800)`, `const SIDE := 88.0`, `const TOP := 62.0`, `const SPINE := 84.0`
  - `static func content_room() -> Vector2` — área das duas páginas juntas: `(1232, 676)`
  - `static func page_room() -> Vector2` — uma página: `(574, 676)`
  - `static func fits(need: Vector2) -> bool` — `need` cabe em `content_room()`
  - `static func scale_for(viewport: Vector2) -> float` — escala do livro para caber na janela com 16 px de folga em cada lado, nunca maior que 1

- [ ] **Step 1: Escrever o teste que falha**

```gdscript
extends RefCounted
## BookLayout: medidas do livro e a regra "cabe na página".


func test_room() -> void:
	T.eq(BookLayout.content_room(), Vector2(1232, 676), "área das duas páginas")
	T.eq(BookLayout.page_room(), Vector2(574, 676), "área de uma página")


func test_fits() -> void:
	T.ok(BookLayout.fits(Vector2(1232, 676)), "do tamanho exato cabe")
	T.ok(not BookLayout.fits(Vector2(1233, 100)), "1 px mais largo não cabe")
	T.ok(not BookLayout.fits(Vector2(100, 677)), "1 px mais alto não cabe")


func test_scale() -> void:
	T.eq(BookLayout.scale_for(Vector2(1600, 900)), 1.0, "tela de projeto: sem escala")
	T.eq(BookLayout.scale_for(Vector2(3840, 2160)), 1.0, "tela grande não amplia")
	T.ok(is_equal_approx(BookLayout.scale_for(Vector2(1280, 720)), 688.0 / 800.0), "720p encolhe pela altura")
	T.ok(is_equal_approx(BookLayout.scale_for(Vector2(1000, 900)), 968.0 / 1408.0), "janela estreita encolhe pela largura")
	T.ok(BookLayout.scale_for(Vector2(0, 0)) > 0.0, "janela minimizada não zera a escala")
```

- [ ] **Step 2:** Rodar `"$G" --headless --path . -s tests/unit/run.gd 2>&1 | tail -15`. Esperado: falha citando `BookLayout`.
- [ ] **Step 3:** Implementar `scripts/ui/book_layout.gd` com a interface acima. Piso da escala: 0.25.
- [ ] **Step 4:** Rodar de novo. Esperado: os três testes de `test_book_layout` passam e a contagem de arquivos de teste subiu em 1 (se não subiu, o arquivo não compilou).
- [ ] **Step 5:** Commit: `git add scripts/ui/book_layout.gd* tests/unit/test_book_layout.gd* && git commit -m "Grimório: medidas do livro (BookLayout)"`.

---

### Task 3: `BookWindow` e o menu do herói em cima dele

**Files:**
- Create: `scripts/ui/book_window.gd`
- Modify: `scripts/ui/game_menu.gd` (o `_ready` e o `_build_header` atuais saem; ficam os construtores de página e os `_refresh_*`)
- Modify: `tests/smoke_test.gd:2353-2362`

**Interfaces:**
- Consumes: `BookLayout` (Task 2); `UITheme.tex`, `UITheme.paper_theme`, `UITheme.INK*`.
- Produces (`class_name BookWindow extends Control`):
  - `signal closed`
  - `signal page_shown(index: int)`
  - `func add_page(title: String, key: String, action: String, page: Control, on_paper := true) -> void` — `key` é a letra mostrada na aba; `action` é a ação de entrada que abre a aba (`""` = nenhuma); `on_paper` aplica `paper_theme()` à página
  - `func show_page(index: int) -> void`
  - `func current_page() -> int`
  - `func close() -> void` — emite `closed` e se libera
  - `func content_rect() -> Rect2` — retângulo global da área das páginas, já com a escala
  - `var overflow_warnings := 0` — quantas vezes uma página não coube (para os testes)
- `game_menu.gd` mantém a interface que `world.gd`, `colony_world.gd` e o smoke test usam: `signal closed`, `var start_tab`, `equip_slots`, `bag_slots`, `_show_tab(i)`, `_close()`.

Comportamento que o `BookWindow` assume (hoje está espalhado em `game_menu.gd`):
- fundo escurecido (0, 0, 0, 0.62), livro centralizado, `process_mode = PROCESS_MODE_ALWAYS`;
- escala `BookLayout.scale_for(get_viewport_rect().size)` aplicada ao livro, refeita no sinal `resized`;
- abas de marcador sobre a página direita (`tab_on` na ativa, `tab_off` nas outras), com o nome e a tecla (`Inventário  I`);
- cada página fica dentro de um `ScrollContainer` só vertical, de modo que conteúdo alto demais rola em vez de sair do livro;
- ao mostrar uma página, espera dois quadros, mede `get_combined_minimum_size()` dela e, se `not BookLayout.fits(...)`, soma 1 em `overflow_warnings` e chama `push_warning` com o nome da aba e os dois tamanhos;
- `Esc` (ação `pause`) fecha; a ação de uma aba troca para ela, ou fecha se ela já está aberta.

Mochila: `BAG_COLS := 8`, `BAG_MIN := 56`, `SLOT := 62.0` (7 linhas; a grade rola dentro da página).

- [ ] **Step 1: Trocar a verificação do smoke test pelo teste que falha**

```gdscript
	world._open_menu(0)
	await wait(0.15)
	var m = world.modal
	check(m != null and m.equip_slots.size() == 8 and m.bag_slots.size() >= 54, "inventário com boneco (8 espaços) e grade")
	check(m.equip_slots.head.item_id == "leather_cap", "boneco mostra o capuz equipado")
	var book: BookWindow = m.book
	check(book != null and book.current_page() == 0, "menu do herói abre no livro, na aba Inventário")
	for i in 3:
		m._show_tab(i)
		await wait(0.1)
		var area := book.content_rect().grow(1.0)
		var page_rect: Rect2 = m.pages[i].get_global_rect()
		check(book.current_page() == i and area.encloses(page_rect), "aba %d fica dentro das páginas do livro" % i)
	check(book.overflow_warnings == 0, "nenhuma aba pede mais espaço do que o livro tem")
	m._close()
```

- [ ] **Step 2:** Rodar `"$G" --headless --path . res://scenes/world.tscn -- --smoketest 2>&1 | grep -i "FALHOU\|inventário\|livro" | head`. Esperado: falha em `m.book`.
- [ ] **Step 3:** Implementar `scripts/ui/book_window.gd` com a interface e o comportamento acima.
- [ ] **Step 4:** Reescrever `game_menu.gd._ready`: criar `book := BookWindow.new()`, `add_page` para `["Inventário","I","inventory"]`, `["Personagem","C","character"]`, `["Missões","J","quest_log"]` (as duas últimas com `on_paper = false` até a etapa 2), ligar `book.closed` a `_close`, `book.show_page(start_tab)`. `_show_tab(i)` delega a `book.show_page(i)`. Remover `_unhandled_input`, `_build_header` e a medição de tamanho, que passam a ser do livro.
- [ ] **Step 5:** Rodar o smoke test. Esperado: as verificações novas passam e o total de falhas é 0 (rodar de novo se só um teste de projétil falhar).
- [ ] **Step 6:** Capturas das três abas com `--geardemo --ui=inv|char|quests --shot=shots/<aba>.png --delay=8` e de uma janela pequena com `--resolution 1280x720`; conferir que o livro aparece inteiro.
- [ ] **Step 7:** Commit: `git add -A && git commit -m "Grimório: BookWindow e menu do herói sobre ele"`.

---

### Task 4: Tema de papel completo

Hoje `paper_theme()` cobre botão, rótulo, separador e barra de rolagem. As telas das próximas etapas usam também lista, abas, barra de progresso, deslizador, campo de texto, caixa de marcar, seletor e texto rico.

**Files:**
- Modify: `scripts/ui/ui_theme.gd`
- Test: `tests/unit/test_ui_theme.gd` (novo)

**Interfaces:**
- Produces:
  - `UITheme.paper_theme() -> Theme` com caixas de estilo para: `Button`, `Label`, `HSeparator`, `VSeparator`, `VScrollBar`, `ItemList`, `TabContainer`, `ProgressBar`, `HSlider`, `LineEdit`, `CheckBox`, `OptionButton`, `PopupMenu`, `RichTextLabel`, `TooltipPanel`, `TooltipLabel`
  - `static func ink_section(text: String, size := 18) -> HBoxContainer` — título vermelho na serifada com linha a tinta (o par de `section()`)
  - `static func ink_bar(color: Color, w: float, h: float) -> ProgressBar` — barra com fundo de tinta clara
  - `static func ink_inset(margin := 12) -> StyleBoxFlat` — quadro a tinta para subdividir uma página

- [ ] **Step 1: Escrever o teste que falha**

```gdscript
extends RefCounted
## Tema de papel: todo controle usado nas telas do livro tem estilo próprio e texto a tinta.


func test_paper_theme_covers_controls() -> void:
	var t := UITheme.paper_theme()
	for pair in [["normal", "Button"], ["panel", "ItemList"], ["selected", "ItemList"], ["panel", "TabContainer"],
			["tab_selected", "TabContainer"], ["background", "ProgressBar"], ["slider", "HSlider"],
			["normal", "LineEdit"], ["focus", "LineEdit"], ["normal", "OptionButton"], ["panel", "PopupMenu"],
			["panel", "TooltipPanel"]]:
		T.ok(t.has_stylebox(pair[0], pair[1]), "estilo %s de %s" % pair)


func test_paper_text_is_ink() -> void:
	var t := UITheme.paper_theme()
	for type in ["Label", "Button", "ItemList", "LineEdit", "CheckBox", "OptionButton", "PopupMenu", "TooltipLabel"]:
		T.eq(t.get_color("font_color", type), UITheme.INK, "texto de %s é tinta" % type)
	T.eq(t.get_color("default_color", "RichTextLabel"), UITheme.INK, "texto rico é tinta")


func test_paper_theme_leaves_dark_theme_alone() -> void:
	T.eq(UITheme.get_theme().get_color("font_color", "Label"), UITheme.TEXT, "tema escuro continua claro")
```

- [ ] **Step 2:** Rodar o executor unitário. Esperado: falhas em `ItemList`, `LineEdit` e companhia.
- [ ] **Step 3:** Completar `paper_theme()` e criar `ink_section`, `ink_bar`, `ink_inset`. Selecionado e pressionado usam tinta cheia com texto `PAGE`; foco é borda `INK` de 2 px.
- [ ] **Step 4:** Rodar de novo. Esperado: passa, e a contagem de arquivos de teste subiu em 1.
- [ ] **Step 5:** Commit: `git commit -am "Grimório: tema de papel completo" && git add tests/unit/test_ui_theme.gd*`.

---

### Task 5: Fonte embutida

Baixar arquivo precisa da autorização do dono do projeto: confirmar antes do Step 1, dizendo nome, origem e tamanho de cada arquivo.

**Files:**
- Create: `assets/fonts/Cinzel.ttf`, `assets/fonts/EBGaramond.ttf`, `assets/fonts/OFL.txt` (licença das duas)
- Modify: `scripts/ui/ui_theme.gd` (`serif()`; novo `body()`; `paper_theme()` usa `body()` como fonte padrão)
- Test: `tests/unit/test_ui_theme.gd`

**Interfaces:**
- Produces:
  - `UITheme.serif() -> Font` — Cinzel; se o arquivo não existir ou não carregar, a `SystemFont` de hoje
  - `UITheme.body() -> Font` — EB Garamond; mesmo recuo para `SystemFont`
  - `static func _load_font(path: String, fallback: Array) -> Font` — o recuo, testável

- [ ] **Step 1: Acrescentar os testes que falham**

```gdscript
func test_fonts_are_bundled() -> void:
	T.ok(UITheme.serif() is FontFile, "título usa a fonte embutida, não a do sistema")
	T.ok(UITheme.body() is FontFile, "texto usa a fonte embutida")


func test_font_fallback() -> void:
	var f := UITheme._load_font("res://assets/fonts/nao_existe.ttf", ["Georgia", "serif"])
	T.ok(f is SystemFont, "fonte ausente cai na do sistema sem erro")
```

- [ ] **Step 2:** Rodar o executor unitário. Esperado: os dois testes falham.
- [ ] **Step 3:** Com a autorização, baixar as fontes (Google Fonts, licença OFL) para `assets/fonts`, com o texto da licença. Rodar `--import`.
- [ ] **Step 4:** Implementar `_load_font`, `serif()` e `body()`.
- [ ] **Step 5:** Rodar de novo. Esperado: passa.
- [ ] **Step 6:** Captura do inventário; conferir que acentos e cedilha aparecem (`Inventário`, `Missões`, `Crítico`, `Poder mágico`).
- [ ] **Step 7:** Commit: `git add -A && git commit -m "Grimório: fontes embutidas (Cinzel e EB Garamond)"`.

---

### Task 6: Ícones 3D guardados em disco

Hoje cada ícone é refeito a cada execução do jogo e chega um por vez. Passam a ser lidos de `user://` e só os que faltam são fotografados.

**Files:**
- Create: `scripts/ui/icon_cache.gd`
- Modify: `scripts/ui/item_icons.gd`
- Test: `tests/unit/test_icon_cache.gd`; `tests/smoke_test.gd` (uma verificação)

**Interfaces:**
- Produces (script puro, `class_name IconCache extends RefCounted`):
  - `static func path_for(root: String, version: String, id: String) -> String` — `"<root>/<version>/<id>.png"`
  - `static func load_icon(root: String, version: String, id: String) -> Texture2D` — `null` se o arquivo não existe ou não é um PNG válido
  - `static func save_icon(root: String, version: String, id: String, img: Image) -> bool`
  - `static func prune(root: String, keep_version: String) -> int` — apaga as pastas de outras versões; devolve quantas apagou
- `ItemIcons` (já existe):
  - `const ROOT := "user://icons"`
  - `static func enabled() -> bool` — falso com `DisplayServer.get_name() == "headless"`
  - `icon()` consulta `IconCache.load_icon` antes de enfileirar e chama `save_icon` depois de fotografar; devolve `null` sem enfileirar quando `not enabled()`
  - `static func prewarm(ids: Array) -> void` — enfileira de uma vez os que faltam

- [ ] **Step 1: Escrever o teste que falha**

```gdscript
extends RefCounted
## IconCache: ícones de item guardados em disco, por versão do jogo.

const ROOT := "user://test_icons"


func _clean() -> void:
	IconCache.prune(ROOT, "")


func test_roundtrip() -> void:
	_clean()
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	T.ok(IconCache.load_icon(ROOT, "1.0.0", "sword") == null, "sem arquivo devolve null")
	T.ok(IconCache.save_icon(ROOT, "1.0.0", "sword", img), "salva")
	var tex := IconCache.load_icon(ROOT, "1.0.0", "sword")
	T.ok(tex != null and tex.get_width() == 8, "lê o que salvou")
	_clean()


func test_other_version_is_ignored_and_pruned() -> void:
	_clean()
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	IconCache.save_icon(ROOT, "1.0.0", "sword", img)
	T.ok(IconCache.load_icon(ROOT, "1.1.0", "sword") == null, "ícone de outra versão não vale")
	T.eq(IconCache.prune(ROOT, "1.1.0"), 1, "apaga a pasta da versão antiga")
	T.ok(IconCache.load_icon(ROOT, "1.0.0", "sword") == null, "o arquivo antigo sumiu")


func test_corrupt_file_is_ignored() -> void:
	_clean()
	var p := IconCache.path_for(ROOT, "1.0.0", "sword")
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string("isto não é um png")
	f.close()
	T.ok(IconCache.load_icon(ROOT, "1.0.0", "sword") == null, "arquivo corrompido devolve null, sem erro")
	_clean()


func test_id_cannot_escape_the_folder() -> void:
	T.ok(not IconCache.path_for(ROOT, "1.0.0", "../../save").contains(".."), "id com .. não sai da pasta")
```

- [ ] **Step 2:** Rodar o executor unitário. Esperado: falha citando `IconCache`.
- [ ] **Step 3:** Implementar `scripts/ui/icon_cache.gd`. `path_for` troca por `_` tudo que não for letra, número, `_` ou `-` em `id` e `version`. `load_icon` usa `Image.load_png_from_buffer` e confere o código de erro.
- [ ] **Step 4:** Rodar de novo. Esperado: os quatro testes passam.
- [ ] **Step 5:** Ligar o cache em `item_icons.gd` (versão = `ProjectSettings.get_setting("application/config/version")`), criar `enabled()` e `prewarm()`; chamar `IconCache.prune` uma vez, quando o nó é criado. `game_menu.gd` chama `ItemIcons.prewarm` com os ids do inventário e do equipamento ao abrir.
- [ ] **Step 6:** Acrescentar ao smoke test, junto das verificações do inventário: `check(not ItemIcons.enabled() and ItemIcons.icon("leather_cap", Callable()) == null, "sem janela, os ícones 3D ficam desligados")`. Rodar o smoke test. Esperado: passa.
- [ ] **Step 7:** Abrir o inventário duas vezes com `--geardemo --ui=inv --shot=... --delay=2`: na segunda, com só 2 s de espera, todos os ícones de equipamento já aparecem.
- [ ] **Step 8:** Commit: `git add -A && git commit -m "Grimório: ícones 3D guardados em disco"`.

---

### Task 7: Pergaminho e fecho

**Files:**
- Modify: `tools/blender/ui_kit.py` (função `paper` e `book`)
- Modify: `assets/ui/book.png`
- Modify: `docs/INTERFACE_GRIMORIO.md` (etapa 1 como feita; "O que existe" atualizado; decisões resolvidas)
- Modify: `project.godot` (`config/version`, o próximo número livre depois de conferir `origin/main`)

- [ ] **Step 1:** No material do papel: manchas mais fortes (rampa de 0.3–0.68 para 0.22–0.6, segunda camada de ruído em escala 6), escurecimento de borda mais largo. No livro: bordas das páginas irregulares (contorno com 40 pontos por lado deslocados por ruído de até 0.02 unidade) e uma vinheta a tinta nos quatro cantos de cada página (arabesco de duas curvas, material `flat` marrom com alfa 0.35).
- [ ] **Step 2:** Regenerar, importar e capturar o inventário. Conferir na captura: o texto continua legível em toda a página, inclusive junto da lombada; as vinhetas ficam fora da área de conteúdo (margens da seção Global Constraints).
- [ ] **Step 3:** Rodar `/smoke-check rapido`. Esperado: tudo `PASSOU`.
- [ ] **Step 4:** Atualizar `docs/INTERFACE_GRIMORIO.md` e a versão.
- [ ] **Step 5:** Commit: `git add -A && git commit -m "Grimório: pergaminho com bordas gastas e vinhetas; etapa 1 concluída"`.

---

## Fica para depois

- Variante de página única do `BookWindow` (convite, recordes): entra na etapa 7, quando a primeira tela pequena migrar.
- Personagem e Missões a tinta, atalhos na dica de item: etapa 2.
- Ícones de itens sem modelo 3D: etapa 3.
- Causa do `draw_texture_rect` branco em `ItemSlot._draw`: só investigar se voltar a aparecer.
