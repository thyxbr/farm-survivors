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
| Inventário · Personagem · Missões | I (ou Tab fora da Horda) · C · J |
| Placar do grupo (no Desafio da Horda, segurar) | Tab |
| Salvar / carregar rápido | F5 / F9 |
| Pausa | Esc |
| Mostrar/esconder ajuda (começa escondida) | H |

## Conteúdo
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
  crítico, velocidade, recarga, roubo de vida). Elmo, peitoral, manoplas, botas, escudo, orbe, aljava e chapéu
  do mago aparecem no cavaleiro. Equipamentos raros ou melhores caem com um feixe de luz na cor da raridade.
- **Interface** (referências: Diablo/Path of Exile para boneco, grade e raridade; World of Warcraft para
  recarga radial; Dark Souls para a barra do chefe): HUD enxuto nas bordas da tela — globos de vida/mana compactos
  com rastro de dano, barra de ações com ícones, vigor que só aparece quando gasto, ajuda escondida no H,
  mira que mostra a tensão do arco, avisos de saque, inventário com prévia 3D, arrastar e soltar,
  filtros, "Organizar" e dica que calcula o que muda se equipar o item. Ícones desenhados por código
  (`icon_painter.gd`); tema em `ui_theme.gd`.
- **Save/Load** em JSON (`user://savegame.json`), opções persistentes (volume, sensibilidade, inverter Y, tela cheia).
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
- A horta é salva no save. Dados de culturas/receitas em `item_db.gd` (`CROPS`, `RECIPES`).

## Desafio da Horda (modo sobrevivência)
Entre no **Portal do Desafio** (perto do portão norte da vila, tecla E) para ir à **Arena** a oeste do mapa:
- Hordas de slimes e goblins surgem sem parar, cada rodada (45 s) mais fortes e numerosas; a cada 5 rodadas vem o **Rei Goblin**
  (a partir do 2º, com guardas de elite).
- **Curva de dificuldade** (`survival_mode.gd`): ritmo em dente de serra dentro de cada ciclo de 5 rodadas (a pressão sobe
  até a 4ª e alivia na rodada do chefe); a vida dos inimigos cresce um pouco mais que linear, então a partida tende a
  terminar entre as rodadas 15 e 20. Da rodada 3 em diante surgem **elites** (douradas, 3x a vida, soltam mais gemas e
  às vezes cura) e um **cerco** por rodada (anel de slimes fechando em volta de alguém). Da rodada 7 vem o **Goblin Bruto**.
  Da rodada 6, cada rodada sem chefe traz uma **maldição** (Frenesi, Couraça, Enxame, Fúria ou Caçada) mostrada no topo.
- HUD da horda: rodada, tempo, nível e XP num bloco só no topo; a build fica em ícones no canto (número = nível).
  **Segure Tab** para o placar: build, dano, abates, quedas e combos de cada jogador (funciona por cima das cartas).
- Armas automáticas atacam sozinhas (**Orbe de Fogo**, **Lâminas Orbitais**, **Relâmpago**, **Aura Gélida**); espada, esquiva, magias e poções continuam valendo.
- Inimigos soltam **gemas de XP**: ao subir o nível da partida você escolhe 1 de 3 cartas (arma nova, melhoria ou passiva) — teclas 1/2/3 ou clique.
- Ao fim de cada rodada a arena é limpa, você recupera 30% da vida e escolhe uma **bênção**, ou se retira com as recompensas.
- Ao sair (retirada, morte ou "Abandonar desafio" na pausa) você volta à vila sem perder ouro e ganha XP do RPG (abates×2 + rodadas×25). O recorde fica salvo.
- Os bônus da partida são temporários; não é possível salvar durante o desafio.

Para editar as melhorias veja `scripts/survival/upgrades.gd`; o ritmo das rodadas fica em `scripts/survival/survival_mode.gd`.

## Defesa da Cidade (tower defense)
Menu principal → **Defesa da Cidade — nova**. Começa num mapa vazio (uma clareira cercada de bosques) e o
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

- **Construções** (`scripts/colony/colony_data.gd`): Prefeitura (primeira, grátis, na clareira central), Casa (+5 moradores),
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
  (F5 também salva, só de dia); o personagem deste modo tem save próprio, separado do RPG.
- Só para um jogador.

## Multiplayer (servidor dedicado)
O servidor roda o Godot sem tela e é dono dos inimigos (IA, vida, morte). Cada jogador é dono
do próprio personagem: atributos, inventário, missões e a Horta ficam no save do PC dele
(salvo automaticamente ao sair). Quem acerta um inimigo ganha XP, missão e loot próprios quando ele morre.

- **Servidor local:** `godot --headless --path . -- --server --port=7777`
- **Docker / Easypanel:** App com build pelo `Dockerfile`; em *Advanced → Ports* publique `7777 → 7777` em **UDP**
  (o jogo não passa pelo domínio/proxy HTTP). Libere UDP 7777 no firewall da VPS. A porta pode ser trocada pela env `GAME_PORT`.
