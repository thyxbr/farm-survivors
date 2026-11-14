# Cidade-hub, servidor autoritativo e painel de admin — design

Data: 2026-11-13 · Branch do design: `hub-design`

## 1. Intenção

Hoje o multiplayer começa num **salão em forma de menu** (`scenes/lobby.tscn`, `scripts/ui/lobby_ui.gd`): uma fogueira
ao fundo e botões para Valdoria e para a Defesa da Cidade em grupo. O que se quer é um jogo com **ciclo de partidas
(roguelite)**:

1. O jogador está numa **cidade-hub 3D**, andando com o próprio cavaleiro, vendo e interagindo com os outros jogadores.
2. Sai dela para uma **partida** — Defesa da Cidade ou Desafio da Horda — e vai o mais longe que conseguir.
3. Ao perder, volta à hub trazendo **Ecos** (moeda de progressão) proporcionais a quão longe foi.
4. Na hub gasta Ecos em **passivas permanentes do personagem** (NPC) e **doa Ecos para construções compartilhadas**
   da cidade, que dão bônus a todos nas partidas. Cada ida seguinte fica mais fácil; o jogador chega mais longe.

A hub é o lugar social do jogo e a "base" que o grupo evolui junto.

Para isso o servidor passa a ser **dono de todo o personagem** (ouro, itens, XP, Ecos, passivas…), com **contas de
login e senha**, preparado para trocar por login da **Steam** no futuro. O admin precisa **balancear dentro do jogo**:
ver estatísticas das partidas e da economia e editar os números (itens, passivas, construções, recompensas) sem deploy.
O **modo solo offline continua existindo** para quem não quer jogar online.

Os jogadores atuais são todos de teste: **saves e personagens existentes são descartados**, sem migração.

## 2. Objetivos, não objetivos, anti-objetivos

**Objetivos**
- Cidade-hub 3D jogável como ponto de chegada do online, com jogadores replicados, chat e emotes simples.
- Ecos ganhos ao fim de cada partida (Defesa e Horda), passivas permanentes compradas com Ecos, base compartilhada
  financiada por doações.
- Servidor autoritativo sobre o personagem inteiro e sobre a base; contas com senha (hash + sal); login por HTTPS.
- Todos os números de balanceamento fora do código, em tabelas que o servidor carrega do banco e envia aos clientes.
- Painel de admin no jogo: estatísticas + edição das tabelas, com efeito imediato e histórico para desfazer.
- Solo offline com as mesmas regras, sem duas versões da economia.

**Não objetivos (por agora)**
- Mercado/troca entre jogadores (o servidor autoritativo deixa isso possível depois, mas não entra agora).
- Login Steam de fato (só a camada de provedor pronta para ele).
- Ranking competitivo, anti-cheat de movimento/combate (posição e acertos continuam vindo do cliente como hoje).
- Recuperação de senha por e-mail.

**Anti-objetivos (seria fracasso mesmo funcionando)**
- A senha trafegar em texto pelo UDP ou ficar gravada sem hash.
- Duas implementações da economia (uma solo, outra online) que divergem com o tempo.
- Balancear exigir editar código e fazer deploy.
- A cidade compartilhada zerar a cada deploy (dados fora de volume persistente).
- A hub virar uma cópia da vila de Valdoria (Bram e Mira continuam lá; a hub tem papel próprio).

## 3. Restrições do projeto

- Godot 4.7.2, GDScript. Servidor dedicado headless em Docker (Debian) no Easypanel, UDP 7777 publicado em modo host;
  o domínio do Easypanel tem HTTPS com proxy para uma porta HTTP do container.
- Rede atual: ENet via autoloads `Network` (jogadores, zonas, inimigos, Horda) e `Lobby` (salão e Defesa em grupo).
  Zonas em `players[id].zone`: `lobby`, `world`, `city`. O relé de posição já funciona por zona, mas ignora `lobby`
  (`network.gd`, `_player_state`).
- Estado do personagem hoje vive no cliente: autoload `Game` (`gold`, `inventory`, `equipment`, `xp`, `quests`,
  `farm`…) com save em `user://savegame.json`. Ouro e itens mudam em ~17 pontos de 14 arquivos (loot, loja, cozinha,
  horta, Horda, Defesa, missões).
