---
name: perf-profile
description: "Procura gargalos de desempenho no Ecos de Valdoria (cliente e servidor dedicado): _process/_physics_process caros, alocação por frame, buscas em grupo, partículas e luzes, tamanho e frequência dos snapshots de rede. Mede de verdade com --netstats e com os monitores do Godot quando possível, e separa o que foi medido do que é suspeita. Use quando o jogo ou o servidor estiver lento, antes de aumentar a horda ou o número de jogadores, ou quando pedirem perfil de desempenho."
argument-hint: "[cliente | servidor | horda | cidade | rede | caminho/do/script.gd]"
license: MIT
metadata:
  adapted-from: https://github.com/Donchitos/Claude-Code-Game-Studios (.claude/skills/perf-profile)
  version: "1.0.0"
---

# Perf Profile (Ecos de Valdoria)

## Regras

- **Medido x suspeito.** Ler código acha candidatos; só medição confirma. Todo achado
  leva a marca `MEDIDO` (com o número e como foi medido) ou `SUSPEITA` (com o motivo).
- **Sem meta combinada, não há "dentro da meta".** O projeto não tem orçamento de
  desempenho escrito. Pergunte ao usuário (ex.: cliente a 60 fps, servidor aguentando
  8 jogadores (`MAX_PLAYERS`) e uma horda cheia). Sem resposta, a coluna de meta fica
  `SEM META — folga não avaliada`. Nunca compare com um 16,67 ms que ninguém escolheu.
- Não otimize durante o perfil. Proponha; o usuário decide.

## Fase 1: Escopo

| Escopo | Onde olhar primeiro |
|---|---|
| `cliente` | `scripts/player/`, `scripts/ui/` (26 scripts, vários com `_process`), `scripts/fx.gd`, `scripts/world/` |
| `servidor` | `scripts/autoload/network.gd`, `scripts/autoload/lobby.gd`, IA em `scripts/enemies/enemy.gd` |
| `horda` | `scripts/survival/survival_mode.gd`, `auto_weapons.gd`, `xp_gem.gd`, `horde_events.gd`: muitos inimigos, gemas e projéteis ao mesmo tempo |
| `cidade` | `scripts/colony/`: torres (`tower_shot.gd`), soldados, construções e animais |
| `rede` | `network.gd` e `lobby.gd`: `SEND_RATE` (20/s), `SNAP_RATE`, `STATE_RATE`, `SNAP_STRIDE` (10 valores por inimigo) |

## Fase 2: Medir

Primeiro o que dá para medir sem o usuário jogar:

**Servidor e rede:** o servidor imprime a cada 5 s com `--netstats`
`[server] N online, N inimigos, N fps, N snapshots/s`. Suba um servidor com uma horda
rápida e 2 clientes de teste (mesmos comandos da skill `smoke-check`, passo 3, com
`--netstats` no servidor e porta própria) e colete essas linhas durante a partida.
Guarde o PID e encerre só o seu servidor (`kill $S`), nunca todos os Godot.

Banda estimada por cliente = snapshots/s × inimigos visíveis × `SNAP_STRIDE` × bytes
por valor. Mostre a conta e diga que é estimativa.

**Cliente:** cena headless não renderiza, então fps de render só vale com janela.
Para tempos de script, um teste temporário (no scratchpad, não no repositório) pode ler
`Performance.get_monitor(Performance.TIME_PROCESS)`, `TIME_PHYSICS_PROCESS`,
`OBJECT_NODE_COUNT` e `MEMORY_STATIC` durante uma horda. Fps, draw calls e memória de
vídeo com o jogo rodando de verdade: peça ao usuário para abrir o jogo no editor
(Depurador → Monitores / Profiler) e informar os números, ou use a ferramenta de
depuração do MCP do Godot se estiver conectada.

O que não deu para medir fica `NÃO MEDIDO`, explicitamente.

## Fase 3: Ler o código

Procure, citando `arquivo:linha`:

- `_process` / `_physics_process` (há ~43 no projeto): o que roda todo frame e
  poderia rodar por timer ou por sinal.
- `get_tree().get_nodes_in_group(...)`, `get_first_node_in_group`, `find_child` e
  `get_node` com caminho dentro de laços por frame, principalmente por inimigo.
- Laços aninhados inimigo × inimigo ou inimigo × projétil (busca do "mais próximo" em
  `auto_weapons.gd`, torres da cidade, IA).
- `instantiate()` / `queue_free()` em massa por segundo (gemas de XP, projéteis,
  partículas, números de dano) sem reaproveitamento.
- Strings montadas por frame (`%`, `str()`) em HUD e placar, `Label.text` atualizado
  mesmo sem mudança.
- Materiais e malhas criados em código a cada instância, em vez de compartilhados.
- `GPUParticles3D`/`OmniLight3D` com sombra por inimigo ou por projétil.
- Rede: RPC por inimigo em vez de snapshot agrupado, envio para todos os peers de
  dados que só um precisa, `reliable` em mensagens frequentes.
- Save: `JSON.stringify` grande no thread principal (autosave a cada 2 min no
  multiplayer).

## Fase 4: Relatório

```
## Perf Profile: [escopo], [data]

### Metas
| Métrica | Meta | Medido | Status |
| Fps do servidor com horda cheia | [do usuário ou SEM META] | 58 fps (--netstats, 2 clientes) | OK / ACIMA / SEM META |
| Snapshots/s | | | |
| Fps do cliente | | NÃO MEDIDO | |

### Pontos quentes
| # | Local (arquivo:linha) | Problema | MEDIDO/SUSPEITA | Ganho estimado | Esforço (P/M/G) |

### Recomendações em ordem
1. **[título]**: local, ganho esperado, risco, como fazer

### Ganhos rápidos (< 1 h)
### Precisa de medição em jogo para confirmar
```

Feche com os 3 pontos mais quentes e a próxima ação. Para itens de esforço M ou G,
pergunte ao usuário: otimizar agora, reduzir o escopo (menos inimigos, menos
partículas) ou aceitar e anotar. Salve o relatório em
`docs/desempenho/<escopo>-<AAAA-MM-DD>.md` só se o usuário quiser; manter os relatórios
no mesmo lugar é o que permite comparar uma medição com a anterior.

Depois de qualquer otimização aplicada, rode a skill `smoke-check` (a lógica dos
testes de rede depende de tempos e estados que otimizações costumam mexer).
