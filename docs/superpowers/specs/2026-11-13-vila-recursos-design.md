# Defesa da Cidade: aldeões, recursos e mapa vivo

Data: 2026-11-13 · Branch: `vila-recursos` (worktree `../godot-3d-vila`)

## Intenção

Hoje, de dia, o mapa da Defesa da Cidade é um campo vazio com coelho, cervo, javali e alguns slimes/goblins
errantes. Não há motivo para sair da cidade além de caçar. O usuário quer:

1. Uma economia no estilo Age of Empires: a prefeitura dá X aldeões; cada construção precisa de aldeões
   livres; ganhar aldeões custa recursos; construir custa ouro **e** recursos coletados no mapa
   (madeira, pedra e outros).
2. Um mapa que dê motivo para explorar: recursos melhores longe da cidade, áreas especiais de monstros,
   eventos aleatórios, fauna perigosa. "Que ao explorar não fique tão monótono."
3. Novas tropas: mago e canhoneiro (arqueiro já existe).

Futuro (fora deste trabalho): dungeons com andares. O sistema de covis deve ser genérico o bastante para que
uma "entrada de dungeon" seja só mais um tipo de ponto de interesse.

## Metas

- O jogador tem razões claras e variadas para sair da cidade durante o dia, e o que traz muda o que dá para construir.
- Aldeões viram um recurso de verdade: limitam quanto se constrói e se recruta.
- Funciona igual no solo e no cooperativo (servidor dedicado), e o save antigo continua carregando.

## Não-metas

- Aldeões como unidades reais andando pelo mapa (opção A descartada; ver Abordagens).
- Carregar recursos nas costas e entregar na prefeitura (o que é coletado vai direto ao estoque da cidade).
- Dungeons e andares.
- Modelos novos no Blender: tudo usa modelos existentes ou peças procedurais como as de `animal.gd`.

## Anti-metas (falhou mesmo que funcione)

- Coletar vira tarefa repetitiva: bater 30 vezes na mesma árvore.
- O servidor fica mais pesado à noite (o pico de carga é a onda; nada novo pode competir com ela).
- O mapa fica cheio de marcadores e texto e perde a sensação de descoberta.
- O começo da partida fica mais lento ou confuso que hoje.

## Restrições

- Godot 4 / GDScript. Tabelas de balanceamento ficam em `scripts/colony/colony_data.gd`, como hoje.
- Rede: o servidor é a autoridade (`role` = solo | server | client). O estado leve vai em `net_state()`/`apply_state()`,
  eventos pontuais pelos `Lobby.city_*`, posições em `net_snapshot()`.
- O mapa é gerado da semente (`map_seed` em `colony_world.gd`): todos os jogadores montam o mesmo mapa sozinhos.
- Testes existentes: `tests/colony_test.gd`, `tests/smoke_test.gd`, `tests/net_test.gd` (skill `smoke-check`).

## Abordagens consideradas (escolhida: B)

- **A — Aldeões reais**, sincronizados como os soldados. Fiel ao AoE, mas pesa na rede e no servidor com 30–40 aldeões.
- **B — Produção calculada + aldeões só visuais (escolhida).** O servidor faz a conta (aldeões × taxa); cada cliente
  desenha bonecos indo e voltando, sem existência no servidor. Leve e rápido. O perigo da exploração fica com o
  jogador; a "emboscada a coletores" vira ataque a uma serraria ou pedreira distante.
- **C — Híbrido** (reais só nos pontos distantes). Deixado como evolução possível de B.

Recursos do mapa e covis: gerados da semente; o servidor só informa o que foi esgotado ou limpo.

## Design

### 1. Recursos

Seis no estoque da cidade (compartilhado no co-op, como o ouro):

| Recurso | Onde vem | Para quê |
|---|---|---|
| Ouro | impostos, mercado, caça, veios de ouro, baús | tudo, salários |
| Comida | fazenda, caça, arbustos de frutas | aldeões, soldados, treinar aldeão |
| Madeira | árvores (jogador e serraria) | quase todas as construções |
| Pedra | pedras (jogador e pedreira) | muros, torres, prefeitura |
| Ferro | veios de ferro (só jogador, anel do meio) | torre de canhão, canhoneiro, cavaleiro, melhorias nível 3 |
| Cristal | cristais arcanos (só jogador, anel externo, meteoros) | torre arcana, mago |

