# Marcha fluida (andar e correr) — desenho

## Intenção
O andar e o correr do cavaleiro parecem travados: as pernas estão bem resolvidas, mas tronco, quadril,
cabeça e braços se movem como um bloco, todos no mesmo instante. Queremos o corpo inteiro participando
da passada, sem mexer nos modelos.

## Objetivos
1. Cabeça estável: compensa o giro e a inclinação lateral do tronco e fica apontada para a frente.
2. Quadril gira com a passada: a pelve avança do lado da perna que vai à frente, contra os ombros.
3. Troca de peso: o tronco desloca um pouco para cima da perna de apoio.
4. Braços soltos: o antebraço chega depois do ombro e a mão cruza um pouco à frente do corpo.
5. Arrasto entre as partes: quadril puxa, tronco segue, cabeça e braços por último.

A inclinação nas curvas já existe (`_bank` em `player.gd`) e não muda.

## Fora do escopo
Ataques, parado, esquiva, dividir o tronco em coluna/pescoço, pele contínua no corpo.

## O que seria um fracasso
- Pé de apoio escorregando (para trás ou de lado) mais do que hoje.
- Movimento caricato: os valores começam discretos e sobem só depois de o Henrique ver no jogo.
- Qualquer mudança na pose parada (`move = 0`) ou nos golpes.

## Restrições
- Tudo em `KnightAnim.locomotion_pose` / `apply` (`scripts/player/knight_anim.gd`), compartilhado por
  jogador, réplicas, NPCs cavaleiros, guardas e menu. Poses continuam sendo dicionários de `rest_pose()`.
- `config/version` sobe antes do merge (0.38.2 -> 0.38.3).

## Abordagens consideradas
1. **Lapidar a marcha no esqueleto atual (escolhida pelo Henrique).** Só código; vale para todos os corpos.
   O tronco continua um bloco.
2. Marcha + coluna: dividir o tronco nos modelos do Blender. Mais expressivo, mas refaz `knight.glb`,
   `knight_f.glb` e o encaixe de todo equipamento de tronco. Fica como segunda etapa, se ainda parecer caixa.
3. Pele contínua no corpo: suaviza as juntas, não muda o movimento. Vai junto com o roupão, em outra sessão.

## Como conferir
- Folha de passada (`tools/gait_shot.gd`) antes e depois, em 2,5 m/s, 5,2 m/s e correndo.
- Teste unitário novo mede: giro da cabeça no mundo, sentido do quadril, escorregão lateral do pé de apoio,
  mão cruzando, e pose intacta com `move = 0`.
- Testes do projeto; por fim o Henrique julga no jogo, um ajuste por rodada.

## Segunda rodada (17/11): inclinação do corpo inteiro
O Henrique testou e achou que ele ainda corre "com a coluna reta e mal inclina". Causa: 4,6° de inclinação na
velocidade normal, aplicada só na cintura. Feito nesta rodada (caminho A, só código): inclinação de ~11° no
andar normal e ~17° correndo, vinda de `KnightAnim.locomotion_pose` (a ferramenta de passada passa a mostrá-la);
o apoio recua em relação ao quadril (`STANCE_BACK`: o pé pousa mais embaixo do corpo e empurra atrás); o tronco
mergulha um pouco a cada apoio (`LEAN_PULSE`); a cabeça desfaz 60% (`HEAD_LEAN`). `player.gd` fica só com a
parte da aceleração. Fica para depois (caminho B): dividir o tronco em quadril/peito/pescoço nos modelos, com a
inclinação repartida pela coluna; é o que resolve a "coluna reta".

## Terceira rodada (17/11): coluna, etapa 1 (só código)
Aprovado pelo Henrique em duas etapas. Etapa 1, feita: pivô `Chest` criado em `KnightAnim.ensure_chest()` (filho de
`Body`, na cintura); cabeça, braços, capa e as peças rígidas que sobem acima da cintura passam para ele, pela
altura de cada peça (vale para toda armadura; `KnightLook.apply` chama de novo ao trocar a roupa). Na marcha a
inclinação se reparte (`CHEST_LEAN`), os ombros giram no peito contra o quadril (cinto e saiote agora giram com
a pelve) e ficam nivelados (`CHEST_LEVEL`). Golpes, arco e magias recebem o tronco inteiro de volta em `Body`
(`drop_gait_comp`), então as poses deles não mudam. Roupas de pele contínua têm um osso só no tronco: ele segue o
peito (`PivotSkin`), ou seja, inclinam inteiras e não curvam.
Etapa 2, pendente (Blender): osso de peito no esqueleto das roupas de pele contínua (camisa, corpo base, manto
do arquimago) para o tecido curvar; emendas das peças rígidas, se aparecerem no jogo.
