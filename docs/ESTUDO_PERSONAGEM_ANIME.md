# Estudo de personagem em estilo anime, feito por código no Blender

Registro técnico de um estudo feito **fora do repositório** (pasta local `C:\Games\blender-estudos\`):
recriar no Blender, só com scripts Python, um personagem de anime a partir de uma ficha de referência
com vários painéis (cabeça em quatro vistas, torso, braço, pernas, botas). A ficha é arte de terceiros,
de uso local: **ela, os renders do estudo e o desenho do personagem não entram no repositório nem no
jogo**. O que interessa aqui é a técnica, e as medidas genéricas que servem para qualquer personagem.

O resumo está em [`ESTILO_TOON.md`](ESTILO_TOON.md), seções "Do estudo no Blender" e "Do rosto e das
mãos desenhados". Este documento aprofunda cada parte e diz, para cada uma, o que funcionou, o que foi
tentado e abandonado, e onde o código para de render. O que já veio para o jogo está em
`tools/blender/anime.py` (`anime_head`, `open_hand`, `anime_hair`, `anime_beard`).

O estudo teve sete rodadas de script (`v1` a `v7`, mais a final). Diferença importante em relação ao
jogo: lá cada peça usava subdivisão (Subsurf nível 1 ou 2) e a cena chegou a centenas de milhares de
triângulos. No jogo o orçamento é ~5 mil por personagem, sem subdivisão; cada técnica abaixo precisa ser
trazida com menos seções e menos lados.

## Resumo por parte

| Parte | O que funcionou | O que não funcionou | Limite do código |
|---|---|---|---|
| Cabeça e rosto | três curvas de perfil por altura (largura, frente, nuca) | elipsoide com afinamento por fórmula | perfil do rosto (lábios, queixo) fica genérico |
| Olhos | decalques em camadas projetados na cabeça | olho como geometria com relevo; sombra no rosto | de perfil o olho é um desenho comprimido |
| Cabelo | mechas largas e chatas por spline sobre o crânio, em camadas | espigões de Bézier, mechas finas, pontas em pé na coroa | o desenho de cada mecha é posto à mão; o acaso só varia |
| Torso e armadura | grade de pontos com material por célula; placas com bordas por função | tubo com arco aberto para tudo | dobras de tecido |
| Braços e mãos | tubo com barra e raio que dependem do ângulo; dedos em falanges | manga de barra reta; dedos em tubo reto | pose da mão, costuras da luva |
| Pernas e botas | loft com rolos; seções com frente e trás diferentes | perna em cone liso; sola em fatia | rugas do couro são só traços |
| Materiais e contorno | dois tons com corte seco; contorno por casca com cor por grupo | sombra de forma no rosto; contorno preto e grosso | sombra desenhada (a que o artista escolhe) |
| Método | medir recortes ampliados; comparar lado a lado; uma parte por vez | proporções "de cabeça"; olhar só o render inteiro | — |

## Cabeça e rosto

**Funcionou.** A cabeça final nasce de um cubo subdividido projetado numa esfera (malha só de quads,
sem polo no rosto) e deformado em duas metades:

- do olho para cima, um elipsoide simples, com a frente achatada por uma potência
  (`y' = -(1 - (1 + y)^1.45)`): o plano do rosto fica mais largo e chato que a nuca;
- do olho para baixo, fatia por fatia, a partir de **três tabelas lidas da ficha**: meia-largura (vista
  de frente), profundidade da frente (perfil) e linha de trás / de baixo da mandíbula (perfil).
  A interpolação entre os pontos da tabela é suave (smoothstep), não linear.

O nariz, os lábios e o sulco acima do queixo são pequenos relevos gaussianos somados só na frente
(`exp(-(x/a)² - ((z-z0)/b)²)`), com poucos milímetros. O nariz é quase nada de frente e uma ponta de
~3 cm de perfil.

Proporções medidas (genéricas de rosto de anime jovem, em fração da altura da cabeça, do queixo ao
topo do crânio): linha dos olhos a ~0,37; nariz a ~0,25; boca a ~0,13; bochecha mais larga na altura
do nariz, não na do olho; queixo estreito, em ponta arredondada; olhos com ~0,13 de largura e quase a
mesma altura.

**Não funcionou.**
- `v1`: elipsoide com a metade de baixo afinada por fórmula (`largura × (1 − k·t²)`). Dava um ovo: sem
  bochecha, queixo largo demais, cabeça 14% mais larga que a referência.
- `v2`: mesma fórmula com um "calombo" de bochecha somado. Melhorou de frente e seguiu errado de perfil,
  porque largura e profundidade eram a mesma curva.
- Covas de olho modeladas (`v1`): com a pele chapada não aparecem, e com sombra viram manchas.

**Limite.** O perfil (testa, nariz, lábios, queixo) é uma curva desenhada com intenção; por tabelas sai
correto e sem graça. A orelha é uma esfera achatada com um traço em decalque: lê bem a distância, não
de perto.

**No jogo.** `anime_head` usa a mesma ideia com uma grade de 13 anéis × 20 colunas (sem subdivisão) e
os mesmos marcos de `head.py`, para que cabelo, barba e chapéus encaixem.

## Olhos

**Funcionou.** O olho inteiro é desenho plano **projetado na cabeça por raio** (da frente para trás),
em camadas afastadas uma da outra por fração de milímetro: branco, sombra da pálpebra no branco, íris,
metade de cima da íris mais escura, reflexo claro embaixo, pupila, brilho, cílio de cima, cílio de
baixo, dobra da pálpebra e sobrancelha.

- O contorno do olho é uma superelipse (expoente ~2,3) mais alta embaixo que em cima, estreitando ~20%
  para a pálpebra de baixo.
- O cílio de cima é uma tira de largura variável: fina no canto de dentro, grossa a dois terços, com
  uma ponta para fora.
- O brilho fica do **mesmo lado nos dois olhos** (é a luz, não a anatomia).
- Vértice cujo raio erra a cabeça (borda do rosto) herda a profundidade do acerto mais próximo; raio
  que passa por uma fresta e acerta lá atrás é descartado.

**Não funcionou.**
- Vermelho e preto puros na íris e no cílio (`v1`): a ficha usa tons quebrados (vinho, marrom
  acinzentado). Colher a cor do recorte ampliado, não "de memória".
- Olho um terço maior que o medido (`v1`): parecia outro personagem. O tamanho do olho é a medida que
  mais muda a idade aparente.
- Boca como um traço contínuo: a ficha desenha dois tracinhos curtos com um vão no meio.

**Limite.** De perfil o decalque comprime e vira um risco; para perfil convincente seria preciso outro
desenho de olho, trocado por ângulo. No jogo as camadas precisam de 1 mm entre si (abaixo disso brigam
à distância) e de todas as faces viradas para a frente.

## Cabelo

Foi a parte que mais rodadas pediu (quatro versões) e a que mais ensinou.

**Funcionou: a mecha (`lock`).**
- Pontos de controle em coordenadas do crânio: (ângulo em volta, elevação, afastamento). Uma função
  `scalp` converte para o espaço; abaixo do "equador" o cabelo deixa de seguir a esfera e cai mais reto.
- Uma spline Catmull-Rom passa pelos pontos (4 a 5 amostras por trecho).
- Em cada amostra, uma seção em superelipse **larga e chata**: a largura fica no plano tangente ao
  crânio (tangente × normal do crânio), a espessura é ~30% da largura.
- Perfil de largura ao longo da mecha: começa em 50%, abre até 100% no primeiro sexto e afina em ponta
  (`min(1, 0,5 + 3,2·s) × (1 − s^2,6)^0,85`).
- Loft com 8 lados, sombreado liso.

**Funcionou: as camadas**, de baixo para cima:
1. calota de couro cabeludo (esfera recortada, um pouco menor que o cabelo) para nunca aparecer pele;
2. nuca: mechas curtas num tom mais escuro, por baixo de tudo, até a gola;
3. **tom intermediário**: mechas largas num terceiro tom, que aparecem nos vãos das mechas claras e
   fazem o papel de sombra desenhada;
4. meio: lados e trás até a altura da boca;
5. topo: saem de perto da coroa e as pontas viram para fora na altura do olho;
6. redemoinho: mechas pontudas que giram a partir de um ponto um pouco atrás e ao lado do topo;
7. franja: poucas **folhas largas**, repartidas de lado, cruzando a testa;
8. moldura do rosto: uma mecha à frente de cada orelha até a mandíbula, uma curta na têmpora, uma atrás
   da orelha.

O cabelo tem contorno próprio, num tom **mais claro** que o contorno do corpo (cabelo claro com traço
preto fica sujo).

Medidas genéricas úteis: a massa do cabelo passa ~1 cm do crânio no topo e 2 a 4 cm nos lados; mechas
de 3 a 4 cm de largura; 10 a 13 mechas por camada em volta da cabeça.

**Não funcionou.**
- `v1`, espigões de Bézier (raiz, controle, ponta) saindo do crânio: viram um ouriço. A mecha tem que
  **correr sobre o crânio** e só soltar na ponta.
- Mechas finas e numerosas (`v2`, largura 1,5 a 2 cm, 13 por camada, mais uma "segunda passada" curta
  no topo): viram espinhos e a cabeça perde a massa. Mecha larga, pouca e sobreposta lê melhor.
- Pontas curtas levantadas na coroa (`v2`/`v3`): de frente formam uma flor em volta da cabeça.
  Trocadas pelo redemoinho, cujas pontas ficam deitadas.
- Mechas cobrindo a orelha (`v3`): no perfil some a orelha e o rosto fica sem referência. Perto da
  orelha as mechas param cedo e viram para trás.
- Um tom só de cabelo (`v1`): sem a camada intermediária e a nuca escura, a massa vira um capacete.
- Calota do mesmo tom claro das mechas: os vãos acendem. A calota vai no tom intermediário.

**Limite.** O acaso (`random`) só serve para variar largura e ângulo de mechas que já estão no lugar.
Franja, moldura do rosto e as mechas que saem da silhueta foram postas uma a uma, olhando a ficha. E a
vista de cima nunca fechou de verdade: o desenho de cima da ficha é uma estrela gráfica que não
corresponde a um volume.

## Torso e armadura

**Funcionou.**
- **Roupa como grade de pontos** (linhas por altura × colunas em volta), com o raio por altura vindo de
  uma tabela `(z, raio_x, raio_y, abertura)`. A grade permite **material por célula** (faixas, forro,
  pala), o que o loft de anéis não dá. Espessura por Solidify.
- **Casaco aberto na frente**: a abertura é um ângulo por altura na mesma tabela, então a frente abre
  em "A" sem modelar duas metades.
- **Placas** (peitoral, joelheira, braçal) pela função `shell`: placa curva em volta de um eixo, com a
  borda de cima e a de baixo dadas por funções da posição lateral (`zb(x)`, `zt(x)`). Um "V" na borda é
  `z0 + |x|·k`; um rebaixo no meio é uma gaussiana.
- **Vinco** da placa: duas linhas da grade a 3 mm uma da outra na altura do vinco. Com sombreado liso é
  isso que dá a aresta.
- **Frisos, tiras e costuras** são tiras desenhadas no ar e projetadas na peça por raio, com espessura
  e contorno próprios quando são grossas (friso dourado) e sem espessura quando são linha (costura).
- Nervuras de tecido canelado: tiras finas num tom mais escuro, em leque.

**Não funcionou.**
- `v1`, placa como tubo de arco aberto: as bordas saem retas e a placa parece um cano cortado.
- Friso fino (`v1`, 7 mm): a ficha desenha frisos grossos (15 mm). Detalhe de anime é pouco e gordo.
- Fivela e bolsa centradas "por simetria": a ficha as põe de lado. Medir também a posição lateral.

**Limite.** Dobras de tecido. O casaco sai liso como papelão; as rugas da ficha (cintura, cotovelo,
calça sobre a bota) são desenho, e por código só dá para sugerir com rolos no loft ou traços em decalque.

## Braços e mãos

**Funcionou.**
- Todo o braço é descrito em **distância ao longo do eixo** ombro → ponta dos dedos (medida uma vez na
  ficha): cada faixa, tira e placa é um intervalo nessa distância. Mudar a pose é mudar o eixo.
- `tube`: grade em volta do eixo em que a **distância e o raio dependem também do ângulo**. É o que
  permite barra de manga inclinada (curta na axila, longa por fora), borda de placa côncava e a crista
  no meio do braçal (um "telhado" somado ao raio perto do ângulo zero).
- Faixas e tiras: anéis curtos de quatro seções (sobe, corre, desce), sem tampas.
- **Mão**: palma em loft de cinco seções (alarga do pulso aos nós e afina), quatro dedos em três
  falanges que dobram 7°, 17° e 16° para a coxa, abertos em leque (+9°, +3°, −4°, −11°), com
  comprimentos diferentes, e polegar grosso saindo da borda da frente da palma. Proporção da mão:
  ~19% do comprimento do braço.

**Não funcionou.**
- `v1`–`v5`, manga de barra reta e braçal em cone com ponta: três rodadas ajustando números sem medir.
  Só destravou ao recortar o painel do braço em 5× e 8× e anotar os intervalos.
- Dedos em tubo reto, lado a lado, do mesmo tamanho: parecem um garfo. O leque e a curva das falanges
  é que dão mão.
- Palma estreita (`v5`): a luva da ficha é larga nos nós.

**Limite.** A mão relaxada funciona parada. Fechada em volta de um cabo, ou em gesto, pede outra malha
(no jogo o ferreiro manteve o punho fechado antigo). Dedos custam caro: ~500 triângulos por mão no jogo.

## Pernas e botas

**Funcionou.**
- Calça folgada: loft com **dois rolos** (seções que engordam e emagrecem) logo acima da bota, em vez
  de dobras.
- Cano da bota em loft, mais **dois punhos dobrados** (anéis curtos sobrepostos).
- Pé em loft ao longo do eixo do pé, com seções em que **o raio de cima e o de baixo são diferentes**
  (`ry`/`ryb`): peito do pé alto atrás, biqueira baixa e larga na frente.
- Sola: loft chato de superelipse quadrada (expoente 3); salto como bloco separado; contraforte como
  placa `shell` atrás do calcanhar.
- Costuras e rugas do tornozelo: traços em decalque.

**Não funcionou.**
- `v1`, perna em cone liso: sem os rolos a calça parece meia.
- Joelheira em tubo de arco aberto (`v1`): mesma lição da placa do peito.
- Biqueira baixa (`v2`–`v4`): de lado a bota parecia um chinelo; a ficha tem biqueira alta e arredondada.

**Limite.** O couro amassado no tornozelo é só linha; o volume fica liso. O salto continuou mais
quadrado que o da ficha.

## Materiais toon e contorno

**Funcionou.**
- **Dois tons com corte seco**: difuso → `Shader to RGB` → rampa constante (sombra, base), saída em
  emissão. Opcionalmente um terceiro degrau de brilho (metal: limiar ~0,9).
- **Tom de sombra escolhido à mão por material**, puxado para o frio, e não "base × 0,6". Pele sombreia
  para o rosado; branco, para o cinza azulado.
- **Rosto sem sombra de forma**: material de emissão pura. Só o pescoço fica no tom de sombra, fixo.
- Limiar por material: o cabelo corta mais cedo (0,30) que a roupa (0,42), para ficar quase todo claro.
- **Contorno por casca invertida** (Solidify com normais viradas e material de trás), 1,2 a 1,6 mm.
  Cor do contorno **cinza-azulado escuro, não preto**, e um contorno mais claro para o cabelo.
- Peças miúdas e decalques sem contorno e sem projetar sombra.
- Fundo e luz: um sol só, que acompanha a câmera nas vistas de conferência, para que a sombra caia
  sempre do mesmo lado em relação a quem olha.

**Não funcionou.**
- Rosto com dois tons e limiar baixo (`v1`, 0,10): ainda apareciam cunhas de sombra no nariz e na
  bochecha.
- Contorno de 1,6 mm no rosto e nas mãos: engrossa demais em peça pequena.
- Branco puro nos olhos e nas roupas: estoura; a ficha usa brancos quebrados.

**Limite.** A sombra de anime é **desenhada**: o artista escolhe onde ela cai (sob a franja, sob o
queixo, na dobra). A luz em dois tons acerta a sombra de forma e erra a sombra de intenção. O jeito de
chegar perto é pôr geometria de sombra (a camada de tom intermediário do cabelo, o pescoço fixo).

**No jogo.** O equivalente está em `toon_light.gdshaderinc` e `ToonLook` (ver `ESTILO_TOON.md`): a
sombra fria é um multiplicador global (`shade_tint`), não um tom por material; `_flat` no nome do
material tira a sombra de forma; o contorno tem uma cor só.

## Método de trabalho

1. **Medir antes de modelar.** Recortar cada painel da ficha ampliado (5× a 12×), medir em pixels,
   converter para metros pela altura do personagem e escrever os números no cabeçalho do script.
   Todas as partes só convergiram depois disso; antes, eram rodadas de palpite.
2. **Comparar lado a lado a cada rodada.** Um script monta a tira "referência | render" na mesma
   altura, por parte e por vista. Olhar só o render engana: ele parece bom sozinho.
3. **Uma parte por vez, com enquadramento próprio** (cabeça, torso, braço, joelho, bota, pulso). O
   render de corpo inteiro esconde os erros de 1 cm.
4. **Todas as vistas da ficha.** Frente e perfil se contradizem menos do que parece; costas e topo
   revelam o que foi esquecido (nuca descoberta, pala das costas, redemoinho).
5. **Câmera ortográfica** nas conferências, como a ficha.
6. **Guardar cada versão** (`v1`…`v7`): voltar a uma tentativa descartada custa uma cópia.
7. **Scripts por parte**, recarregáveis: cada um apaga as peças que cria (`wipe` por prefixo) e
   reconstrói. Trocar a cabeça não refaz o corpo.
8. **Juntar ajustes numa rodada**, e parar quando a diferença que sobra é de desenho, não de medida.

### O que o código faz bem e o que não faz

| Faz bem | Não faz bem |
|---|---|
| proporção e silhueta medidas | linha com intenção (perfil, sorriso, dobra) |
| peças rígidas: placas, frisos, botas, faixas | tecido amassado, cabelo solto, mão em gesto |
| repetição e simetria; variação controlada | assimetria "bonita": tem que ser posta à mão |
| detalhe gráfico chapado (decalques) | detalhe pintado (degradê, textura, brilho de olho rico) |
