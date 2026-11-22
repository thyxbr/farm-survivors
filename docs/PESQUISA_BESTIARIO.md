# Pesquisa: Bestiário do Tibia e como adaptar ao Ecos de Valdoria

Fonte principal: TibiaWiki BR (páginas Bestiário, Charms, Bounty Tasks e Weekly Tasks, lidas em 21/11/2026).
Os números do Tibia são de lá; a parte de adaptação é proposta nossa, para discutir.

---

## Parte 1: como funciona no Tibia

O Tibia tem três sistemas que se encaixam:

1. **Bestiário**: matar o mesmo monstro várias vezes revela informações sobre ele.
2. **Charms**: completar entradas do bestiário dá pontos para comprar bônus contra monstros específicos.
3. **Tasks (Bounty e Weekly)**: missões repetíveis de "mate X de Y", que dão recompensa e aceleram o bestiário.

### 1.1 Bestiário

- Cada monstro comum (chefes ficam de fora, num sistema à parte, o *Bosstiário*) tem uma entrada.
- Antes de matar, a entrada aparece como **silhueta "Desconhecido"**. A primeira morte mostra nome, sprite,
  dificuldade e o quão raro ele é no mapa.
- A entrada tem **3 estágios**, liberados por número de abates:

| Estágio | O que revela |
|---|---|
| 1 | Vida, velocidade, armadura, se ataca de perto ou de longe, se usa magia, **loot comum** |
| 2 | **Loot incomum**, resistências a cada elemento, **onde encontrar** (regiões do mapa) |
| 3 (completo) | **Loot semi-raro e raro**, e o jogador ganha **Charm Points** |

- **Loot muito raro nunca é revelado pelo contador**: só aparece na lista depois que o jogador vê aquele item
  cair de verdade. Isso mantém o mistério dos drops especiais.
- Quantos abates cada estágio pede depende da **dificuldade** da criatura:

| Dificuldade | Exemplo | Estágio 1 | Estágio 2 | Completo | Charm Points |
|---|---|---|---|---|---|
| Inofensivo | gato, cachorro | 5 | 10 | 25 | 1 |
| Trivial | goblin | 10 | 100 | 250 | 5 |
| Fácil | caranguejo | 25 | 250 | 500 | 15 |
| Médio | orc berserker | 50 | 500 | 1.000 | 25 |
| Difícil | elder wyrm | 100 | 1.000 | 2.500 | 50 |
| Desafiador | brachiodemon | 200 | 2.000 | 5.000 | 100 |
| Muito raro no mapa (qualquer dificuldade) | | 2 | 3 | 5 | 5 a 50 |

- Ao todo são ~830 entradas e ~28.700 Charm Points possíveis: é um objetivo de anos.
- **Aviso de progresso**: ao abrir uma entrada nova ou passar de estágio, o botão da enciclopédia ganha um
  contorno amarelo; clicar leva direto à entrada.
- **Conquistas e títulos**: completar 1, 10 e 100 entradas de cada dificuldade dá conquistas, e completar uma
  família inteira (todos os dragões, todos os humanoides…) dá um **título** que aparece para quem inspeciona o
  personagem. Completar o bestiário inteiro dá um título raro.
- **Aceleradores**: eventos de respawn rápido, uma poção que faz cada abate contar 2 por 2 horas, e o talismã das
  Bounty Tasks (ver abaixo).

### 1.2 Charms (o que os pontos compram)

- **Charm Points** só vêm de completar entradas do bestiário. Com eles se compram **Major Charms** em 3 níveis
  (bronze, prata, ouro; o ouro custa bem mais).
- Comprar Major Charms rende uma segunda moeda (**Minor Charm Echoes**), que compra **Minor Charms**.
- O charm não é global: o jogador **escolhe em qual criatura (de entrada completa) aplicar**. 1 major + 1 minor
  por criatura. Tirar custa ouro (100 × nível). Contas grátis podem ter 2 majors aplicados ao mesmo tempo,
  premium 6.
