# Balanceamento da progressão

Guia dos números que decidem o ritmo do jogo: nível dos monstros, XP, nível dos itens e das missões, loot.
Tudo se muda à mão, sem mexer em código. Os arquivos `data/balance/*.json` abrem no editor de texto do Godot
(duplo clique no FileSystem); os campos dos mapas ficam no Inspector.

Depois de mexer em qualquer número, **rode o simulador** e os testes (seção "Como conferir" no fim).

## Metas que os números perseguem

- **35 horas até o nível 50**: 1–10 ~2,5 h, 10–20 ~5,5 h, 20–35 ~11,5 h, 35–45 ~8 h, 45–50 ~7 h (eram 30 h antes do
  ajuste de dificuldade: a XP ficou igual e cada abate demora mais).
  O mundo aberto vai até o nível ~45 (Pico 30–45, Cume Maldito 42–45); a faixa 45–50 é a dungeon final (Abismo
  de Valdoria, 45–50) e as camadas 5 do craft.
- **Monstro comum do mesmo nível morre em 5 a 8 golpes** do ataque básico (guerreiro, arqueiro, mago; healer até
  10), com todos os pontos no atributo da classe e a melhor arma que o nível deixa usar. O goblin leva 6–8, o slime
  3–4, o esqueleto 7–10.
- **O jogador morre em 5 a 6 golpes de um goblin do mesmo nível** sem pontos em VIT e com a armadura do nível
  (~10 de um slime). Dois ou três monstros juntos pedem esquiva, bloqueio ou cura.
- **0,5 a 0,8 item por monstro comum**, quase tudo material.

O teste `tests/unit/test_progression_pacing.gd` falha se as horas saírem mais de 20% do alvo, se os golpes saírem
de 5–8 ou se os itens por morte saírem de 0,5–0,8 (slime, goblin, esqueleto, raptor-capim).

## `data/balance/progression.json`

### `max_level`
Nível máximo (50). No máximo a XP para de contar. Subir exige estender `xp_curve.late` e conferir as faixas.

### `xp_curve` — XP para subir de nível
`XP para sair do nível L = base × L^exp × late[L]`

| Botão | Hoje | O que faz | Faixa segura |
|---|---|---|---|
| `base` | 250 | escala a curva toda (todas as faixas juntas). Tem de ser número inteiro | 150–400 |
| `exp` | 2.4 | quanto os níveis altos custam a mais que os baixos | 2.0–2.6, **sempre perto de `enemy_curves.xp.exp`** |
| `late` | 45: 1.2 … 49: 1.6 | multiplicador só desses níveis: a "parede" do fim | 1.0–2.5 cada |

`exp` e a curva de XP dos monstros andam juntos: o tempo num nível é "XP do nível ÷ XP do monstro". Se você sobe
um e não o outro, o fim do jogo fica muito mais longo (ou curto) que o começo. Para deixar tudo mais longo ou
mais curto por igual, mexa só em `base` (ou em `sim.downtime_per_kill`, que não muda o jogo, só a estimativa).
Para mexer só no fim, use `late`.

Depois de mudar `xp_curve` ou `quest_xp_share`, rode `python tools/balance/set_quest_levels.py --write` para o
XP das missões acompanhar (ver "Missões" abaixo).

### `xp_diff` — XP pela diferença de nível
Linhas `[de, até, multiplicador]` da diferença (nível do monstro − nível do jogador; em grupo, o maior nível do
grupo). Hoje: até −8 → 5%; −7..−5 → 25%; −4..−3 → 70%; −2..+2 → 100%; +3..+4 → 115%; +5 ou mais → 125%.
Seguro: manter a linha do meio em 1.0 e não deixar buraco entre as faixas (diferença sem linha = 100%).

### `enemy_curves` — o monstro no nível L
Para cada atributo, `curva(L) = (1 + rate × (L − 1))^exp`, e o monstro no nível L tem
`número do enemies.json × curva(L) ÷ curva(ref_level)`.

