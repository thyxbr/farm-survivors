# Editar os mapas no Godot

Os quatro mapas do jogo são cenas que você abre e edita no 3D do Godot:

| Mapa | Cena |
|---|---|
| Vale de Valdoria (vila, campos, acampamento, ruínas, lagoa, ninho) | `scenes/maps/vale.tscn` |
| Bosque Sussurrante | `scenes/maps/bosque.tscn` |
| Mina de Cristal | `scenes/maps/mina.tscn` |
| Pico das Cinzas | `scenes/maps/pico.tscn` |
| Arena do Desafio da Horda (mapa à parte, longe ao norte) | `scenes/maps/arena.tscn` |

O que está na cena é o que o jogo monta: mover, apagar ou duplicar (Ctrl+D) um nó muda o jogo. No editor a
cena mostra o chão de verdade (relevo, serra, trilhas), a luz e o estilo toon do jogo. Capim, clima e hora do dia
só aparecem jogando.

## O que cada tipo de nó faz

Todos ficam em `scripts/map/` e aparecem no Inspector com as opções abaixo.

- **Raiz do mapa (MapRoot)**: tamanho do mapa (`half`), altura da serra em volta (`border_height`), a passagem na
  serra do sul por onde chega a estrada (`south_pass_x`, `south_pass_width`; 0 = sem passagem), densidade e
  semente do capim. `show_preview` liga a prévia, `show_colliders` mostra as colisões (azul) e `preview_grass`
  desenha o capim no editor (pesado).
- **Objeto (MapProp)**: qualquer modelo de `assets/models` (árvore, pedra, cerca, caixote, tenda, ruína,
  lampião...). Trocar o `model` já põe a colisão padrão dele; `shape` e `shape_size` ajustam a colisão;
  `no_grass` tira o capim de baixo; `tint` pinta o modelo inteiro de uma cor (alfa 0 = cores do modelo, como os
  pinheiros mortos da Arena). A escala do nó é a escala do modelo.
- **Construção da vila (VillageBuilding)**, em Vila/Construções: casas, as lojas (empório da Mira, botica da Pip e
  ferraria, com o dono na frente; a oficina do artesão e o laboratório de alquimia, abertos na frente), as três
  barracas da feira (`stall_cloth`, `stall_farm`, `stall_goods`) e o poço; `palette` pinta a casa, `flowers` põe canteiro, `delivery` marca uma das 6
  portas da missão de Natal. A porta da casa é a seta azul (+Z) do gizmo.
- **Área pintada no chão (MapGroundPaint)**: retângulo ou disco com cor e borda suave (trilhas, praça, lotes).
  O retângulo fica sempre alinhado aos eixos. No máximo 40 por mapa.
- **Morro (MapMountain)**: raio e altura. Ao mover um morro, o chão e tudo que segue o relevo acompanham.
- **Área do capim (MapGrassArea)**: disco sem capim ou com capim ralo.
- **Luz (MapLight)**: `mode` normal, noite (acende ao escurecer) ou piscando (fogo).
- **Enfeite (MapDecor)**: peças montadas por código (árvore de Natal, boneco de neve, trenó, bengala,
  presentes, varal de luzes, festão, guirlanda, carroça, espantalho, plantação, placa de texto e os discos do
  chão da Arena).
- **NPC ou ponto de jogo (MapEntity)**: `kind` diz o que é (npc, story_point, hub_point, farm_plot, kitchen,
  portal, signpost, santa, xmas_gift, resource_node...), `ref` o id (NPC, ponto da história, ponto da praça,
  tipo do veio), `index` o número (canteiros 0..11, presentes 0..7).
- **Porta de dungeon**: MapEntity com `kind = dungeon_door`. No mapa de fora, `ref` = o id da dungeon
  (`dg_bosque`...) e um MapLandmark `id = "dg:<id>"` ao lado, onde o jogador aparece ao sair ou ao morrer lá
  dentro. Dentro da dungeon, `ref = "out"` (exatamente uma) e o landmark `arrive` (onde se chega). A cena de cada
  dungeon é `scenes/maps/dg_<id>.tscn` (no `MapData.SCENES` e no `Regions.DATA`, com `dungeon: true` e `parent`).
  No ponto de monstro do chefe da dungeon, ligue `chief`.
- **Bancada de craft**: MapEntity com `kind = station` e `ref` = a estação (`leather` é a Bancada de Couraria, na
  oficina do artesão; `alchemy` é a mesa de alquimia, no laboratório ao lado da botica). A forja abre pelos
  serviços do Doran; a alquimia também pela Pip e a couraria pelo Mestre Aurélio.
