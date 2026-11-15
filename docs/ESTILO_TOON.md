# Estilo toon ("desenhado") — o que aprendemos e plano de migração

Estado em 14/11/2026, branch `toon-npc-teste`. O estilo nasceu de um estudo de personagem em Blender
(sombra em dois tons + contorno) e foi trazido para o Godot. Hoje cobre **personagens** (com contorno)
e **cenário** (props, construções, árvores, vegetação, chão e grama, sem contorno).

## O que é o estilo

| Ingrediente | Como é feito | Onde |
|---|---|---|
| Sombra em dois tons | cada luz ou acende a face inteira ou a deixa no tom de sombra; corte seco, sem degradê | `assets/shaders/toon_light.gdshaderinc`, incluído por `toon_character`, `ground` e `grass` |
| Sombra fria | a face em sombra recebe a luz multiplicada por `shade_tint` (0.40, 0.38, 0.55): mais escura e azulada | idem |
| Sombra projetada | a atenuação do sol passa por um degrau (0.3–0.7) e cai num tom mais fundo, `cast_tint` (0.16, 0.16, 0.27) | idem |
| Ambiente | sem SSAO, névoa leve e azulada, menos ambiente e mais sol, sombra do sol com borda seca | `WorldLighting._toon_tune` |
| Brilho de metal | uma faixa dura de especular, só em material com `metallic` > 0.55 | idem, `gloss` |
| Contorno | casca invertida: cópia da malha, faces de trás, empurrada pela normal, sem luz | `assets/shaders/toon_outline.gdshader` |

Os GLBs **não mudam**. `ToonLook.apply(modelo)` (`scripts/world/toon_look.gd`) lê cada
`StandardMaterial3D` e monta o `ShaderMaterial` equivalente em tempo de execução. Ligado por padrão;
`-- --notoon` volta ao sombreado antigo, para comparar.

## Aprendizados

### Do estudo no Blender
1. **Medir a referência antes de modelar.** A primeira versão seguiu proporções "de cabeça" e ficou
   longe. O que funcionou: recortar cada painel da ficha em zoom, medir em pixels, converter para
   metros e só então escrever os números. Depois, comparar render e referência lado a lado a cada rodada.
2. **O rosto fica melhor sem sombra de forma.** Em anime a pele do rosto é chapada; a sombra vem só do
   cabelo e do pescoço. Facetas de low-poly no rosto viram triângulos de sombra dura.
3. **Detalhe pequeno é geometria ou decalque, não textura.** Olhos, costuras e frisos foram tiras
   projetadas sobre a malha; dá para fazer por código e não precisa de UV.
4. **O que código não resolve bem:** dobras de tecido, mãos, perfil do rosto e mechas largas de cabelo.
   Isso pede escultura ou pintura à mão.

### Da adaptação no Godot
1. **Usar a luz do jogo, não uma luz própria.** O shader só troca o *corte* da luz; cor e intensidade
   continuam vindo do sol, da contraluz e do ambiente (`WorldLighting`). Por isso o personagem não
   destoa do cenário.
2. **Face acesa recebe a luz inteira**, sem o cosseno do Lambert, então cores claras estouram. O
   `light_gain` (0.72) compensa.
3. **Metal precisa ser escurecido.** No PBR o metal reflete o céu e sai bem mais escuro que o albedo; no
   toon ele ficaria quase branco. O albedo é escurecido em `0.35 × metallic` — proporcional, porque as
   malhas e cotas usam `metallic` perto de 0.5 e um corte fixo em 0.5 as deixava de fora (foi o bug da
   armadura branca).
4. **Contorno em low-poly exige normais suavizadas.** Com faces chapadas a casca abre frestas nas
   arestas. `ToonLook` gera uma malha de casca com uma normal por posição (média das faces vizinhas),
   uma vez por malha, e guarda em cache.
5. **Peças miúdas ficam sem contorno.** Abaixo de 7 cm (olhos, sobrancelhas, rebites) a casca engole a
   peça. `MIN_OUTLINE_SIZE`.