- Números hoje são `const` em código: `item_db.gd` (ITEMS, CROPS, RECIPES, SHOP_STOCK…), `colony_data.gd`,
  `upgrades.gd` (armas, PASSIVES, BLESSINGS), recompensas em `lobby.gd`/`survival_mode.gd`.
- CI (`.github/workflows/deploy.yml`) roda import, smoke test, teste de colônia e `tests/net_test.gd` antes do deploy;
  a versão em `project.godot` precisa subir a cada mudança de jogo. Auto update do cliente Windows via GitHub Releases.
- Futuro na Steam: o login precisa aceitar um "ticket" de outro provedor sem reescrever o resto.

## 4. Abordagens consideradas

**Hub**
- **A. Cena nova `hub.tscn` como zona `hub` (escolhida).** Praça própria, segura, sem inimigos; reaproveita o relé de
  posição por zona. Custo: um cenário 3D novo.
- B. Usar a vila de Valdoria como hub. Menos cenário, mas divide mapa com inimigos e missões do RPG e mistura a base
  com a vila do solo. Descartada.
- (Manter o salão-menu com 3D ao fundo foi descartado: não dá interação entre jogadores.)

**Base** — escolhida **compartilhada** (uma por servidor), com passivas **pessoais**. Alternativa (base pessoal, no
save de cada um) era mais simples, mas sem motivo social para a hub.

**Autoridade sobre o personagem** — considerados: (1) servidor só guarda o save, (2) servidor dono de tudo, e um
meio-termo (só Ecos/passivas no servidor). Escolhido **(2) servidor dono de tudo**, com reset dos saves, porque o
usuário quer o fluxo completo agora e mercado entre jogadores no horizonte.

**Transporte do login**
- **A. Login por HTTPS, jogo por UDP com token (escolhida).** O certificado do domínio do Easypanel já existe; a senha
  nunca passa pelo UDP; o mesmo endpoint recebe o ticket da Steam depois.
- B. DTLS no ENet. Uma porta só, mas exige certificado próprio no UDP com renovação manual. Descartada.

**Armazenamento** — o usuário pediu **banco de dados desde o início**. Escolha: ver §5.2.

## 5. Desenho

### 5.1 Processos e portas

```
Cliente (Godot)  ──HTTPS──▶  domínio Easypanel  ──HTTP──▶  servidor Godot :8080  (login, cadastro, sessão)
Cliente (Godot)  ──UDP────▶  servidor Godot :7777 (ENet: jogo, com token de sessão no registro)
servidor Godot   ──────────▶ banco SQLite em volume persistente (/data/valdoria.db)
```

- O mesmo processo Godot headless serve HTTP (porta `HTTP_PORT`, padrão 8080) e ENet (`GAME_PORT`, 7777).
  HTTP mínimo próprio sobre `TCPServer` (só JSON, poucas rotas); o TLS é terminado pelo proxy do Easypanel.
- Rotas: `POST /auth/register {user, pass}`, `POST /auth/login {user, pass}` → `{token, expires}`;
  `POST /auth/steam {ticket}` reservada (responde "não suportado" por enquanto); `GET /health` (versão, para o CI).
- O registro no ENet (`_register` hoje recebe nome) passa a receber **token**; o servidor resolve token → conta,
  recusa token inválido/expirado e recusa a mesma conta conectada duas vezes (derruba a sessão antiga).
- **Provedor de identidade** como interface: `AuthProvider.verify(credenciais) -> account_id`. Hoje
  `PasswordProvider`; depois `SteamProvider` (valida ticket com a Web API da Steam e liga a um `account_id`).

### 5.2 Banco de dados

**Escolha do builder registrada aqui: SQLite via GDExtension `godot-sqlite`**, arquivo num volume do Easypanel.
Motivo: banco SQL de verdade (transações, índices, consultas para as estatísticas) sem um serviço extra — o Godot não
tem driver de PostgreSQL, então Postgres exigiria um serviço intermediário em outra linguagem. Migrar para Postgres
depois continua possível porque todo acesso passa por uma camada `Db` (nenhuma cena fala SQL direto).

