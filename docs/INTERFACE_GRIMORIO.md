# Interface "grimório" — o que aprendemos e plano de migração

Estado em 14/11/2026: a base (etapa 1), o menu do herói (etapa 2) e os ícones 3D de todos os itens (etapa 3)
estão prontos; as telas migram uma etapa por vez. O HUD de jogo fica como está.
Todo o resto da interface (menus, inventário, lojas, ofícios, diálogos, telas da colônia e da Horda) migra
para a aparência de um livro: páginas de pergaminho, texto a tinta, abas de marcador.

## Por quê

A interface inteira era desenhada por código com caixas de cor chapada (`UITheme`, só `StyleBoxFlat`), sem
nenhuma imagem nem fonte própria. O resultado funcionava, mas tinha cara de página web. O objetivo é dar ao
jogo uma identidade de RPG sem comprar um kit pronto: a arte é nossa.

- **Objetivo:** menus com material e silhueta próprios; ícones que mostram o item de verdade.
- **Fora do escopo:** o HUD de jogo (barras, barra de ações, minimapa), que já agrada; regras de jogo; rede.
- **O que seria um fracasso:** conteúdo passando por cima da moldura; telas com estilos misturados por muito
  tempo; texto ilegível sobre o papel; perda de função (arrastar, atalhos, dicas) na troca de layout.

## Caminhos considerados