6. **Largura do contorno:** 5,5 mm, crescendo 5% por metro de distância para não sumir de longe.
   Com 11 mm o rosto virava um borrão preto.
7. **O jogo troca materiais por código, e o toon tem que entrar depois:**
   - `material_override` (placas tingidas do cavaleiro) vence os materiais por superfície, então ele
     também é convertido;
   - a tintura dos goblins (`enemy.gd`, `_apply_tint`) lê `StandardMaterial3D`, então o toon é aplicado
     **depois** dela;
   - a cor por vértice (AO assado das placas, armas pintadas) e a textura das armas traçadas
     multiplicam o albedo dentro do shader;
   - `KnightLook.apply` reaplica o toon a cada troca de equipamento (a chamada é idempotente).
8. **Malha com esqueleto:** a casca fica ao lado da malha, presa ao mesmo esqueleto. Sem esqueleto ela
   é filha da peça e herda transformação e visibilidade.
9. **Translúcido não entra pela conversão comum.** Materiais com transparência ou sem luz (`unshaded`)
   são ignorados por `ToonLook.apply`; o slime tem caminho próprio (abaixo).
10. **PowerShell:** para rodar o Godot com caminho entre aspas é preciso o `&` na frente.

### Do slime (gelatina)
1. **Continua translúcido, com shader próprio.** `toon_slime.gdshader` inclui `toon_light.gdshaderinc`
   (mesma luz em dois tons) e mantém o alfa da variante (`data.goo`). Opaco perdia a cara de gelatina.
2. **A casca invertida funciona em corpo translúcido se o corpo gravar profundidade.** O corpo usa
   `depth_draw_always`; a casca (`toon_slime_outline.gdshader`) vai no passe transparente e é desenhada
   depois (`render_priority = 1`). O teste de profundidade barra a casca atrás do corpo e sobra só a
   silhueta. Sem isso, o fundo da casca escurecia o corpo todo e a transparência sumia.
3. **Borda grossa em degrau.** Perto da silhueta o corpo fica mais opaco e mais escuro, como a espessura
   de uma gota. A malha é facetada, então a borda usa a normal de um elipsoide calculada no vértice;
   com a normal da face, a faixa saía em triângulos soltos.
4. **Olhos e brilho saem da gelatina.** No GLB eles nascem meio afundados no corpo; com contorno, a
   parte de dentro ficava riscada e esverdeada. `ToonLook.apply_slime` desloca essas peças uns 5 cm para
   fora (só no toon).
5. **Ordem das chamadas:** `ToonLook.apply_slime(modelo, cor)` e depois `ToonLook.apply(modelo)`, que
   cuida dos olhos e pula o corpo (já marcado). Os overlays de dano e lentidão são `material_overlay` e
   valem sobre qualquer material.
6. **Limite conhecido:** como o corpo grava profundidade, o contorno de um slime não aparece através de
   outro slime que esteja na frente, e um efeito transparente desenhado depois some atrás do corpo em
   vez de aparecer por dentro dele.

### Do cenário
1. **Um gancho só, em vez de dezenas de chamadas.** O autoload `Toon` (`scripts/autoload/toon.gd`) ouve
   `SceneTree.node_added` e converte toda `MeshInstance3D` e `MultiMeshInstance3D` que entra na cena.
   A conversão roda no quadro seguinte, para pegar materiais atribuídos logo depois do `add_child`.
2. **Material com emissão também converte**, levando cor e energia do brilho (`emission` e
   `emission_energy` do shader). No começo o cenário pulava esses materiais por cautela; o levantamento
   mostrou que quase todos são estáticos (ver "Emissão e materiais que o código altera").
3. **MultiMesh não tem material por instância.** O material toon entra na própria malha compartilhada;
   a cor por instância continua valendo via `COLOR`.
4. **Chão e grama têm shader próprio**, então recebem a mesma luz por `#include` em vez de conversão. O
   uniforme `toon` desliga o estilo com `--notoon` (cai num Lambert simples, não no Burley de antes).
