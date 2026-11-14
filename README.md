# Ecos de Valdoria — protótipo de RPG de ação 3D (Godot 4.7)

Abra a pasta no Godot 4.7 e aperte **F5**, ou rode:

```
C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --path C:/Games/godot-3d
```

## Controles
| Ação | Tecla |
|---|---|
| Mover / correr / pular | WASD · Shift · Espaço |
| Câmera | Mouse |
| Atacar | Clique esquerdo — espada: combo de 3 golpes · cajado: projéteis (3º golpe em leque) · arco: segure para tensionar e solte |
| Esquivar (invulnerável) | Clique direito ou Ctrl |
| Magias | 1 Bola de Fogo · 2 Cura (nível 2) · 3 Nova Gélida (nível 4) |
| Poções | R vida · F mana |
| Comer / trocar comida | Q · T |
| Interagir / falar | E |
| Emotes na praça (acenar · comemorar · sentar) | 1 · 2 · 3 |
| Inventário · Personagem · Missões | I (ou Tab fora da Horda) · C · J |
| Placar do grupo (no Desafio da Horda, segurar) | Tab |
| Salvar / carregar rápido | F5 / F9 |
| Pausa | Esc |
| Mostrar/esconder ajuda (começa escondida) | H |

## Conteúdo
- **Praça da cidade** (o ponto de chegada, no solo e online): de lá a estrada leva a Valdoria, o portal ao Desafio
  da Horda e a mesa de guerra à Defesa da Cidade; os **Ecos** ganhos nas partidas viram **passivas permanentes** e
  **doações para a base** (detalhes em *A praça da cidade*, abaixo).
- **Vila** com o Ancião Bram (missões) e a Mira (loja: compra e venda).
- **3 missões em cadeia**: slimes nos campos → batedores goblins na floresta a leste → **Rei Goblin** nas ruínas ao norte (chefe com ataque em área, fúria e invocação).
- **Progressão**: XP, níveis, 3 pontos de atributo por nível (Força, Inteligência, Vitalidade, Agilidade), magias liberadas por nível.
- **Itens**: 70 itens com 5 raridades (Comum, Incomum, Raro, Épico, Lendário), poções, materiais para vender, loot aleatório.
- **Armas por classe** (o ataque básico muda com a arma; o modelo 3D é montado por código em `knight_look.gd`):
  - **Espadas** (escala com Força): Madeira, Ferro, Sabre de Aço, Lâmina do Cavaleiro, Marca Gélida (deixa lento),
    Cutelo do Rei Goblin, Montante do Guardião, Presa do Dragão (lendária, rouba vida).
  - **Cajados** (escala com Inteligência e Poder mágico): Aprendiz, Carvalho Antigo, Brasas (explosão em área),
    Cetro da Geada (deixa lento), Cajado do Arquimago (lendário).
  - **Arcos** (escala com Agilidade; tensão total dá crítico extra e perfura): Curto, Caçador, Élfico,
    Arco de Guerra Goblin (sempre perfura), Arco da Tempestade (lendário, 3 flechas).
- **8 espaços de equipamento**: arma, mão secundária (escudo exige espada, orbe exige cajado, aljava exige arco),
  cabeça, peito, mãos, pés, amuleto e anel. Itens dão defesa e bônus (atributos, vida, mana, poder mágico,
  crítico, velocidade, recarga, roubo de vida). Cabeça, peito, mãos e pés trocam o modelo do personagem
  (jogador, réplicas e soldados da colônia): de camisa e calça sem nada equipado, passando por túnica, capuz,
  gibão de couro, manto arcano, cota de malha, sobreveste com cruz, até a armadura de placas; elmos de nasal,
  chapéu de ferro, elmo fechado e o do cavaleiro. Modelos em `tools/blender/gear.py` (`ASSETS=gear`),
  conferidos com `tools/look_shot.tscn`. Escudo, orbe e aljava também aparecem. Equipamentos raros ou melhores caem com um feixe de luz na cor da raridade.
- **Interface** (referências: Diablo/Path of Exile para boneco, grade e raridade; World of Warcraft para
  recarga radial; Dark Souls para a barra do chefe): HUD enxuto nas bordas da tela — globos de vida/mana compactos
  com rastro de dano, barra de ações com ícones, vigor que só aparece quando gasto, ajuda escondida no H,
  mira que mostra a tensão do arco, avisos de saque, inventário com prévia 3D, arrastar e soltar,
  filtros, "Organizar" e dica que calcula o que muda se equipar o item. Ícones desenhados por código
  (`icon_painter.gd`); tema em `ui_theme.gd`.
- **Personagem solo** num arquivo local (`user://solo_character.json`, gravado de forma atômica; F5/F9 salvam e recarregam; a base local e os recordes do solo ficam ao lado, em `solo_character_base.json` e `solo_character_runs.json`), opções persistentes (volume, sensibilidade, inverter Y, tela cheia).
  O SQLite é só do servidor dedicado: o cliente Windows é um exe único, sem DLL (o Smart App Control do Windows
  bloqueia DLL sem assinatura). O `user://solo.db` da 0.8.0 é ignorado.
- Morte com opção de renascer na vila (perde 10% do ouro) ou carregar o save.

