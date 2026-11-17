# Progressão: nível dos monstros, loot, regiões, profissões e dungeons

Data: 2026-11-16 · Branch: `progressao` (worktree `../godot-3d-progressao`)

## Intenção

Hoje a progressão do mundo aberto quebra cedo. Um personagem chegou ao nível 18 rápido e matava quase tudo com
um golpe; o mapa parece vazio (o Vale tem ~52 monstros e mais de 500 árvores; Bosque 15, Mina 13, Pico 12); o drop
é farto (o goblin solta ~1,9 item por morte, com armas raras a 1% cada; o Rei Goblin solta ~9). Como o jogo agora
tem muitas missões, o usuário quer uma progressão **divertida e longa**, em que:

- o começo seja prazeroso e ensine as mecânicas;
- o mapa tenha regiões cheias de monstros, com nome no mapa, que as missões possam citar;
- o equipamento bom venha do **craft**, que deve ser bom, desafiador e crescer junto com o personagem;
- haja profissões com nível (coleta, produção, fazenda, culinária);
- dungeons com monstros bem mais fortes forcem o personagem a evoluir;
- todos os parâmetros possam ser mudados à mão dentro do Godot.

### Por que está fácil hoje (diagnóstico do código)

- **Monstro não tem nível.** `enemies.json` dá status fixos (goblin = 80 de vida). O dano do jogador é
  `arma + FOR × 1,6` (`game.gd`, `attack_damage`), e cada nível dá 3 pontos de atributo. No nível 18, com ~50 pontos
  no atributo da classe, o golpe passa de 100: mata goblin, esqueleto e slime num golpe.
- **Loot farto e sem trava.** Tabelas longas de equipamento pronto em cada monstro comum, e nenhum item pede nível.
- **As missões dão pouco do total.** As 44 missões somam 9.120 XP (chega no nível ~10); o resto é matar monstro.
- **Craft é só cozinha** (8 receitas). Os veios de ferro e cristal já existem, mas o minério não fabrica nada.
- **"Região" hoje = mapa inteiro** (`Regions.DATA`: vila, bosque, mina, pico, liberados por rank da guilda). Os
  nomes do mapa-mundi são landmarks fixos em `MapRules.PLACES`.

## Metas

1. **30 horas até o nível 50** (nível máximo), com este ritmo:

   | Faixa | Tempo alvo | Onde | Sensação |
   |---|---|---|---|
   | 1–10 | ~2 h | Vale e missões principais | rápido; cada nível libera algo (habilidade, receita, área) |
   | 10–20 | ~5 h | Vale (fim) e Bosque | primeiras escolhas de equipamento e de profissão |
   | 20–35 | ~10 h | Mina e Pico | a primeira dungeon cobra preparo |
   | 35–45 | ~7 h | Pico e dungeons | equipamento de ponta vem do craft e dos chefes |
   | 45–50 | ~6 h | região de elite e dungeon final | curva bem mais íngreme: cada nível custa mais de 1 h |

   As profissões sobem **dentro** dessas 30 h (coletar e fabricar no caminho), não somam por fora.
2. Um monstro comum **do mesmo nível** do jogador morre em **3 a 5 golpes** de um personagem com build focada e
   equipamento craftado da camada certa. Hitkill só contra monstros bem abaixo do seu nível.
3. O equipamento bom de cada faixa vem do craft; o drop dá principalmente material.
4. Cada mapa tem regiões nomeadas e cheias de monstros, com faixa de nível visível no mapa e no aviso de entrada.
5. Dungeons compartilhadas com monstros acima do nível da região e drop exclusivo que o craft de ponta exige.
6. **Todo número de balanceamento editável no Godot**: em `data/balance/*.json` (abre no editor de texto do Godot)
   ou no Inspector dos nós de mapa. Nada de número de balanceamento fixo em `.gd`.
7. Funciona igual no solo e no online (servidor autoritativo); saves e personagens antigos continuam carregando.

## Não-metas