- **Feirante**: MapEntity `npc` com `ref` = `tereza` (couro e tecido), `bento` (sementes e ferramentas) ou `cida`
  (provisões), atrás do balcão da barraca. Cada vendedor vende um tipo de coisa (ShopUI.STALLS); a Mira, as armas.
- **Morador que passeia**: MapEntity com `kind = walker`, `ref` = o NPC (`marta`, `joca`, `lauro`, `bia`) e
  `params.path` = `[[x, z], [x, z, segundos parado], ...]` em coordenadas do mundo. Ele vai e volta pelo caminho e
  para quando o jogador chega perto.
- **Nó de coleta**: MapEntity com `kind = resource_node`, `ref` = um tipo de `data/balance/world_nodes.json`
  (cobre, ferro, cristal, prata, mithril, astralita; pinho, carvalho, bétula-prata, freixo-cinza, madeira-de-alma)
  e um `node_id` fixo (hoje 0–70). Para um
  veio novo, duplique um e dê um `node_id` que nenhum outro usa. Não reaproveite o número de um veio apagado: o
  save dos jogadores guarda o número.
- **Ponto de monstro (EnemySpawn)**, no grupo Monstros de cada mapa: `kind` (tipo do `enemies.json`), `count`
  (quantos), `radius` (onde nascem em volta), `respawn` (segundos para voltar) e `night_only` (só aparece de
  noite e vai embora de dia, como as Asas-de-couro). Vida, dano e loot de cada tipo
  continuam no `data/balance/enemies.json`. `level`/`level_max` dão a faixa de nível dos monstros (cada um sorteia
  o seu ao nascer; `level` 0 = a faixa da região com nome onde o ponto fica, ou sem nível fora de região) e
  `elite` os faz de elite (mais níveis, vida e tamanho); o que cada nível muda está em `docs/BALANCEAMENTO.md`.
- **Região com nome (MapRegion)**, no grupo Regiões de cada mapa: `region_id` (chave no
  `data/balance/regions.json`, que guarda nome, faixa de nível, densidade e se aparece no mapa), `shape`
  (Retângulo, que gira com o nó, ou Disco), `size` (largura × profundidade do retângulo) ou `radius` (disco). A
  prévia mostra a mancha laranja e "Nome · Nv a–b". Vários nós com o mesmo `region_id` são uma região só (o
  Capinzal dos Raptores tem 4 manchas). Regiões que se sobrepõem: vale a menor (o Cume Maldito dentro das Ameias
  do Lich). Para criar uma região nova, ponha a chave no regions.json **e** um nó na cena; o teste
  `test_regions_areas` confere que os dois lados batem.
- **Lugar com nome (MapLandmark)**: acampamento, ruínas, Horta, ninho, pomar, lagoa (`pond`), portal da Horda,
  onde o jogador volta da Horda (`horde_return`), onde nasce (`village_spawn`), carruagem (`coach`) e chegada da
  viagem (`arrive`). O minimapa, a viagem, o chefe e a Horda usam estes pontos.

`follow_ground` (ligado por padrão) prende a peça ao relevo: a altura do nó é a distância até o chão.

A Arena não usa o chão de Valdoria (`has_ground` desligado na raiz): o piso dela são os discos e a colisão de
caixa que estão na própria cena. A posição dela no mundo fica em `MapData.EXTRA_ORIGINS`.

Música da vila: toca dentro de `VillageLayout.BOUNDS`. Se você mudar a cerca da vila de lugar, ajuste esse
retângulo também, e a zona da guarda (`VillageWard.ZONES`: a vila e a Horta + Pomar).

A vila fica no sul do vale (desde a 0.61.0): o personagem novo nasce na estrada do sul (`village_spawn`), entra pelo
portão sul, passa pela Rua da Chegada e chega na praça da feira. A Horta e o Pomar ficam logo depois do portão
norte; a carruagem do Beto fica do lado de fora dele.

## Antes de rodar o jogo

Rode os testes unitários; a validação dos mapas (`tests/unit/test_map_validation.gd`) aponta o que o jogo não
aceita, com o caminho do nó:

```
godot --headless --path . -s tests/unit/run.gd
```

## Multiplayer

O servidor dedicado é o mesmo projeto e lê as mesmas cenas: monstros, coleta e colisões seguem o que está na
cena. Cliente e servidor precisam estar na mesma versão, então uma mudança de mapa vai para os jogadores numa
versão nova (como qualquer mudança de código).