O HUD mostra os seis. Ferro e cristal só aparecem quando o jogador tiver pelo menos 1 (para não poluir o começo).

### 2. Aldeões

- `citizens` passa a significar aldeões. A prefeitura dá os aldeões iniciais (5 solo, 6 co-op, como hoje).
- **Livres vs. ocupados.** Cada construção tem `crew` (aldeões que ocupa). Construir exige aldeões livres suficientes;
  demolir devolve. `crew` sugerido: fazenda 2, mercado 2, serraria 3, pedreira 3, quartel 1, torres 1, casas/muros 0.
  As torres ocupam 1 porque precisam de alguém operando.
- **Crescimento custa recurso.** Some o crescimento automático do amanhecer. Na prefeitura (E) há "Treinar aldeão":
  40 comida, 8 s de fila no servidor, limitado pelas moradias (`pop_cap`). Os refugiados do evento continuam dando aldeões de graça.
- O imposto continua: aldeão (livre ou ocupado) paga imposto. Recrutar soldado continua consumindo 1 aldeão.
- Se faltar aldeão (fome, deserção), as construções com `crew` desfalcado produzem proporcionalmente menos
  (substitui o `eff` atual) e as torres sem operador atiram 50% mais devagar.
- A produção vira **contínua no dia** para madeira e pedra (tique a cada poucos segundos, no servidor), para o
  jogador ver o estoque subir. Comida e ouro continuam no amanhecer, como hoje.

### 3. Construções novas e custos

- **Serraria** (`lumber_camp`): precisa de ≥ 4 árvores vivas num raio de 14 m. Produz madeira por aldeão ocupado e
  "consome" as árvores do raio (uma árvore some a cada N de madeira, para a serraria esgotar e precisar mudar).
  Pode ficar **fora** do raio da cidade (é o alvo do evento de ataque).
- **Pedreira** (`quarry`): igual, com pedras num raio de 14 m.
- Todas as construções ganham custo em vários recursos: `cost` vira dicionário `{"gold":, "wood":, "stone":, "iron":, "crystal":}`.
  O custo progressivo do co-op (`COST_GROWTH`) multiplica todos os recursos. Melhoria e reparo também pedem
  madeira/pedra (melhoria para o nível 3 pede ferro). Demolir devolve 50% de cada recurso.
- Tabela inicial (o builder pode ajustar na passada de balanceamento):

| Construção | Ouro | Madeira | Pedra | Outros |
|---|---|---|---|---|
| Casa | 30 | 40 | 0 | |
| Fazenda | 30 | 50 | 0 | |
| Serraria | 40 | 30 | 0 | |
| Pedreira | 40 | 50 | 0 | |
| Mercado | 90 | 60 | 20 | |
| Quartel | 100 | 80 | 40 | |
| Muro | 4 | 0 | 8 | |
| Portão | 20 | 20 | 15 | |
| Estacas | 10 | 20 | 0 | |
| Torre de Arqueiros | 70 | 60 | 30 | |
| Torre de Canhão | 120 | 40 | 80 | 15 ferro |
| Torre Arcana | 100 | 40 | 50 | 10 cristal |

- Estoque inicial: madeira 150, pedra 60 (co-op: +50 madeira por jogador). Ouro inicial cai um pouco
  (o builder ajusta), porque parte do custo saiu do ouro.
- A barra de construção mostra o custo de cada recurso. O que falta aparece em vermelho, e o motivo de não poder
  construir diz o que falta ("Faltam 20 de pedra", "Faltam 2 aldeões livres").

### 4. Coleta pelo jogador

- Árvores, pedras, veios e cristais são **nós de recurso** que o ataque normal do jogador acerta (sem ferramenta nova).
- Cada golpe tira um pedaço e dá recurso na hora, com número flutuante ("+6 madeira"). Para não virar grind, poucos
  golpes por nó: árvore ~4 golpes (24 madeira no total), pedra ~5 (25 pedra), veio de ferro ~6 (12 ferro),
  cristal ~6 (8 cristal), veio de ouro ~6 (60 ouro), arbusto de frutas 1 interação (12 comida).
  O nível/arma do jogador não muda o rendimento.
