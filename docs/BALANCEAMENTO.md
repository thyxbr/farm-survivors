# Balanceamento da progressão

Guia dos números que decidem o ritmo do jogo: nível dos monstros, XP, nível dos itens e das missões, loot.
Tudo se muda à mão, sem mexer em código. Os arquivos `data/balance/*.json` abrem no editor de texto do Godot
(duplo clique no FileSystem); os campos dos mapas ficam no Inspector.

Depois de mexer em qualquer número, **rode o simulador** e os testes (seção "Como conferir" no fim).

## Metas que os números perseguem

- **30 horas até o nível 50**: 1–10 ~2 h, 10–20 ~5 h, 20–35 ~10 h, 35–45 ~7 h, 45–50 ~6 h.
- **Monstro comum do mesmo nível morre em 3 a 5 golpes** do ataque básico (guerreiro, arqueiro, mago; healer até
  7), com todos os pontos no atributo da classe e a melhor arma que o nível deixa usar.
- **0,5 a 0,8 item por monstro comum**, quase tudo material.

O teste `tests/unit/test_progression_pacing.gd` falha se as horas saírem mais de 20% do alvo, se os golpes saírem
de 3–5 ou se os itens por morte saírem de 0,5–0,8 (slime, goblin, esqueleto, raptor-capim).

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
| `hp` | 0.24, 1.05 | colunas `g.*` (golpes): têm de ficar entre 3 e 5 | rate 0.20–0.30, exp 1.0–1.1 |
| `dmg` | 0.08, 1.0 | (o simulador não mede) quantos golpes o jogador aguenta; hoje ~8 de um goblin do mesmo nível em qualquer nível, sem pontos em VIT | rate 0.05–0.12 |
| `xp` | 0.28, 2.4 | coluna `xp mob` e as horas por faixa | exp perto de `xp_curve.exp` |
| `gold` | 0.005, 1.0 | ouro por abate (não entra no simulador). Quase plano de propósito: no mesmo nível o abate dá o ouro de hoje (goblin nv 6 ~7,6; esqueleto nv 25 ~7,8); como cada abate leva mais golpes, o ouro por hora cai um pouco | rate 0–0.03 |

O dano do jogador cresce quase em linha reta com o nível (3 pontos por nível × 1,4–1,6 de dano por ponto), por
isso a vida usa expoente perto de 1. Vida subindo mais rápido que isso faz os golpes passarem de 5 no fim.

### `tier_size`, `tiers` — camadas de 10 níveis
A cada `tier_size` níveis o monstro muda de camada: `tint` (cor multiplicada) e `scale` (tamanho). Só visual.
A camada também é usada pelo loot. Seguro: `scale` 1.0–1.3.

### `elite` — monstro de elite
Vale para pontos com `elite` ligado no Inspector: `level_bonus` (níveis a mais, hoje 2), `hp` (vida × 2),
`scale` (tamanho × 1,25), `gear_chance` (chance de equipamento, 5%).

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
(soma do `reward_xp` das missões com nível na faixa), no máximo `quest_xp_share`. Hoje: 1–10 30%, 10–20 28%,
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
| `target_hours` | 2, 5, 10, 7, 6 | horas alvo por faixa: o simulador mostra ao lado e o teste cobra ±20% |

O simulador não conta os pontos de atributo dos ranks da guilda, comida, buffs, críticos nem as habilidades: é a
build pura com o ataque básico. Por isso o jogo de verdade é um pouco mais rápido que a tabela.

## `data/balance/enemies.json`

- `hp`, `damage`, `xp`, `gold`: o monstro no seu `ref_level`. São também os números da **Horda** e da **Defesa
  da Cidade** (que criam monstros sem nível): mudar aqui muda lá.
- `ref_level`: o nível em que os números acima valem. Hoje **2 para os monstros comuns**: como usam o mesmo, no
  mesmo nível a proporção entre eles é a do arquivo (o esqueleto, 95 de vida, tem ~1,2× a vida do goblin, 80, em
  qualquer nível; o slime metade). Chefes e elites têm o próprio: Goblin Dourado 4, Campeão Goblin 6, Cavaleiro
  Esqueleto 6, Slime Rainha 6, Lich 10, Rei Goblin 12. Com eles, um personagem bem equipado do nível do ponto
  leva ~10–35 golpes (Campeão ~10, Cavaleiro ~12, Rainha ~16, Lich ~33) e aguenta ~5–7 golpes deles. Subir o `ref_level` de um tipo deixa ele **mais fraco**
  em todos os níveis (o número do arquivo passa a valer num nível mais alto).
  O Rei Goblin nasce no próprio `ref_level` (ele não tem ponto no mapa); mudar esse número muda o nível dele.
- `loot`: `[item, chance]`, cada linha sorteada à parte. Material da família (orelha, gosma, osso...) é o
  principal; poção e semente ficam baixas (1%–10%) para a média ficar em 0,5–0,8 item por morte. A coluna "Itens
  por morte" do simulador mostra a média de cada tipo.
- `boss: true` usa `gear_drop.boss_chance`; `elite: true` é só o nome e o visual (a elite de verdade vem do
  ponto no mapa).

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
`OVERRIDES` do script (hoje `kael_sumiu: 30`). Só para mudar o XP de uma missão, edite `reward_xp` no JSON e
não rode o script de novo.

## Ponto de monstro (EnemySpawn) no Inspector

Nos mapas (`scenes/maps/*.tscn`, grupo Monstros), cada ponto tem:

- `level`: nível dos monstros. **0 = sem nível**: usa os números do enemies.json direto, sem placa "Nv" e sem
  ajuste de XP (é o que Horda e cidade usam). No mundo, sempre ponha um nível.
- `level_max`: fim da faixa. Cada monstro sorteia um nível entre `level` e `level_max` ao nascer (0 = sempre
  `level`). Faixas de hoje: Vale 1–13, Bosque 12–20, Mina 20–30, Pico 30–42.
- `elite`: monstros de elite (bloco `elite` do progression.json): +2 níveis, vida × 2, 25% maiores, 5% de chance
  de equipamento.

Um monstro do mesmo nível do jogador morre em ~4 golpes; 5 níveis acima já pede ~5–6 e dá 125% de XP; 8 abaixo dá
5% de XP. Para uma área mais difícil, suba a faixa, não a vida no enemies.json.

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
- *Monstros morrem em 2–3 golpes*: suba `enemy_curves.hp.rate` (0.24 → 0.28). Em 6 ou mais: desça.
- *Só uma classe destoa*: confira a arma escolhida na última coluna e o `level` das armas daquela classe.
- *Caem itens demais*: baixe a chance de poção/semente no `loot` do monstro, ou `gear_drop.chance`.