- Mexer na dificuldade do **Desafio da Horda** e da **Defesa da Cidade**: eles continuam com os números de hoje.
- Dungeons privadas por grupo (instâncias). Decidido: são compartilhadas.
- Limite de profissões por personagem. Decidido: todas podem chegar ao 50.
- Um quinto mapa novo. Se a faixa 45–50 ficar curta, entra num trabalho depois deste.
- Modelos novos no Blender para monstros. Variações de nível usam cor/tamanho, como o slime de gelo já faz.
  Itens novos de craft precisam de ícone (o pipeline de ícones pintados já existe) e reaproveitam modelos de arma.
- Ferramentas de coleta (picareta, machado) como itens.
- Leilão ou mercado entre jogadores.

## Anti-metas (falhou mesmo que funcione)

- O começo fica mais lento ou mais confuso que hoje (a faixa 1–10 tem de ser *mais* gostosa, não menos).
- Coletar e fabricar vira trabalho braçal: bater 30 vezes na mesma árvore, ou subir profissão só repetindo a
  mesma receita barata.
- O jogador fica preso sem saber para onde ir (precisa sempre haver uma região do seu nível e uma missão apontando).
- Personagem antigo perde nível, item ou ouro com a mudança.
- O servidor pesa: monstros a mais nas regiões não podem derrubar o desempenho do servidor dedicado
  (medir com `--netstats` / skill `perf-profile`).
- Mexer num número exige editar código.

## Restrições

- Godot 4 / GDScript. Tabelas em `data/balance/*.json`, carregadas por `BalanceTables` (`NAMES` lista as tabelas) e
  repovoadas por `scripts/autoload/balance.gd`. O servidor pode mandar tabelas novas (`Balance.apply`).
- Regras puras em `scripts/character/*_rules.gd` (`CharRules`, `LootRules`...): servidor e solo rodam o mesmo
  código. Não usar nomes de autoload dentro dessas classes puras (o runner de testes unitários roda com `-s`).
- Mapas: cenas `scenes/maps/*.tscn` editadas no 3D do Godot (`docs/EDITOR_MAPA.md`), com `EnemySpawn`,
  `MapEntity`, `MapLandmark` etc. Regiões de mapa inteiro em `scripts/world/regions.gd`; nomes do mapa-mundi em
  `scripts/world/map_rules.gd` (`PLACES`).
- Classes: guerreiro (FOR), arqueiro (AGI), mago e healer (INT); talentos dão 1 ponto por nível a partir do 2
  (`CharRules.talent_points`). Itens de arma são adaptados à classe no drop (`LootRules.adapt_weapon`).
- Personagens salvos em SQLite no servidor (`sqlite_char_store.gd`, com `migrations.gd`) e em arquivo no solo.
- Testes: unitários, `smoke_test`, `net_test`, colônia (skill `smoke-check`). PR que muda código do jogo sobe
  `config/version`.

## Abordagens consideradas

**Nível dos monstros** (escolhida: A)

- **A — Nível vem da região; status por fórmula (escolhida).** `enemies.json` guarda o molde do monstro e um
  nível de referência; a região (ou o ponto de nascimento) dá o nível; vida, dano, XP, ouro e loot saem de curvas
  únicas. O mesmo goblin aparece no nível 5 ou 25. Poucos números ajustam o jogo inteiro. Custo: monstros iguais
  em níveis diferentes parecem iguais (resolvido com tinta e escala por faixa).
- **B — Uma entrada por versão (goblin, goblin veterano...), tudo à mão.** Controle total, mas o arquivo triplica
  e manter a curva de 30 h coerente vira trabalho manual.
- **C — Segurar o crescimento do jogador.** Simples, mas não resolve: o hitkill volta mais tarde, as dungeons
  viram só números maiores e os personagens antigos perdem força.

**De onde vem o equipamento** (escolhida: A — craft é a fonte principal; B drop e craft equilibrados e C drop manda
e craft melhora foram descartadas porque o craft viraria secundário).

**Profissões** (escolhida: todas até 50; a alternativa "2 de produção" criaria troca no online, mas travaria
quem joga sozinho).

**Dungeons** (escolhida: compartilhadas, com população que cresce com o número de jogadores; a alternativa
"privada por grupo" é mais justa, mas exige várias cópias no servidor e é bem mais cara de fazer).

## Design

O trabalho é grande e fica em **quatro partes**, nesta ordem, cada uma jogável e mesclável sozinha:

