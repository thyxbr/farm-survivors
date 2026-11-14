# Encantamento de armas no ferreiro — design

Data: 2026-11-14 · Branch: `vfx-encanto-spike` (worktree `../godot-3d-vfx-encanto`), a ser atualizada com o `main` 0.10.1

## 1. Intenção

Dar ao jogador um jeito simples de fortalecer a arma: ele leva materiais ao **Doran, o ferreiro**, escolhe um
elemento e a arma sobe de nível de encantamento. A arma passa a brilhar na cor do elemento (visual já pronto no
protótipo) e ganha dano e um efeito próprio.

O objetivo real é **dar motivo para explorar o mapa de Valdoria**. Os materiais vêm de monstros e pontos de coleta
espalhados pelo mapa. O conteúdo novo feito para a Defesa da Cidade (monstros, fauna, veios, covis) hoje só aparece
naquele modo; aqui ele é reaproveitado no mundo aberto.

Pedido do usuário: processo muito simples, direto no NPC; recursos vindos do mapa; reaproveitar na vila o que foi
feito para a Defesa; decisões tomadas de modo que o jogo escale de forma divertida. As decisões abaixo marcadas
como **minhas** foram tomadas por mim com essa orientação e podem ser trocadas.

## 2. Objetivos, não objetivos, anti-objetivos

**Objetivos**
- Encantar a arma equipada falando com o Doran: escolher elemento, ver o custo, confirmar.
- 6 elementos (Fogo, Gelo, Raio, Veneno, Sagrado, Sombra), níveis +1 a +5.
- Cada elemento pede uma essência que vem de um monstro ou lugar específico de Valdoria.
- Os níveis altos pedem materiais de lugares mais perigosos e, no fim, Ecos (ligando Horda e Defesa ao RPG).
- Os outros jogadores veem o brilho e o nível da arma de cada um.
- Tudo validado e gravado pelo servidor, como o resto do personagem.

**Não objetivos (ficam para depois)**
- Encantar armadura, escudo ou acessórios.
- Itens únicos por cópia (duas Espadas de Ferro com encantos diferentes).
- Chance de falha, quebra de arma ou perda de nível.
- Troca de itens entre jogadores.
- Sistema de habilidades de personagem. As auras já aceitam ser ligadas por habilidade
  (`set_ability_aura`), mas as habilidades em si são outro projeto.
- Conserto e criação de itens no ferreiro.

**Anti-objetivos (falhou mesmo que funcione)**
- Encantar vira uma planilha: muitos passos, muitas telas, o jogador precisa de guia.
- Um elemento é claramente o melhor e os outros cinco ninguém usa.
- O jogador consegue +5 só farmando slime na porta da vila.
- O cliente consegue se dar um encanto que o servidor não registrou.
- Perder progresso ao trocar de arma faz o jogador ter medo de usar a arma nova que achou.

## 3. Restrições (o que o projeto já impõe)

- **Inventário por tipo:** `Game.inventory` é `[{"id", "qty"}]`. Não existe identidade por cópia.
- **Servidor autoritativo:** ouro, itens, Ecos e equipamento só mudam por pedido (`Econ.request(op, args)`),
  validados em `scripts/character/character_service.gd` / `char_rules.gd`, gravados no banco e registrados em
  `economy_log`. No solo, o mesmo serviço roda sobre o arquivo do personagem.
- **Balanceamento em dados:** tabelas em `data/balance/*.json`, carregadas pelo autoload `Balance` e ajustáveis
  pelo painel de admin.
- **Combate no cliente:** dano e acerto são calculados no cliente; o servidor confere (`hit_guard.gd`).
- **Visual pela rede:** o protótipo envia `look["fx"] = {"auras", "en", "lv"}`; o servidor filtra em `_clean_fx`.
- **Doran** (`scripts/world/blacksmith.gd`, `npc.gd`) já está na vila com diálogo de ambientação.
- **Versão:** mudança em rede e regras exige subir `config/version`.

## 4. Abordagens consideradas

