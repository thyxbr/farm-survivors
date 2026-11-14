# Ferreiro da vila com esqueleto e animações do Mixamo — design

Data: 2026-11-14 · Branch: `ferreiro` (worktree `../godot-3d-ferreiro`)

## Intenção

Criar um NPC novo, um **ferreiro** que trabalha numa bigorna na vila e conversa com o jogador.
Ele é o **primeiro personagem com esqueleto (malha *skinned*)** do Ecos de Valdoria. O objetivo
real é testar o caminho "modelo gerado por script + esqueleto humanoide + animações do Mixamo",
que depois servirá para inimigos e criaturas. O cavaleiro e os soldados continuam com o sistema
atual de peças rígidas em pivôs (`knight_anim.gd`) e **não são tocados**.

Por enquanto o ferreiro só dá vida à vila. Um sistema de forja (melhorar/consertar/criar itens)
fica para depois.

## Objetivos

- Ferreiro no estilo low-poly dos outros NPCs, gerado por script em `tools/blender/characters.py`
  e exportado pelo `build_assets.py` (Blender CLI em background).
- Esqueleto humanoide com **nomes de ossos do Mixamo** (`mixamorig:Hips`, `mixamorig:Spine`,
  `mixamorig:LeftArm`, `mixamorig:LeftForeArm`, `mixamorig:LeftHand`…), em **pose T**, com
  proporções próximas às do boneco padrão do Mixamo para o retarget sair limpo.
- Animações do Mixamo tocando no ferreiro via `AnimationPlayer`/`AnimationTree`, com retarget
  pelo perfil humanoide do Godot (`SkeletonProfileHumanoid` + `BoneMap` no import).
- Comportamento:
  - **Trabalhando** (padrão): martelando na bigorna em loop, intercalado de vez em quando com uma
    pausa curta (ex.: limpar a testa, examinar a peça). 2–3 animações.
  - **Jogador perto**: para de martelar e se vira para ele (como o Bram/Mira já fazem).
  - **Conversando**: animação de fala/gesto enquanto o diálogo está aberto.
  - **Fim da conversa**: volta a martelar.
- Faíscas e som de martelo na bigorna **sincronizados com o golpe** da animação.
- Bigorna (e forja/brasa simples) como modelos novos no mesmo estilo.
- Diálogo só de ambientação, pelo mesmo sistema do Bram/Mira (`open_dialogue`).

## Fora do escopo

- Sistema de forja, loja ou missão do ferreiro.
- Migrar cavaleiro, soldados, Bram, Mira ou goblin para esqueleto.
- Rotas/caminhada do ferreiro pela vila.
- Sincronizar a animação pela rede (é cosmética e local, cada cliente anima o seu).

## Anti-objetivos (falhou mesmo que "funcione")

- O ferreiro destoa visualmente do Bram e da Mira (parece um boneco do Mixamo colado na vila).
- Animações com membros torcidos, pés afundando ou mãos longe da bigorna/martelo.
- O ferreiro congela como estátua durante o diálogo (o diálogo pausa o jogo).
- O processo vira algo manual e não reproduzível: o modelo precisa sair do script.

## Restrições

- **Godot 4.7.2**, Forward Plus. Blender 5.2 pela CLI (o MCP do Blender trava ao exportar glTF):
  `"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python tools/blender/build_assets.py`
  com `ASSETS="blacksmith,anvil"` para gerar só esses.
- Convenção do script: frente do personagem = **-Y no Blender** (+Z no Godot).
- O diálogo **pausa a árvore só no jogo solo**; online ele apenas liga `input_locked`. Os nós de
  animação do ferreiro precisam de `process_mode = PROCESS_MODE_ALWAYS` (ou equivalente) para
  continuar animando durante a conversa no solo, e o comportamento tem de funcionar nos dois casos.
- Os NPCs atuais estão em `scripts/world/npc.gd` (`StaticBody3D`, grupo `interactable`,
  `collision_layer = 8`, cápsula 0.4×1.8) e são criados em `scripts/world/world.gd` (~linha 223).
- Sons do jogo são **sintetizados** em `scripts/autoload/sfx.gd` (`_gen`, `play_at` com atenuação
  por distância). O som da bigorna segue esse padrão (novo gerador, ex. `_anvil`), sem arquivo de áudio.
- **Licença Mixamo / repositório:** o repositório `thyxbr/farm-survivors` é **público**. A licença
  do Mixamo permite uso dentro do jogo, mas não redistribuir os arquivos brutos. Mesmo avisado
  disso, o usuário **escolheu commitar os FBX** em `assets/animations/mixamo/` (junto da
  `AnimationLibrary` retargetada, se ela for gerada como `.res`).
- Download das animações é feito **pelo usuário** (login Adobe). O builder entrega a lista exata
  (nome da animação no site + opções: FBX, *Without Skin*, 30 fps, *In Place* quando houver).
- O servidor dedicado (headless) **monta a vila**, então o ferreiro existe lá. Ele não deve custar
  processamento de animação à toa: desligar `AnimationTree`/faíscas/som quando
  `DisplayServer.get_name() == "headless"`.