- **Deploy automático:** cada push no `main` roda o GitHub Actions (`.github/workflows/deploy.yml`):
  importa o projeto, roda o smoke test e o teste de multiplayer e, se tudo passar, chama o webhook de deploy
  do Easypanel (secret `EASYPANEL_DEPLOY_URL`). Deixe o *Auto Deploy* do próprio Easypanel desligado,
  senão ele publica mesmo quando os testes falham. Depois do deploy, o job *Conferir servidor publicado*
  entra no servidor público com `--nettest=... --probe` até ele aceitar a versão do commit (falha após ~15 min).
  Ele só distingue servidor velho de novo se a versão mudou: aumente a versão quando mexer no código.
- **Desligue o *Zero Downtime* do app no Easypanel.** A porta UDP é publicada em modo host: com ele ligado o
  container novo fica em *Pending* ("host-mode port already in use") e o antigo continua no ar sem atualizar.
  Para destravar na VPS: `docker service scale <serviço>=0` e depois `=1`.
- **Firewall da VPS (Hostinger):** o firewall do painel recusa tudo por padrão; adicione *Aceitar · UDP · 7777*
  (e TCP 22/80/443/3000 para SSH e o painel) antes do *Drop*.
- **Jogadores:** menu principal → *Multiplayer* → nome + endereço (`ip` ou `ip:porta`) → *Entrar*.
  Antes de exportar, coloque o IP/domínio do servidor em `DEFAULT_ADDRESS` (`scripts/autoload/network.gd`).
- **Versão:** o servidor recusa clientes com `application/config/version` diferente (*Projeto → Configurações → Application → Config*).
  Para lançar uma versão nova basta aumentar a versão e dar push no `main`: o CI publica o cliente e atualiza o servidor.
  **Mudou o jogo, suba a versão:** se a versão já tem release e algo fora de docs/testes/CI mudou desde a tag,
  o CI falha antes do deploy. Sem isso o servidor receberia o código novo e os jogadores ficariam com o antigo
  na mesma versão (o servidor aceitaria a conexão e as RPCs sairiam dessincronizadas).
- **Auto update (cliente Windows):** quando a versão do `project.godot` ainda não tem release, o job
  *Publicar cliente* do CI exporta o jogo e cria a release `v<versão>` no GitHub com o zip e um `latest.json`
  (versão, link, SHA-256). O deploy do servidor só roda depois disso. No jogo, o autoload `Updater`
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

### Desafio da Horda em grupo
- Quem entra no **Portal do Desafio** abre uma fila de 15 s e **todos os jogadores online recebem o convite**
  (painel no canto: **[Y]** entrar · **[N]** recusar, ou clique). Quando todos respondem a contagem cai para 3 s.
  Quem aceitou vai junto para a **mesma arena**; quem estava caído na hora fica de fora.
- Há uma partida por vez no servidor: se alguém tentar entrar com uma em andamento, recebe o aviso para aguardar.
- O **servidor** é dono das rodadas, do spawn e dos abates; a horda só persegue quem está no desafio e fica
  mais numerosa e resistente conforme o tamanho do grupo.
- Cada **jogador** tem as próprias gemas de XP, nível da partida, cartas, bênçãos, ouro e sementes
  (todo abate do grupo solta gemas para cada um). Orbes de fogo, relâmpagos, lâminas e aura dos colegas aparecem na tela.
- **Cair não encerra**: o jogador volta (com metade da vida) no fim da rodada se alguém do grupo sobreviver.
  Se todos caírem, a partida acaba para o grupo.
- No fim da rodada cada um escolhe a bênção; a próxima rodada começa quando todos escolherem (ou após 30 s).
  Retirar-se ou abandonar tira só você; os outros continuam.
- **Combos em grupo**: quando você tem uma arma automática e um colega tem a arma par, os acertos disparam o combo
  enquanto vocês estão a até 14 m (recarga de 3 s, dano cresce com o nível das duas armas). Pares: Fogo + Aura
  (Choque Térmico), Fogo + Relâmpago (Plasma), Fogo + Lâminas (Ciclone de Brasas), Relâmpago + Aura (Tempestade Gélida),
  Relâmpago + Lâminas (Lâminas Elétricas), Lâminas + Aura (Nevasca Cortante). As cartas avisam quando uma arma nova
  formaria combo com alguém do grupo (e essas armas aparecem mais). O quadro do grupo, à esquerda, mostra a vida e o
  nível de cada colega e ◆ em quem está combando com você. Tabela em `upgrades.gd` (`COMBOS`, `AFFIXES`).
- O servidor conta dano, abates e quedas de cada jogador; cada cliente manda a própria build a cada segundo.
- Para testes, o servidor aceita `--horde-round=SEG` (duração da rodada). Screenshot do HUD com uma build de exemplo:
  `godot --path . res://scenes/world.tscn -- --survival --hordedemo [--tab] --shot=shot.png`.