A questão central é **onde o encantamento fica guardado**, já que o inventário não distingue cópias.

| | Abordagem | Vantagem | Custo |
|---|---|---|---|
| **A** | **Por tipo de arma.** O personagem guarda `{id da arma: {elemento, nível}}`. | Nenhuma mudança no inventário, na loja, no loot ou no save. O jogador ainda sente que encantou "a Espada de Ferro". | Duas cópias da mesma arma compartilham o encanto. |
| B | Por cópia. Cada arma vira um item único com identificador. | O mais fiel à ideia de "esta arma". Abre caminho para troca entre jogadores. | Refaz inventário, loja, loot, banco, save e a interface de itens. É um projeto maior que o próprio encantamento. |
| C | No personagem. Uma "runa" única que vale para qualquer arma equipada. | O mais simples de todos. | Deixa de ser encantamento de arma; trocar de arma não significa nada. |

**Escolhida: A** (decisão minha). É a que entrega o pedido ("muito simples, direto no NPC") sem reabrir o inventário,
e o custo é pequeno na prática: quase ninguém carrega duas cópias da mesma arma. Se um dia houver troca entre
jogadores, B pode substituir A sem mudar as regras de custo nem o visual.

## 5. Desenho

### 5.1 Regras

- O encanto pertence ao **tipo de arma** do personagem. Fica guardado mesmo que a arma seja desequipada ou vendida
  (o Doran "conhece" aquele modelo). Comprar ou achar a mesma arma de novo traz o encanto de volta. *(minha)*
- **Sem falha.** Pagou, subiu. O limite é o custo. *(minha)*
- **Subir de nível** mantém o elemento. **Trocar de elemento** mantém o nível e custa uma taxa pequena, para o
  jogador experimentar sem medo. *(minha)*
- Só a **arma equipada** pode ser encantada, e só **perto do Doran** (mesma distância de interação dos NPCs).
- Nível máximo: **+5**.

### 5.2 O que o encanto dá

Todo encanto aumenta o dano da arma. Cada elemento soma um efeito, que cresce com o nível.

| Nível | Dano da arma |
|---|---|
| +1 | +5% |
| +2 | +10% |
| +3 | +16% |
| +4 | +23% |
| +5 | +30% |

| Elemento | Efeito ao acertar | Em +1 → +5 | Bom para |
|---|---|---|---|
| Fogo | Queimadura: dano ao longo de 3 s | 15% → 45% do dano do golpe | dano bruto, alvos com muita vida |
| Gelo | Lentidão por 2 s | 15% → 40% mais lento | controlar grupos, fugir |
| Raio | Chance de saltar para outro inimigo próximo | 10% → 30% de chance, 50% do dano | hordas |
| Veneno | Alvo marcado recebe mais dano de todos por 4 s | +4% → +12% | jogar em grupo |
| Sagrado | Dano extra contra chefes e elites | +8% → +25% | chefes, covis |
| Sombra | Cura ao acertar | 1% → 3% do dano causado | sobreviver sozinho |

*(valores meus, iniciais; ficam em `enchant.json` para ajuste)*

Reaproveita o que já existe: Gelo usa o efeito `slow` das armas; Sombra usa o atributo `leech`; Raio usa a lógica
de corrente das armas da Horda. Fogo e Veneno são estados novos no inimigo.

### 5.3 Materiais e de onde vêm

Materiais novos do personagem (itens do tipo `material`, empilháveis):

| Material | Vem de | Onde em Valdoria |
|---|---|---|
| Minério de Ferro | veio de ferro (coleta com ataque) | perto do Acampamento Goblin |
| Cristal Arcano | cristal arcano (coleta com ataque) | nas Ruínas |
| Núcleo em Brasa (Fogo) | Slime Explosivo | Ninho de Slimes |
| Gota Gélida (Gelo) | Slime Veloz | Ninho de Slimes |
| Totem Trovejante (Raio) | Goblin Xamã | Acampamento Goblin |
| Glândula Tóxica (Veneno) | Slime Mãe | Ninho de Slimes |
| Pó Dourado (Sagrado) | Goblin Dourado (raro, foge) | aparece pelo mapa |
| Presa Sombria (Sombra) | Lobo | floresta, entre a vila e as Ruínas |
| Insígnia do Campeão | Campeão Goblin (mini-chefe) | Acampamento Goblin |

