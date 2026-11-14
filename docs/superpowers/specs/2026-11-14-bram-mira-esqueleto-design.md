# Bram e Mira com esqueleto e animações do Mixamo — design

Data: 2026-11-14 · Branch: `npcs-esqueleto` (worktree `../godot-3d-ferreiro`, a partir do `main` 7048e1f, versão 0.12.1)

## Intenção

O ferreiro Doran provou o caminho "malha gerada por script + esqueleto com nomes do Mixamo + animações do
Mixamo retargetadas pelo perfil humanoide do Godot". O dono quer levar isso ao **Ancião Bram** e à **Mira, a
Mercadora**, que hoje são estátuas de peças rígidas (só a cabeça balança e o corpo vira para o jogador), dando
**personalidade** a cada um:

- **Bram:** um velho apoiado no cajado. Quando o jogador fala com ele, **fica animado** (reação curta e
  alegre) e depois conversa.
- **Mira:** uma vendedora que, parada, **chama clientes** com gestos, e conversa gesticulando.

## Objetivos

- Bram e Mira gerados pelo script (`tools/blender/characters.py`, `build_elder` / `build_merchant`), com o
  mesmo visual de hoje, agora como malha presa a um esqueleto com nomes `mixamorig:*` em pose T, importados
  com `BoneMap` + `SkeletonProfileHumanoid` como o `blacksmith.glb`.
- Animações do Mixamo baixadas pelo dono (lista abaixo), cada uma numa `AnimationLibrary` por personagem.
- **Bram**
  - Parado: `elder_idle` (velho apoiado no cajado), em loop.
  - Ao interagir: `elder_excited` toca **uma vez** (reação animada), depois `elder_talk` em loop enquanto o
    diálogo estiver aberto. Ao fechar, volta ao parado.
  - O cajado é objeto separado preso à mão esquerda (`BoneAttachment3D`, como o martelo do ferreiro).
- **Mira**
  - Parada: `merchant_idle` em loop.
  - Chamar clientes: `merchant_call` toca uma vez quando o jogador está **entre 7 e 14 m** dela (perto o
    bastante para ver, longe o bastante para não estar conversando), virada para ele, com **intervalo mínimo
    de ~8 s** entre chamadas. *(Proposta minha.)*
  - Conversa: `merchant_talk` em loop enquanto o diálogo dela estiver aberto. Na loja (tela de compra), volta
    ao parado. *(Proposta minha.)*
- Os dois continuam virando para o jogador a menos de 7 m, como hoje, e o marcador `!`/`?` do Bram continua.
- Animam durante o diálogo mesmo com o jogo pausado (solo), e ficam parados atrás de outros menus — o mesmo
  esquema do ferreiro (`PROCESS_MODE_ALWAYS` só durante a conversa).
- No servidor dedicado (headless, sem `--smoketest`): sem animação.

## Fora do escopo

- Cavaleiro, soldados, goblin (próximo passo, decidido à parte).
- O "corpo contínuo" (`tools/blender/body_mesh.py`, ossos com nomes de pivô) — não mexer.
- A pausa do ferreiro com o martelo atravessando o rosto (fica para quando o dono baixar a versão espelhada).
- Sincronizar as animações pela rede (são cosméticas e locais).

## Anti-objetivos

- Bram ou Mira mudarem de cara: o visual (roupas, rosto, cabelo, cores, cajado) tem que continuar o de hoje.
- Pernas atravessando a túnica longa do Bram ou a saia/capa da Mira de forma visível; túnica rasgando.
- O cajado balançando solto, atravessando o corpo ou saindo da mão.
- Membros torcidos ou cotovelo/punho em posição impossível (o dono já reprovou isso na martelada).
- Animações iguais às do ferreiro a ponto de os três parecerem o mesmo boneco (salvo o substituto abaixo).

## Animações a baixar (o dono baixa; podem faltar)