## Horta da Vila (fazenda)
Saia pelo **portão sul** da vila para a Horta:
- **12 canteiros** (6 liberados; os outros se preparam por ouro). Tecla **E** no canteiro:
  vazio → menu de plantio (compra a semente na hora se faltar; "plantar em todos os vazios"),
  crescendo → **regar** (cresce 2x mais rápido e rende +1) e depois **adubar com Gel de Slime** (+40%),
  pronto → **colher** (12% de chance de colheita farta em dobro, 35% de devolver uma semente).
- **6 culturas**: Cenoura, Trigo, Tomate, Pimenta-de-Fogo, Menta Gélida e Abóbora. As plantas crescem em tempo real,
  inclusive enquanto você está na Arena. Sementes também caem de slimes/goblins/Rei Goblin e são
  recompensa de cada rodada do Desafio da Horda (rodadas altas dão sementes raras).
- **Caldeirão da Horta**: 8 receitas (Pão Rústico, Ensopado de Cenoura, Sopa Picante, Chili do Dragão,
  Chá de Menta Gélida, Salada da Horta, Torta de Abóbora, Banquete de Valdoria). Cada prato cura e dá um
  **bônus temporário** (dano, vida máx., defesa, recarga, XP de gemas, ouro, roubo de vida...). O Chili explode em
  fogo ao redor e o Chá congela os inimigos próximos.
- **Comer**: **Q** come a comida selecionada, **T** troca. Funciona na vila e **no meio das rodadas da Horda**;
  os bônus somam com cartas e bênçãos (coma antes de entrar no portal para começar forte). Há 3 s de mastigação
  entre pratos; morrer apaga os efeitos. Colheitas cruas também podem ser comidas pelo inventário.
- A horta é salva com o personagem. Dados de culturas/receitas em `data/balance/crops.json` e `recipes.json`.

## Desafio da Horda (modo sobrevivência)
Entre no **Portal do Desafio** (perto do portão norte da vila, ou o portal da praça, tecla E) para ir à **Arena** a oeste do mapa:
- Hordas de slimes e goblins surgem sem parar, cada rodada (45 s) mais fortes e numerosas; a cada 5 rodadas vem o **Rei Goblin**
  (a partir do 2º, com guardas de elite).
- **Curva de dificuldade** (`survival_mode.gd` e `horde_events.gd`): ritmo em dente de serra dentro de cada ciclo de
  5 rodadas (a pressão sobe até a 4ª e alivia na rodada do chefe); a vida dos inimigos cresce um pouco mais que linear,
  então a partida tende a terminar entre as rodadas 15 e 20. Da rodada 3 em diante surgem **elites** (douradas, anel no
  chão, 3x a vida, soltam mais gemas e às vezes cura). Da rodada 7 vem o **Goblin Bruto**. A meta da Caçada acompanha o ritmo.
- HUD da horda enxuta: rodada, tempo, nível (do grupo) com XP, evento e Caçada num bloco só no topo; a build fica em
  ícones no canto direito (selo com o nível); grupo à esquerda. **Segure Tab** para o placar: build, dano, abates,
  quedas e combos de cada jogador (funciona por cima das cartas).
- Armas automáticas atacam sozinhas (**Orbe de Fogo**, **Lâminas Orbitais**, **Relâmpago**, **Aura Gélida**); espada, esquiva, magias e poções continuam valendo.
- Inimigos soltam **gemas de XP**: ao subir o nível da partida você escolhe 1 de 3 cartas (arma nova, melhoria ou passiva) — teclas 1/2/3 ou clique.
- Ao fim de cada rodada a arena é limpa, você recupera 30% da vida e escolhe uma **bênção**, ou se retira com as recompensas.
- Ao sair (retirada, morte ou "Abandonar desafio" na pausa) você volta à vila (ou à praça, se entrou pelo portal da
  praça) sem perder ouro e ganha XP do RPG (abates×2 + rodadas×25) e **Ecos** pela rodada alcançada. O recorde fica salvo.
- Os bônus da partida são temporários; não é possível salvar durante o desafio.

Para editar as melhorias veja `scripts/survival/upgrades.gd`; o ritmo das rodadas fica em `scripts/survival/survival_mode.gd`.

## Defesa da Cidade (tower defense)
Menu principal → **Defesa da Cidade — nova** (ou a **Mesa de Guerra** da praça). Começa num mapa vazio (uma clareira cercada de bosques) e o
jogador posiciona **todas** as construções. De dia você constrói, recruta e sai para caçar; à noite os monstros
atacam a cidade, cada noite mais fortes (a cada 5 noites vem o Rei Goblin). Se a Prefeitura cair, a cidade cai.

| Ação | Tecla |
|---|---|
| Modo construção (fantasma verde = pode, vermelho = não e o motivo aparece) | B |
| Escolher construção · girar 45° · demolir (devolve 50%) | 1–0 · roda do mouse ou R · X |
| Construir · sair do modo | Clique esquerdo · B, Esc ou clique direito |
| Abrir a construção (melhorar, reparar, demolir; Prefeitura: economia; Quartel: recrutar) | E |
| Exército segue você (para caçar) / volta a defender | G |
| Ponto de reunião do exército onde você está · chamar a noite agora | V · N |

- **Construções** (`data/balance/colony.json`): Prefeitura (primeira, grátis, na clareira central), Casa (+5 moradores),
  Fazenda (+12 comida/dia), Mercado (+25 ouro/dia), Quartel (recrutamento, 6 vagas), Muro (encaixa na ponta de
  outro muro), Portão (você e os soldados passam, os monstros não), Estacas (ferem e atrasam), Torre de Arqueiros,
  Torre de Canhão (dano em área) e Torre Arcana (deixa lento e salta entre monstros). Tudo tem 3 níveis
  (só passa do nível da Prefeitura + 1) e precisa ficar a até 42 m da Prefeitura.