- Tipos de efeito:
  - **Dano por chance** (5/10/11%): causa 5% da vida máxima da criatura num elemento (fogo, gelo, energia,
    terra, morte, sagrado, físico). Um deles explode em área quando a criatura morre.
  - **Defesa**: esquiva de um ataque, ou reflete o dano recebido.
  - **Crítico**: mais chance ou mais dano crítico.
  - **Minors (utilidade)**: mais produtos de criatura no loot, paralisar a criatura, correr mais rápido depois de
    apanhar, limpar condições, perder menos XP ao morrer para ela, impedir que fuja com pouca vida.
- Existe um botão de **reset** (o primeiro é grátis, depois custa ouro).

### 1.3 Bounty Tasks (a "diária" infinita)

- No **quadro de tarefas**, o jogador escolhe a dificuldade (Beginner, Adept, Expert, Master, ligadas às
  dificuldades do bestiário e com nível mínimo 0/30/150/400) e o sistema oferece **3 criaturas sorteadas**.
  Ele escolhe uma.
- Pede entre ~50 e ~600 abates conforme a dificuldade. Concluiu: ganha XP, **Bounty Points** e
  **1 Reroll Token**, e pode pegar outra na hora (as tarefas não acabam).
- **Reroll Token**: troca as 3 opções ou abandona a tarefa. Dá para pegar **1 grátis por dia** no quadro (limite
  de 10 guardados). É aqui que entra o hábito diário.
- **Raridade da tarefa**: Normal, Prata, Ouro e Platina (Platina vale 8× a recompensa). Uma criatura que o jogador
  deixa passar acumula chance de voltar como Prata, Ouro ou Platina na próxima oferta (pity system).
- **Modo Elite**: as criaturas da tarefa batem 75% mais e apanham 25% menos, em troca de 2× XP e uma moeda extra.
- **Listas de preferidas e evitadas**: com pontos, o jogador aumenta ou reduz a chance de certas criaturas
  aparecerem.
- **Bounty Talisman**: item no slot extra, melhorado com Bounty Points. Contra a criatura da tarefa ativa, tem
  chance de dar mais dano, roubo de vida, mais loot e **fazer o abate contar 2 no bestiário**. É a ponte direta
  entre tarefas e bestiário.
- Os monstros da tarefa ganham um **ícone ao lado do nome**, e um painel lateral mostra o progresso.

### 1.4 Weekly Tasks (a semanal)

- Toda segunda-feira chega uma lista: **6 tarefas de caça + 6 de entrega de itens** (9 + 9 com uma melhoria paga).
  As entregas pedem justamente itens que monstros dropam, o que dá uso ao loot comum.
- Cada tarefa dá XP na hora. No fim da semana, o total de tarefas concluídas vira **Hunting Task Points**
  (moeda de uma loja com montarias, roupas e consumíveis) e **Soulseals** (entrada para desafios especiais).
- **Multiplicador semanal**: 0 a 3 tarefas = 1×, 4 a 7 = 2×, 8 a 11 = 3×, 12 a 15 = 5×, 16 a 18 = 8×.
  Isso premia fortemente quem volta vários dias na semana.

### 1.5 Prey (visto por cima)

Sistema mais antigo: slots com uma criatura sorteada que dá um bônus (dano, defesa, XP ou loot) contra ela.
Usa "wildcards" para escolher a criatura ou rerolar o bônus. Hoje divide o painel de progresso com as tasks.
Não li a página atual; se for interessar, vale uma leitura própria.

### 1.6 Por que o sistema funciona (o que vale copiar)

- **Curiosidade**: silhuetas e loot escondido dão vontade de "completar a página".
- **Progresso mesmo em caça repetitiva**: cada abate move um contador, mesmo sem subir de nível.
- **Informação útil de verdade**: resistências e locais de caça ajudam a jogar melhor.
- **Recompensa que volta para o combate**: charms fazem o jogador caçar melhor justamente o que já estudou.
- **Hábito sem obrigação**: 1 token por dia que acumula até 10, então quem perde dias não fica para trás.
- **Ligação entre sistemas**: a tarefa acelera o bestiário, o bestiário define quais tarefas aparecem.
- **Escolha**: 3 opções, reroll, preferidas e evitadas evitam a sensação de tarefa imposta.

---

## Parte 2: o que o nosso jogo já tem

(lido do `origin/main`)

