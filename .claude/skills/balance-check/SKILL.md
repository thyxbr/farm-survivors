---
name: balance-check
description: "Confere o balanceamento do Ecos de Valdoria a partir dos dados reais do código: armas e itens por raridade, preços da loja, curva de XP, inimigos e loot, cartas e combos do Desafio da Horda, economia da Defesa da Cidade e receitas. Use quando pedirem para checar balanceamento, achar item quebrado, outlier, estratégia dominante, curva de progressão ou economia."
argument-hint: "[combate | itens | loot | progressao | horda | cidade | comida | caminho/do/arquivo.gd]"
license: MIT
metadata:
  adapted-from: https://github.com/Donchitos/Claude-Code-Game-Studios (.claude/skills/balance-check)
  version: "1.0.0"
---

# Balance Check (Ecos de Valdoria)

Análise de balanceamento feita sobre os **valores que o jogo realmente usa**, não sobre
um documento de design. Não altera nada sem o usuário pedir.

## Regra principal: sem dado, sem veredito

Antes de qualquer relatório, liste cada fonte que a análise precisa e marque `ENCONTRADA`
ou `AUSENTE`. Uma seção sem dado é **`NÃO AVALIADO — SEM DADOS`**: não estime, não
preencha pelo que "jogos assim costumam ter". Um "tudo certo" sobre dado que não foi lido
é o erro que esta skill existe para evitar.

O projeto **não tem documento de design com metas numéricas**. Então um valor só é
"fora da meta" se o usuário disser a meta, ou se `docs/design/` (escrito pela skill
`reverse-document`) declarar uma. Sem meta, a análise é **relativa**: dominância entre
opções do mesmo nível, saltos na curva, itens que nunca valem a pena, loops de ouro.
Diga sempre qual dos dois tipos de julgamento foi feito.

## Fase 1: Domínio

Pelo argumento (se não houver, pergunte):

| Domínio | O que olhar | Fonte |
|---|---|---|
| `combate` | dano por classe (espada/cajado/arco) por raridade, escala com FOR/INT/AGI, crítico, roubo de vida, magias | `ITEMS`, `ABILITIES` em `scripts/autoload/item_db.gd`; `damage_mult()`, `weapon_damage()`, `melee_damage()`, `spell_power()`, `crit_chance()`, `max_hp()` em `scripts/autoload/game.gd`; dano recebido em `take_damage()` de `scripts/player/player.gd` |
| `itens` | preço x poder por raridade, itens da loja (`SHOP_STOCK`), bônus de `stats`, preço de venda | `scripts/autoload/item_db.gd` (inclui `power_score()`, a nota de poder que o jogo usa); `sell()` em `scripts/autoload/game.gd` |
| `loot` | chance de drop por inimigo, ouro por inimigo, raridade esperada por região | `TYPES[*].loot` e `gold` em `scripts/enemies/enemy.gd`; `drop_loot()` |
| `progressao` | `xp_to_next()` = `int(60 * level^1.55)`, XP por inimigo e por missão, 3 pontos por nível, magias por nível | `scripts/autoload/game.gd`, `QUESTS`/`ABILITIES` em `item_db.gd`, `TYPES[*].xp` |
| `horda` | `xp_needed()` da partida, armas automáticas, passivas, bênçãos, combos em grupo, eventos | `scripts/survival/survival_mode.gd`, `upgrades.gd`, `horde_events.gd`, `auto_weapons.gd` |
| `cidade` | ouro/comida por dia, impostos x crescimento, custo x HP das construções, torres (dano/alcance/cadência), chefe a cada 5 noites | `scripts/colony/colony_data.gd`, `colony.gd`, `soldier.gd` |
| `comida` | colheitas, receitas, buffs e recarga de comer | `CROPS`/`RECIPES` em `item_db.gd`; `EAT_COOLDOWN` em `game.gd`; `scripts/farm/` |

Caminho de arquivo como argumento: leia o arquivo e deduza o domínio.

## Fase 2: Extrair os números

As tabelas são constantes GDScript. Para tê-las prontas em JSON, rode (em uma pasta nova,
faça antes `--import`):

