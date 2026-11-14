---
name: smoke-check
description: "Roda localmente os mesmos testes que o CI do Ecos de Valdoria roda antes do deploy (import, unitários, simulação da economia da cidade, smoke test de gameplay, Defesa da Cidade, multiplayer da Horda e da cidade em grupo) e entrega um veredito PASSOU/FALHOU/NÃO RODOU por teste. Use antes de abrir PR, antes de merge no main, depois de mexer em gameplay ou rede, ou quando pedirem 'roda os testes'."
argument-hint: "[tudo | rapido | unit | gameplay | cidade | rede]"
license: MIT
metadata:
  adapted-from: https://github.com/Donchitos/Claude-Code-Game-Studios (.claude/skills/smoke-check)
  version: "1.0.0"
---

# Smoke Check (Ecos de Valdoria)

Um push no `main` roda `.github/workflows/deploy.yml`: se os testes passam, publica o
cliente Windows (auto update) e faz o deploy do servidor. **Um teste que falha no CI
segura a release; um que passa sem ter rodado de verdade solta uma release quebrada.**
Esta skill roda os mesmos passos na máquina antes disso.

## Regras

- **NÃO RODOU não é PASSOU nem FALHOU.** Se um teste não chegou a rodar (Godot não
  achado, porta ocupada, tempo esgotado antes de imprimir resultado), registre
  `NÃO RODOU` com o motivo. O veredito geral fica `NÃO AVALIADO`, não verde.
- **Não corrija nada durante o check.** Reporte a falha com o trecho do log; o conserto
  é outra etapa, depois que o usuário decidir.
- **Nunca mate todos os Godot** (`taskkill //IM Godot*`): fecha o editor do usuário e
  jogos de outras sessões. Guarde o PID de cada processo que você abrir e encerre só
  esse (`kill $S`).
- Use uma **porta diferente** a cada execução de rede (outras sessões podem estar
  testando ao mesmo tempo). Evite 7777, que é a porta padrão do jogo.

## Preparação

```bash
G="C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe"
git branch --show-current; git status --short
```

Se a pasta for uma worktree nova ou a `.godot/` não existir, importe primeiro (o CI
também faz isso e falha em `SCRIPT ERROR`):

```bash
timeout 600 "$G" --headless --path . --import > "$TEMP/import.log" 2>&1
grep -A1 "SCRIPT ERROR" "$TEMP/import.log"   # qualquer saída aqui = FALHOU
```

## Testes

Escopo pelo argumento (padrão `tudo`): `rapido` = import + unitários + economia + gameplay;
`unit` = import + unitários; `gameplay` = import + gameplay; `cidade` = import + economia + cidade + cidade em grupo;
`rede` = import + os dois testes de multiplayer.

Rode cada um com saída em arquivo no `$TEMP` e pegue o código de saída.
Os testes imprimem `PASS  ...` / `FAIL  ...` e saem com 0 (ok) ou 1 (falhas).

**0. Unitários** (`tests/unit/run.gd`, poucos segundos): regras puras (contas, senha, banco SQLite, HTTP,
personagem, loot, balanceamento). Imprime `ok     arquivo::teste` / `FALHOU arquivo::teste` e no fim
`N testes, M falharam`; sai com 1 se algo falhar. Um erro de script dentro de um teste também conta como
falha (o runner conta os `SCRIPT ERROR`); `ERROR:` de `push_error` esperado (tag malformada, UNIQUE do SQL)
aparece no log e não é falha.

```bash
timeout 300 "$G" --headless --path . -s tests/unit/run.gd > "$TEMP/unit.log" 2>&1; echo "exit=$?"
grep -E "FALHOU|FALHA|testes," "$TEMP/unit.log"
```

**0b. Economia da cidade** (`tests/economy_sim.gd`, poucos segundos): simula 15 dias da Defesa da Cidade em
solo, com 2 e com 4 jogadores (um "jogador razoável" scriptado, só com as contas de `ColonyData`) e confere as
metas de equilíbrio da seção 18 do spec (era II entre os dias 4 e 6, era III entre 9 e 12, madeira nunca zera à
noite, madeira não acumula, pesquisas). Imprime a tabela de cada dia, `PASS`/`FAIL` por meta e no fim
`OK — 0 falha(s)`; sai com 1 se alguma meta falhar. Mexeu em custo, produção, munição, era ou pesquisa? Rode este.

```bash
timeout 120 "$G" --headless --path . --script res://tests/economy_sim.gd > "$TEMP/economy.log" 2>&1; echo "exit=$?"
grep -E "FAIL|falha" "$TEMP/economy.log"
```

**1. Gameplay** (`tests/smoke_test.gd`, ~1 a 3 min): diálogo e missões, combate,
magia, inventário e loja, save/load, chefe, morte, horta e caldeirão, Desafio da Horda,
aviso de atualização.

```bash
timeout 600 "$G" --headless --path . res://scenes/world.tscn -- --smoketest > "$TEMP/smoke.log" 2>&1; echo "exit=$?"
```

