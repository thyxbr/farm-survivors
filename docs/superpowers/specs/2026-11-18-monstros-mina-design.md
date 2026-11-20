# Monstros da Mina de Cristal — design

Data: 2026-11-18 · Branch: `monstros-mina` (worktree `../godot-3d-monstros-mina`)

## Intenção

Cada mapa deve ter monstros próprios (pelo menos 4 comuns + 1 boss). Hoje a Mina (níveis 20–30) é quase só
esqueletos e Goblins Brutos, repetindo o Pico. A Mina é o primeiro mapa a ganhar um bestiário próprio, com o tema
"mineração viva": bichos que cavam, cristais que andam e mineiros pequenos com dinamite.

Os esqueletos **ficam** numa parte da Mina, porque a linha de história do Bolgar depende deles (quests `mina`,
`galerias` "Esqueletos de Crachá", `diario` em `data/balance/quests.json`). A leitura do mapa passa a ser
"mineração viva vs. mortos-vivos invasores".

## Objetivos

- 4 monstros comuns novos e 1 boss novo, todos com nome, números e loot em `data/balance/enemies.json`.
- Mecânica nova de **cavar e emergir** (Toupeira e Mãe-Verme).
- Redistribuir os spawns de `scenes/maps/mina.tscn` por região (tabela abaixo).
- Cada modelo novo ou alterado é validado pelo usuário, **um por rodada**, antes de seguir para o próximo.

## Não-objetivos

- Não mexer no dungeon da Mina (`dg_mina.tscn`, Rei Goblin) nem nos outros mapas.
- Não reescrever quests ou diálogos.
- Não criar itens novos: o loot usa itens que já existem.
- Não colocar os monstros novos na Horda (`survival_mode.gd`) nesta entrega.

## Anti-objetivos (falharia mesmo funcionando)

- Modelos com peças soltas/flutuando (o `LOOSE <asset>` do build tem de sair vazio).
- Quebrar a quest "Esqueletos de Crachá": precisa continuar dando para matar 8 esqueletos perto de `where`
  (z ≈ −25) num nível próximo de 25.
- Monstro que some/emerge diferente no cliente e no servidor (multiplayer).

## Restrições

- Modelos são feitos em código em `tools/blender/monsters.py`, exportados para `assets/models/*.glb` pelo Blender
  CLI (não pelo MCP), no estilo toon liso das feras (sloft, `tools/blender/STYLE.md`).
- A animação de cada rig fica em `scripts/enemies/enemy.gd` (por pivôs com nome); comportamento por `"ai"` e chaves
  do JSON.
- PR que muda código do jogo sobe `config/version` em `project.godot`.
- Testes do CI (`smoke-check`) passam antes do PR; `tests/unit/fixtures/balance_snapshot.bin` pode precisar ser
  regenerado por causa das entradas novas.

## Abordagens consideradas

1. **Todos os modelos novos (5):** mapa mais único, cerca do dobro de rodadas de modelagem.
2. **Misto — escolhida pelo usuário:** 3 modelos novos (Golem, Toupeira, Mãe-Verme); o Kobold reaproveita o rig do
   goblin (equipamento novo) e a Centopeia ganha malha nova com os **mesmos pivôs da aranha**, reaproveitando a
   animação da tecelã.
3. **Só recolorir rigs existentes:** barato, mas não entrega "monstros específicos do mapa". Descartada.

Sobre os esqueletos, o usuário escolheu **dividir a Mina** (A) em vez de reescrever a quest (B).

## Os monstros

Números finais (vida, dano, xp, ouro) ficam com o construtor, calibrados para a faixa 20–30 pelo mesmo critério
dos existentes (`ref_level` + regras de progressão) e conferidos com a skill `balance-check`.