- Volume: Easypanel → *Mounts* → volume em `/data`; `DB_PATH=/data/valdoria.db`. Documentar no README.
- Migrações versionadas (`schema_version`), aplicadas na subida do servidor.
- Tabelas (esboço; o builder ajusta colunas):
  - `accounts(id, username UNIQUE, pass_hash, pass_salt, provider, provider_uid, is_admin, created_at, last_login)`
  - `sessions(token, account_id, expires_at)`
  - `characters(account_id PK, level, xp, gold, ecos, stat_points, attributes JSON, hp, mp, equipment JSON,
    quests JSON, flags JSON, farm JSON, world_pos JSON, updated_at)`
  - `inventory(account_id, item_id, qty)` (ou JSON no `characters` — escolha do builder)
  - `passives(account_id, passive_id, level)`
  - `base_buildings(building_id PK, level, fund)` e `base_donations(account_id, building_id, amount, at)`
  - `balance_tables(name PK, data JSON, version, updated_at, updated_by)` e
    `balance_history(id, name, data JSON, version, at, by_account)`
  - `runs(id, mode, started_at, ended_at, reached, players JSON, result JSON)` e `run_players(run_id, account_id,
    reached, ecos, gold, xp, build JSON)`
  - `economy_log(id, at, account_id, kind, amount, item_id, source)` — toda entrada/saída de ouro, Ecos e itens.
- Senha: PBKDF2-HMAC-SHA256 com sal aleatório por conta (`HMACContext`/`Crypto` do Godot), ≥100k iterações;
  comparação em tempo constante. Limite de tentativas de login por IP/conta.
- O primeiro admin é marcado por variável `ADMIN_USERS=nome1,nome2` (aplicada no login) ou por linha de comando do
  servidor; não há tela para virar admin.

### 5.3 Servidor autoritativo do personagem

- Novo serviço no servidor (ex.: autoload `Economy`/`CharacterService`) é o **único** lugar que muda ouro, itens, XP,
  Ecos, passivas, equipamento, missões e horta. Cada mudança: valida, grava no banco (transação), registra em
  `economy_log`, envia o novo estado ao dono.
- O cliente vira **espelho**: `Game` mantém as mesmas propriedades para a UI e para o combate ler, mas as funções que
  hoje mutam (`add_gold`, `add_item`, `remove_item`, `buy`, `sell`, `equip`, `unequip`, `use_item`, `eat`, `cook`,
  `plant`, `water`, `fertilize`, `unlock_next_plot`, `spend_point`, `start_quest`, `complete_quest`, recompensas
  de Horda/Defesa) viram **pedidos** ao servidor; a UI atualiza quando a resposta chega.
- Origem dos ganhos é do servidor: loot e XP vêm de inimigos que o servidor já possui (hoje o servidor já sabe quem
  acertou); recompensas de rodada/noite já são calculadas no servidor nas partidas em grupo. Pickups no chão passam a
  ser entregues pelo servidor ao pegar (validação de distância simples).
- Horta: o servidor guarda instantes de plantio e calcula o estado; o cliente só desenha.
- Save: não existe mais `savegame.json` no online; o servidor grava a cada mudança relevante (ou em lote curto).
  F5/F9 e "carregar save" deixam de existir no online.
- Combate (dano, posição, esquiva) **continua no cliente** como hoje (não objetivo).

### 5.4 Onde roda a partida (online e solo) — decidido com o usuário

- **Online: toda partida roda no servidor**, inclusive quem entra sozinho na Horda ou na Defesa (é um grupo de 1,
  pelo mesmo caminho das partidas em grupo: `survival_mode` role "server" e a cidade no `SubViewport`). Valdoria
  online já tem inimigos do servidor. O servidor sabe o alcance de cada partida e entrega loot, XP, ouro e Ecos;
  o cliente nunca informa o que ganhou. Isso protege os Ecos e a base compartilhada.
  Consequência: remover os caminhos em que o cliente online roda a partida localmente (ex.: Horda solo dentro do
  online, `Network.horde_xp` reportado pelo cliente).
- **Solo offline: a partida continua rodando no PC**, como hoje (roles "solo" de `survival_mode`/`colony` e
  inimigos locais em Valdoria). A **mesma camada de economia** (o serviço de 5.3) roda dentro do próprio processo,
  gravando num SQLite local (`user://solo.db`) com uma conta local fixa, sem senha e sem HTTP. Os ganhos que a
  partida local produz chamam essa camada direto. Trapaça offline só afeta o save local.
  Uma economia só: o serviço é um módulo usado pelo servidor dedicado e pelo solo; só muda quem chama.
  (Descartado: subir um servidor local em segundo processo — dobraria a fase 1 e tiraria a pausa do solo.)