| Atributo | Hoje (`rate`, `exp`) | O que conferir no simulador | Faixa segura |
|---|---|---|---|
| `hp` | 0.24, 1.05 | colunas `g.*` (golpes): têm de ficar entre 5 e 8 | rate 0.20–0.30, exp 1.0–1.1 |
| `dmg` | 0.08, 1.0 | (o simulador não mede) quantos golpes o jogador aguenta; hoje 5–6 de um goblin do mesmo nível em qualquer nível, sem pontos em VIT (já com `rank.common.dmg`) | rate 0.05–0.12 |
| `xp` | 0.28, 2.4 | coluna `xp mob` e as horas por faixa | exp perto de `xp_curve.exp` |
| `gold` | 0.04, 1.0 | ouro por abate (não entra no simulador). Cresce com o nível: goblin nv 6 ~8,7 (hoje ~7,5), goblin nv 30 ~15,6, esqueleto nv 25 ~13, Lich nv 42 ~580. Como cada abate leva mais golpes que hoje, o ouro por hora cai um pouco | rate 0.03–0.05 |

O dano do jogador cresce quase em linha reta com o nível (3 pontos por nível × 1,4–1,6 de dano por ponto), por
isso a vida usa expoente perto de 1. Vida subindo mais rápido que isso faz os golpes passarem de 8 no fim.

### `tier_size`, `tiers` — camadas de 10 níveis
A cada `tier_size` níveis o monstro muda de camada: `tint` (cor multiplicada) e `scale` (tamanho). Só visual.
A camada também é usada pelo loot. Seguro: `scale` 1.0–1.3.

### `elite` — monstro de elite
Vale para pontos com `elite` ligado no Inspector: `level_bonus` (níveis a mais, hoje 2), `hp` (vida × 2),
`dmg` (dano × 1,3), `scale` (tamanho × 1,25), `gear_chance` (chance de equipamento, 5%).

### `rank` — dificuldade por categoria (comuns, campeões, chefes)
Multiplica vida e dano dos monstros **com nível** por categoria, por cima da curva. **`common` é o botão da
dificuldade geral do mundo** (a Horda não muda): hoje vida × 2 e dano × 2,3 — antes de existir (× 1 e × 1) o
goblin morria em 4 golpes, o slime em 2, e o jogador aguentava ~13 golpes. `elite` (tipos com
`elite: true` no enemies.json: Campeão Goblin, Cavaleiro Esqueleto, Slime Rainha) hoje vida × 2 e dano × 3,45;
`boss` (tipos com `boss: true` **e** chefes de dungeon, mesmo de um tipo elite) hoje vida × 3 e dano × 4,83.
Os blocos **não se multiplicam entre si**: o dano de `elite` e `boss` já traz os × 2,3 dos comuns embutidos
(1,5 × 2,3 e 2,1 × 2,3), e a vida deles ficou como era. Ao mexer em `common.dmg`, mexa nos outros dois na mesma
proporção, senão um comum passa a bater mais que um campeão.

Um tipo pode ter o próprio bloco `"rank": {"hp", "dmg"}` no enemies.json, que vale no lugar do da categoria
(menos quando ele é chefe de dungeon): o Rei Goblin da missão (vida × 1,8, dano × 3,68) e os comuns
"parrudos" — Goblin Bruto, Golem de Cristal e Ieti, com vida × 1,25 em vez de × 2, porque já levavam 13–14
golpes e com × 2 passariam dos campeões.
Existe porque a curva divide pelo `ref_level`: sem isto, um chefe de ref 12 no nível 21 ganhava menos por nível
que um comum de ref 2 (o Goblin Bruto comum batia mais que o Campeão, e o Rei Goblin menos que o Cavaleiro).
O teste `test_rank_order_at_same_level` cobra, nos níveis 8, 21 e 40: todo campeão com mais vida e dano que
qualquer comum (fora os que explodem) e todo chefe mais que qualquer campeão. A Horda não tem nível: não muda.