- **41 tipos de inimigo** em `data/balance/enemies.json`, cada um com `hp`, `gold`, `loot` (`[item, chance]`) e
  flags `boss` e `elite`. Há uma divisão natural: comuns (slime, goblin, lobo_geada, tecela…), fortes
  (goblin_bruto, golem_cristal, ieti…), elites raros (goblin_dourado, goblin_campeao, esqueleto_cavaleiro,
  lobo_alfa, slime_rainha) e chefes (`boss: true`: goblin_king, lich, espinheira, mae_verme…).
- **Loot** em `scripts/character/loot_rules.gd` (`LootRules.roll`): loot da tabela do monstro + equipamento
  sorteado pela janela de nível (`gear_drop`) + couro da camada (`tier_drop`) + itens caçados (`chase_drops`).
  O loot da tabela é fixo por monstro, o que encaixa bem nos estágios do bestiário. O equipamento por nível não
  é do monstro, então no bestiário ele viraria uma linha genérica ("equipamento do nível X a Y").
- **Missões** em `data/balance/quests.json` já têm o tipo `"kill"` com `target` e `count`, e o estado fica em
  `CharState.quests`. Hoje são missões de história, uma vez só.
- **Contador de abates**: só existe `CharState.kills` (total geral). Não há contagem por tipo de monstro.
- **Títulos** já existem (`Game.set_title`), então os títulos de bestiário entram de graça.
- O servidor é a autoridade (`Econ.request`), então o contador e as recompensas devem viver no servidor.

---

## Parte 3: proposta de adaptação

A ideia é ter as mesmas três peças, mas **menores**: temos 41 monstros e não 830, e números do Tibia
(5.000 abates) seriam inviáveis aqui.

### 3.1 Bestiário de Valdoria

**Contagem**: `CharState.bestiary = {kind: abates}` e `CharState.seen_drops = {kind: [itens]}` (para o loot raro
revelado ao cair). Abate em grupo conta para quem causou dano (como no Tibia), para não punir quem joga em party.

**Classes e abates** (proposta inicial, para ajustar no `/balance-check`):

| Classe | Quem entra | Est. 1 | Est. 2 | Completo | Pontos |
|---|---|---|---|---|---|
| Comum | slime, goblin, lobo_geada, tecela, asa_couro… | 10 | 50 | 150 | 5 |
| Forte | goblin_bruto, golem_cristal, ieti, bocarrao… | 5 | 30 | 80 | 15 |
| Elite | goblin_dourado, goblin_campeao, lobo_alfa, esqueleto_cavaleiro, slime_rainha | 1 | 5 | 15 | 30 |
| Chefe | `boss: true` | 1 | 3 | 10 | 50 |

A classe pode ser um campo novo `bestiary_class` no `enemies.json`, com padrão calculado pela vida e pelas
flags.

**O que cada estágio mostra**:

| Estágio | Mostra |
|---|---|
| Desconhecido | silhueta escura do modelo 3D e "???" |
| 1º abate | nome, modelo, classe, região onde foi morto |
| Estágio 1 | vida, dano, comportamento (corpo a corpo / distância / magia), loot com chance ≥ 30% |
| Estágio 2 | fraquezas e resistências (fogo, gelo… se tivermos), todas as regiões onde aparece, loot de 5% a 30% |
| Completo | loot de 1% a 5%, faixa de ouro, linha de equipamento por nível, **pontos de caçador** |
| Sempre escondido | loot abaixo de 1% e `chase_drops`: só aparece depois de cair para o jogador |

Opcional e barato: mostrar a chance como faixa ("comum / incomum / raro") em vez do número exato.

**Tela**: uma aba "Bestiário" no grimório ou no menu, com grade por família (Slimes, Goblins, Mortos-vivos,
Feras, Insetos, Gelo, Chefes), barra de progresso por entrada e o modelo 3D girando no estágio completo.
Aviso ao passar de estágio: toast "Bestiário: Goblin, estágio 2!" e um destaque no botão.

**Títulos**: completar uma família inteira dá título ("Exterminador de Slimes", "Caçador do Gelo"…), e completar
tudo dá um título raro.

### 3.2 Marcas de Caçador (nosso "charm")

