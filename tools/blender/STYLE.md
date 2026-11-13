# Guia de estilo dos personagens (alvo de qualidade low-poly)

Alvo visual para refazer os personagens do jogo. Referências locais (fora do git, imagens de um
pacote comercial — só para olhar, nunca copiar design, nome ou paleta exata de um personagem):

- `C:/Games/godot-3d/tools/blender/refs/estilo-cavaleiros.webp` — três cavaleiros de armadura
- `C:/Games/godot-3d/tools/blender/refs/estilo-plebeus.webp` — quatro plebeus/soldados de túnica

**Leia este texto em vez das imagens.** Abra as imagens só na comparação final de uma fase
(uma vez), não a cada rodada.

## 1. Construção (a maior diferença para os modelos atuais)

- Corpo e membros são **malhas contínuas** feitas de anéis de seção transversal ligados (loft),
  não pilhas de caixas e cilindros. Cada membro afina de forma natural:
  ombro → bíceps → cotovelo (estreita) → antebraço (alarga levemente) → pulso;
  quadril → coxa → joelho (estreita) → panturrilha (volume atrás) → tornozelo.
- Seções com 6–8 lados, levemente achatadas (não circulares): o tronco é mais largo que fundo,
  a coxa é mais funda que larga.
- **Sombreamento flat** com facetas visíveis e planas; nenhuma subdivisão.
- Peças de armadura e roupa são **cascas** um pouco maiores que o corpo (offset de 1–3 cm)
  com espessura visível na borda, não placas de espessura zero.
- Bordas importantes com **chanfro de 1 segmento** (placas, cinto, botas, elmo).

## 2. Proporções

- ~7,5 cabeças de altura; personagem humano 1,80–1,90 m, pés em Z=0, frente = -Y.
- Heroico estilizado: ombros largos (~2,3 cabeças com ombreiras), cintura visivelmente mais
  fina que o peito, quadril um pouco mais estreito que os ombros.
- Mãos e pés ~10–15% maiores que o real; mãos em **punho relaxado** com dedos sugeridos
  (2–3 blocos de dedo + polegar), luvas com punho largo.
- Pernas longas e retas, joelhos legíveis; postura levemente aberta (pés afastados ~ largura
  do quadril), braços afastados do corpo uns 10–15°.

## 3. Cavaleiros (armadura)

- **Elmo**: formas facetadas com crista central, viseira em degrau com fenda dos olhos;
  penacho como 3–5 lâminas finas facetadas em leque, cor forte (vermelho, branco).
- **Ombreiras** grandes, em 2–3 lâminas sobrepostas, inclinadas para fora; passam da linha do ombro.
- **Peitoral** com volume (peito saltado, quina central vertical) e gola em degrau no pescoço.
- **Cintura**: cinto marrom com fivela metálica, saiote de 2–4 placas sobrepostas (faulds/tassets),
  às vezes com tiras de couro penduradas.
- **Braços/pernas**: braçais e grevas como cascas cônicas; cotoveleiras e joelheiras pontudas
  (asa lateral); manoplas escuras.
- **Botas**: sabatons em 2–3 placas segmentadas, bico levemente pontudo.
- **Capa** atrás, caindo dos ombros até a panturrilha, com dobras largas (3–4 facetas verticais).
- **Frisos**: linhas finas de cor contrastante (dourado, laranja, branco) contornando placas —
  peças finas separadas ou faixa de faces com material próprio.

## 4. Plebeus/soldados (tecido)

- Túnica até meio da coxa com barra recortada ou assimétrica; **cores divididas** (metade de
  cada cor, estilo heráldico) e tons dessaturados (vermelho, verde-musgo, azul, ocre, marrom).
- Alça diagonal de couro atravessando o peito, cinto com fivela e ponta pendente.
- Mangas que alargam no antebraço; braçadeiras de couro ou metal.
- Botas de cano alto com dobra no topo; calça justa.
- Capuz com volume atrás da cabeça e borda grossa; chapéu de ferro (kettle hat) com aba larga.
- **Rosto**: maçãs e queixo marcados, nariz em cunha, sobrancelha saliente; barba, bigode e cabelo
  como volumes facetados próprios (não pintados); olhos como pequenas faces escuras.

## 5. Cor e material

- Cores chapadas por material, 2 tons por superfície (base + sombra/realce em peças separadas
  quando ajuda a ler a forma). Metal: cinza-azulado médio, roughness média, metallic alto mas
  sem espelhar. Couro: marrom quente. Tecidos: dessaturados.
- Contraste vem de **valor** (claro × escuro) antes de matiz: armadura clara, manoplas e cinto
  escuros, frisos claros/saturados.
- Até 20 materiais por personagem; reutilize os mesmos materiais entre peças.

## 6. Orçamento

- Personagem completo: **4–6k tris**. Corpo-base ~1,5k; armadura/roupa ~2,5k; cabeça e mãos ~1k.
- Junte num objeto só as peças com o mesmo pivô e material que nunca são tingidas/ocultadas
  separadamente (ver nomes usados em `scripts/player/knight_look.gd`).

## 7. Esqueleto de pivôs

Pivôs atuais (`LegL/LegR/Body/Head/ArmL/ArmR`) continuam. Os personagens novos ganham
`KneeL/KneeR` (filhos de `LegL/LegR`) e `ElbowL/ElbowR` (filhos de `ArmL/ArmR`), posicionados
na articulação; malhas abaixo do joelho/cotovelo ficam penduradas neles.

## 8. Checklist visual (comparação final de cada fase)

- [ ] Silhueta em preto lê "cavaleiro"/"plebeu" sem detalhes, com ombros, cintura e capa claros
- [ ] Membros afinam e têm joelho/cotovelo visíveis; nada de cilindro reto
- [ ] Armadura tem camadas sobrepostas e espessura de borda
- [ ] Valores: claro/escuro separam metal, couro e tecido a distância
- [ ] Mãos em punho e pés robustos
- [ ] Tris e materiais dentro do orçamento