### `danger` — monstro de placa vermelha
Quando o monstro está `diff` (hoje 5) ou mais níveis acima de quem ele enfrenta, a placa fica vermelha (também
nos chefes e elites) e ele ganha contra esse jogador: dano × `dmg` (1,3) e dano recebido × `taken` (0,75). Cada
nível a mais soma `dmg_per_level` (0,05) e tira `taken_per_level` (0,03), até `dmg_max` (2,0) e `taken_min`
(0,5). Ex.: nível 21 contra jogador 11 = dano × 1,55 e leva × 0,6. No servidor conta o nível de cada jogador
(o de quem bateu, o de quem levou o golpe), então no grupo cada um vê o próprio bônus.

### `gear_drop` — equipamento que cai
| Botão | Hoje | O que faz |
|---|---|---|
| `chance` | 0.02 | chance de um equipamento por monstro comum. Vai cair para ~0.005 quando o craft existir |
| `boss_chance` | 1.0 | chance nos chefes (`boss: true` no enemies.json) |
| `window` | [-3, 1] | só caem itens com nível entre nível do monstro −3 e +1 |
| `rarity_weight` | comum 60, incomum 28, raro 10, épico 2, lendário 0 | peso de cada raridade no sorteio |

Itens com `named: true` nunca caem por aqui (só da lista do chefe ou de missão).

### `quest_xp_share`
Que fração da XP de cada nível as missões devem dar (hoje 0.3 = 30%): entra no `reward_xp` que o
`set_quest_levels.py` calcula. O simulador desconta da caça a XP que as missões **de verdade** dão em cada faixa
(soma do `reward_xp` das missões com nível na faixa), no máximo `quest_xp_share`. Hoje: 1–10 28%, 10–20 25%,
20–35 13%, 35–45 14%, 45–50 0% (quase não há missões acima do 20). O teste das missões exige que as missões até o
nível 10 deem 20%–45% da XP dos níveis 1–9. Se mudar, rode o `set_quest_levels.py --write`.

**Quando as partes 2–4 trouxerem missões novas (principalmente acima do nível 35)**, rode o
`set_quest_levels.py --write`, depois o simulador: com mais XP de missão as faixas encurtam, e a curva
(`xp_curve.base`) tem de ser recalibrada para voltar às horas alvo.

### `sim` — só o simulador (não muda o jogo)
| Botão | Hoje | O que é |
|---|---|---|
| `attack_interval` | 0.9 | segundos entre golpes |
| `downtime_per_kill` | 12 | segundos andando/procurando entre um abate e outro |
| `talent_damage` | 0.0 | bônus de dano dos talentos na conta dos golpes (0.1 = +10%) |
| `ref_enemy` | goblin | o monstro comum de referência |
| `ref_class` | warrior | a classe que "caça" na conta das horas |
| `bands` | [1,10] … [45,50] | as faixas somadas (de, até: soma os níveis de..até−1) |
| `target_hours` | 2,5, 5,5, 11,5, 8, 7 | horas alvo por faixa: o simulador mostra ao lado e o teste cobra ±20% |

O simulador não conta os pontos de atributo dos ranks da guilda, comida, buffs, críticos nem as habilidades: é a
build pura com o ataque básico. Por isso o jogo de verdade é um pouco mais rápido que a tabela.

## `data/balance/enemies.json`

- `hp`, `damage`, `xp`, `gold`: o monstro no seu `ref_level`. São também os números da **Horda** (que cria
  monstros sem nível): mudar aqui muda lá.
- `ref_level`: o nível em que os números acima valem. Hoje **2 para os monstros comuns**: como usam o mesmo, no
  mesmo nível a proporção entre eles é a do arquivo (o esqueleto, 95 de vida, tem ~1,2× a vida do goblin, 80, em
  qualquer nível; o slime metade). Chefes e elites têm o próprio: Goblin Dourado 4, Campeão Goblin 6, Cavaleiro
  Esqueleto 6, Slime Rainha 6, Lich 10, Rei Goblin 12. Com eles e o `rank` do progression.json (vida × 2 nos
  campeões, × 3 nos chefes), um guerreiro nível 21 com a melhor arma da faixa (golpe ~136) leva, contra
  monstros também nível 21, ~17 golpes no Campeão, ~43 na Rainha como chefe de dungeon e ~92 no Lich. Subir o `ref_level` de um tipo deixa ele **mais fraco**
  em todos os níveis (o número do arquivo passa a valer num nível mais alto).
  O Rei Goblin nasce no próprio `ref_level` (ele não tem ponto no mapa); mudar esse número muda o nível dele.
