# Mapa editável no editor do Godot — design

Data: 2026-11-15 · Branch base: `vila-cena` (a vila já editável em `scenes/village.tscn`, ainda sem commit)

## Intenção

Hoje o mundo inteiro (vale + Bosque, Mina e Pico) é montado por código em `scripts/world/world.gd` e
`scripts/world/region_builder.gd`. Para mudar qualquer coisa é preciso editar números no código e rodar o jogo
para ver. O usuário quer:

- abrir o Godot e **ver no editor exatamente o que tem no jogo**, o mapa todo, não só a vila;
- poder **redesenhar uma área inteira** no 3D: mover, apagar, duplicar e trocar qualquer peça;
- **parametrizar os monstros pela interface da engine**, como os arquivos de configuração da Unity: onde nascem,
  quantos, de que tipo, em quanto tempo voltam, sem editar código;
- tudo com manutenção fácil, funcionando igual no solo e no multiplayer (servidor dedicado).

## Metas

1. Cada mapa vira uma cena `.tscn` editável: `scenes/maps/vale.tscn`, `bosque.tscn`, `mina.tscn`, `pico.tscn`.
2. Tudo que o jogo monta hoje aparece no editor com o mesmo modelo, a mesma luz e o mesmo estilo toon: objetos,
   árvores, pedras, relevo, chão pintado, enfeites, luzes, NPCs, pontos interativos e pontos de monstros.
3. Árvores e pedras que hoje são sorteadas viram nós fixos (sorteio feito uma vez e salvo).
4. Pontos de nascimento de monstros viram nós com **tipo, quantidade, raio e tempo de reaparecer** no Inspector.
5. A conversão não muda o jogo: logo depois dela o jogo fica igual ao de antes (mesmas posições, mesmas
   contagens, mesmo visual), conferido por fotos e pelos testes.
6. Um guia curto (`docs/EDITOR_MAPA.md`) de como editar os mapas.

## Não-metas (agora)

- Números de cada tipo de monstro (vida, dano, loot) em `.tres`: continuam no `data/balance/enemies.json`.
  Converter isso mexe no Balance, nos testes e na simulação da economia, e fica para um projeto seguinte.
- Esculpir terreno com pincel (plugin tipo Terrain3D). O relevo continua sendo morros paramétricos, agora como nós.
- Capim como nós individuais: continua gerado (milhares de tufos em MultiMesh), controlado por áreas.
- Mudar regras de jogo, rede ou balanceamento (a única mudança no balanceamento é de onde vêm as posições dos
  nós de coleta; os valores ficam iguais).

## Anti-metas (seria fracasso mesmo funcionando)

- O jogo ficar diferente logo após a conversão (casa fora do lugar, monstro a menos, visual mudado).
- Perda de desempenho no jogo ou no servidor.
- Precisar mexer em código para uma mudança que é de mapa (mover, adicionar, trocar, ajustar monstro).
- Editor confuso: peças que não dá para saber o que são, ou prévia diferente do jogo.
- Quebrar os testes unitários porque uma cena carregada por eles passou a depender de autoload.

## Restrições

- **Godot 4.7.2**, GDScript. A prévia no editor depende de scripts `@tool`.
- **Testes unitários (`-s tests/unit/run.gd`) não compilam scripts que citam autoloads** (`Game`, `Network`,
  `Econ`, `Hub`, `ItemDB`...). Qualquer script anexado a nó das cenas de mapa precisa ser puro. Scripts do jogo
  são chamados por `load()` e não por nome de classe (padrão já usado em `village_plan.gd`).
- **Multiplayer:** o servidor dedicado é o mesmo projeto rodando sem tela e monta o mesmo mundo. Os monstros
  nascem só no servidor (`_setup_enemies` não roda no cliente) e chegam ao cliente pelos RPCs do `network.gd`
  (`server_register_enemy` → `_enemy_spawned`, snapshots). Nada disso muda: o servidor lê os pontos da cena em vez
  das listas do código. Cliente e servidor precisam estar na mesma versão (o deploy e o auto update já garantem).
- O servidor não monta visual: capim, clima, prévia do editor e áudio continuam fora do headless.
- `ground.gd` aceita no máximo `MAX_SHAPES = 40` formas pintadas por chão.
- Mapas fora do vale ficam longe da origem (`Regions.DATA[id].origin`). As cenas são em coordenadas locais do
  mapa; o mundo põe cada uma na origem dela.