- Personagem solo e personagem online são separados.
- O solo usa as **tabelas de balanceamento que vêm com a versão** (arquivos em `res://data/balance/*.json`).
  O servidor online semeia o banco com esses arquivos na primeira subida e, depois, usa o que está no banco.
- Hub no solo: a mesma cena, sozinho; a base do solo é a do banco local (progride só com você).
- Ao fechar o jogo, o processo local é encerrado (e encerra sozinho se o cliente sumir).

### 5.5 Tabelas de balanceamento

- Saem do código para `res://data/balance/`: `items.json` (de `ItemDB.ITEMS`, preço, atributos, raridade),
  `loot.json` (tabelas de drop por inimigo), `shop.json`, `crops.json`, `recipes.json`, `enemies.json`
  (vida/dano/XP), `horde.json` (armas, passivas e bênçãos da Horda), `colony.json` (`ColonyData`),
  `rewards.json` (ouro/XP/Ecos por noite e por rodada), `meta_passives.json`, `base_buildings.json`.
- Um autoload `Balance` expõe as tabelas; o código lê `Balance.items[...]` em vez de `const`. Textos e nomes de
  exibição podem ficar nas tabelas também.
- No login o servidor envia as tabelas (ou só a versão; o cliente pede as que mudaram). Quando o admin salva uma
  tabela, o servidor grava versão nova, envia a todos os conectados e o efeito vale **na próxima ação** (itens) ou
  **na próxima partida** (regras de partida em andamento não mudam no meio).
- Validação ao salvar: esquema por tabela (campos e faixas); o servidor recusa tabela inválida com a mensagem.

### 5.6 Cidade-hub

- Cena `scenes/hub.tscn` (zona de rede `hub`): praça de cidade compacta, segura, sem inimigos. Substitui
  `lobby.tscn` como chegada ao conectar e como "Voltar" ao fim das partidas. O `lobby_ui.gd` deixa de ser a tela
  principal; o que ele faz vira pontos do mapa.
- Jogadores andam com o próprio cavaleiro (`player.gd` reaproveitado sem combate), nome flutuante, chat (Enter)
  e emotes (acenar, sentar, comemorar — 3 a 4, por tecla/roda).
- Pontos da praça:
  - **Portal da Horda** — abre/entra na fila da Horda em grupo (fluxo atual de convite).
  - **Mesa de guerra da Defesa** — criar/entrar na sala, pronto, começar (fluxo atual da sala da Defesa).
  - **Estrada para Valdoria** — vai para o mundo do RPG (zona `world`), como hoje.
  - **Mestre de passivas** (NPC) — compra/sobe passivas permanentes com Ecos.
  - **Mercador** (NPC) — loja com estoque das tabelas (o mesmo papel da Mira, na hub).
  - **Terrenos da base** — 3 construções compartilhadas no início (ver 5.8).
  - **Quadro de recordes** — melhor noite da Defesa e melhor rodada da Horda do servidor.
- Interação entre jogadores no início: ver uns aos outros, chat, emotes, convidar para a Horda/sala da Defesa por
  perto (E sobre outro jogador → "Convidar"). Troca/mercado entre jogadores fica fora (não objetivo).

### 5.7 Ecos e passivas permanentes

- **Ecos**: moeda só de progressão, dada pelo servidor ao fim de cada partida, proporcional ao alcance
  (Defesa: por noite vencida; Horda: por rodada; tabela `rewards.json`). Entra também no `economy_log` e em `runs`.
- **O que fica da partida no personagem** (decidido com o usuário):
  - **Defesa**: o ouro da cidade é um **caixa da partida**, separado do ouro do personagem, e some no fim.
    O Celeiro aumenta esse caixa inicial. (Hoje o solo sobrescreve `Game.gold`; isso acaba.) As recompensas por
    noite (ouro/XP/itens do personagem) continuam como hoje, agora entregues pelo servidor.
  - **Horda**: ouro e itens pegos na partida **ficam com o personagem**, como hoje.
  - `economy_log`/`runs`: **um registro de resumo por partida** (ouro, XP, itens, Ecos), não um por moeda coletada;
    compras, vendas, doações e passivas continuam registradas uma a uma.
