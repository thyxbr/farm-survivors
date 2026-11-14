# Interface "grimório" — o que aprendemos e plano de migração

Estado em 14/11/2026, branch `ui-teste` (teste descartável, sem commit). O HUD de jogo fica como está.
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
9. **Blender:** metal precisa de mundo com degradê para refletir algo; papel precisa de um pouco de emissão
   para não sair escuro; `use_nodes` está marcado para sair no Blender 6.

## O que existe no teste

| Peça | Onde |
|---|---|
| Livro aberto, abas de marcador (PNG) | `assets/ui/book.png`, `tab_on.png`, `tab_off.png` |
| Gerador das peças | `tools/blender/ui_kit.py` (`--book` gera só o livro e as abas) |
| Cores de tinta, `ink()`, `paper_theme()` | `scripts/ui/ui_theme.gd` |
| Espaço de item sobre papel (`paper = true`) | `scripts/ui/item_slot.gd` |
| Ícones 3D | `scripts/ui/item_icons.gd` |
| Inventário em duas páginas | `scripts/ui/game_menu.gd` |

As peças de aço do primeiro teste (`window.png`, `inset.png`, `slot.png`, `button_*.png`, `crest.png`,
`forged_theme()`, `forged = true`) continuam no branch e saem na etapa 1.

## Plano de migração

Cada etapa é um PR, sai com as capturas das telas tocadas e com `/smoke-check` passando.

| Etapa | O que | Telas | Estado |
|---|---|---|---|
| 0 | Teste no inventário | `game_menu.gd` (aba Inventário) | feito, descartável |
| 1 | **Base.** Refazer o teste como código de verdade: componente `BookWindow` (livro, margens, abas, fechar, aviso de tamanho), tema de papel completo (lista, abas, barra, deslizador, campo de texto), fonte embutida, remover as peças de aço | `ui_theme.gd`, `item_slot.gd`, `item_icons.gd`, novo `book_window.gd` | a fazer |
| 2 | **Menu do herói inteiro no livro:** Inventário, Personagem e Missões a tinta; atalhos I/C/J de volta nas abas; dica de item em pergaminho | `game_menu.gd`, `item_tooltip.gd`, `skill_icon.gd` | a fazer |
| 3 | **Ícones dos itens sem modelo:** poções, comida, anéis, amuletos, orbe, aljava, materiais, sementes | `icon_painter.gd`, `item_icons.gd` | a fazer |
| 4 | **Comércio e ofícios:** loja, encantamento do ferreiro, cozinha, horta | `shop_ui.gd`, `enchant_ui.gd`, `cooking_ui.gd`, `plant_ui.gd` | a fazer |
| 5 | **Conversa com NPC:** faixa de pergaminho embaixo, nome em placa, retrato 3D de quem fala, respostas a tinta | `dialogue_ui.gd` | a fazer |
| 6 | **Menu principal, pausa, opções, atualização:** o livro fechado vira a capa do jogo; opções em páginas | `main_menu.gd`, `pause_menu.gd`, `options_panel.gd`, `update_panel.gd`, `updater.gd` | a fazer |
| 7 | **Praça e Horda fora de combate:** portal, mesa de guerra, mestre de passivas, recordes, convite, placar | `horde_portal_ui.gd`, `war_table_ui.gd`, `passive_master_ui.gd`, `records_ui.gd`, `horde_invite_ui.gd`, `horde_scoreboard.gd`, `survival_ui.gd` | a fazer |
| 8 | **Colônia:** painel da cidade e das construções (a parte de menu; o HUD da colônia fica) | `colony_ui.gd`, `base_building_ui.gd` | a fazer |
| 9 | **Limpeza:** apagar o tema antigo e os `StyleBoxFlat` soltos das telas migradas; opção "interface clássica" só se alguém pedir | `ui_theme.gd` e sobras | a fazer |

Ficam como estão: `hud.gd`, `hub_hud.gd`, `survival_hud.gd`, `colony_hud.gd`, `chat_ui.gd`, `stat_orb.gd`,
`fury_ring.gd`, `horde_icon.gd`.

### Detalhe da etapa 1 (a que destrava as outras)

- **`BookWindow`:** recebe a lista de páginas (nome, atalho, construtor) e cuida do resto. Variante de
  página única (meio livro ou folha solta) para telas pequenas como convite e recordes.
- **Um tamanho de livro**, igual em todas as abas; tela que não couber usa rolagem dentro da página.
- **Fonte embutida** em `assets/fonts` (hoje o título usa a serifada que o Windows tiver).
- **Pergaminho melhor:** bordas gastas, manchas mais fortes, uma vinheta desenhada nos cantos da página.
- **Ícones 3D sem espera:** gerar em lote na primeira abertura e guardar em `user://` por versão do jogo.
- **Testes:** `tests/smoke_test.gd:2356` exige mochila com 54 espaços ou mais; o teste tem 48 (8 colunas).
  Ou a mochila volta a ter 54+ ou a verificação muda junto.

## Decisões em aberto

| Decisão | Recomendação |
|---|---|
| Qual fonte embutir | Cinzel (títulos) e EB Garamond (texto), licença livre OFL. Precisa baixar os arquivos |
| Ícones dos itens sem modelo (etapa 3) | Modelar peças simples no Blender e passar pelo mesmo `ItemIcons`, para tudo ter o mesmo traço |
| Retrato no diálogo (etapa 5) | Câmera 3D no rosto do NPC, como o close que o diálogo já faz, dentro de uma moldura |
| Tamanho do livro em telas menores que 1600×900 | Encolher o livro inteiro por escala, sem refazer o layout |

## Ferramentas

```powershell
$G = "C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe"
$B = "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
# regenerar o livro e as abas (depois rodar --import)
& $B --background --factory-startup --python tools/blender/ui_kit.py -- "$PWD/assets/ui" --book
& $G --headless --path . --import
# abrir direto numa tela, com o save de demonstração: inv, char, quests, shop, enchant
& $G --path . res://scenes/world.tscn -- --geardemo --ui=inv
# captura (delay de 8 s para os ícones 3D ficarem prontos)
& $G --path . res://scenes/world.tscn -- --geardemo --ui=inv --shot=shots/inv.png --delay=8
```