## Estrutura
```
assets/models/        GLBs low-poly gerados pelo Blender
tools/blender/        build_assets.py (cenário + chama characters.py), characters.py (personagens detalhados),
                      preview_assets.py / preview_characters.py / preview_closeup.py (renders de conferência)
scripts/autoload/     game.gd (estado, save/load), item_db.gd (itens/magias/missões), sfx.gd (sons sintetizados),
                      network.gd (multiplayer: servidor dedicado, réplicas, RPCs), updater.gd (auto update)
scripts/player/       player.gd (controle, combate, magias), fireball.gd
scripts/enemies/      enemy.gd (slime, goblin, rei goblin — IA e animação procedural)
scripts/world/        world.gd (monta o mapa e gerencia UI modal), npc.gd, pickup.gd, challenge_portal.gd
scripts/farm/         farm_plot.gd (canteiro: plantar/regar/adubar/colher), kitchen.gd (caldeirão)
scripts/survival/     survival_mode.gd (rodadas, spawn, XP), auto_weapons.gd, xp_gem.gd, upgrades.gd
scripts/colony/       Defesa da Cidade: colony_world.gd (cena, luz dia/noite, entrada, save), colony.gd (economia,
                      ciclo, ondas, regras de construção), colony_data.gd (tabelas de balanceamento), building.gd,
                      building_visuals.gd, tower_shot.gd, soldier.gd, animal.gd, build_mode.gd
scripts/ui/           horde_invite_ui.gd (convite/fila da horda em grupo), plant_ui.gd (plantio), cooking_ui.gd (receitas), hud, diálogo, inventário/personagem/missões, loja, pausa/morte, opções, menu principal
tests/smoke_test.gd   teste automatizado do gameplay
tests/colony_test.gd  teste automatizado da Defesa da Cidade
tests/net_test.gd     teste do multiplayer (cliente headless contra um servidor)
Dockerfile            imagem do servidor dedicado
```
O mapa, a UI e as animações são montados por código; para mudar dados de itens, missões e
inimigos edite `item_db.gd` e a tabela `TYPES` em `enemy.gd`.

## Regerar os modelos
```
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python tools/blender/build_assets.py
```
Para gerar só alguns modelos: defina `ASSETS=knight,elder` no ambiente antes do comando.
(Rodar via CLI em segundo plano: exportar de uma cena que não é a ativa faz o Blender 5.2 travar.)

## Teste automatizado
```
C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://scenes/world.tscn -- --smoketest
```
Cobre diálogo/missões, combate, loot, magias, loja, equipamento, save/load, chefe, IA, morte, a Horta
(plantar, regar, adubar, colher, liberar canteiro, cozinhar, comer, save) e o Desafio da Horda (inclusive comer na rodada).
Para ver a horta cheia: `... -- --farmdemo --at=1,24.5,0` (acrescente `--ui=cook` ou `--ui=plant` para abrir os menus).
Para começar direto na arena: `... res://scenes/world.tscn -- --survival`.
Para ver as telas novas: `... -- --geardemo --weapon=storm_bow --ui=inv --shot=inv.png --delay=3`
(`--ui=inv|char|quests|shop`; `--geardemo` dá vários equipamentos, `--weapon=<id>` equipa uma arma).
Para tirar um screenshot da arena: `... -- --survival --shot=shot.png --delay=15` (o PNG vai para a pasta atual;
evite a raiz `C:/`, que o Windows não deixa gravar sem administrador).
Usa um arquivo de save separado, então não mexe no seu save.

Defesa da Cidade (construção, economia, recrutamento, torres, cerco, caça, noite, save/load e derrota):
```
C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://scenes/colony.tscn -- --colonytest
```
Cidade de exemplo para screenshots: `... res://scenes/colony.tscn -- --colonydemo --shot=cidade.png --delay=5`
(`--night` começa o ataque; `--ui=build|hall|barracks|hunt` abre o modo construção, a Prefeitura, o Quartel ou vai caçar).

Multiplayer (servidor + 2 clientes headless; cada cliente sai com código 0 se tudo passar):
```
G=C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe
$G --headless --path . -- --server --port=7790 --horde-round=8 &
$G --headless --path . -- --nettest=127.0.0.1:7790 --peers=2 --name=Ana --horde=lead &
$G --headless --path . -- --nettest=127.0.0.1:7790 --peers=2 --name=Beto --horde=join
```
`--horde=lead|join` testa o Desafio da Horda em grupo (Ana abre o portal, Beto aceita o convite, cai e volta,
os dois escolhem bênçãos e se retiram); sem ele o teste pula essa parte.
`--probe` só entra, confere a versão e os snapshots e sai (não mexe no mundo); serve para testar o servidor público.
Cobre conexão, inimigos replicados (snapshots a 20/s), ver o outro jogador, dano pelo servidor, morte, XP, loot
e a horda em grupo.
`--netstats` no servidor imprime jogadores, fps e snapshots/s a cada 5 s.