- Carregamento em etapas com barra (`Loading`) deve continuar funcionando.
- Versão do jogo sobe no `project.godot` (`config/version`), como em todo PR.

## Abordagens consideradas

- **A) Tudo vira nó na cena (escolhida).** Cada objeto, árvore e pedra vira um nó; relevo e chão pintado
  viram nós paramétricos; capim continua gerado mas segue áreas marcadas. Dá para ver e mexer em tudo. Custo:
  conversão grande e centenas de nós por cena (o jogo já tem esses nós em tempo de execução, então não pesa mais).
- **B) Peças soltas viram nó, florestas viram zonas sorteadas.** Menos trabalho e cena mais leve, mas não dá
  para mexer numa árvore específica e "redesenhar uma área" fica pela metade. Descartada pelo motivo principal
  do usuário.
- **C) Plugin de terreno (Terrain3D) + cenas.** Ganharia pincel de relevo e textura, mas troca o chão e o shader
  atuais (risco visual alto e dependência nova). Fica para depois, se o usuário quiser esculpir.

O usuário escolheu A, depois de confirmar que não há impacto de desempenho (os nós já existem hoje no jogo).

## Como funciona (o que foi decidido)

### Peças das cenas (scripts em `scripts/map/`, todos `@tool` e puros)

| Nó | Para quê | No editor | No jogo |
|---|---|---|---|
| `MapRoot` (raiz de cada mapa) | id do mapa, meia largura, altura da serra da borda, densidade do capim, mostrar prévia (e capim na prévia, desligado por padrão) | monta o chão de verdade (`ground.gd`: relevo, serra, formas pintadas), a luz (`WorldLighting`) e aplica o toon (`ToonLook.convert_mesh`) | o mundo instancia a cena, lê os nós e monta tudo |
| `MapProp` | qualquer modelo GLB (`model` em lista), colisão `auto` (tabela por modelo, como hoje: caixa ou cilindro), `none` ou `custom` (CollisionShape3D filha), `no_grass` | modelo com toon + contorno da colisão | modelo + StaticBody3D (`collision_mask = 0`, igual hoje) + pegada sem capim |
| `MapGroundPaint` | retângulo ou disco pintado no chão: cor, suavidade, capim | entra no chão da prévia | `ground.add_rect/add_disc` |
| `MapMountain` | morro: raio e altura | entra no relevo da prévia | `ground.add_mountain` |
| `MapGrassArea` | disco/retângulo de capim `keep_out` (sem capim) ou `sparse` (ralo) | contorno no chão | entra nas listas do `scatter_grass` |
| `MapLight` (estende OmniLight3D) | modo `normal`, `night` (acende à noite, `DayNightFX.night_light`) ou `flicker` (lista `flicker_lights`) | luz acesa | registrada no sistema certo |
| `MapDecor` | peças montadas por código: árvore de Natal, boneco de neve, trenó, bengala, presentes, varal de luzes (ponta final por nó filho), festão de lampião, carroça, espantalho, plantação (MultiMesh), placa com texto (Label3D), fogo da forja (áudio) | chama o mesmo construtor do jogo (`ChristmasDecor`, `RegionBuilder.wagon`...) via `load()` | idem |
| `MapEntity` | tudo que tem script de jogo: NPCs (`npc_id`), pontos da antiga praça (`kind`, `building_id`), canteiros da Horta (`index`), cozinha, pontos da história, presentes e portas do Natal (`index`), portal da Horda, poste de direção (destinos por landmark), Papai Noel, nós de coleta (`node_id`), lojas e seus donos | boneco ou modelo + nome | o mundo cria o nó de jogo certo por `kind` (a fábrica fica no `world.gd`, que pode citar autoloads) |
| `EnemySpawn` | `kind` (lista lida do `enemies.json`), `count`, `radius`, `respawn` (s), `boss` (só nasce pela missão) | disco do raio + boneco + "slime ×4" | gera `count` entradas espalhadas no raio de forma determinística (mesma conta em toda execução) |
| `MapLandmark` | lugares com nome que outros sistemas usam: `camp`, `ruins`, `arena`, `farm`, `nest`, `orchard`, `village_spawn`, `portal`, `coach`, `arrive` | bandeira + nome | o mundo e as regras leem a posição pelo id |
| `VillageBuilding` | já existe: casas, lojas, poço | já existe | já existe |