**2. Defesa da Cidade** (`tests/colony_test.gd`):

```bash
timeout 600 "$G" --headless --path . res://scenes/colony.tscn -- --colonytest > "$TEMP/colony.log" 2>&1; echo "exit=$?"
```

**3. Multiplayer da Horda** (servidor + 2 clientes, `tests/net_test.gd`). Rode em
segundo plano ou com tempo de sobra; espere o servidor dizer `ouvindo em UDP`.
O servidor precisa de **banco novo** (`--db=` num arquivo apagado antes), da **API HTTP** numa porta livre
(`--http-port=`) e de `--test` (ouro de teste das compras do net_test). Os clientes criam conta e fazem login
por `--auth-url=http://127.0.0.1:<porta-http>` (senha fixa do teste):

```bash
P=$((7800 + RANDOM % 150)); H=$((P + 1000))
DB="$TEMP/nettest_$P.db"; rm -f "$DB"
"$G" --headless --path . -- --server --port=$P --http-port=$H --db="$DB" --test --horde-round=8 --horde-pick=5 > "$TEMP/server.log" 2>&1 & S=$!
for i in $(seq 1 30); do grep -q "ouvindo em UDP" "$TEMP/server.log" && break; sleep 1; done
timeout 180 "$G" --headless --path . -- --nettest=127.0.0.1:$P --auth-url=http://127.0.0.1:$H --peers=2 --name=Ana --horde=lead --horde-pick=5 > "$TEMP/ana.log" 2>&1 & A=$!
timeout 180 "$G" --headless --path . -- --nettest=127.0.0.1:$P --auth-url=http://127.0.0.1:$H --peers=2 --name=Beto --horde=join --horde-pick=5 > "$TEMP/beto.log" 2>&1 & B=$!
wait $A; RA=$?; wait $B; RB=$?; kill $S
grep -hE "PASS|FAIL|NETTEST" "$TEMP/ana.log" "$TEMP/beto.log"; echo "exit=$(( RA | RB ))"
```

**4. Cidade em grupo** (salão + servidor + 2 clientes): igual ao 3, com outras portas (UDP e HTTP) e outro
banco novo, servidor com `--city-day=12 --city-event=caravan` (além de `--http-port`, `--db`, `--test`; o evento
forçado é o da troca com a caravana no dia 2) e clientes com
`--auth-url=...` e `--city=lead` / `--city=join` (nomes Caio e Duda, logs `city_server.log`, `caio.log`, `duda.log`).

Sem `--test` no servidor as compras do net_test falham; sem `--auth-url` (ou com a porta HTTP errada) os
clientes não conseguem logar e saem com `FAIL` de login, o que é falha do teste, não `NÃO RODOU`.
Para conferir um servidor publicado sem conta: `--nettest=<domínio>:7777 --probe` (GET `/health` + UDP).

Se o servidor não imprimir `ouvindo em UDP` em 30 s, o teste é `NÃO RODOU` (mostre o fim
de `server.log`), não FALHOU.

## O que olhar além do código de saída

- `SCRIPT ERROR` ou `ERROR:` em qualquer log, mesmo com saída 0: liste como aviso.
- Teste que saiu por `timeout` (código 124): `FALHOU (tempo esgotado)`, com as últimas
  linhas do log.
- Mudanças que nenhum teste cobre: compare `git diff --stat main...HEAD` com o que os
  testes exercitam e aponte os arquivos alterados sem cobertura (ex.: UI nova, sistema
  novo). Isso entra como aviso, não como falha.
- Mudou algo que cliente e servidor compartilham (rede, regras da Horda ou da cidade,
  itens)? Confira se `config/version` no `project.godot` subiu em relação ao `main`:
  o CI recusa publicar código novo com a versão de uma release já existente.

## Relatório

```
## Smoke Check: [branch] @ [commit curto]

| Teste | Resultado | Detalhe |
|---|---|---|
| Import | PASSOU | sem SCRIPT ERROR |
| Unitários | PASSOU | 96 testes, 0 falharam |
| Economia da cidade | PASSOU | OK — 0 falha(s) |
| Gameplay (--smoketest) | PASSOU | 74 PASS, 0 FAIL |
| Defesa da Cidade (--colonytest) | FALHOU | FAIL  torre de canhão acerta em área |
| Multiplayer Horda | NÃO RODOU | porta ocupada |
| Cidade em grupo | PASSOU | |

Avisos: [erros no log com saída 0, arquivos sem cobertura, versão não subiu]

Veredito: PASSOU | PASSOU COM AVISOS | FALHOU | NÃO AVALIADO
```

Veredito: **FALHOU** se qualquer teste falhou; **NÃO AVALIADO** se algum não rodou e
nenhum falhou; **PASSOU COM AVISOS** se todos passaram e há avisos; senão **PASSOU**.

Só grave o relatório em arquivo se o usuário pedir (`docs/qa/smoke-<AAAA-MM-DD>.md`).
Ao final, se houver falha, pergunte se deve investigar a causa.