| Caminho | Resultado |
|---|---|
| Kit pronto comprado (Dark Lands) | descartado pelo dono do projeto: arte própria |
| Moldura de aço renderizada no Blender, em 9 fatias | testado; "muito quadrado e genérico". A borda mudou, a silhueta não |
| Pedra e ferro (Diablo), estandartes e placas (Ni no Kuni), sem janela (Persona, Zelda) | esboçados, não escolhidos |
| **Grimório: livro aberto, pergaminho, tinta, marcadores** (Pentiment, mapas do Baldur's Gate clássico) | **escolhido** depois do teste no inventário |

Como a arte é feita: peças modeladas no Blender e renderizadas de frente em PNG (`tools/blender/ui_kit.py`);
texto, botões e quadros são desenhados a tinta por código sobre o papel. SVG e shader em tempo real foram
descartados: o primeiro fica "vetorial" demais, o segundo é caro para ornamento curvo.

## O que o teste ensinou

1. **Trocar a borda não basta.** Moldura nova em volta do mesmo retângulo com retângulos dentro continua
   genérica. O que muda a cara é a silhueta (livro, abas saindo do topo) e o material (papel, couro, latão).
2. **O livro é uma imagem só, de tamanho fixo** (1408×800), e o conteúdo vive dentro das margens das
   páginas (88 px nos lados, 62 em cima e embaixo, 84 de lombada). Nove fatias não servem para um livro.
3. **Vazamento na borda:** a área das páginas era um `Control` comum, que não informa o tamanho mínimo do
   conteúdo; a página crescia para fora. Tem que ser um contêiner (`PanelContainer` com `StyleBoxEmpty`).
4. **Com tamanho fixo, a garantia é um aviso:** `game_menu.gd` mede a página visível dois quadros depois de
   abrir e emite `push_warning` se ela pedir mais espaço do que cabe. Página escondida não foi diagramada e
   dá falso alarme (rótulos com quebra de linha medem milhares de pixels de altura).
5. **Sobre papel, tudo é tinta.** Texto marrom-escuro sem contorno, títulos na serifada, vermelho para
   rótulos de seção. Botão é um quadro a tinta; ativo, vira tinta cheia com texto cor de papel.
6. **Fundo escuro no espaço de item destoa.** O espaço é papel tingido de leve pela cor da raridade, com a
   borda na mesma cor.
7. **Ícone = o modelo 3D do item.** `ItemIcons` monta a arma ou a peça como o jogo monta no cavaleiro
   (`KnightLook._build_sword`, `_attach_gear`), fotografa num `SubViewport` de 192 px e guarda a textura.
   Item novo ganha ícone sozinho, já no estilo toon.
   - Os GLBs de equipamento trazem partes do corpo (rosto sob o capuz, pescoço da cota): malha só com
     materiais `g_skin`, `g_hair`, `g_eye`, `g_sclera`, `g_lip` fica escondida.
   - Luvas: mostra só o lado direito.
   - Arma comprida e fina vira um risco: a largura é engordada até uns 3,5:1.
   - Os ícones chegam um por vez (6 quadros cada); o espaço mostra o ícone pintado até lá.
8. **`draw_texture_rect` dentro de `ItemSlot._draw` saiu branco** com a textura do espaço de aço; com
   `StyleBoxTexture` funcionou. Causa não investigada.
9. **Não existe lugar livre dentro da página para o botão de fechar.** O conteúdo vai até a margem e a
   vinheta ocupa o canto; o "✕" solto ficava colado nela e por cima de qualquer linha que chegasse ao canto.
   Ele virou um marcador curto no fim da fila de abas, fora do papel: nenhuma página precisa desviar dele.
10. **Cor clara do tema escuro some no papel.** Verde, azul e dourado claros (raridade, bônus, elemento)
    viram a mesma ideia escurecida (`UITheme.on_paper()`); o comum, que é branco, vira tinta pura. Selo de
    cor cheia com texto escuro destoa: o aviso de pontos a distribuir é um quadro de tinta vermelha.
11. **Uma abertura = duas colunas que expandem** dentro de um `HBoxContainer` com `separation = SPINE`.
    Elas só ficam iguais enquanto o mínimo de cada uma cabe em `page_room()`; rótulo comprido sem quebra
    empurra a lombada. O smoke test mede as duas metades de cada aba.
12. **Página refeita a cada mudança:** `queue_free()` sozinho deixa o conteúdo velho na página até o fim do
    quadro (a página mede o dobro e o aviso de tamanho dispara). Tirar com `remove_child` antes.
13. **A Garamond embutida não tem itálico nem ★ ◆ ✓ ✕:** os símbolos vêm da fonte do sistema (funciona,
    mas "✔" vira emoji colorido; usar "✓") e o itálico da dica é a fonte normal inclinada (`FontVariation`).
14. **Espaço de item sobre papel:** apagado (`dim`) desbota para a cor da página em vez de escurecer, e o
    selo da tecla é tinta cheia.
15. **Blender:** metal precisa de mundo com degradê para refletir algo; papel precisa de um pouco de emissão
   para não sair escuro; `use_nodes` está marcado para sair no Blender 6.
16. **Item sem modelo ganha um modelo de família, não um desenho.** Poções, comida, colheitas, sementes,
    materiais, anéis, amuletos, orbe e aljava (42 itens) usam 30 GLBs pequenos de `assets/models/items`,
    fotografados pelo mesmo `ItemIcons`. O ícone vetorial ao lado do 3D destoava; agora ele só aparece
    enquanto o 3D não chega e no modo sem janela.
    - **A cor vem do item, pelo nome do material.** No GLB, `i_tint` recebe a cor do item, `i_tint_dark` e
      `i_tint_light` a mesma cor escurecida e clareada (sombra e brilho pintados) e `i_tint_glow` a cor com
      brilho próprio (orbe, cristal, brasa). Os outros materiais ficam como saíram do Blender. Assim as
      duas poções dividem o frasco, os anéis o aro, as sementes o saquinho, os caldos a tigela.
    - **A tabela item → modelo/cor é um script puro** (`ItemIconModels`, sem autoload), com teste unitário:
      todo item de `data/balance` tem ícone 3D e o arquivo do modelo existe. Item novo cai no modelo do
      tipo (material novo vira gosma, comida nova vira tigela) até ganhar uma linha própria.
    - **Enquadrar pela caixa deixa a peça pequena.** A caixa de uma peça redonda ou inclinada, vista em três
      quartos, é bem maior que a silhueta. Os modelos de família são enquadrados pelos vértices projetados
      no plano da câmera, com 20% de folga.
    - **Peça baixa e larga pede câmera mais de cima.** Torta, travessa, tigela, pão e monte de pó viravam
      uma faixa fina vistos de frente (`VIEW_TOP`); o resto fica de frente, em três quartos (`VIEW_FRONT`).
    - **Cor clara sobre papel some.** Caneca creme, osso e pão claros ficavam sem leitura no pergaminho: a
      caneca virou madeira e as peças claras ganharam a parte de baixo em `i_tint_dark`.
    - **Silhueta simétrica com miolo escuro lê como folha.** A orelha de goblin só virou orelha com a dobra
      de cima em relevo, a concha fora do centro, o corte rosado na base e o brinco.
    - **Material translúcido não entra no toon:** o vidro da poção é opaco e claro, com o líquido como
      outra faixa do mesmo sólido.
    - **O cache de ícones é por versão do jogo.** Ao mexer num modelo sem subir a versão, apague
      `user://icons/<versão>` ou o ícone antigo continua aparecendo.
    - **Fora do papel também:** `ItemSlot.model_icon = true` liga o ícone 3D num espaço do tema escuro (a
      loja usa). O HUD continua no desenho vetorial.

## O que existe

| Peça | Onde |
|---|---|
| Livro aberto e abas de marcador (PNG) | `assets/ui/book.png`, `tab_on.png`, `tab_off.png` |
| Gerador das imagens | `tools/blender/ui_kit.py` |
| Medidas do livro, regra "cabe na página", escala para janela pequena | `scripts/ui/book_layout.gd` |
| Janela-livro: abas, marcador de fechar, rolagem, aviso de página grande demais | `scripts/ui/book_window.gd` |
| Fontes embutidas: Cinzel (títulos, peso 600) e EB Garamond (texto), licença OFL | `assets/fonts`, `UITheme.serif()` e `UITheme.body()` |
| Tema de papel, cores de tinta, `ink()`, `ink_section()`, `ink_bar()`, `ink_inset()`, `on_paper()` | `scripts/ui/ui_theme.gd` |
| Espaço de item sobre papel (`paper = true`) | `scripts/ui/item_slot.gd` |
| Ícones 3D, guardados em `user://icons/<versão>` | `scripts/ui/item_icons.gd`, `scripts/ui/icon_cache.gd` |
| Tabela item → modelo de família, cor e ponto de vista (script puro) | `scripts/ui/item_icon_models.gd` |
| Modelos de família dos itens sem modelo de equipamento (30 GLBs) | `assets/models/items`, gerados por `tools/blender/item_icons.py` |
| Ícone vetorial de reserva (sem janela, HUD e enquanto o 3D não chega) | `scripts/ui/icon_painter.gd` |
| Dica de item em folha de papel (`paper = true`; o padrão continua escuro para loja e HUD) | `scripts/ui/item_tooltip.gd` |
| Menu do herói, as três abas a tinta (`_spread()` monta as duas páginas de uma aba) | `scripts/ui/game_menu.gd` |
| Livro do mapa e do social: aba Mapa (M, região vista de cima, seletor de mapas, legenda e lugares), aba Grupo (P, membros, convite, quem está online) e aba Amigos (O, pedidos, amigos online/offline, chamar ao grupo, sussurrar) | `scripts/ui/world_map_ui.gd` (o desenho do mapa é `map_view.gd`, a foto de cima `map_capture.gd`) |

Para criar uma tela nova no livro:

```gdscript
var book := BookWindow.new()
add_child(book)
book.add_page("Loja", "", "", minha_pagina)      # título, tecla na aba, ação de entrada, conteúdo
book.closed.connect(_close)
book.show_page(0)
```

Uma página ocupa `BookLayout.content_room()` (1232×676); cada metade tem `page_room()` (574×676) e as duas
ficam separadas por `BookLayout.SPINE`. Conteúdo maior rola e gera um aviso no log.

## Plano de migração

Cada etapa é um PR, sai com as capturas das telas tocadas e com `/smoke-check` passando.

| Etapa | O que | Telas | Estado |
|---|---|---|---|
| 0 | Teste no inventário | `game_menu.gd` (aba Inventário) | feito |
| 1 | **Base.** Refazer o teste como código de verdade: componente `BookWindow` (livro, margens, abas, fechar, aviso de tamanho), tema de papel completo (lista, abas, barra, deslizador, campo de texto), fonte embutida, remover as peças de aço | `ui_theme.gd`, `item_slot.gd`, `item_icons.gd`, novo `book_window.gd` | feito |
| 2 | **Menu do herói inteiro no livro:** Inventário, Personagem e Missões a tinta; atalhos I/C/J nas abas; dica de item em pergaminho; fechar como marcador | `game_menu.gd`, `item_tooltip.gd`, `book_window.gd` (`skill_icon.gd` é só da Horda e não precisou mudar) | feito |
| 3 | **Ícones dos itens sem modelo:** poções, comida, colheitas, anéis, amuletos, orbe, aljava, materiais, sementes; a loja também passa a mostrar os ícones 3D | `item_icons.gd`, novo `item_icon_models.gd`, `item_slot.gd`, `shop_ui.gd`, `tools/blender/item_icons.py` | feito |
| 4 | **Comércio e ofícios:** loja, encantamento do ferreiro, cozinha, horta | `shop_ui.gd`, `enchant_ui.gd`, `cooking_ui.gd`, `plant_ui.gd` | a fazer |
| 5 | **Conversa com NPC:** faixa de pergaminho embaixo, nome em placa, retrato 3D de quem fala, respostas a tinta | `dialogue_ui.gd` | a fazer |
| 6 | **Menu principal, pausa, opções, atualização:** o livro fechado vira a capa do jogo; opções em páginas | `main_menu.gd`, `pause_menu.gd`, `options_panel.gd`, `update_panel.gd`, `updater.gd` | a fazer |
| 7 | **Praça e Horda fora de combate:** portal, mesa de guerra, mestre de passivas, recordes, convite, placar | `horde_portal_ui.gd`, `war_table_ui.gd`, `passive_master_ui.gd`, `records_ui.gd`, `horde_invite_ui.gd`, `horde_scoreboard.gd`, `survival_ui.gd` | a fazer |
| 8 | **Colônia:** painel da cidade e das construções (a parte de menu; o HUD da colônia fica) | `colony_ui.gd`, `base_building_ui.gd` | a fazer |
| 9 | **Limpeza:** apagar o tema antigo e os `StyleBoxFlat` soltos das telas migradas; opção "interface clássica" só se alguém pedir | `ui_theme.gd` e sobras | a fazer |

Telas novas já nascem no livro (o mapa e o grupo, 0.18.0; os amigos, 0.20.0). O minimapa e os quadros do grupo são HUD.

Ficam como estão: `hud.gd`, `hub_hud.gd`, `survival_hud.gd`, `colony_hud.gd`, `chat_ui.gd`, `stat_orb.gd`,
`fury_ring.gd`, `horde_icon.gd`.

### Detalhe da etapa 1 (a que destrava as outras)

- **`BookWindow`:** recebe a lista de páginas (nome, atalho, construtor) e cuida do resto. Variante de
  página única (meio livro ou folha solta) para telas pequenas como convite e recordes.
- **Um tamanho de livro**, igual em todas as abas; tela que não couber usa rolagem dentro da página.
- **Fonte embutida** em `assets/fonts` (hoje o título usa a serifada que o Windows tiver).
- **Pergaminho melhor:** bordas gastas, manchas mais fortes, uma vinheta desenhada nos cantos da página.
- **Ícones 3D sem espera:** gerar em lote na primeira abertura e guardar em `user://` por versão do jogo.
- **Testes:** o smoke test confere que as três abas ficam dentro das páginas e que nenhuma pede mais espaço
  do que o livro tem; a mochila tem 56 espaços (8 colunas, 7 linhas, com rolagem).

## Decisões tomadas

| Decisão | O que ficou |
|---|---|
| Ícones dos itens sem modelo (etapa 3) | Peças simples modeladas no Blender, uma por família, com a cor do item, fotografadas pelo mesmo `ItemIcons`. O `IconPainter` ficou como reserva |

## Decisões em aberto

| Decisão | Recomendação |
|---|---|
| Retrato no diálogo (etapa 5) | Câmera 3D no rosto do NPC, como o close que o diálogo já faz, dentro de uma moldura |

## Ferramentas

```powershell
$G = "C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe"
$B = "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
# regenerar o livro e as abas (depois rodar --import)
& $B --background --factory-startup --python tools/blender/ui_kit.py -- "$PWD/assets/ui"
# regenerar os modelos de família dos ícones (todos, ou só os nomeados no fim: potion ring ...)
& $B --background --factory-startup --python tools/blender/item_icons.py -- "$PWD/assets/models/items"
& $G --headless --path . --import
# abrir direto numa tela, com o save de demonstração: inv, char, quests, shop, enchant
& $G --path . res://scenes/world.tscn -- --geardemo --ui=inv
# captura (na primeira vez os ícones 3D levam uns 8 s na mochila e uns 20 s na loja; depois vêm do disco)
& $G --path . res://scenes/world.tscn -- --geardemo --ui=inv --shot=shots/inv.png --delay=8
# depois de mexer num modelo sem subir a versão, apagar o cache para o ícone ser refeito
Remove-Item -Recurse "$env:APPDATA/Godot/app_userdata/Ecos de Valdoria/icons"
# captura com a dica do item do espaço 12 da mochila aberta (presa ao lado do espaço)
& $G --path . res://scenes/world.tscn -- --geardemo --ui=inv --tip=12 --shot=shots/tip.png --delay=5
```