- O nó esgotado some (a árvore cai, a pedra quebra) e volta depois: árvores e arbustos em 2 dias; pedras, veios e
  cristais em 4 dias, **no mesmo lugar** (simples e determinístico).
- Os nós **não** entram no grupo `enemies`: torres e soldados não podem mirá-los. O ataque do jogador consulta um
  grupo novo (`harvest`). No cliente, o golpe vira pedido ao servidor, no mesmo molde de `city_hit_animal`.

### 5. Mapa em anéis (gerado da semente)

Distâncias a partir do centro (a prefeitura fica na clareira central):

Os anéis seguem o mapa atual (clareira `CLEARING` = 52 m, raio de construção da cidade 42 m, bosques de 58 m até a borda):

- **Anel 1 (52–80 m), a orla do bosque:** as árvores e pedras de hoje viram nós de recurso. É onde ficam serrarias e
  pedreiras (fora do raio da cidade, de propósito). Não há covis nem fauna agressiva aqui.
- **Anel 2 (80–105 m):** veios de ferro (6–8), veios de ouro (3–4), arbustos de frutas, lobos, os covis mais fracos.
- **Anel 3 (105 m até a borda):** cristais arcanos (5–6), urso, os covis mais fortes.

A geração usa o `rng` com semente, que já existe, numa ordem fixa. Cada nó tem um id = índice na geração, e o
servidor sincroniza só o conjunto de ids esgotados, com o dia em que voltam.

- **Todas** as árvores e pedras do miolo viram nós. As do anel decorativo da borda (`_build_borders`) não.
- Quando um nó esgota, sai de `colony.obstacles` e perde a colisão. Ao voltar, se houver uma construção em cima,
  ele espera e tenta de novo no próximo amanhecer.
- **Serraria e pedreira**: podem ficar até 80 m do centro (o anel 1). As ondas da noite não mudam de alvo para elas:
  os monstros só as atacam se passarem perto, como acontece hoje com qualquer construção. O perigo de verdade é o
  evento de ataque durante o dia.
- **Um único sistema de esgotamento**: as árvores e pedras consumidas pela serraria ou pela pedreira usam a mesma
  regra de volta (2 e 4 dias). A produção depende de quantos nós estão vivos no raio. Assim a serraria **desacelera**
  quando o bosque em volta rareia (incentivo para mudar ou para ter mais de uma), sem ficar zerada para sempre.

### 6. Covis (pontos de interesse)

- 4 a 6 por mapa, com posição pela semente, longe uns dos outros, cada um numa direção diferente
  (as 8 direções de `DIR_NAMES`).
- Tipos (montados com modelos existentes: `tent`, `campfire`, `ruin_wall`, `ruin_pillar`, `chest`, `crate`, `barrel`):
  - **Acampamento Goblin**: goblins, goblin arqueiro, xamã; chefe = Campeão Goblin.
  - **Ninho de Slimes**: slimes, slime mãe, slime explosivo; chefe = Slime Grande reforçado.
  - **Ruínas Assombradas** (anel 3): mistura forte, com elites (afixos existentes); chefe = Goblin Bruto elite.
- **Guardas**: inimigos do servidor, não `siege`, presos ao covil (voltam se forem atraídos a mais de ~25 m).
  São criados quando um jogador chega a ~45 m e somem quando ninguém está perto, para não pesar a rede à toa.
  Os guardas mortos voltam ao amanhecer enquanto o covil não for limpo.
- **Limpar** (matar o chefe): baú com o loot de RPG de cada jogador (como `night_reward`) + recursos para a cidade +
  um depósito rico que aparece ali (veio grande). O covil não volta.
- **Não limpo**: a cada 3 dias sobe de nível (mais guardas, chefe mais forte). Toda noite, a direção de cada covil
  de pé **entra obrigatoriamente** em `wave_dirs`, com +15% de orçamento por nível do covil, separado do orçamento
  normal e do mesmo jeito que entra no `WAVE_CAP`. Limpar é a forma de "fechar" uma direção.