1. Nível dos monstros, nível dos itens, nova curva de XP e loot enxuto.
2. Regiões de monstros com nome no mapa.
3. Profissões e craft.
4. Dungeons.

### 0. Onde ficam os parâmetros (vale para tudo)

- **`data/balance/progression.json` (novo)**: curvas de nível do monstro, ajuste de XP por diferença de nível,
  curva de XP do jogador, regras de loot por nível, curvas das profissões, população das dungeons. Entra em
  `BalanceTables.NAMES`.
- **`data/balance/regions.json` (novo)**: lista de regiões nomeadas por mapa (id, nome, faixa de nível, forma,
  tamanho, multiplicador de população, se aparece no mapa). *Chamada minha:* as regiões ficam em JSON **e** são
  desenhadas por nós `MapRegion` na cena (ver parte 2); o nó é a fonte da forma/posição e o JSON a dos números,
  para que mexer na faixa de nível não exija abrir a cena.
- **`data/balance/professions.json`** e **`data/balance/recipes.json`** (este passa a cobrir todas as estações).
- Tabelas existentes ganham campos: `enemies.json` (`ref_level`, `family`, `loot_table`), `items.json` (`level`),
  `quests.json` (`region`).
- **Inspector**: `EnemySpawn` ganha `level` (0 = usa a região), `elite` e `per_player`; `MapRegion` mostra forma,
  nome e faixa (prévia no editor como o `EnemySpawn` já faz).
- **`docs/BALANCEAMENTO.md` (novo)**: um guia curto de cada botão (o que faz, em que arquivo, valor seguro).
- **Simulador de ritmo** (`tools/progression_sim.gd`, roda headless): lê as tabelas e imprime, por faixa de nível,
  horas estimadas, golpes para matar um monstro comum do mesmo nível por classe, e XP de missões vs. monstros.
  Serve para conferir depois de mudar qualquer número. Um teste unitário falha se as horas por faixa saírem mais de
  20% do alvo ou se os golpes do mesmo nível saírem de 3–5.

### 1. Nível dos monstros, itens, XP e loot

**Nível do monstro**

- Cada tipo em `enemies.json` ganha `ref_level`: o nível em que os números atuais valem. Status no nível L:
  `stat(L) = base × curva(L) / curva(ref_level)`, com curvas separadas para vida, dano, XP e ouro em
  `progression.json` (forma sugerida: `1 + taxa × (L − 1)` para dano e `(1 + taxa × (L − 1))^expoente` para vida,
  valores a calibrar no simulador).
- **Horda e Defesa da Cidade** criam monstros sem nível → usam `ref_level` → números idênticos aos de hoje.
- O nível vem de: `EnemySpawn.level` se > 0; senão, sorteado dentro da faixa da região em que o ponto está; fora de
  qualquer região, `ref_level`. Dungeons somam `dungeon_level_bonus` (+3 a +5, por dungeon).
- **Elite** (`EnemySpawn.elite` ou chance por região): +2 níveis, mais vida, tamanho 1,25×, loot melhor.
- Placa sobre o monstro mostra o nível, com cor relativa ao jogador (cinza = bem abaixo, branco = igual,
  amarelo/vermelho = acima). O nível vai no estado de rede do monstro (snapshot/spawn), não é recalculado no
  cliente.
- Tinta/escala por faixa (`progression.json`: `tiers[].tint`, `tiers[].scale`) para o goblin de nível 25 não parecer
  o de nível 5.

**XP**

- Curva do jogador em `progression.json`: `xp_to_next(L) = base × L^exp`, mais um multiplicador por faixa
  (`late_mult`: ~1 até 44, subindo forte de 45 a 49) para a penalidade do fim. Nível máximo 50 (`max_level`); no 50 a
  XP para de contar.
- Ajuste por diferença de nível (monstro − jogador), tabela editável. Proposta: ≤ −8 → 5%; −7..−5 → 25%;
  −4..−3 → 70%; −2..+2 → 100%; +3..+4 → 115%; ≥ +5 → 125%.
- Em grupo, a diferença usa o nível mais alto do grupo (evita o forte "carregar" o fraco sem custo). *Chamada minha.*
- Missões: o XP de recompensa passa a ser uma fração da XP do nível da missão (`quest_xp_share`), para as missões
  sozinhas renderem algo como 30% da progressão em cada faixa. Os valores em `quests.json` são recalculados uma
  vez por script e ficam editáveis.