5. **Sombra projetada precisa de tom próprio.** Com o mesmo tom da sombra de forma, a sombra no chão
   ficava fraca e a cena perdia contraste; `cast_tint` é mais fundo.
6. **Degrau largo na sombra projetada.** O borrão da sombra tem ruído; com degrau estreito (0.42–0.58) a
   borda saía granulada.
7. **Servidor dedicado não converte nada.** Sem janela e fora dos testes, `ToonLook.enabled()` é falso.
8. **Capturas de conferência devem usar `--geardemo`** (save à parte). Abrir `hub.tscn` ou
   `colony.tscn` direto usa o save solo de verdade e pode abrir uma partida nele.

### Do clima (WeatherFX)
1. **A camada de neve e chuva recusava qualquer `ShaderMaterial`.** Com o toon, quase tudo vira
   `ShaderMaterial`, e o cenário ficaria sem neve. `ToonLook.is_toon()` diz ao clima que aquele material
   é liso comum.
2. **As árvores usam `tree_wind.gdshader`** (balanço e neve), posto pelo clima no lugar do material do
   GLB. Ele inclui `toon_light.gdshaderinc`, e o clima substitui o material toon se o estilo passou antes.

### Emissão e materiais que o código altera
O material toon é uma **cópia** do `StandardMaterial3D`: mexer no original depois da conversão não muda
mais nada na tela, e não dá erro. Dois casos faziam isso e ganharam `ToonLook.sync(material)`, que dá ao
material um toon só dele (fora do cache compartilhado) e copia cor e emissão a cada chamada:

| Material | Quem altera | Como ficou |
|---|---|---|
| Caldo do caldeirão (`farm/kitchen.gd`) | brilho pulsa a cada quadro; cor muda ao cozinhar | `sync` a cada quadro |
| Terra do canteiro (`farm/farm_plot.gd`) | escurece ao regar | `sync` em `_refresh` (na 0.13.0 a terra regada não escurecia com o toon) |

Regra para código novo: se o material é opaco, iluminado e muda depois de criado, chame
`ToonLook.sync(mat)` ao criar e depois de cada mudança. Sem toon (`--notoon`, servidor) a chamada não faz nada.

**Convertidos com emissão** (todos estáticos): peças dos GLBs (lampião, janelas das casas, forja,
bigorna, fogueira, hortelã e pimenta); anel do portal
(`world/challenge_portal.gd`); ponta da flecha do jogador (`player/projectile.gd`) e haste da flecha
inimiga (`enemies/enemy_arrow.gd`); raio da torre de mago (`colony/tower_shot.gd`); gemas de XP
(`survival/xp_gem.gd`); itens no chão (`world/pickup.gd`); lâminas orbitais (`survival/auto_weapons.gd`);
meteoro da Horda (`survival/survival_mode.gd`) e do cajado (`player/abilities/staff_abilities.gd`); veio
de ouro e cristal (`colony/resource_node.gd`); luzes das construções (`colony/building_visuals.gd`).
Equipamento com brilho (`player/knight_look.gd`) já convertia, pelo caminho dos personagens.

**Ficam como estão**, porque não recebem luz (sem luz não há sombra em dois tons para aplicar):
- sem luz (`unshaded`) ou translúcidos: bola de fogo, raio encadeado, relâmpago, arco e aura das armas
  automáticas, anéis e rajadas do `FX`/`FXEpic`, anel dos elites, redemoinho e faíscas do portal, feixe
  de raridade dos itens, partículas, barras de vida, fantasma e anéis do modo de construção;
- sobreposições de dano e lentidão (`material_overlay`): ficam por cima do toon, sem conflito;
- corpo dos slimes: tem shader próprio (`toon_slime.gdshader`, etapa 3).

**Materiais trocados depois do gancho.** A auditoria (`-- --toonaudit`, ver Ferramentas) rodou na vila,
na horta, na praça, na Horda e na Defesa da Cidade (inclusive durante o `--colonytest`, com construções,
eras e ondas) e não achou nenhuma peça iluminada fora do estilo. Os suspeitos (`resource_node.gd`,
`building_visuals.gd`, `animal.gd`, `farm/*`) atribuem o material no mesmo quadro do `add_child`, e o
gancho pega. O fantasma do modo de construção troca o `material_override` a cada quadro, mas por um
material translúcido sem luz, que o toon não toca.

