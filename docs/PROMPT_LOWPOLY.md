# Prompt-guia: modelagem low poly estilizada (Blender → Godot)

Como usar: copie o bloco **PROMPT** abaixo, preencha os campos `[entre colchetes]` e anexe as imagens de referência.
Um asset (ou uma família pequena de assets) por pedido. O que você não preencher, eu decido seguindo a Bíblia de Estilo.

---

## PROMPT (copiar e preencher)

```
Você é um artista 3D sênior de low poly estilizado. Modele o asset abaixo no pipeline deste projeto
(tools/blender/build_assets.py e characters.py → GLB em assets/models → Godot 4.7), seguindo
docs/PROMPT_LOWPOLY.md (Bíblia de Estilo + Processo + Checklist). Não entregue sem passar pelo checklist.

1. ASSET
- Nome do arquivo: [ex.: merchant.glb]
- Tipo: [personagem | prop | árvore/vegetação | construção]
- O que é, em uma frase: [ex.: mercador de meia-idade, turbante, capa longa nas costas]
- Função no jogo: [ex.: NPC parado na vila, visto a ~6 m pela câmera em 3ª pessoa]

2. REFERÊNCIA
- Imagem principal (anexa): [qual imagem, qual personagem/objeto dentro dela]
- O que copiar dela: [silhueta | proporções | camadas de roupa | paleta | nível de detalhe]
- O que NÃO copiar: [ex.: o chapéu, a cor laranja]
- Estilo de superfície: [A: facetado cor chapada (img NPCs) | B: toon 2 faixas (img cavaleira) |
  C: chanfrado com gradiente (img props) | D: copa em blocos + cartões de folha (img árvores)]

3. PROPORÇÕES E MEDIDAS
- Altura total: [ex.: 1,80 m]   Cabeças de altura: [ex.: 7]
- Largura dos ombros / do objeto: [ex.: 0,48 m]
- Exageros desejados: [ex.: mãos e botas 15% maiores, cintura fina]
- Medidas que precisam ser exatas: [ex.: capa termina 8 cm acima do chão]

4. PEÇAS E CAMADAS (de dentro para fora)
- [ex.: 1 corpo  2 túnica até o joelho  3 cinto + 2 bolsas  4 mantelete nos ombros  5 capa]
- Detalhes obrigatórios: [ex.: barra dupla na túnica, fivela, 3 botões, braçadeiras, barba]
- Detalhes proibidos: [ex.: nada de armas]

5. CORES
- Principal (60%): [hex ou nome]   Secundária (30%): [hex]   Acento (10%): [hex]
- Materiais especiais: [metal | emissivo | vidro | nenhum]

6. TÉCNICO
- Orçamento de triângulos: [ex.: até 2 500]
- Pivôs/animação: [manter LegL, LegR, Body, Head, ArmL, ArmR | estático]
- Colisão / escala no Godot: [ex.: 1 unidade = 1 m, origem no chão]

7. ENTREGA
- Renders de conferência: [frente, costas, 3/4, close do rosto] lado a lado com a referência
- Critério de pronto: [ex.: silhueta reconhecível em preto; ninguém confunde com o ancião]
- Quantas rodadas de ajuste antes de me mostrar: [ex.: 2]
```

### Prompt de correção (para as rodadas seguintes)

```
Ajuste [asset]. Use o render [frente/costas/3-4] como base.
- [Peça]: [o que está errado] → [como deve ficar, com medida]. Ex.: "capa: larga demais → 0,52 m na barra"
- [Peça]: ...
Não mexa em: [o que já está bom].
```

Feedback com medida ("barra 4 cm, 25% mais escura") funciona muito melhor que adjetivo ("mais bonito").

---

## BÍBLIA DE ESTILO