- **Economia** (paga ao amanhecer): impostos por morador (Baixo 1 · Normal 2 · Alto 3 — imposto alto faz a cidade crescer
  mais devagar), comércio dos mercados, renda da Prefeitura, **salários** do exército e consumo de **comida**
  (1 por morador e por soldado). Fazendas e mercados precisam de moradores trabalhando. Sem ouro para os salários,
  soldados desertam; sem comida, moradores vão embora. Monstros abatidos rendem ouro direto para o cofre.
- **Exército**: Miliciano, Soldado, Arqueiro (atira por cima dos muros) e Cavaleiro (quartel nível 2). Cada recruta sai
  dos moradores e cobra salário diário. Ficam em formação no ponto de reunião ou acompanham você.
- **Caça**: de dia aparecem coelhos, cervos e javalis (o javali revida) longe da cidade; rendem comida e ouro (couro).
  Slimes e goblins errantes rondam a mata. À noite os animais somem.
- **Monstros da noite** marcham até a Prefeitura, derrubam o que estiver no caminho e atacam soldados e o jogador por perto.
  Novo: **Goblin Bruto** (dano triplo em construções). O HUD mostra de que direção vem a onda.
- Se você cair, renasce na Prefeitura em 6 s (as torres continuam lutando). Salva automaticamente a cada amanhecer
  (F5 também salva, só de dia). O ouro da cidade é o caixa da partida; o personagem é o mesmo do RPG solo e
  leva só as recompensas por noite e o XP dos abates (no amanhecer).
- Pelo menu principal ou pela Mesa de Guerra da praça no solo é só para um jogador; em grupo, pela **Mesa de Guerra
  da praça online** (abaixo). Ao fim da partida cada um ganha **Ecos** pelas noites em que esteve na cidade.

## Multiplayer (servidor dedicado)
O servidor roda o Godot sem tela e é dono dos inimigos (IA, vida, morte) **e do personagem de cada conta**:
ouro, itens, XP, equipamento, missões e a Horta ficam num banco SQLite no servidor (`addons/godot-sqlite`).
O SQLite existe **só no servidor**: o export do Windows exclui `addons/godot-sqlite/*` e o `Db` acha a classe
`SQLite` pelo `ClassDB` (sem a extensão, `Db.open` devolve null em vez de quebrar a compilação dos scripts).
O jogador entra com **usuário e senha** (cadastro e login pela API HTTP do servidor, por HTTPS no servidor
público); o ENet (UDP) recebe só o token da sessão. Quem acerta um inimigo ganha XP, missão e loot quando ele
morre, concedidos pelo servidor. Os números de balanceamento (itens, inimigos, cidade, horda...) ficam em
`data/balance/*.json` e são lidos desses arquivos (servidor e solo); as tabelas `balance_tables`/`balance_history`
já existem no banco, mas semear e ler o balanceamento do banco (e editar pelo painel de admin) fica para a fase 3.

- **Servidor local:** `godot --headless --path . -- --server --port=7777 --http-port=8080 --db=user://server.db`
  - `--port` (UDP do jogo, padrão 7777), `--http-port` (API de login, padrão 8080; env `HTTP_PORT`),
    `--db` (arquivo do banco, padrão `user://server.db`; env `DB_PATH`), `--admins=nome1,nome2` (env `ADMIN_USERS`),
    `--test` (só para testes: aceita o pedido de ouro de teste do `net_test`; **nunca** em produção).
  - Cliente apontando para outra API: `-- --auth-url=http://127.0.0.1:8080`. Sem ele, IP literal ou `localhost`
    usa `http://host:8080` e domínio usa `https://domínio`.
  - **Limites da API de login:** cadastro até 3 por hora por IP e login até 10 tentativas por minuto por IP (certas
    ou erradas); acima disso `429 muitas_tentativas`. Cinco senhas erradas em 5 min bloqueiam o nome e o IP. A senha
    é derivada (PBKDF2) fora da thread do jogo, no máximo 2 ao mesmo tempo; com a fila cheia a API responde `503`.
  - **Limite de pedidos no jogo:** cada jogador tem um balde de 10 pedidos de economia (recarga de 5/s) e outro de
    30 coletas de loot (10/s); acima disso o servidor responde `devagar` sem tocar no banco.
  - O banco roda em WAL: além do `.db` existem `.db-wal` e `.db-shm` ao lado (faça backup dos três com o servidor
    parado, ou só do `.db` depois de pará-lo).