**Casts para `StandardMaterial3D`/`BaseMaterial3D`.** Nenhum atinge material convertido:
`colony/building.gd` (barra de vida, sem luz); `enemies/enemy.gd` `_apply_tint` (roda antes do toon, no
mesmo `_ready`); `player/knight_look.gd`, `player/weapon_model.gd` e `world/weather_fx.gd` leem o material
da **malha** (`mesh.surface_get_material`), que o toon não altera em `MeshInstance3D` (ele usa override
por superfície); `fx.gd`, `fx_epic.gd`, `vfx/enchant_blade.gd` e as partículas do clima são materiais
sem luz. Atenção ao `MultiMesh`: ali o toon troca o material da própria malha.

### Da luz e do pós-processo (etapa 6)
O estilo entrou material a material, mas o ambiente (`WorldLighting`) era o do sombreado antigo. Com o
estilo ligado, `WorldLighting._toon_tune` troca os valores abaixo; com `--notoon` nada muda. Tudo foi
escolhido por captura comparada (mesma posição e câmera, com e sem cada ajuste, nos quatro climas e
na Horda).

| O quê | Antes | Toon | Por quê |
|---|---|---|---|
| SSAO | ligado (raio 0.8, força 1.6) | desligado | desenhava um halo cinza nos pés, no capim e nas juntas de pedra: mancha sobre cor chapada. O contato vem da sombra projetada |
| Névoa: densidade | 0.002 | 0.0008 | a 300 m cobria ~45% e lavava a serra; agora ~20% |
| Névoa: cor | (0.74, 0.79, 0.86) + 35% da cor do céu | (0.62, 0.74, 0.92), sem cor do céu | a distância vira um véu azul leve, não cinza |
| Ambiente | 0.7 | 0.5 | somado por igual em tudo, aproximava sombra e luz |
| Sol | 1.45 | 1.6 | repõe o brilho que o ambiente tirou, só nas faces acesas |
| Contraluz | 0.4 | 0.3 | no toon ela acende faces inteiras do lado da sombra |
| Saturação | 1.05 | 1.15 | cor cheia |
| Borrão da sombra do sol | 1.6 | 0.6 | o degrau do toon sobre um borrão largo saía pontilhado; curto dá recorte limpo |

Com isso a sombra de forma cai de ~58% para ~53% do tom aceso e a projetada de ~41% para ~34%
(conta por cima: sol × `light_gain` + ambiente). ACES, exposição e brilho (glow) ficaram como estavam.

1. **A serra era degradê por causa da cor, não da luz.** A malha já recebia a luz em dois tons, mas cada
   faceta tinha um tom próprio (ruído contínuo + variação de 7% por face) e a névoa fazia o resto. No
   toon, `ground.gd` (`_terrain_tri`) pinta por faixas: o ruído vira 3 degraus, a variação por face some
   e as passagens grama → mata → rocha são corte seco. Geometria igual; vale também para os maciços
   de dentro do mapa.
2. **O clima parte da base do toon.** `WeatherFX` lê sol, ambiente, névoa e saturação já ajustados. E o
   tempo fechado ficou mais brando no toon, porque a sombra em dois tons depende do sol: com ele a 38%
   e a névoa cheia, chuva e neve viravam um cinza só.

| Clima (tempo fechado) | Antes | Toon |
|---|---|---|
| Sol perde | 62% | 45% |
| Sombra projetada perde | 60% da força | 35% |
| Névoa extra (chuva, neve, poeira) | ×1 | ×0.55 |
| Ganho de ambiente (nuvem, neve) | ×1 | ×0.5 |
| Saturação perde | 0.25 | 0.15 |

Capturas antes/depois (mesma posição e câmera): `docs/screenshots/toon_luz_sol.jpg`, `_chuva`, `_neve`,
`_vento` e `_serra`.