- `loot`: `[item, chance]`, cada linha sorteada à parte. Material da família (orelha, gosma, osso...) é o
  principal; poção e semente ficam baixas (1%–10%) para a média ficar em 0,5–0,8 item por morte. A coluna "Itens
  por morte" do simulador mostra a média de cada tipo.
- `boss: true` usa `gear_drop.boss_chance` e o bloco `rank.boss`; `elite: true` dá o nome, o visual e o bloco
  `rank.elite` (a elite do ponto no mapa é outra coisa: bloco `elite`).
- **Chefes**: 1 material raro garantido (coroa, cristal...) + o equipamento da janela de nível
  (`boss_chance` 1.0) + uma **chance pequena** de item nomeado, somando 0,2–0,35 por abate entre todos os
  nomeados da lista (Rei Goblin: Cutelo 25%; Lich: Montante 12%, Cajado do Arquimago 8%, Arco da Tempestade 6%,
  Presa do Dragão 4%). Resultado: 1–2 equipamentos por abate. O nomeado da lista tem `level` até o nível do
  chefe + 2 (Rei 12 → Cutelo 14; Lich 42 → até 44). Se o item também é recompensa de missão ou vendido na
  loja, não mude o `level` dele: baixe a chance na lista. O teste `test_boss_drops` cobra essas três regras.

## `data/balance/items.json` — `level` dos itens

`level` é o nível mínimo para equipar (sem o campo = 1). Faixas por raridade usadas na migração: comum 1–8,
incomum 8–15, raro 14–24, épico 22–35, lendário 35–45. Pode fugir da faixa quando faz sentido (recompensa de
missão, kit básico).

- **Armas** decidem os golpes: o simulador escolhe a melhor arma não nomeada de nível ≤ L. Se uma classe pular de
  uma arma fraca para uma muito forte, os golpes caem para 3 ou menos naquele nível; espaçar o `level` das armas
  resolve. A última coluna do simulador mostra a arma escolhida por nível.
- **Recompensa de missão** equipável: `level` ≤ nível da missão + 2, para dar para usar ao receber. Se isso põe o
  item abaixo da faixa da raridade dele, marque `"named": true` para ele não cair de monstro (hoje: royal_plate,
  knight_helm, sage_amulet, iron_gauntlets).
- O `level` também decide em que monstros o item pode cair (`gear_drop.window`).

## `data/balance/quests.json` — `level` e `reward_xp` das missões

`level` é a faixa da missão (o nível dos monstros-alvo, ou o da missão anterior da corrente). `reward_xp` sai de
`quest_xp_share × XP do nível × peso` (1,5 principal, 1,0 secundária, 0,6 contrato do quadro).
O script `python tools/balance/set_quest_levels.py` mostra a tabela e, com `--write`, grava os dois campos de
todas as missões, apagando ajustes feitos à mão. Para fixar o nível de uma missão, ponha no dicionário
`OVERRIDES` do script (hoje `kael_sumiu: 30`; `festa`, `registro`, `quadro`: 11, o nível de quem acabou de
vencer o Rei Goblin, e que `bosque` e `tico` herdam pela corrente; as do Natal: 6). Missões de evento
sazonal (`"event"`, ex.: Natal) não entram na conta do ritmo: o simulador e o teste das missões as ignoram. Só para mudar o XP de uma missão, edite `reward_xp` no JSON e
não rode o script de novo.

## Ponto de monstro (EnemySpawn) no Inspector

Nos mapas (`scenes/maps/*.tscn`, grupo Monstros), cada ponto tem:

- `level`: nível dos monstros. **0 = a faixa da região com nome** onde o ponto fica (seção abaixo); fora de
  região, sem nível (números do enemies.json direto, sem placa "Nv" e sem ajuste de XP, como na Horda). Um
  `level` maior que 0 manda sobre a região (os pontos da parte 1 continuam com o nível deles).