**Atributos e talentos**

- 3 pontos por nível continuam (editável em `rules.json`). O equilíbrio vem da curva do monstro, não de cortar o
  jogador.
- Os talentos dão 1 ponto por nível; no 50 serão 49 pontos. O construtor confere se as árvores de talento comportam
  isso; se não, os pontos a mais só ficam guardados (ampliar as árvores fica fora daqui).

**Nível dos itens**

- Todo item equipável ganha `level` (nível mínimo para equipar). Equipar abaixo é recusado em `CharRules.equip` com
  mensagem clara. Tooltip mostra o nível em vermelho se faltar.
- Itens existentes recebem `level` por um script de migração único, a partir da raridade e do dano/defesa atuais
  (comum 1–8, incomum 8–15, raro 14–24, épico 22–35, lendário 35–45), revisável à mão no JSON.
- **Qualidade de craft** (normal, fina, obra-prima) multiplica dano/defesa/bônus (`progression.json`:
  `quality_mult`). *Chamada minha:* a qualidade vai no id do item com sufixo (`iron_sword@fina`), resolvido pela
  consulta de item, porque hoje inventário e equipamento guardam só ids; isso evita criar instâncias de item.

**Loot enxuto**

- A lista longa de equipamento pronto sai dos monstros comuns. Cada monstro passa a ter `family`
  (slime, goblin, esqueleto, fera, planta, morcego...) e o loot vem de **tabelas por família e camada** em
  `progression.json`:
  - material da família e da camada do nível (couro, presa, gosma, osso...) — comum;
  - poção/semente — ocasional;
  - pergaminho de receita — raro;
  - equipamento pronto — muito raro (alvo ~0,5% por monstro comum), sempre de nível compatível.
- Meta: ~0,5 a 0,8 item por monstro comum (hoje ~1–1,9), quase tudo material.
- Ouro escala com o nível e cai um pouco no total (o ouro passa a ter uso no craft: taxas de estação).
- Chefes (Rei Goblin, Slime Rainha, Lich): 1 material raro garantido + chance de pergaminho + chance pequena de
  item nomeado; nada de 9 itens garantidos.
- `LootRules.roll` recebe o nível do monstro e continua puro e testável; `adapt_weapon` continua valendo.

**Personagens existentes** (migração em `migrations.gd` e no carregamento do save local)

- Mantêm o nível e a XP (XP cortada se passar do novo `xp_to_next`).
- Atributos resetados ao inicial e pontos devolvidos (`(nível − 1) × pontos_por_nível`), com aviso no jogo.
- Itens antigos ganham `level` pela migração; se o personagem estiver equipado com algo acima do seu nível, o item
  continua equipado até ser trocado (não quebrar o personagem).

### 2. Regiões de monstros com nome no mapa

- **Nó `MapRegion`** (novo, `scripts/map/map_region.gd`, `@tool`): `region_id` (chave no `regions.json`),
  forma retângulo ou disco, tamanho. Prévia no editor com o nome e a faixa. O `regions.json` guarda nome,
  `level_min`, `level_max`, `density` e `show_on_map`.
- **Faixas propostas** (editáveis):

  | Mapa | Faixa | Exemplos de região |
  |---|---|---|
  | Vale | 1–14 | Campos do Norte (1–4, slimes), Toca dos Goblins (5–9), Cemitério Velho (9–12), Ruínas (11–14) |
  | Bosque | 12–22 | regiões de slime de gelo, xamãs, ninho da Rainha |
  | Mina | 20–32 | galerias de esqueletos e brutos |
  | Pico | 30–45 | encostas, fortaleza do Lich, **região de elite 42–45** |

  Os nomes finais são escritos no `regions.json` durante a implementação (o construtor propõe; o usuário revisa).
- **Mais monstros e concentrados**: cada região mantém 10–20 monstros em grupos de 3–5 (`EnemySpawn` com `count` e
  `radius`), retorno mais curto que hoje. Alvo total: Vale ~120, Bosque/Mina/Pico ~60–80 cada (medir o servidor).