```bash
"C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path . res://.claude/skills/balance-check/dump_data.tscn > "$TEMP/balance.log" 2>&1
grep '^BALANCE_JSON ' "$TEMP/balance.log" | cut -c14- > "$TEMP/balance.json"
```

O JSON tem as constantes de `item_db`, `enemy`, `upgrades`, `horde_events`,
`colony_data` e `game`. Fórmulas (dano, XP, escala de atributo, dificuldade da horda) não
são constantes: leia as funções no código e cite `arquivo:linha`.

Faça as contas com um script Python no scratchpad lendo esse JSON (`python -I script.py
"$TEMP/balance.json"`), não de cabeça. Mostre as tabelas que saírem dele.

## Fase 3: Análise

Toda conta cita de onde veio o valor. Checagens por domínio:

- **Combate:** dano base por classe em cada raridade; dano efetivo com os `stats` do
  item; uma arma estritamente melhor que outra da mesma raridade e preço próximo;
  saltos entre raridades (ex.: Épico → Lendário) muito maiores que os anteriores;
  combinações de `leech` + `hp` + `vit` que tornem o jogador praticamente imortal.
- **Itens / economia:** razão preço ÷ poder por raridade; itens da loja que nunca
  compensam frente ao drop; preço de venda x custo, procurando compra-e-venda com lucro.
- **Loot:** chance esperada de cada raridade por inimigo e por região (campos, floresta,
  ruínas); quantos abates até o primeiro item Raro/Épico; itens que não caem de nada.
- **Progressão:** tabela nível × XP necessário × abates/missões necessários; trechos
  mortos (muitos abates sem nada novo) e picos (magia nova + item novo no mesmo nível);
  se o nível esperado ao chegar no Rei Goblin bate com a dificuldade dele.
- **Horda:** curva de `xp_needed()` × XP que cai por rodada; arma/passiva/bênção que
  domina todas as outras; combos em grupo fortes demais com 2+ jogadores; eventos
  (`SAW`, `EVENT_CHANCE`) que tornam rodadas impossíveis ou triviais.
- **Cidade:** ouro e comida por dia x custo das construções ao longo dos dias; imposto
  alto compensa sempre (`TAX` x `GROWTH`)?; torre com dano por ouro muito acima das
  outras; reparo/demolição (`REFUND`, `REPAIR_RATIO`) permitindo lucro; valores de
  cooperação (`COOP_*`) por jogador.
- **Comida:** buff por custo de plantio e tempo de colheita; receita que domina as
  outras.

## Fase 4: Relatório

```
## Balance Check: [domínio]

### Fontes
| Fonte | Status |
|---|---|
| scripts/autoload/item_db.gd (ITEMS) | ENCONTRADA |
| metas de design | AUSENTE: análise relativa |

### Resumo: [NÃO AVALIADO / SAUDÁVEL / ATENÇÃO / PROBLEMAS CRÍTICOS]

### Outliers
| Item/valor | Comparado com | Valor | Problema |

### Estratégias dominantes
- [o quê, por que domina, com a conta]

### Progressão
[tabela nível × necessário × fonte de XP]

### Recomendações
| Prioridade | Problema | Ajuste sugerido (arquivo:linha, valor atual → novo) | Efeito esperado |
```

Resumo pelo pior achado: **PROBLEMAS CRÍTICOS** (uma opção domina todas, progressão
trava, loop de ouro sem saída) › **ATENÇÃO** (outliers ajustáveis) › **NÃO AVALIADO**
(faltou dado ou meta, diga qual) › **SAUDÁVEL**.

## Fase 5: Depois do relatório

Pergunte ao usuário:
- **Corrigir o problema mais prioritário agora**: ajuste o valor no `.gd`, rode de
  novo o dump e a análise para ver se não criou outro outlier, e rode o smoke test do
  modo afetado (skill `smoke-check`). Mudou um valor que o servidor também usa? Lembre
  que cliente e servidor precisam da mesma versão, então isso pede bump de
  `config/version` no `project.godot` antes do merge.
- **Salvar o relatório** em `docs/balanceamento/<dominio>-<AAAA-MM-DD>.md`.
- **Parar aqui.**

Trabalhe em worktree separada (`../godot-3d-<nome>`) se outra sessão estiver usando a
pasta principal.