- **Passivas permanentes** (`meta_passives.json`): versões permanentes e mais fracas das passivas da Horda
  (Poder, Vigor, Armadura, Regeneração, Celeridade, Ímã, Alcance, Botas), cada uma com níveis e custo crescente.
  Valem no personagem em todo o jogo (Valdoria, Horda e Defesa) via os mesmos `mods` que o `Game` já usa.
  Valores iniciais são palpite e serão ajustados pelo painel.

### 5.8 Base compartilhada

- Uma base por servidor (no solo, a do banco local). Começa com 3 construções:
  **Forja** (+% dano na Horda), **Muralha** (+vida da Prefeitura na Defesa), **Celeiro** (+ouro e comida iniciais
  na Defesa). Níveis e custos em `base_buildings.json`.
- Doação: jogador aperta E no terreno → painel com nível, fundo atual/meta, efeito atual e próximo, maiores doadores,
  botões de doar. Pedido ao servidor, que valida saldo, grava, e ao encher o fundo sobe o nível, avisa no chat e
  envia o estado a todos na hub (o modelo 3D da construção muda na hora).
- Só sobe, nunca regride. Bônus valem para todos, inclusive quem não doou e quem acabou de chegar.
- Os bônus da base entram nas partidas no início (o servidor aplica ao criar a partida).

### 5.9 Painel de admin

- Abre na hub (tecla ou NPC "Escrivão") só para contas `is_admin`; o servidor recusa pedidos de não-admin.
- **Estatísticas** (consultas no banco, com filtro de período):
  - Defesa: distribuição de "noite alcançada", duração, tamanho do grupo, onde mais se perde.
  - Horda: distribuição de rodada alcançada, armas/passivas mais escolhidas pelos que foram mais longe.
  - Economia: Ecos e ouro ganhos/gastos por dia e por fonte; passivas mais compradas; fundo da base ao longo do tempo;
    itens mais vendidos/comprados.
  - Jogadores: online agora, contas criadas, ativos por dia.
- **Edição**: escolher tabela → lista/busca de linhas → editar campos com formulário (números com faixa, sem JSON cru
  na maior parte) → Salvar (valida, versão nova, histórico) → aplica a todos. **Histórico** por tabela com
  "restaurar esta versão". **Exportar** grava os JSON atuais num arquivo que o admin coloca em `res://data/balance/`
  para a próxima versão (e o solo).
- Ações de admin ficam registradas (`balance_history.by_account`).

### 5.10 Fluxo do jogador

```
Menu → Jogar online → [Entrar | Criar conta] (HTTPS) → token → conecta UDP → Hub
Menu → Jogar solo   → sobe servidor local → conecta → Hub (sozinho)
Hub → portal/mesa → partida → derrota/abandono → resultado (+Ecos) → Hub
Hub → estrada → Valdoria (RPG) → Esc → Voltar à hub
```

## 6. Ordem de entrega

Três fases, cada uma com plano próprio e PR próprio, jogável ao fim:

1. **Fundação**: SQLite + migrações, HTTP de login/cadastro, token no ENet, `AuthProvider`, `Balance` com tabelas
   extraídas, serviço autoritativo do personagem, cliente espelho, partidas online sempre no servidor (grupo de 1), solo com a economia no próprio processo, reset dos saves,
   testes de rede adaptados (o `net_test` passa a logar com conta de teste).
2. **Hub**: cena da praça, zona `hub`, Ecos ao fim das partidas, NPC de passivas, mercador, base com 3 construções,
   recordes, emotes; `lobby.tscn` sai.
3. **Admin**: painel de estatísticas e de edição com histórico e exportação.

## 7. Deixado para o builder

- Formato exato das mensagens RPC e das rotas HTTP; granularidade de gravação no banco.
- Inventário em tabela própria ou JSON; índices.
- Layout visual da praça e dos painéis (seguir `ui_theme.gd` e o estilo low-poly do projeto).
- Valores iniciais de Ecos, passivas e construções (palpite razoável; o painel ajusta).
- Como o servidor valida pickups e vendas (distância, existência do item).
- Atualizar README, CI (porta HTTP, `/health`, conta de teste) e as skills do projeto que descrevem o salão.