Paredes invisíveis da borda viram `StaticBody3D`/`CollisionShape3D` comuns na cena. A floresta do anel da serra
(MultiMesh dentro do `ground.gd`) continua parte do chão.

### O que sai do código

- `world.gd` deixa de ter posições: `_build_village`, `_build_farm`, `_build_fields`, `_build_goblin_camp`,
  `_build_ruins`, `_build_arena`, `_build_borders`, `_scatter_*`, `_mountain_nature`, `_setup_enemies` (listas) e
  as funções por mapa do `region_builder.gd` são substituídas por um carregador de mapa (`MapLoader`) que percorre
  a cena e chama a fábrica de cada tipo de nó. As constantes `CAMP`, `RUINS`, `ARENA`, `FARM`, `NEST`, `ORCHARD`,
  `VILLAGE_SPAWN` passam a vir dos `MapLandmark`.
- `VillageLayout` perde as posições fixas que acabaram de ir para lá (lampiões, enfeites, NPCs): elas viram nós.
  Fica só o que é regra (paletas, `tint`, tamanhos de colisão das casas e lojas).
- `scenes/village.tscn` é absorvida pelo `vale.tscn` (os `VillageBuilding` passam a ser nós dele).
- `Regions.DATA` continua com nome, origem, meia largura e rank; `coach` e `arrive` viram landmarks.
- `MapRules.PLACES` (nomes do minimapa) e as posições dos nós de coleta passam a ler da cena (ver "Nós de coleta").

### Conversão (feita uma vez, por ferramenta)

Uma ferramenta `tools/bake_maps.gd` roda os construtores atuais num modo de gravação: cada `prop()`, forma
pintada, morro, luz, enfeite, NPC, ponto e entrada de monstro é registrado, com a posição final, e vira o nó
correspondente nas cenas novas (`PackedScene.pack`). Assim os sorteios de hoje ficam congelados exatamente como
estão. Entradas de monstro iguais e vizinhas (mesmo tipo, mesmo tempo, perto uma da outra) podem ser agrupadas
num `EnemySpawn` com `count` só se as posições geradas pelo nó forem as mesmas; senão ficam um nó por monstro.
Depois que as cenas reproduzem o jogo, o código gerador é apagado.

### Altura: as peças seguem o relevo (decisão minha)

Para redesenhar uma área (mexer num morro e o resto acompanhar), `MapProp`, `MapEntity`, `MapDecor`,
`EnemySpawn` e `MapLandmark` têm `follow_ground` (ligado por padrão). Ligado, a altura salva é a distância até
o chão (`ground.height_at`) e o nó é assentado no relevo, igual no editor e no jogo; desligado, vale a altura
absoluta (ex.: um caixote em cima de outro). A conversão grava a distância até o chão de cada peça, então o
resultado inicial é o mesmo de hoje (as árvores já eram assentadas assim; o resto fica a 0 do chão ou na altura
que tinha).

### Leituras sem mundo carregado (decisão minha)

`Regions.coach_point/arrive_point`, `MapRules.PLACES` e a prévia do editor leem landmarks da cena do mapa com
cache (como `VillageLayout.buildings()` já faz), sem arquivo intermediário: as cenas são puras e os testes
unitários podem carregá-las. Quando o mundo está montado, a HUD e o mapa-múndi leem do mundo.

### Nós de coleta (`world_nodes.json`)

O usuário decidiu: **os nós de coleta também ficam editáveis no mapa agora.**

Hoje as posições dos 20 nós (veios de ferro e cristal) estão em `data/balance/world_nodes.json` (`nodes`:
`[tipo, x, z]`), o id é o índice na lista e o servidor usa a posição para conferir a distância da coleta
(`WorldHarvest.node_def`, `Econ`, `HitGuard.accepts_harvest`). O tipo de cada veio (`kinds`: item, quantidade,
golpes, tempo de volta) continua no JSON.

