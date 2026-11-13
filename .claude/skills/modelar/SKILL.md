---
name: modelar
description: "Workflow completo para criar ou refazer um modelo 3D do Ecos de Valdoria no Blender com as melhores práticas do projeto: worktree própria, brief curto, build filtrado, renders small, comparação com o guia de estilo, smoke test e PR. Só roda quando o usuário chama /modelar."
argument-hint: "<asset> [fase 1|2|3|4 | ajuste] [o que mudar]"
disable-model-invocation: true
license: MIT
metadata:
  version: "1.0.0"
---

# /modelar

Pedido: `$ARGUMENTS`

Siga os passos em ordem, sem pedir confirmação entre eles. Só pare para perguntar quando o
pedido for ambíguo (asset desconhecido, fase impossível) ou exigir quebrar algo que o código usa.

## 0. Interpretar o pedido

- **asset**: primeira palavra (`knight`, `goblin`, `elder`, `merchant`, `slime`, `house`, `chest`…
  ou um nome novo, que vira um `build_<nome>()` novo).
- **modo**:
  - `fase 1` — corpo-base contínuo (loft de anéis), proporção, silhueta, pivôs `KneeL/KneeR/ElbowL/ElbowR`.
  - `fase 2` — armadura/roupa em camadas, cinto, frisos, capa.
  - `fase 3` — cabeça, elmo, rosto, cabelo/barba, mãos.
  - `fase 4` — visual no jogo (luz, ambiente, tonemap no Godot); não usa Blender, pule 4–5 e
    compare com prints do jogo.
  - `ajuste` — mudança pontual descrita no resto do pedido (cor, tamanho, uma peça).
  - Sem modo: personagem que ainda é pilha de primitivas → `fase 1`; o resto → `ajuste`.
- **o que mudar**: o texto restante. Junte com os problemas que você mesmo vê no baseline.

**Modelo**: fases 1–3 e assets novos dependem de julgamento visual. Se estiver rodando em
Sonnet ou Haiku, diga em uma linha que Opus é o recomendado para isso e continue. `ajuste` vai bem em Sonnet.

## 1. Preparar a worktree (outras sessões usam o mesmo checkout)

```bash
cd C:/Games/godot-3d && git fetch -q origin
git worktree add -b modelo-<asset>-<modo> ../godot-3d-<asset> origin/main   # se já existir, reutilize
```

Trabalhe **só dentro de `../godot-3d-<asset>`**: os scripts de build e preview leem e gravam
relativo à própria pasta. Rode `--import` do Godot na worktree antes do smoke test (passo 6).

## 2. Contexto mínimo

1. `.claude/skills/references/godot-3d-pipeline.md` (comandos, convenções, orçamentos).
2. Personagens: `tools/blender/STYLE.md`, só as seções da fase. **Não abra as imagens de
   `refs/` agora.**
3. Ache a função do asset com `grep -n "^def build_<asset>\|^def " tools/blender/*.py` e leia só
   esse trecho e os helpers que ela usa. Nunca leia `characters.py` inteiro.
4. `grep -rn` dos nomes de peças e pivôs do asset em `scripts/` (são API).
5. Carregue no máximo 2–3 skills do roteamento (ex.: fase 1 → `character-artist` + `stylized-style`;
   fase 2 → `character-archetypes` + `materials`; prop → `prop-artist` + `lowpoly-style`).
   Não carregue `blender-director` no modo `ajuste`.

## 3. Brief no chat (até 6 linhas)

```markdown
**Asset:** <nome> — <modo>   **Orçamento:** <tris> tris, <n> materiais
**Hoje:** <2–3 problemas principais>
**Vou mudar:** <lista curta>   **Nomes mantidos:** <peças usadas por scripts/>
**Skills:** <2–3>
```

Siga em frente sem esperar resposta.

## 4. Baseline (uma vez)

Se o GLB já existe: render `small` normal → `<scratchpad>/<asset>_antes.png`, leia uma vez e
anote os problemas. Guarde o arquivo para o antes/depois; não leia de novo.

## 5. Loop de iteração (máx. 3 rodadas; 4 nas fases 1–3)

Cada rodada:
1. Edite a função do asset (e helpers novos, ex.: gerador de corpo-base reutilizável na fase 1).
2. Build filtrado:
   ```bash
   B="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
   ASSETS=<asset> "$B" --background --factory-startup --python tools/blender/build_assets.py > <scratchpad>/build.log 2>&1
   grep -E "^EXPORT|Error|Traceback" <scratchpad>/build.log   # sem EXPORT? tail -n 40 no log
   ```
3. Render `small` (+ `silhouette small` quando a fase é de forma) e leia **uma** imagem por vez.
4. Lista de falhas contra o checklist do STYLE.md / da fase; corrija **todas** na próxima rodada.

Pare antes do limite quando o checklist da fase passar. Se no limite ainda não convergiu, pare,
mostre a última imagem ao usuário e pergunte o que priorizar.

## 6. Conferência final

1. Render em tamanho cheio (sem `small`), normal e `silhouette`; `preview_closeup.py` nas fases 2–3.
2. Agora, e só agora, abra **uma** imagem de referência relevante em
   `C:/Games/godot-3d/tools/blender/refs/` e compare com o checklist do STYLE.md (seção 8).
   Corrija o que for grave (no máximo uma rodada extra).
3. `TRIS` e nº de materiais dentro do orçamento; nomes de `scripts/` ainda batem.
4. Mostre ao usuário o antes e o depois (envie as imagens se houver ferramenta para isso).
5. Rode a skill `smoke-check` no modo `rapido` dentro da worktree.

## 7. Entregar

1. Suba o patch de `config/version` em `project.godot` (o jogo tem auto update; PRs de modelo sobem a versão).
   Se outra branch aberta já subiu o mesmo número, suba de novo ao atualizar com o `main`.
2. Commit com o que mudou e tris antes → depois; push; PR para `main`. **Sem merge** até o usuário pedir.
3. Resposta final curta: o que mudou, tris/materiais antes → depois, veredito do smoke-check,
   link do PR e a sugestão do próximo passo (ex.: `/modelar knight fase 2`).
4. Depois do merge (quando pedido): apagar a branch local e remota e a worktree.

## Regras de economia

- Saída do Blender e do Godot sempre em log + `grep`; nunca a saída inteira no contexto.
- Nunca leia a mesma imagem duas vezes nem releia arquivo já lido; localize com `grep -n`.
- Junte todas as correções de uma rodada; nada de rodada para um detalhe só.
- Imagens de referência: no máximo uma leitura por sessão, na conferência final.
