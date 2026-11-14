# Habilidades por arma e ultimates — design

Data: 2026-11-13 · Branch: `habilidades`

## Intenção

O jogador quer que o combate tenha **habilidades de personagem que dependem da arma equipada**, com
efeitos visuais épicos e cheios de partículas. Cada tipo de arma (espada, cajado, arco) tem pelo menos
3 habilidades funcionais, e uma delas é uma **ultimate** liberada por uma **barra de fúria**. O
objetivo é que usar a ultimate seja o grande momento da luta: animação própria do corpo inteiro,
partículas detalhadas, luz, tremor de tela e congelamento de impacto.

## Objetivos

- Kit de habilidades por classe de arma (`sword`, `staff`, `bow`), trocado ao trocar de arma.
- Barra de fúria que enche lutando e libera a ultimate quando cheia.
- Três ultimates épicas:
  - **Espada — Turbilhão:** o personagem gira com a lâmina por ~1,5 s, deixando rastro de fogo em
    arco, faíscas, poeira levantando do chão; puxa inimigos próximos e causa dano a cada volta.
  - **Cajado — Chuva de Meteoros:** o mago canaliza (fica parado com o cajado erguido); enquanto
    segura a tecla, o céu escurece numa área à frente e meteoros caem com rastro de fogo, explosão,
    cratera/brasas e fumaça. Soltar a tecla, levar dodge ou acabar a duração encerra a chuva.
  - **Arco — Flecha do Vendaval:** o arqueiro agacha e inclina o corpo para trás, o arco treme e
    acumula vento/luz (a "pressão"); ao soltar, uma flecha atravessa tudo em linha reta, com onda de
    choque, rastro de vento cortando o ar e linhas de velocidade.
- Base de partículas mais rica que a atual (`FX.burst` com cubinhos): partículas com brilho
  (aditivas), rastros, fumaça, faíscas alongadas pela velocidade, luzes temporárias (`OmniLight3D`
  que pisca e apaga), decalques/manchas no chão, congelamento de impacto (hit stop) e tremor de tela.
- Tudo visível para os outros jogadores no multiplayer.

## Não-objetivos

- Árvore de talentos, escolha de habilidades ou remapeamento de teclas.
- Nova classe de arma "duas mãos": o Turbilhão vale para qualquer espada (o Montante só fica mais bonito
  por ser maior).
- Sons novos gravados: usar os sons existentes (`Sfx`) com pitch/volume; sons novos só se sobrar.
- Rebalancear o resto do jogo.

## Anti-objetivos (falha mesmo se funcionar)

- Efeito que derruba o FPS (alvo: ultimate de 4 jogadores ao mesmo tempo sem queda perceptível).
- Habilidades comuns que enchem a tela a cada uso: o "épico" é reservado à ultimate.
- Ultimate que trava o jogador num estado quebrado (morte, dodge ou troca de arma no meio).
- Efeitos rodando no servidor dedicado (o servidor não vê partículas; `FX._scene()` já retorna null).

## Kits

| Arma | Tecla 1 | Tecla 2 | Tecla 3 | Ultimate (tecla 4) |
|---|---|---|---|---|
| Espada | **Investida:** avança ~5 m, dano em linha, rastro de faíscas | **Golpe Sísmico:** golpe no chão, rachadura em cone com pedras e poeira, atordoa curto | — | **Turbilhão** |
| Cajado | **Bola de Fogo** (atual) | **Nova Gélida** (atual) | **Cura** (atual) | **Chuva de Meteoros** |
| Arco | **Tiro Triplo:** 3 flechas em leque | **Flecha Glacial:** prende/atrasa o alvo atingido em gelo | — | **Flecha do Vendaval** |

Liberação por nível: 1ª habilidade no nível 1, 2ª no 3, 3ª (só cajado) no 5, ultimate no 8.

## Decisões tomadas na conversa

