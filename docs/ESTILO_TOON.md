# Estilo toon ("desenhado") — o que aprendemos e plano de migração

Estado em 14/11/2026, branch `toon-npc-teste`. O estilo nasceu de um estudo de personagem em Blender
(sombra em dois tons + contorno) e foi trazido para o Godot. Hoje cobre **personagens** (com contorno)
e **cenário** (props, construções, árvores, vegetação, chão e grama, sem contorno).

## O que é o estilo

| Ingrediente | Como é feito | Onde |
|---|---|---|
| Sombra em dois tons | cada luz ou acende a face inteira ou a deixa no tom de sombra; corte seco, sem degradê | `assets/shaders/toon_light.gdshaderinc`, incluído por `toon_character`, `ground` e `grass` |
| Sombra fria | a face em sombra recebe a luz multiplicada por `shade_tint` (0.40, 0.38, 0.55): mais escura e azulada | idem |
| Sombra projetada | a atenuação do sol passa por um degrau (0.3–0.7) e cai num tom mais fundo, `cast_tint` (0.16, 0.16, 0.27) | idem |
| Brilho de metal | uma faixa dura de especular, só em material com `metallic` > 0.55 | idem, `gloss` |
| Contorno | casca invertida: cópia da malha, faces de trás, empurrada pela normal, sem luz | `assets/shaders/toon_outline.gdshader` |

Os GLBs **não mudam**. `ToonLook.apply(modelo)` (`scripts/world/toon_look.gd`) lê cada
`StandardMaterial3D` e monta o `ShaderMaterial` equivalente em tempo de execução. Ligado por padrão;
`-- --notoon` volta ao sombreado antigo, para comparar.

## Aprendizados

### Do estudo no Blender
1. **Medir a referência antes de modelar.** A primeira versão seguiu proporções "de cabeça" e ficou
   longe. O que funcionou: recortar cada painel da ficha em zoom, medir em pixels, converter para
   metros e só então escrever os números. Depois, comparar render e referência lado a lado a cada rodada.
2. **O rosto fica melhor sem sombra de forma.** Em anime a pele do rosto é chapada; a sombra vem só do
   cabelo e do pescoço. Facetas de low-poly no rosto viram triângulos de sombra dura.
3. **Detalhe pequeno é geometria ou decalque, não textura.** Olhos, costuras e frisos foram tiras
   projetadas sobre a malha; dá para fazer por código e não precisa de UV.
4. **O que código não resolve bem:** dobras de tecido, mãos, perfil do rosto e mechas largas de cabelo.
   Isso pede escultura ou pintura à mão.

### Da adaptação no Godot
1. **Usar a luz do jogo, não uma luz própria.** O shader só troca o *corte* da luz; cor e intensidade
   continuam vindo do sol, da contraluz e do ambiente (`WorldLighting`). Por isso o personagem não
   destoa do cenário.
2. **Face acesa recebe a luz inteira**, sem o cosseno do Lambert, então cores claras estouram. O
   `light_gain` (0.72) compensa.
3. **Metal precisa ser escurecido.** No PBR o metal reflete o céu e sai bem mais escuro que o albedo; no
   toon ele ficaria quase branco. O albedo é escurecido em `0.35 × metallic` — proporcional, porque as
   malhas e cotas usam `metallic` perto de 0.5 e um corte fixo em 0.5 as deixava de fora (foi o bug da
   armadura branca).
4. **Contorno em low-poly exige normais suavizadas.** Com faces chapadas a casca abre frestas nas
   arestas. `ToonLook` gera uma malha de casca com uma normal por posição (média das faces vizinhas),
   uma vez por malha, e guarda em cache.
5. **Peças miúdas ficam sem contorno.** Abaixo de 7 cm (olhos, sobrancelhas, rebites) a casca engole a
   peça. `MIN_OUTLINE_SIZE`.
6. **Largura do contorno:** 5,5 mm, crescendo 5% por metro de distância para não sumir de longe.
   Com 11 mm o rosto virava um borrão preto.
7. **O jogo troca materiais por código, e o toon tem que entrar depois:**
   - `material_override` (placas tingidas do cavaleiro) vence os materiais por superfície, então ele
     também é convertido;
   - a tintura dos goblins (`enemy.gd`, `_apply_tint`) lê `StandardMaterial3D`, então o toon é aplicado
     **depois** dela;
   - a cor por vértice (AO assado das placas, armas pintadas) e a textura das armas traçadas
     multiplicam o albedo dentro do shader;
   - `KnightLook.apply` reaplica o toon a cada troca de equipamento (a chamada é idempotente).
8. **Malha com esqueleto:** a casca fica ao lado da malha, presa ao mesmo esqueleto. Sem esqueleto ela
   é filha da peça e herda transformação e visibilidade.