- **Docker / Easypanel:** App com build pelo `Dockerfile`. A imagem já define `GAME_PORT=7777`, `HTTP_PORT=8080`,
  `DB_PATH=/data/valdoria.db` e `DB_REQUIRE_MOUNT=1`. No Easypanel:
  - **Mounts → Volume** montado em **`/data`** — **obrigatório**. É onde fica o banco das contas; a imagem não
    declara `VOLUME` e, com `DB_REQUIRE_MOUNT=1`, o servidor confere em `/proc/mounts` que a pasta do `DB_PATH` é um
    volume montado e **se recusa a subir** (erro no log e saída com código 1) se não for — sem isso cada deploy
    apagaria todas as contas e personagens sem ninguém perceber.
  - **Domains:** o domínio do app com HTTPS fazendo proxy para a porta **8080** (`HTTP_PORT`). É por ele que o
    jogo faz login (`https://<domínio>/auth/...`) e o CI confere a versão (`https://<domínio>/health`).
  - **Advanced → Ports:** continue publicando `7777 → 7777` em **UDP** (o jogo em si não passa pelo proxy HTTP).
    Libere UDP 7777 no firewall da VPS. A porta pode ser trocada pela env `GAME_PORT`.
  - **Environment:** `DB_PATH`, `HTTP_PORT` e `ADMIN_USERS` (nomes separados por vírgula) se quiser mudar o padrão.
    **Crie a sua conta no jogo antes de pôr o seu nome em `ADMIN_USERS`**: o privilégio vai para a conta com
    aquele nome, então um nome de admin ainda sem conta poderia ser registrado por outro jogador. Enquanto isso
    acontecer o servidor avisa no log (`aviso: admin '...' ainda não tem conta`).
  - Testando a imagem localmente: `docker build -t valdoria-server .` e
    `docker run -v valdoria-data:/data -p 7777:7777/udp -p 8080:8080 valdoria-server`; `curl http://127.0.0.1:8080/health`
    responde a versão. O volume nomeado herda o dono `valdoria` de `/data`, então as contas sobrevivem a recriar o container.
    Sem `-v nome:/data` o servidor não sobe; para um teste descartável (contas somem com o container) use
    `-e DB_REQUIRE_MOUNT=0`.
  - Ao sair pelo caminho normal do Godot (pedido de fechar ou `quit`), o servidor grava todos os personagens em
    memória antes de sair. Os pedidos de economia já são gravados na hora; vida e posição vão ao banco a cada 60 s.
- **Deploy automático:** cada push no `main` roda o GitHub Actions (`.github/workflows/deploy.yml`):
  importa o projeto (e confere se a extensão SQLite carregou no Linux), roda os testes unitários, o smoke test,
  a Defesa da Cidade, a praça (`--hubtest`) e os testes de multiplayer (servidor com banco temporário, `--http-port` e `--test`; clientes
  com `--auth-url`) e, se tudo passar, chama o webhook de deploy do Easypanel (secret `EASYPANEL_DEPLOY_URL`).
  Deixe o *Auto Deploy* do próprio Easypanel desligado, senão ele publica mesmo quando os testes falham. Depois do
  deploy, o job *Conferir servidor publicado* roda `--nettest=<domínio>:7777 --probe` até o servidor aceitar a versão
  do commit: `GET https://<domínio>/health` tem que responder a versão e uma conexão UDP na 7777 tem que conectar
  (falha após ~15 min). Ele só distingue servidor velho de novo se a versão mudou: aumente a versão quando mexer no código.
- **Desligue o *Zero Downtime* do app no Easypanel.** A porta UDP é publicada em modo host: com ele ligado o
  container novo fica em *Pending* ("host-mode port already in use") e o antigo continua no ar sem atualizar.
  Para destravar na VPS: `docker service scale <serviço>=0` e depois `=1`.
- **Firewall da VPS (Hostinger):** o firewall do painel recusa tudo por padrão; adicione *Aceitar · UDP · 7777*
  (e TCP 22/80/443/3000 para SSH e o painel) antes do *Drop*.
- **Jogadores:** menu principal → *Multiplayer* → endereço (`ip`, `ip:porta` ou domínio) + usuário e senha →
  *Criar conta* na primeira vez, depois *Entrar* → **praça da cidade**. A senha não fica salva no PC.
  Antes de exportar, coloque o IP/domínio do servidor em `DEFAULT_ADDRESS` (`scripts/autoload/network.gd`).
- **Versão:** o servidor recusa clientes com `application/config/version` diferente (*Projeto → Configurações → Application → Config*).
  Para lançar uma versão nova basta aumentar a versão e dar push no `main`: o CI publica o cliente e atualiza o servidor.
  **Mudou o jogo, suba a versão:** se a versão já tem release e algo fora de docs/testes/CI mudou desde a tag,
  o CI falha antes do deploy. Sem isso o servidor receberia o código novo e os jogadores ficariam com o antigo
  na mesma versão (o servidor aceitaria a conexão e as RPCs sairiam dessincronizadas).
- **Auto update (cliente Windows):** quando a versão do `project.godot` ainda não tem release, o job
  *Exportar cliente Windows* do CI exporta o jogo (um exe só, sem DLL), o job *Ligar o exe exportado* roda esse
  exe sem tela num Windows (`--headless --quit-after 300`; falha com `SCRIPT ERROR`, `Parse Error`, `GDExtension`
  ou saída diferente de 0) e só então *Publicar cliente* cria a release `v<versão>` no GitHub com o zip e um
  `latest.json` (versão, link, SHA-256). O deploy do servidor só roda depois disso. No jogo, o autoload `Updater`
  (`scripts/autoload/updater.gd`) lê `releases/latest/download/latest.json` ao abrir o menu; se houver versão maior,
  mostra *Atualizar agora*, baixa o zip, confere o hash, troca o exe (o atual vira `.old`, apagado na próxima abertura)
  e reabre o jogo. Com o jogo aberto procura de novo a cada 5 minutos; se a versão nova sair durante a partida,
  aparece um aviso no topo da tela e o *Atualizar agora* fica no menu de pausa (Esc), que salva antes de reabrir.
  Também procura de novo sempre que o menu principal abre (ex.: depois de cair quando o servidor reinicia) e
  quando o servidor recusa a versão. Se o jogo já está mais novo que o servidor (o deploy leva alguns minutos
  depois da release), o aviso diz que o servidor está sendo atualizado em vez de pedir para atualizar o jogo. Só roda no build exportado para Windows.
  Se a pasta do jogo não aceitar gravação (ex.: *Arquivos de Programas*), oferece abrir a página de download.
  Para testar com outro manifesto: `EcosDeValdoria.exe -- --update-manifest=http://127.0.0.1:8765/latest.json --update-now`.