Conteúdo da Defesa reaproveitado em Valdoria:
- **Monstros:** Slime Veloz, Explosivo e Mãe; Goblin Arqueiro, Xamã, Bruto, Dourado e Campeão. Hoje Valdoria só
  tem Slime, Goblin Batedor e o Rei Goblin.
- **Fauna:** Lobo (matilha) e Urso, de `animal.gd`.
- **Coleta:** veios de ferro e cristais, de `resource_node.gd`, com o mesmo golpe e a mesma volta depois de um tempo.
- **Covis:** a ideia de `den.gd` (guardas presos ao lugar e um chefe). O Acampamento Goblin e as Ruínas, que já
  existem no mapa, ganham os guardas novos; entra um **Ninho de Slimes** como terceiro ponto.

Disposição por perigo, do mais perto ao mais longe da vila: Ninho de Slimes → floresta dos lobos →
Acampamento Goblin → Ruínas. É a mesma lógica de anéis do mapa da Defesa.

### 5.4 Custos

| Para chegar a | Ouro | Ferro | Cristal | Essência do elemento | Extra |
|---|---|---|---|---|---|
| +1 | 50 | 4 | — | 2 | — |
| +2 | 120 | 8 | — | 4 | — |
| +3 | 250 | 12 | 4 | 6 | — |
| +4 | 500 | 16 | 8 | 8 | 1 Insígnia do Campeão |
| +5 | 1000 | 20 | 12 | 10 | 40 Ecos |

Trocar de elemento: 100 de ouro + 3 essências do elemento novo.

Como isso escala *(raciocínio meu)*:
- **+1 e +2** saem na primeira hora, com o que há perto da vila. O jogador vê o brilho cedo.
- **+3** exige ir às Ruínas buscar cristal.
- **+4** exige vencer o Campeão Goblin, um mini-chefe.
- **+5** exige Ecos, que só vêm da Horda e da Defesa. É o que amarra os três modos.
- Cada arma nova recomeça do zero, então o gasto nunca acaba, mas subir uma arma fraca até +2 é barato.

### 5.5 Interface

Ao falar com o Doran, o diálogo ganha a opção **"Encantar arma"**, que abre um painel único:

```
┌─ Encantar: Espada de Ferro +2 (Fogo) ───────────────────┐
│                                                         │
│   [prévia 3D da arma     Elemento                       │
│    com o brilho do       (Fogo) (Gelo) (Raio)           │
│    nível seguinte]       (Veneno) (Sagrado) (Sombra)    │
│                                                         │
│   Próximo nível: +3                                     │
│   Dano +10% → +16%   Queimadura 22% → 30%               │
│                                                         │
│   Custo                         Você tem                │
│   Ouro               250          412   ✓               │
│   Minério de Ferro    12            9   ✗               │
│   Cristal Arcano       4            4   ✓               │
│   Núcleo em Brasa      6           11   ✓               │
│                                                         │
│   Falta: 3 Minério de Ferro (veios perto do             │
│   Acampamento Goblin)                                   │
│                                                         │
│                  [ Encantar ]   [ Fechar ]              │
└─────────────────────────────────────────────────────────┘
```

- Sem arma equipada, o painel diz isso e não mostra custo.
- Quando falta material, o painel diz **onde consegui-lo**. É o que substitui um guia.
- Ao encantar: o Doran bate na bigorna, as faíscas saem na cor do elemento, a arma na mão do jogador acende.
- A dica do item no inventário mostra o encanto ("+3 Fogo") e seus bônus.

### 5.6 Servidor, dados e rede

- Nova tabela de balanceamento `data/balance/enchant.json`: elementos, bônus por nível, custos, essência de cada
  elemento, taxa de troca.