- `level_max`: fim da faixa. Cada monstro sorteia um nível entre `level` e `level_max` ao nascer (0 = sempre
  `level`). Faixas dos mapas: Vale 1–13, Bosque 12–20, Mina 20–30, Pico 30–45.
- `elite`: monstros de elite (bloco `elite` do progression.json): +2 níveis, vida × 2, 25% maiores, 5% de chance
  de equipamento.

Um monstro do mesmo nível do jogador morre em ~7 golpes; 5 níveis acima já pede ~10–12 e dá 125% de XP; 8 abaixo dá
5% de XP. Para uma área mais difícil, suba a faixa, não a vida no enemies.json.

## `data/balance/regions.json` — regiões com nome

Cada mapa tem regiões de monstros (Campos do Norte, Toca dos Goblins, Cume Maldito...). A **forma e o lugar** são
nós `MapRegion` nas cenas (grupo Regiões; ver `docs/EDITOR_MAPA.md`); os **números** ficam aqui, na chave
`region_id` do nó:

| Campo | O que faz | Valor seguro |
|---|---|---|
| `name` | nome no mapa, no atlas, sob o minimapa, no letreiro de entrada e no objetivo das missões | curto (cabe sob o minimapa) |
| `level_min`, `level_max` | faixa de nível dos pontos de monstro com `level` 0 dentro da região; aparece como "Nv a–b" | sem buraco entre regiões vizinhas do mesmo mapa |
| `density` | multiplica o `count` dos pontos dentro da região (1,5 = 50% mais monstros; 0 esvazia) | 0,5–2 (medir o servidor acima de 1,5) |
| `show_on_map` | false esconde a região do mapa e do atlas (o letreiro e as missões continuam) | true |

Missões citam uma região com `"region": "<id>"` no quests.json: o objetivo ganha o nome da região, o rastreador
aponta para o centro dela, e só contam abates de monstros que nasceram lá dentro. Sem `region`, conta em qualquer
lugar.

**Desempenho:** monstro do mundo parado e sem jogador a menos de `enemy_sleep_radius` metros
(`data/balance/rules.json`, hoje 60) dorme: sem IA nem física. É o que deixa o servidor com ~300 monstros no
mesmo custo de antes com ~100. Raio menor que o alcance de perseguição dos monstros faz eles "acordarem" tarde;
0 desliga o sono. Depois de subir densidades, meça com `--netstats` no servidor (linha `process`/`physics` em ms).

## Profissões e craft (`professions.json`, `recipes.json`, `world_nodes.json`, `crops.json`)

Sete profissões, todas até o nível 50 por personagem (aba **Profissões** do livro, tecla L): Mineração, Lenhador e
Fazenda (coleta); Ferraria, Couraria, Alquimia e Culinária (produção). Ferraria = espadas e peças de metal (forja do
Doran, "Forjar"); Couraria = arcos, aljavas e peças de couro (Bancada de Couraria, a leste do empório); Alquimia =
poções, essências, cajados, cetros, orbes e amuletos (Pip, "Alquimia"); Culinária = o caldeirão.

**`professions.json`**

| Botão | Hoje | O que faz | Faixa segura |
|---|---|---|---|
| `xp_curve.base`, `exp` | 20, 1,3 | XP para subir: `base × nível^exp` (nível 10 pede ~400; 49 pede ~3.200) | base 15–40, exp 1,2–1,5 |
| `xp_diff` | ≤ −10: 10%; −9..−5: 50% | XP de receita/nó bem abaixo do nível da profissão (contra o trabalho braçal) | não dar 100% abaixo de −5 |
| `first_craft_mult` | 3 | a primeira fabricação de cada receita rende 3× (premia variar) | 1–4 |