- Ainda só para um jogador: o "carregar save" durante a partida. No multiplayer os menus não pausam o mundo.

### A praça da cidade (hub)
- **Menu → praça**: *Novo jogo* e *Continuar* (solo) e *Entrar* (online) levam à **praça da cidade**
  (`scenes/hub.tscn`, `scripts/hub/hub_world.gd`). O cavaleiro anda pela praça sem combate; online os outros
  jogadores aparecem com o nome em cima, o chat (**Enter**) funciona e as teclas **1–3** fazem emotes (acenar,
  comemorar, sentar) que os outros veem.
- **Pontos da praça** (tecla **E**): a **estrada para Valdoria** (o mundo do RPG, missões, horta; você reaparece onde
  estava), o **Portal do Desafio da Horda** (abre ou entra na fila do servidor; no fim volta à praça), a **Mesa de
  Guerra** (Defesa da Cidade: sala do servidor online, nova/continuar no solo), **Mestre Orin** (passivas), **Tobias**
  (mercador), o **quadro de recordes** e as três construções da base: **Forja**, **Muralha** e **Celeiro**.
- **Ecos** (moeda permanente): ganhos no fim das partidas — Horda pela rodada alcançada, Defesa pelas noites em que
  você esteve na cidade (`data/balance/rewards.json`). Online quem concede é o servidor.
- **Passivas** (Mestre Orin, `data/balance/meta_passives.json`): 8 passivas de 5 níveis compradas com Ecos (dano,
  vida máxima, defesa, regeneração, recarga, alcance de coleta, área, velocidade); valem em todo lugar.
- **Base compartilhada** (`data/balance/base_buildings.json`): os Ecos doados vão para o servidor inteiro (no solo, para
  a base local). **Forja** dá dano na Horda, **Muralha** vida à Prefeitura da Defesa e **Celeiro** ouro e comida por noite
  na Defesa. Cada construção tem 5 níveis; a placa mostra o nível, o painel mostra o fundo e os maiores doadores, e
  quando uma sobe de nível o chat avisa todo mundo. Os bônus são fixados no começo de cada partida.
- O personagem online é o da conta e mora no servidor (banco): ouro, itens, XP, Ecos, passivas, equipamento, missões
  e horta mudam só por pedido ao servidor (autoload `Econ`); o cliente manda vida, mana e posição de tempos em tempos.
  O solo tem personagem próprio em `user://solo_character.json` (o cliente não leva o SQLite) (F5/F9 só em Valdoria, no solo). Esc → *Voltar à praça* sai de
  Valdoria (no Desafio da Horda, abandone primeiro) e da cidade.
- O chat (**Enter**) é do servidor inteiro: funciona na praça, em Valdoria e na cidade em grupo.
- O servidor guarda a zona de cada jogador (`players[id].zone`: `hub`, `world` ou `city`): inimigos, posições e
  efeitos só vão para quem está na mesma zona. As RPCs da praça ficam no autoload `Hub` (`scripts/autoload/hub.gd`).

### Defesa da Cidade em grupo
- Na **Mesa de Guerra** da praça: **Criar sala** → os outros clicam *Entrar na sala* e *Estou pronto* → o líder clica
  **Começar** (até 6 jogadores). Com a partida rolando, quem estiver na praça pode **Entrar na partida** no meio.
- Uma cidade por vez no servidor. Ela roda no servidor num `SubViewport` com mundo 3D próprio (física separada de
  Valdoria, que continua rodando); o servidor simula economia, ondas, torres, soldados e animais, e cada cliente vê
  réplicas. Construir, melhorar, reparar, demolir, recrutar, impostos e ponto de reunião viram pedidos que o servidor
  valida (`Colony.net_request`). O **cofre é compartilhado**; **N** é um voto para chamar a noite (basta metade do grupo);
  **G** faz o exército seguir quem apertou.
- **Recompensas** (no personagem do RPG de cada um, ao amanhecer, para quem estava na cidade durante a noite):
  `15 + 6n` ouro e `30 + 12n + n²` XP pela noite *n*; nas noites de chefe (a cada 5) um **baú** com um equipamento:
  noite 5 incomum, 10 raro (60%), 15 épico (35%), 20 lendário (15%), 25 lendário (50%), 30+ lendário. Abates dão XP
  a quem acertou e ouro ao cofre (elites valem o dobro). O recorde do servidor aparece no quadro de recordes da praça.