- O personagem ganha o campo `enchants`: `{id da arma: {"el": elemento, "lv": nível}}`. Entra no banco (migração
  nova) e no arquivo do solo.
- Novo pedido `enchant` em `Econ.request`, com argumentos `[id da arma, elemento]`. O servidor confere: arma
  equipada, elemento válido, nível abaixo do máximo, jogador perto do Doran, recursos suficientes. Em uma só
  transação debita e grava, registra em `economy_log` e devolve o estado.
- O dano e o efeito do encanto entram nos mesmos `mods` que o `Game` já usa para o combate. O `hit_guard` do
  servidor passa a contar o bônus de dano do encanto no teto que aceita.
- **Visual:** o `look["fx"]` deixa de vir do cliente no caso do encanto. O servidor preenche `en` e `lv` a partir
  do que ele mesmo tem gravado para a arma equipada. As auras continuam declaradas pelo cliente (são só cosméticas)
  e filtradas por `_clean_fx`.
- As teclas de teste F7/F8 e os argumentos `--enchant`/`--buffs`/`--auras` saem do jogo ou ficam só em modo de
  desenvolvimento.

### 5.7 Testes

- **Unitários** (`tests/unit/`): regras de custo, validações do pedido, bônus por nível, troca de elemento.
- **Gameplay** (`smoke_test.gd`): coletar ferro, receber essência de um monstro, encantar no Doran, conferir o dano.
- **Multiplayer** (`net_test.gd`): encantar pelo servidor e ver o brilho na réplica do outro jogador (as
  verificações de aura e encanto do protótipo já existem e são adaptadas).
- **Balanceamento:** rodar a skill `balance-check` nos números de 5.2 e 5.4.

## 6. Ordem de entrega

1. **Trazer o protótipo para o `main` atual.** A branch está 370 arquivos atrás; `player.gd` e `network.gd` mudaram
   muito. Resultado: auras de buff e brilho de encanto funcionando sobre a 0.10.1, sem regras ainda.
2. **Regras e servidor.** `enchant.json`, campo `enchants`, pedido `enchant`, bônus de dano. Testável por teste
   unitário e por comando, antes de existir interface.
3. **Painel do Doran.** Opção no diálogo, painel, animação e faíscas.
4. **Materiais básicos em Valdoria.** Veios de ferro, cristais e as essências que saem dos monstros que entram
   primeiro (Ninho de Slimes e guardas novos do Acampamento). Aqui o ciclo já fecha até +3.
5. **Efeitos dos elementos.** Os seis efeitos de 5.2.
6. **Conteúdo de nível alto.** Lobos, Goblin Dourado, Campeão Goblin, custo em Ecos. Fecha +4 e +5.

Cada passo deixa o jogo funcionando e pode ser entregue separado.

## 7. Decisões minhas, para o usuário conferir

1. Encanto por **tipo de arma**, não por cópia (abordagem A).
2. O encanto **não se perde** ao vender a arma.
3. **Sem chance de falha.**
4. Trocar de elemento **mantém o nível** e custa pouco.
5. Os **seis efeitos** e seus números (5.2).
6. Qual monstro dá qual essência (5.3).
7. A tabela de custos, incluindo **Ecos no +5** (5.4).
8. Um **Ninho de Slimes** novo no mapa de Valdoria.
9. O **servidor** define o encanto mostrado aos outros; o cliente não declara.

## 8. Deixado para o builder

- Posições exatas dos veios, cristais, ninho e matilhas no mapa de Valdoria.
- Taxas de queda das essências e tempos de volta dos monstros e nós (meta: os números de 5.4 saem no ritmo
  descrito em "como isso escala").
- Como o estado de Queimadura e de Veneno é guardado no inimigo e replicado.
- Aparência dos ícones dos materiais novos (`icon_painter.gd`).
- Texto das falas novas do Doran.
- Se o painel reaproveita `CharPreview` ou tem uma prévia só da arma.