Pontos de caçador (vindos de entradas completas) compram **marcas**. Cada marca é aplicada a **um tipo de monstro
já completo**. Proposta enxuta para começar, 3 níveis cada:

| Marca | Efeito contra o monstro marcado |
|---|---|
| Ferida | chance de causar dano extra de % da vida máxima dele |
| Brasa / Geada / Faísca | igual, mas no elemento (se o combate tiver elementos) |
| Esquiva | chance de anular um golpe dele |
| Espólio | mais chance nos itens da tabela de loot dele (não no equipamento) |
| Saque | mais ouro dele |

Regras: 1 marca por monstro, limite de marcas ativas ao mesmo tempo (ex.: 2 no início e +1 a cada 10 entradas
completas), trocar custa ouro e o primeiro reset é grátis. Começar só com Ferida, Esquiva e Espólio já basta para
testar o sistema.

### 3.3 Mural de Caça (diária + bestiário)

Um NPC ou quadro na vila (combina com o Ancião Bram ou com um caçador novo).

- O mural oferece **3 contratos** sorteados entre monstros **das regiões que o jogador já desbloqueou** e perto do
  nível dele. Ele aceita um.
- Contrato: "mate 20 a 60 de X" (ou 1 elite / 1 chefe nos contratos raros). Ao concluir: XP, ouro,
  **Selos de Caça** e 1 ficha de troca. Pode pegar outro logo em seguida.
- **Ficha de troca diária**: 1 grátis por dia, acumula até 5. Serve para trocar as 3 opções ou desistir de um
  contrato. Esse é o hábito diário sem punir quem falta.
- **Ligação com o bestiário**: enquanto o contrato está ativo, cada abate do alvo conta **2** no bestiário (ou tem
  uma chance de contar 2, se 2 sempre for rápido demais). Monstros com entrada incompleta têm mais peso no sorteio.
- **Contratos dourados**: monstro deixado de lado ganha chance de voltar como contrato dourado (2× ou 3× recompensa),
  copiando a ideia de "pity" do Tibia.
- **Selos de Caça** compram itens numa loja do mural: poções, receitas, cosméticos, e talvez um acessório que
  melhora o bônus de contrato (nosso "talismã").
- Os alvos do contrato ganham um ícone sobre a cabeça e o HUD mostra "Goblin 12/40".

**Fase 2 (semanal)**: uma lista semanal com caça + **entrega de itens que monstros dropam** (dá destino ao
`goblin_ear`, `bone_shard`, `frost_pelt`…), com multiplicador que sobe conforme o jogador conclui mais tarefas na
semana.

### 3.4 Onde mexer no código (estimativa)

| Peça | Arquivos |
|---|---|
| Contador por monstro, loot visto | `char_state.gd` (campos + migração), ponto onde o servidor credita o abate |
| Classes e regras de estágio | `enemies.json` (`bestiary_class`, `family`), novo `scripts/character/bestiary_rules.gd` puro |
| Marcas | `bestiary_rules.gd` + hook no cálculo de dano e no `LootRules.roll` (parâmetro opcional, sem mudar a sequência do RNG de quem não tem marca) |
| Mural | novo `hunt_board_rules.gd`, tabela `hunt_board.json`, comandos novos no `Econ` |
| Telas | aba no grimório/menu, painel do contrato no HUD |
| Testes | testes unitários das regras puras (estágios, revelação de loot, sorteio dos contratos com semente fixa) |

Sugestão de ordem: **(1)** contador + tela do bestiário com estágios e loot escondido, **(2)** Mural de Caça
diário ligado ao bestiário, **(3)** Marcas de Caçador, **(4)** semanal com entregas.

### 3.5 Perguntas em aberto

1. Os chefes entram no mesmo bestiário ou num "Bosstiário" separado como no Tibia?
2. Mostramos a chance exata do drop ou só a faixa (comum/incomum/raro)?
3. O mural é por personagem ou por conta? A ficha diária reseta em qual horário (servidor)?
4. Monstros da Horda e de dungeon contam para o bestiário?
5. Quanto as marcas podem pesar no balanceamento? (Começar fraco: dano extra de 2 a 3% da vida, chance de 5%.)