- O deploy do CI (`.github/workflows/deploy.yml`) monta o jogo a partir do repositório: só chega ao
  jogo publicado o que estiver commitado.
- `build_assets.py` hoje exporta com `export_animations=False`; o ferreiro precisa do esqueleto
  exportado (e, se houver clipes feitos no script, das animações também).

## Abordagens consideradas

| | Abordagem | Ganha | Custa |
|---|---|---|---|
| **A (escolhida)** | Script gera modelo **e** esqueleto com nomes do Mixamo; peças presas aos ossos; animações do Mixamo retargetadas no Godot pelo perfil humanoide | Visual igual à vila; reproduzível pelo script; caminho serve para os próximos personagens | Esqueleto precisa de proporções/orientações corretas; alguns ciclos de ajuste visual |
| B | Exportar FBX sem esqueleto, rig automático no site do Mixamo, baixar já animado | Animações encaixam de primeira | Passo manual a cada mudança; auto-rig erra em avental/martelo/barba; pesos fora do script |
| — | Boneco pronto do Mixamo | Zero modelagem | Não combina com o estilo; usuário quer testar a modelagem. Descartada |

O usuário escolheu **A**.

## Decisões (do usuário)

- Personagem: ferreiro, fixo numa bigorna, trabalhando e conversando.
- Função: só ambientação por enquanto.
- Abordagem A.
- FBX do Mixamo são commitados no repositório.
- Se o Mixamo não tiver um bom clipe de martelar ou de pausa, o builder **pode criar o clipe** por
  keyframes no script do Blender, no mesmo esqueleto (o export passa a incluir animações).
- O usuário baixa as animações **depois**: a implementação começa com clipes provisórios
  (feitos no script) e troca pelos do Mixamo quando os arquivos chegarem. Ordem sugerida:
  modelo + esqueleto → NPC no Godot com clipes provisórios → retarget dos FBX → faíscas/som.

## Decisões minhas (propostas, corrigíveis)

- **Pesos:** cada peça rígida ligada 100% ao seu osso; nas juntas de cotovelo/joelho/ombro, as
  malhas que cruzam a junta (manga, calça, avental) recebem pesos suaves (automáticos ou por
  gradiente no script). Se ficar estranho, cai para 100% rígido, que já combina com o estilo.
- **Martelo** é um objeto separado preso à mão direita via `BoneAttachment3D` no Godot (não
  ponderado na malha), para poder trocar depois e para posicionar faíscas.
- **Sincronia golpe→faísca/som:** *method track* (ou marcadores) na animação de martelar,
  chamando `_on_strike()`; faíscas na ponta do martelo / topo da bigorna; som via `Sfx.play_at`.
- **Máquina de estados:** `AnimationTree` com `StateMachine` (`work`, `pause_variant`, `turn/idle`,
  `talk`), transições com *crossfade* curto (~0.2–0.3 s).
- **Código:** o ferreiro reaproveita `npc.gd` (novo `npc_id = "blacksmith"`, modelo e diálogo) se
  couber sem bagunçar; se a lógica de animação crescer, vai para um script próprio
  (ex.: `scripts/world/blacksmith.gd`) que estende ou compõe o NPC. Escolha do builder.
- **Nome e falas:** proposta "Doran, o Ferreiro", 2–3 falas de ambientação sobre a forja e a vila.
- **Local:** um canto livre da vila, visível da praça, sem bloquear caminhos; registrar a área em
  `_avoid` como a horta faz. Ponto exato fica com o builder, conferindo por screenshot.
- **Teste:** o smoke test (`--smoketest`) continua passando; adicionar uma checagem de que o
  ferreiro existe, tem `Skeleton3D` com os ossos esperados e que o `AnimationPlayer` tem as
  animações de trabalho e fala.

## Animações a baixar (lista inicial, o builder confirma os nomes no site)

1. Martelar em pé (procurar "hammer", "hammering", "blacksmith") — loop principal.
2. Uma pausa de trabalho (ex.: limpar o suor, alongar, olhar a peça) — variação.
3. Idle em pé — quando o jogador se aproxima.
4. Falando/gesticulando ("talking") — durante o diálogo.

Opções: FBX for Unity/FBX Binary, **Without Skin**, 30 fps, *In Place* quando a opção existir.

## O que fica com o builder

- Proporções exatas e rolls dos ossos para o retarget (comparar com o boneco do Mixamo).
- Configuração do import (BoneMap, perfil, *rest fixer*) e como gerar a `AnimationLibrary` `.res`.
- Detalhes visuais do ferreiro (avental de couro, braços fortes, barba, luvas) dentro do estilo
  de `characters.py`, conferidos com renders lado a lado com Bram e Mira.
- Partícula de faísca e som `_anvil`.

## Perguntas

Nenhuma em aberto. As três levantadas na revisão (licença/repo, clipes próprios, quando baixar)
foram respondidas pelo usuário e estão em "Decisões (do usuário)".
