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
| Inventário · Personagem · Missões | I (ou Tab) · C · J |
| Salvar / carregar rápido | F5 / F9 |
| Pausa | Esc |
| Esconder ajuda | H |

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
  recarga radial; Dark Souls para a barra do chefe): globos de vida/mana com rastro de dano, barra de ações
  com ícones, mira que mostra a tensão do arco, avisos de saque, inventário com prévia 3D, arrastar e soltar,
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
- Hordas de slimes e goblins surgem sem parar, cada rodada (45 s) mais fortes e numerosas; a cada 5 rodadas vem o **Rei Goblin**.
- Armas automáticas atacam sozinhas (**Orbe de Fogo**, **Lâminas Orbitais**, **Relâmpago**, **Aura Gélida**); espada, esquiva, magias e poções continuam valendo.
- Inimigos soltam **gemas de XP**: ao subir o nível da partida você escolhe 1 de 3 cartas (arma nova, melhoria ou passiva) — teclas 1/2/3 ou clique.
- Ao fim de cada rodada a arena é limpa, você recupera 30% da vida e escolhe uma **bênção**, ou se retira com as recompensas.
- Ao sair (retirada, morte ou "Abandonar desafio" na pausa) você volta à vila sem perder ouro e ganha XP do RPG (abates×2 + rodadas×25). O recorde fica salvo.
- Os bônus da partida são temporários; não é possível salvar durante o desafio.

Para editar as melhorias veja `scripts/survival/upgrades.gd`; o ritmo das rodadas fica em `scripts/survival/survival_mode.gd`.

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
  Ao mandar um build novo para os amigos, aumente a versão e atualize o servidor junto.
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
- Para testes, o servidor aceita `--horde-round=SEG` (duração da rodada).

## Estrutura
```
assets/models/        GLBs low-poly gerados pelo Blender
tools/blender/        build_assets.py (cenário + chama characters.py), characters.py (personagens detalhados),
                      preview_assets.py / preview_characters.py / preview_closeup.py (renders de conferência)
scripts/autoload/     game.gd (estado, save/load), item_db.gd (itens/magias/missões), sfx.gd (sons sintetizados),
                      network.gd (multiplayer: servidor dedicado, réplicas, RPCs)
scripts/player/       player.gd (controle, combate, magias), fireball.gd
scripts/enemies/      enemy.gd (slime, goblin, rei goblin — IA e animação procedural)
scripts/world/        world.gd (monta o mapa e gerencia UI modal), npc.gd, pickup.gd, challenge_portal.gd
scripts/farm/         farm_plot.gd (canteiro: plantar/regar/adubar/colher), kitchen.gd (caldeirão)
scripts/survival/     survival_mode.gd (rodadas, spawn, XP), auto_weapons.gd, xp_gem.gd, upgrades.gd
scripts/ui/           horde_invite_ui.gd (convite/fila da horda em grupo), plant_ui.gd (plantio), cooking_ui.gd (receitas), hud, diálogo, inventário/personagem/missões, loja, pausa/morte, opções, menu principal
tests/smoke_test.gd   teste automatizado do gameplay
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