### 1. Kobold Lanterneiro (`kobold`) — rig do goblin
- Mineiro baixinho com capacete de lanterna (vela/lampião no capacete), picareta pequena e cinto de dinamite.
- Peças novas como `Opt_` no `build_goblin()`: `MinerHelmet`, `Pickaxe`, `DynamiteBelt`. Cor própria (tint).
- Anda em bando (3–4). Ataque corpo a corpo com a picareta; a cada poucos ataques **arremessa uma dinamite no
  ponto onde o jogador está** (decisão do usuário):
  - Ataque novo (`attack_kind` "throw"): a dinamite voa em arco até o ponto marcado, com o aviso no chão
    (`FX.telegraph`) naquele ponto durante o voo, e explode em área ao cair. O Kobold **não** morre.
  - O ponto do alvo é escolhido no servidor e vai pela rede (snapshot ou RPC do ataque) para que o aviso e a
    explosão apareçam no mesmo lugar para todos.
  - Não reaproveita o `ai: "bomber"` (que é suicida e substitui o corpo a corpo); reaproveita só o raio `blast`
    e o visual da explosão.
- Variante opcional a critério do construtor: nenhuma nesta entrega.

### 2. Centopeia de Túnel (`centopeia`) — pivôs da aranha
- Corpo longo e segmentado, rente ao chão, muitas patinhas; antenas e mandíbulas. Malha nova
  (`build_centipede()`), mas com os pivôs da tecelã (`Body`, `Abdomen`, `Head`, `Leg0L..Leg3R`) para reaproveitar
  a animação; as patas extras de cada segmento ficam presas ao pivô de perna mais próximo.
- Rápida, pouca vida, persegue. A mordida aplica **veneno paralisante = a lentidão que já existe**
  (`apply_chill` do jogador), com cor verde no efeito se for barato. *Chamada minha: não criar um efeito de dano
  contínuo novo no jogador, porque isso exigiria estado novo na rede.*

### 3. Golem de Cristal (`golem_cristal`) — modelo novo
- Corpo de rocha escura com aglomerados de cristal saindo dos ombros e das costas; braços enormes, pernas curtas,
  "rosto" de cristal brilhante. Pivôs no padrão humanoide (`LegL`, `LegR`, `Body`, `Head`, `ArmL`, `ArmR`) para
  reaproveitar a animação de marcha/ataque dos humanoides o máximo possível.
- Lento, muita vida, golpe pesado com `slam_every` (pancada em área com aviso).
- **Ao morrer, estoura em estilhaços:** aviso no chão (`FX.telegraph`) e dano em área curto depois — a mesma
  lógica do `blast`, disparada na morte.

### 4. Toupeira-Broca (`toupeira`) — modelo novo
- Toupeira grande com garras de pá e um focinho em forma de broca de metal enferrujado; óculos de mineiro.
- **Mecânica nova "cavar e emergir"** (`ai: "burrow"`):
  1. Ao ver o jogador a média distância, afunda no chão (vira um monte de terra que anda; não pode ser alvo nem
     tomar dano).
  2. Vai por baixo da terra até o jogador.
  3. Marca um círculo de aviso no chão onde ele está e, após ~1 s, sai de baixo com dano em área.
  4. Fica na superfície alguns segundos vulnerável (é a janela para bater), lutando corpo a corpo, e repete.
- O estado "debaixo da terra" passa pelo snapshot de rede (`apply_snapshot`: estado/flags) para o cliente esconder
  o modelo e mostrar o rastro de terra igual ao servidor.

### 5. Boss: Mãe-Verme das Profundezas (`mae_verme`) — modelo novo
- Verme gigante segmentado de couraça de pedra com cristais incrustados; boca circular com anéis de dentes que
  abre em pétalas. Só a parte da frente sai do chão (o resto "continua" na terra).