**`recipes.json`** (uma receita por linha; gerado uma vez por `tools/balance/make_recipes.py`, depois à mão):
`station` (kitchen, forge, leather, alchemy), `prof`, `level` (nível da profissão que pede), `ingredients`,
`gold` (taxa da bancada), `out` e `qty` (o que sai), `xp`, `learn` (`npc` = todos sabem; `scroll` = precisa do
pergaminho `scroll_<receita>`, que cai dos chefes). Regras do catálogo de hoje:

- Materiais por camada (níveis 1–10, 11–20, 21–30, 31–40, 41–50): minério (cobre, ferro, prata, mithril,
  astralita), tora (pinho, carvalho, bétula-prata, freixo-cinza, madeira-de-alma), couro (`hide_t1..5`, cai de
  qualquer monstro do mundo da camada) e essência (`essence_t1..5`, só da Alquimia: 2 couros + 1 parte de monstro).
  Todo equipamento pede a essência da camada.
- A receita de maior nível de cada camada em cada profissão pede a **peça do chefe** (Coroa do Rei Goblin, Geleia
  Real da Slime Rainha, Selo do Cavaleiro, Filactério do Lich, Núcleo do Abismo) e é por pergaminho; a camada 5
  inteira também. Os pergaminhos e as peças estão no `loot` dos chefes no enemies.json.
- O equipamento que já existia virou receita no próprio nível (os nomeados continuam só de chefe). Itens novos
  (`"craft": true`, não caem de monstro): os buracos das camadas 3–5 (prata, mithril, astral, madeira-de-alma).

**Qualidade** (`progression.json`): `quality_chance.per_level` (2% por nível da profissão acima da receita, até
`max` 40%; `obra_share` 25% disso é obra-prima) e `quality_mult` (fina 1,15×, obra-prima 1,3× em dano, defesa,
bônus e preço). O item sai com sufixo (`iron_sword@fina`); as variantes são geradas sozinhas a partir do item base
(não edite `@` no items.json) e não caem de monstro. O encanto da arma vale para todas as qualidades dela.

**Bônus de ofício** (`progression.json` `craft_affix`): equipamento fabricado das raridades em `rarities` (raro,
épico, lendário) sai sempre com um bônus sorteado por igual entre os `affixes`. Valor = `base + per_level × nível da
receita` (atributos: 1 + 0,06/nível, ou seja +2 no 17 e +3 no 35; crítico e velocidade 2% + 0,05%/nível; vida
10 + 1/nível; roubo de vida 1% + 0,03%/nível); a qualidade multiplica o bônus junto com o resto e o preço sobe
`price_mult` (1,25×). O bônus vai no id depois da qualidade (`knight_blade@fina~urso`) e as variantes são geradas
sozinhas. Faixa segura: bônus de atributo até metade do maior atributo do item base.

**Falha** (`progression.json` `craft_fail`): só equipamento falha. `chance` por raridade (comum 0, incomum 5%,
raro 15%, épico 25%, lendário 35%), menos `per_level` (1 ponto) por nível da profissão acima da receita, nunca
abaixo de `floor` (40%) da chance da raridade. Na falha o ouro é gasto, volta `refund` (metade) de cada material
(a unidade ímpar volta em metade das vezes) e a XP vale `xp_mult` (0,5), sem bônus de primeira vez.

**Couro no loot** (`progression.json` `tier_drop`): `chance` 15% por monstro do mundo com nível (1 couro da camada;
`elite_qty` 2, `boss_qty` 3). Para caber na meta de 0,5–0,8 item por morte, as partes comuns caíram: gosma e
garra 40%, orelha e osso 55%, seda, língua e asa 45%.

**Coleta** (`world_nodes.json`, um tipo de nó por linha): `item`, `amount`, `hits` (2–3 golpes), `respawn`
(segundos), `model` (rocha `ore` na cor `tint`, `iron`, `crystal` ou árvore `tree_*`), `prof`, `level` (nível que
pede; sem ele os golpes não contam) e `xp`. Ferro e cristal pedem nível 1 (o encantamento usa os dois cedo).
**Fazenda** (`crops.json`): `level` da semente (pimenta 2, hortelã 3, abóbora 5) e `xp` da colheita.