Mesmas opções do ferreiro: **FBX Binary, Without Skin, 30 fps, Keyframe Reduction none**, *In Place* quando
houver. Salvar em `C:\Games\godot-3d-ferreiro\assets\animations\mixamo\`.

| Arquivo | O que é | Sugestões de busca |
|---|---|---|
| `elder_idle.fbx` | velho parado, curvado, apoiado | "old man idle", "old", "tired idle" |
| `elder_excited.fbx` | reação alegre curta (1–3 s) | "excited", "cheering", "clapping", "happy" |
| `elder_talk.fbx` | conversa calma, gesto com uma mão | "talking", "old man talking" |
| `merchant_idle.fbx` | parada, postura confiante | "idle", "standing idle", "happy idle" |
| `merchant_call.fbx` | chamando com a mão / acenando | "waving", "beckoning", "come here" |
| `merchant_talk.fbx` | conversa animada com gestos | "talking", "explaining", "argue" |

Dica do cajado: o Bram segura o cajado na **mão esquerda**. Prefira clipes em que ele gesticula com a
**direita**; se o gesto vier na esquerda, marque **Mirror** no Mixamo antes de baixar.

**Se faltar algum (decisão do dono: pode faltar):**
- `elder_idle` / `elder_talk` / `merchant_idle` / `merchant_talk` faltando → usar o clipe equivalente que já
  existe na biblioteca do ferreiro (`mixamo/idle`, `mixamo/talk`).
- `elder_excited` ou `merchant_call` faltando → clipe curto feito por keyframes no script (como a martelada),
  respeitando o anti-objetivo de articulações (braço como dobradiça, sem torção).

## Restrições

- Godot 4.7.2; Blender 5.2 **só por CLI**; frente = -Y no Blender.
- Esqueleto e nomes de osso **iguais aos do ferreiro** (`BS_BONES`, prefixo `mixamorig:`), para todas as
  animações do Mixamo servirem nos três.
- Sem duplicar código: o rig (criação da armature, pesos) e o lado Godot (carregar a biblioteca, `clip()`,
  trilhas de repouso, troca de `process_mode` na conversa, desligar no headless, prender objetos a ossos) hoje
  estão dentro de `build_blacksmith` / `blacksmith.gd`. Devem virar peças reaproveitadas pelos três; o ferreiro
  tem que continuar se comportando exatamente igual (seus testes continuam passando).
- `npc.gd` também está sendo mexido por **outra sessão** (pasta `../godot-3d-toon`, estilo toon dos NPCs, sem
  commit ainda). Quem juntar por último resolve o conflito; mexer em `npc.gd` só no necessário.
- Os testes do jogo (smoke) hoje acham o ancião por `npc_id == "elder"` e abrem o diálogo dele; a loja da Mira
  abre pelo diálogo. Esses caminhos não podem quebrar.
- Versão: subir para uma acima da do `main` no momento do PR.
- FBX commitados no repositório (decisão anterior do dono), fora do export como os do ferreiro.

## Abordagens consideradas

| | Abordagem | Ganha | Custa |
|---|---|---|---|
| **A (escolhida)** | Todas do Mixamo, com substitutos se faltar | Movimento natural; personalidade de cada um | Download manual; cajado limita a mão esquerda |
| B | Todas feitas no script | Nada a baixar; controle do cajado | Muito mais trabalho; risco de ficar duro (a martelada levou 2 rodadas) |
| C | Misto (idle/talk do ferreiro + 2 do Mixamo) | Só 2 downloads | Os três NPCs ficam iguais parados e conversando |

## Decisões do dono

- Abordagem A; podem faltar animações (usar substitutos).
- Bram: velho apoiado no cajado; reação animada ao interagir.
- Mira: vendedora chamando clientes; conversa gesticulando.

## Decisões minhas (corrigíveis)

- Mira chama clientes entre 7 e 14 m, com intervalo mínimo de ~8 s; na tela da loja volta ao parado.
- A reação do Bram toca **toda vez** que o jogador abre o diálogo com ele.
- Uma `AnimationLibrary` por personagem (`elder_mixamo.res`, `merchant_mixamo.res`), com nomes curtos
  dentro dela (`idle`, `excited`, `talk`, `call`).
- O teste do asset e o smoke test ganham checagens para os dois (esqueleto, clipes, estados, conversa com o
  jogo pausado), como as do ferreiro.

### Respostas à revisão do builder (decisões minhas)

- **Reação do Bram e o diálogo:** o diálogo abre **na hora**, como hoje e como o ferreiro. `elder_excited` toca
  por cima da primeira página e, ao terminar, entra `elder_talk`. O teste que chama `elder.interact()` e
  espera `world.modal` imediatamente continua valendo.
- **Antes dos downloads:** a implementação começa já com os substitutos (clipes do ferreiro e clipes feitos no
  script), tudo funcionando e testado. Quando os FBX chegarem, entram no mesmo branch antes do PR; o que não
  vier fica no substituto. Os substitutos de idle/talk são **copiados para a biblioteca do personagem na hora
  de gerá-la** (`elder_mixamo.res` / `merchant_mixamo.res` sempre têm todos os nomes), então o jogo e os
  testes nunca dependem de um clipe faltar ou não. A ferramenta que gera as bibliotecas diz, por clipe, se usou
  o FBX ou o substituto.
- **Onde o código mora:** um script base compartilhado (ex.: `scripts/world/skinned_npc.gd`, estendendo
  `npc.gd`) com o que hoje está no `blacksmith.gd` e serve aos três; `Blacksmith`, `Elder` e `Merchant` o
  estendem. `world.gd` passa a criar Bram e Mira por essas classes, mantendo `npc_id` ("elder"/"merchant"),
  para o smoke test e a loja seguirem funcionando. `npc.gd` só muda se for inevitável.
- **"Mesmo visual":** conferido a olho, com fotos lado a lado (antes/depois) do modelo parado com os braços
  baixados, de frente, lado e 3/4. Roupas, rosto, cabelo, cores e cajado têm que bater; a curvatura do Bram
  pode vir do clipe de velho.
- **Cajado:** preso à mão esquerda por `BoneAttachment3D` com deslocamento fixo. Nas bibliotecas do Bram, as
  trilhas do braço esquerdo (ombro, braço, antebraço, mão) são **trocadas por uma pose fixa de segurar o
  cajado**, para nenhum clipe do Mixamo balançar o cajado. Se algum clipe gesticular só com a esquerda, ele
  perde o gesto — por isso a dica do Mirror.
- **Chamado da Mira:** vale só o jogador local (`get_first_node_in_group("player")`, como hoje). Durante o
  `merchant_call` ela vira para ele mesmo entre 7 e 14 m; fora disso, a regra de virar a menos de 7 m não muda.
  O smoke test põe o jogador a ~10 m dela para conferir o chamado e o intervalo.

## O que fica com o builder

- Como converter os modelos atuais (braços pendentes) para pose T sem mudar o visual.
- Pesos da túnica/saia/capa entre quadril e pernas.
- Forma exata das peças compartilhadas (módulo Python do rig, script base no Godot).
- Detalhes de transição (blends) e do clipe substituto, se precisar.
- Conferência visual com fotos e vídeo (ferramenta de fotos e cena de vídeo do ferreiro como base).