3. **Ficou de fora:** a Defesa da Cidade monta a própria luz (`colony_world.gd`, com ciclo de dia e
   noite) e ainda usa SSAO e névoa antigos; a sombra do próprio corpo na armadura sai em blocos (é
   resolução do mapa de sombra, não do estilo).

### Do desempenho
1. **O custo do contorno é de nós, não de triângulos.** O goblin tem 102 peças (`MeshInstance3D`), 59 delas
   com casca; cada casca era um nó a mais para o motor mover a cada passo. Com os goblins parados quase não
   pesa; andando, pesava 60% do quadro.
2. **Cascas juntadas por grupo.** `ToonLook.apply(modelo, true, true)` junta numa malha só as cascas das
   peças irmãs (mesmo nó pai): 59 → 7 por goblin (braços, pernas, corpo, cabeça, coroa). O desenho é o
   mesmo, porque as peças não têm transformação própria. Só serve para modelo cujas peças não mudam depois
   de montado: os inimigos sim; cavaleiro, soldados e NPCs não (o equipamento troca peça por peça).
3. **De longe a casca não é desenhada** (`visibility_range_end`, 36 m): a 25 m o traço já tem um quarto de
   pixel em 720p.
4. **Opção x linha de comando.** `ToonLook` lê `toon` e `toon_outline` direto do `settings.cfg` (não pode
   depender do autoload `Game`). `--notoon` e `--nooutline` vencem a opção; os testes ignoram a opção.
5. **Medir na Horda cheia é ruidoso.** Duas rodadas iguais diferem em até 60% no tempo de quadro (a partida é
   sorteada e a máquina divide CPU com outros processos). Contagens (nós, draw calls, triângulos, caches)
   são estáveis; para tempo, a bancada `tools/toon_cost.gd ... move` é a que decide.

### Custo medido
Medições de 14/11/2026, Ryzen 7 5700X + RX 9070 XT, 1280×720, vsync desligado. **Medido** tem número e
ferramenta; o que é **suspeita** está marcado. Não há meta de desempenho combinada para o jogo.

**Bancada: 80 goblins, luz do jogo** (`tools/toon_cost.gd`, quatro rodadas de cada):

| | Sem toon | Toon, casca por peça (antes) | Toon, cascas juntadas (depois) |
|---|---|---|---|
| Quadro, goblins parados | 3,7–5,0 ms | 4,5–6,6 ms | 3,3–5,0 ms |
| Quadro, goblins andando (`move`) | 13,2–19,5 ms | 23,9–31,4 ms | 15,1–16,5 ms |
| Draw calls | 445 | 505 | 452 |
| Objetos desenhados | 22 mil | 26,8 mil | 22,6 mil |
| Triângulos | 505 mil | 642 mil | 642 mil |

**Horda real** (`--geardemo --survival --hordedemo --toonprobe=50 --proberound=12`: rodada 12 fixa, 90
inimigos vivos, jogador imortal e sem carta de nível). Nesse regime o jogo fica saturado, entre 100 e 200 ms
por quadro **com ou sem toon**:

| | Sem toon | Toon sem contorno | Toon antes | Toon depois |
|---|---|---|---|---|
| Quadro médio (cada valor é uma rodada) | 115 · 122 · 133 · 172 · 174 ms | 111 ms | 135 · 195 · 195 ms | 101 · 149 · 151 · 165 ms |
| Cascas por inimigo nascido | 0 | 0 | 27 | 3,5–4,6 |
| `ToonLook.apply` por inimigo | 0 | 0,65 ms | 1,05 ms | 0,70–0,91 ms |
| Pior `apply` depois da carga | — | 3,0 ms | 5,4 ms | 2,8–3,9 ms |
| Draw calls (média) | 4,4–6,3 mil | 3,2 mil | 3,6–4,2 mil | 3,3–4,4 mil |
| Triângulos (média) | 0,62–0,84 mi | 0,61 mi | 0,72–0,99 mi | 0,69–0,96 mi |