- **Curva de dificuldade** (tabelas em `data/balance/colony.json`; constantes do bloco *cooperativo* em `colony_data.gd`):
  - *Começo fácil:* cofre de 450 (+150 por jogador extra), 40 de comida, 6 moradores, primeiro dia de 4 min, as três
    primeiras noites pequenas e de uma direção só.
  - *Recursos sobem aos poucos:* a economia é a mesma do solo, mas **cada cópia** de uma construção custa mais
    (casa +10% por casa existente, torres +14–18%, mercado +30%, muro +1,5%); mercados além do 2º rendem 20% a menos
    cada (mínimo 40%); torres e quartéis cobram **manutenção** por nível ao amanhecer (sem ouro, elas se desgastam).
    Cada jogador extra rende +15/dia na prefeitura.
  - *Fim de jogo duro:* a vida dos monstros sobe 12% por noite e, depois da noite 10, mais 6% compostos por noite;
    da noite 6 surgem **elites** (até 45% da onda): *Blindado* (resiste a flechas e soldados), *Arcano* (resiste à Torre
    Arcana e não fica lento), *Ágil* (rápido, resiste a explosões) e, da noite 12, *Colosso* (vida ×2,2, derruba muros) —
    é preciso misturar torres. A partir da noite 7, **noites especiais** são avisadas um amanhecer antes: Lua de Sangue,
    Névoa Densa (torres −30% de alcance), Enxame e Cerco Pesado. Da noite 12 os ataques vêm de 4 direções; a noite 15
    traz 2 Reis Goblin e a 25, 3. Acima de um teto o orçamento da onda vira vida extra (menos monstros, mais duros).
  - *Grupo:* cada jogador extra dá +45% de monstros e +10% de vida.
  - *Para não ficar impossível:* a prefeitura recupera 25% da vida a cada amanhecer; a partir do dia 3, se o cofre está
    vazio ou a prefeitura muito ferida, chega a **ajuda do reino** (no máximo a cada 4 dias); 25% das manhãs trazem um
    evento bom (caravana, refugiados, colheita farta); quem cai renasce em 6 s.
- A partida acaba quando a prefeitura cai (tela de resultado com as recompensas) ou quando todos voltam à praça.
  Não há save da cidade em grupo: o que fica é o que foi para o personagem.
- Para testes, o servidor aceita `--city-day=SEG` (duração do dia na cidade).

### Desafio da Horda em grupo
- Quem entra no **Portal do Desafio** abre uma fila de 15 s e **todos os jogadores online recebem o convite**
  (em Valdoria, painel no canto: **[Y]** entrar · **[N]** recusar, ou clique; na praça, pelo portal da praça, e a
  partida espera alguns segundos quem está viajando até a arena). Quando todos respondem a contagem cai para 3 s.
  Quem aceitou vai junto para a **mesma arena**; quem estava caído na hora fica de fora.
- Há uma partida por vez no servidor: se alguém tentar entrar com uma em andamento, recebe o aviso para aguardar.
- O **servidor** é dono das rodadas, do spawn e dos abates; a horda só persegue quem está no desafio e fica
  mais numerosa e resistente conforme o tamanho do grupo.
- **O nível é do grupo**: cada um coleta as próprias gemas (todo abate solta gemas para cada um) e o XP vai para o
  servidor, que soma num nível só (dividido pelo tamanho do grupo). Ao subir de nível **a horda congela** — inimigos,
  flechas, meteoros e o relógio da rodada param — e cada um escolhe a própria carta. A luta volta quando todos
  escolhem ou após **20 s**; quem não escolheu (caiu da conexão, AFK) recebe uma carta sorteada. Quem já escolheu vê
  a faixa "horda congelada" com quem falta. Quem está caído também escolhe.
- Cartas, bênçãos, ouro e sementes continuam sendo de cada jogador (cada um monta a própria build).
  Orbes de fogo, relâmpagos, lâminas e aura dos colegas aparecem na tela.
- **Cair não encerra**: o jogador volta (com metade da vida) no fim da rodada se alguém do grupo sobreviver.
  Se todos caírem, a partida acaba para o grupo.
- No fim da rodada cada um escolhe a bênção; a próxima rodada começa quando todos escolherem (ou após 30 s).
  Retirar-se ou abandonar tira só você; os outros continuam.
- **Combos em grupo**: quando você tem uma arma automática e um colega tem a arma par, os acertos disparam o combo
  enquanto vocês estão a até 14 m (recarga de 3 s, dano cresce com o nível das duas armas). Pares: Fogo + Aura
  (Choque Térmico), Fogo + Relâmpago (Plasma), Fogo + Lâminas (Ciclone de Brasas), Relâmpago + Aura (Tempestade Gélida),
  Relâmpago + Lâminas (Lâminas Elétricas), Lâminas + Aura (Nevasca Cortante). As cartas avisam quando uma arma nova
  formaria combo com alguém do grupo (e essas armas aparecem mais). O quadro do grupo, à esquerda, mostra a vida de
  cada colega, quem está escolhendo/pronto e ◆ em quem está combando com você. Tabela em `data/balance/horde.json` (`combos`).
- O servidor conta dano, abates e quedas de cada jogador; cada cliente manda a própria build a cada segundo.
- Para testes, o servidor aceita `--horde-round=SEG` (duração da rodada), `--horde-pick=SEG` (tempo para escolher
  as cartas de nível) e `--horde-event=ID` (força um evento em toda rodada; também vale offline). Screenshot do HUD
  com uma build de exemplo: `godot --path . res://scenes/world.tscn -- --survival --hordedemo[=cards|grupo|espera] [--tab] --shot=shot.png`.

### Eventos e monstros da Horda
- A partir da rodada 2, cada rodada (menos a do chefe) pode trazer um **evento** (`scripts/survival/horde_events.gd`):
  *Chuva de Meteoros* (círculos vermelhos no chão, o impacto fere jogadores e monstros), *Lua de Sangue* (monstros mais
  rápidos e fortes, gemas em dobro), *Febre do Ouro* (Goblins Dourados fogem pela arena e somem em 22 s; abatidos,
  soltam muito ouro), *Enxame* (o dobro de monstros, mais frágeis), *Campeões* (Campeões Goblin de elite) e
  *Emboscada* (a horda nasce em círculo em volta do grupo).
