# Penteados escolhidos na criação e cabelo sob capuzes

## Por quê

Com a cabeça lisa nova (0.48.0), capuzes, chapéus e elmos abertos mostram a cabeça careca, porque esses
estilos montam a cabeça sem cabelo. E o herói tem um cabelo só por corpo. O usuário quer penteados
variados, baseados em referências de cabelo anime e estilizado (folhas largas, pontas, franja), escolhidos
na criação do personagem, e o cabelo inteiro aparecendo também sob capuzes e chapéus.

## Decidido com o usuário

- O penteado é uma **escolha na criação**, gravada no personagem (como o corpo).
- Sob capuzes e chapéus aparece o **cabelo inteiro**, inclusive o comprido caindo nas costas.

## Abordagens consideradas

1. **Cabelo como peça separada** (escolhida): os estilos de cabeça (`h_*`) param de trazer cabelo; cada
   penteado vira `gear/hair_<id>.glb` (e `_f`), vestido por `KnightLook.apply` como um equipamento. Cada
   estilo de cabeça diz como o cabelo entra: inteiro, apertado (sob capuz e chapéu) ou nenhum (elmo fechado).
   Custa um GLB por penteado e variante, em vez de um por penteado e chapéu.
2. Cabelo embutido em cada `h_*` por penteado: 19 estilos × 8 penteados × 2 corpos = ~300 GLBs. Descartada.
3. Cabelo montado em tempo de jogo por código: perde o pipeline do Blender (sombra assada, contorno, pele).
   Descartada.

## Desenho

**Penteados (4 por corpo, a partir das referências):**

| id | corpo | descrição |
|---|---|---|
| `m_curto` | m | o atual: curto, franja repartida de lado (padrão) |
| `m_penteado` | m | penteado para trás e para o lado, testa à mostra, topo com volume |
| `m_franja` | m | franja reta cobrindo a testa até a sobrancelha, lados cheios (tigela) |
| `m_raspado` | m | bem curto rente à cabeça, só uma franja curta em pontas |
| `f_longo` | f | o atual: comprido nas costas com rabo de cavalo alto (padrão) |
| `f_chanel` | f | chanel na altura do queixo, franja reta |
| `f_curto` | f | curto repicado, mechas do rosto até a mandíbula |
| `f_marias` | f | franja de lado e duas marias-chiquinhas presas acima das orelhas |

Todos com as mechas largas em camadas de `anime_hair` (calota no tom médio, nuca escura, folhas claras),
que é o que as referências mostram.

**Modelos:** `hair_<id>.glb` (penteado sobre a cabeça nua) e `hair_<id>_tight.glb` (o mesmo penteado
achatado contra o crânio no topo e nos lados, para caber sob capuz e chapéu; franja, nuca e o que cai abaixo
da orelha ficam iguais). Corpo feminino: `_f`, como as roupas. Rabo de cavalo e marias-chiquinhas saem do
`knight_f.glb` e vão para o GLB do penteado, com o mesmo nó `Ponytail` (o balanço do jogo continua).

**Estilos de cabeça:** `h_bare` e os demais param de trazer cabelo. Cada estilo ganha um modo:
- `full`: cabeça nua, coroas e tiaras (`h_bare`, `h_astral`, `h_frost`, `h_hierophant`, `h_raven`...);
- `tight`: capuzes e chapéus (`h_hood`, `h_cap`, `h_wizard`, `h_archmage`, capuzes de manto...);
- `none`: elmos fechados (`h_great`, `h_dragon`, `h_kettle`, `h_nasal`, se o rosto ficar coberto).
A tabela fica em `KnightLook` (como `HIDE_PONYTAIL` hoje, que some).

**Dados:** `CharState.hair` (string; vazio = padrão do corpo). `choose_class(cls, body, hair)` valida que o
penteado existe e é do corpo. Criação, lista de personagens, seleção e o visual na rede levam `hair` como
levam `body` (o servidor manda o gravado, nunca o do cliente). Personagens antigos ficam com o padrão.

**Tela de criação:** uma fileira de 4 botões de penteado abaixo do corpo; trocar o corpo troca a lista e
volta ao padrão. A prévia mostra o penteado na hora.

## Não é objetivo

- Cor de cabelo escolhível (fica a cor atual).
- Trocar de penteado depois de criado (barbeiro).
- Penteados para NPCs e aldeões.

## Fica com quem implementa

- Proporção exata de cada penteado, olhando as referências lado a lado a cada rodada.
- Quanto o `tight` achata, por medição contra o forro de cada capuz (sem atravessar o tecido).
- Quais elmos são `none`: decidir pelo render (se o rosto aparece, o cabelo da franja aparece).
