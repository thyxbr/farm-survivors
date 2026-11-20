# Biomas, rio do Vale e dungeons subterrâneas

## Por quê
Os três mapas de viagem (Bosque, Mina, Pico) usam o mesmo chão verde, o mesmo capim e a mesma serra com
pinheiros do Vale: parecem o mesmo lugar. As quatro dungeons são praças abertas de 90 m com céu, muros de ruína e
pinheiros em volta: não parecem dungeon. O usuário quer cada mapa com bioma próprio, um rio com ponte no Vale e
dungeons fechadas, debaixo da terra, com curvas que escondem o que vem e uma sala do chefe com entrada épica.

## Decidido com o usuário (2026-11-20)
- Bosque Sussurrante → **Pântano Sussurrante** (água parada, lama, árvores retorcidas, névoa verde).
- Mina de Cristal → **Geleira de Cristal** (neve, gelo azul, cristais, neve caindo sempre); os slimes de gelo do
  Bosque passam para lá.
- Pico das Cinzas → **Vulcão das Cinzas** (rocha escura, lava, cinza caindo, céu avermelhado).
- Cada dungeon segue o tema do mapa de onde se entra.
- Ordem: rio (PR 1), biomas (PR 2), dungeons (PR 3). Um PR por parte.

## Abordagens consideradas
- **Rio pintado no chão** (como a lagoa: disco de cor): barato, mas o rio fica chapado e não bloqueia nada; a
  ponte vira enfeite. Descartado.
- **Rio rebaixado** (escolhido): o chão some (discard no shader) numa faixa ao longo do caminho do rio; por baixo,
  margem inclinada e água animada abaixo do nível do chão. Paredes de colisão nas margens; a ponte é o único lugar
  de passar. Dá profundidade de verdade sem mexer no chão plano/colisão de caixa.
- **Malha de terreno com sulco**: trocar o plano do chão por grade com altura. Mexe em tudo que assume y = 0
  (spawns, peças, servidor). Descartado.

Biomas: **paleta de bioma por mapa** (tabela em código, puro) que o chão, a serra, a vegetação da serra, o capim,
a luz/céu/neblina e o clima leem, em vez de cores fixas. Alternativa (shader por mapa) duplicaria código.

Dungeons: **salas e corredores montados por código a partir de uma planta** (lista de salas e ligações na cena,
como peças) com teto, paredes e chão próprios, sem o chão de Valdoria; a luz do mundo é trocada por uma luz de
caverna enquanto o jogador está dentro. Alternativa (modelar cada dungeon no Blender) é mais cara para iterar.

## Rio (PR 1)
- Peça nova `MapRiver` (`scripts/map/map_river.gd`, @tool): caminho = filhos `MapWaypoint` (arrastáveis), `width`
  (água), `bank` (margem inclinada), `depth`. Caminho suavizado (Catmull-Rom).
- Chão: `ground.gd` recebe o caminho (segmentos) e o shader descarta o plano dentro da faixa do rio.
- Malhas: margem (terra/lama, do nível do chão até a água) e água (shader toon: correnteza, espuma na borda).
- Colisão: paredes na borda de fora da margem, na camada 32 (jogador e monstros colidem; câmera não). Abrem onde
  há ponte (MapProp com modelo `bridge*`).
- Capim e flores não nascem no rio (áreas sem capim ao longo do caminho).
- No Vale: rio de oeste a leste perto de z ≈ -31, entre os Campos do Norte e o Forte/Cemitério; ponte de pedra na
  Estrada do Norte (x = 0). Árvores no leito saem; capinzal 2 e o veio de cobre 1 mudam um pouco de lugar.
- Ponte: modelo GLB de pedra (Blender, CLI) com colisão `-col` no tabuleiro e nas muretas.

## O que fica para o construtor
Formato exato das salas das dungeons, quantos biomas extras de enfeite (modelos novos) e o tom de cada paleta:
decidido rodada a rodada com fotos no jogo.

## Biomas (PR 2, feito)
`BiomeRules` (puro) por mapa: capim, plantas, serra, árvores da encosta, céu, névoa, sol, clima e partículas.
Chão e serra leem o bioma em `MapRoot.make_ground`; o `WeatherFX` troca céu/névoa/sol/clima pelo mapa da câmera.
Charcos e lava são `MapRiver` curtos com pontas arredondadas.

## Dungeons (PR 3, feito)
`MapDungeon` junta salas (`MapDungeonRoom`) e corredores (`MapDungeonPath`) numa grade de 1 m: chão, paredes de
rocha com deslocamento por ruído (o mesmo nos dois lados de um canto, sem fresta), teto só visto de baixo (a
câmera passa por ele; camada visual fora da foto do minimapa), colisão só no chão e nas paredes. Tochas, enfeites
por tema e, onde um corredor encosta na sala `boss`, o portão (até 6 m, resto vira parede) com estátuas e
braseiros. `DungeonFX` (cliente) abre o portão a 10 m: folhas giram, braseiros da sala acendem em volta, círculo
de runas, letreiro com o nome da sala. Debaixo da terra: `BiomeRules.UNDERGROUND` (sem sol, céu preto, névoa
escura, sem clima). Plantas geradas por script (fora do repositório) e conferidas por `test_dungeon_layout`.