- **Caçada**: algumas rodadas têm a meta de abater N inimigos; quem bate a meta ganha um baú (gemas, ouro, coração).
- Monstros novos: **Slime Explosivo** (explode ao chegar perto — saia do círculo), **Slime Mãe** (se divide em 3),
  **Goblin Arqueiro** (mantém distância e atira flechas), **Goblin Xamã** (cura os monstros em volta),
  **Goblin Dourado** e **Campeão Goblin** (elite com golpe em área).

### Chat
- No multiplayer, **[Enter]** abre a caixa de mensagem, **[Enter]** envia e **[Esc]** cancela. Funciona também com
  as cartas da Horda abertas. As mensagens vão para todos os jogadores online (o servidor registra no log como
  `[chat] nome: texto`) e somem da tela depois de alguns segundos. Limite de 120 caracteres e de 5 mensagens a cada 6 s.

## Estrutura
```
assets/models/        GLBs low-poly gerados pelo Blender
tools/blender/        build_assets.py (cenário + chama characters.py), characters.py (personagens detalhados),
                      preview_assets.py / preview_characters.py / preview_closeup.py (renders de conferência)
data/balance/         tabelas de balanceamento em JSON (itens, culturas, receitas, magias, missões, loja, raridade,
                      inimigos, horda, eventos, cidade, regras), carregadas pelo autoload Balance
scripts/autoload/     game.gd (espelho do personagem para a UI e o jogo), econ.gd (pedidos ao dono do personagem:
                      servidor online, arquivo solo offline), balance.gd, auth.gd (cadastro/login HTTP), item_db.gd
                      (itens/magias/missões), sfx.gd (sons sintetizados), network.gd (multiplayer: servidor dedicado,
                      zonas, réplicas, RPCs), updater.gd (auto update), lobby.gd (navegação praça/Valdoria/cidade
                      e Defesa em grupo), hub.gd (praça: base compartilhada, recordes, portal da Horda)
scripts/character/    char_state.gd / char_rules.gd (regras puras do personagem), character_service.gd (carrega,
                      grava e aplica os pedidos), char_store.gd / file_char_store.gd (onde o personagem
                      fica: CharStore; FileCharStore = JSON do solo), loot_rules.gd
scripts/server/       db.gd + migrations.gd + sqlite_char_store.gd (SQLite, só no servidor), auth/ (contas, senha), http/ (API HTTP: /health, /auth/*),
                      pickups.gd (loot no chão conferido pelo servidor), hit_guard.gd
scripts/balance/      balance_tables.gd (lê/grava as tabelas JSON)
scripts/player/       player.gd (controle, combate, magias), fireball.gd, cape_rig.gd (física da capa)
scripts/enemies/      enemy.gd (slimes, goblins, rei goblin e os monstros da horda — IA e animação procedural), enemy_arrow.gd
scripts/hub/          hub_world.gd (a praça: cenário, jogador sem combate, painéis), hub_point.gd (os 9 pontos da praça)
scripts/world/        world.gd (monta o mapa e gerencia UI modal), npc.gd, pickup.gd, challenge_portal.gd
scripts/farm/         farm_plot.gd (canteiro: plantar/regar/adubar/colher), kitchen.gd (caldeirão)
scripts/survival/     survival_mode.gd (rodadas, spawn, XP, nível do grupo), horde_events.gd (eventos e Caçada),
                      auto_weapons.gd, xp_gem.gd, upgrades.gd
scripts/colony/       Defesa da Cidade: colony_world.gd (cena, luz dia/noite, entrada, save), colony.gd (economia,
                      ciclo, ondas, regras de construção), colony_data.gd (tabelas de balanceamento), building.gd,
                      building_visuals.gd, tower_shot.gd, soldier.gd, animal.gd, build_mode.gd
scripts/ui/           hub_hud.gd (HUD da praça), war_table_ui.gd (Defesa: sala/solo), horde_portal_ui.gd (fila da horda),
                      passive_master_ui.gd (passivas), base_building_ui.gd (doações), records_ui.gd (recordes), chat_ui.gd (chat), survival_hud.gd / skill_icon.gd (HUD da horda), horde_invite_ui.gd (convite/fila da horda em grupo), plant_ui.gd (plantio), cooking_ui.gd (receitas), hud, diálogo, inventário/personagem/missões, loja, pausa/morte, opções, menu principal
tests/smoke_test.gd   teste automatizado do gameplay
tests/colony_test.gd  teste automatizado da Defesa da Cidade
tests/hub_test.gd     teste automatizado da praça (solo)
tests/net_test.gd     teste do multiplayer (cliente headless contra um servidor: praça, Valdoria, --horde e --city em grupo)
tests/unit/           testes unitários das regras puras (run.gd acha e roda os test_*.gd)
Dockerfile            imagem do servidor dedicado
```
O mapa, a UI e as animações são montados por código; para mudar dados de itens, missões,
inimigos, cidade e horda edite `data/balance/*.json` (cores como `{"$c": [r, g, b, a]}`) e suba a versão.

## Regerar os modelos
```
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python tools/blender/build_assets.py
```
Para gerar só alguns modelos: defina `ASSETS=knight,elder` no ambiente antes do comando.
(Rodar via CLI em segundo plano: exportar de uma cena que não é a ativa faz o Blender 5.2 travar.)