- **Menos árvores nas áreas de monstro**: abrir clareiras nas regiões do Vale; árvores ficam nas bordas e trilhas.
  Árvores restantes podem virar nó de coleta de madeira (parte 3).
- **Nome no mapa**: `MapRules` passa a listar as regiões de `regions.json` (com a faixa, ex. "Toca dos Goblins ·
  Nv 5–9"), no mapa-mundi/atlas e no minimapa, além dos landmarks atuais.
- **Aviso de entrada**: ao cruzar o limite de uma região, um letreiro curto no HUD com nome e faixa; não repete
  enquanto o jogador ficar nela. `Regions.region_at` ganha um irmão `area_at(pos)` que devolve a região nomeada.
- **Missões citam regiões**: `quests.json` ganha `region` opcional; o objetivo mostra o nome, o marcador aponta a
  região, e `quest_counts_kill` só conta mortes dentro dela. Missões atuais sem `region` continuam iguais.

### 3. Profissões e craft

- **Profissões**, todas com nível 1–50 por personagem, guardadas no save (`s.professions = {id: {"lv", "xp"}}`):

  | Tipo | Profissão | Fonte |
  |---|---|---|
  | Coleta | Mineração | veios (ferro e cristal já existem; novos minérios por camada) |
  | Coleta | Lenhador | árvores marcadas como coletáveis + nós de madeira por camada |
  | Coleta | Fazenda | a horta atual (plantar e colher dá XP; sementes melhores pedem nível) |
  | Produção | Ferraria | armas e armaduras de metal (forja do Doran) |
  | Produção | Couraria | armaduras leves e de pano com couro e partes de monstro (bancada nova na vila) |
  | Produção | Alquimia | poções e essências (bancada da Pip) |
  | Produção | Culinária | a cozinha atual |

- **Camadas de material a cada 10 níveis**, ligadas às regiões (nomes propostos, editáveis):

  | Camada | Níveis | Metal | Madeira | Onde |
  |---|---|---|---|---|
  | 1 | 1–10 | Cobre | Pinho | Vale |
  | 2 | 11–20 | Ferro | Carvalho | Vale (fim) e Bosque |
  | 3 | 21–30 | Prata | Bétula-prata | Mina |
  | 4 | 31–40 | Mithril | Freixo-cinza | Pico |
  | 5 | 41–50 | Astralita | Madeira-de-alma | só dungeons e região de elite |

  Couros e partes de monstro seguem a mesma camada, pela família e nível do monstro.
- **Receitas** em `recipes.json` (estação, profissão, nível da profissão, ingredientes, ouro, item gerado, XP).
  A receita de ponta de cada camada pede **uma peça rara de chefe ou de dungeon**.
- **Como se aprende**: receitas básicas de cada camada com os NPCs (Doran, Pip, cozinha); as fortes por pergaminho
  que cai em dungeons e chefes.
- **Qualidade**: chance de fina/obra-prima cresce quando o nível da profissão passa o da receita
  (`progression.json`: `quality_chance`).
- **XP de profissão**: por coleta e por fabricação; receitas/nós muito abaixo do nível rendem quase nada (mesma
  ideia da XP de monstro). Curva própria em `professions.json`.
- **Contra o trabalho braçal**: nós de coleta rendem em 2–3 golpes; o craft fabrica em lote (já existe `times` em
  `cook`); a XP de profissão premia variar receitas.
- **Tela de profissões**: uma aba no livro (Grimório) com nível/XP de cada profissão e as receitas conhecidas. As
  estações abrem a lista filtrada da profissão, no mesmo estilo da `cooking_ui`.
- Regras puras em `scripts/character/craft_rules.gd` (fabricar, coletar, XP), chamadas pelo servidor como
  `CharRules.cook` hoje.

### 4. Dungeons

- **Uma por mapa** a partir do Bosque, mais uma final: Bosque (~16–20), Mina (~26–30), Pico (~36–40), final
  (~45–50). Faixas editáveis.
- **Estrutura**: uma entrada no mapa (`MapEntity` kind `dungeon_entrance`) leva a uma área própria, montada como
  as regiões de mapa (`Regions.DATA` ganha as dungeons, com `origin` longe, cena em `scenes/maps/dg_*.tscn`), com
  2–3 salas e um chefe. Monstros `+3 a +5` níveis acima da região de fora (`dungeon_level_bonus`).
- **Compartilhadas**: todos que entram veem a mesma dungeon. População escala com jogadores presentes:
  `monstros = base × (1 + per_player × (jogadores − 1))`, até `max_mult`; retorno mais rápido com mais gente. Chefe
  volta após `boss_respawn` minutos. Todos os números em `progression.json`.
- **Prêmio**: materiais da camada 5 e as peças raras das receitas de ponta, pergaminhos de receita. O loot do chefe
  é rolado **para cada jogador que causou dano** (evita briga pelo último golpe). *Chamada minha.*
- **Morte dentro**: volta para a entrada; a penalidade de morte atual continua.
- **Arte**: reaproveita modelos existentes (rocha, ruína, cristal, tochas) e o editor de mapas.

## Ordem e validação

Cada parte vira um PR próprio (com versão nova), testado com a skill `smoke-check` e com o simulador de ritmo:

1. Parte 1 — o jogo continua com os mesmos mapas, mas monstros têm nível, itens pedem nível e o loot é material.
   Conferir: golpes 3–5 no mesmo nível, horas por faixa no simulador, Horda inalterada, save antigo carrega.
2. Parte 2 — regiões, nomes e densidade. Conferir desempenho do servidor com o mapa cheio.
3. Parte 3 — profissões e receitas por camada.
4. Parte 4 — dungeons.

## Decisões do usuário na revisão

- **Loja só com o básico**: `shop.json` passa a vender poções, sementes, materiais da camada 1 e equipamento comum
  de nível 1–10 (para o começo ser tranquilo). Épicos e lendários saem da loja; equipamento acima disso só vem do
  craft (e dos itens nomeados de chefe). Entra na parte 1.
- **Dungeons e chefes possíveis sozinho, mas difíceis**: a base de cada dungeon e chefe é ajustada para **um**
  jogador bem equipado da faixa (equipamento craftado da camada, nível no meio da faixa). O `per_player` só aumenta
  monstros e ritmo com mais gente, para o grupo continuar desafiado e terminar mais rápido. O simulador e os testes
  usam o caso solo como referência.

## Decisões da revisão (chamadas minhas, para o usuário conferir)

- **Rank da guilda continua liberando a viagem** (Bosque C, Mina B, Pico A), e também as entradas das dungeons de
  cada mapa. Os pontos de rank das missões são recalibrados para o rank chegar **antes** do início da faixa de nível do
  mapa seguinte; o simulador confere isso (anti-meta "jogador preso").
- **"Hora" do simulador**: modelo fixo e explícito em `progression.json` (segundos por morte por classe, tempo de
  deslocamento e de descanso por morte, tempo de cada missão), calibrado uma vez cronometrando a faixa 1–10 jogando de
  verdade com as regras novas. O modelo é solo; o grupo é conferido à parte (só não pode ser mais lento).
- **Regra dos 3–5 golpes**: vale para guerreiro e arqueiro com ataque básico e para mago com o ataque principal
  (sem contar habilidades com recarga). O healer pode precisar de até 7. Medido com equipamento craftado normal da
  camada e atributos todos na classe.
- **Catálogo do craft**: os itens que já existem viram resultado de receita e são renivelados (cada camada fica com
  pelo menos 1 arma por classe e 1 peça por espaço de armadura). Itens novos só para preencher buracos nas
  camadas 4 e 5. Os itens de chefe continuam como drop nomeado.
- **Devolução de atributos** = `(nível − 1) × pontos_por_nível` + os pontos dos ranks já alcançados (`guild.json`) +
  qualquer outra fonte de pontos que o código tenha. Talentos não são resetados.
- **Encantamento segue o item-base**: `iron_sword@fina` usa o encanto de `iron_sword` (a consulta tira o sufixo).

## Deixado para o construtor

- Valores iniciais exatos das curvas (calibrar com o simulador até bater as metas).
- Nomes finais das regiões, materiais e receitas (propor no JSON; o usuário revisa).
- Layout da tela de profissões e do aviso de região, seguindo `ui_theme.gd` e o Grimório.
- Quais árvores do Vale viram coletáveis e quais saem.