- **À noite os covis dormem**: no entardecer os guardas somem (no servidor) e não nascem de novo até o amanhecer,
  mesmo com um jogador por perto. Nada novo compete com a onda pela carga do servidor.
- Estrutura genérica: `ColonyData.POIS[kind]` com `ring`, `props`, `guards`, `boss`, `reward`. Uma entrada de dungeon
  futura vira mais um `kind`.

### 7. Eventos aleatórios do dia

A partir do dia 2, no começo de cada dia, há ~60% de chance de **um** evento. O servidor sorteia, anuncia com
`say()` e uma direção ("Uma caravana parou a Nordeste") e marca o ponto na bússola/mini-mapa do HUD, se existir
(o builder verifica o que o HUD tem; se não houver marcador, adiciona um indicador simples de direção na borda da tela).
O evento acaba ao anoitecer.

- **Caravana de mercador**: NPC (`merchant.glb`) com carroça. Ao interagir, abre trocas da cidade
  (ex.: 50 madeira → 30 ouro; 40 ouro → 1 ferro × 5; 80 ouro → 3 cristal).
- **Aldeões perdidos**: 2–4 aldeões (modelo `elder` ou cavaleiro sem armadura) cercados por lobos. Matar os lobos e
  interagir dá +aldeões (até o `pop_cap`; o excedente vira comida).
- **Queda de meteoro**: efeito de impacto visível de longe; deixa 2–3 cristais extras e alguns slimes por perto.
- **Fera alfa**: um javali ou urso alfa grande (afixo visual) vagando; dá muito couro (ouro) e comida.
- **Ataque à serraria/pedreira**: só se existir uma fora do raio da cidade. Um grupo pequeno de monstros nasce perto
  e vai até ela. Se cair, fica destruída como qualquer construção.
- **Baú esquecido**: um baú guardado por 2–3 errantes, com recursos e ouro.

Os eventos de amanhecer do co-op que já existem (caravana que dá ouro, refugiados, colheita farta) continuam.

### 8. Fauna nova

Em `ColonyData.ANIMALS` e `animal.gd` (peças procedurais, como cervo e javali):

- **Lobo**: matilha de 3–4, agressivo, rápido, pouca vida, anel 2+.
- **Urso**: sozinho, agressivo, muita vida e dano, anel 3; dá bastante comida e ouro.

### 9. Tropas novas

Em `ColonyData.UNITS` (o soldado já suporta `ranged`):

- **Mago**: à distância, dano em cadeia leve + lentidão (como a Torre Arcana, em menor escala). Custo inclui cristal.
  Exige quartel nível 2.
- **Canhoneiro**: à distância, lento, dano em área. Custo inclui ferro. Exige quartel nível 2.
- O cavaleiro passa a custar ferro também.
- A aparência usa itens existentes do `item_db` (cajado/robe para o mago, armadura pesada para o canhoneiro). Se não
  houver item adequado, o builder escolhe o mais próximo, sem modelar nada novo.

### 10. Aldeões visuais (cliente)

- Cada construção com `crew` mostra até `crew` bonecos simples andando entre a porta e o nó de recurso mais próximo
  (serraria/pedreira) ou dentro da área (fazenda). Só no cliente com tela (nunca no headless), puramente
  decorativos, sem colisão.
- Ficam dentro de casa à noite.

### 11. Rede e save

- `net_state()` ganha os recursos novos, aldeões livres/ocupados, fila de treino e evento ativo.
- Eventos pontuais novos no `Lobby`: nó esgotado ou restaurado, covil mudou de estado, evento começou ou acabou.
- `to_dict()` sobe de versão: guarda os recursos, os nós esgotados, o estado dos covis e o evento. Saves antigos
  carregam com estoque inicial de madeira/pedra e covis novos.

### 12. Testes

- `tests/colony_test.gd`: custo com vários recursos (pode/não pode), aldeões livres ao construir e demolir,
  treinar aldeão, produção da serraria, esgotar e restaurar um nó, limpar um covil, save novo e save antigo.
