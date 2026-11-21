# Monstros da Geleira de Cristal

## Intenção

O PR #180 transformou a mina na Geleira de Cristal (`scenes/maps/mina.tscn`, níveis 20–30), mas os monstros
continuaram os da mina: kobold, centopeia e toupeira não combinam com gelo. Este trabalho troca esses monstros
por monstros próprios do bioma de gelo. O Golem de Cristal, os esqueletos (corredor norte, missão do Bolgar) e
os Brutos do contrato ficam como estão.

## Monstros (aprovados pelo usuário)

| Id | Nome | Modelo | Papel | Região |
|---|---|---|---|---|
| `lobo_geada` | Lobo da Geada | `wolf` (novo, 4 patas) | bando (`ai: pack`), bote com mordida que deixa lento (`chill`) | Galeria de Entrada, escolta dos Alfas |
| `gralha_cristal` | Gralha-de-Cristal | `crow` (novo, pivôs do morcego) | à distância (`ai: ranged`), estilhaço de gelo (`shot: ice`) que deixa lento | Entrada e Veio de Cristal |
| `ieti` | Ieti Glacial | `yeti` (novo, pivôs do golem) | tanque; a cada 2 golpes bate no chão (`slam_every`) com onda de gelo e lentidão | Fossos |
| `lobo_alfa` | Alfa da Matilha | `wolf` tingido de branco, escala 1,4, elite | uiva (`howl_cd`) e acelera os lobos em volta por `howl_secs` | Veio de Cristal e fosso leste |

A Mãe-Verme continua no fosso oeste (o teste exige), com casca de gelo (`tint`) e chamando Lobos da Geada.

## Abordagens consideradas

- **Modelos novos com animação nova só para o lobo** (escolhida): o lobo precisa de 4 patas; a gralha e o ieti
  reaproveitam as animações do morcego e do golem com os mesmos nomes de pivô.
- Reaproveitar os modelos antigos tingidos de azul: barato, mas não muda a leitura do bioma.
- Um modelo novo por monstro, inclusive o Alfa: o Alfa como o mesmo lobo tingido e maior já lê como líder.

## Decisões do construtor

- Fica **um bando de Toupeiras** no fosso leste: `tests/net_test.gd` usa uma Toupeira na Geleira para testar a
  réplica que cava. Tirar exigiria outro monstro de cavar no teste.
- Materiais novos: `frost_pelt` (Pele da Geada) e `ice_feather` (Pena de Cristal). A arte deles em
  `assets/ui/items` é provisória (couro recolorido e pena desenhada em código); pode ser trocada por uma pintada
  como as outras (docs/ICONES_PROMPTS.md).
- Os números seguem os vizinhos da mina (mesmo `ref_level` 2; o Alfa como elite de `ref_level` 6, abaixo do
  Cavaleiro Esqueleto).