- Medido: nos três pares rodados em seguida, o toon com casca por peça ficou 12%, 13% e 18% acima do
  sem toon; sem contorno, empatou. Depois de juntar as cascas a diferença some no ruído.
- Medido: o quadro em que nasce inimigo não é mais lento que os outros (135 ms x 154 ms na rodada de 190 s).
- Medido: a GPU quase não trabalha (1,5–2,1 ms por quadro); o tempo está em script e física (40–58 ms de
  `_process`, 23–32 ms de física por quadro).
- Investigado depois (não era do toon): a Horda cheia ficava presa no teto de 8 passos de física por quadro,
  movendo as 102 malhas soltas de cada goblin a cada passo. Corrigido com as peças juntadas por grupo
  (`scripts/enemies/enemy_model.gd`); relatório e números em `docs/desempenho/horda-2026-11-14.md`.
  Os tempos da tabela acima são de antes dessa correção.

**Primeira vez de cada malha** (a casca é calculada uma vez e fica em cache):

- Medido: na carga da vila, 246–254 cascas levam 140–210 ms no total; o `apply` do cavaleiro do jogador, que
  calcula quase todas, leva 56–79 ms. Fica dentro do quadro de carga da cena (1,9–2,1 s).
- Medido: na cidade (`--colonytest` com janela), um tipo novo de unidade aparecendo no meio da partida custa
  até 33 ms uma vez.
- Suspeita: perceptível só como um engasgo isolado na primeira aparição; pré-calcular as cascas na tela de
  carga resolveria, se incomodar.

**Gancho de cena** (`scripts/autoload/toon.gd`, converte no quadro seguinte ao da entrada):

| Cena | Malhas no maior lote | Tempo do lote | Quadro de carga da cena |
|---|---|---|---|
| Vila (`world.tscn`) | 4776–5716 | 29–32 ms | 1,9–2,1 s |
| Praça (`hub.tscn`) | 4806 | 22 ms | 1,2 s |
| Cidade (`colony.tscn`) | 5209 | 11 ms | 3,8 s |

- Medido: o gancho é 1–2% do quadro de carga; durante a Horda vê ~130 malhas por segundo (efeitos, gemas,
  peças de inimigo) e gasta 0,8 ms por segundo. Converter em lotes por quadro não se paga.

**Caches** (`_mats`, `_hulls`, `_merged`):

- Medido: Horda de 190 s, 342 inimigos nascidos: 256 materiais, 246 cascas e 8 cascas juntadas aos 5 s e os
  mesmos números no fim. Não crescem com o número de inimigos.
- Medido: no teste da cidade (105 s) vão de 148 a 364 materiais e de 72 a 473 cascas, conforme aparecem
  tipos novos de construção e unidade.
- Suspeita: o teto é a variedade de conteúdo (malhas e cores distintas); não foi medido numa partida longa
  de cidade.

**O que foi feito e o que foi descartado**

| Candidato | Decisão | Por quê |
|---|---|---|
| Juntar cascas por personagem | feito (inimigos) | era o custo medido: 59 nós a mais por goblin |
| Contorno só até certa distância | feito (36 m) | barato; ganho não medido isolado (na Horda tudo fica perto) |
| Sem contorno em inimigos comuns acima de N | não feito | com as cascas juntadas o contorno deixou de pesar |
| Converter em lotes no gancho | não feito | 11–32 ms dentro de cargas de 1–4 s |

**Não medido:** GPU fraca ou integrada (os triângulos a mais, +27% na bancada, podem pesar lá); cliente em
partida em grupo; cidade com muitos soldados (cavaleiros seguem com casca por peça: 36 por soldado).

### Opções no menu
"Estilo desenhado" e "Contorno nos personagens" ficam no painel de opções (`scripts/ui/options_panel.gd`),
gravadas em `settings.cfg` como `toon` e `toon_outline`. Desligar o contorno vale na hora (as cascas ficam
no grupo `toon_outline` e são escondidas); o resto vale para o que for criado dali em diante, e o cenário
já montado muda ao trocar de área. O painel avisa isso ao mexer na opção.

