# Tela de criação de herói refeita (versão A, tema escuro)

Mockup aprovado: https://claude.ai/artifact/QMceNMwcbppqf754CNpQs5 (aba "A · Palco central").

## Por quê

A tela atual (`scripts/ui/char_create.gd`) é um painel de 1100 px centrado com cartões de texto. Os problemas
apontados pelo usuário:

- a prévia 3D é um quadro de 300×330 ao lado do texto e quase não aparece;
- as habilidades mostram só a tecla, embora 15 das 17 já tenham arte em `assets/ui/skills/<id>.png`;
- o nome do herói (online) fica solto no topo e não mostra como vai aparecer no jogo;
- cada classe tem uma frase só: sem ícone, papel no grupo, dificuldade nem história;
- os quatro cartões numa fileira não cabem as classes que vão chegar.

## Objetivos

- O herói grande no centro da tela, girável, com o brilho do pedestal na cor da classe.
- Cada classe com **emblema próprio**, reaproveitável depois em placa de nome, grupo e chat.
- Ficha da classe com história, papel, dificuldade, perfil em barras, arma e atributo principal.
- Habilidades como ícones (arte pintada; sem arte, o desenho do `IconPainter`), com detalhe ao passar o mouse
  ou clicar.
- Nome com contador, validação ao vivo e placa de nome sobre o herói como no jogo.
- Lista de classes que cresce sem refazer o layout.

## Fora do escopo

- Mostrar o emblema no jogo (placa de nome, grupo, chat): fica para um próximo PR, que já vai ter o componente.
- Roupa própria de cada classe na prévia (hoje as quatro vestem a roupa inicial; só a arma muda).
- Arte pintada de Lança de Luz e Julgamento de Luz (seguem no `IconPainter` até haver PNG).
- Renomear "Healer". A migração para o grimório: esta tela fica no tema escuro, por decisão do usuário.
- Regras de criação (`CharRules`, `CharacterService`, rede): nada muda.

## Layout (1600×900 de referência, tela inteira, sem painel central)

```
┌──────┬──────────────────────────┬───────────────────────────────┐
│CLASSES│ Crie seu herói           │ [emblema] MAGO                 │
│ [⛨]   │ APARÊNCIA     Seu nome   │ Distância · Dano em área · ◆◆◆ │
│ Guerr.│ [Masc][Fem]  ⛨ Nv1·Mago  │ história (EB Garamond)         │
│ [⛨]   │ CABELO                   │ ── ARMA E ATRIBUTOS ──         │
│ Arq.  │ [🙂][🙂]     (herói 3D)  │ Cajado · Inteligência · inicial│
│ [⛨]●  │ Curto Pent.              │ Dano ▮▮▮▮▮  Resistência ▮      │
│ Mago  │ [🙂][🙂]   pedestal      │ ── HABILIDADES ──              │
│ [⛨]   │ Franja Rasp. ⟲ arraste ⟳ │ [1][2][3][4]                   │
│ Healer│                          │ detalhe da habilidade          │
├──────┴──────────────────────────┴───────────────────────────────┤
│ [Nome do herói   0/16 ⚄]  regra/erro          [Voltar] [Começar]│
└──────────────────────────────────────────────────────────────────┘
```

- **Coluna de classes (esquerda, ~140 px):** um botão por id de `CharRules.CLASS_IDS`: emblema de 46 px e nome
  embaixo; o escolhido ganha borda e fundo na cor da classe. Com mais de 8 classes, a coluna rola.
  Não há espaços "Em breve" no jogo (só no mockup).
- **Aparência (coluna estreita à esquerda do herói, ~180 px):** sexo em dois botões e, embaixo, os
  penteados do corpo escolhido como **miniaturas do rosto** em grade de 2 colunas (~80 px cada, nome
  pequeno embaixo; o escolhido com borda dourada). Substitui a linha de botões de texto do 0.49.0; a regra
  continua a de `HairStyles` (trocar o sexo volta ao penteado padrão do corpo). Clicar troca o cabelo
  também no herói grande.
- **Palco (centro):** título "Crie seu herói" e subtítulo; `CharPreview` grande (~620×660), arrastar gira
  (como hoje), mais os botões ⟲ ⟳; pedestal com brilho na cor da classe. Placa de nome sobre a cabeça: nome
  digitado (ou "Seu nome"), emblema pequeno + "Nv 1 · Classe", barra de vida. No solo não há nome: a placa
  mostra só a classe.
- **Ficha (direita, ~700 px):** emblema de 72 px, nome da classe na cor dela, selos de papel e de estilo,
  dificuldade em losangos (1 a 3); história; linha "arma · escala com atributo · começa com arma inicial";
  perfil em 5 barras de 5 pontos (Dano, Resistência, Alcance, Mobilidade, Suporte); fileira de habilidades
  em ordem de tecla com a tecla no canto, "Nv N" quando liberam depois do nível 1, e a ultimate com borda
  dourada; caixa de detalhe da habilidade sob a mão (nome, tecla, nível, recarga e mana, descrição).