**Loja** (`shop.json`): só o básico — poções, sementes, material da camada 1 (cobre, pinho, couro cru) e
equipamento comum de nível até 10. O resto do equipamento vem do craft e dos chefes.

## Dungeons (`progression.json` `dungeons`, salas no `regions.json`)

Quatro dungeons compartilhadas (todos que entram veem a mesma), com porta no mapa de fora e rank da guilda:
Covil das Raízes (Bosque, Rank C, 16–20), Galerias Profundas (Mina, B, 26–30), Cripta de Cinzas (Pico, A, 36–40)
e Abismo de Valdoria (Pico, no Cume Maldito, A, 45–50). Cada uma tem 3 salas (`dg_<id>_entrada`, `_galeria`,
`_trono` no regions.json): a faixa de nível das salas é o "+3 a +5 acima da região de fora" do projeto. Morrer lá
dentro devolve na porta de fora (com a penalidade de morte de sempre).

| Botão | Hoje | O que faz | Faixa segura |
|---|---|---|---|
| `per_player` | 0,5 | cada jogador a mais dentro soma 50% dos monstros de cada ponto | 0,25–1 |
| `max_mult` | 2,5 | teto da população (×base) | 1,5–3 (medir com `--netstats`) |
| `respawn_per_player` | 0,3 | cada jogador a mais encurta a volta dos monstros (respawn ÷ (1 + 0,3 × (n − 1))) | 0–0,5 |
| `boss_respawn` | 10 | minutos até o chefe voltar | 5–30 |
| `loot.<id>.monster` / `.boss` | couro/essência; peça + pergaminhos | loot extra (`[item, chance]`) de quem morre na dungeon | peça do chefe 1.0 |

A base de cada dungeon é para **um** jogador bem equipado da faixa; o `per_player` só aumenta monstros e ritmo.
O chefe é o ponto com `chief` ligado no Inspector (barra de chefe, volta em `boss_respawn`, loot de chefe). O loot
é sorteado para cada jogador que acertou o monstro. Com as dungeons o servidor tem ~400 monstros: os que não têm
jogador perto dormem (`enemy_sleep_radius`), por isso o custo ficou como o de antes.

## Como conferir

Simulador (na raiz do projeto; `$GODOT` = o executável do Godot):

```
& "C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path . -s tools/progression_sim.gd
```

Imprime:

1. **Por nível**: XP para o próximo, vida e XP do goblin naquele nível, dano (`d.*`) e golpes (`g.*`) de cada
   classe, minutos no nível e as armas escolhidas.
2. **Horas por faixa** × alvo, e quanto da XP de cada faixa as missões do quests.json dão.
3. **Golpes do guerreiro em cada monstro** nos níveis 5, 15, 25 e 40 (vida/golpes). Chefes e elites ficam bem
   acima de 5 de propósito.
4. **Itens por morte** de cada monstro comum.

Depois rode os testes unitários:

```
& "C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path . -s tests/unit/run.gd
```

Receitas rápidas:

- *Tudo está rápido demais (ou lento)*: `xp_curve.base` (ex.: 250 → 290 deixa todas as faixas ~16% mais longas).
- *O fim (45–50) está curto*: suba os `late`.
- *O mundo todo está fácil (ou difícil) demais*: `rank.common` — `hp` muda os golpes para matar (2,0 = goblin em
  ~7; 1,5 = ~6; 1,0 = ~4), `dmg` os golpes que o jogador aguenta (2,3 = 5–6 de um goblin; 1,7 = ~8; 1,0 = ~13).
  Leve `rank.elite.dmg` e `rank.boss.dmg` na mesma proporção.
- *Só os chefes batem forte demais*: baixe `rank.boss.dmg` (4,83 → 3,5, por exemplo).
- *Os golpes saem da meta só nos níveis altos (ou só nos baixos)*: `enemy_curves.hp.rate` (0.24 → 0.28 sobe mais
  no fim).
- *Só uma classe destoa*: confira a arma escolhida na última coluna e o `level` das armas daquela classe.
- *Caem itens demais*: baixe a chance de poção/semente no `loot` do monstro, ou `gear_drop.chance`.