- Habilidades acompanham a arma equipada.
- Ultimate liberada por barra de fúria (escolha do usuário).
- Ordem de entrega: base de partículas + kit da espada primeiro; o usuário testa e aprova o nível de
  "épico"; depois cajado e arco no mesmo padrão.

## Decisões minhas (o usuário pode corrigir)

- **Tecla da ultimate é 4**, não R: R já é a poção de vida na barra de ações.
- **A Cura passa a ser só do cajado.** Hoje qualquer arma usa Cura no nível 2; espada e arco perdem
  isso e dependem de poções. É a mudança de balanceamento mais visível do projeto.
- **Custo:** habilidades do cajado gastam mana como hoje; as de espada e arco só têm recarga (sem
  custo), porque esses personagens não têm motivo para ter mana.
- **Fúria:** 0–100. Enche com dano causado (1 ponto a cada ~2% da vida máxima do alvo, com mínimo) e
  com dano recebido (mais devagar). Não esvazia com o tempo. Usar a ultimate zera. Trocar de arma
  mantém a fúria. Valores finos ficam para o teste.
- **HUD:** a barra de ações passa a mostrar as habilidades da arma atual (ícones trocam ao trocar de
  arma) e ganha um espaço de ultimate com a barra de fúria em volta/embaixo, que brilha e pulsa quando
  cheia.
- **Dano da ultimate** escala com o atributo da arma (FOR espada, INT cajado, AGI arco), como os
  ataques normais.
- **Modo Horda:** as habilidades funcionam igual no Desafio da Horda.

## Como funciona hoje (o que a mudança toca)

- `scripts/autoload/item_db.gd`: `SPELLS` com 3 magias globais (teclas 1–3, nível, custo, recarga).
  Passa a ter as habilidades agrupadas por classe de arma (`class` já existe nos itens).
- `scripts/player/player.gd`: `cast(id)` lida com magias, `cooldowns` é um dicionário fixo, as teclas
  `spell_1..3` chamam a lista fixa. Vai virar despacho por kit da arma + estados de habilidade
  (investida, giro, canalização, carregar tiro) que bloqueiam ataque/dodge do jeito certo.
- `scripts/player/knight_anim.gd` / `knight_moves.gd`: animação procedural por poses. Ganha poses
  novas: giro (corpo inteiro rodando, lâmina estendida), canalizar (cajado erguido, corpo tremendo),
  arqueiro agachado e inclinado para trás com tensão crescente, investida e golpe no chão.
- `scripts/fx.gd`: hoje só `damage_number`, `burst`, `ring`. Ganha as peças novas da base de
  partículas, todas criadas por código como o resto do projeto.
- `scripts/autoload/network.gd`: `send_event(kind, a, b)` replica efeitos; réplicas tocam o efeito em
  `player.gd` (~linha 977). Habilidades novas usam o mesmo caminho; a canalização manda início e fim
  (e a pose vai nos flags de estado já enviados em `_player_state`).
- `scripts/ui/hud.gd`: barra de ações monta os espaços de magia com lista fixa; `game_menu.gd` também
  lista as magias. Ambos passam a ler o kit da arma atual.
- Dano em inimigos no cliente usa o mesmo caminho dos ataques atuais (`take_damage` /
  `Network.client_hit_enemy`).

## Restrições

- Godot 4, tudo por código (sem cenas de partícula feitas no editor), no estilo de `fx.gd`.
- Servidor dedicado não cria efeitos.
- Os testes do CI (`smoke-check`) precisam continuar passando; o smoke test cita magias e pode precisar
  ser atualizado.
- Trabalhar no worktree `../godot-3d-habilidades` (outras sessões usam a pasta principal).

## Deixado para quem implementa

- Números exatos de dano, recarga, alcance e duração (ajustar jogando).
- Quantidade de partículas por efeito, dentro do anti-objetivo de desempenho.
- Ícones das habilidades novas no estilo de `icon_painter.gd`.