- **Rodapé:** campo do nome (online) com contador `n/16`, botão de dado que sorteia um nome, e a regra ou o
  erro em linha embaixo (mesmas regras de `CharacterService.clean_name`; a disponibilidade só se sabe ao criar).
  O aviso do personagem antigo continua, como faixa acima do rodapé. Botões "Voltar" e "Começar a jornada".

## Dados

`data/balance/classes.json` ganha, por classe (tudo opcional, com padrão vazio):

| Campo | Exemplo | Uso |
|---|---|---|
| `lore` | texto de 2 a 3 frases | história na ficha |
| `role`, `style` | "Distância", "Dano em área" | os dois selos |
| `difficulty` | 1 a 3 | losangos |
| `profile` | `{"dano":5,"resistencia":1,"alcance":4,"mobilidade":2,"suporte":1}` | barras |
| `emblem` | "mage" | qual desenho do `ClassEmblem` |

Os textos e números iniciais são os do mockup (rascunho do Claude); o usuário revisa direto no JSON.
A tabela já viaja pela rede com o balanceamento, então o servidor e o cliente veem o mesmo.

## Peças novas

- **`ClassEmblem`** (`scripts/ui/class_emblem.gd`): `Control` que desenha por código, como o `IconPainter`
  (vetorial, qualquer tamanho): escudo com borda dourada e o símbolo da classe na cor dela (espada, arco,
  cajado com estrela, sol). Uma função estática `draw(ci, kind, color, rect)` para quem desenha sem nó
  (placa de nome, futuro). Classe nova = um símbolo novo e o campo `emblem`.
- **Miniatura de penteado:** renderizada no próprio jogo, não pintada. Ao abrir a tela (e ao trocar o sexo),
  um `CharPreview` pequeno por penteado tira a foto com a câmera fechada no rosto, virado ~45° para mostrar
  rabo de cavalo e marias (no mockup: câmera em (0; 1,70; 1,30) olhando (0; 1,64; 0), giro −0,75). Depois da
  foto o viewport para de atualizar (`UPDATE_ONCE`) para não custar nada. Penteado novo em `HairStyles`
  aparece sozinho, sem arte nova.
- **Ícone de habilidade:** reaproveita `ItemSlot.skill_art()` com o `IconPainter` de reserva (sem código novo
  de carga).

## Comportamento que se mantém

- API usada pelos testes: `select_class()`, `select_body()`, `kit_names()`, `enter_world`, `finished`, e o
  fluxo de "Começar" (`choose_class` no solo, `Network.char_create` online), "Voltar" e Esc.
- Argumentos de captura `--class=`, `--body=`, `--hair=`, `--shot=`.

## Para conferir na implementação

- Ao gerar as miniaturas com `CharPreview`, o console mostrou várias vezes
  `The object does not have any 'meta' values with the key 'ponytail'` em `KnightAnim.sway_ponytail`
  (`knight_anim.gd:252`). Pode acontecer também na tela atual ao trocar de corpo ou penteado. Ver e corrigir.
- Na captura com `--hair=f_marias`, o botão aceso era "Rabo de cavalo" enquanto o herói mostrava marias.
  Ver se o botão escolhido segue o `--hair` (com as miniaturas, o escolhido tem que bater com o herói).

## Verificação

- `/smoke-check` (o smoke test passa pela tela em `_test_char_create`).
- Teste unitário: toda classe de `CLASS_IDS` tem `emblem` conhecido pelo `ClassEmblem` e `profile` com valores
  de 0 a 5.
- Capturas das quatro classes (m e f) com `--shot`, comparadas com o mockup, mais uma a 1280×720 para ver se
  nada corta.
- Subir `config/version` (o PR muda código de jogo).

## Abordagens consideradas

- **A · Palco central** (escolhida): tudo numa tela, herói em destaque, coluna de classes que cresce.
- **B · Passo a passo:** Classe, Aparência, Nome em etapas; mais cliques e mais telas para manter.
- **C · Códex:** livro aberto; combina com o grimório, mas é a mais trabalhosa e deixa o herói menor.
- Tema: o pergaminho (grimório) foi mostrado lado a lado; o usuário escolheu o tema escuro.
- Emblema desenhado por código e não em PNG: vale em qualquer tamanho e combina com o `IconPainter`;
  um PNG pintado pode substituir depois sem mudar a tela.

## Decisões do Claude (para conferir)

- Classes "Em breve" não aparecem no jogo.
- Perfil em 5 barras com números escritos à mão no JSON, não calculados dos status.
- Botão de dado com uma lista curta de nomes de fantasia no cliente.
- Placa de nome no solo mostra só a classe.
