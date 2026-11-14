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

## Decisões do usuário

- Coleta pelos dois: jogador e aldeões (opção C da coleta).
- Aldeões como produção calculada + bonecos visuais (abordagem B).
- Ordem: economia → mapa vivo → tropas novas.
- Covis estruturados para virar dungeons no futuro.
- Mapa do solo aleatório a cada partida nova.

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