### 1. Princípios
1. **Silhueta primeiro.** O asset tem de ser reconhecível preenchido de preto. Detalhe que não muda a silhueta nem cria uma faixa de cor é descartado.
2. **Grande → médio → pequeno.** 70% formas grandes, 25% médias, 5% pequenas. Detalhes pequenos ficam agrupados (cinto, gola, punhos), com áreas de descanso entre eles.
3. **Cor por face, não por textura.** Cada detalhe é geometria com cor chapada. Sem ruído, sem normal map.
4. **Facetas intencionais.** Shading flat. Cada plano precisa ter tamanho parecido com os vizinhos; nada de faces finas e compridas nem triângulos degenerados.
5. **Nada flutua, nada atravessa.** Camadas se apoiam umas nas outras com folga de 1–1,5 cm.

### 2. Personagens (ref.: NPCs "Trades & Tales" e cavaleira toon)
| Item | Valor |
|---|---|
| Altura | 1,75–1,85 m, 7 cabeças (heroico estilizado: 6–6,5) |
| Cabeça | 0,25 m alt. × 0,15 larg. (~7 alturas no corpo); olhos na metade; nariz e boca nos terços |
| Ombros | 2 a 2,2 larguras de cabeça; cintura 1,3 |
| Pernas | 48–50% da altura; joelho marcado por 1 loop |
| Mãos | 10–15% maiores que o real; luva-mitene + polegar separado |
| Botas | 15% maiores; cano com dobra/punho de 3–4 cm |
| Membros | prismas de 6 lados (8 só no tronco); afunilam 20–30% |
| Triângulos | 2 500–4 000 por personagem (mercadora: 3 574; o rosto custa ~200) |

Detalhes que definem o nível da referência:
- **Barras/debruns** em toda borda de tecido: faixa de 3–5 cm, 25–30% mais escura (ou mais clara) que o tecido, feita como loop de faces próprio. Túnicas levam barra dupla.
- **Camadas**: corpo → túnica → cinto → mantelete/capuz → capa. Cada camada 1,5–2 cm de espessura, 1–1,5 cm afastada da anterior.
- **Capa**: do ombro até 5–10 cm do chão, abre 15–20% em direção à barra, 3–4 dobras verticais largas, borda de 5–6 cm em cor de contraste.
- **Cinto**: 5–6 cm de altura, fivela saliente 1 cm, 1–3 bolsas assimétricas, tira pendente.
- **Punhos/braçadeiras**: 8–10 cm, 1 cm mais grossos que o antebraço.
- **Cabelo**: mechas facetadas (`hair_locks` em `tools/blender/head.py`): tiras de seção em losango com aresta viva no meio, que seguem o crânio e terminam em ponta. Use 10–15 mechas largas (5–6 cm) **sobrepostas**, formando uma massa contínua; comprimentos alternados nas pontas e uma base mais escura colada ao crânio para dar profundidade. Nunca cascas lisas (viram capacete) nem mechas finas separadas (viram espaguete).
- **Barba**: cunha facetada cobrindo a mandíbula, com 1–2 pontas extras; bigode em 2 cunhas caídas.
- **Rosto "desenhado"** (`tools/blender/head.py`): ~10 colunas × 8 anéis triangulados, shading flat, planos grandes de testa, maçã, mandíbula e queixo. Feições são formas gráficas, nunca anatomia realista:
  - olho = amêndoa escura (2,3 × 1 cm) dentro da órbita + 1 ponto de brilho; sem esclera branca nem íris;
  - sobrancelha = cunha grossa por dentro, fina por fora, cor do cabelo;
  - nariz = cunha com 2 faces laterais e base plana;
  - boca = traço curto 1 tom acima da pele + sombra do lábio inferior; **nunca lábios modelados**;
  - orelha = cunha simples inclinada para trás.
- Confira o rosto com `tools/blender/face_compare.py` + `tools/face_sheet.py` (referência ao lado e linhas de proporção humana).
- **Assimetria**: pelo menos 1 elemento (alça cruzada, bolsa, ombreira) quebra a simetria.