- `boss: true`, aura de chefe, respawn longo (como o Lich do Pico: ~300 s), nasce sozinho no fosso, sem missão.
- Comportamento (reaproveita o "cavar e emergir" da Toupeira):
  - Emerge sob o jogador com aviso no chão (dano em área) ou num ponto do fosso.
  - Na superfície: mordida em área à frente e **cuspe de ácido** (projétil, `shot` com cor verde).
  - Depois de alguns ataques, afunda e emerge em outro lugar.
  - Abaixo de 50% de vida chama 2 Centopeias (`summon: "centopeia"`, como o Lich chama esqueletos).
  - *Chamada minha:* ela **fica presa ao fosso oeste** (40×30 m). Só emerge dentro dele; se todos os jogadores
    saírem, ela afunda e volta à vida cheia, como um reset de chefe. Debaixo da terra não pode ser atingida, mas
    cada mergulho dura pouco (~2–3 s) e a barra de vida do chefe continua na tela.
- Loot: itens e pergaminhos existentes da faixa 25–30 (o construtor escolhe, conferindo com `balance-check`).

## Onde cada um aparece (`scenes/maps/mina.tscn`)

O mapa vai da entrada (z ≈ +56, carruagem) até o fundo (z ≈ −52, diário). Regiões atuais: Galeria de Entrada
(z 20, nv 20–23), Veio de Cristal (z −10, nv 23–26), Fosso (x ±45, z −40, nv 25–28), Salão do Cavaleiro
(z −45, nv 28–30).

| Região | Fica | Sai |
|---|---|---|
| Galeria de Entrada | Kobolds (bandos), Centopeias | bandos de esqueleto e de Goblin Bruto |
| Veio de Cristal (parte sul, z −0 a −18) | Golens, alguns Kobolds | esqueletos |
| Corredor norte (z −20 a −35) — "as galerias" da quest | esqueletos guerreiro/arqueiro/mago (como hoje) | — |
| Fosso leste | Toupeiras | Goblins Brutos |
| Fosso oeste | Mãe-Verme + 2 Toupeiras | Goblins Brutos |
| Salão do Cavaleiro | Cavaleiro Esqueleto + esqueletos (como hoje) | — |

- Os Goblins Brutos saem da Mina, **exceto um bando** perto do marcador do contrato "Brutamontes" (`q_brutos`,
  `where` [830, 0] = x ≈ +30, z ≈ 0 no mapa), na borda leste do Veio. *Chamada minha:* assim o contrato continua
  certo sem mexer em `quests.json`. Fora isso, continuam no Vale, no dungeon e na Horda.
- A quest "Esqueletos de Crachá" conta abate em qualquer lugar (`where` é só o marcador do mapa), então basta
  manter esqueletos suficientes no corredor norte.
- *Chamada minha:* a região `fosso_brutos` muda só o nome exibido para **"Fosso da Mãe-Verme"** em
  `regions.json` (o id fica igual para não quebrar nada).
- A quantidade de esqueletos no corredor norte tem de bastar para a quest de 8 abates sem espera longa.

## Ordem de entrega (uma rodada de validação por peça)

1. Kobold (equipamento novo no goblin) → screenshot comparando com o goblin.
2. Centopeia → screenshot parada e andando.
3. Golem de Cristal → screenshot + estouro na morte.
4. Toupeira + mecânica de cavar (testar solo e multiplayer).
5. Mãe-Verme.
6. Spawns no `mina.tscn`, nome da região, `balance-check`, `smoke-check`, versão, PR.

Cada rodada: build pelo Blender CLI, conferir `LOOSE` vazio, captura dentro do jogo (não só no preview do
Blender), e o usuário aprova antes da próxima.

## Fica com o construtor

- Números de balanceamento e tabela de loot (dentro da faixa e conferidos com `balance-check`).
- Paleta exata de cada monstro (dentro do estilo toon do projeto).
- Tempos exatos (aviso, janela vulnerável, cooldown do cavar), contanto que o aviso seja legível (~1 s).
- Como encaixar o estado "cavando" no snapshot de rede existente.
- Posição exata dos pontos de spawn dentro de cada região.
- Se a PR é uma só no fim ou uma por rodada.