## Onde o estilo já está

| Quem | Por onde |
|---|---|
| NPCs da vila (ancião, mercadora, ferreiro) | `scripts/world/npc.gd` |
| Jogador, soldados, prévia do personagem, armas | `scripts/player/knight_look.gd` (fim de `apply`) |
| Inimigos | `scripts/enemies/enemy.gd` |
| Slimes (jogo e menu), gelatina translúcida | `ToonLook.apply_slime`, chamada por `enemy.gd` e `main_menu.gd` |
| Caravana e aldeão perdido | `scripts/colony/caravan.gd` |
| NPCs da praça | `scripts/hub/hub_point.gd` |
| Cavaleiro, goblin e slime do menu | `scripts/ui/main_menu.gd` |

| Props, construções, árvores, vegetação em MultiMesh | autoload `Toon` (`scripts/autoload/toon.gd`) |
| Chão, grama e árvores com vento | `ground.gdshader`, `grass.gdshader` e `tree_wind.gdshader`, via `toon_light.gdshaderinc` |

## Plano de migração

| Etapa | O que | Estado |
|---|---|---|
| 1 | Personagens, com contorno | feito |
| 2 | Cenário: props, construções, árvores, vegetação, chão e grama, sem contorno | feito |
| 3 | Slimes: gelatina translúcida em dois tons, borda grossa e contorno só na silhueta | feito |
| 4 | Peças com emissão e efeitos (lamparinas, portal, projéteis): convertem mantendo o brilho; efeitos sem luz ficam como estão | feito |
| 5 | Materiais trocados ou alterados por código depois do primeiro quadro: `ToonLook.sync` e auditoria `--toonaudit` | feito |
| 6 | Ajuste global de luz e pós-processo: SSAO, névoa, sol/ambiente/contraluz, clima e serra em faixas chapadas (vila, praça e Horda) | feito |
| 6b | O mesmo ajuste na luz própria da Defesa da Cidade (`colony_world.gd`) | a fazer |
| 7 | Desempenho: medido na Horda e nas cargas de cena; cascas juntadas nos inimigos e corte do contorno ao longe | feito |
| 8 | Opção no menu (estilo e contorno ligados/desligados); `--notoon` e `--nooutline` vencem | feito |
| 9 | Rosto dos NPCs sem sombra de forma, como no estudo | em aberto |

## Ferramentas

```powershell
$G = "C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe"
# foto lado a lado (antigo à esquerda, toon à direita) de qualquer modelo, com a luz do jogo
& $G --path . --resolution 1400x1000 --script res://tools/toon_shot.gd -- goblin saida.png 3q
# slime: gelatina antiga à esquerda, toon à direita; goo=RRGGBBAA troca a cor da variante
& $G --path . --resolution 1400x1000 --script res://tools/toon_shot.gd -- slime saida.png 3q goo=8c40d9cc
# custo numa multidão
& $G --path . --resolution 1280x720 --script res://tools/toon_cost.gd -- 80 toon
# idem, com as cascas juntadas e os goblins andando (o caso que pesa)
& $G --path . --resolution 1280x720 --script res://tools/toon_cost.gd -- 80 toon merge move
# sonda dentro do jogo: Horda na rodada 12 por 50 s (com --notoon ou --nooutline para comparar)
& $G --path . --resolution 1280x720 res://scenes/world.tscn -- --geardemo --survival --hordedemo --toonprobe=50 --proberound=12
# conferir as cascas juntadas: toon por peça à esquerda, juntado à direita
& $G --path . --resolution 1400x1000 --script res://tools/toon_shot.gd -- goblin saida.png 3q merge
# jogo com o sombreado antigo, para comparar
& $G --path . res://scenes/world.tscn -- --notoon
# auditoria: depois de 5 s lista no console as peças visíveis que ficaram com material iluminado comum
& $G --path . res://scenes/colony.tscn -- --geardemo --toonaudit=5
```

A prévia em Blender (`toon_preview.py`, fora do repositório) serviu só para decidir se valia a pena;
o que vale é a foto no Godot.