### 3. Props (ref.: folha de props medieval)
- Proporção "gordinha": espessuras 1,5–2× o real (tábuas 4–6 cm, aros de barril 3 cm, cabos 5 cm).
- **Chanfro em toda aresta visível**: 1–2 cm, 1 segmento. O chanfro recebe tom mais claro (pega luz).
- Cilindros: 8 lados (pequenos), 10–12 (barris, poços). Nunca 16+.
- Tábuas com frestas de 1 cm e alturas/ângulos variando 2–5°; pedras com 5–9 faces irregulares.
- 50–600 triângulos; 2–4 cores por prop + 1 acento (metal, corda, emissivo).
- Leve afunilamento/inclinação (2–4°) para tirar o ar de "CAD".

### 4. Árvores e vegetação (ref.: árvores pintadas à mão)
- Tronco: 6 lados, base alargada 1,6–2× com 3–5 raízes; 1–2 curvas em S; galho quebrado ocasional.
- Copa: 3–7 blocos (icosfera subdiv. 1–2 deformada) sobrepostos 20–30%, tamanhos desiguais, o maior fora do centro.
- Gradiente vertical: base da copa 25–35% mais escura e mais fria, topo mais claro e mais quente.
- Pinheiros: 3–5 camadas cônicas com borda irregular, cada uma girada 20–40°.
- Opcional (para chegar mais perto da referência): cartões de folha com alpha na borda dos blocos, com normais transferidas de uma esfera para sombrear como volume único.
- 300–1 200 triângulos. Variações por cor (verde, outono, rosa) reutilizando a malha.

### 5. Cor
- Regra 60/30/10 (principal / neutro de apoio como couro-marrom / acento).
- Cada material tem 3 tons: base, sombra (valor −15 a −20%, matiz puxando p/ frio), luz (valor +10%, matiz p/ quente).
- Saturação 55–80%; nunca preto puro nem branco puro (mín. valor 8%, máx. 92%).
- Materiais vizinhos diferem em **valor** (≥15%), não só em matiz.
- Paleta única do projeto em textura de paleta ou cor de vértice → 1 material por asset, menos draw calls.
- Roughness 0,8–1,0 em tudo; metal só em fivelas/lâminas (metallic 0,8, rough 0,35).

### 6. Shader e luz no Godot
- Toon de 2 faixas (luz/sombra) com corte suave de ~5%, sombra tingida de azul-roxo, sem especular (exceto metal).
- Rim light fraco opcional; outline opcional (casco invertido, 1–1,5 cm) só em personagens.
- Luz principal quente 45° de cima, ambiente frio a 30–40%.

---

## PROCESSO (o que eu faço a cada pedido)
1. **Leitura da referência**: listo proporções medidas na imagem (em cabeças/percentuais), camadas e paleta extraída.
2. **Blockout**: só formas grandes, cor única. Render de silhueta preto sobre branco ao lado da referência.
3. **Formas médias**: camadas de roupa, chanfros, blocos de copa.
4. **Detalhes pequenos**: barras, fivelas, bolsas, botões.
5. **Cor**: paleta 3 tons por material, conferência de valor em tons de cinza.
6. **Render de conferência** (frente, costas, 3/4, close) com `tools/blender/preview_*.py`, comparação lado a lado, lista de diferenças e correção.
7. **Export + teste no Godot** (smoke test headless) e contagem de triângulos.

## CHECKLIST DE ACEITE
- [ ] Silhueta legível em preto, distinta dos outros assets
- [ ] Proporções dentro de ±5% do pedido
- [ ] Toda borda de tecido com barra; toda aresta de prop com chanfro
- [ ] Nenhuma peça flutuando ou atravessando
- [ ] 3 tons por material, vizinhos separados em valor
- [ ] Dentro do orçamento de triângulos
- [ ] Pivôs e origem corretos; importa e roda no Godot sem erro

## Limites honestos
- Textura pintada à mão (árvores e props das referências) não sai de script com a mesma qualidade; o equivalente viável é gradiente por vértice + cor por face + cartões de folha. Pintura real exigiria você ou um artista no Blender/Substance.
- Rostos estilo anime (cavaleira) dependem de textura de olhos desenhada; posso gerar uma simples, mas não no nível de um ilustrador.
