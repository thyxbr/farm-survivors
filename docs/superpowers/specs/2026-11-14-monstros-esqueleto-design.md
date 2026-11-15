# Monstros: goblin refeito, esqueletos e novas variantes — design

Aprovado pelo usuário em 2026-11-14 (conversa). Pedido original: "melhore a modelagem de todos os
monstros menos a slime, que já está boa; acrescente um monstro esqueleto e novos tipos de variações".

## Intenção

Os monstros precisam ser mais bonitos e mais variados. Hoje só existem dois modelos (slime e goblin) e as
sete variantes de goblin são o mesmo modelo recolorido: o arqueiro atira flechas segurando uma clava.

## Objetivos

1. Goblin remodelado no padrão de `tools/blender/STYLE.md` (membros em loft que afinam, joelho e cotovelo
   legíveis, mãos e pés robustos), com equipamento próprio por variante.
2. Esqueleto como família nova de inimigos, com modelo próprio.
3. Variantes novas usando as IAs que já existem.
4. Os novos monstros aparecem no mundo, na Horda e na Defesa da Cidade.

## Fora do escopo

- O modelo da slime não muda (a Slime de Gelo é só cor e efeito).
- Nenhuma IA nova; nenhuma animação nova (os modelos usam os pivôs `LegL/LegR/Body/Head/ArmL/ArmR`).
- Nenhuma missão nova.

## Abordagens

- **A. Um GLB por variante.** Mais arquivos, memória e tempo de import; a tintura continuaria igual.
- **B. Um GLB por família com peças opcionais (escolhida).** Cada peça de equipamento é um nó `Opt_<Nome>`
  no modelo; `enemies.json` lista em `"gear"` quais ficam, e o resto é removido ao instanciar. Um arquivo
  por família, variantes novas viram só dados.
- **C. Montar equipamento por código no Godot.** Fugiria do pipeline do Blender e do estilo dos modelos.

## Decisões

### Peças opcionais
- Nó cujo nome começa com `Opt_` é opcional. `Enemy.apply_gear(model, gear)` remove os que não estão em
  `gear` (nomes sem o prefixo). Usado também no menu principal e nas ferramentas de foto.
- A coroa do rei deixa de ser caso especial: vira `Opt_Crown`.

### Goblin (`goblin.glb`)
| Tipo | `gear` |
|---|---|
| goblin (batedor) | Club |
| goblin_arqueiro | Bow, Quiver |
| goblin_xama | Staff, Mask |
| goblin_dourado | Sack |
| goblin_campeao | Axe, Armor, Helm |
| goblin_bruto | BigClub, Pads |
| goblin_king | Club, Crown, Cape |
| goblin_bombardeiro (novo) | Barrel, Torch |

### Esqueleto (`skeleton.glb`)
| Tipo | Nome | IA | `gear` |
|---|---|---|---|
| esqueleto | Esqueleto Guerreiro | corpo a corpo | Sword, Shield |
| esqueleto_arqueiro | Esqueleto Arqueiro | ranged | Bow, Quiver |
| esqueleto_mago | Esqueleto Mago | ranged com `"shot": "bolt"` (projétil mágico roxo) | Staff, Hood |
| esqueleto_cavaleiro | Cavaleiro Esqueleto | elite, `slam_every: 3` | Greatsword, Helm, Armor |

### Outras variantes
- **Goblin Bombardeiro**: IA `bomber` com o modelo do goblin.
- **Slime de Gelo**: `"chill": 2.5` — o golpe deixa o jogador lento (velocidade × 0,6) por 2,5 s. Em rede o
  servidor avisa o dono do personagem, como já faz com o dano.

### Onde aparecem
- **Mundo**: esqueletos nas Ruínas (3 guerreiros, 2 arqueiros, 1 mago, 1 cavaleiro); 2 bombardeiros no
  Acampamento Goblin; 2 slimes de gelo nos campos.
- **Horda**: slime de gelo (rodada 4+), esqueleto e bombardeiro (5+), esqueleto arqueiro (6+), esqueleto
  mago (8+); a partir da rodada 8 o "campeão" pode ser um Cavaleiro Esqueleto.
- **Defesa da Cidade**: esqueleto guerreiro nas ondas noturnas (só corpo a corpo, porque o cerco não trata
  ataque à distância); as Ruínas Assombradas passam a ser guardadas por esqueletos, com o Cavaleiro como chefe.

### Itens
- `bone_shard` ("Lasca de Osso", material, preço 9): cai dos esqueletos.

### Correção necessária
- A flecha inimiga só causava dano quando o pai tinha `targets()` (só a Horda). Sem isso ela passa a usar o
  grupo `players`, como a explosão já faz; senão arqueiros e magos seriam inofensivos no mundo e na cidade.

### Chamadas do construtor (minhas, não do usuário)
- Código de modelagem dos monstros sai de `characters.py` para `tools/blender/monsters.py`.
- Valores de vida/dano dos novos tipos seguem a faixa dos goblins equivalentes.
- Versão do jogo: 0.14.0 (muda o protocolo: tipos novos e um RPC novo).