## Teste automatizado
Testes unitários (regras puras: contas, senha, banco, HTTP, personagem, loot, balanceamento; poucos segundos):
```
C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tests/unit/run.gd
```
Sai com 1 se alguma verificação falhar **ou** se um teste tiver erro de script (acesso a nulo etc.). Depois de
criar um `class_name` novo rode `--import` uma vez. Erros esperados (`push_error` de entrada malformada, SQL
recusado) aparecem no log mas não contam como falha.

Gameplay:
```
C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://scenes/world.tscn -- --smoketest
```
Cobre diálogo/missões, combate, loot, magias, loja, equipamento, save/load, chefe, IA, morte, a Horta
(plantar, regar, adubar, colher, liberar canteiro, cozinhar, comer, save) e o Desafio da Horda (inclusive comer na rodada).
Para ver a horta cheia: `... -- --farmdemo --at=1,24.5,0` (acrescente `--ui=cook` ou `--ui=plant` para abrir os menus).
Para começar direto na arena: `... res://scenes/world.tscn -- --survival`.
Para ver a HUD da horda com uma build pronta: `... -- --survival --hordedemo[=cards|grupo|espera] --shot=horda.png --delay=7`.
Para ver as telas novas: `... -- --geardemo --weapon=storm_bow --ui=inv --shot=inv.png --delay=3`
(`--ui=inv|char|quests|shop`; `--geardemo` dá vários equipamentos, `--weapon=<id>` equipa uma arma).
Para tirar um screenshot da arena: `... -- --survival --shot=shot.png --delay=15` (o PNG vai para a pasta atual;
evite a raiz `C:/`, que o Windows não deixa gravar sem administrador).
Usa um personagem solo separado (`user://smoketest_solo.json`, apagado no início; ou `--solo-save=CAMINHO`), então não mexe no seu personagem.

Defesa da Cidade (construção, economia, recrutamento, torres, cerco, caça, noite, save/load e derrota):
```
C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://scenes/colony.tscn -- --colonytest
```
Cidade de exemplo para screenshots: `... res://scenes/colony.tscn -- --colonydemo --shot=cidade.png --delay=5`
(`--night` começa o ataque; `--ui=build|hall|barracks|hunt` abre o modo construção, a Prefeitura, o Quartel ou vai caçar).

Praça (solo: os 9 pontos, Ecos do fim de partida, passiva e doação, placa da Forja, cada painel abre e fecha,
emotes, réplica ignorando emote desconhecido e o caminho portal → Horda → de volta à praça):
```
C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://scenes/hub.tscn -- --hubtest
```
Usa um save solo próprio (`user://hubtest_solo.json` e os arquivos da base e das partidas ao lado, apagados no início).

Multiplayer (servidor + 2 clientes headless; cada cliente sai com código 0 se tudo passar):
```
G=C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe
rm -f "$TEMP/nettest.db"
$G --headless --path . -- --server --port=7790 --http-port=8790 --db="$TEMP/nettest.db" --test --horde-round=8 --horde-pick=5 &
$G --headless --path . -- --nettest=127.0.0.1:7790 --auth-url=http://127.0.0.1:8790 --peers=2 --name=Ana --horde=lead --horde-pick=5 &
$G --headless --path . -- --nettest=127.0.0.1:7790 --auth-url=http://127.0.0.1:8790 --peers=2 --name=Beto --horde=join --horde-pick=5 --relogin
```
Os clientes entram com conta: `--name` é o usuário (senha fixa `teste-1234`); o teste cadastra a conta (se já existe,
segue), faz login pela API HTTP do servidor (`--auth-url`) e entra no ENet com o token. `--relogin` confere, no fim, que
uma segunda conexão com o mesmo token derruba a primeira (abre outro processo do Godot) e que um token inválido é recusado.
Todos os modos começam na praça: cada um vê o outro com o nome em cima e o emote dele, recebe Ecos de teste
(`--test`), compra a passiva Poder e doa 60 Ecos à Forja (com `--peers=2` ela sobe para o nível 1 e o aviso chega pelo chat).
`--horde=lead|join` testa o Desafio da Horda em grupo (Ana abre a fila em Valdoria, Beto volta à praça e entra pelo
portal de lá; os dois conferem os Ecos da partida e Beto termina de volta na praça; nível do grupo com
a horda congelada até os dois escolherem, Beto "AFK" recebe carta sorteada; Beto cai e volta, os dois escolhem bênçãos
e se retiram); sem ele o teste pula essa parte. Com `--peers=2` também testa o chat (entrega e anti-spam).
`--probe` confere, sem conta, a versão por `GET /health` (HTTP) e se uma conexão ENet chega a conectar na porta do jogo (UDP); serve para testar o servidor público.
Cobre conexão, inimigos replicados (snapshots a 20/s), ver o outro jogador, dano pelo servidor, morte, XP, loot
e a horda em grupo.
`--test` no servidor aceita o pedido de ouro de teste do `net_test` (Ana: compra, compra dupla, op forjada e
reconexão); sem ele o pedido é recusado. XP, abate, loot (pickups com `net_id`, coleta conferida pelo servidor),
sementes/XP da horda e prêmios da cidade vêm do servidor; o teste falha se o cliente tentar conceder a si mesmo.
`--netstats` no servidor imprime jogadores, fps e snapshots/s a cada 5 s.
