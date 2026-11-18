# Slot "Costas": capas e asas

## Intenção
Dar ao jogador um nono espaço de equipamento, "Costas", para capas e asas em estilo anime, com efeitos
e muito detalhe nas peças épicas. Pedido do Henrique em 2026-11-18.

## Objetivos
- Slot `back` no inventário, nas regras do servidor e no save (personagens antigos ganham o slot vazio).
- Dez peças, validadas uma por rodada contra as referências escolhidas (Google Imagens, 2026-11-18).
- Cada peça épica tem efeito próprio (partículas e brilho).

## Fora do escopo
- Voar ou planar: as asas são só visual e atributos.
- Tingir ou trocar a aparência separada do item.

## O que não pode acontecer
- Peça flutuando solta do corpo (as lascas de cristal são a exceção pedida pelo estilo, presas a um núcleo).
- Capa atravessando o corpo ou quebrando a capa da armadura de placas que já existe.
- Custo de desempenho visível com vários jogadores na tela.

## As peças (como ficaram)
| Peça | Tipo | Raridade | Partícula | Pano animado |
|---|---|---|---|---|
| Asas Seráficas | asa | épica | penas de luz | |
| Asas do Abismo | asa | épica | brasas | |
| Asas de Cristal | asa | épica | lascas de cristal | |
| Asas de Fênix | asa | épica | penas de fogo | |
| Asas Mecânicas | asa | épica | faíscas | |
| Asas de Dragão | asa | rara | escamas | |
| Asas de Fada | asa | rara | pó de estrelas | |
| Capa do Rei-Dragão | capa | épica | brasas | barra em chamas |
| Manto da Galáxia | capa | épica | estrelas | nebulosa, estrelas piscando, cadente |
| Capa das Chamas | capa | épica | brasas | labaredas |
| Capa Glacial | capa | épica | flocos de neve | facetas de gelo |
| Capa da Tempestade | capa | épica | faíscas | nuvens e raios |
| Capa da Floresta | capa | épica | folhas | cipós e pólen |
| Manto do Corvo Andarilho | capa | rara | penas de corvo | |
| Meia Capa de Ombro | capa | rara | pétalas | |
| Capa de Viajante | capa | comum | poeira | |

A primeira versão das capas (um pano só) foi recusada como "muito simples" em 2026-11-18; foram refeitas em
camadas (sobrecapa, forro, ombreiras, correntes) e as elementais e a da galáxia entraram a pedido.
Receitas das partículas em `scripts/player/back_fx.gd`; pano animado em `assets/shaders/back_anim.gdshader`.

## Abordagens
1. **Slot novo `back` com itens próprios (escolhida).** Capas reaproveitam o `CapeRig`; asas são GLB preso
   ao pivô do peito. Custa mexer em regras, save, rede e interface, mas é o que o pedido descreve.
2. **Capa/asa como parte do item de peito** (o `"cape": true` de hoje). Sem slot novo, mas o jogador não
   escolhe a peça: descartada.
3. **Aba de aparência separada dos atributos.** Mais flexível, bem maior; fica para depois se fizer falta.

## Decisões (minhas, para corrigir se preciso)
- `back` é o último de `SLOTS`; na tela fica sob o boneco, entre as duas colunas.
- As peças dão atributos como o resto do equipamento.
- Slot vazio: a capa da armadura de placas continua aparecendo como hoje. Capa equipada substitui essa
  capa; asa equipada esconde a capa.
- Para o slot ser testável antes das peças, entra a "Capa de Viajante" (comum, cai de inimigos pelo sorteio de equipamento), que usa a malha
  de capa que já existe tingida com a cor do item.
- Modelos por script do Blender em linha de comando, formas curvas, pintura cel (`cel_paint`).

## Para quem for construir
Ordem: slot e capa simples primeiro; depois uma peça por rodada, começando pelas asas seráficas.