Como fica:
- Cada nó vira um `MapEntity` `resource_node` na cena do mapa, com `node_id` (inteiro fixo, escrito no nó) e
  `kind` (`iron`/`crystal`, lista lida do `kinds`). A posição vem da cena.
- O id deixa de ser o índice da lista: apagar ou reordenar nós no editor não muda o id dos outros. Nó novo
  ganha o próximo id livre.
- `nodes` sai do `world_nodes.json`. `WorldHarvest.node_def` passa a montar a definição juntando o `kind` do JSON
  com a posição e o tipo lidos das cenas dos mapas (leitura pura com cache, a mesma do resto do mapa). O servidor
  dedicado tem os mesmos arquivos, então confere a coleta com a posição nova.
- O save e a rede guardam e mandam o `node_id`, que é o mesmo número de hoje para os 20 nós existentes (a
  conversão grava `node_id` = índice atual), então saves antigos e o protocolo continuam valendo.
- Ajustar o snapshot do balanceamento (`balance_tables.gd`, fixture `balance_snapshot.bin`) e o
  `test_world_harvest` para a nova origem das posições, sem afrouxar o que eles conferem.
- O teste de validação dos mapas confere: `node_id` único em todos os mapas, `kind` existente em `kinds`, nós
  dentro do mapa.

### Conferência de que nada mudou

Critério (decisão minha): igualdade de conteúdo, não de pixel. Mesmas contagens e posições (tolerância de
1 cm), mesmos modelos, cores e luzes, conferidos por teste; fotos lado a lado para olhar. O capim pode mudar
tufo a tufo (o sorteio dele depende da ordem em que as pegadas entram), desde que as áreas com e sem capim
continuem as mesmas. A fase da piscada das luzes e os presentes sorteados ao pé do poço também podem variar.

- Contagens por categoria (props, árvores, luzes, NPCs, pontos, monstros por tipo e por mapa) antes e depois.
- Fotos do `tools/village_shot.gd` (e vistas novas para campos, acampamento, ruínas, arena e os três mapas) com
  o mesmo horário e clima, antes e depois, lado a lado.
- Testes: unitários, smoke, vila, multiplayer (`net_test`), simulação da economia — os mesmos que o CI roda.
- Tempo de carregamento do mapa medido antes e depois.

### Testes novos

Um teste unitário de validação dos mapas (lê as cenas, sem autoload): todo `EnemySpawn.kind` existe no
`enemies.json`; cada chão tem no máximo 40 formas; landmarks obrigatórios existem uma vez; índices de canteiros,
presentes e portas são únicos e completos; tudo dentro da meia largura do mapa; construções da vila sem
sobreposição (o teste da planta atual passa a ler o `vale.tscn`).

## O que fica para quem constrói

- Nomes exatos de classes, arquivos e propriedades; organização dos nós em grupos dentro de cada cena (sugestão:
  por área — Vila, Horta, Campos, Acampamento, Ruínas, Arena, Floresta Leste...).
- Como desenhar o contorno das colisões e áreas no editor (gizmo, malha de linhas ou malha translúcida).
- A regra determinística de espalhar `count` monstros no raio (ex.: ângulo áureo a partir do centro).
- Ordem das etapas do carregamento com barra, desde que a barra ande e os testes que olham o `Loading` passem.
- Ajustar os testes que procuram nós como filhos diretos do mundo (`vila_test`, `net_test`) para procurar
  na árvore, sem afrouxar o que eles conferem.
- Se a fábrica de `MapEntity` fica no `world.gd` ou num script próprio do jogo (pode citar autoload).

## Etapas sugeridas

1. Peças da cena (`scripts/map/`) com prévia no editor e o carregador; ferramenta de conversão; converter o vale
   (vila incluída); trocar o `world.gd` para carregar o `vale.tscn`; conferir igualdade.
2. Converter Bosque, Mina e Pico do mesmo jeito.
3. `EnemySpawn` com quantidade/raio no Inspector e o teste de validação; agrupar pontos onde der; nós de coleta
   lidos da cena (`node_id` fixo) e `nodes` fora do `world_nodes.json`.
4. Apagar o código gerador, landmarks no lugar das constantes, guia `docs/EDITOR_MAPA.md`, versão.

Cada etapa termina com os testes do CI passando e o jogo igual ao anterior.