9. **Translúcido não entra.** O contorno apareceria por dentro do corpo do slime; materiais com
   transparência ou sem luz (`unshaded`) são ignorados.
10. **PowerShell:** para rodar o Godot com caminho entre aspas é preciso o `&` na frente.

### Do cenário
1. **Um gancho só, em vez de dezenas de chamadas.** O autoload `Toon` (`scripts/autoload/toon.gd`) ouve
   `SceneTree.node_added` e converte toda `MeshInstance3D` e `MultiMeshInstance3D` que entra na cena.
   A conversão roda no quadro seguinte, para pegar materiais atribuídos logo depois do `add_child`.
2. **Material com emissão fica como está no cenário.** Lamparinas, portais e brilhos são efeitos, e parte
   deles é animada por código; convertê-los congelaria a animação.
3. **MultiMesh não tem material por instância.** O material toon entra na própria malha compartilhada;
   a cor por instância continua valendo via `COLOR`.
4. **Chão e grama têm shader próprio**, então recebem a mesma luz por `#include` em vez de conversão. O
   uniforme `toon` desliga o estilo com `--notoon` (cai num Lambert simples, não no Burley de antes).
5. **Sombra projetada precisa de tom próprio.** Com o mesmo tom da sombra de forma, a sombra no chão
   ficava fraca e a cena perdia contraste; `cast_tint` é mais fundo.
6. **Degrau largo na sombra projetada.** O borrão da sombra tem ruído; com degrau estreito (0.42–0.58) a
   borda saía granulada.
7. **Servidor dedicado não converte nada.** Sem janela e fora dos testes, `ToonLook.enabled()` é falso.
8. **Capturas de conferência devem usar `--geardemo`** (save à parte). Abrir `hub.tscn` ou
   `colony.tscn` direto usa o save solo de verdade e pode abrir uma partida nele.

### Custo medido
80 goblins parados, 1280×720, `tools/toon_cost.gd` (medida simples, sem IA nem efeitos):

| | Sem toon | Com toon |
|---|---|---|
| Tempo por quadro | 4,9–5,1 ms | 6,6–7,5 ms |
| Draw calls | 445 | 505 |
| Triângulos | 505 mil | 642 mil |

Cerca de 40% a mais, quase tudo do contorno (dobra os triângulos de cada personagem).

## Onde o estilo já está

| Quem | Por onde |
|---|---|
| NPCs da vila (ancião, mercadora, ferreiro) | `scripts/world/npc.gd` |
| Jogador, soldados, prévia do personagem, armas | `scripts/player/knight_look.gd` (fim de `apply`) |
| Inimigos | `scripts/enemies/enemy.gd` |
| Caravana e aldeão perdido | `scripts/colony/caravan.gd` |
| NPCs da praça | `scripts/hub/hub_point.gd` |
| Cavaleiro e goblin do menu | `scripts/ui/main_menu.gd` |

| Props, construções, árvores, vegetação em MultiMesh | autoload `Toon` (`scripts/autoload/toon.gd`) |
| Chão e grama | `ground.gdshader` e `grass.gdshader`, via `toon_light.gdshaderinc` |

## Plano de migração

| Etapa | O que | Estado |
|---|---|---|
| 1 | Personagens, com contorno | feito |
| 2 | Cenário: props, construções, árvores, vegetação, chão e grama, sem contorno | feito |
| 3 | Slimes: corpo translúcido precisa de tratamento próprio (opaco com brilho em faixa, ou contorno por borda) | a fazer |
| 4 | Peças com emissão e efeitos (lamparinas, portal, projéteis): decidir caso a caso | a fazer |
| 5 | Materiais trocados por código depois do primeiro quadro (ex.: `resource_node.gd`) não são convertidos | a conferir |
| 6 | Ajuste global de luz e pós-processo (SSAO e névoa brigam com cor chapada; serra ao fundo ainda é degradê) | a fazer |
| 7 | Desempenho: custo do contorno na Horda e do gancho de cena em mapas grandes | a medir |
| 8 | Opção no menu de vídeo (estilo e contorno ligados/desligados) | a fazer |
| 9 | Rosto dos NPCs sem sombra de forma, como no estudo | em aberto |

## Ferramentas

```powershell
$G = "C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe"
# foto lado a lado (antigo à esquerda, toon à direita) de qualquer modelo, com a luz do jogo
& $G --path . --resolution 1400x1000 --script res://tools/toon_shot.gd -- goblin saida.png 3q
# custo numa multidão
& $G --path . --resolution 1280x720 --script res://tools/toon_cost.gd -- 80 toon
# jogo com o sombreado antigo, para comparar
& $G --path . res://scenes/world.tscn -- --notoon
```

A prévia em Blender (`toon_preview.py`, fora do repositório) serviu só para decidir se valia a pena;
o que vale é a foto no Godot.