- `tests/net_test.gd`: o cliente recebe o recurso após coletar e vê o nó esgotado.
- Rodar a skill `smoke-check` no fim.

### 13. Mapa aleatório no solo

Hoje o solo usa sempre `map_seed = 7731`. Uma partida solo nova sorteia a semente, e a semente vai para o save
(`to_dict`). Um save antigo, sem semente, carrega com 7731, para as construções não caírem em cima de árvores
novas. O cooperativo continua usando `Lobby.city_seed`.

### 14. Para onde vão os recursos (o ciclo da economia)

Como no AoE, a cidade precisa gastar sempre, senão a coleta perde o sentido. São três gastos:

- **Munição** (gasto diário): a noite consome o que o dia coletou.
- **Eras** (grandes metas do meio do jogo).
- **Pesquisas** (compras únicas, que sobram para o fim do jogo).

### 15. Munição das torres e tropas à distância

- As torres e as tropas à distância tiram munição do estoque da cidade a cada disparo:

| Quem atira | Recurso | Consumo |
|---|---|---|
| Torre de Arqueiros | madeira | 1 a cada 5 flechas |
| Torre de Canhão | pedra | 1 a cada 2 balas |
| Torre Arcana | cristal | 1 a cada 15 raios |
| Arqueiro | madeira | 1 a cada 8 flechas |
| Mago | cristal | 1 a cada 20 raios |
| Canhoneiro | pedra | 1 a cada 3 tiros |

  O servidor guarda as frações num acumulador, para não arredondar a cada tiro.
- **Sem estoque, ninguém fica sem atirar:** atiram com metade da cadência. A tela avisa uma vez ("Acabaram as flechas!")
  e o HUD pisca o recurso em falta.
- **Ordem de grandeza** (noite com ~60 s de combate ativo):
  - uma torre de arqueiros gasta ~12 de madeira por noite;
  - uma de canhão gasta ~10 de pedra;
  - uma arcana gasta ~3 de cristal.
  - **Regra de bolso: uma serraria cheia sustenta ~6 torres de arqueiros com folga.** O resto da madeira fica para construir.
- O relatório do amanhecer mostra a munição gasta.

### 16. Eras da prefeitura

Evoluir a era é a ação "Avançar de era", feita na prefeitura (E). Leva 30 s no servidor, só pode ser feita de dia
e, enquanto dura, a prefeitura não treina aldeões.

| Era | Custo | Exige | Libera |
|---|---|---|---|
| I · Aldeia | (início) | | o básico; construções até nível 1 |
| II · Vila | 250 comida, 250 madeira, 150 pedra, 200 ouro | 1 serraria, 1 pedreira | nível 2; Torre de Canhão e Torre Arcana; cavaleiro, mago e canhoneiro; pesquisas da era II |
| III · Cidade | 500 comida, 450 madeira, 400 pedra, 400 ouro, 40 ferro, 20 cristal | 1 quartel nível 2 | nível 3; pesquisas da era III; +1 aldeão de `crew` nas serrarias e pedreiras |

- O `needs_level: 2` do cavaleiro passa a ser `needs_era: 2`. O nível da construção continua dando vida e produção.
- A era é da cidade inteira. No co-op, os custos multiplicam por `1 + 0.5 × (jogadores − 1)` (`ERA_TEAM_COST`).
  O plano era `0.35`, como o teto das ondas; a simulação da seção 18 mostrou o grupo de 4 chegando à era II no
  dia 3 com 0.35 e com 0.45 (a coleta à mão cresce com cada jogador), e com 0.5 a era II fica no dia 4.

### 17. Pesquisas

Feitas na construção correspondente (E). Cada uma é comprada uma vez, leva 20 s e só pode ser feita de dia.

| Era | Pesquisa | Onde | Efeito | Custo |
|---|---|---|---|---|
| I | Machado Afiado | Serraria | +20% madeira (serraria e jogador) | 60 ouro, 60 madeira |
| I | Picareta | Pedreira | +20% pedra | 60 ouro, 80 madeira |
| I | Arado | Fazenda | +20% comida | 80 ouro, 80 madeira |
| II | Feixes de Flechas | Torre de Arqueiros | −30% munição de madeira | 100 ouro, 120 madeira |
| II | Flechas de Ferro | Torre de Arqueiros | +15% dano de flechas (torres e arqueiros) | 120 ouro, 100 madeira, 10 ferro |
| II | Alvenaria | Prefeitura | +20% vida de todas as construções | 150 ouro, 200 pedra |
| II | Serra Dupla | Serraria | +20% madeira (soma com Machado) | 120 ouro, 150 madeira, 10 ferro |
| III | Pólvora Fina | Torre de Canhão | +25% raio da explosão, −30% munição | 200 ouro, 200 pedra, 25 ferro |
| III | Foco Arcano | Torre Arcana | +1 salto na cadeia, −30% munição | 200 ouro, 25 cristal |
| III | Muralha Reforçada | Prefeitura | muros e portões +40% vida | 150 ouro, 400 pedra |
| III | Treino de Elite | Quartel | tropas +15% vida e dano | 250 ouro, 150 comida, 30 ferro |

As pesquisas ficam em `ColonyData.TECHS`, com `era`, `at`, `cost` e `fx`. São só modificadores lidos onde o número
já é calculado (produção, dano, vida, munição), sem sistema de buff novo. Vão no save e no `net_state`.

### 18. Garantia de equilíbrio

"Equilibrado" vira metas medidas. O builder ajusta os números até todas passarem:

| Meta | Alvo |
|---|---|
| Era II | possível entre os dias 4 e 6 jogando razoavelmente; nunca antes do dia 3 |
| Era III | entre os dias 9 e 12 |
| Munição | com a regra "1 serraria para 6 torres", a madeira nunca zera durante a noite até o dia 15 |
| Madeira parada | o estoque não passa de ~1500 antes do dia 12 (senão a madeira está sobrando) |
| Pesquisas | todas as da era I compráveis até a Era II; as da era III não acabam antes do dia 15 |
| Começo | no dia 1, com o estoque inicial, dá para fazer prefeitura + 2 casas + fazenda + serraria + 1 torre (o começo não pode ficar mais lento que hoje) |
| Exploração | coletar à mão durante um dia inteiro rende ~1,5× uma serraria cheia: vale sair, mas a cidade não depende só do jogador |
| Co-op | as mesmas metas com 2 e com 4 jogadores |

**Como medir:**
- **`tests/economy_sim.gd`** (novo, headless): simula 15 dias com um "jogador razoável" scriptado. Ele constrói numa
  ordem fixa, mantém 1 serraria para cada 6 torres, avança de era quando pode e usa um consumo de munição tirado de
  ondas reais. A cada dia imprime o estoque e, no fim, compara com as metas.
- Roda em solo, com 2 e com 4 jogadores, e entra no `smoke-check`.
- No fim, rodar também a skill `balance-check` para achar outliers (pesquisa ou construção que ninguém usaria, ou
  estratégia dominante).

## Decisões do usuário

- Coleta pelos dois: jogador e aldeões (opção C da coleta).
- Aldeões como produção calculada + bonecos visuais (abordagem B).
- Ordem: economia → mapa vivo → tropas novas.
- Covis estruturados para virar dungeons no futuro.
- Mapa do solo aleatório a cada partida nova.
- A cidade gasta recursos sempre: munição, eras e pesquisas. O equilíbrio é garantido por metas medidas.

## Decisões minhas (para o usuário conferir)

- Recursos vão direto ao estoque (sem carregar).
- Treinar aldeão: 40 comida na prefeitura; acaba o crescimento automático.
- Torres ocupam 1 aldeão.
- Valores de custo, rendimento e distâncias acima.
- Nós voltam no mesmo lugar (2 ou 4 dias).
- Guardas de covil só existem com jogador por perto.

## Fica a cargo do builder

- Valores finos de balanceamento (rodar a skill `balance-check` depois).
- Visual exato dos nós (veio de ferro = rocha com tom ferrugem; cristal = prisma emissivo procedural).
- Layout da UI de custos e da janela de troca da caravana, seguindo `UITheme` e as janelas existentes.
